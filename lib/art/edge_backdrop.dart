import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'edge_strips.dart';

/// The gradient blur as a backdrop filter, where the edges wear [EdgeLook.backdrop] (Android): each [EdgeBlurStrip]
/// a band of the screen blurred where it lies by shaders/edge_blur.frag, across and then down, the softness growing
/// from none at the band's inner end to the strip's sigma at its edge. No picture of the view is taken: the band
/// reads what is behind it once a frame, with the other bands of its view or box ([BackdropGroup], one of each's
/// own), and the shader's taps are as many whatever the softness. A page's ground is laid over it as [EdgeShade]
/// lays it; a box's ends have no ground of their own to lay, and the blur clears toward the edge as the box's own
/// mask does ([EdgeBackdropBand.clear], lib/art/blur_box.dart).
///
/// Matt, 2026-10-25, on the Fold with 2.3.27: "the blur works now but it's super laggy, research if there is a
/// library or something we can use for cleaner blurs, if not use simple gradients on android". The packages that
/// draw a blur growing toward an edge on pub.dev that keep up do it this way (scroll_edge_blur 0.1.1 and
/// liquid_glass_widgets 1.15.0's ProgressiveBlur, both MIT: a backdrop filter of two one-axis passes of
/// `ImageFilter.shader`, Impeller's, since Flutter 3.29); the rest take a picture of the view as the strips did, or
/// stack hard bands of blurs. It is written here rather than taken in: one shader and one render object.
///
/// The blur is laid over the sharp view through a gradient mask, a clipping mask on the blurred layer (Matt,
/// 2026-10-25, on the Fold with 2.3.28: "this is really close on the blur! the only thing I'd like to change is put
/// a small gradient mask over it so the edge doesn't look like it's clipped so hard", and then "the mask should be a
/// clipping mask"): none of the blur at the band's inner end, all of it from [edgeBlurFeather] of the way in, a
/// smoothstep between. What looked clipped was the band's inner end. Its blur was whole from the first row, only
/// faint, and the two passes are one axis each: the down pass gathers rows nearer the inner end, which the across
/// pass had hardly blurred, so a word lying across the inner end kept its sharp half and grew streaks of its sharp
/// strokes toward the edge, a word cut along a line with its ink running (on the ghostflutter2 emulator at the Fold's
/// 2.625: "## Words" at a note's foot had hard tops and long drips, build/feature-shots/blur-feather/). Under the mask
/// those rows are the sharp view, the streaks are as faint as the blur they are in, and the blur comes in as the
/// strips' does (their sharp view is gone at the same place, [EdgeBlurStrip]). The mask is the down pass's alpha,
/// and the layer is laid over the sharp view as any backdrop filter's is: no pass, tap or picture more.
///
/// A box's end clears the blur again toward its edge by the same mask (Matt, 2026-10-25, on the Fold: "the cassette
/// area needs to have a blur not a gradient"). The box's view is drawn through its own fade first, clear at the edge
/// (no backdrop filter can be drawn through a mask in this engine, edge_strips.dart), and the band blurs that, so
/// what it gathers from inside spreads into the cleared rows: on the ghostflutter2 emulator a sixth of a cassette's
/// colour stood at the shelf's very edge, a step down to the page's ground where the band ended
/// (build/feature-shots/shelf-blur/). Over the outer [EdgeBackdropBand.clear] of the band the mask falls again to
/// none, a smoothstep, and the rows there are the box's own fade: the last pixel before the ground is the ground's
/// within three levels of 255.
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

/// One band of what is behind it, blurred toward [side] up to [sigma] at the band's edge, and [bleed] past its
/// edge under a header ([EdgeBlurStrip.bleed]). [clear] is how far in from the edge the blur gives way again to what
/// it read, for a box whose own mask clears its view toward that edge (lib/art/blur_box.dart): none for a page.
class EdgeBackdropBand extends LeafRenderObjectWidget {
  const EdgeBackdropBand({super.key, required this.side, required this.sigma, this.bleed = 0, this.clear = 0});

  final EdgeSide side;
  final double sigma;
  final double bleed;
  final double clear;

  @override
  RenderEdgeBackdropBand createRenderObject(BuildContext context) => RenderEdgeBackdropBand(
      side: side, sigma: sigma, bleed: bleed, clear: clear, ratio: MediaQuery.devicePixelRatioOf(context), group: BackdropGroup.of(context)?.backdropKey);

  @override
  void updateRenderObject(BuildContext context, RenderEdgeBackdropBand renderObject) {
    renderObject
      ..side = side
      ..sigma = sigma
      ..bleed = bleed
      ..clear = clear
      ..ratio = MediaQuery.devicePixelRatioOf(context)
      ..group = BackdropGroup.of(context)?.backdropKey;
  }
}

class RenderEdgeBackdropBand extends RenderBox {
  RenderEdgeBackdropBand({required EdgeSide side, required double sigma, double bleed = 0, double clear = 0, required double ratio, BackdropKey? group})
      : _side = side,
        _sigma = sigma,
        _bleed = bleed,
        _clear = clear,
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

  double _bleed;
  double get bleed => _bleed;
  set bleed(double value) {
    if (value == _bleed) return;
    _bleed = value;
    markNeedsPaint();
  }

  double _clear;
  double get clear => _clear;
  set clear(double value) {
    if (value == _clear) return;
    _clear = value;
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
    super.detach();
  }

  /// What the band blurs, in its own pixels: itself, and [bleed] past its edge. The shader's band is the band's own
  /// rectangle, so the bleed is as soft as the edge.
  Rect get _clip => switch (_side) {
        EdgeSide.top => Rect.fromLTRB(0, -_bleed, size.width, size.height),
        EdgeSide.bottom => Rect.fromLTRB(0, 0, size.width, size.height + _bleed),
        EdgeSide.left => Rect.fromLTRB(-_bleed, 0, size.width, size.height),
        EdgeSide.right => Rect.fromLTRB(0, 0, size.width + _bleed, size.height),
      };

  /// For a test: the rectangle the band's filter is drawn in, in its own pixels.
  @visibleForTesting
  Rect get debugClip => _clip;

  /// For a test: the share of the band at its edge where the blur gives way again ([EdgeBackdropBand.clear]).
  @visibleForTesting
  double get debugClearShare => _clearShare;

  double get _clearShare {
    final long = _side == EdgeSide.top || _side == EdgeSide.bottom ? size.height : size.width;
    return long > 0 ? (_clear / long).clamp(0.0, 1.0) : 0;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final program = EdgeBackdropProgram.program.value;
    if (program == null || _sigma <= 0 || size.isEmpty) {
      layer = null;
      return;
    }
    final band = (layer as _EdgeBandLayer?) ?? _EdgeBandLayer(program);
    band
      ..program = program
      ..band = offset & size
      ..sigma = _sigma * _ratio
      ..side = _side
      ..clear = _clearShare;
    layer = band;
    context.pushLayer(band, (context, offset) {
      context.pushClipRect(true, offset, _clip, (context, offset) {
        final filter = BackdropFilterLayer()..backdropKey = _group;
        band.filter = filter;
        context.pushLayer(filter, (context, offset) {}, offset);
      });
    }, offset);
  }
}

/// A band's layer: where the band is on the screen is read as the frame is put together, not as the band was
/// painted. The shader is told the band in the screen's pixels, and a band is carried by whatever holds it without
/// being painted again: a page sliding in, a board's lane under a note scrolled, the meetings' shelf on the home page
/// flung. Until now a band that had moved was painted again a frame late, and a lane's foot, whose softness runs down
/// the screen, was a frame's scroll from where its blur was drawn while its note moved. Here every frame puts the
/// band's place in its filter from the layers over it (as a [FollowerLayer] reads its leader's), and nothing is
/// painted again for it: the layers above it are added to the frame anew rather than kept, which costs no picture.
class _EdgeBandLayer extends ContainerLayer {
  _EdgeBandLayer(this.program);

  ui.FragmentProgram program;
  ui.FragmentShader? _across, _down;
  ui.FragmentProgram? _madeFrom;

  /// The band in this layer's own pixels.
  Rect band = Rect.zero;

  /// The softness at the edge in the screen's pixels, the side, and the share at the edge where the blur clears.
  double sigma = 0, clear = 0;
  EdgeSide side = EdgeSide.top;

  /// The filter this paint pushed, which is given its shader as the frame is put together.
  BackdropFilterLayer? filter;

  @override
  bool get alwaysNeedsAddToScene => true;

  /// This layer's pixels to the screen's: every layer over it, to the view's own, which scales to the screen.
  Matrix4 _toScreen() {
    final path = <(ContainerLayer, Layer)>[];
    Layer child = this;
    for (var parent = child.parent; parent != null; parent = parent.parent) {
      path.add((parent, child));
      child = parent;
    }
    final transform = Matrix4.identity();
    for (final (parent, child) in path.reversed) {
      parent.applyTransform(child, transform);
    }
    return transform;
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    final filter = this.filter;
    if (filter != null) {
      if (_madeFrom != program) {
        _across?.dispose();
        _down?.dispose();
        _across = program.fragmentShader();
        _down = program.fragmentShader();
        _madeFrom = program;
      }
      final across = _across!, down = _down!;
      final at = MatrixUtils.transformRect(_toScreen(), band);
      for (final (shader, axis) in [(across, 0.0), (down, 1.0)]) {
        // The first two floats are the engine's: the size of the texture it reads.
        shader
          ..setFloat(2, at.left)
          ..setFloat(3, at.top)
          ..setFloat(4, at.right)
          ..setFloat(5, at.bottom)
          ..setFloat(6, sigma)
          ..setFloat(7, side.index.toDouble())
          ..setFloat(8, axis)
          ..setFloat(9, edgeBlurFeather)
          ..setFloat(10, clear);
      }
      // The engine copies a shader's floats when the filter is added to the scene, just after this, so the same two
      // shaders serve every frame.
      filter.filter = ui.ImageFilter.compose(outer: ui.ImageFilter.shader(down), inner: ui.ImageFilter.shader(across));
    }
    super.addToScene(builder);
  }

  @override
  void dispose() {
    _across?.dispose();
    _down?.dispose();
    super.dispose();
  }
}
