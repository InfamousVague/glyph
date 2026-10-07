import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'turbulence.dart';
import 'wisp_edge.dart';
import 'wisp_kit.dart';

/// The wisp edge drawn as a mask instead of a filter (art/wispMask.ts): the band's shape made once, as a picture -
/// the same turbulence the filter uses, stitched so it tiles along the edge, over the soft ramp the filter blurs
/// from its strip, taken to alpha through a steep curve so it tears the words into tendrils rather than misting
/// them. What it loses is the bend; what it keeps is the smoke and its movement.
///
/// The page makes the picture as an SVG with a filter in it and lets the engine draw it; here the same primitives
/// are worked out in Dart, pixel by pixel ([wispMaskAlpha]), and handed over as an image. The web app wears this on
/// the engine that cannot afford the filter; no engine here is that, so it is drawn only when asked for by name
/// ([WispDraw.mask]).

/// The picture tiles along the edge this wide (`WISP_MASK_TILE`).
const double wispMaskTile = 512;

/// The picture's height and where the lip sits in it (`WISP_MASK_ABOVE`, `WISP_MASK_HEIGHT`).
const double wispMaskAbove = 160;
const double wispMaskHeight = 256;

/// How much of the words shows through the smoke past the lip (`SMOKE_SHOW`).
const double wispMaskShow = 0.34;

/// `feFuncA type="table"` of the band: the steep curve that tears.
const List<double> wispMaskCurve = [0, 0, 0.12, 0.88, 1, 1];

/// `feComponentTransfer`'s table: [values] spread evenly over 0 to 1, read between two of them.
double tableTransfer(List<double> values, double c) {
  final n = values.length - 1;
  if (c >= 1) return values[n];
  if (c <= 0) return values[0];
  final k = (c * n).floor();
  return values[k] + (c * n - k) * (values[k + 1] - values[k]);
}

final Turbulence _maskNoise = Turbulence(3);
const TurbulenceTile _maskTileBox = TurbulenceTile(wispMaskTile, wispMaskHeight);

/// The band's alpha at a point of its picture, 0 to 1: `bandSvg` of art/wispMask.ts, primitive by primitive. [soft]
/// is the ramp's blur; [flip] turns the picture over for the foot, the lip then 96 from the top and the smoke below.
double wispMaskAlpha(double x, double y, {required double soft, bool flip = false}) {
  // The foot's picture is the top's, drawn in a space turned over: the band and its noise with it.
  final v = flip ? wispMaskHeight - y : y;
  // `stripOnWhite` blurred down the picture: grey above the lip, white below it, and clear past the picture's own
  // edges, which the blur brings in at its top and bottom.
  double part(double from, double to) => gaussianRamp((to - v) / soft) - gaussianRamp((from - v) / soft);
  final rampAlpha = part(0, wispMaskHeight);
  final ramp = wispMaskShow * part(0, wispMaskAbove) + part(wispMaskAbove, wispMaskHeight);
  final noise = _maskNoise.sample(0, x + 0.5, v + 0.5, baseFrequencyX: 0.018, baseFrequencyY: 0.06, octaves: 2, tile: _maskTileBox);
  // `feComposite arithmetic` of the opaque noise and the ramp, on colours multiplied by their alpha.
  final alpha = (0.9 + rampAlpha - 0.45).clamp(0.0, 1.0);
  final field = (0.9 * noise + ramp - 0.45).clamp(0.0, alpha);
  return tableTransfer(wispMaskCurve, alpha == 0 ? 0 : field / alpha);
}

/// The band as pixels, ink at [wispMaskAlpha]: [ratio] pixels to each of the picture's own.
Uint8List wispMaskPixels({required bool foot, int ratio = 2}) {
  final width = (wispMaskTile * ratio).round(), height = (wispMaskHeight * ratio).round();
  final soft = foot ? wispEdgeFootSoft : wispEdgeSoft;
  final out = Uint8List(width * height * 4);
  for (var py = 0; py < height; py++) {
    for (var px = 0; px < width; px++) {
      final alpha = wispMaskAlpha((px + 0.5) / ratio, (py + 0.5) / ratio, soft: soft, flip: foot);
      out[(py * width + px) * 4 + 3] = (alpha * 255).round();
    }
  }
  return out;
}

/// The two bands, made: the top's and the foot's.
class WispMaskBands {
  const WispMaskBands(this.top, this.foot);
  final ui.Image top, foot;
}

WispMaskBands? _bands;
Future<WispMaskBands>? _bandsComing;

/// The bands if they have been made.
WispMaskBands? wispMaskBandsNow() => _bands;

/// Makes both bands once (`installWispMasks`), the first time a view asks for the mask drawing; nothing before.
Future<WispMaskBands> wispMaskBands({int ratio = 2}) {
  return _bandsComing ??= () async {
    final top = await _image(wispMaskPixels(foot: false, ratio: ratio), ratio);
    final foot = await _image(wispMaskPixels(foot: true, ratio: ratio), ratio);
    return _bands = WispMaskBands(top, foot);
  }();
}

Future<ui.Image> _image(Uint8List pixels, int ratio) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(pixels, (wispMaskTile * ratio).round(), (wispMaskHeight * ratio).round(), ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}
