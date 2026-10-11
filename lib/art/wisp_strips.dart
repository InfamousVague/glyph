import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../perf/frame_log.dart' show Perf, ghostPerf;
import 'wisp_kit.dart';
import 'wisp_probe.dart';
import 'wisp_settings.dart';
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

  /// Whether the strip reads its picture of the view only through shaders that are told where the picture lies,
  /// and only near where it stands itself. A view's strips that do are given one picture between them, of the
  /// rectangle that holds them all with only their own parts drawn in it (the picture then lies over more of the
  /// view than the strip's own part, and [paint]'s `viewRect` says where). A strip that lays the whole picture
  /// down, or blurs it, has one of its own.
  bool get shares => false;

  /// The soft half this strip's smoke wants made before it is painted, with the view's others
  /// (lib/art/wisp_smoke.dart `wispSoftSheet`); null for a strip with none. [at], [view] and [viewRect] are [paint]'s.
  WispSoftAsk? softAsk(Rect at, ui.Image view, Rect viewRect, double ratio) => null;

  /// [paint], with the soft half [softAsk] asked for.
  void paintSoft(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio, ({ui.Image image, Rect rect}) soft) => paint(canvas, at, view, viewRect, ratio);
}

/// A strip that smokes: one of the web app's smoke filters over the part of the view it bends ([WispSmoke]).
/// [within] is the subregion the web filter gives its bend and blur, which may run past the view.
class WispSmokeStrip extends WispStrip {
  const WispSmokeStrip({required this.rect, required this.smoke, required this.within, this.paper});

  @override
  final Rect rect;
  final WispSmoke smoke;
  final Rect within;

  /// The page's paper behind the view, where whoever lays the strip knows it: what the view fades to when the strip
  /// is read off the backdrop, which has no clear in it (measuring only: shaders/wisp_back.frag).
  final Color? paper;

  /// Half the displacement's scale is the furthest a pixel is thrown. The bent view is worked out that far past the
  /// strip (below), and each of its pixels may come from that far again.
  @override
  double get reach => 2 * (smoke.bend / 2).ceilToDouble();

  @override
  bool get ready => WispKit.maybe?.tableNow(smoke.seed) != null;

  /// The bent view is worked out a throw past the strip, so the blur at the strip's edge has what the page's has:
  /// pixels thrown out of the view, which the page's own mask then hides.
  Rect _bentRect(Rect at, double ratio) => snapOut(at.inflate((smoke.bend / 2).ceilToDouble()).intersect(within), at.topLeft, ratio);

  @override
  bool get shares => wispQuick && !WispProbe.has('noshare');

  @override
  WispSoftAsk? softAsk(Rect at, ui.Image view, Rect viewRect, double ratio) =>
      wispQuick ? WispSoftAsk(table: WispKit.maybe!.tableNow(smoke.seed)!, source: view, sourceRect: viewRect, bentRect: _bentRect(at, ratio), smoke: smoke) : null;

  @override
  void paint(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio) => _paint(canvas, at, view, viewRect, ratio, null);

  @override
  void paintSoft(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio, ({ui.Image image, Rect rect}) soft) => _paint(canvas, at, view, viewRect, ratio, soft);

  void _paint(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio, ({ui.Image image, Rect rect})? soft) {
    final kit = WispKit.maybe!;
    paintWispSmoke(canvas, kit: kit, table: kit.tableNow(smoke.seed)!, source: view, sourceRect: viewRect, rect: at, bentRect: _bentRect(at, ratio), ratio: ratio, smoke: smoke, soft: soft);
  }

  @override
  bool operator ==(Object other) => other is WispSmokeStrip && other.rect == rect && other.smoke == smoke && other.within == within;

  @override
  int get hashCode => Object.hash(rect, smoke, within);
}

/// The strips a smoke is drawn in over [rect] of a view: [rect] itself as the web filter's subregion has it, or,
/// drawn the quick way ([wispQuick]), only the parts of it the smoke changes at all ([WispSmoke.touched]). The
/// subregion is sized for the filter's arithmetic (four deviations of the band's ramp and 48px more); what a pixel
/// shows changes only where the band is not nothing or the fade not whole, and past three deviations of the ramp
/// the band is under a seven-hundredth: the view there is the view, to less than one step of 255, and is left to
/// paint itself. A third to a half of every strip, and of every picture a strip is drawn through.
List<WispStrip> wispSmokeStrips({required Rect rect, required WispSmoke smoke, required Rect within, Color? paper}) {
  if (!wispQuick) return [WispSmokeStrip(rect: rect, smoke: smoke, within: within)];
  return [
    for (final part in smoke.touched(rect))
      if (!part.isEmpty) WispSmokeStrip(rect: part, smoke: smoke, within: within, paper: paper),
  ];
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
    if (ghostPerf) WispProbe.watch();
  }

  @override
  void detach() {
    _repaint?.removeListener(markNeedsPaint);
    _placed.remove(this);
    super.detach();
  }

  /// The views whose strips were laid on the screen's pixels at their last paint, and where each then stood.
  static final Map<RenderWispStrips, Offset> _placed = {};
  static bool _watching = false;

  /// Remembers where this view's strips were laid, and from then on looks after every frame whether any such view
  /// has since been moved to another place between the screen's pixels without being painted: under a repaint
  /// boundary (lib/art/wisp_box.dart) a view is moved by whatever holds it and keeps its picture, and its strips'
  /// pictures were taken on the pixels it stood on. One that has moved is painted again, a frame late.
  void _place(Offset phase) {
    _placed[this] = phase;
    if (_watching) return;
    _watching = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      var moved = false;
      for (final entry in _placed.entries.toList()) {
        final view = entry.key;
        if (!view.attached || !view.hasSize) continue;
        if ((view._phase() - entry.value).distanceSquared > 1e-6) {
          view.markNeedsPaint();
          moved = true;
        }
      }
      // Asked for outright: a view marked while a frame is being drawn is taken to be that frame's to paint, and
      // this one has painted already.
      if (moved) SchedulerBinding.instance.scheduleFrame();
    });
  }

  /// How far this view's corner stands from a corner of the screen's pixels.
  Offset _phase() {
    final corner = localToGlobal(Offset.zero);
    return Offset(_fraction(corner.dx * _ratio) / _ratio, _fraction(corner.dy * _ratio) / _ratio);
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
      if (!WispProbe.has('off'))
        for (final strip in _strips)
          if (strip.ready && !strip.rect.isEmpty) strip,
    ];
    _painted = drawn;
    if (child == null || drawn.isEmpty) {
      layer = null;
      _placed.remove(this);
      super.paint(context, offset);
      return;
    }
    // Where the view's corner falls on the screen, to lay each strip's picture on the screen's own pixels.
    final phase = _phase();
    if (wispQuick) _place(phase);
    final stripLayer = (layer as _WispStripLayer?) ?? _WispStripLayer();
    stripLayer
      ..offset = offset
      ..strips = drawn
      ..ratio = _ratio
      ..corner = -phase
      ..global = localToGlobal(Offset.zero)
      ..view = Offset.zero & size;
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

  /// Where the view's corner is on the screen: for a strip read off the backdrop, whose pixels are the screen's.
  Offset _global = Offset.zero;
  set global(Offset value) {
    if (value == _global) return;
    _global = value;
    if (WispProbe.has('backdrop')) markNeedsAddToScene();
  }

  /// The view's own rectangle: what a filter over its layers is given a picture of.
  Rect _view = Rect.zero;
  set view(Rect value) {
    if (value == _view) return;
    _view = value;
    if (WispProbe.has('through')) markNeedsAddToScene();
  }

  /// Measuring only (GHOST_PERF_SMOKE=through): the program this view's layers go through for its smokes, where
  /// every strip of it is a smoke one program can say and the engine can filter a layer with a program; else null.
  ui.FragmentShader? _through(List<Rect> at, Rect view) {
    if (!WispProbe.has('through') || !wispQuick || !ui.ImageFilter.isShaderFilterSupported) return null;
    final kit = WispKit.maybe;
    if (kit == null || view.isEmpty) return null;
    final smokes = <({Rect at, WispSmoke smoke, Rect within})>[];
    for (var i = 0; i < _strips.length; i++) {
      final strip = _strips[i];
      if (strip is! WispSmokeStrip) return null;
      if (at[i].isEmpty || at[i].width <= 0 || at[i].height <= 0) continue;
      smokes.add((at: at[i], smoke: strip.smoke, within: strip.within));
    }
    if (WispProbe.has('backsay') && _saidOf.add('through ${smokes.length} ${smokes.isEmpty ? 0 : smokes.first.at.top}') && _saidOf.length < 16) {
      // ignore: avoid_print
      print('[through] view ${_ltrb(view)} (layer offset ${offset.dx},${offset.dy}), ratio $_ratio, ${[for (final each in smokes) 'strip ${_ltrb(each.at)} lips ${each.smoke.lipA}/${each.smoke.lipB} soft ${each.smoke.soft} bend ${each.smoke.bend}'].join('; ')}');
    }
    return wispThrough(kit: kit, view: view, smokes: smokes, probe: _probe);
  }

  static double get _probe => WispProbe.has('backred') ? 1.0 : (WispProbe.has('backheavy') ? 2.0 : (WispProbe.has('backshow') ? 3.0 : (WispProbe.has('backplace') ? 4.0 : 0.0)));
  static String _ltrb(Rect rect) => '${rect.left},${rect.top},${rect.right},${rect.bottom}';
  static final Set<String> _saidOf = {};
  static int _groups = 1 << 24;
  final int _group = _groups++;

  /// Measuring only (GHOST_PERF_SMOKE=backdrop): whether strip [i] is read off what is already drawn behind it,
  /// where the engine can filter its own backdrop with a program, and not through a picture of the view.
  bool _reads(int i) {
    if (!WispProbe.has('backdrop') || !wispQuick || !ui.ImageFilter.isShaderFilterSupported) return false;
    final strip = _strips[i];
    return strip is WispSmokeStrip && strip.paper != null && WispKit.maybe != null;
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
    if (WispProbe.has('layers')) _census();

    // Measuring only: the view's layers through one program, which bends and fades its strips as they are drawn.
    final view = snapOut(_view, _corner, _ratio);
    final through = _through(at, view);
    if (through != null) {
      if (ghostPerf) Perf.count('wisp.throughs');
      builder.pushClipRect(view, clipBehavior: Clip.hardEdge);
      builder.pushImageFilter(ui.ImageFilter.shader(through));
      // The filter's picture is of what is drawn, and the program counts from the view's corner: a clear rectangle
      // the size of the view, drawn so that it counts, makes the picture the view's whatever else is in it.
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(view, Paint()..color = const Color(0x00000000)..blendMode = BlendMode.src);
      final whole = recorder.endRecording();
      builder.addPicture(Offset.zero, whole);
      whole.dispose();
      addChildrenToScene(builder);
      builder.pop();
      builder.pop();
      builder.pop();
      return;
    }

    // The view itself, everywhere but under the strips. Hard edged, as the strips are drawn, so the two meet on one
    // line of pixels with neither showing through the other.
    final rest = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(const Rect.fromLTRB(-1e7, -1e7, 1e7, 1e7));
    for (var i = 0; i < at.length; i++) {
      // A strip read off the backdrop needs the view drawn under it.
      if (!at[i].isEmpty && !_reads(i)) rest.addRect(at[i]);
    }
    builder.pushClipPath(rest, clipBehavior: Clip.hardEdge);
    addChildrenToScene(builder);
    builder.pop();

    // Measuring only: the strips read off the backdrop, one reading of it between them.
    for (var i = 0; i < at.length; i++) {
      if (at[i].isEmpty || at[i].width <= 0 || at[i].height <= 0 || !_reads(i)) continue;
      final strip = _strips[i] as WispSmokeStrip;
      final probe = _probe;
      final shader = wispBack(kit: WispKit.maybe!, at: at[i], smoke: strip.smoke, within: strip.within, viewAt: _global, ratio: _ratio, paper: strip.paper!, probe: probe);
      if (shader == null) continue;
      if (ghostPerf) Perf.count('wisp.backdrops');
      if (WispProbe.has('backsay') && _saidOf.add('back ${at[i].top} ${at.length}') && _saidOf.length < 16) {
        // ignore: avoid_print
        print('[back] strip ${_ltrb(at[i])} of a view at ${_global.dx},${_global.dy} (layer offset ${offset.dx},${offset.dy}; view ${_ltrb(_view)}), ratio $_ratio, lips ${strip.smoke.lipA}/${strip.smoke.lipB} soft ${strip.smoke.soft}, bend ${strip.smoke.bend}, noise in ${_ltrb(strip.smoke.noiseRect)}, slide ${strip.smoke.slide.dx},${strip.smoke.slide.dy}, fade ${strip.smoke.fade.clearUntil}/${strip.smoke.fade.wholeFrom}/${strip.smoke.fade.wholeUntil}/${strip.smoke.fade.clearFrom}');
      }
      builder.pushClipRect(at[i], clipBehavior: Clip.hardEdge);
      builder.pushBackdropFilter(ui.ImageFilter.shader(shader), backdropId: _group);
      builder.pop();
      builder.pop();
    }

    // The strips' pictures of the view. Those that can share one do ([WispStrip.shares]): each picture the engine
    // is asked for is a task of its own on the raster thread before the frame, with a walk of every layer under
    // this view in it, and a page's top, its foot and its dock's halo each asked for one.
    final live = [
      for (var i = 0; i < _strips.length; i++)
        if (!(at[i].isEmpty || at[i].width <= 0 || at[i].height <= 0) && !_reads(i)) i,
    ];
    final views = <int, ({ui.Image image, Rect rect})>{};
    final sharing = [
      for (final i in live)
        if (_strips[i].shares) i,
    ];
    ui.Image? shared;
    if (sharing.isNotEmpty) {
      final rects = [for (final i in sharing) snapOut(at[i].inflate(_strips[i].reach), _corner, _ratio)];
      final made = _pictures(rects);
      shared = made.image;
      for (final i in sharing) {
        views[i] = made;
      }
    }
    for (final i in live) {
      if (!views.containsKey(i)) views[i] = _pictures([snapOut(at[i].inflate(_strips[i].reach), _corner, _ratio)]);
    }

    // The smokes' soft halves, made together.
    final asking = <int>[], asks = <WispSoftAsk>[];
    if (!WispProbe.has('plain')) {
      for (final i in live) {
        final ask = _strips[i].softAsk(at[i], views[i]!.image, views[i]!.rect, _ratio);
        if (ask == null) continue;
        asking.add(i);
        asks.add(ask);
      }
    }
    final softs = asks.isEmpty ? null : wispSoftSheet(kit: WispKit.maybe!, ratio: _ratio, asks: asks);

    for (final i in live) {
      final rect = at[i], strip = _strips[i], view = views[i]!;
      if (ghostPerf) Perf.count('wisp.strips');
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      if (WispProbe.has('plain')) {
        // Measuring only: the picture of the view drawn straight back.
        canvas.clipRect(rect, doAntiAlias: false);
        _drawView(canvas, view.image, view.rect);
      } else {
        final n = asking.indexOf(i);
        if (n >= 0) {
          strip.paintSoft(canvas, rect, view.image, view.rect, _ratio, (image: softs!.image, rect: softs.rects[n]));
        } else {
          strip.paint(canvas, rect, view.image, view.rect, _ratio);
        }
      }
      final picture = recorder.endRecording();
      builder.addPicture(Offset.zero, picture);
      picture.dispose();
    }
    softs?.image.dispose();
    shared?.dispose();
    for (final i in live) {
      if (!identical(views[i]!.image, shared)) views[i]!.image.dispose();
    }

    builder.pop();
  }

  static int _censusAt = 0;

  /// Measuring only: what lies under this view by kind of layer, said once a second while it is drawn. A layer that
  /// is not an offset, a clip of a rectangle or a picture is one the engine may draw through a picture of its own.
  void _census() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _censusAt < 1000) return;
    _censusAt = now;
    final kinds = <String, int>{};
    void visit(Layer layer) {
      var kind = layer.runtimeType.toString();
      if (layer is OpacityLayer) kind = '$kind(${layer.alpha})';
      if (layer is ClipRRectLayer) kind = '$kind(${layer.clipBehavior.name})';
      if (layer is ClipPathLayer) kind = '$kind(${layer.clipBehavior.name})';
      kinds[kind] = (kinds[kind] ?? 0) + 1;
      if (layer is ContainerLayer) {
        for (var child = layer.firstChild; child != null; child = child.nextSibling) {
          visit(child);
        }
      }
    }

    for (var child = firstChild; child != null; child = child.nextSibling) {
      visit(child);
    }
    final said = (kinds.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((entry) => '${entry.key}=${entry.value}').join(' ');
    debugPrint('[perf] layers under ${_strips.length} strip(s): $said');
  }

  /// The children as one picture of several parts of the view ([rects], each on the screen's pixels), at the
  /// screen's own pixels: a picture of the rectangle that holds them all, with only the parts drawn in it and the
  /// rest clear. The answer's [rect] is that rectangle, which is where the picture lies in the view and what a
  /// shader that reads it is told. For one part, it is the part.
  ///
  /// One picture, and the children put into its scene once: a scene may use a layer only once, so a picture with
  /// each part's rows moved up against the next is not to be had from one scene, and a scene for each part is a
  /// walk of every layer under this view for each. What lies between the parts costs the engine a clear.
  ({ui.Image image, Rect rect}) _pictures(List<Rect> rects) {
    var all = rects.first;
    for (final rect in rects.skip(1)) {
      all = all.expandToInclude(rect);
    }
    final builder = ui.SceneBuilder();
    final transform = Matrix4.diagonal3Values(_ratio, _ratio, 1)..translateByDouble(-all.left, -all.top, 0, 1);
    builder.pushTransform(transform.storage);
    if (rects.length > 1) {
      final parts = Path();
      for (final rect in rects) {
        parts.addRect(rect);
      }
      builder.pushClipPath(parts, clipBehavior: Clip.hardEdge);
    }
    addChildrenToScene(builder);
    if (rects.length > 1) builder.pop();
    builder.pop();
    final scene = builder.build();
    debugWispPictures += 1;
    if (ghostPerf) Perf.count('wisp.pictures');
    try {
      return (image: scene.toImageSync(math.max(1, (all.width * _ratio).round()), math.max(1, (all.height * _ratio).round())), rect: all);
    } finally {
      scene.dispose();
    }
  }
}
