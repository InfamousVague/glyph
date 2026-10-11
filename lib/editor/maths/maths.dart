/// Maths drawn as the formula it is. Ports `src/app/editor/mathsDrawn.ts` (the audit's Missing 2): `$x^2 + y$` in a
/// line as a formula, a raised 2 and all, and a `$$` block on lines of its own as a formula set in the middle of
/// the page.
///
/// The caret on a formula's line shows what was typed, to edit, as a heading's hashes and a definition's colon
/// come back there; a view with no caret (the Formatted view, the Academy's preview, a note not focused) draws
/// every one. A formula that cannot be read stays as it was typed, set as code and underlined with dots, with
/// what is wrong said on a long press. Where the maths is found is `core/maths.dart`, Pandoc's rule, so two
/// prices on a line stay prices; a `$` in code is code.
///
/// What differs:
/// - KaTeX is `flutter_math_fork` (`formula.dart`). There is nothing to fetch, so a formula is never shown as its
///   source while a library loads.
/// - The web's field reads every line of the note again on every change, every move of the caret and every focus.
///   Here the lines with a dollar sign in them are a fact kept with the document's tree (`LineFact`), read for
///   the lines a change made; a change builds the set from those lines alone, and a move of the caret builds
///   nothing unless it enters or leaves a line or a block that has maths.
/// - `title` (what a browser shows over a formula it could not draw) is a panel on a long press, the footnotes'
///   own (`view/text_panel.dart`).
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart' hide Decoration;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_math_fork/ast.dart' show SyntaxTree;
import 'package:flutter_math_fork/flutter_math.dart' show Math, MathOptions, RenderEqnArray;
import 'package:glacier/glacier.dart';

import '../../core/maths.dart';
import '../../sheet/css.dart' show CssLines;
import '../editor.dart';
import '../looks/look.dart';
import '../syntax/tree.dart' show SyntaxNode;
import '../view/blocks.dart' show ClassedBlockWidget;
import '../view/drawn_block.dart';
import '../view/editor_view.dart';
import '../view/extended.dart' show frontMatter;
import '../view/line.dart' show EditorRunScope;
import '../view/syntax_tree.dart';
import '../view/text_panel.dart';
import 'formula.dart';

/// A line that is `$$` and nothing else: the edge of a formula on lines of its own.
final RegExp _edge = RegExp(r'^\s*\$\$\s*$');

/// What a line with a dollar sign in it holds: an edge, or stretches of maths counted from the line's start.
class _Dollars {
  const _Dollars(this.edge, this.maths);

  final bool edge;
  final List<({int from, int to})> maths;
}

/// The lines that can have maths on them: read from each line's words alone, kept with the document's tree.
final LineFact<_Dollars> _dollars = LineFact<_Dollars>((text) {
  if (!text.contains(r'$')) return null;
  if (_edge.hasMatch(text)) return const _Dollars(true, <({int from, int to})>[]);
  final maths = mathsIn(text);
  return maths.isEmpty ? null : _Dollars(false, maths);
});

/// Code, where a dollar sign is a dollar sign: a fence, a code span, an indented block.
const Set<String> _code = <String>{'FencedCode', 'CodeBlock', 'InlineCode', 'CodeText'};

bool _inCode(EditorState state, int at) {
  for (SyntaxNode? node = syntaxTree(state).resolveInner(at, 1); node != null; node = node.parent) {
    if (_code.contains(node.name)) return true;
  }
  return false;
}

/// The panel a long press on a formula that could not be drawn opens, saying what is wrong.
const String mathsPanel = 'cm-mathsPanel';

/// A formula in place of its source.
class MathsWidget extends EditorWidget implements ClassedBlockWidget {
  const MathsWidget(this.tex, this.source, this.display, {this.opens = false, this.block = false, this.first = 0});

  /// The number of the formula's first numbered row, counted through the note from its top; 0 for a formula
  /// that numbers none.
  final int first;

  /// The formula, without its dollar signs.
  final String tex;

  /// What was typed, dollar signs and all: shown if the formula cannot be drawn.
  final String source;

  /// Set apart, in the middle of the page: a `$$` block, or `$$…$$` alone on its line.
  final bool display;

  /// Whether the note can be changed: a press opens the formula only then.
  final bool opens;

  /// A block of its own between the lines, where `display` alone is a block inside its line.
  final bool block;

  @override
  String get className => display ? 'cm-mathsBlock' : 'cm-mathsInline';

  /// The web's widget also holds where it is (`at`, for a press to put the caret there) and is a new widget
  /// when that moves, so every formula below a letter typed is drawn again for the letter. Here where it is is
  /// asked when it is pressed ([_placeOf]), and a formula that only moved is the formula it was.
  @override
  bool eq(MathsWidget other) => other.tex == tex && other.display == display && other.opens == opens && other.block == block && other.first == first && other.source == source;

  @override
  double get estimatedHeight => display ? 64 : -1;

  @override
  Widget build(BuildContext context) => DrawnMaths(tex: tex, source: source, display: display, opens: opens, block: block, first: first);

  /// `ignoreEvent(event) { return event.type !== 'mousedown' }`: a wide formula scrolled sideways is the
  /// formula's. Where the note can be changed the formula answers a press itself (`openOnPress`); where it
  /// cannot, the press is the view's own.
  @override
  bool takesPointer(PointerEvent event) => opens || event is! PointerDownEvent;
}

/// The face KaTeX's own box is in (`.katex { font: normal 1.21em KaTeX_Main; line-height: 1.2 }`), and the face
/// of a letter in a formula (`.mathnormal { font-family: KaTeX_Math; font-style: italic }`): how far each
/// reaches above and below its baseline, of its size. The faces' own `hhea` tables (KaTeX 0.16's, which
/// packages/flutter_math_fork carries: 903 and 272 of 1000 in KaTeX_Main-Regular, 717 and 218 in
/// KaTeX_Math-Italic), which is what a page's engine rounds to whole pixels for an inline box. The text engine
/// here would answer each with half the faces' line gap (90) added, and round another way at some sizes.
const FaceMetrics _katexMain = FaceMetrics(0.903, 0.272), _katexMath = FaceMetrics(0.717, 0.218);

/// What one inline box in `face` at `fontSize` with a line `lineHeight` high gives its line, above and below the
/// baseline, as Blink makes it: the arithmetic of `Look._box` (looks/look.dart), for a box the stylesheets here
/// have no class for. A formula is never shorter than the boxes it is in, however small it is: KaTeX's own
/// (`.katex`, a line of 1.2 in KaTeX_Main), and in a line of the note the span round it (`.cm-mathsInline`, 1.05
/// of the words' size, whose line is the words' own line grown with it: a line with a formula in it is that much
/// taller on the page).
///
/// [metrics] are the face's ascent and descent where they are known otherwise than by asking the text engine,
/// which answers each with half the face's line gap added. The app's own faces have no gap; KaTeX's have one.
({double above, double below}) _inlineBox(LookEnv? env, TextStyle? face, double fontSize, double lineHeight, {FaceMetrics? metrics}) {
  metrics ??= FaceMetrics.of(face!);
  final ratio = env != null && env.t.css.lineDpr > 0 ? env.t.css.lineDpr : 1.0;
  if (ratio == 1) {
    final ascent = (metrics.ascent * fontSize).roundToDouble(), descent = (metrics.descent * fontSize).roundToDouble();
    final leading = lineBoxHeight(lineHeight, fontSize);
    final above = ascent + ((leading - (ascent + descent)) / 2).floorToDouble();
    return (above: above, below: leading - above);
  }
  final exact = metrics.descent * fontSize * ratio;
  var up = (metrics.ascent * fontSize * ratio).roundToDouble(), down = exact.roundToDouble();
  if (down < exact - 1e-4) {
    down += 1;
    up -= 1;
  }
  final leading = lineBoxHeight(lineHeight, fontSize * ratio);
  final above = up + ((leading - (up + down)) / 2).floorToDouble();
  return (above: above / ratio, below: (leading - above) / ratio);
}

/// The formula as a widget: drawn, or its source where it cannot be.
class DrawnMaths extends StatefulWidget {
  const DrawnMaths({super.key, required this.tex, required this.source, required this.display, this.opens = false, this.block = false, this.first = 0});

  final String tex, source;
  final bool display, opens, block;

  /// The number of the formula's first numbered row ([MathsWidget.first]); 0 where nobody counted, and then
  /// its rows are numbered from one.
  final int first;

  @override
  State<DrawnMaths> createState() => _DrawnMathsState();
}

class _DrawnMathsState extends State<DrawnMaths> {
  /// The reading this place on screen draws: its own while it is here.
  late Formula _formula = takeFormula(widget.tex, widget.display);

  /// The numbers this place draws, each read once.
  final Map<int, SyntaxTree> _numbers = <int, SyntaxTree>{};

  String get tex => widget.tex;
  String get source => widget.source;
  bool get display => widget.display;
  bool get opens => widget.opens;
  bool get block => widget.block;

  @override
  void didUpdateWidget(DrawnMaths oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tex != widget.tex || oldWidget.display != widget.display) {
      releaseFormula(_formula);
      _formula = takeFormula(widget.tex, widget.display);
    }
  }

  @override
  void dispose() {
    releaseFormula(_formula);
    super.dispose();
  }

  /// Where a press on the formula under `position` puts the caret, to edit it: the start of a formula in a
  /// line, the end of a block's first `$$` line (mathsDrawn.ts's `at`).
  static int? _placeOf(EditorView view, Offset position) {
    final pos = view.posAtCoords(position, precise: false);
    if (pos == null) return null;
    var at = pos;
    drawnMathsIn(view.state).between(pos, pos, (from, to, value) {
      final widget = value.widget;
      if (widget is! MathsWidget) return null;
      at = widget.block ? view.state.doc.lineAt(from).to : from;
      return false;
    });
    return at;
  }

  @override
  Widget build(BuildContext context) {
    final view = EditorViewScope.maybeOf(context);
    final env = view is EditorView ? view.look?.env : null;
    final run = block ? null : EditorRunScope.maybeOf(context)?.look;
    final t = context.tokens;
    // The em the formula's box is set in: its line's, or the note's for a block between lines.
    final em = run?.fontSize ?? env?.body ?? DefaultTextStyle.of(context).style.fontSize ?? 16;
    final ink = run?.color ?? env?.ink ?? t.color('glacier-text');
    final formula = _formula;
    final tree = formula.tree;
    Widget child;
    if (tree == null) {
      // '.cm-mathsInline:not([data-drawn])': { fontFamily: 'var(--glacier-font-mono)', fontSize: '0.92em',
      //   whiteSpace: 'pre-wrap', color: 'var(--app-ink-2, var(--glacier-text))' }
      // '[data-failed]': { textDecoration: 'underline dotted', textUnderlineOffset: '0.25em' }
      // Its lines are the note's own leading at its own size (`.cm-scroller { line-height: 1.6 }`, which a
      // number inherits as a number): three lines of a block that could not be read are 77.06 px at 16.05, where
      // the face's own lines would be 63.
      // The dots are drawn here ([DottedUnderline]), as the page's engine draws them: the text engine's own are
      // hairs close under the letters.
      final style = t.textAt(em * 0.92, mono: true, color: t.color('app-ink-2'), height: run?.props.lineHeight ?? 1.6);
      child = CssLines(
        line: lineBoxHeight(style.height!, style.fontSize!),
        child: DottedUnderline(
          fontSize: style.fontSize!,
          color: t.color('app-ink-2'),
          child: Text(source, style: style, textAlign: display ? TextAlign.center : TextAlign.start, textScaler: TextScaler.noScaling),
        ),
      );
      if (view is EditorView) {
        child = GestureDetector(
          onLongPressStart: (details) {
            final at = _placeOf(view, details.globalPosition);
            if (at != null) showTextPanel(view, at, 'This formula could not be drawn: ${formula.failed}', className: mathsPanel, label: 'Formula');
          },
          child: child,
        );
      }
    } else {
      // '.cm-mathsInline': { fontSize: '1.05em' }, '.cm-mathsInline .katex': { fontSize: '1em' }: in a line, a
      // touch larger than the words, as KaTeX's type runs small beside a sans face. Set apart, KaTeX's own 1.21em.
      final size = em * (display ? 1.21 : 1.05);
      var box = _inlineBox(env, null, size, 1.2, metrics: _katexMain);
      if (display && formula.letterInLine) {
        // A letter in the formula's own line is in another face, whose box of the same leading stands a little
        // off KaTeX_Main's: the line is as tall as the two together (27.33 px for `x` at 21.12, not 25.33).
        final slanted = _inlineBox(env, null, size, 1.2, metrics: _katexMath);
        box = (above: slanted.above > box.above ? slanted.above : box.above, below: slanted.below > box.below ? slanted.below : box.below);
      }
      if (!display && run != null) {
        final span = _inlineBox(env, run.style, size, run.props.lineHeight);
        box = (above: span.above > box.above ? span.above : box.above, below: span.below > box.below ? span.below : box.below);
      }
      // Set apart, a formula is one piece that scrolls sideways if it is wider than the page; in a line it is
      // broken where it may be if it will not fit, as its pieces wrap on the page.
      final options = optionsFor(display: display, size: size, color: ink);
      // What stands at the right of each row of `align`, `gather`, `equation` and `alignat`: the row's own
      // `\tag`, or the next equation number.
      final rowOf = <int>[];
      final rowTags = <Widget>[];
      final tags = formula.rowTags, numbered = formula.rowNumbered;
      if (display && tags != null && numbered != null && formula.tag == null) {
        var number = widget.first > 0 ? widget.first : 1;
        for (var row = 0; row < tags.length; row++) {
          if (tags[row] != null) {
            rowOf.add(row);
            rowTags.add(Math(ast: tags[row], options: options));
          } else if (numbered[row]) {
            rowOf.add(row);
            rowTags.add(Math(ast: _numbers[number] ??= numberTag(number), options: options));
            number++;
          }
        }
      }
      child = display || formula.parts.length < 2
          ? _MathsLine(
              above: box.above,
              below: box.below,
              // '.katex-display > .katex > .katex-html > .tag { position: absolute; right: 0 }': a formula's
              // `\tag` at the right of its line, on the formula's baseline.
              tagged: formula.tag != null,
              // And the numbers and tags of an environment's rows, each on its row's line.
              rows: rowOf.isEmpty ? null : rowOf,
              children: <Widget>[Math(ast: tree, options: options), if (formula.tag != null) Math(ast: formula.tag, options: options), ...rowTags],
            )
          : _InlineMaths(formula: formula, options: options, above: box.above, below: box.below);
    }
    if (display) {
      // '.cm-mathsBlock': { display: 'block', padding: '0.4em var(--app-gutter, 1rem)', overflowX: 'auto',
      //   overflowY: 'hidden', textAlign: 'center', textIndent: '0' }; '.katex-display': { margin: '0' }
      final gutter = env?.gutter ?? t.len('app-gutter');
      // The formula itself, named before `child` is the box round it: the builder below runs later.
      final formulaBox = child;
      child = LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
          final inner = room - 2 * gutter;
          return SizedBox(
            width: constraints.maxWidth.isFinite ? room : null,
            child: Padding(
              // The padding's em is the block's own type: 0.92 of the note's where the formula is its source.
              padding: EdgeInsets.symmetric(vertical: layoutUnitFloor((tree == null ? em * 0.92 : em) * 0.4), horizontal: gutter),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: inner > 0 ? inner : 0),
                  // A tagged formula takes the whole width itself, to put its tag at the far side of it.
                  child: formula.tag != null || formula.rowTags != null ? formulaBox : Center(widthFactor: 1, child: formulaBox),
                ),
              ),
            ),
          );
        },
      );
    }
    if (display && !block && run != null) {
      // `$$…$$` alone on its line is a block inside its line, and CodeMirror stands a buffer (an image with no
      // width, `.cm-widgetBuffer`) either side of a widget at a line's edge. A block parts what is round it: the
      // buffer before it is a line box of its own and the buffer after it another, each as tall as the line's
      // own leading makes an empty line. So the formula has an empty line above it and one below, in the line's
      // own box (measured: a line 131.625 high round a formula 75.781 high in lines of 27.922).
      child = _BufferLines(line: run.above + run.below, below: run.below, child: child);
    }
    child = Semantics(label: tex, child: ExcludeSemantics(child: child));
    if (opens && view is EditorView) {
      // `openOnPress`: a press puts the caret on the formula, and its source is there to edit.
      child = MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            final at = _placeOf(view, event.position);
            if (at != null) openOnPress(view, at);
          },
          child: child,
        ),
      );
    }
    return child;
  }
}

/// `text-decoration: underline dotted; text-underline-offset: 0.25em` under each line of a paragraph in one style,
/// as Chromium draws it (measured on the page at 16.05, 16.76 and 20.51 px, tool/blocks_reference.mjs; the
/// arithmetic is Blink's `TextDecorationOffset` and `GraphicsContext::DrawLine`):
///
/// - as thick as a tenth of the type, and never under a pixel (`text-decoration-thickness: auto`);
/// - its upper edge the offset below the baseline, the offset rounded to a whole pixel;
/// - drawn as a stroke along its middle, the middle put on a whole pixel (and half a pixel on where the dots
///   are an odd number of pixels wide);
/// - dots as wide as the thickness to the nearest whole pixel, as far apart again, from the words' left edge
///   to their right, each edge on a whole pixel.
///
/// The text engine's own dotted underline is round dots a hair thick at the face's own underline place.
class DottedUnderline extends SingleChildRenderObjectWidget {
  const DottedUnderline({super.key, required this.fontSize, required this.color, required super.child});

  final double fontSize;
  final Color color;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderDottedUnderline(fontSize, color);

  @override
  void updateRenderObject(BuildContext context, RenderDottedUnderline renderObject) => renderObject
    ..fontSize = fontSize
    ..color = color;
}

class RenderDottedUnderline extends RenderProxyBox {
  RenderDottedUnderline(this._fontSize, this._color);

  double _fontSize;
  Color _color;

  set fontSize(double value) {
    if (value == _fontSize) return;
    _fontSize = value;
    markNeedsPaint();
  }

  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  /// The first line's baseline under the box's top: asked while the box is laid out, which is when it may be.
  double _first = 0;

  @override
  void performLayout() {
    super.performLayout();
    _first = child?.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true) ?? 0;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final words = child;
    if (words is! RenderParagraph) return;
    final length = words.text.toPlainText().length;
    if (length == 0) return;
    // The words of each line, joined: a line's boxes share its top.
    final lines = <Rect>[];
    for (final box in words.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: length))) {
      final rect = box.toRect();
      if (lines.isNotEmpty && (lines.last.top - rect.top).abs() < 1) {
        lines[lines.length - 1] = lines.last.expandToInclude(rect);
      } else {
        lines.add(rect);
      }
    }
    if (lines.isEmpty) return;
    final thickness = _fontSize / 10 < 1 ? 1.0 : _fontSize / 10;
    final dot = thickness.roundToDouble() < 1 ? 1.0 : thickness.roundToDouble();
    final under = (0.25 * _fontSize).roundToDouble();
    final paint = Paint()..color = _color;
    final canvas = context.canvas;
    for (final line in lines) {
      final baseline = offset.dy + _first + (line.top - lines.first.top);
      var middle = (baseline + under + thickness / 2).roundToDouble();
      if (dot.toInt().isOdd) middle += 0.5;
      final from = (offset.dx + line.left).roundToDouble(), to = (offset.dx + line.right).roundToDouble();
      for (var x = from; x < to; x += 2 * dot) {
        canvas.drawRect(Rect.fromLTRB(x, middle - thickness / 2, x + dot < to ? x + dot : to, middle + thickness / 2), paint);
      }
    }
  }
}

/// A formula set apart inside its line, with the line box CodeMirror's buffer makes above it and the one below:
/// [line] of room either side of the child, and a baseline [below] above the foot, where the last line box's is,
/// so the line this stands in is exactly as tall as this.
class _BufferLines extends SingleChildRenderObjectWidget {
  const _BufferLines({required this.line, required this.below, required super.child});

  final double line, below;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBufferLines(line, below);

  @override
  void updateRenderObject(BuildContext context, _RenderBufferLines renderObject) => renderObject
    ..line = line
    ..below = below;
}

class _RenderBufferLines extends RenderShiftedBox {
  _RenderBufferLines(this._line, this._below) : super(null);

  double _line, _below;

  set line(double value) {
    if (value == _line) return;
    _line = value;
    markNeedsLayout();
  }

  set below(double value) {
    if (value == _below) return;
    _below = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicHeight(double width) => (child?.getMinIntrinsicHeight(width) ?? 0) + 2 * _line;

  @override
  double computeMaxIntrinsicHeight(double width) => (child?.getMaxIntrinsicHeight(width) ?? 0) + 2 * _line;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final inner = child?.getDryLayout(constraints.deflate(EdgeInsets.symmetric(vertical: _line))) ?? Size.zero;
    return constraints.constrain(Size(inner.width, inner.height + 2 * _line));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(0, 2 * _line));
      return;
    }
    child.layout(constraints.deflate(EdgeInsets.symmetric(vertical: _line)), parentUsesSize: true);
    (child.parentData! as BoxParentData).offset = Offset(0, _line);
    size = constraints.constrain(Size(child.size.width, child.size.height + 2 * _line));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => size.height - _below;

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) => getDryLayout(constraints).height - _below;
}

/// A formula in a line that can be broken: its pieces side by side where they fit the line, and row under row
/// where they do not, from the first frame. A piece is the formula up to and with a relation or an operator at
/// its top level, and keeps the space that followed it (the reader's `texBreak`, as packages/flutter_math_fork
/// has it: README 14), so the pieces in a row are the formula as it is set whole, to the pixel. It is never
/// drawn whole and then again in pieces: the reader keeps one drawing of each part of a formula, and the whole
/// and its pieces would share theirs.
class _InlineMaths extends StatelessWidget {
  const _InlineMaths({required this.formula, required this.options, required this.above, required this.below});

  final Formula formula;
  final MathOptions options;
  final double above, below;

  @override
  Widget build(BuildContext context) => _MathsLine(
    above: above,
    below: below,
    children: <Widget>[for (final part in formula.parts) Math(ast: part, options: options)],
  );
}

/// A formula on its line: no shorter above or below its baseline than the boxes it is in ([_inlineBox]), however
/// small it is; and, in pieces, broken onto another row of the same where the pieces do not fit the width.
class _MathsLine extends MultiChildRenderObjectWidget {
  const _MathsLine({required this.above, required this.below, this.tagged = false, this.rows, required super.children});

  /// For a formula whose rows have numbers or tags: the row each child after the first stands beside. Each is
  /// set at the right of the width given, on its row's baseline, the formula in the middle.
  final List<int>? rows;

  final double above, below;

  /// Whether the last child is the formula's tag: set at the right of the width given, the formula in the
  /// middle of it.
  final bool tagged;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMathsLine(above, below)
    ..tagged = tagged
    ..rows = rows;

  @override
  void updateRenderObject(BuildContext context, _RenderMathsLine renderObject) => renderObject
    ..above = above
    ..below = below
    ..tagged = tagged
    ..rows = rows;
}

class _MathsLineParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderMathsLine extends RenderBox with ContainerRenderObjectMixin<RenderBox, _MathsLineParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _MathsLineParentData> {
  _RenderMathsLine(this._above, this._below);

  double _above, _below;

  set above(double value) {
    if (value == _above) return;
    _above = value;
    markNeedsLayout();
  }

  set below(double value) {
    if (value == _below) return;
    _below = value;
    markNeedsLayout();
  }

  bool _tagged = false;
  set tagged(bool value) {
    if (value == _tagged) return;
    _tagged = value;
    markNeedsLayout();
  }

  List<int>? _rows;
  set rows(List<int>? value) {
    if (listEquals(value, _rows)) return;
    _rows = value;
    markNeedsLayout();
  }

  /// The first equation array inside `box`, which is the formula's own when the formula is one environment.
  static RenderEqnArray? _arrayIn(RenderObject box) {
    RenderEqnArray? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is RenderEqnArray) {
        found = child;
        return;
      }
      child.visitChildren(visit);
    }

    visit(box);
    return found;
  }

  /// The first row's baseline, from the top.
  double _up = 0;
  bool _clipped = false;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MathsLineParentData) child.parentData = _MathsLineParentData();
  }

  @override
  void performLayout() {
    final room = constraints.maxWidth;
    // Each piece as wide as it is: the rows are made of them.
    final pieces = <RenderBox>[], baselines = <double>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(const BoxConstraints(), parentUsesSize: true);
      pieces.add(child);
      baselines.add(child.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true) ?? child.size.height);
    }
    final rows = _rows;
    if (rows != null && pieces.length == rows.length + 1) {
      // '.katex-display > .katex > .katex-html > .tag { position: absolute; right: 0 }', the tag a column of
      // them: the formula in the middle of the width, each row's number at the right on the row's baseline.
      final formula = pieces[0];
      final array = _arrayIn(formula);
      // Where the array's top is in the formula's box: the boxes between them say where each put its child.
      var arrayTop = 0.0;
      for (RenderObject? box = array; box != null && !identical(box, formula); box = box.parent) {
        final data = box.parentData;
        if (data is BoxParentData) arrayTop += data.offset.dy;
      }
      final tops = <double>[
        for (var i = 0; i < rows.length; i++)
          // A row that is not there (the reader laid out fewer): on the formula's own baseline.
          (array != null && rows[i] < array.rowBaselines.length ? arrayTop + array.rowBaselines[rows[i]] : baselines[0]) - baselines[i + 1],
      ];
      // The formula's top in this box: low enough for the tallest number above it and for the line's own box.
      var top = _above - baselines[0];
      if (top < 0) top = 0;
      var bottom = formula.size.height;
      for (var i = 0; i < rows.length; i++) {
        if (-tops[i] > top) top = -tops[i];
        final end = tops[i] + pieces[i + 1].size.height;
        if (end > bottom) bottom = end;
      }
      if (baselines[0] + _below > bottom) bottom = baselines[0] + _below;
      final wide = constraints.minWidth > formula.size.width ? constraints.minWidth : formula.size.width;
      (formula.parentData! as _MathsLineParentData).offset = Offset((wide - formula.size.width) / 2, top);
      for (var i = 0; i < rows.length; i++) {
        final tag = pieces[i + 1];
        (tag.parentData! as _MathsLineParentData).offset = Offset(wide - tag.size.width, top + tops[i]);
      }
      _up = top + baselines[0];
      _clipped = false;
      size = constraints.constrain(Size(wide, top + bottom));
      return;
    }
    if (_tagged && pieces.length == 2) {
      // The formula in the middle of the width, its tag at the right, both on one baseline.
      final formula = pieces[0], tag = pieces[1];
      var up = _above, down = _below;
      for (var i = 0; i < 2; i++) {
        if (baselines[i] > up) up = baselines[i];
        if (pieces[i].size.height - baselines[i] > down) down = pieces[i].size.height - baselines[i];
      }
      final wide = constraints.minWidth > formula.size.width ? constraints.minWidth : formula.size.width;
      (formula.parentData! as _MathsLineParentData).offset = Offset((wide - formula.size.width) / 2, up - baselines[0]);
      (tag.parentData! as _MathsLineParentData).offset = Offset(wide - tag.size.width, up - baselines[1]);
      _up = up;
      _clipped = false;
      size = constraints.constrain(Size(wide, up + down));
      return;
    }
    var top = 0.0, width = 0.0;
    var first = true;
    for (var start = 0; start < pieces.length || first;) {
      var end = start, rowWidth = 0.0, up = _above, down = _below;
      while (end < pieces.length && (end == start || rowWidth + pieces[end].size.width <= room)) {
        final size = pieces[end].size, baseline = baselines[end];
        rowWidth += size.width;
        if (baseline > up) up = baseline;
        if (size.height - baseline > down) down = size.height - baseline;
        end++;
      }
      var x = 0.0;
      for (var i = start; i < end; i++) {
        (pieces[i].parentData! as _MathsLineParentData).offset = Offset(x, top + up - baselines[i]);
        x += pieces[i].size.width;
      }
      if (first) _up = up;
      first = false;
      if (rowWidth > width) width = rowWidth;
      top += up + down;
      start = end;
    }
    size = constraints.constrain(Size(width, top));
    _clipped = width > size.width + 0.01;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _up;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_clipped) {
      // One piece wider than the line by itself: what does not fit is not drawn over the page's edge.
      context.pushClipRect(needsCompositing, offset, Offset.zero & size, defaultPaint);
    } else {
      defaultPaint(context, offset);
    }
  }
}

/// The formulas drawn, and what a move of the caret is held against.
class _Maths {
  const _Maths(this.decorations, this.blocks, this.touched);

  final DecorationSet decorations;

  /// Every `$$` block, drawn or not: where each starts and ends.
  final List<int> blocks;

  /// Which lines and blocks with maths the selection is on, said as a string: a move that leaves it the same
  /// leaves the drawing the same.
  final String touched;

  static final _Maths none = _Maths(Decoration.none, const <int>[], '');
}

/// The lines with maths, and the blocks, that a selection range of a focused view is on.
String _touched(EditorState state, List<int> blocks) {
  if (!focused(state)) return '';
  final lines = _dollars.of(state.doc);
  if (lines.isEmpty) return '';
  final out = StringBuffer();
  for (final range in state.selection.ranges) {
    // The first line with a dollar sign that ends at or after the range's start.
    var low = 0, high = lines.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (lines[mid].to < range.from) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    for (var i = low; i < lines.length && lines[i].from <= range.to; i++) {
      out
        ..write(lines[i].number)
        ..write(',');
    }
    for (var i = 0; i < blocks.length; i += 2) {
      if (range.to >= blocks[i] && range.from <= blocks[i + 1]) {
        out
          ..write('b')
          ..write(blocks[i])
          ..write(',');
      }
    }
  }
  return out.toString();
}

final RegExp _numbering = RegExp(r'\\begin\{(?:align|gather|equation|alignat)\}');
final Map<String, int> _rowsNumbered = <String, int>{};

/// How many equation numbers the formula `tex`, set apart, takes: the rows of an unstarred `align`, `gather`,
/// `equation` or `alignat` that do not say otherwise. A formula with none of those words in it is not read to
/// find out, and one that has is read once for what it says, on screen or not.
int _numbersOf(String tex) {
  if (!tex.contains(r'\begin{')) return 0;
  final known = _rowsNumbered[tex];
  if (known != null) return known;
  if (_rowsNumbered.length > 400) _rowsNumbered.clear();
  return _rowsNumbered[tex] = _numbering.hasMatch(tex) ? formulaOf(tex, true).numbered : 0;
}

_Maths _build(EditorState state) {
  final doc = state.doc;
  final lines = _dollars.of(doc);
  if (lines.isEmpty) return _Maths.none;
  // The note's own front matter is its settings, never maths.
  final front = frontMatter(doc)?.to ?? 0;
  final editable = state.facet(EditorViewLike.editable);
  final ranges = <Range<Decoration>>[];
  final blocks = <int>[];
  // Equation numbers are counted through the note from its top, formula by formula, row by row. KaTeX counts
  // with a counter of the page's stylesheet (`.eqn-num::before { counter-increment: katexEqnNo }`), which
  // counts the numbered rows that are in the page as it stands; the web editor keeps only the lines near the
  // screen in the page, so by those two a formula's number there is one more than however many numbered rows
  // happen to be drawn above it (read from the stylesheet and the editor, not watched in the web app). Here a
  // number is the formula's place in the note and nothing else: a deliberate difference (docs/PARITY.md,
  // Differs 41).
  var numbers = 0;
  var skipTo = front;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.number <= skipTo) continue;
    // A formula on lines of its own, between two lines of `$$`.
    if (line.fact.edge && !_inCode(state, line.from)) {
      var end = -1;
      for (var j = i + 1; j < lines.length; j++) {
        if (lines[j].fact.edge) {
          end = j;
          break;
        }
      }
      if (end > -1 && lines[end].number > line.number + 1) {
        final last = lines[end];
        final tex = doc.sliceString(line.to + 1, last.from - 1);
        blocks
          ..add(line.from)
          ..add(last.to);
        if (tex.trim().isNotEmpty) {
          // Counted whether or not it is drawn: the caret in a formula does not renumber the ones below it.
          final takes = _numbersOf(tex), first = takes > 0 ? numbers + 1 : 0;
          numbers += takes;
          if (!caretIn(state, line.from, last.to)) {
            ranges.add(Decoration.replace(widget: MathsWidget(tex, doc.sliceString(line.from, last.to), true, opens: editable, block: true, first: first), block: true).range(line.from, last.to));
          }
        }
        skipTo = last.number;
        continue;
      }
    }
    if (line.fact.maths.isEmpty) continue;
    // The caret on the line: what was typed, to edit.
    final shown = caretIn(state, line.from, line.to);
    for (final maths in line.fact.maths) {
      final from = line.from + maths.from, to = line.from + maths.to;
      // A line the caret is on, with no `$$` on it, has nothing to count either.
      if (shown && !line.text.contains(r'$$')) break;
      if (_inCode(state, from)) continue;
      final source = line.text.substring(maths.from, maths.to);
      final wide = source.startsWith(r'$$');
      final tex = source.substring(wide ? 2 : 1, source.length - (wide ? 2 : 1));
      if (tex.trim().isEmpty) continue;
      // `$$…$$` alone on its line is set as a formula of its own; inside a sentence, it stays in the line.
      final alone = wide && line.text.trim() == source;
      final takes = alone ? _numbersOf(tex) : 0, first = takes > 0 ? numbers + 1 : 0;
      numbers += takes;
      if (shown) continue;
      ranges.add(Decoration.replace(widget: MathsWidget(tex, source, alone, opens: editable, first: first)).range(from, to));
    }
  }
  final set = ranges.isEmpty ? Decoration.none : Decoration.set(ranges);
  return _Maths(set, blocks, _touched(state, blocks));
}

final StateField<_Maths> _mathsField = StateField.define<_Maths>(
  create: _build,
  update: (value, tr) {
    if (tr.docChanged || tr.reconfigured || !identical(syntaxTreeOrNull(tr.state), syntaxTreeOrNull(tr.startState))) return _build(tr.state);
    if (tr.selection == null && !focusMoved(tr)) return value;
    // The caret moved, or the view was entered or left: nothing to draw again unless it is on other maths now.
    return _touched(tr.state, value.blocks) == value.touched ? value : _build(tr.state);
  },
  provide: (field) => EditorViewLike.decorations.from<_Maths>(field, (value) => value.decorations),
);

/// The formulas drawn in `state` now, for a test to ask.
DecorationSet drawnMathsIn(EditorState state) => state.fieldOrNull(_mathsField)?.decorations ?? Decoration.none;

final Extension _drawnMaths = Extension.list(<Extension>[trackFocus, _mathsField]);

/// Every formula in the note drawn, off the caret's line.
Extension drawnMaths() => _drawnMaths;
