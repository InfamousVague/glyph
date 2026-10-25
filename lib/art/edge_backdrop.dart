import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'edge_strips.dart';

/// The gradient blur as a backdrop filter, where the edges wear [EdgeLook.backdrop] (Android): each [EdgeBlurStrip]
/// a band of the screen blurred where it lies by shaders/edge_blur.frag, across and then down, the softness growing
/// from none at the band's inner end to the strip's sigma at its edge. No picture of the view is taken: the band
/// reads what is behind it once a frame, with the app's other glass ([BackdropGroup] at the app's root), and the
/// shader's taps are as many whatever the softness. The page's ground is laid over it as [EdgeShade] lays it.
///
/// Matt, 2026-10-25, on the Fold with 2.3.27: "the blur works now but it's super laggy, research if there is a
/// library or something we can use for cleaner blurs, if not use simple gradients on android". The packages that
/// draw a blur growing toward an edge on pub.dev that keep up do it this way (scroll_edge_blur 0.1.1 and
/// liquid_glass_widgets 1.15.0's ProgressiveBlur, both MIT: a backdrop filter of two one-axis passes of
/// `ImageFilter.shader`, Impeller's, since Flutter 3.29); the rest take a picture of the view as the strips did, or
/// stack hard bands of blurs. It is written here rather than taken in: one shader and one render object.
abstract final class EdgeBackdropProgram {
  /// The program once it is loaded, and null until then (or where the engine cannot filter by a shader, where the
  /// edges fade instead, [edgeLook]). A band waiting for it draws nothing, and is drawn again when it comes.
  static final ValueNotifier<ui.FragmentProgram?> program = ValueNotifier(null);
  static bool _asked = false;

  /// Loads the program, once: called as the first view with soft edges is made, so it is there by the first scroll.
  static void load() {
    if (_asked || !ui.ImageFilter.isShaderFilterSupported) return;
    _asked = true;
    ui.FragmentProgram.fromAsset('shaders/edge_blur.frag').then<void>((loaded) => program.value = loaded, onError: (Object error) => debugPrint('edge blur: $error'));
  }
}

/// One band of what is behind it, blurred toward [side] up to [sigma] at the band's edge.
class EdgeBackdropBand extends LeafRenderObjectWidget {
  const EdgeBackdropBand({super.key, required this.side, required this.sigma});

  final EdgeSide side;
  final double sigma;

  @override
  RenderEdgeBackdropBand createRenderObject(BuildContext context) =>
      RenderEdgeBackdropBand(side: side, sigma: sigma, ratio: MediaQuery.devicePixelRatioOf(context), group: BackdropGroup.of(context)?.backdropKey);

  @override
  void updateRenderObject(BuildContext context, RenderEdgeBackdropBand renderObject) {
    renderObject
      ..side = side
      ..sigma = sigma
      ..ratio = MediaQuery.devicePixelRatioOf(context)
      ..group = BackdropGroup.of(context)?.backdropKey;
  }
}

class RenderEdgeBackdropBand extends RenderBox {
  RenderEdgeBackdropBand({required EdgeSide side, required double sigma, required double ratio, BackdropKey? group})
      : _side = side,
        _sigma = sigma,
        _ratio = ratio,
        _group = group;

  EdgeSide _side;
  EdgeSide get side => _side;
  set side(EdgeSide value) {
    if (value == _side) return;
    _side = value;
    markNeedsPaint();
  }

  double _sigma;
  double get sigma => _sigma;
  set sigma(double value) {
    if (value == _sigma) return;
    _sigma = value;
    markNeedsPaint();
  }

  double _ratio;
  set ratio(double value) {
    if (value == _ratio) return;
    _ratio = value;
    markNeedsPaint();
  }

  BackdropKey? _group;
  set group(BackdropKey? value) {
    if (value == _group) return;
    _group = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    EdgeBackdropProgram.program.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    EdgeBackdropProgram.program.removeListener(markNeedsPaint);
    _placed.remove(this);
    super.detach();
  }

  ui.FragmentShader? _across, _down;

  @override
  void dispose() {
    _across?.dispose();
    _down?.dispose();
    super.dispose();
  }

  /// The bands painted, and where on the screen each was then. The shader is told where its band is in the
  /// screen's pixels, and a band can be carried somewhere else without being painted again (a page sliding in): one
  /// that has moved is painted again, a frame late, as a strip of a box is (edge_strips.dart).
  static final Map<RenderEdgeBackdropBand, Rect> _placed = {};
  static bool _watching = false;

  /// The band on the screen, in its pixels.
  Rect _onScreen() {
    final from = localToGlobal(Offset.zero) * _ratio, to = localToGlobal(size.bottomRight(Offset.zero)) * _ratio;
    return Rect.fromPoints(from, to);
  }

  void _place(Rect band) {
    _placed[this] = band;
    if (_watching) return;
    _watching = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      var moved = false;
      for (final entry in _placed.entries.toList()) {
        final band = entry.key;
        if (!band.attached || !band.hasSize) continue;
        final now = band._onScreen();
        if ((now.topLeft - entry.value.topLeft).distanceSquared > 1e-4 || (now.bottomRight - entry.value.bottomRight).distanceSquared > 1e-4) {
          band.markNeedsPaint();
          moved = true;
        }
      }
      if (moved) SchedulerBinding.instance.scheduleFrame();
    });
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final program = EdgeBackdropProgram.program.value;
    if (program == null || _sigma <= 0 || size.isEmpty) {
      _placed.remove(this);
      return;
    }
    final band = _onScreen();
    _place(band);
    final across = _across ??= program.fragmentShader(), down = _down ??= program.fragmentShader();
    for (final (shader, axis) in [(across, 0.0), (down, 1.0)]) {
      // The first two floats are the engine's: the size of the texture it reads.
      shader
        ..setFloat(2, band.left)
        ..setFloat(3, band.top)
        ..setFloat(4, band.right)
        ..setFloat(5, band.bottom)
        ..setFloat(6, _sigma * _ratio)
        ..setFloat(7, _side.index.toDouble())
        ..setFloat(8, axis);
    }
    // The engine copies a shader's floats when the filter is added to the scene, later in this frame, so the same
    // two shaders serve every paint.
    final filter = ui.ImageFilter.compose(outer: ui.ImageFilter.shader(down), inner: ui.ImageFilter.shader(across));
    context.pushClipRect(true, offset, Offset.zero & size, (context, offset) {
      context.pushLayer(BackdropFilterLayer(filter: filter)..backdropKey = _group, (context, offset) {}, offset);
    });
  }
}
