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
}) {
  if (!wispQuick) {
    paintWispSmokeExact(canvas, kit: kit, table: table, source: source, sourceRect: sourceRect, rect: rect, bentRect: bentRect, ratio: ratio, smoke: smoke);
    return;
  }
  final haze = wispHaze(kit: kit, table: table, source: source, sourceRect: sourceRect, bentRect: bentRect, ratio: ratio, smoke: smoke);
  final field = wispNoiseField(kit: kit, table: table, bentRect: bentRect, ratio: ratio, smoke: smoke);
  final shader = kit.smoke(source: source, sourceRect: sourceRect, bentRect: bentRect, haze: haze.image, hazeRect: haze.rect, field: field.image, fieldRect: field.rect, origin: rect.topLeft, smoke: smoke);
  canvas.save();
  canvas.translate(rect.left, rect.top);
  // Hard edged, as the clip that keeps the view out of this rectangle is: the two then meet on one line of pixels.
  canvas.drawRect(Offset.zero & rect.size, Paint()..shader = shader..isAntiAlias = false);
  canvas.restore();
  haze.image.dispose();
}

/// The noise of [smoke] over [bentRect], as the picture the one-pass drawing reads its bend from
/// (shaders/wisp_field.frag): one pixel to two of the screen's each way, lying over the answer's rectangle.
///
/// Kept, and not made again while the same noise is asked for over the same rectangle: the noise is the same on
/// every frame of a scroll until the drift steps it (lib/art/wisp_edge.dart `WispDrift`, at most thirty-five times a
/// second), and it is the same for ever on a page that has come to rest. The few last asked for are kept (a page's
/// top and foot, a column's, a board's lanes, which are alike and share one); the picture is the caller's to read
/// and not to let go.
({ui.Image image, Rect rect}) wispNoiseField({required WispKit kit, required ui.Image table, required Rect bentRect, required double ratio, required WispSmoke smoke}) {
  final key = (smoke.seed, smoke.frequency, smoke.slide, smoke.noiseRect, bentRect, ratio);
  final had = _fields.remove(key);
  if (had != null) return _fields[key] = had;
  if (ghostPerf) Perf.count('wisp.fields');
  final texel = 2 / ratio;
  final wide = math.max(1, (bentRect.width / texel - 1e-4).ceil()), tall = math.max(1, (bentRect.height / texel - 1e-4).ceil());
  final rect = bentRect.topLeft & Size(wide * texel, tall * texel);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(1 / texel);
  canvas.drawRect(Offset.zero & rect.size, Paint()..shader = kit.field(origin: rect.topLeft, smoke: smoke, table: table)..isAntiAlias = false..blendMode = BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(wide, tall);
  picture.dispose();
  if (_fields.length >= _fieldsKept) _fields.remove(_fields.keys.first)!.image.dispose();
  return _fields[key] = (image: image, rect: rect);
}

final Map<Object, ({ui.Image image, Rect rect})> _fields = {};
const int _fieldsKept = 8;

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

/// `soft` kept to `near`, small: the bent view drawn at one pixel to [wispSmallStep] of the screen's, then blurred
/// and kept near its own ink (shaders/wisp_haze.frag). The picture lies over the answer's rectangle, which is
/// [bentRect] grown to whole pixels of the small picture.
({ui.Image image, Rect rect}) wispHaze({
  required WispKit kit,
  required ui.Image table,
  required ui.Image source,
  required Rect sourceRect,
  required Rect bentRect,
  required double ratio,
  required WispSmoke smoke,
}) {
  final step = wispSmallStep(smoke.blur * ratio);
  // One pixel of the small picture, in the view's.
  final texel = step / ratio;
  final wide = math.max(1, (bentRect.width / texel - 1e-4).ceil()), tall = math.max(1, (bentRect.height / texel - 1e-4).ceil());
  final rect = bentRect.topLeft & Size(wide * texel, tall * texel);
  final bent = wispBent(kit: kit, table: table, source: source, sourceRect: sourceRect, bentRect: rect, ratio: ratio / step, smoke: smoke, spread: step == 1 ? Offset.zero : Offset(texel / 4, texel / 4));

  final taps = WispProbe.has('noblur') ? WispBlurTaps.none : wispBlurTaps(wispSmallSigma(smoke.blur * ratio, step));
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(ratio / step);
  final near = WispProbe.has('nonear') ? Offset.zero : smoke.near;
  // The ink is looked for a little nearer in a small picture than the dilate's radius: a small pixel already has
  // the ink of the screen's pixels round it, and the gain widens what is found again. Eight tenths and the gains
  // above are what brought this drawing's halo nearest the first's, of those tried (test/art/smoke_compare_test.dart).
  final shader = kit.haze(bent: bent, bentRect: rect, origin: rect.topLeft, taps: taps, near: near * (step == 1 ? 1.0 : 0.8), gain: near == Offset.zero ? 0 : wispNearGain(step));
  canvas.drawRect(Offset.zero & rect.size, Paint()..shader = shader..isAntiAlias = false..blendMode = BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(wide, tall);
  picture.dispose();
  bent.dispose();
  return (image: image, rect: rect);
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
