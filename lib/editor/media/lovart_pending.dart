/// What stands where a Lovart picture is coming (Matt, 2026-10-26: "when hitting return start to generate the image,
/// place a blurry abstract image with the lovart logo and a loading circle around it"). The port's own.
///
/// Drawn under the line of a `{image: …}` while Lovart makes it (lib/editor/ai/lovart_cues.dart), at the width a
/// picture is: three soft fields of colour, blurred together over a wash of the first, the colours picked from the
/// prompt's words among the cassettes' hues (lib/tapes/tape_art.dart [tapeHues]) so one cue keeps its look while it
/// waits; in the middle, Lovart's mark on a dark round with a ring turning round it. Still under reduced motion, the
/// ring a quarter drawn. Nothing of it is in the note: when the picture lands, the picture takes its place.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../plugins/lovart/lovart_mark.dart';
import '../../tapes/tape_art.dart' show tapeHues;

/// How tall the stand-in is for its width: a landscape picture's.
const double lovartPendingAspect = 16 / 10;

/// The mark's round, and the ring's gap round it.
const double _round = 44;
const double _ringGap = 5;

/// 32-bit FNV-1a over [words], as the cassettes pick their hue (tape_art.dart `tapeHue`).
int _hash(String words) {
  var hash = 0x811c9dc5;
  for (final unit in words.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// The stand-in for the picture [prompt] will make, [width] wide at most.
class LovartPending extends StatelessWidget {
  const LovartPending({super.key, required this.prompt, this.maxHeight = 360});

  final String prompt;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final seed = _hash(prompt.trim().toLowerCase());
    final hues = [for (var i = 0; i < 3; i += 1) t.color('glacier-${tapeHues[(seed >> (i * 5)) % tapeHues.length]}-9')];
    final radius = t.radius('md');
    return Semantics(
      label: 'Lovart is making: $prompt',
      liveRegion: true,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth.isFinite ? box.maxWidth : 320.0;
          final height = math.min(width / lovartPendingAspect, maxHeight);
          return ClipRRect(
            key: const ValueKey<String>('lovart-pending'),
            borderRadius: BorderRadius.circular(radius),
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The fields of colour, blurred into one another: an abstract, not a picture of anything.
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28, tileMode: TileMode.mirror),
                    child: CustomPaint(painter: _Fields(hues: hues, seed: seed)),
                  ),
                  // A veil, so the mark reads on any of them.
                  ColoredBox(color: const Color(0x14000000)),
                  const Center(child: LovartWorking()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Three rounds of colour over a wash of the first, placed by [seed].
class _Fields extends CustomPainter {
  _Fields({required this.hues, required this.seed});

  final List<Color> hues;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Color.lerp(hues[0], const Color(0xFFFFFFFF), 0.35)!);
    for (var i = 0; i < 3; i += 1) {
      final bits = (seed >> (i * 7 + 3)) & 0x7f;
      final x = size.width * (0.15 + 0.7 * ((bits & 0xf) / 15));
      final y = size.height * (0.15 + 0.7 * ((bits >> 4) / 7));
      final r = math.min(size.width, size.height) * (0.35 + 0.1 * i);
      canvas.drawCircle(Offset(x, y), r, Paint()..color = hues[i].withValues(alpha: 0.85));
    }
  }

  @override
  bool shouldRepaint(_Fields old) => old.seed != seed || old.hues != hues;
}

/// Lovart's mark, white on a dark round, with a ring turning round it while it works.
class LovartWorking extends StatefulWidget {
  const LovartWorking({super.key});

  @override
  State<LovartWorking> createState() => _LovartWorkingState();
}

class _LovartWorkingState extends State<LovartWorking> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!context.tokens.reducedMotion) _turn.repeat();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const side = _round + 2 * (_ringGap + 3);
    return SizedBox(
      key: const ValueKey<String>('lovart-working'),
      width: side,
      height: side,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(turns: _turn, child: const CustomPaint(size: Size.square(side), painter: _Ring())),
          Container(
            width: _round,
            height: _round,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x99000000),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x40FFFFFF), width: 0.5),
            ),
            child: const LovartMark(size: _round * 0.5, color: Color(0xFFFFFFFF)),
          ),
        ],
      ),
    );
  }
}

/// A faint whole ring, and a quarter of it bright: the part that turns.
class _Ring extends CustomPainter {
  const _Ring();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0x40FFFFFF);
    final bright = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFFFFF);
    canvas.drawArc(rect, 0, 2 * math.pi, false, faint);
    canvas.drawArc(rect, -math.pi / 2, math.pi / 2, false, bright);
  }

  @override
  bool shouldRepaint(_Ring old) => false;
}
