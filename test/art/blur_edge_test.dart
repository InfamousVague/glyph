import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';

/// The gradient blur on a view, where the wisp's smoke was (Matt, 2026-10-24: "replace the smoke effect with a
/// gradient blur on all places that use the wisp smoke", then "remove the smoke on mac too so all versions get
/// blur"): when a view wears it, where its bands are, what the switch and reduced motion do, that every platform
/// draws the same, and that the blur is a blur, the softest at the edge. Case for case with what
/// test/art/wisp_edge_test.dart said of the smoke, where the smoke's numbers allow.
void main() {
  tearDown(() {
    BlurEdgeSettings.instance.reset();
    debugDefaultTargetPlatformOverride = null;
  });

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

  List<EdgeStrip> strips(WidgetTester tester) => tester.renderObject<RenderEdgeStrips>(find.descendant(of: find.byKey(const ValueKey('page')), matching: find.byType(EdgeStrips))).strips;
  EdgeBlurStrip? top(WidgetTester tester) => strips(tester).whereType<EdgeBlurStrip>().where((s) => s.side == EdgeSide.top).firstOrNull;
  EdgeBlurStrip? foot(WidgetTester tester) => strips(tester).whereType<EdgeBlurStrip>().where((s) => s.side == EdgeSide.bottom).firstOrNull;

  group('BlurEdge', () {
    testWidgets('blurs under the header once the view is scrolled off its top, turning in, and lets go at the top', (tester) async {
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

    testWidgets('never blurs a view that cannot scroll, whatever its place says', (tester) async {
      await view(tester, header: 60, more: 2, foot: true);
      expect(strips(tester), isEmpty);
    });

    testWidgets('with no header, fades over the status bar\'s height and 8px more, and is soft for a band past it', (tester) async {
      final scroll = await view(tester, safeTop: 36);
      scroll.jumpTo(100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final strip = top(tester)!;
      expect(strip.rect, const Rect.fromLTRB(0, 0, 400, 36 + 8 + blurEdgeDepth));
      expect(strip.fade, const EdgeFade(clearUntil: 0, wholeFrom: 44));
    });

    testWidgets('blurs the foot while there is more below, and not at the end', (tester) async {
      final scroll = await view(tester, foot: true);
      expect(foot(tester)!.rect, const Rect.fromLTRB(0, 800 - blurEdgeFootDepth, 400, 800));
      expect(foot(tester)!.fade, const EdgeFade(wholeUntil: 800 - blurEdgeFootFade, clearFrom: 800));
      scroll.jumpTo(600);
      await tester.pump();
      expect(foot(tester), isNull);
    });

    testWidgets('blurs the foot at a dock\'s top edge, and is gone below it', (tester) async {
      await view(tester, foot: true, footOver: 100);
      expect(foot(tester)!.rect, const Rect.fromLTRB(0, 700 - blurEdgeFootDepth, 400, 700));
      final below = strips(tester).whereType<EdgeFadeStrip>().single;
      expect(below.rect, const Rect.fromLTRB(0, 700, 400, 800));
      expect(below.fade.at(701), 0, reason: 'beside and under the dock the view is clear');
    });

    testWidgets('draws nothing at all with the blur switched off in Settings, and comes back with it', (tester) async {
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

    testWidgets('with reduced motion keeps the blur, which does not move, and loses only its turn', (tester) async {
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

    for (final platform in TargetPlatform.values) {
      testWidgets('draws the same blur on ${platform.name}, and asks for no frame of its own while it rests', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final scroll = await view(tester, header: 60, foot: true);
        scroll.jumpTo(100);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(strips(tester).map((s) => s.runtimeType), [EdgeBlurStrip, EdgeBlurStrip]);
        expect(top(tester)!.rect, const Rect.fromLTWH(0, 60, 400, blurEdgeDepth));
        expect(foot(tester)!.rect, const Rect.fromLTRB(0, 800 - blurEdgeFootDepth, 400, 800));
        expect(tester.binding.hasScheduledFrame, isFalse, reason: 'the smoke drifted on its own clock while a page scrolled; a blur has none');
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

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
      expect(shaders, ['wisp_bend.frag']);
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(RegExp(r'shaders/\w+\.frag').allMatches(pubspec).map((m) => m.group(0)), ['shaders/wisp_bend.frag']);
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
