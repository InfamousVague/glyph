/// What a blank's square is painted with (lib/editor/ai/blanks.dart): the dashed hairline of `.cm-blank`, which on
/// the page is one border round one `<span>`, whatever is inside it.
///
/// Not a port of a web file: what CSS does for `border: 1px dashed`, `border-radius`, `padding` and
/// `box-decoration-break: clone` on an inline box. The view paints a mark run by run and a widget by itself, and
/// no run knows where the square it is part of starts or ends on its line; so the square is drawn whole by one of
/// its own widgets. A [BlankPiece] stands at each end of the mark, inside it: each is the room the border and the
/// padding take there, and the one at the start paints the border, asking the line it is in where the square's
/// words are (`RenderEditorLine.rectsForRange`) and drawing one closed, round-cornered box for each visual line
/// the square is on.
///
/// One dash is three times the border's width and as far from the next, as Blink draws a thin dashed border.
library;

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../marks/run_paint.dart' show snapToDevice;
import '../view/line.dart' show RenderEditorLine, VisualLine;
import '../view/projection.dart' show SegmentKind;

/// A dash and the gap after it, in border widths.
const double _dash = 3;

/// A closed box with round corners, its border dashed: `box` is the border box.
void paintDashedBox(Canvas canvas, Rect box, double width, double radius, Color color) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;
  final inner = box.deflate(width / 2);
  final r = math.max(0.0, math.min(radius - width / 2, math.min(inner.width, inner.height) / 2));
  final path = Path()..addRRect(RRect.fromRectAndRadius(inner, Radius.circular(r)));
  for (final PathMetric metric in path.computeMetrics()) {
    for (var at = 0.0; at < metric.length; at += 2 * _dash * width) {
      canvas.drawPath(metric.extractPath(at, math.min(at + _dash * width, metric.length)), paint);
    }
  }
}

/// An inline box that asks nothing of its line's height: its child is set with its baseline on the line's and drawn
/// past the box, above and below. A border and a padding are drawn round an inline box without the line box
/// growing for them, and a square in a heading, whose leading is tight, is taller than its line.
class InlineFlat extends SingleChildRenderObjectWidget {
  const InlineFlat({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderInlineFlat();
}

class _RenderInlineFlat extends RenderShiftedBox {
  _RenderInlineFlat() : super(null);

  @override
  void performLayout() {
    final inner = child!;
    inner.layout(BoxConstraints(maxWidth: constraints.maxWidth), parentUsesSize: true);
    final baseline = inner.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true) ?? inner.size.height;
    (inner.parentData! as BoxParentData).offset = Offset(0, -baseline);
    size = constraints.constrain(Size(inner.size.width, 0));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => 0;

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) => 0;

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;
}

/// Which part of the square a [BlankPiece] is.
enum BlankEnd { start, middle, end }

/// A box inside the square that is not words: as tall as the square's border box, its baseline the words' own. At
/// an end it is as wide as the border and the padding there (after its child, at the square's end: the icon and
/// the closing brace), and the one at the start paints the square's border.
class BlankPiece extends SingleChildRenderObjectWidget {
  const BlankPiece({super.key, required this.end, required this.ascent, required this.descent, required this.color, required this.width, this.room = 0, this.radius = 0, this.drop = 0, super.child});

  final BlankEnd end;

  /// The content area of the square's words above and below their baseline.
  final double ascent, descent;

  /// The border's ink.
  final Color color;

  /// The border's width.
  final double width;

  /// At an end, the padding inside the border.
  final double room;

  /// `border-radius`.
  final double radius;

  /// How far under the baseline the child's foot sits (`vertical-align` below zero, on a box with no words).
  final double drop;

  @override
  RenderBlankPiece createRenderObject(BuildContext context) => RenderBlankPiece(end, ascent, descent, color, width, room, radius, drop);

  @override
  void updateRenderObject(BuildContext context, RenderBlankPiece renderObject) => renderObject.set(end, ascent, descent, color, width, room, radius, drop);
}

class RenderBlankPiece extends RenderShiftedBox {
  RenderBlankPiece(this._end, this._ascent, this._descent, this._color, this._width, this._room, this._radius, this._drop) : super(null);

  BlankEnd _end;
  double _ascent, _descent;
  Color _color;
  double _width, _room, _radius, _drop;

  BlankEnd get end => _end;
  Color get color => _color;

  /// The square's border boxes as they were last painted, in the line's own box: one for each visual line the
  /// square is on. For a test to hold against the page's rectangles.
  List<Rect> boxes = const <Rect>[];

  void set(BlankEnd end, double ascent, double descent, Color color, double width, double room, double radius, double drop) {
    final layout = end != _end || ascent != _ascent || descent != _descent || width != _width || room != _room || drop != _drop;
    final paint = color != _color || radius != _radius;
    _end = end;
    _ascent = ascent;
    _descent = descent;
    _color = color;
    _width = width;
    _room = room;
    _radius = radius;
    _drop = drop;
    if (layout) {
      markNeedsLayout();
    } else if (paint) {
      markNeedsPaint();
    }
  }

  double get _cap => _end == BlankEnd.middle ? 0 : _width + _room;

  @override
  void performLayout() {
    final inner = child;
    var across = 0.0;
    if (inner != null) {
      inner.layout(BoxConstraints(maxWidth: constraints.maxWidth), parentUsesSize: true);
      across = inner.size.width;
      // On the words' own baseline where it has one; a box with no words stands with its foot `drop` under it.
      final baseline = inner.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true);
      (inner.parentData! as BoxParentData).offset = Offset(0, _width + _ascent - (baseline ?? inner.size.height - _drop));
    }
    size = constraints.constrain(Size(across + _cap, _ascent + _descent + 2 * _width));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _width + _ascent;

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) => _width + _ascent;

  @override
  double computeMinIntrinsicWidth(double height) => (child?.getMinIntrinsicWidth(height) ?? 0) + _cap;

  @override
  double computeMaxIntrinsicWidth(double height) => (child?.getMaxIntrinsicWidth(height) ?? 0) + _cap;

  @override
  double computeMinIntrinsicHeight(double width) => _ascent + _descent + 2 * _width;

  @override
  double computeMaxIntrinsicHeight(double width) => _ascent + _descent + 2 * _width;

  /// The line this piece is a widget of, the place of the piece in it, and the piece itself as the line's child
  /// (the box the line placed), found from `box` up.
  static ({RenderEditorLine line, RenderBox child, int at, int to})? _placeOf(RenderBox box) {
    RenderObject child = box;
    var line = box.parent;
    while (line != null && line is! RenderEditorLine) {
      child = line;
      line = line.parent;
    }
    if (line is! RenderEditorLine || child is! RenderBox) return null;
    // The line's children are its widgets, in the order of the projection's widget segments.
    var index = 0;
    for (var c = line.firstChild; c != null && !identical(c, child); c = line.childAfter(c)) {
      index += 1;
    }
    var seen = 0;
    for (final segment in line.spec.projection.segments) {
      if (segment.kind != SegmentKind.widget) continue;
      if (seen == index) return (line: line, child: child, at: segment.from, to: segment.to);
      seen += 1;
    }
    return null;
  }

  /// The piece that ends the square this one starts: the next end among the line's widgets.
  static RenderBlankPiece? _endAfter(RenderEditorLine line, RenderBox start) {
    for (var c = line.childAfter(start); c != null; c = line.childAfter(c)) {
      RenderObject? inner = c;
      while (inner != null && inner is! RenderBlankPiece) {
        inner = inner is RenderObjectWithChildMixin<RenderBox> ? inner.child : null;
      }
      if (inner is RenderBlankPiece && inner._end == BlankEnd.end) return inner;
      if (inner is RenderBlankPiece && inner._end == BlankEnd.start) return null;
    }
    return null;
  }

  static VisualLine? _lineAt(RenderEditorLine line, double y) {
    for (final visual in line.visualLines) {
      if (y >= visual.top && y < visual.bottom) return visual;
    }
    return null;
  }

  /// The square's border boxes in the line's own box, one for each visual line it is on (`box-decoration-break:
  /// clone`): round everything of the square on that line, with the border and the padding outside its words
  /// where the line has neither end. An end that a wrap left by itself, at the foot of one line or the head of the
  /// next, is room and no box: on the page the padding is never apart from the words.
  List<Rect> _boxesIn(RenderEditorLine line, RenderBox own, int from) {
    final ending = _endAfter(line, own);
    final end = ending == null ? null : _placeOf(ending);
    if (ending == null || end == null) return const <Rect>[];
    final mine = (own.parentData! as BoxParentData).offset & own.size;
    final theirs = (end.child.parentData! as BoxParentData).offset & end.child.size;
    final first = _lineAt(line, mine.center.dy), last = _lineAt(line, theirs.center.dy);
    final cap = _cap;
    final found = <Rect>[];
    // Everything from this piece to the end's, both in it: a widget before this one or after that one is not.
    final rects = line.rectsForRange(from, end.to);
    for (final rect in rects) {
      final visual = _lineAt(line, rect.center.dy);
      if (visual == null) continue;
      final starts = identical(visual, first), ends = identical(visual, last);
      if (rects.length > 1 && rect.width <= cap + 0.01 && (starts || ends)) continue;
      found.add(Rect.fromLTRB(starts ? rect.left : rect.left - cap, visual.baseline - _ascent - _width, ends ? rect.right : rect.right + cap, visual.baseline + _descent + _width));
    }
    return found;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_end == BlankEnd.start && _width > 0) {
      final place = _placeOf(this);
      if (place != null) {
        boxes = _boxesIn(place.line, place.child, place.at);
        // The line's own corner on this canvas: where this piece was painted, less where the line put it.
        final origin = offset - localToGlobal(Offset.zero, ancestor: place.line);
        for (final box in boxes) {
          final at = box.shift(origin);
          paintDashedBox(context.canvas, Rect.fromLTRB(at.left, snapToDevice(at.top), at.right, snapToDevice(at.bottom)), _width, _radius, _color);
        }
      }
    }
    super.paint(context, offset);
  }
}

/// A whole square in one piece, for where a blank is drawn outside the editor's lines (a table's cell): the
/// border round what is in it.
class BlankBoxPainter extends CustomPainter {
  const BlankBoxPainter({required this.color, required this.width, required this.radius});

  final Color color;
  final double width;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) => paintDashedBox(canvas, Offset.zero & size, width, radius, color);

  @override
  bool shouldRepaint(BlankBoxPainter old) => old.color != color || old.width != width || old.radius != radius;
}
