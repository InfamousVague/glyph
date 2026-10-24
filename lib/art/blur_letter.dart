import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// A letter coming out of a blur: what every letter the wisp drew in smoke is now (Matt, 2026-10-24: "replace the
/// smoke effect with a gradient blur on all places that use the wisp smoke", on every platform). The words arriving
/// in the recorder, an AI's words landing in a note, a headline typing itself in (lib/art/wisp_text.dart), the
/// spoiler's hidden words: each letter goes from soft and faint to sharp and whole, where it was bent by noise and
/// blurred. The clocks that move them are the wisp's own and say a bend and a blur at each moment; the bend is taken
/// into the blur ([letterBlur]), so a letter is softest as it appears and sharp as it sets, on the same curve.
///
/// One layer and one blur for a letter while it is soft, and none once it has set; no shader, no noise.

/// How much of a smoke's bend a letter's blur stands for: a bend of 34 px (a letter just arriving) is a blur of
/// about four more, with the smoke's own blur of five, six and a half in all.
const double letterBendShare = 0.12;

/// The most a letter is blurred: past this a word is a smudge, and the layer only grows.
const double letterBlurMost = 8;

/// The blur a letter is drawn with for a smoke of [bend] and [blur]: the two together, as two blurs add (as
/// squares), held to [letterBlurMost].
double letterBlur(double bend, double blur) {
  final fromBend = bend * letterBendShare;
  return math.min(letterBlurMost, math.sqrt(blur * blur + fromBend * fromBend));
}

/// The room a letter's layer is given round its [box]: three widths either side and one and a half heights above
/// and below, as the wisp's was, and as far again as the blur reaches.
Rect letterRegion(Size box, double sigma) => Rect.fromLTWH(-3 * box.width, -1.5 * box.height, 7 * box.width, 4 * box.height).inflate(sigma * 3);

/// Draws a letter [sigma] soft and [opacity] there, its corner at the canvas's origin: [draw] paints the letter
/// itself, [box] is its size. A letter that is sharp and whole is drawn as it is, with no layer.
void paintBlurLetter(Canvas canvas, {required Size box, required double sigma, double opacity = 1, required void Function(Canvas canvas) draw}) {
  final shown = opacity.clamp(0.0, 1.0);
  if (shown <= 0) return;
  if (sigma < 0.05 && shown >= 1) {
    draw(canvas);
    return;
  }
  final paint = Paint()..color = Color.fromRGBO(0, 0, 0, shown);
  if (sigma >= 0.05) paint.imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal);
  canvas.saveLayer(letterRegion(box, sigma), paint);
  draw(canvas);
  canvas.restore();
}
