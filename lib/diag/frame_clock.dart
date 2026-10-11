/// Frame times read off the app itself, for the smoke bench (lib/diag/wisp_bench.dart). A port of
/// `src/app/diag/frameClock.ts`.
///
/// A run drives a surface one way for one cell (nothing, a repaint a frame, a scroll a frame) and keeps every
/// frame's length until the frames or the wall clock run out. Two lessons from the hand-built rig are rules here. A
/// cell is capped by wall clock as well as frames, and says how many frames it got: a four-second cap on a
/// three-second frame gave one frame and no median. And the p90 is reported beside the median: an effect that is
/// usually fine and now and then six seconds is what "laggy" feels like.
///
/// What differs:
/// - **The clock.** The page asked `requestAnimationFrame` for each frame and `performance.now()` for the time.
///   Here a frame is asked of the scheduler (`SchedulerBinding.scheduleFrameCallback`, the thing a `Ticker` is made
///   of), which also asks the engine to draw one, and the time is the frame's own stamp
///   (`currentSystemFrameTimeStamp`): when the display said the frame began. So a frame's length is the gap between
///   two frames the engine began, as a browser's is; a frame the raster thread could not finish in time shows as the
///   display's ticks it missed. `SchedulerBinding.addTimingsCallback` would split a frame into its build and its
///   raster; nothing here reads it, since the bench's question is the page's, how long between frames.
/// - **The wall is counted from the cell's first frame**, where the page counted it from the call. Between frames
///   the scheduler's stamp is the last frame's, however long ago that was, so a cell begun after the app had stood
///   still would have met its wall before its first reading. The two differ by the wait for one frame.
/// - Under a test the stamps are the test's clock, so `tester.pump(16 ms)` is a 16 ms frame.
/// - [engineName] reads a browser's agent string and is kept for its tests and for a web build; what draws a Flutter
///   app is [drawnBy].
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';

/// What a cell measured: how many frames, and their lengths in milliseconds at three points (`Reading`).
class Reading {
  const Reading({required this.n, required this.median, required this.p90, required this.worst});

  /// No frames: nothing rather than NaN.
  static const Reading none = Reading(n: 0, median: 0, p90: 0, worst: 0);

  final int n;
  final double median, p90, worst;

  @override
  bool operator ==(Object other) => other is Reading && other.n == n && other.median == median && other.p90 == p90 && other.worst == worst;

  @override
  int get hashCode => Object.hash(n, median, p90, worst);

  @override
  String toString() => 'Reading(n: $n, median: $median, p90: $p90, worst: $worst)';
}

/// The three points of a run of frame lengths; an empty run reads as nothing rather than NaN (`summarise`).
Reading summarise(List<double> deltas) {
  if (deltas.isEmpty) return Reading.none;
  final sorted = [...deltas]..sort();
  double at(double share) {
    final index = (share * sorted.length).floor();
    return sorted[index < sorted.length - 1 ? index : sorted.length - 1];
  }

  return Reading(n: sorted.length, median: at(0.5), p90: at(0.9), worst: at(1));
}

/// One frame's number, in ms with one decimal (`ms`).
String ms(double value) => value.toStringAsFixed(1);

/// When a cell stops (`CellLimits`): after [frames] frames, or after [wallMs], whichever comes first, so an
/// expensive cell still ends.
class CellLimits {
  const CellLimits({required this.frames, required this.wallMs});
  final int frames;
  final double wallMs;
}

/// What a run uses for a frame and for the time, so a test can turn the clock by hand (`Clock`). [frame] calls back
/// once, at the next frame, with that frame's time in milliseconds; [now] is the time on the same clock, which for
/// the scheduler's is the stamp of the frame being drawn, or of the last one drawn.
class FrameClock {
  const FrameClock({required this.frame, required this.now});
  final void Function(void Function(double now) callback) frame;
  final double Function() now;
}

double _stamp() => SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds / 1000;

/// The scheduler's frames and their own stamps (`REAL_CLOCK`; see the header).
final FrameClock realClock = FrameClock(
  frame: (callback) => SchedulerBinding.instance.scheduleFrameCallback((_) => callback(_stamp())),
  now: _stamp,
);

/// Runs one cell (`runCell`): [drive] is called once per frame with the frame's index (to move or repaint the
/// surface, or to do nothing) and the frame's length is kept, until the limits say stop. The first frame's length is
/// not kept, since it measures the wait for the run to start rather than a frame of the driving.
Future<Reading> runCell(void Function(int frame) drive, CellLimits limits, [FrameClock? clock]) {
  final on = clock ?? realClock;
  final done = Completer<Reading>();
  final deltas = <double>[];
  double? started;
  var last = -1.0;
  var index = 0;
  void tick(double now) {
    if (last >= 0) deltas.add(now - last);
    last = now;
    started ??= now;
    if (deltas.length >= limits.frames || now - started! >= limits.wallMs) {
      done.complete(summarise(deltas));
      return;
    }
    drive(index++);
    on.frame(tick);
  }

  on.frame(tick);
  return done.future;
}

/// A rolling read of the frames as they come, for the live counter beside a surface someone is scrolling by hand
/// (`FrameRing`): every frame's length goes in, the last [keep] are summarised on demand.
class FrameRing {
  FrameRing([this.keep = 120]);

  final int keep;
  final List<double> _deltas = [];
  double _last = -1;

  /// A frame happened at [now].
  void mark(double now) {
    if (_last >= 0) {
      _deltas.add(now - _last);
      if (_deltas.length > keep) _deltas.removeAt(0);
    }
    _last = now;
  }

  /// Forgets the frames so far (when the surface changes, the old frames say nothing about the new one).
  void reset() {
    _deltas.clear();
    _last = -1;
  }

  Reading read() => summarise(_deltas);
}

/// Which engine is drawing a page, from the only thing a page can see of it (`engineName`): `WebKit`, `Chromium`,
/// `Gecko` or `unknown`.
String engineName(String userAgent) {
  if (userAgent.contains('Firefox/')) return 'Gecko';
  if (RegExp(r'Chrome/|Chromium/|CriOS/').hasMatch(userAgent)) return 'Chromium';
  if (userAgent.contains('AppleWebKit/')) return 'WebKit';
  return 'unknown';
}

/// What draws this app: `Impeller` or `Skia`, told apart by the one thing only Impeller does (a fragment shader as
/// an image filter); `Flutter` where the engine will not say. The app's counterpart of [engineName].
String drawnBy() {
  try {
    return ui.ImageFilter.isShaderFilterSupported ? 'Impeller' : 'Skia';
  } catch (_) {
    return 'Flutter';
  }
}
