/// Tags drawn: a small quiet chip on each, the `#` kept. Ports `src/app/editor/tags.ts`. What a tag is is
/// `lib/core/tags.dart`, which a query reads too; here is only where one is drawn. Nothing inside code, an
/// address, front matter, HTML, a comment or maths is a tag, which is the parser's to say.
///
/// What differs: the chip's `padding: 0 0.3em` is a gap either side of the mark (`inline_box.dart`), and its
/// ground a painted layer; so the caret just before a tag stands inside the chip's edge where the page has it
/// either side of the padding by which way it leans. `white-space: nowrap` is not kept: a tag has no space in it,
/// and breaks where a word would.
///
/// **A tap on a chip opens the tag's page** (the port's own, 2026-10-16; lib/notes/collection_screen.dart), where
/// whoever made the editor says how ([tagOpener]): the press is the chip's, as a note link's is (wiki_links.dart),
/// and the caret stays where it was; the arrow keys, or a tap beside the chip, put it inside to edit the tag. Only a
/// tag drawn as a chip answers, so a `#word` in code or a blank's question is words like any other.
library;

import '../../core/blanks_syntax.dart';
import '../../core/tags.dart';
import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../marks/run_paint.dart';
import '../syntax/syntax.dart';
import '../view/syntax_tree.dart';
import 'inline_box.dart';

final Decoration _chip = Decoration.mark(className: 'cm-tag');

/// What a tap on a tag's chip does: open its page, by its name (lower case, no `#`). Absent, a tap is the editor's.
final Facet<void Function(String tag), void Function(String tag)?> tagOpener =
    Facet.define<void Function(String tag), void Function(String tag)?>(combine: (values) => values.isEmpty ? null : values.first);

/// `padding: 0 0.3em` of a chip at `font-size: 0.92em`, in the line's own ems.
const double _pad = 0.3 * 0.92;
final Decoration _padBefore = Decoration.widget(widget: const GapWidget(em: _pad), side: -1);
final Decoration _padAfter = Decoration.widget(widget: const GapWidget(em: _pad), side: 1);

/// The tags on each line, counted from the line's start, kept for every line of a document (`LineFact`): the lines
/// on screen are not put to the pattern again on every letter.
final LineFact<List<Tag>> _tagged = LineFact<List<Tag>>((text) {
  if (!text.contains('#')) return null;
  final tags = tagsIn(text);
  return tags.isEmpty ? null : tags;
});

DecorationSet _decorate(EditorViewLike view) {
  final found = <Range<Decoration>>[];
  final doc = view.state.doc;
  final tree = syntaxTree(view.state);
  // Nothing inside code, an address, front matter, HTML, a comment or maths is a tag.
  for (final range in view.visibleRanges) {
    for (final line in _tagged.between(doc, doc.lineAt(range.from).number, doc.lineAt(range.to).number)) {
      // A `#word` inside a blank's question is not a chip: the question reads as one quiet phrase.
      final blanks = line.text.contains('{?') ? blankMatches(line.text, line.from) : const <Blank>[];
      for (final tag in line.fact) {
        final from = line.from + tag.from, to = line.from + tag.to;
        if (inQuietText(tree, from) || blanks.any((b) => from > b.from && from < b.to)) continue;
        found
          ..add(_padBefore.range(from))
          ..add(_chip.range(from, to))
          ..add(_padAfter.range(to));
      }
    }
  }
  return Decoration.set(found, true);
}

/// The chip's ground: its own ink, a tenth of it, whatever ink the words inside are in.
void _ground(Props p, LookEnv e) => p.painter = MarkPaint.add(p.painter, BoxLayer(color: inkShare(e.t.color('app-ink-2'), 0.09), radius: p.em(0.35), padStart: p.em(0.3), padEnd: p.em(0.3)));

final LookSheet _theme = LookSheet('editor/tags.ts', <LookRule>[
  // '.cm-tag': { padding: '0 0.3em', borderRadius: '0.35em',
  //   background: 'color-mix(in srgb, currentColor 9%, transparent)', color: 'var(--app-ink-2, inherit)',
  //   fontSize: '0.92em', whiteSpace: 'nowrap' }
  LookRule(
    'cm-tag',
    classes: 2,
    (p, e) {
      p
        ..color = e.t.color('app-ink-2')
        ..sizeEm(0.92);
    },
    box: _ground,
  ),
  // A tag on a list's line stands round the highlighter's own span, whose run it is that is painted: the chip is
  // drawn under that run.
  LookRule.under('cm-tag', null, classes: 2, box: _ground),
]);

class _Tags extends PluginValue {
  _Tags(EditorViewLike view) : decorations = _decorate(view);

  DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    if (update.docChanged || update.viewportChanged || !identical(syntaxTree(update.startState), syntaxTree(update.state))) decorations = _decorate(update.view);
  }
}

final ViewPlugin<_Tags> _tagsPlugin = ViewPlugin.define<_Tags>(
    _Tags.new,
    decorations: (value) => value.decorations,
    eventHandlers: EditorEventHandlers(
      mouseDown: (event, view) {
        final open = view.state.facet(tagOpener);
        if (open == null) return false;
        final pos = view.posAtCoords(event.position);
        if (pos == null) return false;
        // Only a tag drawn as a chip: one the decorations put a chip on, which leaves out code and the other quiet
        // places, and a blank's question.
        final chips = view.plugin(_tagsPlugin)?.decorations;
        if (chips == null) return false;
        String? hit;
        chips.between(pos, pos, (from, to, value) {
          if (identical(value, _chip) && pos >= from && pos <= to) {
            final line = view.state.doc.lineAt(from);
            for (final tag in tagsIn(line.text, line.from)) {
              if (tag.from == from) hit = tag.name;
            }
            return false;
          }
          return null;
        });
        final name = hit;
        if (name == null) return false;
        open(name);
        return true;
      },
    ),
  );

final Extension _tags = Extension.list(<Extension>[_tagsPlugin, baseTheme(_theme)]);

/// `#tags` drawn as small chips.
Extension tags() => _tags;
