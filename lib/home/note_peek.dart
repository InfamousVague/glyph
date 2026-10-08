/// A note drawn small on its card: the first lines of it after its title, at a fraction of the note's size, clipped
/// to about six lines with the last one fading out where there is more.
///
/// Ports `src/app/notes/NotePeek.tsx`. On the web a card's preview is the note's own editor (CodeMirror, read-only,
/// in its formatted view and `peek` mode) given `peekMarkdown(body)`, so whatever a note draws its card draws. Here
/// it is the same: [MarkdownView] (lib/editor/markdown_view.dart), which draws the editor's own lines in the web's
/// `.peek` box. It was drawn by hand until the editor's view was ported; nothing of that is left but what follows.
///
/// What differs, until the pieces of the editor that draw them are ported (docs/STAGE4.md, pieces E to H):
/// - A `#tag`, an `@person` and a heading's count of its to-dos ("0 of 1") are the web's `tags.ts`,
///   `fieldChips.ts` and `headingProgress.ts`. Small stand-ins for the three are kept here ([_standIns]), drawn as
///   the hand-drawn preview drew them, so a card does not lose them in the meantime; they go when those files are
///   ported, and nothing else knows of them.
/// - A table is its rows as typed, a picture its line, a diagram and a query their fences; Ghost.md's own marks
///   (`==highlight==`, `||spoiler||`, the five effects) and a counter `[3/8]` keep their signs.
/// - Nothing is kept between draws and nothing waits to come near the screen: a card's lines cost well under a
///   millisecond here, where an editor cost the web 25 to 30.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/canvas_body.dart';
import '../core/note_text.dart';
import '../editor/editor.dart' hide Decoration;
import '../editor/looks/look.dart' show layoutUnit;
import '../editor/markdown_view.dart';
import '../editor/syntax/syntax.dart';
import '../editor/view/decoration.dart' as cm;
import '../editor/view/line.dart';
import '../editor/view/lines.dart';
import '../editor/view/syntax_tree.dart';

/// The preview of a note's [body] on its card. Draws nothing for a canvas (its body is JSON) or a note with nothing
/// under its title.
class NotePeek extends StatelessWidget {
  const NotePeek({super.key, required this.body, this.fill = false, this.dense = false});

  final String body;

  /// The card is stretched to its row's height: the preview takes the room there is, up to its six lines
  /// (NoteCard.module.css `.peek { flex: 1 }` under `max-block-size`).
  final bool fill;

  /// A dense card: `.item[data-dense] .peek { max-block-size: calc(1.6em * 4.2) }`.
  final bool dense;

  /// Whether [body] has anything to draw small.
  static bool has(String body) => !isCanvasBody(body) && peekMarkdown(body).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (isCanvasBody(body)) return const SizedBox.shrink();
    final markdown = peekMarkdown(body);
    if (markdown.isEmpty) return const SizedBox.shrink();
    return Padding(
      // `.peek { margin-block-start: var(--glacier-space-2) }`
      padding: EdgeInsets.only(top: context.tokens.space(2)),
      // `max-block-size: calc(1.6em * 6.2)`, and the fade over the last `1.8em`.
      child: MarkdownView(markdown: markdown, lines: dense ? 4.2 : 6.2, fill: fill, extensions: _standIns),
    );
  }
}

// ---- stand-ins for tags.ts, fieldChips.ts and headingProgress.ts ---------------------------------------------------

/// A tag and a person in a line of words, as the hand-drawn preview found them.
final RegExp _chip = RegExp(
  r'(?<![\w/#&])#([\p{L}\p{N}_][\p{L}\p{N}_/-]*)' // 1: a tag
  r'|(?<![\w@.])@(\p{L}[\p{L}\p{N}_.-]*)', // 2: a person
  unicode: true,
);

final RegExp _heading = RegExp(r'^ {0,3}(#{1,6})\s+(\S.*)$');

/// Maple Mono's ascent, descent and x-height, as shares of its size (hhea 1020 and 300; the x-height as the page
/// measures it, which puts a count 1.23px under a heading's baseline at the card's size).
const double _monoAscent = 1.02, _monoDescent = 0.3, _monoX = 0.563;

class _TagChip extends EditorWidget {
  const _TagChip(this.words);
  final String words;

  @override
  bool eq(_TagChip other) => other.words == words;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // `.cm-tag` (editor/tags.ts): the tag on a wash of its own ink, a touch under the words' size.
    final size = 0.92 * (EditorRunScope.maybeOf(context)?.look.fontSize ?? t.len('app-body'));
    final color = t.color('app-ink-2');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 0.3 * size),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(0.35 * size)),
      child: Text(words, softWrap: false, style: t.textAt(size, mono: true, color: color, height: 1.35), textScaler: TextScaler.noScaling),
    );
  }
}

class _PersonChip extends EditorWidget {
  const _PersonChip(this.name);
  final String name;

  @override
  bool eq(_PersonChip other) => other.name == name;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // `.cm-field[data-person]` (editor/fieldChips.ts): a person's initial in a purple ring, then the name, on a pill.
    final size = 0.92 * (EditorRunScope.maybeOf(context)?.look.fontSize ?? t.len('app-body'));
    final color = t.color('app-ink-2');
    final initial = 0.78 * size;
    return Container(
      padding: EdgeInsetsDirectional.only(start: 0.12 * size, end: 0.35 * size),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 1.25 * initial,
            height: 1.25 * initial,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.colorOf('color-mix(in oklch, var(--glacier-purple-9) 24%, transparent)'), shape: BoxShape.circle),
            child: Text(
              name.substring(0, 1).toUpperCase(),
              style: t.textAt(initial, mono: true, weight: 'bold', color: t.color('glacier-purple-11'), height: 1.25),
              textHeightBehavior: const TextHeightBehavior(leadingDistribution: TextLeadingDistribution.even),
              textScaler: TextScaler.noScaling,
            ),
          ),
          SizedBox(width: 0.28 * initial),
          Text(name, softWrap: false, style: t.textAt(size, mono: true, color: color, height: 1.35), textScaler: TextScaler.noScaling),
        ],
      ),
    );
  }
}

/// `.cm-headingCount` (editor/headingProgress.ts): how many of a heading's to-dos are done, after it.
class _CountChip extends EditorWidget {
  const _CountChip(this.done, this.total);
  final int done;
  final int total;

  @override
  bool eq(_CountChip other) => other.done == done && other.total == total;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final small = t.fontSize('sm');
    final em = EditorRunScope.maybeOf(context)?.line.base.fontSize ?? t.len('app-body');
    // The count's own inline box, as the page makes it: the face's ascent and descent to whole pixels, its 1.6
    // leading with the upper half floored.
    final ascent = (_monoAscent * small).roundToDouble(), descent = (_monoDescent * small).roundToDouble();
    final leading = layoutUnit(1.6 * small);
    final above = ascent + ((leading - ascent - descent) / 2).floorToDouble(), below = leading - above;
    // `vertical-align: middle`: the box's middle on the line's baseline plus half its x-height, so the count hangs
    // a little under the heading's baseline.
    final drop = (above - below) / 2 - layoutUnit(_monoX * em / 2);
    return Padding(
      // `margin-inline-start: 0.6em`
      padding: EdgeInsetsDirectional.only(start: 0.6 * small),
      child: _Extent(
        above: above - drop,
        below: below + drop,
        child: Text(
          done == total ? 'All $total done' : '$done of $total',
          softWrap: false,
          textScaler: TextScaler.noScaling,
          style: t
              .textAt(small, mono: true, weight: 'medium', color: t.color('app-ink-3'), height: 1, tracking: 0.02 * small)
              .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }
}

/// An inline box that reaches [above] and [below] its baseline, whatever its child's own line is: the child is
/// set with its baseline on this one's.
class _Extent extends SingleChildRenderObjectWidget {
  const _Extent({required this.above, required this.below, required Widget super.child});
  final double above;
  final double below;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderExtent(above, below);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderExtent)
      ..above = above
      ..below = below;
  }
}

class _RenderExtent extends RenderShiftedBox {
  _RenderExtent(this._above, this._below) : super(null);

  double _above;
  set above(double value) {
    if (value == _above) return;
    _above = value;
    markNeedsLayout();
  }

  double _below;
  set below(double value) {
    if (value == _below) return;
    _below = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final inner = child!;
    inner.layout(constraints.loosen(), parentUsesSize: true);
    final baseline = inner.getDistanceToBaseline(TextBaseline.alphabetic) ?? inner.size.height;
    (inner.parentData! as BoxParentData).offset = Offset(0, _above - baseline);
    size = constraints.constrain(Size(inner.size.width, _above + _below));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _above;
}

cm.DecorationSet _decorate(EditorViewLike view) {
  final state = view.state;
  final doc = state.doc;
  final tree = syntaxTree(state);
  final found = <Range<cm.Decoration>>[];
  // Progress under a heading: the boxes until the next heading of its level or higher.
  final counts = <int, ({int done, int total})>{};
  final open = <({int line, int level})>[];
  forEachDocLineOutsideFences(doc, (line) {
    final heading = _heading.firstMatch(line.text);
    if (heading != null) {
      final level = heading.group(1)!.length;
      while (open.isNotEmpty && open.last.level >= level) {
        open.removeLast();
      }
      open.add((line: line.number, level: level));
      return;
    }
    final lead = listLead(line.text);
    // A box with no words is not a to-do yet.
    if (lead == null || lead.done == null || line.text.substring(lead.wordsAt).trim().isEmpty) return;
    for (final each in open) {
      final was = counts[each.line] ?? (done: 0, total: 0);
      counts[each.line] = (done: was.done + (lead.done! ? 1 : 0), total: was.total + 1);
    }
  });
  forEachDocLineOutsideFences(doc, (line) {
    for (final m in _chip.allMatches(line.text)) {
      if (inQuietText(tree, line.from + m.start)) continue;
      final widget = m.group(1) != null ? _TagChip('#${m.group(1)}') : _PersonChip(m.group(2)!);
      found.add(cm.Decoration.replace(widget: widget).range(line.from + m.start, line.from + m.end));
    }
    final count = counts[line.number];
    if (count != null && count.total > 0) found.add(cm.Decoration.widget(widget: _CountChip(count.done, count.total), side: 1).range(line.to));
  });
  return cm.Decoration.set(found, true);
}

class _StandIns extends PluginValue {
  _StandIns(EditorViewLike view) : decorations = _decorate(view);

  cm.DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    if (update.docChanged) decorations = _decorate(update.view);
  }
}

final List<Extension> _standIns = <Extension>[ViewPlugin.define<_StandIns>(_StandIns.new, decorations: (value) => value.decorations)];
