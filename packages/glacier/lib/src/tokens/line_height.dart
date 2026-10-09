import 'package:flutter/painting.dart';

final Map<String, (double, double)> _faceMetrics = {};
bool _watchingFonts = false;

/// `line-height: normal` for [face], in logical pixels, as a browser works it out: the font's ascent and its descent
/// each rounded to a whole pixel, then added. Flutter rounds their sum instead, which for Inter at 11px is a line of
/// 13 where the page's is 14, and at 16px 19 where the page's is 20: a pixel on every heading and row. (An explicit
/// `line-height` the page keeps to the fraction and Flutter rounds to a pixel; that half pixel is the engine's.)
///
/// The pixel is the DEVICE's: Chromium lays a page out at the device's scale, so at [dpr] 2.625 a 16.26px title's
/// ascent and descent are rounded as 41.3 and 10.3 device pixels and its line is 51 of them, 19.43 logical, where
/// rounding the logical 15.75 and 3.92 gave 20. On a desktop's ratio of 1, where the tests' rectangles were
/// measured, the two are the same.
double normalLineHeight(TextStyle face, {double dpr = 1}) {
  final size = face.fontSize!;
  final key = '${face.fontFamily}|${face.fontFamilyFallback?.join(',')}|${face.fontWeight?.value}';
  final (ascent, descent) = _faceMetrics.putIfAbsent(key, () {
    if (!_watchingFonts) {
      // A font that arrives later is a different answer.
      _watchingFonts = true;
      PaintingBinding.instance.systemFonts.addListener(_faceMetrics.clear);
    }
    const probe = 1000.0;
    final painter = TextPainter(
      text: TextSpan(text: 'x', style: face.copyWith(fontSize: probe, height: kTextHeightNone, letterSpacing: 0)),
      textDirection: TextDirection.ltr,
    )..layout();
    final line = painter.computeLineMetrics().first;
    painter.dispose();
    return (line.ascent / probe, line.descent / probe);
  });
  final ratio = dpr > 0 ? dpr : 1.0;
  return ((ascent * size * ratio).roundToDouble() + (descent * size * ratio).roundToDouble()) / ratio;
}
