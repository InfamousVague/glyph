import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'wisp_kit.dart';
import 'wisp_smoke.dart';

/// What one strip of a view is drawn through, in place of the view itself: its smoke, its torn mask, its fade.
///
/// On the page a `filter` or a `mask-image` is worn by the whole element, and the engine works out which pixels it
/// can leave alone (art/WispEdgeFilter.tsx gives every primitive a subregion for that). Here the view says which
/// strips of it are treated at all: everything outside them is the view as it paints itself, never taken through a
/// picture, and only the strips cost anything. [rect] is the strip in the view's own pixels; [reach] is how much
/// further the picture of the view has to run for what the strip draws (a bend throws pixels in from beside it, a
/// blur gathers them).
@immutable
abstract class WispStrip {
  const WispStrip();
  Rect get rect;
  double get reach;

  /// Draws the strip over [at], the strip's own rectangle after it was laid on the screen's pixels. [view] is a
  /// picture of the view over [viewRect], at [ratio] of the screen's pixels to a logical one.
  void paint(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio);

  /// Whether the strip can be drawn yet: a smoke waits for its programs and its table.
  bool get ready => true;
}

/// A strip that smokes: one of the web app's smoke filters over the part of the view it bends ([WispSmoke]).
/// [within] is the subregion the web filter gives its bend and blur, which may run past the view.
class WispSmokeStrip extends WispStrip {
  const WispSmokeStrip({required this.rect, required this.smoke, required this.within});

  @override
  final Rect rect;
  final WispSmoke smoke;
  final Rect within;

  /// Half the displacement's scale is the furthest a pixel is thrown. The bent view is worked out that far past the
  /// strip (below), and each of its pixels may come from that far again.
  @override
  double get reach => 2 * (smoke.bend / 2).ceilToDouble();

  @override
  bool get ready => WispKit.maybe?.tableNow(smoke.seed) != null;

  @override
  void paint(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio) {
    final kit = WispKit.maybe!;
    // The bent view is worked out a throw past the strip, so the blur at the strip's edge has what the page's has:
    // pixels thrown out of the view, which the page's own mask then hides.
    final throwBy = (smoke.bend / 2).ceilToDouble();
    final bentRect = snapOut(at.inflate(throwBy).intersect(within), at.topLeft, ratio);
    paintWispSmoke(canvas, kit: kit, table: kit.tableNow(smoke.seed)!, source: view, sourceRect: viewRect, rect: at, bentRect: bentRect, ratio: ratio, smoke: smoke);
  }

  @override
  bool operator ==(Object other) => other is WispSmokeStrip && other.rect == rect && other.smoke == smoke && other.within == within;

  @override
  int get hashCode => Object.hash(rect, smoke, within);
}

/// A strip that only fades: the view's `mask-image` gradient with no filter under it, which is what the page wears
/// with reduced motion and on a desktop (art/wisp.css).
class WispFadeStrip extends WispStrip {
  const WispFadeStrip({required this.rect, required this.fade, this.axis = Axis.vertical});

  @override
  final Rect rect;
  final WispFade fade;
  final Axis axis;

  @override
  double get reach => 0;

  @override
  void paint(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio) {
    canvas.saveLayer(at, Paint());
    _drawView(canvas, view, viewRect);
    for (final ramp in fadeRamps(fade, axis)) {
      canvas.drawRect(at, Paint()..blendMode = BlendMode.dstIn..shader = ramp..isAntiAlias = false);
    }
    canvas.restore();
  }

  @override
  bool operator ==(Object other) => other is WispFadeStrip && other.rect == rect && other.fade == fade && other.axis == axis;

  @override
  int get hashCode => Object.hash(rect, fade, axis);
}

/// A [WispFade] as the gradient the stylesheet writes, along [axis] of the view: the ramp in at its start and the
/// ramp out at its end, each a gradient of its own, laid one after the other (their alphas multiply, which is the
/// one mask: whole between the two, clear outside them).
///
/// Each ramp's line is only as long as the ramp. One gradient for the whole mask had four stops a few pixels
/// apart on a line long enough for any view, and an engine that draws a gradient from a table of colours (Impeller
/// on the Mac) put the whole 28 px ramp inside one entry of it: the foot of every page on a desktop was cut off 28 px
/// above the window's edge, where the page's fades to it.
List<ui.Gradient> fadeRamps(WispFade fade, Axis axis) {
  const clear = Color(0x00000000), whole = Color(0xFF000000);
  Offset on(double value) => axis == Axis.vertical ? Offset(0, value) : Offset(value, 0);
  // A ramp with no length is an edge: a line one hundredth of a pixel long draws it as one.
  ui.Gradient ramp(double from, double to, Color first, Color last) => ui.Gradient.linear(on(from), on(math.max(to, from + 0.01)), [first, last]);
  // An end with no fade is said as a place no view reaches (wisp_kit.dart `WispFade`): no ramp is drawn for it.
  const nowhere = 1e8;
  return [
    // Clear before `clearUntil`, whole from `wholeFrom` on, however far.
    if (fade.wholeFrom > -nowhere) ramp(fade.clearUntil, fade.wholeFrom, clear, whole),
    // Whole until `wholeUntil`, clear from `clearFrom` on.
    if (fade.wholeUntil < nowhere) ramp(fade.wholeUntil, fade.clearFrom, whole, clear),
  ];
}

void _drawView(Canvas canvas, ui.Image view, Rect viewRect, [Paint? paint]) {
  canvas.drawImageRect(view, Rect.fromLTWH(0, 0, view.width.toDouble(), view.height.toDouble()), viewRect, paint ?? Paint());
}

/// A strip torn by a picture of smoke: the web app's mask drawing (art/wispMask.ts, art/wisp.css
/// `[data-wisp-draw='mask']`). Two mask layers, added: [whole], the part of the strip the words show whole in, and
/// [band], the torn band, tiled across from [bandAt] and slid by the drift.
class WispMaskStrip extends WispStrip {
  const WispMaskStrip({required this.rect, required this.whole, required this.band, required this.bandSize, required this.bandAt});

  @override
  final Rect rect;
  final Rect whole;

  /// The band's picture, null until it has been made; without it the strip shows only [whole].
  final ui.Image? band;

  /// The band's size in logical pixels, whatever its picture's own.
  final Size bandSize;
  final Offset bandAt;

  @override
  double get reach => 0;

  @override
  void paint(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio) {
    canvas.saveLayer(at, Paint());
    _drawView(canvas, view, viewRect);
    canvas.saveLayer(at, Paint()..blendMode = BlendMode.dstIn);
    canvas.drawRect(whole.intersect(at), Paint()..color = const Color(0xFF000000)..isAntiAlias = false);
    final picture = band;
    if (picture != null) {
      final matrix = Matrix4.translationValues(bandAt.dx, bandAt.dy, 0)..scaleByDouble(bandSize.width / picture.width, bandSize.height / picture.height, 1, 1);
      final shader = ui.ImageShader(picture, TileMode.repeated, TileMode.decal, matrix.storage, filterQuality: FilterQuality.low);
      canvas.drawRect(at, Paint()..shader = shader..isAntiAlias = false);
      shader.dispose();
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool operator ==(Object other) =>
      other is WispMaskStrip && other.rect == rect && other.whole == whole && identical(other.band, band) && other.bandSize == bandSize && other.bandAt == bandAt;

  @override
  int get hashCode => Object.hash(rect, whole, band, bandSize, bandAt);
}

/// A desktop's edge under a header: `.app-headerBlur` of art/wisp.css, a strip of blur that fades to nothing where a
/// phone has the wisp. On the page it is an element of its own with a `backdrop-filter`; here it is the view's own
/// strip drawn blurred over itself, since a backdrop blur cannot be faded by a mask in this engine.
class WispBlurStrip extends WispStrip {
  const WispBlurStrip({required this.rect, required this.wash, required this.opacity, this.sigma = 10});

  @override
  final Rect rect;

  /// The page's ground at 55%, which the strip's own background fades from.
  final Color wash;

  /// The strip's `opacity`, on its way to 1 while the view under it is scrolled.
  final double opacity;
  final double sigma;

  @override
  double get reach => (sigma * 3).ceilToDouble();

  @override
  void paint(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio) {
    canvas.save();
    canvas.clipRect(at, doAntiAlias: false);
    _drawView(canvas, view, viewRect);
    if (opacity > 0) {
      canvas.saveLayer(at, Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)));
      _drawView(canvas, view, viewRect, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp));
      final down = [at.topCenter, at.bottomCenter];
      canvas.drawRect(at, Paint()..shader = ui.Gradient.linear(down[0], down[1], [wash, wash.withValues(alpha: 0)]));
      canvas.drawRect(at, Paint()..blendMode = BlendMode.dstIn..shader = ui.Gradient.linear(down[0], down[1], const [Color(0xFF000000), Color(0x00000000)]));
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool operator ==(Object other) => other is WispBlurStrip && other.rect == rect && other.wash == wash && other.opacity == opacity && other.sigma == sigma;

  @override
  int get hashCode => Object.hash(rect, wash, opacity, sigma);
}

/// Draws [child] with some strips of it taken through [strips]: the render side of every wisp widget.
///
/// The child paints as it always does; where a strip lies, the child is cut away and the strip is drawn from a
/// picture of the child taken for it. With no strips this is the child and nothing more: no layer, no picture.
class WispStrips extends SingleChildRenderObjectWidget {
  const WispStrips({super.key, required this.strips, this.repaint, super.child});

  final List<WispStrip> strips;

  /// Told when what the strips draw changes without the widget being built again: the kit arriving.
  final Listenable? repaint;

  @override
  RenderWispStrips createRenderObject(BuildContext context) =>
      RenderWispStrips(strips: strips, ratio: MediaQuery.devicePixelRatioOf(context), repaint: repaint);

  @override
  void updateRenderObject(BuildContext context, RenderWispStrips renderObject) {
    renderObject
      ..strips = strips
      ..ratio = MediaQuery.devicePixelRatioOf(context)
      ..repaint = repaint;
  }
}

class RenderWispStrips extends RenderProxyBox {
  RenderWispStrips({required List<WispStrip> strips, required double ratio, Listenable? repaint})
      : _strips = strips,
        _ratio = ratio,
        _repaint = repaint;

  List<WispStrip> _strips;
  List<WispStrip> get strips => _strips;
  set strips(List<WispStrip> value) {
    if (listEquals(value, _strips)) return;
    final had = _strips.isNotEmpty;
    _strips = value;
    if (had != value.isNotEmpty) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  double _ratio;
  double get ratio => _ratio;
  set ratio(double value) {
    if (value == _ratio) return;
    _ratio = value;
    markNeedsPaint();
  }

  Listenable? _repaint;
  Listenable? get repaint => _repaint;
  set repaint(Listenable? value) {
    if (identical(value, _repaint)) return;
    if (attached) _repaint?.removeListener(markNeedsPaint);
    _repaint = value;
    if (attached) _repaint?.addListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => _strips.isNotEmpty;

  /// The strips drawn in the last paint, for a test to read: the ones that were ready.
  @visibleForTesting
  List<WispStrip> get debugPainted => _painted;
  List<WispStrip> _painted = const [];

  @override
  void paint(PaintingContext context, Offset offset) {
    final drawn = [
      for (final strip in _strips)
        if (strip.ready && !strip.rect.isEmpty) strip,
    ];
    _painted = drawn;
    if (child == null || drawn.isEmpty) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    // Where the view's corner falls on the screen, to lay each strip's picture on the screen's own pixels.
    final corner = localToGlobal(Offset.zero);
    final phase = Offset(_fraction(corner.dx * _ratio) / _ratio, _fraction(corner.dy * _ratio) / _ratio);
    final stripLayer = (layer as _WispStripLayer?) ?? _WispStripLayer();
    stripLayer
      ..offset = offset
      ..strips = drawn
      ..ratio = _ratio
      ..corner = -phase;
    context.pushLayer(stripLayer, super.paint, Offset.zero);
    layer = stripLayer;
  }

  static double _fraction(double value) {
    final part = value - value.floorToDouble();
    // A view a hair off a pixel's corner, by the arithmetic that put it there, is on it.
    return part < 1e-3 || part > 1 - 1e-3 ? 0 : part;
  }
}

class _WispStripLayer extends OffsetLayer {
  List<WispStrip> _strips = const [];
  set strips(List<WispStrip> value) {
    if (listEquals(value, _strips)) return;
    _strips = value;
    markNeedsAddToScene();
  }

  double _ratio = 1;
  set ratio(double value) {
    if (value == _ratio) return;
    _ratio = value;
    markNeedsAddToScene();
  }

  /// A point of the view that lies on a screen pixel's corner.
  Offset _corner = Offset.zero;
  set corner(Offset value) {
    if (value == _corner) return;
    _corner = value;
    markNeedsAddToScene();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    // Each strip on the screen's pixels, and none over another: where two meet, each keeps its own side.
    final at = [for (final strip in _strips) snapOut(strip.rect, _corner, _ratio)];
    for (var i = 0; i < at.length; i++) {
      for (var j = i + 1; j < at.length; j++) {
        final over = at[i].intersect(at[j]);
        if (over.isEmpty || over.width <= 0 || over.height <= 0) continue;
        if (over.height <= over.width) {
          final upper = at[i].top <= at[j].top ? i : j, lower = upper == i ? j : i;
          final mid = snapOut(Rect.fromLTRB(0, (over.top + over.bottom) / 2, 0, (over.top + over.bottom) / 2), _corner, _ratio).top;
          at[upper] = Rect.fromLTRB(at[upper].left, at[upper].top, at[upper].right, mid);
          at[lower] = Rect.fromLTRB(at[lower].left, mid, at[lower].right, at[lower].bottom);
        } else {
          final first = at[i].left <= at[j].left ? i : j, second = first == i ? j : i;
          final mid = snapOut(Rect.fromLTRB((over.left + over.right) / 2, 0, (over.left + over.right) / 2, 0), _corner, _ratio).left;
          at[first] = Rect.fromLTRB(at[first].left, at[first].top, mid, at[first].bottom);
          at[second] = Rect.fromLTRB(mid, at[second].top, at[second].right, at[second].bottom);
        }
      }
    }

    engineLayer = builder.pushOffset(offset.dx, offset.dy, oldLayer: engineLayer as ui.OffsetEngineLayer?);

    // The view itself, everywhere but under the strips. Hard edged, as the strips are drawn, so the two meet on one
    // line of pixels with neither showing through the other.
    final rest = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(const Rect.fromLTRB(-1e7, -1e7, 1e7, 1e7));
    for (final rect in at) {
      if (!rect.isEmpty) rest.addRect(rect);
    }
    builder.pushClipPath(rest, clipBehavior: Clip.hardEdge);
    addChildrenToScene(builder);
    builder.pop();

    for (var i = 0; i < _strips.length; i++) {
      final rect = at[i];
      if (rect.isEmpty || rect.width <= 0 || rect.height <= 0) continue;
      final strip = _strips[i];
      final viewRect = snapOut(rect.inflate(strip.reach), _corner, _ratio);
      final view = _picture(viewRect);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      try {
        strip.paint(canvas, rect, view, viewRect, _ratio);
      } finally {
        view.dispose();
      }
      final picture = recorder.endRecording();
      builder.addPicture(Offset.zero, picture);
      picture.dispose();
    }

    builder.pop();
  }

  /// The children as a picture of [rect] of the view, at the screen's own pixels.
  ui.Image _picture(Rect rect) {
    final builder = ui.SceneBuilder();
    final transform = Matrix4.diagonal3Values(_ratio, _ratio, 1)..translateByDouble(-rect.left, -rect.top, 0, 1);
    builder.pushTransform(transform.storage);
    addChildrenToScene(builder);
    builder.pop();
    final scene = builder.build();
    try {
      return scene.toImageSync(math.max(1, (rect.width * _ratio).round()), math.max(1, (rect.height * _ratio).round()));
    } finally {
      scene.dispose();
    }
  }
}
