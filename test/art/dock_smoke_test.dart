import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';

/// The wisp round the home page's dock, and the mask's bands it shares its making with: the three pictures the
/// halo's mask is composed from, the halo given them once the dock is measured, and its smoke sliding with the
/// page's. Case for case with the web app's art/dockSmoke.test.tsx and art/wispMask.test.ts; how the pictures look
/// is test/art/wisp_parity_test.dart's.
void main() {
  tearDown(() {
    WispSettings.instance.reset();
    WispDrift.instance.debugReset();
  });

  group('the smoke round the dock', () {
    test('is a core and a ramp the halo\'s size, pills round the dock, the ramp the wider and the softer', () {
      final core = dockSmokeCore(155.4, 299.2), ramp = dockSmokeRamp(155.4, 299.2);
      RRect pill(double out) {
        final inset = dockSmokeReach - out;
        return RRect.fromRectAndRadius(Rect.fromLTWH(inset, inset, 155 - 2 * inset, 299 - 2 * inset), Radius.circular((155 - 2 * inset) / 2));
      }

      expect(core.pill, pill((dockSmokeReach * 0.12).roundToDouble()));
      expect(ramp.pill, pill(dockSmokeReach / 2));
      expect(ramp.soft, greaterThan(core.soft));
      expect(core.soft, 5);
      expect(ramp.soft, 10);
    });

    test('is a tile of the header\'s turbulence, stitched so it can slide without a seam', () {
      for (var v = 2.5; v < dockSmokeTileSide; v += 31) {
        expect(dockSmokeTileAlpha(-0.5, v), closeTo(dockSmokeTileAlpha(dockSmokeTileSide - 0.5, v), 1e-9));
        expect(dockSmokeTileAlpha(v, -0.5), closeTo(dockSmokeTileAlpha(v, dockSmokeTileSide - 0.5), 1e-9));
      }
      // Tendrils, and clear between them: a fair part of the tile is wholly one and a fair part wholly the other.
      var clear = 0, whole = 0, all = 0;
      for (var y = 0.5; y < 256; y += 4) {
        for (var x = 0.5; x < 256; x += 4) {
          final alpha = dockSmokeTileAlpha(x, y);
          all++;
          if (alpha < 0.1) clear++;
          if (alpha > 0.9) whole++;
        }
      }
      expect(clear / all, greaterThan(0.05));
      expect(whole / all, greaterThan(0.05));
    });

    test('is taken to alpha through a table, read between its values', () {
      expect(tableTransfer(dockSmokeCurve, 0), 0);
      expect(tableTransfer(dockSmokeCurve, 0.5), 0.5);
      expect(tableTransfer(dockSmokeCurve, 1), 1);
      expect(tableTransfer(dockSmokeCurve, 0.25), closeTo(0.025, 1e-12));
      expect(tableTransfer(wispMaskCurve, 0.5), closeTo(0.5, 1e-12));
      expect(tableTransfer(wispMaskCurve, 0.3), closeTo(0.06, 1e-12));
    });

    DockHaloStrip? halo(WidgetTester tester) => tester.renderObject<RenderWispStrips>(find.byType(WispStrips).first).strips.whereType<DockHaloStrip>().firstOrNull;

    Future<void> dock(WidgetTester tester, {Size size = const Size(160, 44), bool still = false}) async {
      await tester.runAsync(() async {
        await WispKit.load();
        await dockSmokeTile();
      });
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(devicePixelRatio: 2, disableAnimations: still),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                height: 500,
                child: DockSmoke(
                  padding: const EdgeInsets.only(bottom: 20),
                  behind: const ColoredBox(color: Color(0xFF202020), child: SizedBox.expand()),
                  dock: SizedBox.fromSize(size: size),
                ),
              ),
            ),
          ),
        ),
      );
      // Measured once the frame that laid the dock out is done, and drawn in the next.
      await tester.pump();
      await tester.pump();
    }

    testWidgets('is given to the halo once the dock is measured', (tester) async {
      await dock(tester);
      final strip = halo(tester)!;
      // The dock at the foot's middle, 20 up; the halo its box and the reach on every side.
      expect(strip.rect, const Rect.fromLTWH(120, 436, 160, 44).inflate(dockSmokeReach));
      expect(strip.tile, isNotNull);
      expect(strip.ready, isTrue);
      expect(tester.renderObject<RenderWispStrips>(find.byType(WispStrips).first).debugPainted, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('slides with the page\'s smoke, and lets go when the dock is gone', (tester) async {
      await dock(tester);
      expect(halo(tester)!.slide, Offset.zero);
      // The page's band stepping, as a scroll steps it.
      WispDrift.instance.moving(WispBand.page, true);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      final at = WispDrift.instance.at(WispBand.page);
      expect(at.slide, isNot(Offset.zero));
      expect(halo(tester)!.slide, at.slide);
      expect(halo(tester)!.frequency, at.frequency);
      WispDrift.instance.moving(WispBand.page, false, reset: false);
      await tester.pumpWidget(const SizedBox());
      // Nothing is told once the dock has gone.
      WispDrift.instance.moving(WispBand.page, true);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 40));
      WispDrift.instance.moving(WispBand.page, false);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bends what scrolls behind it on a phone, and only softens it on a desktop and with reduced motion', (tester) async {
      await dock(tester);
      expect(halo(tester)!.bends, isTrue);
      WispSettings.instance.head = WispHead.blur;
      await tester.pump();
      expect(halo(tester)!.bends, isFalse);
      WispSettings.instance.head = null;
      await tester.pumpWidget(const SizedBox());
      await dock(tester, still: true);
      expect(halo(tester)!.bends, isFalse);
    });

    testWidgets('follows the dock when it changes size', (tester) async {
      await dock(tester);
      await dock(tester, size: const Size(240, 44));
      expect(halo(tester)!.rect, const Rect.fromLTWH(80, 436, 240, 44).inflate(dockSmokeReach));
    });

    testWidgets('draws nothing where there is no dock to draw round', (tester) async {
      await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: DockHalo(dock: null, child: SizedBox(width: 100, height: 100))));
      expect(tester.renderObject<RenderWispStrips>(find.byType(WispStrips)).strips, isEmpty);
    });
  });

  group('the wisp edge drawn as a mask', () {
    test('makes each band once as a tiling picture: stitched turbulence over a soft strip, taken to a torn alpha', () {
      for (var y = 3.5; y < wispMaskHeight; y += 23) {
        expect(wispMaskAlpha(-0.5, y, soft: wispEdgeSoft), closeTo(wispMaskAlpha(wispMaskTile - 0.5, y, soft: wispEdgeSoft), 1e-9));
      }
      // Well under the lip the words show whole; above it they are torn: some gone, some left, and less left than gone.
      var shown = 0.0, count = 0;
      for (var x = 0.5; x < wispMaskTile; x += 8) {
        expect(wispMaskAlpha(x, wispMaskAbove + 70, soft: wispEdgeSoft), greaterThan(0.99));
        shown += wispMaskAlpha(x, 60, soft: wispEdgeSoft);
        count++;
      }
      expect(shown / count, inExclusiveRange(0.05, 0.5));
    });

    test('turns the foot over, with its own taller ramp', () {
      for (final x in [10.5, 200.5, 400.5]) {
        for (final y in [20.5, 100.5, 180.5]) {
          expect(wispMaskAlpha(x, y, soft: wispEdgeFootSoft, flip: true), wispMaskAlpha(x, wispMaskHeight - y, soft: wispEdgeFootSoft));
        }
      }
      expect(wispEdgeFootSoft, greaterThan(wispEdgeSoft));
    });

    test('is a picture of the band\'s own size at the pixels asked for', () {
      final pixels = wispMaskPixels(foot: false, ratio: 1);
      expect(pixels.length, wispMaskTile.toInt() * wispMaskHeight.toInt() * 4);
      // Ink, with the band in its alpha: nothing in the colour.
      expect(pixels[0] + pixels[1] + pixels[2], 0);
    });
  });
}
