/// What the app's frames cost, kept by the stretch of use they were drawn in, in a build made to be measured
/// (`--dart-define=GHOST_PERF=true`; lib/perf/perf_run.dart walks the app and reads this).
///
/// Matt, 2026-10-10: "The flutter app is still significantly more laggy than the react native version". Lag is a
/// frame that took longer than the screen gives it, so this keeps every frame's two halves as the engine itself
/// timed them (`FrameTiming`): the **build** (Dart on the UI thread: building widgets, layout, painting into layers)
/// and the **raster** (the GPU's side: the layers drawn, every shader, blur and offscreen picture). Which half is
/// over says where to look; a count that cannot fail says nothing, so the numbers here are the engine's own and a
/// stretch with no frames says so.
///
/// The engine hands timings over in batches, about once a second in a release build and ten times in a profile one,
/// so a stretch is closed a moment after it ends ([mark]) and its frames are picked by their own clock
/// (`Timeline.now`'s), not by when they were heard of.
library;

import 'dart:developer' show Timeline;
import 'dart:ui' show FramePhase, FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Whether this build measures itself. Nothing below costs anything in a build that does not: every call site asks
/// this constant first, and the compiler takes the rest away.
const bool ghostPerf = bool.fromEnvironment('GHOST_PERF');

/// One stretch's frames, summed up.
@immutable
class FrameStats {
  const FrameStats({
    required this.name,
    required this.began,
    required this.ended,
    required this.milliseconds,
    required this.frames,
    required this.budgetMs,
    required this.build,
    required this.raster,
    required this.slow,
    required this.dropped,
    required this.counts,
  });

  final String name;

  /// When the stretch began and ended, on `Timeline.now`'s clock in microseconds: the clock the VM stamps its CPU
  /// samples with, so a profile can be cut by stretch (tool/perf_cpu.dart).
  final int began;
  final int ended;

  /// How long the stretch lasted, by the clock.
  final double milliseconds;
  final int frames;

  /// What the screen gives a frame: 8.3 ms at 120 Hz, 16.7 at 60.
  final double budgetMs;

  /// The UI thread's half and the raster thread's: the middle frame, the slow tenth, the slowest hundredth, the worst.
  final ({double p50, double p90, double p99, double max}) build;
  final ({double p50, double p90, double p99, double max}) raster;

  /// Frames whose two halves together were over the budget: each was late to the screen.
  final int slow;

  /// Refreshes of the screen that went by with nothing new while frames were being drawn one after another: the
  /// gaps between one frame's start and the next, counted in whole refreshes missed. A stretch that was simply
  /// still has none.
  final int dropped;

  /// What was counted meanwhile ([Perf.count], [Perf.add]): how many, and for the timed ones how long in all.
  final Map<String, ({int n, double ms})> counts;

  Map<String, Object?> toJson() => {
        'name': name,
        'began': began,
        'ended': ended,
        'ms': _round(milliseconds),
        'frames': frames,
        'budgetMs': _round(budgetMs),
        'build': {'p50': _round(build.p50), 'p90': _round(build.p90), 'p99': _round(build.p99), 'max': _round(build.max)},
        'raster': {'p50': _round(raster.p50), 'p90': _round(raster.p90), 'p99': _round(raster.p99), 'max': _round(raster.max)},
        'slow': slow,
        'dropped': dropped,
        if (counts.isNotEmpty)
          'counts': {
            for (final entry in counts.entries) entry.key: entry.value.ms > 0 ? {'n': entry.value.n, 'ms': _round(entry.value.ms)} : entry.value.n,
          },
      };

  static double _round(double value) => (value * 100).roundToDouble() / 100;

  /// One line, for the log.
  String said() {
    String half(({double p50, double p90, double p99, double max}) of) =>
        '${of.p50.toStringAsFixed(1)}/${of.p90.toStringAsFixed(1)}/${of.p99.toStringAsFixed(1)}/${of.max.toStringAsFixed(1)}';
    final counted = [
      for (final entry in counts.entries) entry.value.ms > 0 ? '${entry.key}=${entry.value.n}(${entry.value.ms.toStringAsFixed(1)}ms)' : '${entry.key}=${entry.value.n}',
    ].join(' ');
    return '$name: ${milliseconds.round()}ms, $frames frames, build ${half(build)} raster ${half(raster)} ms (p50/p90/p99/max), '
        '$slow slow of ${budgetMs.toStringAsFixed(1)}ms, $dropped dropped${counted.isEmpty ? '' : ' | $counted'}';
  }
}

/// Counters and clocks for what a frame did, read and emptied with each stretch. A call site asks [ghostPerf]
/// first, so none of this is in a build that does not measure:
///
/// ```dart
/// if (ghostPerf) Perf.count('root.build');
/// final began = ghostPerf ? Perf.now() : 0;
/// ...
/// if (ghostPerf) Perf.add('library.reads', began);
/// ```
abstract final class Perf {
  static final Map<String, int> _counts = {};
  static final Map<String, int> _micros = {};
  static final Stopwatch _watch = Stopwatch()..start();

  static void count(String name, [int by = 1]) => _counts[name] = (_counts[name] ?? 0) + by;

  /// The clock a timed stretch of code begins on: hand it to [add].
  static int now() => _watch.elapsedMicroseconds;

  /// Counts one more [name] and the time since [began].
  static void add(String name, int began) {
    _counts[name] = (_counts[name] ?? 0) + 1;
    _micros[name] = (_micros[name] ?? 0) + (_watch.elapsedMicroseconds - began);
  }

  static Map<String, ({int n, double ms})> _take() {
    final taken = {
      for (final entry in _counts.entries) entry.key: (n: entry.value, ms: (_micros[entry.key] ?? 0) / 1000),
    };
    _counts.clear();
    _micros.clear();
    return taken;
  }
}

/// Every frame's timing since [install], and the stretches they are summed by.
class FrameLog {
  FrameLog._();
  static final FrameLog instance = FrameLog._();

  final List<FrameTiming> _heard = [];
  String _name = 'launch';
  int _began = Timeline.now;
  bool _installed = false;

  /// Each stretch closed so far, in order.
  final List<FrameStats> stretches = [];

  /// Begins listening. Asked twice, listens once.
  void install() {
    if (_installed) return;
    _installed = true;
    _began = Timeline.now;
    SchedulerBinding.instance.addTimingsCallback(_heard.addAll);
  }

  /// What the screen gives a frame, in milliseconds, from its own refresh rate.
  static double get budgetMs {
    final views = PlatformDispatcher.instance.views;
    final rate = views.isEmpty ? 60.0 : views.first.display.refreshRate;
    return 1000 / (rate > 0 ? rate : 60);
  }

  /// Ends the stretch in hand and begins [name]. Waits first for the timings the engine has not handed over yet.
  /// A stretch is kept and said to the log unless it is [quiet] and had no frames at all: the app was still.
  Future<FrameStats> mark(String name, {bool quiet = false}) async {
    final ended = Timeline.now;
    // A release build hears of its frames once a second.
    await Future<void>.delayed(Duration(milliseconds: kReleaseMode ? 1300 : 300));
    final stats = _stats(_name, _began, ended);
    if (!quiet || stats.frames > 0) {
      stretches.add(stats);
      debugPrint('[perf] ${stats.said()}');
    }
    _name = name;
    _began = Timeline.now;
    return stats;
  }

  FrameStats _stats(String name, int from, int to) {
    final frames = [
      for (final frame in _heard)
        if (frame.timestampInMicroseconds(FramePhase.vsyncStart) >= from && frame.timestampInMicroseconds(FramePhase.vsyncStart) < to) frame,
    ];
    _heard.removeWhere((frame) => frame.timestampInMicroseconds(FramePhase.vsyncStart) < to);
    final budget = budgetMs;
    double ms(Duration time) => time.inMicroseconds / 1000;
    ({double p50, double p90, double p99, double max}) spread(Iterable<double> values) {
      final sorted = values.toList()..sort();
      if (sorted.isEmpty) return (p50: 0, p90: 0, p99: 0, max: 0);
      double at(double part) => sorted[((sorted.length - 1) * part).round()];
      return (p50: at(0.5), p90: at(0.9), p99: at(0.99), max: sorted.last);
    }

    var slow = 0, dropped = 0;
    for (var i = 0; i < frames.length; i += 1) {
      if (ms(frames[i].buildDuration) + ms(frames[i].rasterDuration) > budget) slow += 1;
      if (i == 0) continue;
      // Frames drawn one after another start a refresh apart. A gap of a few refreshes is refreshes missed; a long
      // one is the app being still, which is no fault.
      final gap = (frames[i].timestampInMicroseconds(FramePhase.vsyncStart) - frames[i - 1].timestampInMicroseconds(FramePhase.vsyncStart)) / 1000;
      final missed = (gap / budget).round() - 1;
      if (missed >= 1 && missed <= 12) dropped += missed;
    }
    return FrameStats(
      name: name,
      began: from,
      ended: to,
      milliseconds: (to - from) / 1000,
      frames: frames.length,
      budgetMs: budget,
      build: spread(frames.map((frame) => ms(frame.buildDuration))),
      raster: spread(frames.map((frame) => ms(frame.rasterDuration))),
      slow: slow,
      dropped: dropped,
      counts: Perf._take(),
    );
  }
}
