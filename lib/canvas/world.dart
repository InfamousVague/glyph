/// The canvas's world: everything drawn in the canvas's own pixels, moved and scaled by the camera. The twin of
/// CanvasView.module.css `.world` (`transform: translate(x, y) scale(s)`, written by camera.ts), and of the
/// `scale(calc(1 / var(--canvas-scale)))` the picked card's handles and bar wear to stay one size on the screen
/// (Selection.module.css).
///
/// One render object lays its children out once, each at its place in the canvas, and reads the camera when it
/// paints and when it is asked what is under a point: a pan or a pinch repaints it and lays nothing out, builds
/// nothing, and no child is told. A child says where it goes with [Placed].
///
/// What a pan paints is the places: a child that is a layer of its own (a card is, card.dart) is set down again
/// where the camera now has it and is not drawn again, and one that scales with the canvas and is wholly off the
/// screen is not set down at all ([RenderCanvasWorld.reach] is how far outside its box a child may draw: a lifted
/// card's shadow, a ring round a card).
///
/// What differs from the web: the world there is an element of no size whose children overflow it; a render box
/// that small would take no taps, so this one fills the canvas and answers for its children wherever they are.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'camera.dart';

class WorldPlace extends ContainerBoxParentData<RenderBox> {
  /// The point of the canvas the child is set at.
  Offset at = Offset.zero;

  /// The child's size in the canvas's pixels; null lets it be as big as it likes.
  Size? size;

  /// Which point of the child sits at [at]: its top-left corner, or (0.5, 1) for the middle of its foot.
  Alignment anchor = Alignment.topLeft;

  /// Scaled back by the view's scale, so it is the same size on the screen at any zoom.
  bool fixed = false;

  /// Moved this far on the screen after everything else (a fixed child's margin).
  Offset nudge = Offset.zero;
}

/// Where a child of [CanvasWorld] goes.
class Placed extends ParentDataWidget<WorldPlace> {
  const Placed({super.key, required this.at, this.size, this.anchor = Alignment.topLeft, this.fixed = false, this.nudge = Offset.zero, required super.child});

  final Offset at;
  final Size? size;
  final Alignment anchor;
  final bool fixed;
  final Offset nudge;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as WorldPlace;
    final layout = data.size != size;
    final paint = data.at != at || data.anchor != anchor || data.fixed != fixed || data.nudge != nudge;
    data
      ..at = at
      ..size = size
      ..anchor = anchor
      ..fixed = fixed
      ..nudge = nudge;
    final parent = renderObject.parent;
    if (layout) {
      parent?.markNeedsLayout();
    } else if (paint) {
      parent?.markNeedsPaint();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => CanvasWorld;
}

class CanvasWorld extends MultiChildRenderObjectWidget {
  const CanvasWorld({super.key, required this.camera, super.children});

  final CanvasCamera camera;

  @override
  RenderCanvasWorld createRenderObject(BuildContext context) => RenderCanvasWorld(camera);

  @override
  void updateRenderObject(BuildContext context, RenderCanvasWorld renderObject) => renderObject.camera = camera;
}

class RenderCanvasWorld extends RenderBox with ContainerRenderObjectMixin<RenderBox, WorldPlace>, RenderBoxContainerDefaultsMixin<RenderBox, WorldPlace> {
  RenderCanvasWorld(this._camera);

  /// How far outside its own box a child that scales with the canvas may draw, in the canvas's pixels: a lifted
  /// card's shadow (ten down, twenty-eight of blur) is the furthest.
  static const double reach = 80;

  /// How many children the last paint set down, for a test and for a measured build.
  int debugPainted = 0;

  CanvasCamera _camera;
  CanvasCamera get camera => _camera;
  set camera(CanvasCamera value) {
    if (identical(value, _camera)) return;
    if (attached) {
      _camera.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _camera = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _camera.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _camera.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! WorldPlace) child.parentData = WorldPlace();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    // The screen's size first: the camera fits the canvas to it before anything is painted.
    _camera.resized(size.width, size.height);
    var child = firstChild;
    while (child != null) {
      final place = child.parentData! as WorldPlace;
      final given = place.size;
      child.layout(given == null ? const BoxConstraints() : BoxConstraints.tight(given), parentUsesSize: true);
      child = place.nextSibling;
    }
  }

  /// The child's own pixels to this box's: the view, and for a fixed child the view's scale taken back.
  Matrix4 _matrixOf(RenderBox child) {
    final place = child.parentData! as WorldPlace;
    final view = _camera.view;
    final scale = place.fixed ? 1.0 : view.scale;
    final x = view.x + place.at.dx * view.scale + place.nudge.dx - (place.anchor.x + 1) / 2 * child.size.width * scale;
    final y = view.y + place.at.dy * view.scale + place.nudge.dy - (place.anchor.y + 1) / 2 * child.size.height * scale;
    return Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.multiply(_matrixOf(child));

  /// Whether any of [child] can be on the screen. Only a child with a box that scales with the canvas is ever left
  /// out: one with no size draws where it likes (the lines), and one held to a size on the screen is the picked
  /// card's, whose bar opens a row of colours beyond itself.
  bool _shows(RenderBox child) {
    final place = child.parentData! as WorldPlace;
    if (place.fixed || child.size.isEmpty) return true;
    final view = _camera.view;
    final scale = view.scale;
    final left = view.x + place.at.dx * scale + place.nudge.dx - (place.anchor.x + 1) / 2 * child.size.width * scale;
    final top = view.y + place.at.dy * scale + place.nudge.dy - (place.anchor.y + 1) / 2 * child.size.height * scale;
    final out = reach * scale;
    return left - out < size.width && left + child.size.width * scale + out > 0 && top - out < size.height && top + child.size.height * scale + out > 0;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var painted = 0;
    var child = firstChild;
    while (child != null) {
      final at = child;
      if (_shows(at)) {
        painted += 1;
        context.pushTransform(needsCompositing, offset, _matrixOf(at), (context, offset) => context.paintChild(at, offset));
      }
      child = (child.parentData! as WorldPlace).nextSibling;
    }
    debugPainted = painted;
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => hitTestChildren(result, position: position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    while (child != null) {
      final at = child;
      final hit = result.addWithPaintTransform(transform: _matrixOf(at), position: position, hitTest: (result, position) => at.hitTest(result, position: position));
      if (hit) return true;
      child = (child.parentData! as WorldPlace).previousSibling;
    }
    return false;
  }
}
