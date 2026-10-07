import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'wisp_kit.dart';

/// A filter's passes, drawn: the chain of primitives art/wispBox.ts `smokeFrom` and art/WispEdgeFilter.tsx write,
/// from the picture of a view to the picture of it smoking. Three steps, as the web filter has them:
///
/// 1. `bent`: the view thrown about by the noise where the band is (shaders/wisp_bend.frag);
/// 2. `soft`: the bent view blurred, by the engine's own Gaussian blur, which is what `feGaussianBlur` is;
/// 3. the merge: the view, the bent view in the band, and the blur kept near the bent strokes, under the view's own
///    fade (shaders/wisp_merge.frag).
///
/// Everything is in the view's own logical pixels; [ratio] is the screen's pixels to one of them. The rectangles are
/// taken as they are given, so a caller who wants the result pixel for pixel hands in ones that lie on the screen's
/// grid ([snapOut]).
///
/// What differs from the page: `near` is read from the bent view on a grid of taps inside the last shader where the
/// page runs `feMorphology`, so its edge is a little softer than a dilate's; and the band's ramp is the Gaussian
/// itself where Chromium blurs a strip with three box blurs. Neither can be told apart by eye in the pictures the two
/// were compared in (test/art/wisp_parity_test.dart).
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
  final bent = wispBent(kit: kit, table: table, source: source, sourceRect: sourceRect, bentRect: bentRect, ratio: ratio, smoke: smoke);
  final soft = wispSoft(bent, smoke.blur * ratio);
  final shader = kit.merge(source: source, sourceRect: sourceRect, bent: bent, soft: soft, bentRect: bentRect, origin: rect.topLeft, smoke: smoke);
  canvas.save();
  canvas.translate(rect.left, rect.top);
  // Hard edged, as the clip that keeps the view out of this rectangle is: the two then meet on one line of pixels.
  canvas.drawRect(Offset.zero & rect.size, Paint()..shader = shader..isAntiAlias = false);
  canvas.restore();
  bent.dispose();
  soft.dispose();
}

/// `bent`: [source] displaced by [smoke]'s noise over [bentRect], as a picture of its own at the screen's pixels.
ui.Image wispBent({
  required WispKit kit,
  required ui.Image table,
  required ui.Image source,
  required Rect sourceRect,
  required Rect bentRect,
  required double ratio,
  required WispSmoke smoke,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(ratio);
  final shader = kit.bend(source: source, sourceRect: sourceRect, origin: bentRect.topLeft, smoke: smoke, table: table);
  canvas.drawRect(Offset.zero & bentRect.size, Paint()..shader = shader..isAntiAlias = false);
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
