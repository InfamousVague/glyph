/// The little reader, for the wait before the first word. A port of `src/app/format/Thinking.tsx` and
/// `Thinking.module.css`.
///
/// Loading a model and reading the note are the two stretches where nothing arrives for the person to watch - ten
/// seconds to a minute on a phone - so something on the page has to be alive. Matt asked for "a robot doing things or
/// a fun abstract animation": this is a robot made of the app's own shapes, on the ink like everything in
/// art/shapes.dart. A rounded square for a head with two dots for eyes and an antenna; under it, three bars, the
/// note.
///
/// Two acts, by phase. Loading: the antenna's dot blinks and the eyes are shut (two short bars), the machine warming
/// up. Reading: the eyes open and sweep left to right along each bar in turn, and the bar being read is ink while
/// the others wait in grey. It leaves the moment the first word is written. Under reduced motion the eyes and the
/// antenna hold still.
///
/// What differs: the svg is a painter over one clock. [size] is the reader's side when it is a corner of something
/// (the AI card's `.reader svg`: 4.5rem, and no room round it); left out, it is the whole stage, `min(40vw, 9rem)`
/// wide with the stage's own room round it.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../ai/backend.dart' show Phase;

/// See the header (`Thinking`).
class Thinking extends StatefulWidget {
  const Thinking({super.key, required this.phase, this.size});

  final Phase phase;

  /// The reader's side, in pixels, with no room round it; null for the whole stage.
  final double? size;

  @override
  State<Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<Thinking> with SingleTickerProviderStateMixin {
  // One clock for every motion: each reads its own place in its own round from the time since the reader came.
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(hours: 1));
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // @media (prefers-reduced-motion: reduce) { .beacon, .robot, .eyes, .lines rect { animation: none; } }
    _still = context.tokens.reducedMotion;
    if (_still) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reading = widget.phase == Phase.prefill || widget.phase == Phase.generating;
    // .stage { color: var(--app-ink); }
    final ink = t.color('app-ink');
    final corner = widget.size;
    // .robot { inline-size: min(40vw, 9rem); block-size: auto; overflow: visible; }
    final side = corner ?? math.min(MediaQuery.sizeOf(context).width * 0.4, t.lenOf('9rem'));
    final robot = AnimatedBuilder(
      animation: _clock,
      builder: (context, _) => CustomPaint(
        key: ValueKey<String>(reading ? 'thinking-reading' : 'thinking-loading'),
        size: Size.square(side),
        painter: _Robot(ink: ink, reading: reading, still: _still, ms: _still ? 0 : (_clock.lastElapsedDuration?.inMicroseconds ?? 0) / 1000),
      ),
    );
    if (corner != null) return ExcludeSemantics(child: robot);
    // .stage { display: grid; place-items: center;
    //   padding: var(--glacier-space-10) var(--app-gutter) var(--glacier-space-6); }
    return ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.len('app-gutter'), t.space(10), t.len('app-gutter'), t.space(6)),
        // As tall as the reader and its room, and no taller.
        child: Center(heightFactor: 1, child: robot),
      ),
    );
  }
}

/// `ease-in-out`, the keyword: cubic-bezier(0.42, 0, 0.58, 1).
const Cubic _easeInOut = Cubic(0.42, 0, 0.58, 1);

/// A value that goes from [a] to [b] and back over a round of [period] ms, each half eased: a keyframe at 50% with
/// the same value at both ends.
double _toAndFro(double ms, double period, double a, double b) {
  final at = (ms % period) / period;
  final half = at < 0.5 ? at * 2 : (1 - at) * 2;
  return a + (b - a) * _easeInOut.transform(half);
}

class _Robot extends CustomPainter {
  const _Robot({required this.ink, required this.reading, required this.still, required this.ms});

  final Color ink;
  final bool reading;
  final bool still;
  final double ms;

  @override
  void paint(Canvas canvas, Size size) {
    // viewBox="0 0 120 120"
    final unit = size.width / 120;
    canvas.save();
    // .stage[data-phase='loading'] .robot { animation: breathe 2.6s ease-in-out infinite; }
    // @keyframes breathe { 50% { transform: translateY(-3px); } }: pixels of the page, not of the drawing.
    if (!reading && !still) canvas.translate(0, _toAndFro(ms, 2600, 0, -3));
    canvas.scale(unit);
    Paint fill([double opacity = 1]) => Paint()..color = ink.withValues(alpha: ink.a * opacity);
    Paint stroke([double opacity = 1]) => Paint()
      ..color = ink.withValues(alpha: ink.a * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // the antenna
    canvas.drawLine(const Offset(60, 16), const Offset(60, 30), stroke());
    // .beacon { transform-origin: 60px 12px; animation: beacon 1.1s ease-in-out infinite; }
    // @keyframes beacon { 0%, 100% { opacity: 0.25; transform: scale(0.8); } 50% { opacity: 1; transform: scale(1.15); } }
    // .stage[data-phase='reading'] .beacon { animation: none; opacity: 1; }
    final blinking = !reading && !still;
    final beaconOpacity = blinking ? _toAndFro(ms, 1100, 0.25, 1) : 1.0;
    final beaconScale = blinking ? _toAndFro(ms, 1100, 0.8, 1.15) : 1.0;
    canvas.drawCircle(const Offset(60, 12), 5 * beaconScale, fill(beaconOpacity));
    // the head
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(32, 30, 56, 44), const Radius.circular(12)), stroke());
    // eyes: closed while loading, open and sweeping while reading
    if (reading) {
      // .stage[data-phase='reading'] .lid { opacity: 0; }
      // .stage[data-phase='reading'] .eyes { animation: sweep 1.2s ease-in-out infinite; }
      // @keyframes sweep { 0% { transform: translateX(-5px); } 50% { transform: translateX(5px); } 100% { -5px } }
      final dx = still ? 0.0 : _toAndFro(ms, 1200, -5, 5);
      canvas.drawCircle(Offset(48 + dx, 50), 4.5, fill());
      canvas.drawCircle(Offset(72 + dx, 50), 4.5, fill());
    } else {
      // .stage[data-phase='loading'] .eye { opacity: 0; }
      canvas.drawLine(const Offset(42, 50), const Offset(54, 50), stroke());
      canvas.drawLine(const Offset(66, 50), const Offset(78, 50), stroke());
    }
    // the note: three lines it reads
    // .stage[data-phase='loading'] .lines rect { opacity: 0.25; }
    // .stage[data-phase='reading'] .lines rect { opacity: 0.25; animation: turn 3.6s linear infinite; }
    // .line2 { animation-delay: 1.2s; } .line3 { animation-delay: 2.4s; }
    // @keyframes turn { 0%, 33.3% { opacity: 1; } 33.4%, 100% { opacity: 0.25; } }
    // Reduced motion: .stage[data-phase='reading'] .lines rect { opacity: 1; }
    double lineOpacity(int n) {
      if (!reading) return 0.25;
      if (still) return 1;
      final since = ms - n * 1200;
      // Before its delay is up a line waits as its own rule leaves it.
      if (since < 0) return 0.25;
      return (since % 3600) / 3600 <= 0.333 ? 1 : 0.25;
    }

    const bars = <Rect>[Rect.fromLTWH(22, 86, 76, 6), Rect.fromLTWH(22, 98, 56, 6), Rect.fromLTWH(22, 110, 66, 6)];
    for (var n = 0; n < bars.length; n += 1) {
      canvas.drawRRect(RRect.fromRectAndRadius(bars[n], const Radius.circular(3)), fill(lineOpacity(n)));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Robot old) => old.ink != ink || old.reading != reading || old.still != still || old.ms != ms;
}
