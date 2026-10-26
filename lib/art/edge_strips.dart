import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../perf/frame_log.dart' show Perf, ghostPerf;

/// The strips of a view drawn through a picture of the view itself: the gradient blur at a page's edges
/// (blur_edge.dart), at a board lane's foot and the tab row's ends (blur_box.dart), round the dock (dock_blur.dart),
/// and the haze over a scene's words (lib/scene/at_work.dart).
///
/// Where the wisp's smoke was (Matt, 2026-10-24: "replace the smoke effect with a gradient blur on all places that
/// use the wisp smoke", and the same day "remove the smoke on mac too so all versions get blur"), each of these
/// is now a blur that grows toward the edge it stands at, washed with the page's ground. A backdrop filter blurs
/// what is behind it but cannot be faded through a mask in this engine (Impeller on the Mac and the phones draws a
/// `BackdropFilter` under a `ShaderMask` whole, or not at all), so a blur that fades in would be a stack of hard
/// bands; here the view's own strip is drawn at three softnesses and sharp, each through a gradient of its own,
/// crossing from one to the next along the strip ([EdgeBlurStrip]). What is behind the view is the page's ground,
/// and the strip's own ground is laid over it toward the edge.
///
/// What it costs: one picture of the strip (and as far round it as the strongest blur gathers from) when the view
/// under it is painted, and three blurs of that picture, a band 20 to 64 pixels deep, the softest two of which the
/// engine draws at a fraction of the screen's pixels. Nothing moves in it, so it
/// asks for no frame of its own, and a view at rest is painted once. A view that scrolls is painted at every frame,
/// though, and so is every picture: too much for Android, which draws the blur as a backdrop filter instead, its
/// softness grown by a shader rather than by bands ([edgeLook], lib/art/edge_backdrop.dart).

/// How a platform draws a view's soft edges: the gradient blur through pictures of the view ([blur]); the same blur
/// as a backdrop filter whose shader grows its softness toward the edge, with no picture taken ([backdrop],
/// lib/art/edge_backdrop.dart); or the page's ground laid over the edge and nothing blurred ([fade]).
enum EdgeLook { blur, backdrop, fade }

/// A build's own choice of [EdgeLook], for measuring one against another on the same device
/// (`--dart-define=GHOST_EDGE=fade`, `backdrop` or `blur`, with tool/perf.sh's `PERF_DEFINES`); the platform's own
/// when left out.
const String ghostEdge = String.fromEnvironment('GHOST_EDGE');

/// For a test: the look the edges wear whatever the platform and the engine say.
@visibleForTesting
EdgeLook? debugEdgeLook;

/// The look this platform's edges wear ([EdgeLook]).
///
/// Android draws the blur as a backdrop filter (Matt, 2026-10-25, on the Fold with 2.3.27: "the blur works now but
/// it's super laggy, research if there is a library or something we can use for cleaner blurs, if not use simple
/// gradients on android"). The strips took a picture of the view for every strip at every frame a page scrolled,
/// three or four a frame, and drew each at three softnesses: walked on the ghostflutter2 emulator, a fling down the
/// home page spent 11 ms of each frame's raster on them (a note's 12, a board's 11.5), where the backdrop spent 2.8
/// and the page's ground alone, no blur at all, 2.5 to 2.8; a fling down a long note dropped 70 frames with the
/// strips, 15 with the backdrop and 5 with the fade (build/feature-shots/blur-perf/). The emulator's GPU is the
/// Mac's, not the Fold's: what it tells is the cost of each way against the others. An engine that cannot filter by
/// a shader (Skia, which a test runs on) fades. The Mac, the iPhone and every desktop keep the strips: Impeller on
/// Metal draws them inside a frame, and their look is the one the tests measure (test/art/blur_edge_test.dart).
///
/// The web build keeps the strips too, on every browser's machine (docs/WEB.md): a browser cannot filter by a
/// shader, so a phone's would have faded, and the strips are pictures and blurs that skwasm draws as Skia does. A
/// note scrolled at a desktop's width and a phone's drew its 60 frames a second in Chromium on the Mac's GPU
/// (tool/web_shots.mjs --gpu, 2026-10-26), and the page looks as the Mac app and the iPhone app do.
EdgeLook get edgeLook {
  if (debugEdgeLook case final look?) return look;
  final asked = switch (ghostEdge) {
    'fade' => EdgeLook.fade,
    'blur' => EdgeLook.blur,
    'backdrop' => EdgeLook.backdrop,
    _ => !kIsWeb && defaultTargetPlatform == TargetPlatform.android ? EdgeLook.backdrop : EdgeLook.blur,
  };
  return asked == EdgeLook.backdrop && !ui.ImageFilter.isShaderFilterSupported ? EdgeLook.fade : asked;
}

/// What one strip of a view is drawn through, in place of the view itself: its blur, or a plain fade. [rect] is the
/// strip in the view's own pixels; [reach] is how much further the picture of the view has to run for what the
/// strip draws (a blur gathers from beside it).
@immutable
abstract class EdgeStrip {
  const EdgeStrip();
  Rect get rect;
  double get reach;

  /// Draws the strip over [at], the strip's own rectangle after it was laid on the screen's pixels. [view] is a
  /// picture of the view over [viewRect], at [ratio] of the screen's pixels to a logical one.
  void paint(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio);

  /// Whether the strip can be drawn yet: one that waits for a program (the scene's haze) says so here.
  bool get ready => true;
}

/// A view's own `mask-image` along an axis, the four stops of a `linear-gradient`: clear up to [clearUntil], whole
/// from [wholeFrom] until [wholeUntil], clear again from [clearFrom]. Two stops at one place are a cut; an end with
/// no fade is said as a place no view reaches.
@immutable
class EdgeFade {
  const EdgeFade({this.clearUntil = -1e9, this.wholeFrom = -1e9, this.wholeUntil = 1e9, this.clearFrom = 1e9});
  final double clearUntil, wholeFrom, wholeUntil, clearFrom;

  static const none = EdgeFade();

  /// How much of the view shows at [along] the axis, 0 to 1.
  double at(double along) {
    final rise = wholeFrom > clearUntil ? ((along - clearUntil) / (wholeFrom - clearUntil)).clamp(0.0, 1.0) : (along >= clearUntil ? 1.0 : 0.0);
    final fall = clearFrom > wholeUntil ? ((clearFrom - along) / (clearFrom - wholeUntil)).clamp(0.0, 1.0) : (along < clearFrom ? 1.0 : 0.0);
    return rise * fall;
  }

  @override
  bool operator ==(Object other) =>
      other is EdgeFade && other.clearUntil == clearUntil && other.wholeFrom == wholeFrom && other.wholeUntil == wholeUntil && other.clearFrom == clearFrom;

  @override
  int get hashCode => Object.hash(clearUntil, wholeFrom, wholeUntil, clearFrom);
}

/// An [EdgeFade] as the gradient a stylesheet writes, along [axis] of the view: the ramp in at its start and the
/// ramp out at its end, each a gradient of its own, laid one after the other (their alphas multiply, which is the
/// one mask: whole between the two, clear outside them).
///
/// Each ramp's line is only as long as the ramp. One gradient for the whole mask had four stops a few pixels
/// apart on a line long enough for any view, and an engine that draws a gradient from a table of colours (Impeller
/// on the Mac) put the whole 28 px ramp inside one entry of it: the foot of every page on a desktop was cut off 28 px
/// above the window's edge, where the page's fades to it.
List<ui.Gradient> fadeRamps(EdgeFade fade, Axis axis) {
  const clear = Color(0x00000000), whole = Color(0xFF000000);
  Offset on(double value) => axis == Axis.vertical ? Offset(0, value) : Offset(value, 0);
  // A ramp with no length is an edge: a line one hundredth of a pixel long draws it as one.
  ui.Gradient ramp(double from, double to, Color first, Color last) => ui.Gradient.linear(on(from), on(math.max(to, from + 0.01)), [first, last]);
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

/// A strip that only fades: the view's `mask-image` gradient with nothing under it.
class EdgeFadeStrip extends EdgeStrip {
  const EdgeFadeStrip({required this.rect, required this.fade, this.axis = Axis.vertical});

  @override
  final Rect rect;
  final EdgeFade fade;
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
  bool operator ==(Object other) => other is EdgeFadeStrip && other.rect == rect && other.fade == fade && other.axis == axis;

  @override
  int get hashCode => Object.hash(rect, fade, axis);
}

/// Which edge of its strip a blur is strongest at: the edge the view passes under or runs off.
enum EdgeSide { top, bottom, left, right }

/// How many softnesses a gradient blur is drawn at, the softest reaching furthest in from the edge.
const int edgeBlurLevels = 3;

/// How far in from a gradient blur's inner end its gradient mask is whole, as a share of the strip: the blur is laid
/// over the sharp view through the mask, none of it at the inner end, all of it from here to the edge, and a
/// smoothstep between (Matt, 2026-10-25, on the Fold: "put a small gradient mask over it so the edge doesn't look
/// like it's clipped so hard", and "the mask should be a clipping mask"). The same on every platform: Android's
/// backdrop sets it as its shader's (lib/art/edge_backdrop.dart), and the strips' sharp view gives way to their
/// first softness over it ([EdgeBlurStrip]), which is whole at its own place, a third of the way in.
const double edgeBlurFeather = 1 / edgeBlurLevels;

/// How far past its edge a gradient blur under a header is drawn, in logical pixels ([EdgeBlurStrip.bleed]): under
/// the header, which is painted over the page and hides it. A page is told its header's height as a whole pixel
/// (`--wisp-under`, the web's `offsetHeight`: lib/note/note_screen.dart rounds it, and the home page's header is
/// laid out on its own) where the header itself ends between two of the screen's pixels, and the row between the
/// header's foot and the blur was the page itself, sharp: a line of the words' tops glinting under the header as
/// they passed (Matt, 2026-10-25: "the top blur on the scrolling list on the home page has 1px visible above the
/// blur"; on the ghostflutter2 emulator at 2.625, row 233 under the home page's header and row 353 under a note's
/// tab row). One logical pixel covers a rounding of up to half of one at any density.
const double edgeBlurBleed = 1;

/// The mask's share at [t] of the way from a gradient blur's inner end to its edge, 0 to 1: GLSL's
/// `smoothstep(0, edgeBlurFeather, t)`, as shaders/edge_blur.frag has it.
double edgeBlurMask(double t) {
  final u = (t / edgeBlurFeather).clamp(0.0, 1.0);
  return u * u * (3 - 2 * u);
}

/// A gradient blur: the strip of the view at [edgeBlurLevels] softnesses up to [sigma] and sharp, each shown over
/// a band of its own along the strip and the bands crossing into one another, so the view goes from sharp at the
/// strip's inner end to [sigma] at its edge with no step between. [wash] is the page's ground laid over the blur, as
/// much of it as its alpha at the edge and none at the inner end. [opacity] is how much of the blur (and its wash)
/// shows, on its way to 1 as a page is scrolled under a header. With a [fade], the strip is then faded along its
/// axis as the page's own mask fades it (clear where a dock begins, or under a status bar).
///
/// The softnesses are not laid one over another: a blurred word over the same word sharp is the sharp word with a
/// halo, since a word's ground is clear and its blur is mostly clear too. Each is weighed instead, the weights adding
/// to one at every point, and the pictures added (`BlendMode.plus`): at each row the view is a mix of the two
/// softnesses either side of it, and nothing of the sharp view is left at the edge.
///
/// Each softness is whole at a place of its own, evenly along the strip (the sharp view at the inner end, the
/// softest at the edge), and shares a row only with the next softer or sharper one, so the sharp view is gone a
/// third of the way in (Matt, 2026-10-24, on the Fold: "on android the blur is a gradient instead of a gradient
/// blur"). Until then every softness came in from its own place and stayed to the edge, which left the sharp view's
/// share falling in a straight line over the whole strip: halfway down, half of every word was still there sharp,
/// over a haze too faint to see, and the strip read as the words fading under a wash, not blurring. Nothing about
/// Android drew it so: the emulator's Impeller (OpenGL ES) drew every part of it as the test's engine does, the
/// blurs, the pictures, the cut and the weights, and each row's contrast fell in that same straight line. A word
/// part sharp reads as a sharp word however faint (test/art/blur_edge_test.dart measures the hardness of the edges
/// left, not only how much is left).
///
/// The first softness comes in over the sharp view as the gradient mask does on Android ([edgeBlurFeather], Matt,
/// 2026-10-25: "put a small gradient mask over it so the edge doesn't look like it's clipped so hard"): by a
/// smoothstep rather than a straight line, so the blur starts with no corner at the inner end, and the two
/// platforms' edges come in alike. The strips had no hard start of Android's kind (each softness is a whole blur,
/// with no pass gathering rows less blurred than itself); the curve is the one change.
class EdgeBlurStrip extends EdgeStrip {
  const EdgeBlurStrip({required this.rect, required this.side, required this.sigma, this.wash, this.opacity = 1, this.fade, this.bleed = 0});

  @override
  final Rect rect;
  final EdgeSide side;
  final double sigma;
  final Color? wash;
  final double opacity;
  final EdgeFade? fade;

  /// How far past its edge the strip is drawn, under a header ([edgeBlurBleed]); none where nothing stands over
  /// its edge. Its [rect] is as it is: the wash over it and Android's band keep to it (the band's filter reaches the
  /// bleed past it, at the edge's softness), and where the strips draw it, its gradient runs over [drawn], a pixel
  /// longer.
  final double bleed;

  /// The strip as drawn: its [rect], and [bleed] past its edge.
  Rect get drawn => bleed <= 0
      ? rect
      : switch (side) {
          EdgeSide.top => Rect.fromLTRB(rect.left, rect.top - bleed, rect.right, rect.bottom),
          EdgeSide.bottom => Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom + bleed),
          EdgeSide.left => Rect.fromLTRB(rect.left - bleed, rect.top, rect.right, rect.bottom),
          EdgeSide.right => Rect.fromLTRB(rect.left, rect.top, rect.right + bleed, rect.bottom),
        };

  Axis get _axis => side == EdgeSide.top || side == EdgeSide.bottom ? Axis.vertical : Axis.horizontal;

  @override
  double get reach => (sigma * 3).ceilToDouble();

  /// The strip's inner end and its edge, on the screen's pixels as [at] lies.
  (Offset inner, Offset edge) _ends(Rect at) => switch (side) {
        EdgeSide.top => (at.bottomCenter, at.topCenter),
        EdgeSide.bottom => (at.topCenter, at.bottomCenter),
        EdgeSide.left => (at.centerRight, at.centerLeft),
        EdgeSide.right => (at.centerLeft, at.centerRight),
      };

  /// Where softness [level] (0 the sharp view, [edgeBlurLevels] the softest) is whole, as a share of the way from
  /// the inner end to the edge: evenly along the strip, the sharp view at the inner end and the softest at the edge.
  static double _place(int level) => level / edgeBlurLevels;

  /// How much of softness [level] shows at [t] of the way to the edge, 0 to 1: all of it at its own place, none at
  /// the places of the softnesses either side of it, and a straight line between, but for the first softness coming
  /// in over the sharp view, which is the gradient mask's smoothstep ([edgeBlurMask]). At every point the two that
  /// show add to one.
  static double _share(int level, double t) {
    if (level <= 1 && t < edgeBlurFeather) {
      final mask = edgeBlurMask(t);
      return level == 0 ? 1 - mask : mask;
    }
    return (1 - (t * edgeBlurLevels - level).abs()).clamp(0.0, 1.0);
  }

  /// The gradient's stops: each softness's place, and between the sharp view's and the first softness's as many
  /// more as draw the mask's curve with no corner to be seen (a gradient is straight between two stops).
  static final List<double> _stops = [
    for (var k = 0; k < _maskSteps; k++) edgeBlurFeather * k / _maskSteps,
    for (var level = 1; level <= edgeBlurLevels; level++) _place(level),
  ];
  static const int _maskSteps = 8;

  @override
  void paint(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio) {
    final fade = this.fade;
    final shown = opacity.clamp(0.0, 1.0);
    if (fade != null) canvas.saveLayer(at, Paint());
    canvas.save();
    canvas.clipRect(at, doAntiAlias: false);
    if (shown <= 0 || sigma <= 0) {
      _drawView(canvas, view, viewRect);
    } else {
      final (inner, edge) = _ends(at);
      canvas.saveLayer(at, Paint());
      // Level 0 is the view as it is; level k is the view at k of the levels' share of the sigma. Each is weighed by
      // its share along the strip, a line through the gradient's stops.
      final stops = _stops;
      for (var level = 0; level <= edgeBlurLevels; level++) {
        double weight(double t) {
          final mine = _share(level, t);
          // With the blur only partly shown, the sharp view keeps the rest.
          return level == 0 ? 1 - shown * (1 - mine) : shown * mine;
        }

        canvas.saveLayer(at, Paint()..blendMode = level == 0 ? BlendMode.srcOver : BlendMode.plus);
        final soft = sigma * level / edgeBlurLevels;
        _drawView(canvas, view, viewRect, level == 0 ? null : (Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: soft, sigmaY: soft, tileMode: TileMode.clamp)));
        canvas.drawRect(
          at,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..isAntiAlias = false
            ..shader = ui.Gradient.linear(inner, edge, [for (final t in stops) Color.fromRGBO(0, 0, 0, weight(t).clamp(0.0, 1.0))], stops),
        );
        canvas.restore();
      }
      final wash = this.wash;
      if (wash != null && wash.a > 0) {
        canvas.drawRect(at, Paint()..shader = ui.Gradient.linear(inner, edge, [wash.withValues(alpha: 0), wash.withValues(alpha: wash.a * shown)]));
      }
      canvas.restore();
    }
    canvas.restore();
    if (fade != null) {
      for (final ramp in fadeRamps(fade, _axis)) {
        canvas.drawRect(at, Paint()..blendMode = BlendMode.dstIn..shader = ramp..isAntiAlias = false);
      }
      canvas.restore();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is EdgeBlurStrip &&
      other.rect == rect &&
      other.side == side &&
      other.sigma == sigma &&
      other.wash == wash &&
      other.opacity == opacity &&
      other.fade == fade &&
      other.bleed == bleed;

  @override
  int get hashCode => Object.hash(rect, side, sigma, wash, opacity, fade, bleed);
}

/// How much of the page's ground a faded edge ([EdgeLook.fade]) lays at its very edge, where a blur's wash is
/// [EdgeBlurStrip.wash]: with nothing blurred under it, the words have to go further into the ground to be gone
/// (a plain build's shade, lib/art/blur_edge.dart `PlainShade`, is as much).
const double edgeFadeWash = 0.92;

/// The strips of a view laid over it as the page's [ground] alone, where [EdgeLook.fade] has them, and over the
/// backdrop's blur ([EdgeLook.backdrop], with the blur's own [wash]): no picture of the view and no layer, two or
/// three gradients a frame. Each [EdgeBlurStrip] is its wash, from none at its inner end
/// to [wash] of the ground at its edge (as much of it as the strip's opacity), and wherever a strip's own mask
/// ([EdgeFade]) would clear the view, the ground stands in its place: what is behind the view is the page's ground.
class EdgeShade extends CustomPainter {
  const EdgeShade({required this.strips, required this.ground, this.wash = edgeFadeWash});

  final List<EdgeStrip> strips;
  final Color ground;
  final double wash;

  @override
  void paint(Canvas canvas, Size size) {
    for (final strip in strips) {
      final rect = strip.rect;
      if (rect.isEmpty) continue;
      canvas.save();
      canvas.clipRect(rect, doAntiAlias: false);
      if (strip is EdgeBlurStrip) {
        final (inner, edge) = strip._ends(rect);
        final most = wash * strip.opacity.clamp(0.0, 1.0);
        if (most > 0) canvas.drawRect(rect, Paint()..shader = ui.Gradient.linear(inner, edge, [ground.withValues(alpha: 0), ground.withValues(alpha: most)]));
      }
      final (fade, axis) = switch (strip) {
        EdgeBlurStrip(:final fade, :final side) => (fade, side == EdgeSide.top || side == EdgeSide.bottom ? Axis.vertical : Axis.horizontal),
        EdgeFadeStrip(:final fade, :final axis) => (fade, axis),
        _ => (null, Axis.vertical),
      };
      if (fade != null) _cleared(canvas, rect, fade, axis);
      canvas.restore();
    }
  }

  /// The ground where [fade] clears the view over [rect]: whole where the view is gone, none where it is whole.
  void _cleared(Canvas canvas, Rect rect, EdgeFade fade, Axis axis) {
    const nowhere = 1e8;
    Offset on(double value) => axis == Axis.vertical ? Offset(rect.left, value) : Offset(value, rect.top);
    final start = axis == Axis.vertical ? rect.top : rect.left, end = axis == Axis.vertical ? rect.bottom : rect.right;
    Rect span(double from, double to) => axis == Axis.vertical ? Rect.fromLTRB(rect.left, from, rect.right, to) : Rect.fromLTRB(from, rect.top, to, rect.bottom);
    final whole = ground, none = ground.withValues(alpha: 0);
    if (fade.wholeFrom > -nowhere && fade.wholeFrom > start) {
      final until = math.max(start, fade.clearUntil);
      if (until > start) canvas.drawRect(span(start, until), Paint()..color = whole);
      canvas.drawRect(span(until, math.min(end, fade.wholeFrom)), Paint()..shader = ui.Gradient.linear(on(fade.clearUntil), on(math.max(fade.wholeFrom, fade.clearUntil + 0.01)), [whole, none]));
    }
    if (fade.wholeUntil < nowhere && fade.wholeUntil < end) {
      final from = math.min(end, fade.clearFrom);
      canvas.drawRect(span(math.max(start, fade.wholeUntil), from), Paint()..shader = ui.Gradient.linear(on(fade.wholeUntil), on(math.max(fade.clearFrom, fade.wholeUntil + 0.01)), [none, whole]));
      if (from < end) canvas.drawRect(span(from, end), Paint()..color = whole);
    }
  }

  @override
  bool shouldRepaint(EdgeShade old) => old.ground != ground || old.wash != wash || !listEquals(old.strips, strips);
}

/// [child] seen through the masks of [strips] alone ([EdgeFade], the stylesheet's `mask-image`), with nothing
/// blurred: where the edges are not the strips' ([EdgeLook.backdrop], [EdgeLook.fade]), a box's ends (a board lane's
/// foot, the tab row's ends), whose ground is not the page's to lay over them and whose fade to clear no backdrop
/// filter can be drawn through. A mask layer for each ramp of each mask (fadeRamps: one gradient for both ends of a
/// box is drawn from too coarse a table on the Mac), pushed as the box paints, so an end that opens or shuts builds
/// nothing again; no picture is taken of the box, and a scroller inside it moves under the masks without painting
/// them again. Where the engine filters by a shader ([EdgeLook.backdrop]) the box's blur is laid over this, as
/// backdrop bands that clear toward the edge as the mask does (blur_box.dart).
class EdgeMasked extends SingleChildRenderObjectWidget {
  const EdgeMasked({super.key, required this.strips, super.child});

  final List<EdgeStrip> strips;

  @override
  RenderEdgeMasked createRenderObject(BuildContext context) => RenderEdgeMasked(strips: strips);

  @override
  void updateRenderObject(BuildContext context, RenderEdgeMasked renderObject) => renderObject.strips = strips;
}

class RenderEdgeMasked extends RenderProxyBox {
  RenderEdgeMasked({required List<EdgeStrip> strips}) : _strips = strips;

  List<EdgeStrip> _strips;
  List<EdgeStrip> get strips => _strips;
  set strips(List<EdgeStrip> value) {
    if (listEquals(value, _strips)) return;
    final had = _strips.isNotEmpty;
    _strips = value;
    if (had != value.isNotEmpty) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  /// Each mask's ramps, in the box's own pixels: two strips of one mask (a row's two ends) are one mask.
  List<ui.Gradient> get _ramps {
    final masks = <(EdgeFade, Axis)>{
      for (final strip in _strips)
        if (strip case EdgeBlurStrip(:final fade?, :final side))
          (fade, side == EdgeSide.top || side == EdgeSide.bottom ? Axis.vertical : Axis.horizontal)
        else if (strip case EdgeFadeStrip(:final fade, :final axis))
          (fade, axis),
    };
    return [for (final (fade, axis) in masks) ...fadeRamps(fade, axis)];
  }

  @override
  bool get alwaysNeedsCompositing => _strips.isNotEmpty;

  @override
  void paint(PaintingContext context, Offset offset) {
    final ramps = _ramps;
    if (child == null || ramps.isEmpty) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    void masked(PaintingContext context, Offset offset, int index) {
      if (index == ramps.length) {
        context.paintChild(child!, offset);
        return;
      }
      context.pushLayer(
        ShaderMaskLayer()
          ..shader = ramps[index]
          ..maskRect = offset & size
          ..blendMode = BlendMode.dstIn,
        (context, offset) => masked(context, offset, index + 1),
        offset,
      );
    }

    masked(context, offset, 0);
  }
}

/// The budget a strip's picture is held to, in the screen's own pixels: a region past it keeps its plain edge.
const int edgePictureBudget = 1 << 24;

/// Whether a region [across] by [down] logical pixels fits [edgePictureBudget], counted in the screen's own pixels.
///
/// The budget was found in WebKit, which paints an element black when its filter's region is over 2^24 device
/// pixels. Nothing here goes black; it is kept as the same guard on the same sizes, since what it guards here is
/// the size of the pictures a strip is drawn through.
bool withinPictureBudget(double across, double down, double ratio) {
  final dots = ratio > 0 ? ratio : 1.0;
  return (across * dots).ceil() * (down * dots).ceil() <= edgePictureBudget;
}

/// [rect] grown out to whole screen pixels, on the grid that has a pixel's corner at [corner]: a picture taken of it
/// and drawn back lands pixel on pixel.
Rect snapOut(Rect rect, Offset corner, double ratio) {
  double down(double value, double from) => from + ((value - from) * ratio + 1e-4).floorToDouble() / ratio;
  double up(double value, double from) => from + ((value - from) * ratio - 1e-4).ceilToDouble() / ratio;
  return Rect.fromLTRB(down(rect.left, corner.dx), down(rect.top, corner.dy), up(rect.right, corner.dx), up(rect.bottom, corner.dy));
}

/// How many pictures of a view the strips have asked for: for a test.
@visibleForTesting
int debugEdgePictures = 0;

/// Draws [child] with some strips of it taken through [strips]: the render side of every edge's blur.
///
/// The child paints as it always does; where a strip lies, the child is cut away and the strip is drawn from a
/// picture of the child taken for it. With no strips this is the child and nothing more: no layer, no picture.
class EdgeStrips extends SingleChildRenderObjectWidget {
  const EdgeStrips({super.key, required this.strips, this.repaint, super.child});

  final List<EdgeStrip> strips;

  /// Told when what the strips draw changes without the widget being built again.
  final Listenable? repaint;

  @override
  RenderEdgeStrips createRenderObject(BuildContext context) => RenderEdgeStrips(strips: strips, ratio: MediaQuery.devicePixelRatioOf(context), repaint: repaint);

  @override
  void updateRenderObject(BuildContext context, RenderEdgeStrips renderObject) {
    renderObject
      ..strips = strips
      ..ratio = MediaQuery.devicePixelRatioOf(context)
      ..repaint = repaint;
  }
}

class RenderEdgeStrips extends RenderProxyBox {
  RenderEdgeStrips({required List<EdgeStrip> strips, required double ratio, Listenable? repaint})
      : _strips = strips,
        _ratio = ratio,
        _repaint = repaint;

  List<EdgeStrip> _strips;
  List<EdgeStrip> get strips => _strips;
  set strips(List<EdgeStrip> value) {
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
    _placed.remove(this);
    super.detach();
  }

  /// The views whose strips were laid on the screen's pixels at their last paint, and where each then stood.
  static final Map<RenderEdgeStrips, Offset> _placed = {};
  static bool _watching = false;

  /// Remembers where this view's strips were laid, and from then on looks after every frame whether any such view
  /// has since been moved to another place between the screen's pixels without being painted: under a repaint
  /// boundary (lib/art/blur_box.dart) a view is moved by whatever holds it and keeps its picture, and its strips'
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
  List<EdgeStrip> get debugPainted => _painted;
  List<EdgeStrip> _painted = const [];

  @override
  void paint(PaintingContext context, Offset offset) {
    final drawn = [
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
    _place(phase);
    final stripLayer = (layer as _EdgeStripLayer?) ?? _EdgeStripLayer();
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

class _EdgeStripLayer extends OffsetLayer {
  List<EdgeStrip> _strips = const [];
  set strips(List<EdgeStrip> value) {
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
    // A strip under a header reaches past its edge under the header ([EdgeBlurStrip.bleed]), which hides it.
    final at = [for (final strip in _strips) snapOut(strip is EdgeBlurStrip ? strip.drawn : strip.rect, _corner, _ratio)];
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

    // Each strip from a picture of its own, the strip's size and its reach round it: a page's top and its foot stand
    // at the two ends of the view, and one picture holding both would be as tall as the page.
    for (var i = 0; i < _strips.length; i++) {
      final rect = at[i];
      if (rect.isEmpty || rect.width <= 0 || rect.height <= 0) continue;
      final strip = _strips[i];
      final view = _picture(snapOut(rect.inflate(strip.reach), _corner, _ratio));
      if (ghostPerf) Perf.count('edge.strips');
      final recorder = ui.PictureRecorder();
      strip.paint(Canvas(recorder), rect, view.image, view.rect, _ratio);
      final picture = recorder.endRecording();
      builder.addPicture(Offset.zero, picture);
      picture.dispose();
      view.image.dispose();
    }

    builder.pop();
  }

  /// The children as a picture of [rect] of the view (on the screen's pixels), at the screen's own pixels.
  ({ui.Image image, Rect rect}) _picture(Rect rect) {
    final builder = ui.SceneBuilder();
    final transform = Matrix4.diagonal3Values(_ratio, _ratio, 1)..translateByDouble(-rect.left, -rect.top, 0, 1);
    builder.pushTransform(transform.storage);
    addChildrenToScene(builder);
    builder.pop();
    final scene = builder.build();
    debugEdgePictures += 1;
    if (ghostPerf) Perf.count('edge.pictures');
    try {
      return (image: scene.toImageSync(math.max(1, (rect.width * _ratio).round()), math.max(1, (rect.height * _ratio).round())), rect: rect);
    } finally {
      scene.dispose();
    }
  }
}
