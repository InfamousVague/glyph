import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';

import '../support/edges.dart';

/// The gradient blur at a board lane's foot and at the tab row's ends, where the wisp's smoke was (Matt, 2026-10-24:
/// "replace the smoke effect with a gradient blur on all places that use the wisp smoke", and on the Mac too); and
/// a letter coming out of a blur, where it came out of smoke. On Android the same ends are their masks alone (Matt,
/// 2026-10-25: "if not use simple gradients on android"); a test's platform is Android unless it says otherwise, so
/// the blur is said of a Mac.
void main() {
  tearDown(BlurEdgeSettings.instance.reset);

  /// The strips' blur is said of a Mac: a test's platform is Android unless it says otherwise.
  final onMac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<List<EdgeStrip>> boxed(WidgetTester tester, Widget box, {bool still = false}) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(devicePixelRatio: 2, disableAnimations: still),
        child: Directionality(textDirection: TextDirection.ltr, child: Align(alignment: Alignment.topLeft, child: box)),
      ),
    );
    await tester.pump();
    return edgeStripsUnder(tester, find.byType(Align).first);
  }

  group('BlurFoot', () {
    Widget lane({required bool more, double height = 300}) => SizedBox(width: 390, height: height, child: BlurFoot(more: more, plainFade: 17, child: const SizedBox.expand()));

    testWidgets('blurs a lane\'s foot while there is more below, and fades it over the lane\'s own 1.2em', variant: onMac, (tester) async {
      final strip = (await boxed(tester, lane(more: true))).single as EdgeBlurStrip;
      expect(strip.side, EdgeSide.bottom);
      expect(strip.rect, const Rect.fromLTRB(0, 300 - blurFootDepth, 390, 300));
      expect(strip.sigma, blurFootSigma);
      expect(strip.fade, const EdgeFade(wholeUntil: 283, clearFrom: 300));
    });

    testWidgets('runs half a short lane at most, and never shorter than its fade', variant: onMac, (tester) async {
      final strip = (await boxed(tester, lane(more: true, height: 40))).single as EdgeBlurStrip;
      expect(strip.rect, const Rect.fromLTRB(0, 20, 390, 40));
      final tiny = (await boxed(tester, lane(more: true, height: 24))).single as EdgeBlurStrip;
      expect(tiny.rect.height, 17);
    });

    testWidgets('draws the lane as it is with nothing below, and the fade alone with the blur switched off', variant: onMac, (tester) async {
      expect(await boxed(tester, lane(more: false)), isEmpty);
      BlurEdgeSettings.instance.wanted = false;
      final strips = await boxed(tester, lane(more: true));
      expect(strips.single, isA<EdgeFadeStrip>());
      expect(strips.single.rect, const Rect.fromLTRB(0, 283, 390, 300));
    });

    testWidgets('keeps its blur with reduced motion: nothing in it moves', variant: onMac, (tester) async {
      expect((await boxed(tester, lane(more: true), still: true)).single, isA<EdgeBlurStrip>());
    });
  });

  group('BlurSides', () {
    Widget row({required bool start, required bool end, double width = 390}) => SizedBox(width: width, height: 44, child: BlurSides(start: start, end: end, child: const SizedBox.expand()));

    testWidgets('blurs each open end toward its edge, over the row\'s own 12px fade', variant: onMac, (tester) async {
      final strips = (await boxed(tester, row(start: true, end: true))).cast<EdgeBlurStrip>();
      expect([for (final s in strips) s.side], [EdgeSide.left, EdgeSide.right]);
      expect(strips.first.rect, const Rect.fromLTWH(0, 0, blurSidesDepth, 44));
      expect(strips.last.rect, const Rect.fromLTWH(390 - blurSidesDepth, 0, blurSidesDepth, 44));
      expect(strips.first.fade!.wholeFrom, blurSidesFade);
      expect(strips.last.fade!.clearFrom - strips.last.fade!.wholeUntil, blurSidesFade);
    });

    testWidgets('blurs only an end that is open, and none of a row that fits', variant: onMac, (tester) async {
      expect((await boxed(tester, row(start: false, end: true))).cast<EdgeBlurStrip>().single.side, EdgeSide.right);
      expect(await boxed(tester, row(start: false, end: false)), isEmpty);
    });

    testWidgets('fades alone with the blur switched off, or on a row too narrow for two blurs', variant: onMac, (tester) async {
      BlurEdgeSettings.instance.wanted = false;
      expect((await boxed(tester, row(start: true, end: true))).every((s) => s is EdgeFadeStrip), isTrue);
      BlurEdgeSettings.instance.wanted = true;
      expect((await boxed(tester, row(start: true, end: true, width: 40))).every((s) => s is EdgeFadeStrip), isTrue);
    });
  });

  // A test's own platform, which needs no saying.
  group('on Android', () {
    testWidgets('a lane\'s foot and a row\'s ends are their masks alone: no picture of the box, one mask for each ramp', (tester) async {
      final lane = await boxed(tester, const SizedBox(width: 390, height: 300, child: BlurFoot(more: true, plainFade: 17, child: SizedBox.expand())));
      expect(lane.single.rect, const Rect.fromLTRB(0, 300 - blurFootDepth, 390, 300), reason: 'the same strip as the blur\'s');
      expect(find.byType(EdgeStrips), findsNothing);
      expect(tester.layers.whereType<ShaderMaskLayer>(), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      final row = await boxed(tester, const SizedBox(width: 390, height: 44, child: BlurSides(start: true, end: true, child: SizedBox.expand())));
      expect(row, hasLength(2));
      expect(find.byType(EdgeStrips), findsNothing);
      expect(tester.layers.whereType<ShaderMaskLayer>(), hasLength(2), reason: 'one mask for the row, a ramp at each end');
      await tester.pumpWidget(const SizedBox());
      await boxed(tester, const SizedBox(width: 390, height: 300, child: BlurFoot(more: false, plainFade: 17, child: SizedBox.expand())));
      expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty, reason: 'nothing below, no mask');
      expect(find.byType(EdgeBackdropBand), findsNothing, reason: 'an engine that cannot filter by a shader fades alone');
    });

    // Matt, 2026-10-25, on the Fold: "the cassette area needs to have a blur not a gradient". Where the engine
    // filters by a shader, a box's ends are blurred as backdrop bands over its fade. The test's engine cannot run the
    // shader: the look was seen on the ghostflutter2 emulator (build/feature-shots/shelf-blur/).
    group('blurred as backdrop bands', () {
      setUp(() => debugEdgeLook = EdgeLook.backdrop);
      tearDown(() => debugEdgeLook = null);

      List<(Rect, EdgeSide, double, double)> bands(WidgetTester tester) => [
            for (final band in tester.renderObjectList<RenderEdgeBackdropBand>(find.byType(EdgeBackdropBand)))
              (band.localToGlobal(Offset.zero) & band.size, band.side, band.sigma, band.clear),
          ];

      testWidgets('a row\'s open ends are a band each, as soft as each end shows, over the row\'s own fade', (tester) async {
        debugEdgePictures = 0;
        final strips = await boxed(
          tester,
          const SizedBox(width: 390, height: 44, child: BlurSides(start: true, end: true, startShown: 1, endShown: 0.5, child: SizedBox.expand())),
        );
        expect(bands(tester), [
          (const Rect.fromLTWH(0, 0, blurSidesDepth, 44), EdgeSide.left, blurSidesSigma, blurSidesFade),
          (const Rect.fromLTWH(390 - blurSidesDepth, 0, blurSidesDepth, 44), EdgeSide.right, blurSidesSigma * 0.5, blurSidesFade * 0.5),
        ], reason: 'the right end half shown: half as soft, its blur clearing over half the fade');
        expect(strips.map((s) => s.rect), [for (final (rect, _, _, _) in bands(tester)) rect], reason: 'a band where each strip lies');
        expect(tester.layers.whereType<ShaderMaskLayer>(), hasLength(2), reason: 'the row still fades out under its bands');
        expect(find.byType(EdgeStrips), findsNothing);
        expect(debugEdgePictures, 0, reason: 'no picture of the box is taken');
        final band = tester.renderObject<RenderEdgeBackdropBand>(find.byType(EdgeBackdropBand).last);
        expect(band.debugClearShare, closeTo(blurSidesFade * 0.5 / blurSidesDepth, 1e-9));
        expect(band.debugClip, Offset.zero & band.size, reason: 'nothing stands over a box\'s edge to bleed under');
      });

      testWidgets('reads the box in a group of its own, not one round it', (tester) async {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 2),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: BackdropGroup(
                key: const ValueKey('page-group'),
                child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 390, height: 44, child: BlurSides(start: true, end: true, child: Container(key: const ValueKey('row'))))),
              ),
            ),
          ),
        );
        final groups = find.ancestor(of: find.byType(EdgeBackdropBand).first, matching: find.byType(BackdropGroup));
        expect(groups, findsNWidgets(2));
        expect(find.descendant(of: find.byType(BlurSides), matching: groups.first), findsOneWidget, reason: 'the nearest group is the box\'s');
        expect(find.ancestor(of: find.byKey(const ValueKey('row')), matching: groups.first), findsOneWidget, reason: 'and the row is drawn in it, under the bands');
        final stack = tester.widget<Stack>(find.descendant(of: groups.first, matching: find.byType(Stack)).first);
        expect(stack.children.last, isA<Positioned>(), reason: 'the bands over the row, so they blur it');
      });

      testWidgets('a lane\'s foot is one band at its foot, clearing over the lane\'s own fade', (tester) async {
        await boxed(tester, const SizedBox(width: 390, height: 300, child: BlurFoot(more: true, plainFade: 17, child: SizedBox.expand())));
        expect(bands(tester), [(const Rect.fromLTRB(0, 300 - blurFootDepth, 390, 300), EdgeSide.bottom, blurFootSigma, 17.0)]);
        await tester.pumpWidget(const SizedBox());
        await boxed(tester, const SizedBox(width: 390, height: 300, child: BlurFoot(more: false, plainFade: 17, child: SizedBox.expand())));
        expect(bands(tester), isEmpty, reason: 'nothing below, no band');
      });

      testWidgets('a box as tall as what it holds has its bands once it is laid out', (tester) async {
        await boxed(
          tester,
          const SizedBox(
            width: 390,
            child: SingleChildScrollView(child: Column(children: [BlurSides(start: true, end: true, child: SizedBox(width: 390, height: 120))])),
          ),
        );
        expect(bands(tester).map((b) => (b.$1, b.$2)), [
          (const Rect.fromLTWH(0, 0, blurSidesDepth, 120), EdgeSide.left),
          (const Rect.fromLTWH(390 - blurSidesDepth, 0, blurSidesDepth, 120), EdgeSide.right),
        ]);
        expect(tester.getSize(find.byType(BlurSides)), const Size(390, 120), reason: 'the box is as tall as what it holds, bands and all');
      });

      testWidgets('fades alone with the blur switched off, or on a row too narrow for two blurs', (tester) async {
        BlurEdgeSettings.instance.wanted = false;
        expect((await boxed(tester, const SizedBox(width: 390, height: 44, child: BlurSides(start: true, end: true, child: SizedBox.expand())))).every((s) => s is EdgeFadeStrip), isTrue);
        expect(bands(tester), isEmpty);
        expect(tester.layers.whereType<ShaderMaskLayer>(), hasLength(2));
        BlurEdgeSettings.instance.wanted = true;
        await tester.pump();
        expect(bands(tester), hasLength(2), reason: 'and the bands back with the switch');
        await tester.pumpWidget(const SizedBox());
        await boxed(tester, const SizedBox(width: 40, height: 44, child: BlurSides(start: true, end: true, child: SizedBox.expand())));
        expect(bands(tester), isEmpty);
      });

      testWidgets('a band with no program yet draws nothing and asks for no frame', (tester) async {
        await boxed(tester, const SizedBox(width: 390, height: 44, child: BlurSides(start: true, end: true, child: SizedBox.expand())));
        expect(tester.layers.whereType<BackdropFilterLayer>(), isEmpty, reason: 'the test\'s engine has no shader to filter by');
        expect(tester.binding.hasScheduledFrame, isFalse);
      });
    });

    testWidgets('a Mac\'s box keeps its strips: no band and no group of its own', variant: onMac, (tester) async {
      final strips = await boxed(tester, const SizedBox(width: 390, height: 44, child: BlurSides(start: true, end: true, child: SizedBox.expand())));
      expect(strips.whereType<EdgeBlurStrip>(), hasLength(2));
      expect(find.byType(EdgeStrips), findsOneWidget);
      expect(find.byType(EdgeBackdropBand), findsNothing);
      expect(find.byType(BackdropGroup), findsNothing);
    });
  });

  group('a letter out of a blur', () {
    test('is as soft as its smoke\'s bend and blur together, and never past the most', () {
      expect(letterBlur(0, 0), 0);
      expect(letterBlur(0, 3), 3);
      expect(letterBlur(wispLetterBend, wispLetterSoft), closeTo(6.45, 0.05), reason: 'a letter just arriving');
      expect(letterBlur(200, 20), letterBlurMost);
    });

    testWidgets('is drawn soft and faint, and as itself once it has set, with no layer', (tester) async {
      final result = (await tester.runAsync(() async {
        Future<({int high, int drawn})> draw(double sigma, double opacity) async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..translate(20, 20);
          paintBlurLetter(canvas, box: const Size(20, 20), sigma: sigma, opacity: opacity, draw: (c) => c.drawRect(const Rect.fromLTWH(0, 0, 20, 20), Paint()..color = const Color(0xFF000000)));
          final image = await recorder.endRecording().toImage(60, 60);
          final data = (await image.toByteData())!;
          var high = 0, drawn = 0;
          for (var i = 3; i < data.lengthInBytes; i += 4) {
            final a = data.getUint8(i);
            if (a > high) high = a;
            if (a > 8) drawn += 1;
          }
          return (high: high, drawn: drawn);
        }

        return (sharp: await draw(0, 1), soft: await draw(6, 0.5), gone: await draw(4, 0));
      }))!;
      expect(result.sharp, (high: 255, drawn: 400), reason: 'a set letter is the letter, to the pixel');
      expect(result.soft.high, lessThan(128), reason: 'half there, and its ink spread');
      expect(result.soft.drawn, greaterThan(400), reason: 'the blur reaches past the letter\'s box');
      expect(result.gone, (high: 0, drawn: 0));
    });
  });
}
