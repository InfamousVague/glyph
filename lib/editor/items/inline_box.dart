/// Two small things the inline items stand on, neither of them the web's (which has CSS for both):
///
/// - [InlineBox], an inline widget whose box reaches a stated way above and below the line's baseline, whatever
///   its child's own height: `display: inline-block` with a `line-height`, or `vertical-align: middle`, whose
///   place on the line the page works out from the font and Flutter's paragraph is simply told.
/// - [GapWidget], room at one end of a mark: the `padding` (and border) of an inline `<span>`. The view styles a
///   mark's words and has no padding to give them, so a chip drawn as a mark (a tag, a counter) puts a gap either
///   side of its words and paints its ground under all three (`lib/editor/marks/run_paint.dart` `BoxLayer`).
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' hide Decoration;

import '../editor.dart';
import '../view/line.dart' show EditorRunScope;

/// An inline box that reaches [above] and [below] the line's baseline. Its child is laid out loose and set with
/// its top at the box's top; what is in it places itself.
class InlineBox extends SingleChildRenderObjectWidget {
  const InlineBox({super.key, required this.above, required this.below, required Widget super.child});

  final double above;
  final double below;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderInlineBox(above, below);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderInlineBox)
      ..above = above
      ..below = below;
  }
}

class _RenderInlineBox extends RenderShiftedBox {
  _RenderInlineBox(this._above, this._below) : super(null);

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
    inner.layout(BoxConstraints(maxWidth: constraints.maxWidth), parentUsesSize: true);
    (inner.parentData! as BoxParentData).offset = Offset.zero;
    size = constraints.constrain(Size(inner.size.width, _above + _below));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _above;

  @override
  double computeMaxIntrinsicHeight(double width) => _above + _below;

  @override
  double computeMinIntrinsicHeight(double width) => _above + _below;
}

/// Room at one end of a mark's words: [em] of the line's own size and [px] more. It draws nothing and takes no
/// caret stop or press of its own.
class GapWidget extends EditorWidget {
  const GapWidget({required this.em, this.px = 0});

  final double em;
  final double px;

  @override
  bool eq(GapWidget other) => other.em == em && other.px == px;

  @override
  bool get isHidden => true;

  @override
  bool takesPointer(_) => false;

  @override
  Widget build(BuildContext context) {
    final size = EditorRunScope.maybeOf(context)?.line.base.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 16;
    return SizedBox(width: em * size + px, height: 0);
  }
}

/// Sets `child` with its top `top` under the top of the box it is in, above it where `top` is below zero: a
/// letter's own box starts a fraction over the line box it is set in, which a padding cannot say.
class Dropped extends StatelessWidget {
  const Dropped({super.key, required this.top, required this.child});

  final double top;
  final Widget child;

  @override
  Widget build(BuildContext context) => Transform.translate(offset: Offset(0, top), child: child);
}
