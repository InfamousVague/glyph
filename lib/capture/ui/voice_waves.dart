/// Rings rising from behind the microphone in the recorder's top line while a recording runs: a picture of sound, and
/// a mark that the mic is live. A port of `src/app/capture/VoiceWaves.tsx` and VoiceWaves.module.css.
///
/// They rose from the screen's edge beside the side key before, and only for a recording the key had started. Matt:
/// "move the ripple waves effect to show behind the mic icon in app when recording", so they are every recording's
/// now, and their source is the mic drawn in the top line (the `anchor`), measured where it is - nothing to guess and
/// nothing to set. In the page's faintest ink, over the words and under the top line, so the line and its mic sit in
/// front of them.
///
/// The voice sends them out (Matt: "make the ripple … react to the levels of my voice as I record the note"). In a
/// pause, one faint ring every 2.7 seconds, so the screen shows it is listening; talking, rings go out as often as
/// five a second, each wider, brighter, thicker and quicker the louder the voice (voice_level.dart `paceRings`).
/// Decoration only: it hears the level the recorder publishes and opens no microphone of its own. With reduced motion
/// three rings stand still.
///
/// What differs:
/// - The layer fills its parent, which the recorder makes the whole screen (a `Stack` with `Positioned.fill`), where
///   the page's was `position: fixed; inset: 0`. Its order among the recorder's layers is the recorder's to give:
///   over the page, the tips and the buttons, under the top line.
/// - The rings are painted on one canvas from a ticker, where the page added a circle each and animated it with Web
///   Animations. The frames are the same: the ring's whole run eased by `cubic-bezier(0.2, 0.6, 0.35, 1)`, its size
///   from 0.04 to its reach, its opacity up by a tenth of the way, down to a third by six tenths, and out.
/// - The mic's place is read every frame while the rings move, so a top line that shifts is followed without an
///   observer.
/// - It is found by `Key('voice-waves')` (the page's `data-testid`), and its canvas, drawn only once the layer has a
///   size, by `Key('voice-waves-rings')`.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../voice_level.dart';

/// More than this many rings on screen at once is a smear, not a picture of a voice (`MOST_RINGS`).
const int mostRings = 9;

/// The easing of a ring's whole run.
const Cubic _ringEase = Cubic(0.2, 0.6, 0.35, 1);

class VoiceWaves extends StatefulWidget {
  const VoiceWaves({super.key, required this.anchor});

  /// The mic in the recorder's top line: the rings rise from its centre.
  final GlobalKey anchor;

  @override
  State<VoiceWaves> createState() => _VoiceWavesState();
}

/// One ring on its way out.
class _Ring {
  _Ring({required this.shape, required this.bornAt, required this.at});

  final RingShape shape;
  final double bornAt;
  final Offset at;
}

class _VoiceWavesState extends State<VoiceWaves> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final GlobalKey _layer = GlobalKey();
  final ValueNotifier<double> _now = ValueNotifier<double>(0);
  final List<_Ring> _rings = <_Ring>[];
  RingPacer _pacer = RingPacer(smooth: 0, lastRingAt: double.negativeInfinity);
  void Function()? _off;
  double _level = 0;
  Offset _at = Offset.zero;
  bool _laidOut = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  /// The rings move only once the layer has a size, and never when the phone is set to reduce motion.
  void _sync() {
    final moving = _laidOut && !context.tokens.reducedMotion;
    if (moving && !_ticker.isActive) {
      _level = 0;
      _off = onVoiceLevel((next) => _level = next);
      _pacer = RingPacer(smooth: 0, lastRingAt: double.negativeInfinity);
      _rings.clear();
      _ticker.start();
    } else if (!moving && _ticker.isActive) {
      _stop();
    }
  }

  void _stop() {
    _ticker.stop();
    _off?.call();
    _off = null;
    _rings.clear();
  }

  /// The mic's centre in the layer, or null before either is on screen.
  Offset? _micCentre() {
    final mic = widget.anchor.currentContext?.findRenderObject();
    final layer = _layer.currentContext?.findRenderObject();
    if (mic is! RenderBox || layer is! RenderBox || !mic.attached || !layer.attached || !mic.hasSize || !layer.hasSize) return null;
    return layer.globalToLocal(mic.localToGlobal(mic.size.center(Offset.zero)));
  }

  void _tick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1000;
    final at = _micCentre();
    if (at != null) _at = at;
    _rings.removeWhere((ring) => now - ring.bornAt >= ring.shape.durationMs);
    final shape = paceRings(_pacer, _level, now);
    if (shape != null && _rings.length < mostRings) _rings.add(_Ring(shape: shape, bornAt: now, at: _at));
    _now.value = now;
  }

  /// After a frame: whether the layer has a size yet, and, for the rings that stand still, where the mic is.
  void _measure() {
    if (!mounted) return;
    final at = _micCentre();
    final layer = _layer.currentContext?.findRenderObject();
    final laidOut = layer is RenderBox && layer.hasSize && layer.size.width > 0;
    if (laidOut != _laidOut || (at != null && at != _at && !_ticker.isActive)) {
      setState(() {
        _laidOut = laidOut;
        if (at != null) _at = at;
      });
      _sync();
    }
  }

  @override
  void dispose() {
    _stop();
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    // .waves {
    //   position: fixed;
    //   inset: 0;
    //   z-index: 2;
    //   pointer-events: none;
    //   overflow: hidden;
    // }
    return IgnorePointer(
      key: const Key('voice-waves'),
      child: ExcludeSemantics(
        child: ClipRect(
          child: LayoutBuilder(
            key: _layer,
            builder: (context, box) {
              final width = box.maxWidth.isFinite ? box.maxWidth : 0.0;
              final height = box.maxHeight.isFinite ? box.maxHeight : 0.0;
              if (width <= 0) return const SizedBox.shrink();
              // Far enough to cross most of the screen's width, never the whole screen.
              final reach = math.min(math.max(width, height) * 0.5, width * 1.1);
              // .ring { fill: none; stroke: var(--app-ink-3); stroke-width: 2px; vector-effect: non-scaling-stroke; }
              return CustomPaint(
                key: const Key('voice-waves-rings'),
                size: Size(width, height),
                painter: VoiceRingsPainter(rings: _rings, now: _now, at: _at, reach: reach, color: t.color('app-ink-3'), still: t.reducedMotion),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The rings as they stand at `now`: each from the mic's centre as it was when the ring left, or, [still], three that
/// do not move.
class VoiceRingsPainter extends CustomPainter {
  VoiceRingsPainter({required List<Object> rings, required this.now, required this.at, required this.reach, required this.color, required this.still})
      : _rings = rings,
        super(repaint: now);

  final List<Object> _rings;
  final ValueNotifier<double> now;
  final Offset at;
  final double reach;
  final Color color;
  final bool still;

  /// How many rings are on their way out.
  int get count => still ? 3 : _rings.length;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()..style = PaintingStyle.stroke;
    if (still) {
      // .still { opacity: 0.25; transform: scale(0.35); }
      // .still:nth-child(2) { transform: scale(0.6); opacity: 0.15; }
      // .still:nth-child(3) { transform: scale(0.85); opacity: 0.08; }
      const rings = [(0.35, 0.25), (0.6, 0.15), (0.85, 0.08)];
      for (final (scale, opacity) in rings) {
        stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: color.a * opacity);
        canvas.drawCircle(at, reach * scale, stroke);
      }
      return;
    }
    for (final ring in _rings.cast<_Ring>()) {
      final shape = ring.shape;
      final run = ((now.value - ring.bornAt) / shape.durationMs).clamp(0.0, 1.0);
      final p = _ringEase.transform(run);
      // [{ transform: 'scale(0.04)', opacity: 0 }, { opacity, offset: 0.1 }, { opacity: opacity * 0.32, offset: 0.6 },
      //  { transform: `scale(${reach})`, opacity: 0 }]
      final scale = 0.04 + (shape.reach - 0.04) * p;
      final double opacity;
      if (p < 0.1) {
        opacity = shape.opacity * (p / 0.1);
      } else if (p < 0.6) {
        opacity = shape.opacity * (1 - 0.68 * ((p - 0.1) / 0.5));
      } else {
        opacity = shape.opacity * 0.32 * (1 - (p - 0.6) / 0.4);
      }
      if (opacity <= 0) continue;
      stroke
        ..strokeWidth = shape.stroke
        ..color = color.withValues(alpha: color.a * opacity.clamp(0.0, 1.0));
      canvas.drawCircle(ring.at, reach * scale, stroke);
    }
  }

  @override
  bool shouldRepaint(VoiceRingsPainter old) => old.at != at || old.reach != reach || old.color != color || old.still != still || !identical(old._rings, _rings);
}
