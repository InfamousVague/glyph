import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';

/// The two boxed wisps, a board lane's foot and the tab row's ends, as numbers: the web app's art/wispFoot.test.ts
/// and art/wispSides.test.ts, said of the smoke each answers where those are said of an SVG filter's attributes.
void main() {
  tearDown(WispSettings.instance.reset);

  group('wispFoot', () {
    test('reads the noise per pixel, at every lane size', () {
      final short = wispFoot(120, 240, ratio: 3)!, tall = wispFoot(400, 240, ratio: 3)!;
      expect(short.frequency, const Offset(0.02, 0.07));
      expect(tall.frequency, short.frequency);
      expect(short.seed, 3);
    });

    test('places the band at the lane\'s own foot, so the test above can fail', () {
      final short = wispFoot(121, 240, ratio: 3)!, tall = wispFoot(401, 240, ratio: 3)!;
      // The lip sits its lift and its band above the foot, wherever the foot is.
      expect(short.lipB, 121 - 26);
      expect(tall.lipB, 401 - 26);
      expect(short.lipA, isNull);
      expect(short.axis, Axis.vertical);
      expect(wispFootLaneWithin(401, 240), const Rect.fromLTWH(-40, 401 - 106, 320, 146));
    });

    test('scales the band to a short lane and leaves a tall one whole', () {
      // A lane with room for the whole band gets the full fade; a shorter one gets a smaller band and a shorter fade.
      expect(wispFootFade(300), wispFootFade(150));
      expect(wispFootFade(300), 22);
      expect(wispFootFade(91), lessThan(wispFootFade(300)));
      expect(wispFootFit(106), 1);
      expect(wispFootFit(91), closeTo(75 / 90, 1e-12));
      final shape = wispFootShape(91);
      expect(shape.soft, closeTo(16 * 75 / 90, 1e-12));
      // Under the shortest lane that can carry a band there is no smoke at all, and the lane keeps its plain fade.
      expect(wispFoot(40, 240, ratio: 3), isNull);
      expect(wispFoot(61, 240, ratio: 3), isNotNull);
    });

    test('fades from where the lip is whole, down to the lane\'s foot', () {
      final smoke = wispFoot(300, 240, ratio: 3)!;
      expect(smoke.fade, const WispFade(wholeUntil: 300 - 22, clearFrom: 300));
      expect(smoke.fade.at(100), 1);
      expect(smoke.fade.at(289), closeTo(0.5, 1e-9));
      expect(smoke.fade.at(300), 0);
    });

    test('is not worn switched off, with reduced motion, or past the budget', () {
      expect(wispFoot(300, 240, ratio: 3, still: true), isNull);
      expect(wispFoot(300, 240, ratio: 3, wanted: false), isNull);
      WispSettings.instance.wanted = false;
      expect(wispFoot(300, 240, ratio: 3), isNull);
      WispSettings.instance.wanted = true;
      expect(wispFoot(5000, 5000, ratio: 1), isNull);
      expect(wispFoot(3000, 3000, ratio: 1), isNotNull);
    });

    test('throws as far as Chromium throws it: the meant bend by the lane\'s width over its corner', () {
      expect(boxCorner(300, 400), closeTo(353.5534, 1e-3));
      expect(wispFoot(300, 390, ratio: 3)!.bend, closeTo(28 * 390 / boxCorner(390, 300), 1e-9));
      // A lane as wide as it is tall is thrown as far as was meant.
      expect(wispFoot(300, 300, ratio: 3)!.bend, closeTo(28, 1e-9));
    });
  });

  group('wispSides', () {
    test('reads the noise per pixel, at every row size', () {
      final narrow = wispSides(375, 41, true, true, ratio: 3)!, wide = wispSides(1024, 44, true, true, ratio: 3)!;
      expect(narrow.frequency, const Offset(0.07, 0.035));
      expect(wide.frequency, narrow.frequency);
      expect(narrow.seed, 5);
    });

    test('places a lip in from each open end, so the test above can fail', () {
      final narrow = wispSides(376, 41, true, true, ratio: 3)!, wide = wispSides(1025, 44, true, true, ratio: 3)!;
      expect(narrow.lipA, 20);
      expect(narrow.lipB, 376 - 20);
      expect(wide.lipB, 1025 - 20);
      expect(narrow.axis, Axis.horizontal);
      expect(narrow.bend, isNot(wide.bend));
      expect(wispSidesWithin(376, 41), const Rect.fromLTWH(-24, -24, 424, 89));
    });

    test('smokes only an end that is open, and refuses a row too small to carry a band', () {
      expect(wispSides(375, 41, false, false, ratio: 3), isNull);
      expect(wispSides(20, 41, true, true, ratio: 3), isNull);
      final startOnly = wispSides(375, 41, true, false, ratio: 3)!;
      expect(startOnly.lipA, 20);
      expect(startOnly.lipB, isNull);
      // Only the open end fades.
      expect(startOnly.fade.at(0), 0);
      expect(startOnly.fade.at(12), 1);
      expect(startOnly.fade.at(375), 1);
    });

    test('is not worn on a desktop or where the mask is drawn, where a filter on a row that scrolls stalled the scroll', () {
      expect(wispSides(377, 41, true, true, ratio: 3), isNotNull, reason: 'a phone');
      WispSettings.instance.head = WispHead.blur;
      expect(wispSides(377, 41, true, true, ratio: 3), isNull, reason: 'a mouse');
      WispSettings.instance.head = null;
      WispSettings.instance.draw = WispDraw.mask;
      expect(wispSides(377, 41, true, true, ratio: 3), isNull, reason: 'the mask');
      WispSettings.instance.draw = null;
      expect(wispSides(377, 41, true, true, ratio: 3), isNotNull);
      expect(wispSides(377, 41, true, true, ratio: 3, still: true), isNull, reason: 'reduced motion');
    });
  });

  group('the band', () {
    test('is whole at its lip\'s own side, half at the lip, and gone four sigma past it', () {
      final top = wispTopSmoke(under: 60);
      expect(top.lipA, 60 + 12 + 7);
      expect(top.bandAt(0), closeTo(1, 1e-6));
      expect(top.bandAt(79), closeTo(0.5, 1e-6));
      expect(top.bandAt(79 + 60), lessThan(1e-4));
      final foot = wispFootSmoke(height: 800);
      expect(foot.lipB, 800 - 24 - 11);
      expect(foot.bandAt(800), greaterThan(0.85));
      expect(foot.bandAt(765 - 29 * 4), lessThan(1e-4));
    });

    test('rises as a blurred step does', () {
      expect(gaussianRamp(0), closeTo(0.5, 1e-7));
      expect(gaussianRamp(1), closeTo(0.841345, 1e-5));
      expect(gaussianRamp(-2), closeTo(0.0227501, 1e-5));
      expect(gaussianRamp(40), 1);
    });
  });
}
