import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'line_height.dart';

/// Text whose lines are exactly as tall as its style says, where the engine makes each a whole pixel.
///
/// A page keeps a line's height to the fraction: `line-height: normal` on a 16.26px title is 51 device pixels on a
/// phone at 2.625 (19.43px), and `1.45` on a 19.62px paragraph is 28.45px. Flutter's paragraph rounds every line to a
/// whole logical pixel (19 and 28), so a row of two lines stands a pixel short of the page's and a list of twelve
/// rows a dozen. This lays [child] out as it is, takes the page's height for its box (the lines counted, times the
/// style's own `height × fontSize`), and paints each line where the page has it: the first half the difference
/// down, each one after by the whole difference more.
///
/// [child] is one `Text` or `RichText` in one size (its lines all one height); anything else is passed through as
/// it is. [lineHeight] is the exact line, in logical pixels: `style.height! * style.fontSize!` ([ExactLines.of]).
///
/// [baseline] is where the page has the first line's baseline under the box's top, for a line of `line-height:
/// normal` ([normalLineBox]); left out, the words are centred in their line as an explicit line height centres them.
class ExactLines extends SingleChildRenderObjectWidget {
  const ExactLines({super.key, required this.lineHeight, this.baseline, required Widget super.child});

  /// [text] with the line its own style gives it. A style with no height or size of its own is left as it is.
  /// [normal] says the style's line is `line-height: normal` (what `Tokens.textAt` gives with no height asked for),
  /// whose baseline the page puts on a device pixel of its own; [dpr] is the ratio it is rounded at
  /// (`context.tokens.css.lineDpr`).
  static Widget of(Text text, {bool normal = false, double dpr = 1}) {
    final style = text.style;
    final size = style?.fontSize, height = style?.height;
    if (style == null || size == null || height == null || height <= 0) return text;
    if (normal) {
      final line = normalLineBox(style, dpr: dpr);
      // At a ratio of 1 the page's line is whole pixels, the engine's line is the same line, and the words stay
      // where the engine centres them (within a tenth of a pixel of the page's baseline).
      return ExactLines(lineHeight: line.height, baseline: dpr == 1 ? null : line.baseline, child: text);
    }
    return ExactLines(lineHeight: height * size, child: text);
  }

  final double lineHeight;
  final double? baseline;

  @override
  RenderExactLines createRenderObject(BuildContext context) => RenderExactLines(lineHeight: lineHeight, baseline: baseline);

  @override
  void updateRenderObject(BuildContext context, RenderExactLines renderObject) => renderObject
    ..lineHeight = lineHeight
    ..baseline = baseline;
}

class RenderExactLines extends RenderProxyBox {
  RenderExactLines({required double lineHeight, double? baseline}) : _lineHeight = lineHeight, _baseline = baseline;

  double? _baseline;
  double? get baseline => _baseline;
  set baseline(double? value) {
    if (value == _baseline) return;
    _baseline = value;
    markNeedsLayout();
  }

  /// How far the first line is moved down from where the engine drew it.
  double _first = 0;

  double _lineHeight;
  double get lineHeight => _lineHeight;
  set lineHeight(double value) {
    if (value == _lineHeight) return;
    _lineHeight = value;
    markNeedsLayout();
  }

  /// The engine's line, and how many of them the child came out as.
  double _drawn = 0;
  int _lines = 0;

  /// How far each line is moved down from the one before, and the first from the top.
  double get _slip => _lineHeight - _drawn;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    _drawn = _lineHeight.roundToDouble();
    _lines = child is RenderParagraph && _drawn > 0 ? (child.size.height / _drawn).round() : 0;
    // Only a paragraph whose lines are all the rounded line: anything else (a taller run, a widget in the text)
    // keeps the engine's own box.
    if (_lines <= 0 || (child.size.height - _lines * _drawn).abs() > 0.01) {
      _lines = 0;
      size = constraints.constrain(child.size);
      return;
    }
    size = constraints.constrain(Size(child.size.width, _lines * _lineHeight));
    // Centred in the taller or shorter line, as the engine centred it in its own; or on the page's own baseline.
    _first = _slip / 2;
    final wanted = _baseline;
    if (wanted != null) {
      final drawn = child.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true);
      if (drawn != null) _first = wanted - drawn;
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    final dry = child.getDryLayout(constraints);
    final drawn = _lineHeight.roundToDouble();
    final lines = drawn > 0 ? (dry.height / drawn).round() : 0;
    if (lines <= 0 || (dry.height - lines * drawn).abs() > 0.01) return constraints.constrain(dry);
    return constraints.constrain(Size(dry.width, lines * _lineHeight));
  }

  double _scaled(double childHeight) {
    final drawn = _lineHeight.roundToDouble();
    final lines = drawn > 0 ? (childHeight / drawn).round() : 0;
    if (lines <= 0 || (childHeight - lines * drawn).abs() > 0.01) return childHeight;
    return lines * _lineHeight;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _scaled(super.computeMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) => _scaled(super.computeMaxIntrinsicHeight(width));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final at = super.computeDistanceToActualBaseline(baseline);
    return at == null || _lines == 0 ? at : at + _first;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_lines == 0 || (_slip == 0 && _first == 0)) {
      context.paintChild(child, offset);
      return;
    }
    if (_lines == 1) {
      context.paintChild(child, offset + Offset(0, _first));
      return;
    }
    // Each line through a window of its own, moved to where the page has it. A little over each edge, for ink that
    // overhangs its line (a descender under a tight line), which the next line's window gives back.
    final width = size.width;
    for (var i = 0; i < _lines; i++) {
      final shift = _first + i * _slip;
      final band = Rect.fromLTWH(-width, i * _drawn + shift - (i == 0 ? _drawn : 0), 3 * width, _drawn + (i == 0 ? _drawn : 0) + (i == _lines - 1 ? _drawn : 0));
      context.pushClipRect(needsCompositing, offset, band, (context, offset) => context.paintChild(child, offset + Offset(0, shift)));
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null || _lines == 0) return super.hitTestChildren(result, position: position);
    final line = (position.dy / _lineHeight).floor().clamp(0, _lines - 1);
    final shift = _first + line * _slip;
    return result.addWithPaintOffset(offset: Offset(0, shift), position: position, hitTest: (result, at) => child.hitTest(result, position: at));
  }
}
