/// The ElevenLabs plugin's mark: ElevenLabs' own, its two upright bars, as Simple Icons draws it (Matt, 2026-10-29:
/// "Iconize real company logos ... and use those for the plugin icons"; lib/art/brand_marks.dart), in one colour, the
/// text's around it unless told.
///
/// Until then it was a plain mark of the app's own that nodded at theirs: two bars a sixth of the box wide, drawn
/// here. Those bars are what a build for a store's pictures draws still, where no brand's mark is shown
/// (`brandMarksShown`).
library;

import 'package:flutter/widgets.dart';

import '../../art/brand_marks.dart';
import '../brands.dart' show brandOfId;

class ElevenLabsMark extends StatelessWidget {
  const ElevenLabsMark({super.key, this.size = 16, this.color});

  final double size;

  /// Its colour; the icon's or the text's around it when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
    final mark = brandOfId('elevenlabs');
    if (mark != null) return BrandMarkIcon(mark, size: size, color: ink);
    return SizedBox.square(dimension: size, child: CustomPaint(painter: _Bars(ink)));
  }
}

/// Two bars, each a sixth of the box wide and three quarters of it tall, a sixth apart, centred.
class _Bars extends CustomPainter {
  const _Bars(this.ink);
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final width = side / 6, height = side * 0.76, gap = side / 6;
    final left = (size.width - (2 * width + gap)) / 2, top = (size.height - height) / 2;
    final paint = Paint()..color = ink;
    final round = Radius.circular(width * 0.18);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, top, width, height), round), paint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left + width + gap, top, width, height), round), paint);
  }

  @override
  bool shouldRepaint(_Bars old) => old.ink != ink;
}

/// The mark as a plugin's icon (lib/plugins/types.dart [PluginIcon]).
Widget elevenLabsIcon(BuildContext context, double size) => ElevenLabsMark(size: size);
