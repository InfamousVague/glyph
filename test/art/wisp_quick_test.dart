import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/wisp_edge.dart';
import 'package:ghost_md/art/wisp_kit.dart';
import 'package:ghost_md/art/wisp_settings.dart';
import 'package:ghost_md/art/wisp_sides.dart';
import 'package:ghost_md/art/wisp_smoke.dart';
import 'package:ghost_md/art/wisp_strips.dart';

/// The arithmetic the quick smoke stands on (lib/art/wisp_smoke.dart): which part of a strip a smoke touches, the
/// blur's taps, and how small its pictures are. What it looks like is test/art/smoke_compare_test.dart's to say.
void main() {
  group('the part of a strip a smoke touches', () {
    test('a top band: from the strip\'s start to three deviations of the ramp past the lip', () {
      const under = 56.0;
      final fade = wispEdgeFade(height: 800, footFade: wispFootFadeSmoke);
      final smoke = wispTopSmoke(under: under, fade: fade);
      final strip = Rect.fromLTRB(0, 0, 390, under + wispEdgeDrop + wispEdgeReach);
      final parts = smoke.touched(strip);
      expect(parts, [Rect.fromLTRB(0, 0, 390, under + wispEdgeDrop + wispEdgeBand + 3 * wispEdgeSoft)]);
      // Past it the band is under a seven-hundredth: the bend throws nothing a tenth of a pixel, and the smoke
      // adds less than half a step of 255.
      expect(smoke.bandAt(parts.single.bottom), lessThan(0.0014));
      expect(smoke.bandAt(parts.single.bottom) * smoke.bend / 2, lessThan(0.02));
    });

    test('a top band with no header: down to where its fade is whole, if that is further', () {
      final fade = wispEdgeFade(height: 800, topFade: 96);
      final smoke = wispTopSmoke(under: 0, fade: fade);
      expect(smoke.touched(const Rect.fromLTRB(0, 0, 390, 122)), [const Rect.fromLTRB(0, 0, 390, 96)]);
    });

    test('a foot: from three deviations before the lip to the strip\'s end', () {
      const height = 800.0;
      final fade = wispEdgeFade(height: height, footFade: wispFootFadeSmoke);
      final smoke = wispFootSmoke(height: height, fade: fade);
      final within = wispFootWithin(height);
      final parts = smoke.touched(Rect.fromLTRB(0, within.top, 390, height));
      expect(parts, [Rect.fromLTRB(0, height - wispEdgeFootLift - wispEdgeFootBand - 3 * wispEdgeFootSoft, 390, height)]);
      expect(smoke.bandAt(parts.single.top), lessThan(0.0014));
      // The fade's start is inside it: the mask is drawn where the strip is.
      expect(parts.single.top, lessThan(fade.wholeUntil));
    });

    test('a strip whose edges are not on whole pixels: still one part, and no sliver at the end nothing reaches', () {
      // A page 763.5 tall under a header 56.4 tall, as a window's layout leaves them.
      const height = 763.5, under = 56.4;
      final fade = wispEdgeFade(height: height, footFade: wispFootFadeSmoke);
      final top = wispTopSmoke(under: under, fade: fade).touched(Rect.fromLTRB(0, 0, 390, under + wispEdgeDrop + wispEdgeReach));
      expect(top, [const Rect.fromLTRB(0, 0, 390, 121)]);
      final within = wispFootWithin(height);
      final foot = wispFootSmoke(height: height, fade: fade).touched(Rect.fromLTRB(0, within.top, 390, height));
      expect(foot, [const Rect.fromLTRB(0, 641, 390, height)]);
    });

    test('a row open at both ends: two parts, and the middle left to paint itself', () {
      final smoke = wispSides(390, 48, true, true, ratio: 2)!;
      final parts = smoke.touched(const Rect.fromLTWH(0, 0, 390, 48));
      expect(parts, hasLength(2));
      expect(parts[0].left, 0);
      expect(parts[1].right, 390);
      expect(parts[0].right, lessThan(parts[1].left));
      expect(parts[0].height, 48);
      for (final x in [parts[0].right, parts[1].left]) {
        expect(smoke.bandAt(x), lessThan(0.0014));
        expect(smoke.fade.at(x), 1);
      }
    });

    test('a row too short for its two ends to part, and a smoke with no band: all of the strip', () {
      const strip = Rect.fromLTWH(0, 0, 90, 48);
      expect(wispSides(90, 48, true, true, ratio: 2)!.touched(strip), [strip]);
      const flat = WispSmoke.flat(seed: 3, frequency: Offset(0.018, 0.06), bend: 23, blur: 1.6);
      expect(flat.touched(strip), [strip]);
    });
  });

  group('the blur\'s taps', () {
    test('weigh to one, and are as wide as the deviation asked for', () {
      for (final sigma in [0.6, 1.0, 1.25, 1.7, 2.23, 2.55, 3.0]) {
        final taps = wispBlurTaps(sigma);
        expect(taps.weights[0] + 2 * (taps.weights[1] + taps.weights[2] + taps.weights[3]), closeTo(1, 1e-9));
        // Each pair stands for two pixels: its place is between them, nearer the heavier.
        for (var pair = 0; pair < 3; pair++) {
          expect(taps.offsets[pair], inInclusiveRange(2 * pair + 1, 2 * pair + 2));
        }
        // The spread of the pixels' own weights, the pairs taken apart again.
        var spread = 0.0;
        for (var pair = 0; pair < 3; pair++) {
          final a = 2 * pair + 1, b = a + 1;
          final part = taps.offsets[pair] - a;
          spread += 2 * taps.weights[pair + 1] * ((1 - part) * a * a + part * b * b);
        }
        expect(spread, closeTo(sigma * sigma, 1e-6), reason: 'a blur of $sigma');
      }
    });

    test('no blur is the pixel itself', () {
      expect(wispBlurTaps(0).weights, [1, 0, 0, 0]);
      expect(wispBlurTaps(0.1).weights, [1, 0, 0, 0]);
    });
  });

  testWidgets('a boxed wisp keeps its picture while what holds it moves it by whole pixels, and is painted again when moved between them', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(780, 400);
    addTearDown(tester.view.reset);
    debugWispQuick = true;
    addTearDown(() => debugWispQuick = null);
    await tester.runAsync(() => WispKit.load(seeds: [3, 5]));
    final top = ValueNotifier<double>(10);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(390, 200), devicePixelRatio: 2),
          child: ValueListenableBuilder<double>(
            valueListenable: top,
            // The row itself is the same widget at every place: only what holds it is built again.
            child: const SizedBox(height: 48, child: WispSides(start: true, end: true, child: ColoredBox(color: Color(0xFF336699), child: SizedBox.expand()))),
            builder: (context, at, row) => Stack(children: [Positioned(left: 0, right: 0, top: at, child: row!)]),
          ),
        ),
      ),
    );
    await tester.pump();
    final strips = tester.renderObject<RenderWispStrips>(find.byType(WispStrips));
    expect(strips.debugPainted, hasLength(2), reason: 'the row\'s two ends, each a strip');
    final first = strips.debugPainted;

    // Two whole pixels down: the row is moved by its holder and not painted.
    top.value = 12;
    await tester.pump();
    await tester.pump();
    expect(identical(strips.debugPainted, first), isTrue, reason: 'moved by whole pixels, the row keeps its picture');

    // A quarter of a logical pixel more is half of one of the screen's: its strips were laid on other pixels.
    top.value = 12.25;
    await tester.pump();
    expect(identical(strips.debugPainted, first), isTrue, reason: 'the frame that moved it draws the picture it had');
    await tester.pump();
    expect(identical(strips.debugPainted, first), isFalse, reason: 'and the next paints it where it now stands');
  });

  test('a smoke\'s small pictures: a quarter of the screen each way from a blur of five of its pixels, a half from two and a half', () {
    // A page's edge (3.4) on a Mac, the Fold and an iPhone; a lane's foot (2.4) and the tabs (1.6) on a Mac and the Fold.
    expect([for (final ratio in [2.0, 2.625, 3.0]) wispSmallStep(wispEdgeBlur * ratio)], [4, 4, 4]);
    expect([wispSmallStep(2.4 * 2), wispSmallStep(2.4 * 2.625), wispSmallStep(1.6 * 2), wispSmallStep(1.6 * 2.625)], [2, 4, 2, 2]);
    expect(wispSmallStep(1.0), 1);
    // The blur in the small picture's own pixels is always one the taps can hold.
    for (final sigma in [2.5, 4.2, 5.0, 6.8, 8.9, 10.2, 11.8]) {
      final step = wispSmallStep(sigma);
      expect(wispSmallSigma(sigma, step), inInclusiveRange(1.0, 3.0), reason: 'a blur of $sigma of the screen\'s pixels');
    }
  });
}
