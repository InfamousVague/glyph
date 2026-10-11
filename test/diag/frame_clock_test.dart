import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/diag/frame_clock.dart';

/// `diag/frameClock.test.ts`, case for case: the bench's clock, turned by hand. The two rules it exists for are the
/// two that were learned the hard way in the hand-built rig: a cell ends on the wall clock as well as on its frame
/// count and says how many frames it got, and the p90 stands beside the median. Then the scheduler's own clock,
/// which the page had no counterpart of.

/// A clock whose frames are as long as the caller says, one after another.
FrameClock clockOf(List<double> lengths) {
  var now = 0.0;
  var started = false;
  void Function(double now)? pending;
  final frames = [...lengths];
  return FrameClock(
    now: () => now,
    frame: (callback) {
      pending = callback;
      // Run on a microtask so a run reads as asynchronous, as the real one does.
      scheduleMicrotask(() {
        final next = pending;
        pending = null;
        if (next == null) return;
        // The first frame arrives at once; every later one after the next length in the list.
        if (started) now += frames.isNotEmpty ? frames.removeAt(0) : 16.7;
        started = true;
        next(now);
      });
    },
  );
}

void main() {
  group('summarise', () {
    test('reads the median, p90 and worst off a run, and the count', () {
      final reading = summarise([16, 17, 16, 3000, 16, 17, 16, 16, 17, 16]);
      expect(reading.n, 10);
      expect(reading.median, 16);
      expect(reading.p90, 3000);
      expect(reading.worst, 3000);
    });

    test('reads nothing off no frames rather than NaN', () {
      expect(summarise([]), const Reading(n: 0, median: 0, p90: 0, worst: 0));
    });
  });

  group('runCell', () {
    test('stops at the frame count when the frames are quick, and drives every frame', () async {
      final driven = <int>[];
      final reading = await runCell(driven.add, const CellLimits(frames: 5, wallMs: 10000), clockOf([16, 16, 16, 16, 16, 16]));
      expect(reading.n, 5);
      expect(reading.median, 16);
      // The first frame starts the run and isn't a reading; the five after it are.
      expect(driven, [0, 1, 2, 3, 4]);
    });

    test('stops on the wall clock when the frames are slow, and says how few it got', () async {
      // Three-second frames against a ten-second wall: the rig's four-second cap gave one frame and no median.
      final reading = await runCell((_) {}, const CellLimits(frames: 120, wallMs: 10000), clockOf([3000, 3000, 3000, 3000, 3000]));
      expect(reading.n, 4);
      expect(reading.median, 3000);
    });

    test('keeps the p90 apart from the median, since one slow frame in ten is what lag feels like', () async {
      final reading = await runCell((_) {}, const CellLimits(frames: 10, wallMs: 60000), clockOf([16, 16, 16, 16, 16, 16, 16, 16, 16, 6500]));
      expect(reading.median, 16);
      expect(reading.p90, 6500);
    });
  });

  group('FrameRing', () {
    test('keeps only the last frames, and forgets them on reset', () {
      final ring = FrameRing(3);
      for (final at in const [0.0, 10.0, 20.0, 30.0, 1000.0]) {
        ring.mark(at);
      }
      // Four lengths were seen (10, 10, 10, 970); the ring holds the last three.
      expect(ring.read(), const Reading(n: 3, median: 10, p90: 970, worst: 970));
      ring.reset();
      expect(ring.read().n, 0);
      // After a reset the next mark is a start, not a length.
      ring.mark(5000);
      expect(ring.read().n, 0);
    });
  });

  group('engineName', () {
    test('tells the Mac app apart from the browser pane', () {
      expect(engineName('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)'), 'WebKit');
      expect(engineName('Mozilla/5.0 (Macintosh) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36'), 'Chromium');
      expect(engineName('Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0'), 'Gecko');
      expect(engineName('curl/8.4'), 'unknown');
    });
  });

  group('the scheduler’s clock', () {
    testWidgets('reads a frame’s length off the frames the engine began, and ends a cell on its count', (tester) async {
      final driven = <int>[];
      Reading? reading;
      unawaited(runCell(driven.add, const CellLimits(frames: 4, wallMs: 10000)).then((got) => reading = got));
      // The first frame starts the run; each pump after it is one frame, as long as the pump says.
      await tester.pump();
      for (final length in const [16, 16, 16, 100]) {
        expect(reading, isNull);
        await tester.pump(Duration(milliseconds: length));
      }
      await tester.pump();
      expect(reading, const Reading(n: 4, median: 16, p90: 100, worst: 100));
      expect(driven, [0, 1, 2, 3]);
      // The cell asked for no frame after its last.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('ends a cell on the wall when the frames are slow', (tester) async {
      Reading? reading;
      unawaited(runCell((_) {}, const CellLimits(frames: 120, wallMs: 5000)).then((got) => reading = got));
      await tester.pump();
      for (var i = 0; i < 3 && reading == null; i++) {
        await tester.pump(const Duration(seconds: 2));
      }
      await tester.pump();
      expect(reading?.n, 3);
      expect(reading?.median, 2000);
    });

    test('names what draws the app', () {
      expect(['Impeller', 'Skia', 'Flutter'], contains(drawnBy()));
    });
  });
}
