import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../perf/frame_log.dart' show Perf, ghostPerf;
import 'wisp_kit.dart';
import 'wisp_probe.dart';
import 'wisp_settings.dart';

/// A smoke filter, drawn: the chain of primitives art/wispBox.ts `smokeFrom` and art/WispEdgeFilter.tsx write, from
/// the picture of a view to the picture of it smoking.
///
/// 1. `bent`: the view thrown about by the noise where the band is;
/// 2. `soft`: the bent view under `feGaussianBlur`, and `near`: the bent view's ink widened by `feMorphology`;
/// 3. the merge: the view, the bent view in the band, and the blur kept near the bent strokes, under the view's own
///    fade.
///
/// Drawn in one pass over the strip (shaders/wisp_smoke.frag): each pixel reads the view where the noise throws
/// it, so no picture of the bent view is made at the screen's size, and the soft half of the smoke (2) comes from
/// two small pictures, the bent view drawn at a half or a quarter of the screen's pixels and that blurred and kept
/// near its ink (shaders/wisp_haze.frag). A blur has nothing in it finer than itself, so it loses nothing by being
/// made small; the bent words are the same pixels [paintWispSmokeExact] draws.
///
/// Why: the three-pass drawing made two pictures the size of the strip on every frame of a scroll and read one of
/// them forty-nine times a pixel, and a phone's screen is two thousand pixels across and drawn a hundred and twenty
/// times a second. Measured on the Mac (tool/perf.sh, the phone's drawing asked for with `GHOST_PERF_SMOKE=phone`)
/// and held to the old drawing by pictures side by side (test/art/smoke_compare_test.dart).
///
/// Everything is in the view's own logical pixels; [ratio] is the screen's pixels to one of them. The rectangles are
/// taken as they are given, so a caller who wants the result pixel for pixel hands in ones that lie on the screen's
/// grid ([snapOut]).
void paintWispSmoke(
  Canvas canvas, {
  required WispKit kit,
  required ui.Image table,
  required ui.Image source,
  required Rect sourceRect,
  required Rect rect,
  required Rect bentRect,
  required double ratio,
  required WispSmoke smoke,
  ({ui.Image image, Rect rect})? soft,
}) {
  if (!wispQuick) {
    paintWispSmokeExact(canvas, kit: kit, table: table, source: source, sourceRect: sourceRect, rect: rect, bentRect: bentRect, ratio: ratio, smoke: smoke);
    return;
  }
  // The soft half as it was made with a page's others ([wispSoftSheet]), or made here for this smoke alone.
  final haze = soft ?? wispHaze(kit: kit, table: table, source: source, sourceRect: sourceRect, bentRect: bentRect, ratio: ratio, smoke: smoke);
  final field = wispNoiseField(kit: kit, table: table, bentRect: bentRect, smoke: smoke);
  final shader = kit.smoke(source: source, sourceRect: sourceRect, bentRect: bentRect, haze: haze.image, hazeRect: haze.rect, field: field.image, fieldRect: field.rect, origin: rect.topLeft, smoke: smoke);
  canvas.save();
  canvas.translate(rect.left, rect.top);
  // Hard edged, as the clip that keeps the view out of this rectangle is: the two then meet on one line of pixels.
  canvas.drawRect(Offset.zero & rect.size, Paint()..shader = shader..isAntiAlias = false);
  canvas.restore();
  if (soft == null) haze.image.dispose();
}

/// The noise of [smoke]'s seed as the picture the one-pass drawing reads its bend from (shaders/wisp_field.frag):
/// a stretch of the noise's own space, in its cells, wide enough for [smoke] over [bentRect]. The answer's rectangle
/// is the stretch the picture holds.
///
/// One picture for a seed, whatever the smoke's frequency and wherever its drift has slid it: a smoke reads the
/// noise at its pixel's place less the slide, times the frequency, and that is a place in the noise's own space
/// (shaders/wisp_smoke.frag), so a drift that slides the noise and breathes its frequency moves where the picture
/// is read and makes no picture. The first drawing of this made the noise over each strip in the strip's own
/// pixels and so made it again at every step of the drift, for each strip: on the phone, 182 pictures in the 242
/// frames of a drag down the home page, each a task of its own before the frame. Made again only when a smoke
/// asks for a stretch it does not hold (a wider window, a page's first smoke), and then with room to spare.
({ui.Image image, Rect rect}) wispNoiseField({required WispKit kit, required ui.Image table, required Rect bentRect, required WispSmoke smoke}) {
  // The stretch [smoke] reads: its bent rectangle (inside the noise's own subregion), slid and at its frequency.
  final over = bentRect.intersect(smoke.noiseRect).shift(-smoke.slide + const Offset(0.5, 0.5));
  final need = Rect.fromLTRB(over.left * smoke.frequency.dx, over.top * smoke.frequency.dy, over.right * smoke.frequency.dx, over.bottom * smoke.frequency.dy).inflate(1);
  final had = _fields[smoke.seed];
  if (had != null && had.rect.left <= need.left && had.rect.top <= need.top && had.rect.right >= need.right && had.rect.bottom >= need.bottom) return had;
  if (ghostPerf) Perf.count('wisp.fields');
  debugWispFields += 1;
  // What is held already and what is asked, out to whole eights of a cell and a fifth more each way: a frequency
  // that breathes a sixth and a slide of a few pixels stay inside it.
  final both = had == null ? need : had.rect.expandToInclude(need);
  final grown = both.inflate(math.max(both.width, both.height) * 0.2);
  final rect = Rect.fromLTRB((grown.left / 8).floor() * 8.0, (grown.top / 8).floor() * 8.0, (grown.right / 8).ceil() * 8.0, (grown.bottom / 8).ceil() * 8.0);
  // Twenty-five pixels to a cell, the finer octave's cell being half of one: as fine down a page as the first
  // drawing's picture was on a phone, and no bigger than 2048 either way.
  final texel = math.max(0.04, math.max(rect.width, rect.height) / 2048);
  final wide = math.max(1, (rect.width / texel).ceil()), tall = math.max(1, (rect.height / texel).ceil());
  final held = rect.topLeft & Size(wide * texel, tall * texel);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(1 / texel);
  canvas.drawRect(Offset.zero & held.size, Paint()..shader = kit.noise(origin: held.topLeft, table: table)..isAntiAlias = false..blendMode = BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(wide, tall);
  picture.dispose();
  had?.image.dispose();
  return _fields[smoke.seed] = (image: image, rect: held);
}

final Map<int, ({ui.Image image, Rect rect})> _fields = {};

/// The program a view's layers go through for its smokes (shaders/wisp_through.frag): measuring only. [view] is the
/// rectangle of the view the filter is given a picture of. Null where one program cannot say them: more than two,
/// or of two seeds, axes or fades, or the seed's table not made yet.
ui.FragmentShader? wispThrough({required WispKit kit, required Rect view, required List<({Rect at, WispSmoke smoke, Rect within})> smokes, double probe = 0}) {
  if (smokes.isEmpty || smokes.length > 2) return null;
  final first = smokes.first.smoke;
  for (final other in smokes.skip(1)) {
    if (other.smoke.seed != first.seed || other.smoke.axis != first.axis || other.smoke.fade != first.fade) return null;
  }
  final table = kit.tableNow(first.seed);
  if (table == null) return null;
  // One picture of the noise for both: each asks for its stretch, and the last answer holds every one asked.
  var field = wispNoiseField(kit: kit, table: table, bentRect: smokes.first.at.inflate((first.bend / 2).ceilToDouble()).intersect(smokes.first.within), smoke: first);
  for (final other in smokes.skip(1)) {
    field = wispNoiseField(kit: kit, table: table, bentRect: other.at.inflate((other.smoke.bend / 2).ceilToDouble()).intersect(other.within), smoke: other.smoke);
  }
  return kit.through(view: view, smokes: [for (final each in smokes) (strip: each.at, smoke: each.smoke)], field: field.image, fieldRect: field.rect, probe: probe);
}

/// The program a strip [at] of a view is read off the backdrop with (shaders/wisp_back.frag): measuring only.
/// [viewAt] is the view's corner on the screen, whose pixels the backdrop's are; null where the table of the
/// smoke's seed is not made yet.
ui.FragmentShader? wispBack({required WispKit kit, required Rect at, required WispSmoke smoke, required Rect within, required Offset viewAt, required double ratio, required Color paper, double probe = 0}) {
  final table = kit.tableNow(smoke.seed);
  if (table == null) return null;
  final bentRect = at.inflate((smoke.bend / 2).ceilToDouble()).intersect(within);
  final field = wispNoiseField(kit: kit, table: table, bentRect: bentRect, smoke: smoke);
  return kit.back(viewAt: viewAt, ratio: ratio, smoke: smoke, field: field.image, fieldRect: field.rect, paper: paper, probe: probe);
}

/// How many times a noise's picture was made: for a test.
int debugWispFields = 0;

/// Lets every kept noise go: for a test that counts them.
@visibleForTesting
void debugClearWispFields() {
  for (final field in _fields.values) {
    field.image.dispose();
  }
  _fields.clear();
}

/// How many of the screen's pixels one pixel of a smoke's small pictures covers, each way, for a blur of [sigma] of
/// the screen's: 4 where that is five or more, 2 from two and a half, and 1 (no smaller than the screen) for a blur
/// finer than that. The blur is then a pixel and a quarter to two and a half of the small picture's own, or a
/// little more: wide enough to be drawn up again smoothly, and narrow enough for the thirteen pixels it is read
/// over (shaders/wisp_haze.frag). [debugWispSmall] says it outright, for a test that compares them.
int wispSmallStep(double sigma) => debugWispSmall ?? (sigma >= 5 ? 4 : (sigma >= 2.5 ? 2 : 1));

/// The blur's deviation in a small picture's own pixels, for a blur of [sigma] of the screen's drawn at one pixel
/// to [step] of them: less what the small picture adds to the blur on its way, the mean a small pixel is of the
/// screen's under it (a box a pixel wide: a twelfth of its square) and its being read up between pixels at the end
/// (a sixth).
double wispSmallSigma(double sigma, int step) {
  if (step <= 1) return sigma;
  final small = sigma / step;
  return math.sqrt(math.max(0.0, small * small - 0.25));
}

@visibleForTesting
int? debugWispSmall;

/// What the ink found near a point is multiplied by in a small picture (shaders/wisp_haze.frag `uGain`): a stroke
/// thinner than one of its pixels is there at a part of its ink, and the dilate would otherwise find the smoke
/// round fine print thinner than round a heading.
double wispNearGain(int step) => debugWispGain ?? (step >= 4 ? 2.5 : (step == 2 ? 1.5 : 1.0));

@visibleForTesting
double? debugWispGain;

/// `soft` kept to `near`, small, for one smoke: [wispSoftSheet] of one.
({ui.Image image, Rect rect}) wispHaze({
  required WispKit kit,
  required ui.Image table,
  required ui.Image source,
  required Rect sourceRect,
  required Rect bentRect,
  required double ratio,
  required WispSmoke smoke,
}) {
  final sheet = wispSoftSheet(kit: kit, ratio: ratio, asks: [WispSoftAsk(table: table, source: source, sourceRect: sourceRect, bentRect: bentRect, smoke: smoke)]);
  return (image: sheet.image, rect: sheet.rects.single);
}

/// How many pictures the engine has been asked for on a strip's account (of the view, and of smokes' soft halves):
/// each is a task of its own before the frame. For a test to count a frame's.
int debugWispPictures = 0;

/// One smoke's asking for its soft half: the view it bends ([source], a picture lying over [sourceRect]), where the
/// bent view is worked out ([bentRect]), and the smoke.
@immutable
class WispSoftAsk {
  const WispSoftAsk({required this.table, required this.source, required this.sourceRect, required this.bentRect, required this.smoke});
  final ui.Image table, source;
  final Rect sourceRect, bentRect;
  final WispSmoke smoke;
}

/// The soft halves of several smokes, made together: `soft` kept to `near` for each (the bent view drawn at one
/// pixel to [wispSmallStep] of the screen's, then blurred and kept near its own ink, shaders/wisp_haze.frag), every
/// one in a place of its own on one small picture. Two pictures are made in all, the bent views and that blurred,
/// however many smokes ask: a page's top and its foot made a pair each, and each picture the engine is asked for
/// is a task of its own on the raster thread before the frame, which costs what it costs however small it is.
///
/// The answer's picture is every smoke's; [rects] says, for each, where the whole of it would lie in that smoke's
/// view for the smoke's own place to lie over its [WispSoftAsk.bentRect] (grown to whole pixels of the small
/// picture): what a shader that reads a picture by its place in the view is given. The places are one under the
/// next with a clear pixel between, so a reading between two pixels at a place's edge takes nothing of its
/// neighbour.
({ui.Image image, List<Rect> rects}) wispSoftSheet({required WispKit kit, required double ratio, required List<WispSoftAsk> asks}) {
  final places = <({int top, int wide, int tall, double texel, int step, Rect rect})>[];
  var down = 0, sheetWide = 1;
  for (final ask in asks) {
    final step = wispSmallStep(ask.smoke.blur * ratio);
    // One pixel of the small picture, in the view's.
    final texel = step / ratio;
    final wide = math.max(1, (ask.bentRect.width / texel - 1e-4).ceil()), tall = math.max(1, (ask.bentRect.height / texel - 1e-4).ceil());
    places.add((top: down, wide: wide, tall: tall, texel: texel, step: step, rect: ask.bentRect.topLeft & Size(wide * texel, tall * texel)));
    down += tall + 1;
    sheetWide = math.max(sheetWide, wide);
  }
  final sheetTall = math.max(1, down - 1);
  Rect whole(({int top, int wide, int tall, double texel, int step, Rect rect}) place) =>
      Rect.fromLTWH(place.rect.left, place.rect.top - place.top * place.texel, sheetWide * place.texel, sheetTall * place.texel);

  // The bent views, each in its place at the place's own size.
  var recorder = ui.PictureRecorder();
  var canvas = Canvas(recorder);
  for (var i = 0; i < asks.length; i++) {
    final ask = asks[i], place = places[i];
    canvas.save();
    canvas.translate(0, place.top.toDouble());
    canvas.clipRect(Rect.fromLTWH(0, 0, place.wide.toDouble(), place.tall.toDouble()), doAntiAlias: false);
    canvas.scale(1 / place.texel);
    final shader = kit.bend(source: ask.source, sourceRect: ask.sourceRect, origin: place.rect.topLeft, smoke: ask.smoke, table: ask.table, spread: place.step == 1 ? Offset.zero : Offset(place.texel / 4, place.texel / 4));
    canvas.drawRect(Offset.zero & place.rect.size, Paint()..shader = shader..isAntiAlias = false);
    canvas.restore();
  }
  var picture = recorder.endRecording();
  final bent = picture.toImageSync(sheetWide, sheetTall);
  picture.dispose();

  // And blurred, each by its own deviation and kept near its own ink, reading only its own place.
  recorder = ui.PictureRecorder();
  canvas = Canvas(recorder);
  for (var i = 0; i < asks.length; i++) {
    final smoke = asks[i].smoke, place = places[i];
    final taps = WispProbe.has('noblur') ? WispBlurTaps.none : wispBlurTaps(wispSmallSigma(smoke.blur * ratio, place.step));
    final near = WispProbe.has('nonear') ? Offset.zero : smoke.near;
    // The ink is looked for a little nearer in a small picture than the dilate's radius: a small pixel already has
    // the ink of the screen's pixels round it, and the gain widens what is found again. Eight tenths and the gains
    // above are what brought this drawing's halo nearest the first's, of those tried (test/art/smoke_compare_test.dart).
    final shader = kit.haze(bent: bent, bentRect: whole(place), own: place.rect, origin: place.rect.topLeft, taps: taps, near: near * (place.step == 1 ? 1.0 : 0.8), gain: near == Offset.zero ? 0 : wispNearGain(place.step));
    canvas.save();
    canvas.translate(0, place.top.toDouble());
    canvas.scale(1 / place.texel);
    canvas.drawRect(Offset.zero & place.rect.size, Paint()..shader = shader..isAntiAlias = false..blendMode = BlendMode.src);
    canvas.restore();
  }
  picture = recorder.endRecording();
  final image = picture.toImageSync(sheetWide, sheetTall);
  picture.dispose();
  bent.dispose();
  debugWispPictures += 2;
  if (ghostPerf) Perf.count('wisp.pictures', 2);
  return (image: image, rects: [for (final place in places) whole(place)]);
}

/// The same filter in three passes, each primitive a picture of its own at the screen's pixels, as the web filter
/// has them: `bent` (shaders/wisp_bend.frag), `soft` by the engine's own Gaussian blur, and the merge
/// (shaders/wisp_merge.frag), which reads `near` from the bent view on a grid of taps. What the one-pass drawing is
/// held to, and what test/art/wisp_parity_test.dart first held to Chromium's own pictures.
///
/// What differs from the page: `near` is read on a grid of taps where the page runs `feMorphology`, so its edge is
/// a little softer than a dilate's; and the band's ramp is the Gaussian itself where Chromium blurs a strip with
/// three box blurs. Neither can be told apart by eye in the pictures the two were compared in.
void paintWispSmokeExact(
  Canvas canvas, {
  required WispKit kit,
  required ui.Image table,
  required ui.Image source,
  required Rect sourceRect,
  required Rect rect,
  required Rect bentRect,
  required double ratio,
  required WispSmoke smoke,
}) {
  final bent = wispBent(kit: kit, table: table, source: source, sourceRect: sourceRect, bentRect: bentRect, ratio: ratio, smoke: smoke);
  if (WispProbe.has('nomerge')) {
    // Measuring only: the bent view and nothing after it.
    canvas.save();
    canvas.clipRect(rect, doAntiAlias: false);
    canvas.drawImageRect(bent, Rect.fromLTWH(0, 0, bent.width.toDouble(), bent.height.toDouble()), bentRect, Paint());
    canvas.restore();
    bent.dispose();
    return;
  }
  final soft = wispSoft(bent, WispProbe.has('noblur') ? 0 : smoke.blur * ratio);
  final shader = kit.merge(source: source, sourceRect: sourceRect, bent: bent, soft: soft, bentRect: bentRect, origin: rect.topLeft, smoke: smoke);
  canvas.save();
  canvas.translate(rect.left, rect.top);
  // Hard edged, as the clip that keeps the view out of this rectangle is: the two then meet on one line of pixels.
  canvas.drawRect(Offset.zero & rect.size, Paint()..shader = shader..isAntiAlias = false);
  canvas.restore();
  bent.dispose();
  soft.dispose();
}

/// `bent`: [source] displaced by [smoke]'s noise over [bentRect], as a picture of its own at [ratio] pixels to one
/// of the view's: the screen's, or fewer for a picture a blur is made from, which then says how far round each
/// point the view is read ([WispKit.bend] `spread`).
ui.Image wispBent({
  required WispKit kit,
  required ui.Image table,
  required ui.Image source,
  required Rect sourceRect,
  required Rect bentRect,
  required double ratio,
  required WispSmoke smoke,
  Offset spread = Offset.zero,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(ratio);
  if (WispProbe.has('nobend')) {
    // Measuring only: the view as it is, where the bent one would be.
    canvas.translate(-bentRect.left, -bentRect.top);
    canvas.drawImageRect(source, Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()), sourceRect, Paint());
  } else {
    final shader = kit.bend(source: source, sourceRect: sourceRect, origin: bentRect.topLeft, smoke: smoke, table: table, spread: spread);
    canvas.drawRect(Offset.zero & bentRect.size, Paint()..shader = shader..isAntiAlias = false);
  }
  final picture = recorder.endRecording();
  final image = picture.toImageSync((bentRect.width * ratio).round().clamp(1, 1 << 14), (bentRect.height * ratio).round().clamp(1, 1 << 14));
  picture.dispose();
  return image;
}

/// `soft`: [bent] under `feGaussianBlur` of [sigma] of its own pixels, clear past its edges as a primitive's
/// subregion is.
ui.Image wispSoft(ui.Image bent, double sigma) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();
  if (sigma > 0.01) paint.imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal);
  canvas.drawImage(bent, Offset.zero, paint);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(bent.width, bent.height);
  picture.dispose();
  return image;
}

/// [rect] grown out to whole screen pixels, on the grid that has a pixel's corner at [corner]: a picture taken of it
/// and drawn back lands pixel on pixel.
Rect snapOut(Rect rect, Offset corner, double ratio) {
  double down(double value, double from) => from + ((value - from) * ratio + 1e-4).floorToDouble() / ratio;
  double up(double value, double from) => from + ((value - from) * ratio - 1e-4).ceilToDouble() / ratio;
  return Rect.fromLTRB(down(rect.left, corner.dx), down(rect.top, corner.dy), up(rect.right, corner.dx), up(rect.bottom, corner.dy));
}
