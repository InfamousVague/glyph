/// The look of a plugin formatting whose look is a style (`plugins/marks.dart` [StyleLook]): the words between the
/// delimiters carry the plugin's CSS, as an inline mark, and the delimiters stay dimmed marks. Nothing is hidden
/// or moved. Ports `src/app/editor/formatLooks.ts`. Smoke looks are `wisp_format.dart`.
///
/// A view plugin over the visible lines, redrawn when the document, the viewport or the parse changes, and when
/// the caret moves if any look lifts at the caret (a redaction's bar, so the words under it can be edited).
///
/// A look inside a look is drawn inside it: a bar in a highlight is a bar on the wash. The one exception is a look
/// that hides its words (`clearAtCaret`, the bar): nothing inside it is drawn. [coveringLooks] names those looks
/// for the rest of the editor, so the links' piece leaves an address under a bar whole.
///
/// What differs:
/// - The page gives each stretch one `<span class="cm-formatLook" style="…">`. A look with a box (a wash, a bar)
///   is given here in up to three marks of the same class and style, the first and last letter apart
///   (`data-edge`), because a painter is told a run's rectangles and not where its mark ends: the ends are what is
///   rounded and spread, and the cut between pieces is square, as a wrapped `<span>`'s is. A reader of the runs
///   sees one stretch of one class, as on the page.
/// - `font-variant-caps: all-small-caps` (the shout). Neither of the app's faces has small capitals, so Blink
///   makes them: each letter its capital at 0.7 of the size, to a whole pixel (measured: five letters of 17.45px
///   Maple Mono are 36px wide, 7.2 each, which is 12px type). A text style here cannot say that, so each letter is
///   a mark of its own (`data-char`), spaced by the difference between the capital's width and its own and drawn
///   as the capital by a [LetterLayer].
/// - `filter: var(--app-ink-flat)` prints an emoji under a bar flat in the ink; here the bar is painted over the
///   words, which comes to the same picture.
/// - The CSS a look may use is what `StyleCss` reads (`run_paint.dart`).
library;

import 'package:flutter/painting.dart' hide Decoration;

import '../../plugins/marks.dart';
import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../syntax/tree.dart' show SyntaxNode;
import '../view/syntax_tree.dart';
import 'run_paint.dart';

/// A styled stretch: the words of one node, delimiters aside, and the CSS they carry.
class Styled {
  const Styled(this.from, this.to, this.css);
  final int from;
  final int to;
  final String css;

  @override
  bool operator ==(Object other) => other is Styled && other.from == from && other.to == to && other.css == css;

  @override
  int get hashCode => Object.hash(from, to, css);

  @override
  String toString() => 'Styled($from, $to, $css)';
}

/// A style look as the editor reads it: its delimiter's length and its CSS.
class StyleLookSpec {
  const StyleLookSpec({required this.length, required this.css, this.clearAtCaret = false, this.tint});
  final int length;
  final String css;
  final bool clearAtCaret;

  /// A name in brackets after the mark, as extra CSS for those words.
  final String? Function(String name)? tint;
}

/// `(green)` straight after a mark: the name a tint is asked about.
final RegExp _tint = RegExp(r'^\(([^)\n]+)\)');

/// The names of the nodes whose look hides its words (a redaction): what sits under one is not drawn, by anything.
final Facet<String, List<String>> coveringLooks = Facet.define<String, List<String>>();

/// Whether `node` sits inside a node whose look hides its words.
bool underCover(SyntaxNode node, List<String> covering) {
  if (covering.isEmpty) return false;
  for (var above = node.parent; above != null; above = above.parent) {
    if (covering.contains(above.name)) return true;
  }
  return false;
}

/// The styled stretches in `from`-`to`: the words of every node in `looks`, delimiters aside, and not a lifting
/// look's node the selection touches while `atCaret`. A look's words inside another look's are listed after it, in
/// document order; none inside a look that hides its words, unless it is lifted.
List<Styled> styledRanges(EditorState state, Map<String, StyleLookSpec> looks, int from, int to, [bool atCaret = false]) {
  final found = <Styled>[];
  syntaxTree(state).iterate(
    from: from,
    to: to,
    enter: (node) {
      final look = looks[node.name];
      if (look == null) return null;
      // Lifted: the words are drawn as they are, and so is any look inside them.
      if (look.clearAtCaret && atCaret && state.selection.ranges.any((r) => r.to >= node.from && r.from <= node.to)) return null;
      final a = node.from + look.length, b = node.to - look.length;
      if (b <= a) return false;
      // A name in brackets straight after the mark, where this mark takes one: `==the key==(green)`. A name it
      // does not know is left to mark_notes.dart, which reads the same brackets as a note.
      String? tint;
      if (look.tint != null) {
        final end = node.to + 40 < state.doc.length ? node.to + 40 : state.doc.length;
        final after = _tint.firstMatch(state.sliceDoc(node.to, end));
        if (after != null) tint = look.tint!(after.group(1) ?? '');
      }
      found.add(Styled(a, b, tint != null ? '${look.css}$tint' : look.css));
      // A look inside these words is drawn inside this one; under a bar, nothing is.
      return look.clearAtCaret ? false : null;
    },
  );
  return found;
}

/// The style looks of `formats`, by node name.
Map<String, StyleLookSpec> styleLooksOf(Iterable<GlyphFormat> formats) => <String, StyleLookSpec>{
  for (final format in formats)
    if (format.look case final StyleLook look) format.name: StyleLookSpec(length: format.delimiter.length, css: look.css, clearAtCaret: look.clearAtCaret, tint: format.tint),
};

final Map<String, Decoration> _marks = <String, Decoration>{};

Decoration _markFor(String css, [String? edge, String? char]) => _marks['$css\u0000$edge\u0000$char'] ??= Decoration.mark(
  className: 'cm-formatLook',
  attributes: <String, String>{'style': css, 'data-edge': ?edge, 'data-char': ?char},
);

int _firstUnit(String text) => text.length > 1 && (text.codeUnitAt(0) & 0xfc00) == 0xd800 ? 2 : 1;
int _lastUnit(String text) => text.length > 1 && (text.codeUnitAt(text.length - 1) & 0xfc00) == 0xdc00 ? 2 : 1;

/// The marks one styled stretch is drawn with (see the file's note on pieces).
Iterable<Range<Decoration>> _pieces(EditorState state, Styled styled) sync* {
  final css = StyleCss.parse(styled.css);
  final text = state.sliceDoc(styled.from, styled.to);
  if (css.smallCaps) {
    var at = 0, index = 0;
    final count = text.runes.length;
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final edge = count == 1 ? null : (index == 0 ? 'start' : (index == count - 1 ? 'end' : 'none'));
      yield _markFor(styled.css, edge, ch).range(styled.from + at, styled.from + at + ch.length);
      at += ch.length;
      index += 1;
    }
    return;
  }
  final boxed = css['background'] != null || css.shadow != null;
  final first = _firstUnit(text), last = _lastUnit(text);
  if (!boxed || text.length <= first) {
    yield _markFor(styled.css).range(styled.from, styled.to);
    return;
  }
  yield _markFor(styled.css, 'start').range(styled.from, styled.from + first);
  if (styled.to - last > styled.from + first) yield _markFor(styled.css, 'none').range(styled.from + first, styled.to - last);
  yield _markFor(styled.css, 'end').range(styled.to - last, styled.to);
}

DecorationSet _build(EditorViewLike view, Map<String, StyleLookSpec> looks) {
  final ranges = view.visibleRanges;
  if (ranges.isEmpty) return Decoration.none;
  final atCaret = view.state.facet(EditorViewLike.editable) && view.hasFocus;
  final found = <Range<Decoration>>[
    for (final styled in styledRanges(view.state, looks, ranges.first.from, ranges.last.to, atCaret)) ..._pieces(view.state, styled),
  ];
  return Decoration.set(found, true);
}

class _FormatLooks extends PluginValue {
  _FormatLooks(EditorViewLike view, this.looks, this.lifts) : decorations = _build(view, looks);

  final Map<String, StyleLookSpec> looks;
  final bool lifts;
  DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    final moved = lifts && (update.selectionSet || update.focusChanged);
    if (moved || update.docChanged || update.viewportChanged || !identical(syntaxTree(update.state), syntaxTree(update.startState))) {
      decorations = _build(update.view, looks);
    }
  }
}

// ---- the stylesheet ----------------------------------------------------------------------------------------------

/// A text style near enough to the one the look will resolve to, to measure a letter in.
TextStyle _measureStyle(Props p, LookEnv e, double size) => TextStyle(
  inherit: false,
  fontFamily: p.families.isEmpty ? null : p.families.first,
  fontFamilyFallback: p.families.length > 1 ? p.families.sublist(1) : null,
  fontSize: size,
  fontWeight: FontWeight.values[((p.weight / 100).round() - 1).clamp(0, 8)],
  fontStyle: p.italic ? FontStyle.italic : FontStyle.normal,
  fontVariations: <FontVariation>[FontVariation('wght', p.weight), if (p.optical) FontVariation('opsz', size)],
  fontFeatures: p.pageFeatures && e.t.typography.features.isNotEmpty ? e.t.typography.features : null,
);

double _widthOf(String text, TextStyle style) {
  final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Blink's made small capitals: 0.7 of the size, to a whole pixel.
double smallCapsSize(double size) => (size * 0.7).roundToDouble();

/// Whether Blink sets `ch` as a small capital under `all-small-caps`: a letter, either case.
bool _cased(String ch) => ch.toUpperCase() != ch.toLowerCase();

class _SmallCap extends LetterLayer {
  const _SmallCap(super.text, this.size);

  final double size;

  @override
  TextStyle styleOf(RunLook look) => look.style.copyWith(fontSize: size, letterSpacing: 0, fontVariations: <FontVariation>[FontVariation('wght', look.props.weight), if (look.props.optical) FontVariation('opsz', size)]);

  @override
  void drawLetter(Canvas canvas, LetterGlyph glyph, Offset at, Size box, RunLook look) => glyph.painter.paint(canvas, Offset.zero);
}

/// The text properties of a look's declarations, on the element that carries them.
void _dressText(Props p, LookEnv e, StyleCss css) {
  final size = css.fontSizeEm;
  if (size != null) p.sizeEm(size);
  if (css.italic) p.italic = true;
  final color = css['-webkit-text-fill-color'] ?? css['color'];
  if (color != null) p.color = e.t.colorOf(color, current: p.color);
  final weight = css['font-weight'];
  if (weight != null) {
    final named = RegExp(r'^var\(--([\w-]+)').firstMatch(weight);
    p.weight = named != null ? e.t.len(named.group(1)!) : (double.tryParse(weight) ?? (weight == 'bold' ? 700 : p.weight));
  }
  final spacing = css.letterSpacingEm;
  if (spacing != null) p.trackingEm(spacing);
}

/// The layers a look's declarations paint, on the element that carries them or on one inside it.
void _dressPaint(Props p, LookEnv e, StyleCss css, LookElement from, {required bool own}) {
  final em = p.fontSize;
  final edge = boxEdgeOf(from.attrs['data-edge']);
  final background = css['background'], shadow = css.shadow;
  if (background != null || shadow != null) {
    final ground = background == null ? null : e.t.colorOf(background, current: p.color);
    p.painter = MarkPaint.add(
      p.painter,
      BoxLayer(
        color: ground,
        radius: StyleCss.length(css['border-radius'], em) ?? 0,
        spread: shadow == null ? 0 : shadow.em * em,
        spreadColor: shadow == null ? null : e.t.colorOf(shadow.color, current: p.color),
        edge: edge,
        onTop: css.flat,
      ),
    );
  }
  final underline = css.underline;
  if (underline != null) {
    final said = css['text-decoration-color'];
    p.painter = MarkPaint.add(
      p.painter,
      UnderlineLayer(
        color: said == null ? null : e.t.colorOf(said, current: p.color),
        // Blink's own line where the look says neither: a tenth of an em under the baseline, a twentieth thick.
        offset: StyleCss.length(css['text-underline-offset'], em) ?? em * 0.1,
        thickness: StyleCss.length(underline.thickness, em) ?? em * 0.05,
        style: underline.style,
      ),
    );
  }
  if (!own || !css.smallCaps) return;
  final ch = from.attrs['data-char'];
  if (ch == null || !_cased(ch)) return;
  final small = smallCapsSize(em), capital = ch.toUpperCase();
  // The letter keeps its place in the paragraph and is made as wide as its small capital.
  p.trackingPx(p.tracking + _widthOf(capital, _measureStyle(p, e, small)) - _widthOf(ch, _measureStyle(p, e, em)));
  p.painter = MarkPaint.add(p.painter, _SmallCap(capital, small));
}

/// The elements with the class above the one being dressed, as `LookRule.when` met them: a rule for what is
/// inside a look (`.cm-formatLook *`) is told the look's element there, and reads it here, in the same order.
final List<LookElement> _above = <LookElement>[];

/// A mark's `style` attribute wins over every rule on the page.
const int _inline = 90;

final LookSheet _theme = LookSheet('editor/formatLooks.ts', <LookRule>[
  LookRule(
    'cm-formatLook',
    classes: _inline,
    (p, e) => _dressText(p, e, StyleCss.parse(p.element?.attrs['style'] ?? '')),
    box: (p, e) => _dressPaint(p, e, StyleCss.parse(p.element?.attrs['style'] ?? ''), p.element!, own: true),
  ),
  // What stands inside a look (another mark's letters, a tag) is drawn on the look's wash and over its line.
  LookRule.under(
    'cm-formatLook',
    null,
    classes: _inline,
    when: (element, context) {
      _above.add(element);
      return true;
    },
    box: (p, e) {
      if (_above.isEmpty) return;
      final from = _above.removeAt(0);
      _dressPaint(p, e, StyleCss.parse(from.attrs['style'] ?? ''), from, own: false);
    },
  ),
]);

final Extension _themed = baseTheme(_theme);

/// The style looks of `formats`, drawn.
Extension formatLooks(Iterable<GlyphFormat> formats) {
  final looks = styleLooksOf(formats);
  if (looks.isEmpty) return const Extension.list(<Extension>[]);
  final lifts = looks.values.any((look) => look.clearAtCaret);
  return Extension.list(<Extension>[
    for (final entry in looks.entries)
      if (entry.value.clearAtCaret) coveringLooks.of(entry.key),
    // The look's span sits inside the highlighter's, so it takes the size of the words it is on.
    Prec.highest(ViewPlugin.define<_FormatLooks>((view) => _FormatLooks(view, looks, lifts), decorations: (value) => value.decorations)),
    _themed,
  ]);
}
