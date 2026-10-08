/// Tags drawn: a small quiet chip on each, the `#` kept. Ports `src/app/editor/tags.ts`. What a tag is is
/// `lib/core/tags.dart`, which a query reads too; here is only where one is drawn. Nothing inside code, an
/// address, front matter, HTML, a comment or maths is a tag, which is the parser's to say.
///
/// What differs: the chip's `padding: 0 0.3em` is a gap either side of the mark (`inline_box.dart`), and its
/// ground a painted layer; so the caret just before a tag stands inside the chip's edge where the page has it
/// either side of the padding by which way it leans. `white-space: nowrap` is not kept: a tag has no space in it,
/// and breaks where a word would.
library;

import '../../core/blanks_syntax.dart';
import '../../core/tags.dart';
import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../marks/run_paint.dart';
import '../syntax/syntax.dart';
import '../view/lines.dart';
import '../view/syntax_tree.dart';
import 'inline_box.dart';

final Decoration _chip = Decoration.mark(className: 'cm-tag');

/// `padding: 0 0.3em` of a chip at `font-size: 0.92em`, in the line's own ems.
const double _pad = 0.3 * 0.92;
final Decoration _padBefore = Decoration.widget(widget: const GapWidget(em: _pad), side: -1);
final Decoration _padAfter = Decoration.widget(widget: const GapWidget(em: _pad), side: 1);

DecorationSet _decorate(EditorViewLike view) {
  final found = <Range<Decoration>>[];
  final tree = syntaxTree(view.state);
  // Nothing inside code, an address, front matter, HTML, a comment or maths is a tag.
  forEachVisibleLine(view, (line) {
    // A `#word` inside a blank's question is not a chip: the question reads as one quiet phrase.
    final blanks = line.text.contains('{?') ? blankMatches(line.text, line.from) : const <Blank>[];
    for (final tag in tagsIn(line.text, line.from)) {
      if (inQuietText(tree, tag.from) || blanks.any((b) => tag.from > b.from && tag.from < b.to)) continue;
      found
        ..add(_padBefore.range(tag.from))
        ..add(_chip.range(tag.from, tag.to))
        ..add(_padAfter.range(tag.to));
    }
  });
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

final Extension _tags = Extension.list(<Extension>[ViewPlugin.define<_Tags>(_Tags.new, decorations: (value) => value.decorations), baseTheme(_theme)]);

/// `#tags` drawn as small chips.
Extension tags() => _tags;
