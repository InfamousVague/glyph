/// The ElevenLabs plugin's mark: two upright bars side by side, the "II" of ElevenLabs' own in spirit, drawn here in
/// one colour, the text's around it unless told.
///
/// Not ElevenLabs' artwork: their logo is a trademark, and this is a plain mark of the app's own that nods at it. Where
/// the official mark is to be used (with ElevenLabs' leave, from their brand kit), it goes in as an SVG beside
/// Lovart's (assets/plugins/elevenlabs/elevenlabs-mark.svg) and is drawn the way lib/plugins/lovart/lovart_mark.dart
/// draws Lovart's, in this widget's place; nothing else changes. As a third party's mark it would then be drawn in the
/// plugin's own places only (its page, its action, its tile in the Market), never in a store's listing.
library;

import 'package:flutter/widgets.dart';

class ElevenLabsMark extends StatelessWidget {
  const ElevenLabsMark({super.key, this.size = 16, this.color});

  final double size;

  /// Its colour; the icon's or the text's around it when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
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
