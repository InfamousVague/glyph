import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/launch/eyes.dart';
import 'package:ghost_md/launch/launch_screen.dart';

/// `launch/eyes.test.ts`, case for case.
void main() {
  group('the ghost watching the bar', () {
    test('turns an eye as far as it goes toward what it looks at, near or far', () {
      final eye = eyes[0];
      expect(lookAt(eye, eye + const Offset(50, 0)), const Offset(lookX, 0));
      expect(lookAt(eye, eye + const Offset(0, -3)), const Offset(0, -lookY));
      final corner = lookAt(eye, eye + const Offset(-10, 10));
      expect(corner.dx, closeTo(-lookX / math.sqrt2, 1e-9));
      expect(corner.dy, closeTo(lookY / math.sqrt2, 1e-9));
      // Looking at itself, it looks ahead.
      expect(lookAt(eye, eye), Offset.zero);
    });

    test('puts the bar a lap round every lap, and names its middle', () {
      expect(barAt(0).middle, dash / 200);
      expect(barAt(0).offset, 0);
      expect(barAt(lapMs / 2).offset, closeTo(-50, 1e-9));
      expect(barAt(lapMs / 2).middle, closeTo(0.5 + dash / 200, 1e-9));
      expect(barAt(lapMs * 3 + 10).middle, closeTo(barAt(10).middle, 1e-9));
      expect(barAt(lapMs * 3 + 10).offset, closeTo(barAt(10).offset, 1e-9));
      // Near the end of a lap the middle has come round past the start.
      expect(barAt(lapMs * 0.99).middle, closeTo(0.99 + dash / 200 - 1, 1e-9));
    });

    test('catches up most of the way in a tenth of a second, and none of it in no time', () {
      expect(easeFor(0), 0);
      expect(easeFor(100), greaterThan(0.6));
      expect(easeFor(1000), greaterThan(0.99));
    });
  });

  group('the drawing', () {
    test('a squircle is the web\'s: 96 points from the right-hand middle, clockwise, to the hundredth', () {
      final ring = squircle(64, 58);
      expect(ring, hasLength(96));
      expect(ring.first, const Offset(122, 64));
      // A quarter round is straight down; a squircle's corner is further out than a circle's.
      expect(ring[24], const Offset(64, 122));
      expect((ring[12] - const Offset(64, 64)).distance, greaterThan(58 * 1.2));
      for (final point in ring) {
        expect((point.dx * 100 - (point.dx * 100).round()).abs(), lessThan(1e-9));
      }
    });

    test('the wink shuts the eye, holds it, and opens it again', () {
      expect(winkScale(0), 1);
      expect(winkScale(0.15), closeTo(0.55, 1e-6));
      expect(winkScale(0.30), closeTo(0.1, 1e-6));
      expect(winkScale(0.5), 0.1);
      expect(winkScale(0.62), closeTo(0.1, 1e-6));
      expect(winkScale(0.81), closeTo(0.55, 1e-6));
      expect(winkScale(1), 1);
    });
  });
}
