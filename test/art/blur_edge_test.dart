import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';

import '../support/edges.dart';

/// The gradient blur on a view, where the wisp's smoke was (Matt, 2026-10-24: "replace the smoke effect with a
/// gradient blur on all places that use the wisp smoke", then "remove the smoke on mac too so all versions get
/// blur"): when a view wears it, where its bands are, what the switch and reduced motion do, that every platform
/// draws the same, and that the blur is a blur, the softest at the edge. Case for case with what
/// test/art/wisp_edge_test.dart said of the smoke, where the smoke's numbers allow.
///
/// Android draws the same strips in the same places as a backdrop filter, or as the page's ground alone where the
/// engine cannot filter by a shader, and takes no picture of the view (Matt, 2026-10-25: "the blur works now but it's
/// super laggy, research if there is a library or something we can use for cleaner blurs, if not use simple
/// gradients on android"). A test's platform is Android unless it says otherwise, so what is said here of the
/// strips' blur is said on a Mac.
void main() {
  tearDown(() {
    BlurEdgeSettings.instance.reset();
    debugDefaultTargetPlatformOverride = null;
    debugEdgeLook = null;
  });

  /// The strips' blur is said of a Mac: a test's platform is Android unless it says otherwise.
  final onMac = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// A screen with room for the views: a test's own is 800 by 600.
  void room(WidgetTester tester) {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(2000, 2000);
    addTearDown(tester.view.reset);
  }

  /// A view 400 by 800 that can scroll [more] px past its height, wearing the blur under a header [header] px tall.
  Future<ScrollController> view(WidgetTester tester, {double more = 600, double header = 0, bool foot = false, double footOver = 0, bool still = false, double safeTop = 0, ValueChanged<bool>? onChanged}) async {
    room(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), devicePixelRatio: 2, disableAnimations: still),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: const ValueKey('page'),
              width: 400,
              height: 800,
              child: BlurEdge(
                under: header,
                foot: foot,
                footOver: footOver,
                safeTop: safeTop,
                onChanged: onChanged,
                // A desktop's scrollbar wants the app's tokens; it is lib/shell/desktop's to test.
                scrollbar: false,
                child: SingleChildScrollView(
                  controller: controller,
                  child: SizedBox(height: 800 + more, child: const Align(alignment: Alignment.topLeft, child: Text('Hold. Talk. Done.'))),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  List<EdgeStrip> strips(WidgetTester tester) => edgeStripsUnder(tester, find.byKey(const ValueKey('page')));
  EdgeBlurStrip? top(WidgetTester tester) => strips(tester).whereType<EdgeBlurStrip>().where((s) => s.side == EdgeSide.top).firstOrNull;
  EdgeBlurStrip? foot(WidgetTester tester) => strips(tester).whereType<EdgeBlurStrip>().where((s) => s.side == EdgeSide.bottom).firstOrNull;

  group('BlurEdge', () {
    testWidgets('blurs under the header once the view is scrolled off its top, turning in, and lets go at the top', variant: onMac, (tester) async {
      final said = <bool>[];
      final scroll = await view(tester, header: 60, onChanged: said.add);
      expect(strips(tester), isEmpty, reason: 'at its top a view wears nothing');
      scroll.jumpTo(100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final turning = top(tester)!;
      expect(turning.rect, const Rect.fromLTWH(0, 60, 400, blurEdgeDepth), reason: 'hung from the header\'s foot');
      expect(turning.opacity, inExclusiveRange(0, 1), reason: 'it turns in over a sixth of a second');
      await tester.pump(const Duration(milliseconds: 200));
      expect(top(tester)!.opacity, 1);
      expect(top(tester)!.sigma, blurEdgeSigma);
      expect(said, [true]);
      scroll.jumpTo(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(top(tester), isNull);
      expect(said, [true, false]);
    });

    testWidgets('never blurs a view that cannot scroll, whatever its place says', variant: onMac, (tester) async {
      await view(tester, header: 60, more: 2, foot: true);
      expect(strips(tester), isEmpty);
    });

    testWidgets('with no header, fades over the status bar\'s height and 8px more, and is soft for a band past it', variant: onMac, (tester) async {
      final scroll = await view(tester, safeTop: 36);
      scroll.jumpTo(100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final strip = top(tester)!;
      expect(strip.rect, const Rect.fromLTRB(0, 0, 400, 36 + 8 + blurEdgeDepth));
      expect(strip.fade, const EdgeFade(clearUntil: 0, wholeFrom: 44));
    });

    testWidgets('blurs the foot while there is more below, and not at the end', variant: onMac, (tester) async {
      final scroll = await view(tester, foot: true);
      expect(foot(tester)!.rect, const Rect.fromLTRB(0, 800 - blurEdgeFootDepth, 400, 800));
      expect(foot(tester)!.fade, const EdgeFade(wholeUntil: 800 - blurEdgeFootFade, clearFrom: 800));
      scroll.jumpTo(600);
      await tester.pump();
      expect(foot(tester), isNull);
    });

    testWidgets('blurs the foot at a dock\'s top edge, and is gone below it', variant: onMac, (tester) async {
      await view(tester, foot: true, footOver: 100);
      expect(foot(tester)!.rect, const Rect.fromLTRB(0, 700 - blurEdgeFootDepth, 400, 700));
      final below = strips(tester).whereType<EdgeFadeStrip>().single;
      expect(below.rect, const Rect.fromLTRB(0, 700, 400, 800));
      expect(below.fade.at(701), 0, reason: 'beside and under the dock the view is clear');
    });

    testWidgets('draws nothing at all with the blur switched off in Settings, and comes back with it', variant: onMac, (tester) async {
      final scroll = await view(tester, header: 60, foot: true);
      scroll.jumpTo(100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(strips(tester), hasLength(2));
      BlurEdgeSettings.instance.wanted = false;
      await tester.pump();
      await tester.pump();
      expect(strips(tester), isEmpty);
      BlurEdgeSettings.instance.wanted = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(strips(tester), hasLength(2));
    });

    testWidgets('with reduced motion keeps the blur, which does not move, and loses only its turn', variant: onMac, (tester) async {
      final scroll = await view(tester, header: 60, foot: true, still: true);
      scroll.jumpTo(100);
      await tester.pump();
      await tester.pump();
      expect(top(tester)!.opacity, 1, reason: 'there at once, with no turn in');
      expect(foot(tester), isNotNull);
      expect(footBlurs(true), isTrue, reason: 'the note keeps its caret clear of it with reduced motion too');
      expect(footBlurs(false), isFalse);
      scroll.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(top(tester), isNull, reason: 'and gone at once at the top');
    });

    for (final platform in TargetPlatform.values.where((p) => p != TargetPlatform.android)) {
      testWidgets('draws the same blur on ${platform.name}, and asks for no frame of its own while it rests', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final scroll = await view(tester, header: 60, foot: true);
        scroll.jumpTo(100);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(edgeLook, EdgeLook.blur);
        expect(takesEdgePictures(tester, find.byKey(const ValueKey('page'))), isTrue);
        expect(strips(tester).map((s) => s.runtimeType), [EdgeBlurStrip, EdgeBlurStrip]);
        expect(top(tester)!.rect, const Rect.fromLTWH(0, 60, 400, blurEdgeDepth));
        expect(foot(tester)!.rect, const Rect.fromLTRB(0, 800 - blurEdgeFootDepth, 400, 800));
        expect(tester.binding.hasScheduledFrame, isFalse, reason: 'the smoke drifted on its own clock while a page scrolled; a blur has none');
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

  // A test's own platform, which needs no saying.
  group('on Android', () {
    /// Scrolls the view a frame at a time, as a finger does.
    Future<void> scrolled(WidgetTester tester, ScrollController scroll) async {
      for (var y = 100.0; y <= 300; y += 20) {
        scroll.jumpTo(y);
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    Iterable<RenderEdgeBackdropBand> bands(WidgetTester tester) => tester.renderObjectList<RenderEdgeBackdropBand>(find.byType(EdgeBackdropBand));

    test('blurs as a backdrop filter where the engine filters by a shader, and fades where it cannot', () {
      expect(edgeLook, ui.ImageFilter.isShaderFilterSupported ? EdgeLook.backdrop : EdgeLook.fade);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(edgeLook, EdgeLook.blur, reason: 'the iPhone, the Mac and every desktop keep the strips');
    });

    // Matt, 2026-10-25, on the Fold with 2.3.27: "the blur works now but it's super laggy". The strips took three or
    // four pictures of the view at every frame a page scrolled (build/feature-shots/blur-perf/).
    testWidgets('blurs the same strips as backdrop bands under the same wash, and takes no picture of the view however far it scrolls', (tester) async {
      debugEdgeLook = EdgeLook.backdrop;
      final scroll = await view(tester, header: 60, foot: true);
      debugEdgePictures = 0;
      await scrolled(tester, scroll);
      expect(strips(tester).map((s) => s.runtimeType), [EdgeBlurStrip, EdgeBlurStrip], reason: 'the strips are the blur\'s own');
      expect([for (final band in bands(tester)) (band.localToGlobal(Offset.zero) & band.size, band.side, band.sigma)], [
        (const Rect.fromLTWH(0, 60, 400, blurEdgeDepth), EdgeSide.top, blurEdgeSigma),
        (const Rect.fromLTRB(0, 800 - blurEdgeFootDepth, 400, 800), EdgeSide.bottom, blurEdgeSigma),
      ]);
      final shade = tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((p) => p.painter).whereType<EdgeShade>().single;
      expect(shade.wash, blurEdgeWash, reason: 'the blur\'s own wash over it, and the foot cleared to the page\'s ground');
      expect(takesEdgePictures(tester, find.byKey(const ValueKey('page'))), isFalse);
      expect(debugEdgePictures, 0);
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'a band with no program yet draws nothing, and asks for no frame');

      // The count can fail: the same scroll on a Mac takes pictures at every frame.
      debugEdgeLook = null;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.pumpWidget(const SizedBox());
      await scrolled(tester, await view(tester, header: 60, foot: true));
      expect(debugEdgePictures, greaterThan(10));
      debugDefaultTargetPlatformOverride = null;
    });

    // Matt, 2026-10-25: "Scrolling on the meetings section of settings shows the hole page behind it". In the app's
    // one group the bands of a view laid over another page read the backdrop once, with that page's first band, and
    // showed it under their own header.
    testWidgets('reads its own backdrop: the bands are a group of the view\'s own, over the page\'s ground, not the app\'s', (tester) async {
      debugEdgeLook = EdgeLook.backdrop;
      final scroll = await view(tester, header: 60, foot: true);
      await scrolled(tester, scroll);
      final groups = {for (final band in bands(tester)) tester.widget<BackdropGroup>(find.ancestor(of: find.byWidgetPredicate((w) => w is EdgeBackdropBand && w.side == band.side), matching: find.byType(BackdropGroup)).first).backdropKey};
      expect(groups, hasLength(1), reason: 'the view\'s two bands share one read');
      final view0 = tester.element(find.byKey(const ValueKey('page')));
      final outer = find.ancestor(of: find.byType(Stack).first, matching: find.byType(BackdropGroup));
      expect(outer, findsOneWidget, reason: 'the group is the view\'s, under any group above it');
      expect(view0.mounted, isTrue);
      expect(find.byKey(const ValueKey('edge-ground')), findsOneWidget, reason: 'the page\'s ground under the view, so nothing behind it shows through the band');
    });

    testWidgets('turns its bands in with the blur, at once with reduced motion, and has none with the switch off', (tester) async {
      debugEdgeLook = EdgeLook.backdrop;
      final scroll = await view(tester, header: 60);
      scroll.jumpTo(100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(bands(tester).single.sigma, inExclusiveRange(0, blurEdgeSigma), reason: 'softer while it turns in');
      await tester.pumpWidget(const SizedBox());
      final still = await view(tester, header: 60, still: true);
      still.jumpTo(100);
      await tester.pump();
      await tester.pump();
      expect(bands(tester).single.sigma, blurEdgeSigma, reason: 'there at once, with no turn in');
      BlurEdgeSettings.instance.wanted = false;
      await tester.pump();
      await tester.pump();
      expect(bands(tester), isEmpty);
      expect(strips(tester), isEmpty);
    });

    testWidgets('where the engine cannot filter by a shader, fades the same strips with the page\'s ground, and takes no picture', (tester) async {
      debugEdgeLook = EdgeLook.fade;
      final scroll = await view(tester, header: 60, foot: true);
      debugEdgePictures = 0;
      await scrolled(tester, scroll);
      expect(strips(tester).map((s) => s.runtimeType), [EdgeBlurStrip, EdgeBlurStrip], reason: 'where the blur would be, the fade is');
      expect(top(tester)!.rect, const Rect.fromLTWH(0, 60, 400, blurEdgeDepth));
      expect(foot(tester)!.rect, const Rect.fromLTRB(0, 800 - blurEdgeFootDepth, 400, 800));
      expect(bands(tester), isEmpty);
      expect(takesEdgePictures(tester, find.byKey(const ValueKey('page'))), isFalse);
      expect(debugEdgePictures, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      BlurEdgeSettings.instance.wanted = false;
      await tester.pump();
      await tester.pump();
      expect(strips(tester), isEmpty);
      expect(find.descendant(of: find.byKey(const ValueKey('page')), matching: find.byWidgetPredicate((w) => w is CustomPaint && w.foregroundPainter is EdgeShade)), findsNothing);
    });

    testWidgets('lays the ground over the edge: none at a strip\'s inner end, most at its edge, whole where the view is cleared', (tester) async {
      const ground = Color(0xFFFFFFFF);
      final alphas = (await tester.runAsync(() async {
        // A page 400 by 800 under a header 60 tall, with a dock 100 tall over its foot: the strips BlurEdge gives it.
        const strips = <EdgeStrip>[
          EdgeBlurStrip(rect: Rect.fromLTWH(0, 60, 400, blurEdgeDepth), side: EdgeSide.top, sigma: blurEdgeSigma),
          EdgeBlurStrip(rect: Rect.fromLTRB(0, 700 - blurEdgeFootDepth, 400, 700), side: EdgeSide.bottom, sigma: blurEdgeSigma, fade: EdgeFade(wholeUntil: 700 - blurEdgeFootFade, clearFrom: 700)),
          EdgeFadeStrip(rect: Rect.fromLTRB(0, 700, 400, 800), fade: EdgeFade(wholeUntil: 700, clearFrom: 700)),
        ];
        final recorder = ui.PictureRecorder();
        const EdgeShade(strips: strips, ground: ground).paint(Canvas(recorder), const Size(400, 800));
        final image = await recorder.endRecording().toImage(400, 800);
        final data = (await image.toByteData())!;
        return [for (var y = 0; y < 800; y++) data.getUint8((y * 400 + 200) * 4 + 3) / 255];
      }))!;
      expect(alphas[30], 0, reason: 'nothing over the header, which is the header\'s');
      expect(alphas[60], closeTo(edgeFadeWash, 0.03), reason: 'most of the ground at the header\'s foot');
      expect(alphas[60 + blurEdgeDepth.round() - 1], lessThan(0.05), reason: 'and none at the strip\'s inner end');
      for (var y = 61; y < 100; y++) {
        expect(alphas[y], lessThanOrEqualTo(alphas[y - 1] + 0.01), reason: 'row $y: less of the ground going in from the edge');
      }
      expect(alphas[400], 0, reason: 'the page between its edges is as it is');
      expect(alphas[700 - blurEdgeFootDepth.round() + 1], lessThan(0.05));
      expect(alphas[699], greaterThan(0.95), reason: 'gone into the ground at the dock\'s top edge');
      expect(alphas[750], 1, reason: 'beside and under the dock the view is gone');
    });

    test('the backdrop\'s shader is the one pubspec.yaml ships, with the uniforms the band sets', () {
      final shader = File('shaders/edge_blur.frag').readAsStringSync();
      final uniforms = RegExp(r'^uniform (\w+) (\w+);', multiLine: true).allMatches(shader).map((m) => '${m.group(1)} ${m.group(2)}').toList();
      // The engine's size first, then the band (floats 2 to 5), the softness (6), the side (7), the axis (8) and the
      // gradient mask's feather (9).
      expect(uniforms, ['vec2 uSize', 'vec4 uBand', 'float uSigma', 'float uSide', 'float uAxis', 'float uFeather', 'sampler2D uTexture']);
      // The mask is the down pass's alpha, a smoothstep over the feather (edgeBlurMask is the same curve), and the
      // across pass is whole: the engine lays the layer over the sharp view it read. The test's engine cannot run the
      // shader; how it looks was seen on the ghostflutter2 emulator (build/feature-shots/blur-feather/).
      expect(shader, contains('float shown = down ? smoothstep(0.0, max(uFeather, 1e-3), t) : 1.0;'));
      expect(shader, contains('fragColor = sum / weights * shown;'));
      expect(edgeBlurFeather, 1 / edgeBlurLevels, reason: 'whole where the strips\' sharp view is gone');
      expect(edgeBlurMask(0), 0);
      expect(edgeBlurMask(edgeBlurFeather / 2), closeTo(0.5, 1e-9));
      expect(edgeBlurMask(edgeBlurFeather), 1);
      expect(edgeBlurMask(0.9), 1);
      expect(EdgeSide.values, [EdgeSide.top, EdgeSide.bottom, EdgeSide.left, EdgeSide.right], reason: 'the shader reads a side by its index');
      expect(shader.contains('IMPELLER_TARGET_OPENGLES'), isFalse, reason: 'since Flutter 3.47 GLES keeps a texture top down, as Vulkan and Metal do');
    });
  });

  // Matt, 2026-10-25: "the top blur on the scrolling list on the home page has 1px visible above the blur". A page
  // is told its header's height as a whole pixel where the header ends between two: on the ghostflutter2 emulator at
  // 2.625 the home page's header ended a row short of its blur, and that row was the list, sharp.
  group('under a header', () {
    /// The device rows of a page of upright bars between the foot of a header [headerFoot] tall and its blur hung
    /// at a whole [under], drawn at [ratio] through a strip that reaches [bleed] past its edge: each row's contrast,
    /// how far apart its lightest and darkest pixels are (0 to 1). The bars are 2 px every 4, which the blur at its
    /// edge (sigma 8) makes one grey: a row that is the blur's is flat, one that is the page's is striped.
    Future<List<double>> between(WidgetTester tester, {required double ratio, required double bleed, double headerFoot = 59.4, double under = 60}) async {
      const width = 200.0, height = 200.0;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: const Size(width, height), devicePixelRatio: ratio),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: boundary,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    children: [
                      EdgeStrips(
                        strips: [EdgeBlurStrip(rect: Rect.fromLTWH(0, under, width, blurEdgeDepth), side: EdgeSide.top, sigma: blurEdgeSigma, bleed: bleed)],
                        child: const CustomPaint(size: Size(width, height), painter: _Bars()),
                      ),
                      // The header, painted over the page as the app's is, its foot between two pixels.
                      Positioned(left: 0, top: 0, right: 0, height: headerFoot, child: const ColoredBox(color: Color(0xFF808080))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: ratio);
        final data = (await image.toByteData())!;
        final across = image.width;
        final rows = <double>[];
        for (var y = (headerFoot * ratio).floor(); y < (under * ratio).floor(); y++) {
          var low = 255, high = 0;
          for (var x = across ~/ 4; x < across * 3 ~/ 4; x++) {
            final a = data.getUint8((y * across + x) * 4);
            if (a < low) low = a;
            if (a > high) high = a;
          }
          rows.add((high - low) / 255);
        }
        image.dispose();
        return rows;
      }))!;
    }

    for (final ratio in [1.0, 2.625]) {
      testWidgets('leaves no row of the page sharp between the header\'s foot and the blur (at $ratio x)', variant: onMac, (tester) async {
        final soft = await between(tester, ratio: ratio, bleed: edgeBlurBleed);
        expect(soft, isNotEmpty, reason: 'a row lies between the header\'s foot and the whole pixel the page was told');
        for (final contrast in soft) {
          expect(contrast, lessThan(0.05), reason: 'a row the header leaves is the blur\'s: $soft');
        }
        // The measure can fail: with no bleed that row is the page itself, striped.
        final sharp = await between(tester, ratio: ratio, bleed: 0);
        expect(sharp.reduce((a, b) => a > b ? a : b), greaterThan(0.3), reason: '$sharp');
      });
    }

    testWidgets('a page under a header has its blur reach a pixel up under it; a foot and a page with no header do not', variant: onMac, (tester) async {
      final scroll = await view(tester, header: 60, foot: true);
      scroll.jumpTo(100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(top(tester)!.bleed, edgeBlurBleed);
      expect(top(tester)!.drawn, const Rect.fromLTRB(0, 60 - edgeBlurBleed, 400, 60 + blurEdgeDepth));
      expect(top(tester)!.rect, const Rect.fromLTWH(0, 60, 400, blurEdgeDepth), reason: 'its gradient and wash are where they were');
      expect(foot(tester)!.bleed, 0);
      await tester.pumpWidget(const SizedBox());
      final bare = await view(tester, safeTop: 36);
      bare.jumpTo(100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(top(tester)!.bleed, 0, reason: 'nothing stands over a view with no header to hide it');
    });

    testWidgets('on Android the band\'s filter reaches as far under the header, at 1x and the Fold\'s 2.625', (tester) async {
      debugEdgeLook = EdgeLook.backdrop;
      final scroll = await view(tester, header: 60, foot: true);
      for (var y = 100.0; y <= 300; y += 50) {
        scroll.jumpTo(y);
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pump(const Duration(milliseconds: 400));
      final bands = tester.renderObjectList<RenderEdgeBackdropBand>(find.byType(EdgeBackdropBand)).toList();
      final under = bands.firstWhere((b) => b.side == EdgeSide.top), foot = bands.firstWhere((b) => b.side == EdgeSide.bottom);
      expect(under.debugClip, const Rect.fromLTRB(0, -edgeBlurBleed, 400, blurEdgeDepth));
      expect(foot.debugClip, Offset.zero & foot.size, reason: 'a foot\'s edge is the page\'s ground');
      // A header that ends anywhere in the half pixel its height was rounded by is met: the filter's first device
      // row is at or above the header's last.
      final top = under.localToGlobal(Offset.zero).dy + under.debugClip.top;
      for (final ratio in [1.0, 2.625]) {
        for (final headerFoot in [59.5, 59.75, 60.0]) {
          expect((top * ratio).floor(), lessThanOrEqualTo((headerFoot * ratio).floor()), reason: 'a header ending at $headerFoot at $ratio x');
        }
      }
    });
  });

  // Where the blur is drawn (every platform but Android), it is a blur.
  group('a gradient blur', () {
    /// Rows of black and white across a strip [height] tall, drawn through an [EdgeBlurStrip] whose edge is its top.
    Future<List<double>> contrastDown(WidgetTester tester, double height) async {
      return (await tester.runAsync(() async {
        // Wide, and read only in its middle: at its two ends the blur gathers what its clamped edge repeats.
        const width = 200;
        final rows = height.round();
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (var x = 0; x < width; x += 4) {
          canvas.drawRect(Rect.fromLTWH(x.toDouble(), -40, 2, rows + 80.0), Paint()..color = const Color(0xFF000000));
        }
        final view = await recorder.endRecording().toImage(width, rows + 80);
        final strip = EdgeBlurStrip(rect: Rect.fromLTWH(0, 0, width.toDouble(), height), side: EdgeSide.top, sigma: blurEdgeSigma);
        final out = ui.PictureRecorder();
        strip.paint(Canvas(out), Rect.fromLTWH(0, 0, width.toDouble(), height), view, Rect.fromLTWH(0, -40, width.toDouble(), rows + 80.0), 1);
        final image = await out.endRecording().toImage(width, rows);
        final data = (await image.toByteData())!;
        // How far apart the lightest and darkest pixels of each row are: 1 sharp, near 0 blurred flat.
        return [
          for (var y = 0; y < rows; y++)
            () {
              var low = 255, high = 0;
              for (var x = 60; x < 140; x++) {
                final a = data.getUint8((y * width + x) * 4 + 3);
                if (a < low) low = a;
                if (a > high) high = a;
              }
              return (high - low) / 255;
            }(),
        ];
      }))!;
    }

    /// Bars 8 px wide with 8 px between, drawn at [ratio] through [strip] (a [height] tall strip whose edge is its
    /// top), and read back row by row: how far apart the row's lightest and darkest pixels are (its contrast, 0 to
    /// 1), and how steep its steepest step across one logical pixel is, as a share of that contrast (1 a hard edge,
    /// near 0 a soft one). A strip that only fades the bars keeps every edge hard, however faint; a blur softens them.
    Future<List<({double contrast, double steep})>> edgesDown(WidgetTester tester, EdgeStrip strip, double height, {double ratio = 1}) async {
      return (await tester.runAsync(() async {
        const width = 240.0;
        final across = (width * ratio).round(), rows = (height * ratio).round();
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(ratio);
        for (var x = 0.0; x < width; x += 16) {
          canvas.drawRect(Rect.fromLTWH(x, -40, 8, height + 80), Paint()..color = const Color(0xFF000000));
        }
        final view = await recorder.endRecording().toImage(across, ((height + 80) * ratio).round());
        final out = ui.PictureRecorder();
        final drawn = Canvas(out)..scale(ratio);
        strip.paint(drawn, Rect.fromLTWH(0, 0, width, height), view, Rect.fromLTWH(0, -40, width, height + 80), ratio);
        final image = await out.endRecording().toImage(across, rows);
        final data = (await image.toByteData())!;
        return [
          for (var y = 0; y < rows; y++)
            () {
              // The middle of the strip: at its two ends the blur gathers what its clamped edge repeats.
              var low = 255, high = 0, step = 0;
              final pixel = ratio.round();
              int alpha(int x) => data.getUint8((y * across + x) * 4 + 3);
              for (var x = across ~/ 4; x < across * 3 ~/ 4; x++) {
                final a = alpha(x), d = (a - alpha(x + pixel)).abs();
                if (a < low) low = a;
                if (a > high) high = a;
                if (d > step) step = d;
              }
              final contrast = (high - low) / 255;
              return (contrast: contrast, steep: high > low ? step / (high - low) : 0.0);
            }(),
        ];
      }))!;
    }

    // Matt, 2026-10-24, on the Fold: "on android the blur is a gradient instead of a gradient blur". The view was
    // drawn sharp at a share falling evenly from the inner end to the edge, so halfway down half of every word was
    // there sharp over its own haze, and it read as words fading, not blurring. Measured on the emulator's Impeller
    // the same as here: each row's contrast fell in a straight line to the edge and every edge left stayed hard.
    for (final ratio in [1.0, 2.625]) {
      testWidgets('blurs what it shows, and does not merely fade it: past its first third no hard edge is left (at $ratio x)', (tester) async {
        const height = 48.0;
        final rows = await edgesDown(tester, const EdgeBlurStrip(rect: Rect.fromLTWH(0, 0, 240, height), side: EdgeSide.top, sigma: blurEdgeSigma), height, ratio: ratio);
        final inner = rows.last;
        expect(inner.contrast, greaterThan(0.9), reason: 'at the inner end the bars are as they were');
        expect(inner.steep, greaterThan(0.9), reason: 'and their edges are hard');
        for (var y = 0; y < rows.length * 2 ~/ 3; y++) {
          final row = rows[y];
          // Too faint to tell an edge from the steps between two shades of a byte.
          if (row.contrast < 0.06) continue;
          expect(row.steep, lessThan(0.35), reason: 'row $y of ${rows.length} (contrast ${row.contrast.toStringAsFixed(2)}): an edge this near the strip\'s own edge is soft, not a hard one faded');
        }
        // Halfway down the bars are still there to be seen, softened: a blur, not a wash of the page's ground.
        expect(rows[rows.length ~/ 2].contrast, greaterThan(0.08));

        // The measure can fail: the same bars only faded keep their hard edges all the way to the edge.
        final faded = await edgesDown(tester, const EdgeFadeStrip(rect: Rect.fromLTWH(0, 0, 240, height), fade: EdgeFade(clearUntil: 0, wholeFrom: height)), height, ratio: ratio);
        expect(faded[faded.length ~/ 3].steep, greaterThan(0.9));
      });
    }

    // Matt, 2026-10-25: "put a small gradient mask over it so the edge doesn't look like it's clipped so hard". The
    // first softness comes in over the sharp view as Android's mask does: by a smoothstep, with no corner.
    testWidgets('brings its first softness in over the sharp view by the gradient mask\'s smoothstep', (tester) async {
      const height = 96.0;
      final contrast = await contrastDown(tester, height);
      // Each row is the sharp stripes and the first softness's, weighed: its contrast is 1 less the mask's share of
      // what the first softness takes away, which is whole where the mask is.
      final whole = (height * (1 - edgeBlurFeather)).round();
      final lost = 1 - contrast[whole];
      expect(lost, greaterThan(0.2), reason: 'the first softness softens the stripes');
      for (final y in [whole + 8, whole + 16, whole + 24, height.round() - 4]) {
        final t = (height - y - 0.5) / height;
        expect(contrast[y], closeTo(1 - edgeBlurMask(t) * lost, 0.03), reason: 'row $y, ${(t / edgeBlurFeather).toStringAsFixed(2)} of the feather');
      }
      // The measure can fail: a straight line in its place is a quarter in where the smoothstep is a sixth.
      final y = height.round() - 8, t = (height - y - 0.5) / height;
      expect((1 - (t / edgeBlurFeather) * lost - contrast[y]).abs(), greaterThan(0.03));
    });

    testWidgets('is softest at its edge and sharp at its inner end, softening all the way with no step', (tester) async {
      final contrast = await contrastDown(tester, 40);
      expect(contrast.first, lessThan(0.25), reason: 'at the edge the stripes are near blurred away');
      expect(contrast.last, greaterThan(0.9), reason: 'at the inner end the view is as it was');
      for (var y = 1; y < contrast.length; y++) {
        expect(contrast[y], greaterThanOrEqualTo(contrast[y - 1] - 0.02), reason: 'row $y is no blurrier than the row nearer the edge');
        expect(contrast[y] - contrast[y - 1], lessThan(0.12), reason: 'row $y: no hard step between two softnesses');
      }
    });
  });

  group('the wisp', () {
    test('is drawn nowhere: no smoke widget, shader or bench is left, and the bend alone stays, for the heat and the haze', () {
      final shaders = Directory('shaders').listSync().map((f) => f.uri.pathSegments.last).toList();
      expect(shaders..sort(), ['edge_blur.frag', 'wisp_bend.frag'], reason: 'the bend, and the backdrop\'s blur on Android');
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(RegExp(r'shaders/\w+\.frag').allMatches(pubspec).map((m) => m.group(0)), ['shaders/wisp_bend.frag', 'shaders/edge_blur.frag']);
      const gone = ['wisp_edge', 'wisp_smoke', 'wisp_strips', 'wisp_mask', 'wisp_foot', 'wisp_sides', 'wisp_box', 'wisp_letters', 'wisp_probe', 'wisp_settings', 'dock_smoke', 'wisp_bench'];
      final users = <String>[];
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final text = file.readAsStringSync();
        for (final name in gone) {
          expect(file.path.endsWith('/$name.dart'), isFalse, reason: '${file.path} is the smoke\'s');
          expect(text.contains(RegExp("import '[^']*$name\\.dart'")), isFalse, reason: '${file.path} imports $name');
        }
        if (RegExp(r'\bWispKit\b').hasMatch(text)) users.add(file.path.replaceFirst('lib/', ''));
      }
      // What still bends: the heat on words and its tables, the scene's haze; the kit itself and the barrel.
      expect(users..sort(), ['art/wisp_kit.dart', 'editor/marks/text_effects.dart', 'editor/marks/wisp_tables.dart', 'scene/at_work.dart']);
    });
  });
}

/// Upright bars two pixels wide, black on white, every four: sharp, every row is as hard as an edge gets.
class _Bars extends CustomPainter {
  const _Bars();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    for (var x = 0.0; x < size.width; x += 4) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), Paint()..color = const Color(0xFF000000));
    }
  }

  @override
  bool shouldRepaint(_Bars old) => false;
}
