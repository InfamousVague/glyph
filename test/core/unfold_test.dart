import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/unfold.dart';

/// The unfold (core/unfold.dart): `src/app/core/unfold.test.ts` case for case, and the driver a screen draws from.
void main() {
  group('the unfold', () {
    test('starts as the hinge opens through the hand-over and follows it to flat', () {
      final unfold = Unfold();
      expect(unfold.reading(0, 0), 1);
      expect(unfold.reading(20, 10), 1);
      expect(unfold.active, isFalse);
      final first = unfold.reading(40, 20);
      expect(unfold.active, isTrue);
      expect(first, greaterThan(0));
      expect(first, lessThan(0.2));
      final mid = unfold.reading(75, 30);
      expect(mid, greaterThan(first));
      expect(mid, lessThan(1));
      expect(unfold.reading(unfoldFlat + 5, 40), 1);
      expect(unfold.active, isFalse);
    });

    test('never folds back up on a wobble, and closing ends it flat', () {
      final unfold = Unfold();
      unfold.reading(10, 0);
      unfold.reading(70, 10);
      final at70 = unfold.reading(70, 20);
      expect(unfold.reading(62, 30), at70);
      expect(unfold.reading(unfoldHandover - 1, 40), 1);
      expect(unfold.active, isFalse);
    });

    test('settles flat on its own when the hinge stops partway', () {
      final unfold = Unfold();
      unfold.reading(0, 0);
      final held = unfold.reading(80, 10);
      expect(unfold.tick(10.0 + unfoldStallMs - 1), held);
      expect(unfold.tick(10.0 + unfoldStallMs), held);
      final later = unfold.tick(10 + unfoldStallMs + unfoldSettleMs / 2);
      expect(later, greaterThan(held));
      expect(later, lessThan(1));
      expect(unfold.tick(10.0 + unfoldStallMs + unfoldSettleMs), 1);
      expect(unfold.active, isFalse);
    });

    test('ignores the hinge once it has begun to settle', () {
      final unfold = Unfold();
      unfold.reading(0, 0);
      unfold.reading(60, 10);
      final settling = unfold.tick(10.0 + unfoldStallMs + 40);
      final next = unfold.reading(100, 10.0 + unfoldStallMs + 41);
      expect(next, greaterThanOrEqualTo(settling));
      expect(next, lessThan(unfoldProgressAt(100)));
    });

    test('gives up on an unfold that drags on', () {
      final unfold = Unfold();
      unfold.reading(0, 0);
      var now = 0.0;
      for (var angle = 35.0; angle < 60; angle += 1) {
        now += 100;
        unfold.reading(angle, now);
      }
      expect(now, greaterThan(unfoldLongestMs));
      expect(unfold.tick(now + unfoldSettleMs), 1);
      expect(unfold.active, isFalse);
    });

    test('joins an unfold already under way when the app wakes mid-hinge, and nothing else', () {
      final woke = Unfold();
      expect(woke.reading(70, 0), lessThan(1));
      expect(woke.active, isTrue);
      final closed = Unfold();
      expect(closed.reading(0, 0), 1);
      expect(closed.active, isFalse);
      final flat = Unfold();
      expect(flat.reading(180, 0), 1);
      expect(flat.active, isFalse);
    });

    test('eases from hand-over to flat', () {
      expect(unfoldProgressAt(unfoldHandover), 0);
      expect(unfoldProgressAt(unfoldFlat), 1);
      expect(unfoldProgressAt((unfoldHandover + unfoldFlat) / 2), closeTo(0.5, 1e-5));
      expect(unfoldProgressAt(-10), 0);
      expect(unfoldProgressAt(180), 1);
    });
  });

  group('the driver', () {
    testWidgets('draws from the hinge while it opens, settles when it stops, and is null while flat', (tester) async {
      final angles = StreamController<double>();
      var now = 0.0;
      final driver = UnfoldDriver(angles: angles.stream, vsync: tester, now: () => now);
      expect(driver.progress.value, isNull);
      angles.add(10);
      await tester.pump();
      expect(driver.progress.value, isNull);
      now = 10;
      angles.add(60);
      await tester.pump();
      final at60 = driver.progress.value;
      expect(at60, isNotNull);
      expect(at60, lessThan(1));
      // The hinge stops: after the stall the frames carry it flat.
      now = 10.0 + unfoldStallMs;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(driver.progress.value, at60);
      now += unfoldSettleMs / 2;
      await tester.pump(const Duration(milliseconds: 16));
      expect(driver.progress.value, greaterThan(at60!));
      now += unfoldSettleMs;
      await tester.pump(const Duration(milliseconds: 16));
      expect(driver.progress.value, isNull);
      driver.dispose();
      unawaited(angles.close());
    });

    testWidgets('does nothing where motion is turned down, and a dark phone flattens it at once', (tester) async {
      final angles = StreamController<double>.broadcast();
      final still = UnfoldDriver(angles: angles.stream, vsync: tester, still: true);
      final moving = UnfoldDriver(angles: angles.stream, vsync: tester, now: () => 0);
      angles.add(70);
      await tester.pump();
      expect(still.progress.value, isNull);
      expect(moving.progress.value, isNotNull);
      moving.flatten();
      expect(moving.progress.value, isNull);
      still.dispose();
      moving.dispose();
      unawaited(angles.close());
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
