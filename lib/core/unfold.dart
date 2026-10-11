/// The unfold: the note opening with the phone. A port of `src/app/core/unfold.ts`.
///
/// On a folding phone MainActivity streams the hinge angle (degrees, 0 closed to 180 flat) while the app is up
/// ([hingeAngles]). One UI hands the app from the cover screen to the inner display at about 30 degrees, and from
/// there to flat is the moment this draws: the note is paper folded down its middle, foreshortened with the crease's
/// shadow in the valley, and it flattens as the hinge does. The hand drives it, not a clock, so it runs exactly as
/// fast as the phone opens.
///
/// Two rules keep it out of the way. It only ever moves forward: a hinge that stops (flex mode, the phone propped at
/// a hundred degrees) settles the note flat on its own after a short pause rather than leaving it creased, and a
/// hinge closing never folds it back up. And it starts only on the way open: an app that wakes partway (the first
/// reading it ever sees is mid-hinge) joins in, and anything else sees the note flat.
///
/// [Unfold] is the machine, time passed in so it runs the same under test as on the phone. [UnfoldDriver] is the
/// page's `useUnfold`: it listens to the hinge and answers a progress to draw, 0 to 1, or null while the note is
/// flat. What differs from the web: the progress is a [ValueListenable] a widget draws from, where the page wrote
/// `--unfold` and `data-unfolding` onto the screen's element; and the frames are a [Ticker]'s.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Where One UI hands the app over to the inner display.
const double unfoldHandover = 30;

/// Where the note is fully open. Flat is 180, but the eye is done well before.
const double unfoldFlat = 115;

/// No reading for this long mid-unfold and the hinge has stopped: settle.
const int unfoldStallMs = 220;

/// How long a settle takes to reach flat.
const int unfoldSettleMs = 320;

/// No unfold runs longer than this, whatever the hinge is doing.
const int unfoldLongestMs = 1600;

/// How open the note is for a hinge angle: 0 at hand-over, 1 at flat, eased (`progressAt`).
double unfoldProgressAt(double angle) {
  final t = ((angle - unfoldHandover) / (unfoldFlat - unfoldHandover)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// The unfold as a state machine. [reading] is a hinge angle; [tick] is time passing without one. Both answer the
/// progress to draw, 1 meaning flat and idle.
class Unfold {
  double? _last;
  double _progress = 1;
  double? _startedAt;
  double _readAt = 0;
  ({double at, double from})? _settle;

  /// Whether an unfold is being drawn.
  bool get active => _startedAt != null;

  double reading(double angle, double now) {
    final before = _last;
    _last = angle;
    _readAt = now;
    final started = _startedAt;
    if (started == null) {
      // Opening through the hand-over, or an app that woke up mid-hinge.
      final opening = angle > unfoldHandover && (before == null ? angle < unfoldFlat : before <= unfoldHandover);
      if (!opening) return 1;
      _startedAt = now;
      _settle = null;
      _progress = unfoldProgressAt(angle);
      if (_progress >= 1) _end();
      return _progress;
    }
    if (angle <= unfoldHandover) {
      // Closed again before it finished: the cover screen is about to take over, and a note folding back up is not
      // a thing anyone asked to see.
      _end();
      return 1;
    }
    // Once settling, the hinge no longer drives; the settle finishes. An unfold that has dragged past its longest
    // starts settling here too, so a hinge inching open cannot hold the note creased for ever.
    if (_settle != null || now - started >= unfoldLongestMs) return tick(now);
    final at = unfoldProgressAt(angle);
    if (at > _progress) _progress = at;
    if (_progress >= 1) _end();
    return _progress;
  }

  double tick(double now) {
    final started = _startedAt;
    if (started == null) return 1;
    if (_settle == null && (now - _readAt >= unfoldStallMs || now - started >= unfoldLongestMs)) {
      _settle = (at: now, from: _progress);
    }
    final settle = _settle;
    if (settle != null) {
      final t = ((now - settle.at) / unfoldSettleMs).clamp(0.0, 1.0);
      final eased = 1 - (1 - t) * (1 - t) * (1 - t);
      _progress = settle.from + (1 - settle.from) * eased;
      if (t >= 1) _end();
    }
    return _progress;
  }

  /// Ends the unfold where it stands, flat. For a screen that can no longer draw it.
  void abandon() => _end();

  void _end() {
    _startedAt = null;
    _settle = null;
    _progress = 1;
  }
}

/// The hinge's channel (Hinge.kt): `angle`, in degrees, said as it changes on a folding phone while the app is
/// resumed. A phone without a hinge says nothing; anything but Android has no such channel.
const MethodChannel _hinge = MethodChannel('ghost_md/hinge');
StreamController<double>? _angles;

/// The hinge's angles, 0 closed to 180 flat; silent where there is no hinge to read. Nothing is asked of the phone:
/// the activity says each angle, and a word said before anything listens is dropped.
Stream<double> hingeAngles() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return const Stream<double>.empty();
  final held = _angles;
  if (held != null) return held.stream;
  final angles = _angles = StreamController<double>.broadcast();
  _hinge.setMethodCallHandler((call) async {
    final value = call.arguments;
    if (call.method == 'angle' && value is num) angles.add(value.toDouble());
  });
  return angles.stream;
}

/// Draws the unfold (`useUnfold`): [progress] runs 0 to 1 while a note unfolds, and is null the rest of the time,
/// when a flat note costs nothing. Nothing happens where there is no hinge, or where motion is turned down
/// ([still]).
class UnfoldDriver {
  UnfoldDriver({Stream<double>? angles, required TickerProvider vsync, this.still = false, double Function()? now}) : _now = now ?? _clock {
    if (still) return;
    _ticker = vsync.createTicker((_) => _frame());
    _sub = (angles ?? hingeAngles()).listen(_reading);
  }

  static final Stopwatch _watch = Stopwatch()..start();
  static double _clock() => _watch.elapsedMicroseconds / 1000;

  /// `prefers-reduced-motion: reduce`.
  final bool still;
  final double Function() _now;
  final Unfold _machine = Unfold();
  Ticker? _ticker;
  StreamSubscription<double>? _sub;
  Timer? _guard;

  /// 0 to 1 while the note unfolds; null while it is flat.
  final ValueNotifier<double?> progress = ValueNotifier<double?>(null);

  void _draw(double value) {
    if (_machine.active && value < 1) {
      progress.value = value;
    } else {
      progress.value = null;
      _guard?.cancel();
      _guard = null;
      _ticker?.stop();
    }
  }

  void _frame() => _draw(_machine.tick(_now()));

  void _reading(double angle) {
    final wasActive = _machine.active;
    _draw(_machine.reading(angle, _now()));
    if (!_machine.active) return;
    final ticker = _ticker;
    if (ticker != null && !ticker.isActive) ticker.start();
    // Frames are how it settles, and an app that is not being shown gets no frames. So a creased note is never left
    // to wait for one: a timer past the longest an unfold can run flattens it whatever happened to the frames.
    if (!wasActive) _guard = Timer(const Duration(milliseconds: unfoldLongestMs + unfoldSettleMs + 100), flatten);
  }

  /// The phone going dark mid-unfold flattens it at once.
  void flatten() {
    _machine.abandon();
    _draw(1);
  }

  void dispose() {
    _sub?.cancel();
    _guard?.cancel();
    _ticker?.dispose();
    progress.dispose();
  }
}

/// The crease's shadow while the note unfolds (`.crease`, editor/NoteScreen.module.css): over the note, a band of
/// the ink down the middle that thins and fades as the paper flattens.
///
/// `background: linear-gradient(90deg, transparent 34%, color-mix(in srgb, var(--app-ink) 24%, transparent) 50%,
/// transparent 66%); opacity: calc(1 - var(--unfold)); transform: scaleX(calc(0.35 + 0.65 * (1 - var(--unfold))))`.
class UnfoldCrease extends StatelessWidget {
  const UnfoldCrease({super.key, required this.at, required this.ink});

  /// How open the note is, 0 to 1.
  final double at;

  /// `--app-ink`.
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final clear = ink.withValues(alpha: 0);
    return Opacity(
      opacity: (1 - at).clamp(0.0, 1.0),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(0.35 + 0.65 * (1 - at), 1, 1),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [clear, clear, ink.withValues(alpha: ink.a * 0.24), clear, clear], stops: const [0, 0.34, 0.5, 0.66, 1]),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
