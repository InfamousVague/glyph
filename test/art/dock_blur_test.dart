import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';

/// The halo round the dock, a gradient blur where the wisp's smoke was (Matt, 2026-10-24: "replace the smoke effect
/// with a gradient blur on all places that use the wisp smoke", and on the Mac too): where it is drawn, that it
/// follows the dock, that it is the same on every platform and with reduced motion, and that it is softest at the
/// dock and nothing at its own edge. Case for case with what test/art/dock_smoke_test.dart said of the smoke. On
/// Android the halo is the page's ground through the same pill, and no picture is taken (Matt, 2026-10-25: "if not
/// use simple gradients on android"); a test's platform is Android unless it says otherwise, so the blur is said of a
/// Mac.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  /// The strips' blur is said of a Mac: a test's platform is Android unless it says otherwise.
  final onMac = TargetPlatformVariant.only(TargetPlatform.macOS);

  DockBlurStrip? halo(WidgetTester tester) => tester.renderObject<RenderEdgeStrips>(find.byType(EdgeStrips).first).strips.whereType<DockBlurStrip>().firstOrNull;

  Future<void> dock(WidgetTester tester, {Size size = const Size(160, 44), bool still = false}) async {
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
              child: DockBlur(
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

  testWidgets('no halo is drawn round the dock: the dock sits on the page as it is (Matt, 2026-10-26)', (tester) async {
    expect(DockBlurHalo.drawn, isFalse);
    for (final platform in [TargetPlatform.android, TargetPlatform.macOS, TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = platform;
      await dock(tester);
      expect(find.byType(EdgeStrips), findsNothing, reason: platform.name);
      expect(tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((p) => p.foregroundPainter).whereType<DockFadeHalo>(), isEmpty, reason: platform.name);
    }
    debugDefaultTargetPlatformOverride = null;
  });

  group('the blur round the dock, where a look draws it', () {
    setUp(() => DockBlurHalo.drawn = true);
    tearDown(() => DockBlurHalo.drawn = false);

    test('is shown through a soft pill the halo\'s size, the dock\'s shape grown half the reach', () {
      final shape = dockBlurPill(160 + 2 * dockBlurReach, 44 + 2 * dockBlurReach);
      expect(shape.pill.outerRect, Rect.fromLTWH(dockBlurReach / 2, dockBlurReach / 2, 160 + dockBlurReach, 44 + dockBlurReach));
      expect(shape.pill.tlRadiusX, (44 + dockBlurReach) / 2, reason: 'a pill, round at its ends as the dock is');
      expect(shape.soft, greaterThan(1));
    });

    testWidgets('is given to the halo once the dock is measured', variant: onMac, (tester) async {
      await dock(tester);
      final strip = halo(tester)!;
      // The dock at the foot's middle, 20 up; the halo its box and the reach on every side.
      expect(strip.rect, const Rect.fromLTWH(120, 436, 160, 44).inflate(dockBlurReach));
      expect(strip.ready, isTrue, reason: 'nothing to wait for: no program, no tile');
      expect(tester.renderObject<RenderEdgeStrips>(find.byType(EdgeStrips).first).debugPainted, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS, TargetPlatform.windows]) {
      testWidgets('is the same blur on ${platform.name}, and with reduced motion', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        await dock(tester);
        final moving = halo(tester)!;
        await tester.pumpWidget(const SizedBox());
        await dock(tester, still: true);
        expect(halo(tester), moving, reason: 'it does not move, so reduced motion has nothing to take away');
        expect(tester.binding.hasScheduledFrame, isFalse, reason: 'and it asks for no frame of its own');
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('is the page\'s ground through the same pill on Android, and no picture of the page', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      DockFadeHalo? faded() => tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((p) => p.foregroundPainter).whereType<DockFadeHalo>().firstOrNull;
      await dock(tester);
      expect(find.byType(EdgeStrips), findsNothing);
      expect(faded()!.rect, const Rect.fromLTWH(120, 436, 160, 44).inflate(dockBlurReach), reason: 'round the dock as the blur is');
      final moving = faded();
      await tester.pumpWidget(const SizedBox());
      await dock(tester, still: true);
      expect(faded()!.rect, moving!.rect, reason: 'the same with reduced motion');
      expect(tester.binding.hasScheduledFrame, isFalse);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('follows the dock when it changes size', variant: onMac, (tester) async {
      await dock(tester);
      await dock(tester, size: const Size(240, 44));
      expect(halo(tester)!.rect, const Rect.fromLTWH(80, 436, 240, 44).inflate(dockBlurReach));
    });

    testWidgets('draws nothing where there is no dock to draw round', variant: onMac, (tester) async {
      await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: DockBlurHalo(dock: null, child: SizedBox(width: 100, height: 100))));
      expect(tester.renderObject<RenderEdgeStrips>(find.byType(EdgeStrips)).strips, isEmpty);
    });

    testWidgets('is soft and washed at the dock, and the view as it is at its own edge', (tester) async {
      final alphas = (await tester.runAsync(() async {
        const size = Size(256, 140);
        // Stripes of ink on a clear ground, the dock's box in the middle.
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (var x = 0.0; x < size.width + 80; x += 4) {
          canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height + 80), Paint()..color = const Color(0xFF000000));
        }
        final view = await recorder.endRecording().toImage(size.width.round() + 80, size.height.round() + 80);
        final box = Offset.zero & size;
        const strip = DockBlurStrip(rect: Rect.fromLTWH(0, 0, 256, 140), ground: Color(0xFFFFFFFF));
        final out = ui.PictureRecorder();
        strip.paint(Canvas(out), box, view, Rect.fromLTWH(-40, -40, size.width + 80, size.height + 80), 1);
        final image = await out.endRecording().toImage(size.width.round(), size.height.round());
        final data = (await image.toByteData())!;
        // The contrast across eight pixels of the row through the halo's middle, at its edge and at the dock.
        double contrastAt(int x0) {
          var low = 255, high = 0;
          for (var x = x0; x < x0 + 8; x++) {
            final a = data.getUint8((70 * size.width.round() + x) * 4 + 3);
            if (a < low) low = a;
            if (a > high) high = a;
          }
          return (high - low) / 255;
        }

        return (edge: contrastAt(0), dock: contrastAt(124));
      }))!;
      expect(alphas.dock, lessThan(0.1), reason: 'by the dock the stripes are blurred flat and washed');
      expect(alphas.edge, greaterThan(0.9), reason: 'at the halo\'s edge the view is as it was');
    });
  });
}
