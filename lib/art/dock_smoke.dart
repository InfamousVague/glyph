import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'turbulence.dart';
import 'wisp_edge.dart';
import 'wisp_kit.dart';
import 'wisp_mask.dart';
import 'wisp_probe.dart';
import 'wisp_settings.dart';
import 'wisp_smoke.dart';
import 'wisp_strips.dart';

/// The wisp around the home page's floating dock (art/dockSmoke.ts, home/HomeScreen.module.css `.dockHalo`): what
/// scrolls toward the dock is softened and washed toward the page's paper, and the halo's edge is the header's
/// smoke - turbulence over a soft ramp, torn into tendrils - wrapped round the dock's pill.
///
/// Three mask layers, as the stylesheet composes them: a soft core that keeps the halo whole at the pill, added to
/// a wider ramp cut by a tile of smoke. Only the tile slides, with the page's own drift ([WispDrift.follow]), so
/// the tendrils past the core sway while the halo keeps its shape. And on a phone the halo bends what scrolls
/// behind it with the foot's own noise at the foot's strength, breathed by the same drift ([dockBends]).

/// How far past the pill the smoke reaches, in px: the halo's inset (`DOCK_SMOKE_REACH`).
const double dockSmokeReach = 48;

/// The smoke tile's side, in px (`DOCK_SMOKE_TILE`).
const double dockSmokeTileSide = 256;

/// The halo's blur where it does not bend, and how much of the page's ground washes over it: bent, a lighter wash,
/// or the paper would hide the bend it is there to show (`.dockHalo`, `.dockHalo[data-bend]`).
const double dockHaloBlur = 14;
const double dockHaloWash = 0.70;
const double dockHaloWashBent = 0.35;

/// `#dockWisp` of art/WispEdgeFilter.tsx: the foot's strength, and the softening after it.
const double dockBendScale = 23;
const double dockBendBlur = 1.6;

/// `feFuncA type="table"` of the tile: gentler than the header's, leaving tendrils and clear between them.
const List<double> dockSmokeCurve = [0, 0, 0.05, 0.5, 0.95, 1, 1];

/// A pill for a halo [width] by [height] whose dock stands [reach] in from every side (`softPill`): where it is
/// drawn, and the blur that softens it.
({RRect pill, double soft}) _softPill(double width, double height, double reach, double out, double soft) {
  final w = math.max(1.0, width.roundToDouble()), h = math.max(1.0, height.roundToDouble());
  final inset = math.max(0.0, reach - out);
  final innerW = math.max(1.0, w - 2 * inset), innerH = math.max(1.0, h - 2 * inset);
  return (pill: RRect.fromRectAndRadius(Rect.fromLTWH(inset, inset, innerW, innerH), Radius.circular(math.min(innerW, innerH) / 2)), soft: soft);
}

/// The halo's core (`dockSmokeCore`): whole at the dock's edge and gone a third of the reach out, so the pill never
/// stands on a hole.
({RRect pill, double soft}) dockSmokeCore(double width, double height, [double reach = dockSmokeReach]) =>
    _softPill(width, height, reach, (reach * 0.12).roundToDouble(), math.max(1, (reach * 0.1).roundToDouble()));

/// The ramp the smoke is cut from (`dockSmokeRamp`): strong near the dock, nothing by the halo's edge.
({RRect pill, double soft}) dockSmokeRamp(double width, double height, [double reach = dockSmokeReach]) =>
    _softPill(width, height, reach, (reach * 0.5).roundToDouble(), math.max(1, (reach * 0.2).roundToDouble()));

/// Draws a pill of [dockSmokeCore] or [dockSmokeRamp] in ink, soft at its edge: alpha is what a mask reads.
void paintDockPill(Canvas canvas, ({RRect pill, double soft}) shape, {Paint? paint}) {
  canvas.drawRRect(shape.pill, (paint ?? Paint())..color = const Color(0xFF000000)..maskFilter = MaskFilter.blur(BlurStyle.normal, shape.soft));
}

final Turbulence _tileNoise = Turbulence(7);
const TurbulenceTile _tileBox = TurbulenceTile(dockSmokeTileSide, dockSmokeTileSide);

/// The tile's alpha at a point of it, 0 to 1 (`dockSmokeTile`): the header's turbulence, stitched so it repeats
/// with no seam, its red taken to alpha through [dockSmokeCurve].
double dockSmokeTileAlpha(double x, double y) =>
    tableTransfer(dockSmokeCurve, _tileNoise.sample(0, x + 0.5, y + 0.5, baseFrequencyX: 0.035, baseFrequencyY: 0.035, octaves: 3, tile: _tileBox));

/// The tile as pixels, [ratio] to each of its own.
Uint8List dockSmokeTilePixels({int ratio = 2}) {
  final side = (dockSmokeTileSide * ratio).round();
  final out = Uint8List(side * side * 4);
  for (var py = 0; py < side; py++) {
    for (var px = 0; px < side; px++) {
      out[(py * side + px) * 4 + 3] = (dockSmokeTileAlpha((px + 0.5) / ratio, (py + 0.5) / ratio) * 255).round();
    }
  }
  return out;
}

ui.Image? _tile;
Future<ui.Image>? _tileComing;

/// The tile if it has been made.
ui.Image? dockSmokeTileNow() => _tile;

/// The tile, made once.
Future<ui.Image> dockSmokeTile({int ratio = 2}) {
  return _tileComing ??= () {
    final done = Completer<ui.Image>();
    final side = (dockSmokeTileSide * ratio).round();
    ui.decodeImageFromPixels(dockSmokeTilePixels(ratio: ratio), side, side, ui.PixelFormat.rgba8888, (image) {
      _tile = image;
      done.complete(image);
    });
    return done.future;
  }();
}

/// The halo as a strip of what lies behind the dock: that strip softened (or bent, then softened a little), washed
/// with the page's ground, and shown through the three-layer mask.
///
/// On the page this is an element with a `backdrop-filter` and a `mask-image`. A backdrop filter cannot be shown
/// through a mask in this engine, so the halo is drawn from a picture of the view behind the dock instead
/// (wisp_strips.dart), which is the same thing wherever the only thing behind the dock is that view.
class DockHaloStrip extends WispStrip {
  const DockHaloStrip({required this.rect, required this.ground, required this.bends, required this.frequency, required this.slide, required this.tile, this.reach48 = dockSmokeReach});

  /// The halo's own box: the dock's, grown by the reach on every side.
  @override
  final Rect rect;

  /// The page's ground, which washes over the halo.
  final Color ground;
  final bool bends;

  /// The bend's noise, breathed by the page's drift, and how far the smoke's tile has slid with it.
  final Offset frequency;
  final Offset slide;
  final ui.Image? tile;
  final double reach48;

  @override
  double get reach => bends ? 2 * (dockBendScale / 2).ceilToDouble() : (dockHaloBlur * 3).ceilToDouble();

  @override
  bool get ready => tile != null && (!bends || WispKit.maybe?.tableNow(3) != null);

  /// What the bending halo softens: the foot's noise at the foot's strength over the whole box, breathed by the
  /// page's drift and not slid.
  WispSmoke get _smoke => WispSmoke(seed: 3, frequency: frequency, slide: rect.topLeft, lipA: 1e9, bend: dockBendScale, blur: dockBendBlur);

  @override
  bool get shares => wispQuick && bends;

  @override
  WispSoftAsk? softAsk(Rect at, ui.Image view, Rect viewRect, double ratio) =>
      wispQuick && bends ? WispSoftAsk(table: WispKit.maybe!.tableNow(3)!, source: view, sourceRect: viewRect, bentRect: at, smoke: _smoke) : null;

  @override
  void paintSoft(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio, ({ui.Image image, Rect rect}) soft) => _paintQuick(canvas, at, view, viewRect, ratio, soft);

  @override
  void paint(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio) {
    if (wispQuick && bends) {
      _paintQuick(canvas, at, view, viewRect, ratio, null);
      return;
    }
    final whole = Rect.fromLTWH(0, 0, view.width.toDouble(), view.height.toDouble());
    canvas.save();
    canvas.clipRect(at, doAntiAlias: false);
    canvas.drawImageRect(view, whole, viewRect, Paint());
    canvas.saveLayer(at, Paint());

    paintDockBackdrop(canvas, at: at, halo: rect, view: view, viewRect: viewRect, ratio: ratio, bends: bends, frequency: frequency);
    canvas.drawRect(at, Paint()..color = ground.withValues(alpha: bends ? dockHaloWashBent : dockHaloWash));

    // The mask: the core, added to the ramp where the tile is.
    canvas.saveLayer(at, Paint()..blendMode = BlendMode.dstIn);
    canvas.translate(rect.left, rect.top);
    final box = Offset.zero & rect.size;
    canvas.saveLayer(box, Paint());
    paintDockPill(canvas, dockSmokeRamp(rect.width, rect.height, reach48));
    final picture = tile!;
    final matrix = Matrix4.translationValues(slide.dx, slide.dy, 0)..scaleByDouble(dockSmokeTileSide / picture.width, dockSmokeTileSide / picture.height, 1, 1);
    final shader = ui.ImageShader(picture, TileMode.repeated, TileMode.repeated, matrix.storage, filterQuality: FilterQuality.low);
    canvas.drawRect(box, Paint()..shader = shader..blendMode = BlendMode.dstIn);
    shader.dispose();
    canvas.restore();
    paintDockPill(canvas, dockSmokeCore(rect.width, rect.height, reach48));
    canvas.restore();

    canvas.restore();
    canvas.restore();
  }

  /// The bending halo in one pass (shaders/wisp_halo.frag), where [paint] composes it as the stylesheet does, in
  /// three layers over a picture of the bent view and a blur of that: eight pictures the engine made on every frame
  /// of a scroll, for a patch of the screen round the dock. Here there are two small ones, the view behind the dock
  /// bent at half the screen's pixels and that softened (lib/art/wisp_smoke.dart `wispHaze`), and the two pills of
  /// the mask are a picture made once for the dock's size ([_pills]).
  void _paintQuick(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio, ({ui.Image image, Rect rect})? made) {
    final kit = WispKit.maybe!;
    final soft = made ?? wispHaze(kit: kit, table: kit.tableNow(3)!, source: view, sourceRect: viewRect, bentRect: at, ratio: ratio, smoke: _smoke);
    final pills = _pills(rect.size, reach48);
    final shader = kit.halo(
      source: view,
      sourceRect: viewRect,
      soft: soft.image,
      softRect: soft.rect,
      pills: pills,
      // The pills' picture is whole pixels, a pixel to the logical one, from the halo's corner.
      halo: rect.topLeft & Size(pills.width.toDouble(), pills.height.toDouble()),
      tile: tile!,
      tileSide: dockSmokeTileSide,
      slide: slide,
      wash: ground.withValues(alpha: dockHaloWashBent),
      origin: at.topLeft,
    );
    canvas.save();
    canvas.translate(at.left, at.top);
    canvas.drawRect(Offset.zero & at.size, Paint()..shader = shader..isAntiAlias = false);
    canvas.restore();
    if (made == null) soft.image.dispose();
  }

  static ui.Image? _pillsImage;
  static (Size, double)? _pillsFor;

  /// The mask's two pills for a halo of [size], as one picture a pixel to the logical one: the ramp in red and the
  /// core in green, each soft at its edge ([dockSmokeRamp], [dockSmokeCore]). Made when the dock's size changes,
  /// which is when the dock gains a button or the Fold opens, and kept between.
  static ui.Image _pills(Size size, double reach) {
    final had = _pillsImage;
    if (had != null && _pillsFor == (size, reach)) return had;
    had?.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final (shape, color) in [(dockSmokeRamp(size.width, size.height, reach), const Color(0xFFFF0000)), (dockSmokeCore(size.width, size.height, reach), const Color(0xFF00FF00))]) {
      canvas.drawRRect(shape.pill, Paint()..color = color..blendMode = BlendMode.plus..maskFilter = MaskFilter.blur(BlurStyle.normal, shape.soft));
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(math.max(1, size.width.ceil()), math.max(1, size.height.ceil()));
    picture.dispose();
    _pillsFor = (size, reach);
    return _pillsImage = image;
  }

  @override
  bool operator ==(Object other) =>
      other is DockHaloStrip &&
      other.rect == rect &&
      other.ground == ground &&
      other.bends == bends &&
      other.frequency == frequency &&
      other.slide == slide &&
      identical(other.tile, tile) &&
      other.reach48 == reach48;

  @override
  int get hashCode => Object.hash(rect, ground, bends, frequency, slide, tile, reach48);
}

/// What is behind the dock, through the halo's `backdrop-filter`: bent by `#dockWisp` and softened a little where
/// the halo bends, blurred where it does not. [halo] is the halo's own box, whose corner the filter's noise is laid
/// from (it is not slid); [at] is that box on the screen's pixels.
void paintDockBackdrop(Canvas canvas, {required Rect at, required Rect halo, required ui.Image view, required Rect viewRect, required double ratio, required bool bends, Offset frequency = wispBaseFrequency}) {
  final whole = Rect.fromLTWH(0, 0, view.width.toDouble(), view.height.toDouble());
  if (!bends) {
    canvas.drawImageRect(view, whole, viewRect, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: dockHaloBlur, sigmaY: dockHaloBlur, tileMode: TileMode.clamp));
    return;
  }
  final kit = WispKit.maybe!;
  final smoke = WispSmoke(seed: 3, frequency: frequency, slide: halo.topLeft, lipA: 1e9, bend: dockBendScale, blur: dockBendBlur);
  final bentRect = snapOut(at, at.topLeft, ratio);
  final bent = wispBent(kit: kit, table: kit.tableNow(3)!, source: view, sourceRect: viewRect, bentRect: bentRect, ratio: ratio, smoke: smoke);
  canvas.drawImageRect(
    bent,
    Rect.fromLTWH(0, 0, bent.width.toDouble(), bent.height.toDouble()),
    bentRect,
    Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: dockBendBlur, sigmaY: dockBendBlur, tileMode: TileMode.clamp),
  );
  bent.dispose();
}

/// The halo round a dock at [dock] of [child], which is what scrolls behind it (`useDockSmoke`, with the halo's
/// own styles): the low half of [DockSmoke], for a screen that places its dock itself and knows where.
///
/// Nothing is drawn while [dock] is null, or smaller than a pill: until a dock is measured the page's halo keeps a
/// plain feather, which nobody sees for longer than a frame and is not drawn here.
class DockHalo extends StatefulWidget {
  const DockHalo({super.key, required this.dock, required this.child});

  /// The dock's own box, in [child]'s.
  final Rect? dock;
  final Widget child;

  @override
  State<DockHalo> createState() => _DockHaloState();
}

class _DockHaloState extends State<DockHalo> {
  final ValueNotifier<int> _ready = ValueNotifier(0);
  VoidCallback? _unfollow;
  Offset _slide = Offset.zero;
  Offset _frequency = wispBaseFrequency;

  @override
  void initState() {
    super.initState();
    WispSettings.instance.addListener(_changed);
    dockSmokeTile().then((_) => _changed());
    WispKit.load().then((_) => _changed());
    // Written on the halo alone, as the header's slide is written on its own views.
    _unfollow = WispDrift.instance.follow((dx, dy, frequency) {
      if (!mounted) return;
      setState(() {
        _slide = Offset(dx, dy);
        _frequency = frequency;
      });
    });
  }

  @override
  void dispose() {
    WispSettings.instance.removeListener(_changed);
    _unfollow?.call();
    _ready.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    _ready.value += 1;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dock = widget.dock;
    final strips = <WispStrip>[];
    if (dock != null && dock.width >= 2 && dock.height >= 2 && !WispProbe.has('nodock')) {
      final tokens = GlacierTheme.maybeOf(context);
      strips.add(DockHaloStrip(
        rect: dock.inflate(dockSmokeReach),
        ground: tokens?.color('glacier-bg') ?? const Color(0xFF000000),
        bends: dockBends() && !MediaQuery.of(context).disableAnimations,
        frequency: _frequency,
        slide: _slide,
        tile: dockSmokeTileNow(),
      ));
    }
    return WispStrips(strips: strips, repaint: _ready, child: widget.child);
  }
}

/// A dock floating over what scrolls behind it, with the wisp round it: [behind] fills the box, [dock] is laid
/// over it at [alignment] inside [padding], and the halo is drawn round wherever that puts it. The home page's
/// dock, with its scroller.
class DockSmoke extends StatefulWidget {
  const DockSmoke({super.key, required this.behind, required this.dock, this.alignment = Alignment.bottomCenter, this.padding = EdgeInsets.zero});

  final Widget behind;
  final Widget dock;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;

  @override
  State<DockSmoke> createState() => _DockSmokeState();
}

class _DockSmokeState extends State<DockSmoke> {
  final GlobalKey _dock = GlobalKey();
  Rect? _rect;

  /// Where the dock was laid, read once the frame that laid it is done: its size is the dock's own (two buttons or
  /// four, a phone or the Fold), so it is measured, as the page measures the halo.
  void _measure() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dock = _dock.currentContext?.findRenderObject();
      final box = context.findRenderObject();
      if (dock is! RenderBox || box is! RenderBox || !dock.hasSize) return;
      final rect = dock.localToGlobal(Offset.zero, ancestor: box) & dock.size;
      if (rect != _rect) setState(() => _rect = rect);
    });
  }

  @override
  Widget build(BuildContext context) {
    _measure();
    return Stack(
      fit: StackFit.expand,
      children: [
        DockHalo(dock: _rect, child: widget.behind),
        Padding(
          padding: widget.padding,
          child: Align(
            alignment: widget.alignment,
            child: NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (_) {
                _measure();
                return false;
              },
              child: SizeChangedLayoutNotifier(child: KeyedSubtree(key: _dock, child: widget.dock)),
            ),
          ),
        ),
      ],
    );
  }
}
