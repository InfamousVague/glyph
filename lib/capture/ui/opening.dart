/// The recorder's picture of sound beginning, drawn in the app's own ink: a dot and three arcs opening to the right.
/// A port of `src/app/capture/Opening.tsx` and the `.picture*` rules of CaptureScreen.module.css.
///
/// Abstract, like the rest of the artwork. It plays as the microphone opens, each arc arriving in turn, breathes
/// while the recorder listens, and stays, dashed and faint, when the microphone never did (the recorder's failed
/// state). Single colour, so it inverts with the theme. A picture only: it opens no microphone.
///
/// What differs:
/// - `listening` is said to it. On the page the breathing was the screen's rule
///   (`.screen[data-phase='listening'] .pictureArc`), which a widget cannot read from above.
/// - The arcs are painted ([OpeningPainter]) from one clock rather than animated by a stylesheet; the frames are the
///   stylesheet's: each arc in over 520 ms from its own delay, and the breath from 900 ms after listening began.
/// - Its width is `min(60%, 14rem)` of the width it is given, and it stands 8 px to the left of where it is laid out
///   (`margin-inline-start: calc(-1 * var(--glacier-space-2))`) without taking that from its box.
library;

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

class Opening extends StatelessWidget {
  const Opening({super.key, this.failed = false, this.listening = false});

  /// The microphone never opened: the arcs dashed and faint, and still.
  final bool failed;

  /// The recorder is listening: the arcs breathe together, slowly.
  final bool listening;

  @override
  Widget build(BuildContext context) => _Arcs(failed: failed, listening: listening);
}

class _Arcs extends StatefulWidget {
  const _Arcs({required this.failed, required this.listening});

  final bool failed;
  final bool listening;

  @override
  State<_Arcs> createState() => _ArcsState();
}

/// The last arc is in by its delay and its run: 180 + 2 * 220 + 520.
const double _allInMs = 1140;

class _ArcsState extends State<_Arcs> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);

  /// The picture's clock when the ticker last started: a ticker counts from nothing each time.
  double _from = 0;

  /// When the breath begins on the picture's clock, or null while it does not breathe.
  double? _breatheAt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Arcs old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _tick(Duration elapsed) {
    _clock.value = _from + elapsed.inMicroseconds / 1000;
    // Once the arcs are in, only a breath keeps the clock running.
    if (_breatheAt == null && _clock.value >= _allInMs) _ticker.stop();
  }

  void _sync() {
    // .picture[data-failed] .pictureArc { animation: none }, and with reduced motion none either.
    final moves = !widget.failed && !context.tokens.reducedMotion;
    // breathe 2.6s var(--glacier-ease-in-out) 900ms infinite alternate: from 900 ms after the rule arrives.
    if (moves && widget.listening) {
      _breatheAt ??= _clock.value + 900;
    } else {
      _breatheAt = null;
    }
    final runs = moves && (_breatheAt != null || _clock.value < _allInMs);
    if (runs && !_ticker.isActive) {
      _from = _clock.value;
      _ticker.start();
    } else if (!runs && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final moves = !widget.failed && !t.reducedMotion;
    // .picture {
    //   inline-size: min(60%, 14rem);
    //   block-size: auto;
    //   margin-inline-start: calc(-1 * var(--glacier-space-2));
    //   color: var(--app-ink);
    //   overflow: visible;
    // }
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final width = math.min(box.maxWidth.isFinite ? box.maxWidth * 0.6 : double.infinity, t.lenOf('14rem'));
          return Align(
            alignment: Alignment.centerLeft,
            heightFactor: 1,
            child: Transform.translate(
              offset: Offset(-t.space(2), 0),
              child: CustomPaint(
                // viewBox="0 0 160 120"
                size: Size(width, width * 120 / 160),
                painter: OpeningPainter(
                  color: t.color('app-ink'),
                  failed: widget.failed,
                  clock: moves ? _clock : null,
                  breatheAt: _breatheAt,
                  breath: t.curve('glacier-ease-in-out'),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The dot and its three arcs on the 160 by 120 drawing, as they stand at `clock` milliseconds; with no clock, whole
/// and still.
class OpeningPainter extends CustomPainter {
  OpeningPainter({required this.color, required this.failed, required this.clock, required this.breatheAt, required this.breath}) : super(repaint: clock);

  final Color color;
  final bool failed;
  final ValueNotifier<double>? clock;

  /// When the breath begins on the clock, or null while the arcs do not breathe.
  final double? breatheAt;
  final Curve breath;

  /// The arcs' radii round the dot (`[24, 44, 64]`).
  static const List<double> radii = [24, 44, 64];

  /// `strokeDasharray={failed ? '6 7' : undefined}`.
  List<double>? get dash => failed ? const [6, 7] : null;

  // animation: arc-in 520ms cubic-bezier(0.34, 1.3, 0.64, 1) both;
  static const Cubic _arcIn = Cubic(0.34, 1.3, 0.64, 1);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 160, size.height / 120);
    // <circle cx="40" cy="60" r="7" />, .pictureInk { fill: currentColor; }
    canvas.drawCircle(const Offset(40, 60), 7, Paint()..color = color);
    final now = clock?.value;
    final breathing = breatheAt;
    for (var i = 0; i < radii.length; i += 1) {
      final r = radii[i];
      var opacity = 1.0;
      var scale = 1.0;
      if (failed) {
        // .picture[data-failed] .pictureArc { opacity: 0.35; animation: none; }
        opacity = 0.35;
      } else if (now != null) {
        // @keyframes arc-in { from { opacity: 0; transform: scale(0.6); } }
        // style={{ animationDelay: `${180 + i * 220}ms` }}
        final run = ((now - (180 + i * 220)) / 520).clamp(0.0, 1.0);
        final at = _arcIn.transform(run);
        opacity = at.clamp(0.0, 1.0);
        scale = 0.6 + 0.4 * at;
        if (breathing != null && now >= breathing) {
          // @keyframes breathe { to { opacity: 0.45; } }: there and back, 2.6 s each way, over the arc's own opacity.
          final turn = (now - breathing) / 2600;
          final within = turn - turn.floorToDouble();
          final there = turn.floor().isEven ? within : 1 - within;
          opacity = 1 - 0.55 * breath.transform(there);
        }
      }
      if (opacity <= 0) continue;
      // d={`M${40 + r * Math.cos(-0.9)} ${60 + r * Math.sin(-0.9)} A${r} ${r} 0 0 1 ${40 + r * Math.cos(0.9)} ${60 + r * Math.sin(0.9)}`}
      final arc = Path()..addArc(Rect.fromCircle(center: const Offset(40, 60), radius: r), -0.9, 1.8);
      // .pictureArc {
      //   fill: none;
      //   stroke: currentColor;
      //   stroke-width: 9;
      //   stroke-linecap: round;
      //   transform-box: fill-box;
      //   transform-origin: left center;
      // }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: color.a * opacity);
      canvas.save();
      if (scale != 1) {
        // The arc's own box runs from its two ends to its middle; its left centre is level with the dot.
        final left = 40 + r * math.cos(0.9);
        canvas.translate(left, 60);
        canvas.scale(scale);
        canvas.translate(-left, -60);
      }
      if (failed) {
        for (final PathMetric metric in arc.computeMetrics()) {
          for (var from = 0.0; from < metric.length; from += 13) {
            canvas.drawPath(metric.extractPath(from, math.min(from + 6, metric.length)), paint);
          }
        }
      } else {
        canvas.drawPath(arc, paint);
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(OpeningPainter old) => old.color != color || old.failed != failed || old.breatheAt != breatheAt || !identical(old.clock, clock);
}
