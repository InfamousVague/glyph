/// The boxes this folder's inline widgets are made of, laid out the way the page lays out an inline box: words in
/// their content area, a line box of a said height round them, and a baseline that can be raised or lowered
/// (`vertical-align`). The editor's line asks an inline widget for its size and its baseline and sets it on the
/// line's own (lib/editor/view/line.dart), so a widget that says both as the page's box has them sits where the
/// page's does.
///
/// Not a port of a web file: what CSS does for `display: inline-block`, `line-height` and `vertical-align`.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../looks/look.dart';

/// A face's ascent and descent at a size, each a whole pixel, as Blink rounds them: the content area of an inline
/// box, which is what `getBoundingClientRect` answers for a span of words.
({double ascent, double descent}) contentArea(TextStyle style) {
  final face = FaceMetrics.of(style);
  final size = style.fontSize ?? 16;
  return (ascent: (face.ascent * size).roundToDouble(), descent: (face.descent * size).roundToDouble());
}

/// Words in a box as the page measures it. By default one line that is never broken (`white-space: nowrap`): as
/// wide as the words (or the room, past which they are cut with an ellipsis when [ellipsis]) and as tall as
/// [lineHeight] pixels, the words' content area in the middle of it; with no [lineHeight], as tall as the content
/// area alone, which is an inline span's own rectangle. With [maxLines] above one the words wrap in the room and
/// are cut after that many lines (`-webkit-line-clamp`), each line [lineHeight] tall to the sixty-fourth of a
/// pixel, where a paragraph of Flutter's own rounds each line to a whole one. Its baseline is the first line's.
class InlineWords extends LeafRenderObjectWidget {
  const InlineWords(this.text, {super.key, required this.style, this.lineHeight, this.ellipsis = false, this.opacity = 1, this.maxLines = 1});

  final String text;
  final TextStyle style;
  final double? lineHeight;
  final bool ellipsis;
  final double opacity;
  final int maxLines;

  @override
  RenderInlineWords createRenderObject(BuildContext context) => RenderInlineWords(text, style, lineHeight, ellipsis, opacity, maxLines);

  @override
  void updateRenderObject(BuildContext context, RenderInlineWords renderObject) => renderObject.set(text, style, lineHeight, ellipsis, opacity, maxLines);
}

class RenderInlineWords extends RenderBox {
  RenderInlineWords(this._text, this._style, this._lineHeight, this._ellipsis, this._opacity, this._maxLines);

  String _text;
  TextStyle _style;
  double? _lineHeight;
  bool _ellipsis;
  double _opacity;
  int _maxLines;
  TextPainter? _painter;
  List<LineMetrics> _lines = const <LineMetrics>[];
  double _top = 0;
  double _ascent = 0;
  double _each = 0;

  bool get _wraps => _maxLines > 1;

  void set(String text, TextStyle style, double? lineHeight, bool ellipsis, double opacity, int maxLines) {
    if (text == _text && style == _style && lineHeight == _lineHeight && ellipsis == _ellipsis && opacity == _opacity && maxLines == _maxLines) return;
    _text = text;
    _style = style;
    _lineHeight = lineHeight;
    _ellipsis = ellipsis;
    _opacity = opacity;
    _maxLines = maxLines;
    _painter?.dispose();
    _painter = null;
    markNeedsLayout();
  }

  TextPainter _laidOut(double maxWidth) {
    final ink = _opacity < 1 && _style.color != null ? _style.color!.withValues(alpha: _style.color!.a * _opacity) : _style.color;
    final painter = TextPainter(
      text: TextSpan(text: _text, style: _style.copyWith(height: kTextHeightNone, color: ink)),
      textDirection: TextDirection.ltr,
      maxLines: _maxLines,
      ellipsis: _ellipsis || _wraps ? '…' : null,
      textScaler: TextScaler.noScaling,
    );
    return painter..layout(maxWidth: _ellipsis || _wraps ? maxWidth : double.infinity);
  }

  Size _measure(BoxConstraints constraints, TextPainter painter, {bool keep = false}) {
    final area = contentArea(_style);
    final content = area.ascent + area.descent;
    final each = _lineHeight == null ? content : layoutUnitFloor(_lineHeight!);
    final lines = _wraps ? painter.computeLineMetrics() : const <LineMetrics>[];
    final count = _wraps ? (lines.isEmpty ? 1 : lines.length) : 1;
    if (keep) {
      _lines = lines;
      _each = each;
      _top = _lineHeight == null ? 0 : ((each - content) / 2).floorToDouble();
      _ascent = area.ascent;
    }
    // A block of wrapped words is as wide as its room; a line of them as wide as they are.
    final width = _wraps && constraints.hasBoundedWidth ? constraints.maxWidth : layoutUnit(painter.width);
    return constraints.constrain(Size(width, layoutUnit(each * count)));
  }

  @override
  void performLayout() {
    _painter?.dispose();
    final painter = _painter = _laidOut(constraints.maxWidth);
    size = _measure(constraints, painter, keep: true);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final painter = _laidOut(constraints.maxWidth);
    final size = _measure(constraints, painter);
    painter.dispose();
    return size;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _ellipsis || _wraps ? 0 : computeMaxIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) {
    final painter = _laidOut(double.infinity);
    // The longest line the words would make with all the room there is.
    final width = layoutUnitCeil(painter.maxIntrinsicWidth);
    painter.dispose();
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) => computeDryLayout(BoxConstraints(maxWidth: width.isFinite ? width : double.infinity)).height;

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  double get _baseline {
    final area = contentArea(_style);
    final content = area.ascent + area.descent;
    final each = _lineHeight == null ? content : layoutUnitFloor(_lineHeight!);
    return (_lineHeight == null ? 0 : ((each - content) / 2).floorToDouble()) + area.ascent;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _baseline;

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) => _baseline;

  /// The words' own content area in the box, for a test to hold against a span's rectangle on the page.
  Rect get contentRect {
    final area = contentArea(_style);
    return Rect.fromLTWH(0, _top, size.width, area.ascent + area.descent);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final painter = _painter;
    if (painter == null) return;
    final canvas = context.canvas;
    if (!_wraps || _lines.length <= 1) {
      painter.paint(canvas, offset + Offset(0, _top + _ascent - painter.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
      return;
    }
    // Each line of the paragraph set on a line box of this box's own height: the paragraph's lines are as tall
    // as the face, and this box's as tall as it was told.
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final top = line.baseline - line.ascent, bottom = line.baseline + line.descent;
      canvas
        ..save()
        ..translate(offset.dx, offset.dy + i * _each + _top + _ascent - line.baseline)
        ..clipRect(Rect.fromLTRB(-1, top - 1, size.width + 1, bottom + 1));
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _text
      ..textDirection = TextDirection.ltr;
  }

  @override
  void dispose() {
    _painter?.dispose();
    _painter = null;
    super.dispose();
  }
}

/// `vertical-align: <length>`: the box raised [by] pixels above the baseline it would sit on (lowered, below zero).
/// With [from], the baseline is that far down the box rather than the child's own: an inline-flex box whose first
/// item has no words takes its baseline from that item's foot.
class InlineRaise extends SingleChildRenderObjectWidget {
  const InlineRaise({super.key, required this.by, this.from, super.child});

  final double by;
  final double? from;

  @override
  RenderInlineRaise createRenderObject(BuildContext context) => RenderInlineRaise(by, from);

  @override
  void updateRenderObject(BuildContext context, RenderInlineRaise renderObject) {
    renderObject
      ..by = by
      ..from = from;
  }
}

class RenderInlineRaise extends RenderProxyBox {
  RenderInlineRaise(this._by, this._from);

  double _by;
  double? _from;

  set by(double value) {
    if (value == _by) return;
    _by = value;
    markNeedsLayout();
  }

  set from(double? value) {
    if (value == _from) return;
    _from = value;
    markNeedsLayout();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final own = _from ?? child?.getDistanceToActualBaseline(baseline);
    return own == null ? null : own + _by;
  }

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) {
    final own = _from ?? child?.getDryBaseline(constraints, baseline);
    return own == null ? null : own + _by;
  }
}
