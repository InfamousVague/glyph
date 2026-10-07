import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';

/// Gears that mesh, and the update card's three cogs: the web app's art/gears.test.ts and art/WorkingGears.test.tsx.
void main() {
  /// How far a phase sum may be from a half before the teeth would show crossing.
  const near = 1e-6;

  /// Distance around the unit circle from [value]'s fraction to a half.
  double offHalf(double value) => (value - value.floorToDouble() - 0.5).abs();

  group('two gears meshing', () {
    test('keeps a tooth of one in a gap of the other as they turn at their rolling speeds', () {
      const teethA = 30, teethB = 12;
      const direction = 0.83;
      const phaseA = 0.4, omegaA = 0.7;
      final phaseB = outsidePhase(teethA, phaseA, direction, teethB);
      const omegaB = -omegaA * teethA / teethB;
      for (var t = 0.0; t < 40; t += 0.37) {
        final sum = toothPhase(teethA, phaseA + omegaA * t, direction) + toothPhase(teethB, phaseB + omegaB * t, direction + math.pi);
        expect(offHalf(sum), lessThan(near));
      }
    });

    test('would cross their teeth without the meshing angle, so the check above can fail', () {
      // The same pair with the second gear simply at zero: a tooth of each points at the other.
      expect(offHalf(toothPhase(30, 0.4, 0.83) + toothPhase(12, 0, 0.83 + math.pi)), greaterThan(0.01));
    });
  });

  group('a spur gear', () {
    test('draws a tip arc and a root arc for each tooth, then its hub', () {
      int arcs(String path) => ' A '.allMatches(path).length;
      expect(arcs(spurPath(16, 4, Hub.plain)), greaterThanOrEqualTo(32));
      // The hub is cut after the teeth: more holes, more arcs, the same teeth.
      expect(arcs(spurPath(24, 4, Hub.holes)), greaterThan(arcs(spurPath(24, 4, Hub.plain))));
      expect('Z'.allMatches(spurPath(24, 4, Hub.spokes)).length, greaterThan(2));
    });

    test('is a path the app can draw, a tooth\'s tip at its pitch radius and a module', () {
      final bounds = parseSvgPath(spurPath(13, 1.9, Hub.holes)).getBounds();
      expect(bounds.right, closeTo(pitchRadius(13, 1.9) + 1.9, 0.02));
    });
  });

  group('the working cogs', () {
    test('sit a pitch apart and mesh, each with the one that drives it', () {
      final drawn = workingGears().cogs;
      expect(drawn, hasLength(3));
      expect(drawn.map((cog) => cog.teeth).toList(), workingGearsTeeth);
      for (final i in [1, 2]) {
        final driver = drawn[i - 1], driven = drawn[i];
        final between = driven.at - driver.at;
        expect(between.distance, closeTo(pitchRadius(driver.teeth, workingGearsModule) + pitchRadius(driven.teeth, workingGearsModule), 1e-9));
        final sum = toothPhase(driver.teeth, driver.angle, between.direction) + toothPhase(driven.teeth, driven.angle, between.direction + math.pi);
        // A tooth of one faces a gap of the other: the phases add up to a half.
        expect(offHalf(sum), lessThan(1e-9));
      }
    });

    test('turn the other way from their driver, faster by the ratio of their teeth', () {
      final drawn = workingGears().cogs;
      for (final i in [1, 2]) {
        expect(drawn[i].way, -drawn[i - 1].way);
        // Rounded to the hundredth of a second the stylesheet is given.
        expect(drawn[i].seconds, closeTo(drawn[0].seconds * drawn[i].teeth / drawn[0].teeth, 0.006));
      }
      expect(drawn[0].seconds, 3.4);
      expect(drawn[1].seconds, 2.35);
      expect(drawn[2].seconds, 1.83);
    });

    test('stay meshed while they turn, each about its own middle', () {
      final drawn = workingGears().cogs;
      // Over the first second the hundredths the times were rounded to have not yet pulled a tooth out of its gap.
      for (var t = 0.0; t <= 1; t += 0.05) {
        for (final i in [1, 2]) {
          final direction = (drawn[i].at - drawn[i - 1].at).direction;
          final sum = toothPhase(drawn[i - 1].teeth, drawn[i - 1].angleAt(t), direction) + toothPhase(drawn[i].teeth, drawn[i].angleAt(t), direction + math.pi);
          expect(offHalf(sum), lessThan(0.03));
        }
      }
    });

    test('are held in a box drawn round all three, a tooth\'s size to spare', () {
      final made = workingGears();
      for (final cog in made.cogs) {
        final reach = pitchRadius(cog.teeth, workingGearsModule) + workingGearsModule;
        expect(made.box.contains(cog.at - Offset(reach - 0.01, 0)) || cog.at.dx - reach >= made.box.left - 1e-9, isTrue);
        expect(cog.at.dy + reach, lessThanOrEqualTo(made.box.bottom + 1e-9));
        expect(cog.at.dy - reach, greaterThanOrEqualTo(made.box.top - 1e-9));
      }
      expect(made.box.left, closeTo(-14.25, 1e-9));
      expect(made.box.width, closeTo(55.1274470829416, 1e-9));
    });

    Widget host(Widget child, {bool still = false}) => MediaQuery(
          data: MediaQueryData(disableAnimations: still),
          child: Directionality(textDirection: TextDirection.ltr, child: DefaultTextStyle(style: const TextStyle(fontSize: 20, color: Color(0xFFFFFFFF)), child: Align(alignment: Alignment.topLeft, child: child))),
        );

    testWidgets('are one picture, named for what is happening, as tall as the words beside them', (tester) async {
      await tester.pumpWidget(host(const WorkingGears(label: 'Downloading')));
      expect(tester.getSemantics(find.byType(WorkingGears)).label, 'Downloading');
      final size = tester.getSize(find.byType(CustomPaint).last);
      final box = workingGears().box;
      expect(size.height, closeTo(1.15 * 20, 1e-9));
      expect(size.width / size.height, closeTo(box.width / box.height, 1e-9));
      // Turning: a frame is asked for, and the next is drawn without a fault.
      expect(tester.binding.transientCallbackCount, 1);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('stand still when the phone asks for reduced motion', (tester) async {
      await tester.pumpWidget(host(const WorkingGears(), still: true));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.getSemantics(find.byType(WorkingGears)).label, 'Working');
    });
  });
}
