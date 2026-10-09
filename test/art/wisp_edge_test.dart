import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';

/// The wisp edge on a view: when it wears the smoke, where the bands are placed, the budget that keeps a view too
/// large on its plain fade, the drift that moves only the band being scrolled, and what is left with reduced motion
/// and on a desktop. Case for case with the web app's art/wispEdge.test.tsx, said of the strips a view is drawn
/// through where that is said of a filter's attributes; the look of the smoke is test/art/wisp_parity_test.dart's.
class _Views {
  _Views(this.tester);
  final WidgetTester tester;
  final page = ScrollController(), column = ScrollController();

  List<WispStrip> strips(String name) => tester.renderObject<RenderWispStrips>(find.descendant(of: find.byKey(ValueKey(name)), matching: find.byType(WispStrips))).strips;
  WispSmokeStrip? top(String name) => strips(name).whereType<WispSmokeStrip>().where((s) => s.smoke.lipA != null).firstOrNull;
  WispSmokeStrip? foot(String name) => strips(name).whereType<WispSmokeStrip>().where((s) => s.smoke.lipB != null).firstOrNull;

  Future<void> scroll(ScrollController controller, double to) async {
    controller.jumpTo(to);
    await tester.pump();
  }

  /// Plays [count] frames, 30 ms apart: each far enough from the last to be a step of the drift, and all of them
  /// together short of the wait after which a scroll counts as stopped.
  Future<void> run([int count = 5]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }
}

void main() {
  tearDown(() {
    WispSettings.instance.reset();
    WispDrift.instance.debugReset();
  });

  /// A screen with room for the views: a test's own is 800 by 600.
  void room(WidgetTester tester) {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(2000, 2000);
    addTearDown(tester.view.reset);
  }

  Widget scroller(ScrollController controller, double more) =>
      SingleChildScrollView(controller: controller, child: SizedBox(height: 800 + more, child: const Align(alignment: Alignment.topLeft, child: Text('Hold. Talk. Done.', textDirection: TextDirection.ltr))));

  /// A view 400 by 800 that can scroll [more] px past its height, wearing the wisp edge under a header [header] px
  /// tall; in a [window] of its own size unless another is given.
  Future<_Views> view(
    WidgetTester tester, {
    double more = 600,
    double header = 0,
    bool foot = false,
    double footOver = 0,
    Size window = const Size(400, 800),
    double ratio = 2,
    bool still = false,
    double safeTop = 0,
    WispDraw? draw,
    ValueChanged<bool>? onChanged,
  }) async {
    await tester.runAsync(() => WispKit.load());
    room(tester);
    final views = _Views(tester);
    addTearDown(views.page.dispose);
    addTearDown(views.column.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: window, devicePixelRatio: ratio, disableAnimations: still),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: const ValueKey('page'),
              width: 400,
              height: 800,
              child: WispEdge(under: header, foot: foot, footOver: footOver, safeTop: safeTop, draw: draw, onChanged: onChanged, child: scroller(views.page, more)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return views;
  }

  /// A page and a column beside it, as Settings' split view has them: the page under no header, the column under a
  /// header [header] px tall and wearing the column's band; asking for a foot as well when [foot].
  Future<_Views> pageAndColumn(WidgetTester tester, {double header = 54, bool foot = false, Size window = const Size(800, 800), double ratio = 2, WispDraw? draw}) async {
    await tester.runAsync(() async {
      await WispKit.load();
      if (draw == WispDraw.mask) await wispMaskBands();
    });
    room(tester);
    final views = _Views(tester);
    addTearDown(views.page.dispose);
    addTearDown(views.column.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: window, devicePixelRatio: ratio),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              height: 800,
              child: Row(
                children: [
                  SizedBox(key: const ValueKey('column'), width: 400, child: WispEdge(under: header, foot: foot, band: WispBand.column, safeTop: 0, draw: draw, child: scroller(views.column, 600))),
                  SizedBox(key: const ValueKey('page'), width: 400, child: WispEdge(safeTop: 0, draw: draw, child: scroller(views.page, 600))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return views;
  }

  group('the numbers', () {
    test('are the web app\'s own', () {
      final edge = (jsonDecode(File('test/art/reference/cases.json').readAsStringSync()) as Map<String, dynamic>)['edge'] as Map<String, dynamic>;
      expect(wispEdgeAbove, edge['ABOVE']);
      expect(wispEdgeBand, edge['BAND']);
      expect(wispEdgeSoft, edge['SOFT']);
      expect(wispEdgeReach, edge['REACH']);
      expect(wispEdgeFootBand, edge['FOOT_BAND']);
      expect(wispEdgeFootSoft, edge['FOOT_SOFT']);
      expect(wispEdgeFootLift, edge['FOOT_LIFT']);
      expect(wispEdgeFootClear, edge['FOOT_CLEAR']);
      expect(wispEdgeEase, edge['EASE']);
      expect(wispEdgeSide, edge['SIDE']);
      expect(wispEdgeDrop, edge['DROP']);
      expect(wispEdgeFootReach, edge['FOOT_REACH']);
    });

    test('step the drift as the page steps it', () {
      // The reference pictures were drawn five seconds into a scroll, with what the page's own arithmetic gave.
      final top = ((jsonDecode(File('test/art/reference/cases.json').readAsStringSync()) as Map<String, dynamic>)['cases'] as Map<String, dynamic>)['top'] as Map<String, dynamic>;
      final at = WispDriftAt.at(5000);
      expect('${at.frequency.dx} ${at.frequency.dy}', top['frequency']);
      expect(at.slide.dx.toStringAsFixed(2), top['dx']);
      expect(at.slide.dy.toStringAsFixed(2), top['dy']);
      // The noise never slides up past the view's top, nor more than its 20px down.
      for (var t = 0.0; t < 60000; t += 137) {
        final slide = WispDriftAt.at(t).slide;
        expect(slide.dy, inInclusiveRange(0, wispSlidePx));
        expect(slide.dx.abs(), lessThanOrEqualTo(4));
      }
    });
  });

  group('the budget', () {
    test('holds a region to 2^24 of the screen\'s own pixels', () {
      expect(withinWispBudget(4096, 4096, 1), isTrue);
      expect(withinWispBudget(4200, 4000, 1), isFalse);
      // At two device pixels to the logical pixel, the boundary moves to 2048 exactly.
      expect(withinWispBudget(2048, 2048, 2), isTrue);
      expect(withinWispBudget(2049, 2048, 2), isFalse);
    });
  });

  group('WispEdge', () {
    testWidgets('wears the smoke once the view is scrolled off its top, and puts it away at the top again', (tester) async {
      final changes = <bool>[];
      final v = await view(tester, onChanged: changes.add);
      expect(v.strips('page'), isEmpty);
      await v.scroll(v.page, 120);
      // The band at the view's top, its lip at the band's own depth: no header, and a phone with no status bar.
      expect(v.top('page')!.smoke.lipA, wispEdgeBand);
      expect(v.top('page')!.within.bottom, wispEdgeReach);
      expect(v.top('page')!.rect, const Rect.fromLTRB(0, 0, 400, wispEdgeReach));
      expect(v.top('page')!.smoke.bend, 24);
      expect(changes, [true]);
      await v.scroll(v.page, 0);
      expect(v.strips('page'), isEmpty);
      expect(changes, [true, false]);
    });

    testWidgets('taken down while its scroll is still counted as moving, rests its band after the frame and tells nobody mid-build', (tester) async {
      final v = await view(tester);
      await v.scroll(v.page, 120);
      await v.scroll(v.page, 140);
      await v.run(3);
      expect(WispDrift.instance.at(WispBand.page), isNot(WispDriftAt.rest));
      // A listener of the band that rebuilds, as a view beside it would: telling it while the tree is locked throws.
      final beside = ListenableBuilder(listenable: WispDrift.instance.of(WispBand.page), builder: (context, _) => const SizedBox.shrink());
      await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: beside));
      expect(tester.takeException(), isNull);
      await tester.pump();
      expect(WispDrift.instance.at(WispBand.page), WispDriftAt.rest);
    });

    testWidgets('draws the strip through the shaders once they have loaded', (tester) async {
      final v = await view(tester, foot: true);
      await v.scroll(v.page, 120);
      final box = tester.renderObject<RenderWispStrips>(find.byType(WispStrips));
      expect(box.debugPainted.whereType<WispSmokeStrip>(), hasLength(2));
      expect(box.alwaysNeedsCompositing, isTrue);
      await v.scroll(v.page, 0);
      await v.scroll(v.page, 600);
      expect(box.debugPainted.whereType<WispSmokeStrip>(), hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('never smokes a view that cannot scroll, whatever its place says', (tester) async {
      final v = await view(tester, more: 0);
      expect(v.strips('page'), isEmpty);
    });

    testWidgets('moves the band under a header', (tester) async {
      final v = await view(tester, header: 60);
      await v.scroll(v.page, 120);
      // Below the header, the drop under its edge, and the lip.
      expect(v.top('page')!.smoke.lipA, 60 + wispEdgeDrop + wispEdgeBand);
      expect(v.top('page')!.within.bottom, 60 + wispEdgeDrop + wispEdgeReach);
      // Under a header the header hides the top, so nothing fades there.
      expect(v.top('page')!.smoke.fade.at(0), 1);
    });

    testWidgets('with no header, sits at the view\'s own top and fades over the status bar\'s height', (tester) async {
      final v = await view(tester, safeTop: 36);
      await v.scroll(v.page, 120);
      // The page's `safeTop()` reads a `calc()` as no number, so its lip is at the top edge with no drop (Settings
      // on Android: the filter's strip ends 7px down), and the fade is the stylesheet's, safe top and 8px.
      expect(v.top('page')!.smoke.lipA, wispEdgeBand);
      expect(v.top('page')!.rect.bottom, greaterThanOrEqualTo(44));
      expect(v.top('page')!.smoke.fade.at(0), 0);
      expect(v.top('page')!.smoke.fade.at(22), closeTo(0.5, 1e-9));
      expect(v.top('page')!.smoke.fade.at(44), 1);
    });

    testWidgets('smokes the foot while there is more below, and not at the end', (tester) async {
      final v = await view(tester, foot: true);
      // The foot's lip above the view's bottom edge, lifted to where the words still are.
      expect(v.foot('page')!.smoke.lipB, 800 - wispEdgeFootLift - wispEdgeFootBand);
      expect(v.foot('page')!.smoke.bend, 23);
      expect(v.foot('page')!.rect, const Rect.fromLTRB(0, 800 - wispEdgeFootLift - wispEdgeFootReach, 400, 800));
      // The last 32px dissolve under the smoke, and the top is crisp: nothing is going under the header yet.
      expect(v.foot('page')!.smoke.fade.at(800 - 16), closeTo(0.5, 1e-9));
      expect(v.foot('page')!.smoke.fade.at(0), 1);
      await v.scroll(v.page, 600);
      expect(v.foot('page'), isNull);
    });

    testWidgets('smokes the foot at a dock\'s top edge, and is gone below it', (tester) async {
      final v = await view(tester, foot: true, footOver: 80);
      expect(v.foot('page')!.smoke.lipB, 720 - wispEdgeFootLift - wispEdgeFootBand);
      expect(v.foot('page')!.smoke.fade.at(719), greaterThan(0));
      expect(v.foot('page')!.smoke.fade.at(721), 0);
      expect(v.foot('page')!.rect.bottom, 800);
    });

    testWidgets('keeps a window too large for the filter\'s budget on its plain fade', (tester) async {
      final v = await view(tester, foot: true, window: const Size(5000, 5000), ratio: 1);
      await v.scroll(v.page, 120);
      expect(v.strips('page'), isEmpty);
    });

    testWidgets('draws nothing at all with the smoke switched off in Settings', (tester) async {
      WispSettings.instance.wanted = false;
      final v = await view(tester, foot: true);
      await v.scroll(v.page, 120);
      expect(v.strips('page'), isEmpty);
      // And puts it on when it is switched back, without waiting for a scroll.
      WispSettings.instance.wanted = true;
      await tester.pump();
      await v.scroll(v.page, 121);
      expect(v.top('page'), isNotNull);
      WispSettings.instance.wanted = false;
      await tester.pump();
      expect(v.strips('page'), isEmpty);
    });

    testWidgets('drifts while it is scrolled, holds when the scrolling stops, and rests at the top', (tester) async {
      final v = await view(tester);
      await v.scroll(v.page, 120);
      await v.run();
      final moved = v.top('page')!.smoke;
      expect(moved.slide, isNot(Offset.zero));
      expect(moved.frequency, isNot(wispBaseFrequency));
      // The scrolling stops: after the wait the smoke holds where it is.
      await tester.pump(const Duration(milliseconds: 200));
      final held = v.top('page')!.smoke.slide;
      await v.run();
      expect(v.top('page')!.smoke.slide, held);
      // A view back at its top while it is moving puts its band back to rest.
      await v.scroll(v.page, 160);
      await v.run();
      await v.scroll(v.page, 0);
      expect(WispDrift.instance.at(WispBand.page), WispDriftAt.rest);
    });

    testWidgets('holds its drift while a recording holds it, and tells whoever follows', (tester) async {
      final seen = <Offset>[];
      final unfollow = WispDrift.instance.follow((dx, dy, frequency) => seen.add(Offset(dx, dy)));
      final release = WispDrift.instance.hold();
      final v = await view(tester);
      await v.scroll(v.page, 120);
      await v.run();
      expect(v.top('page')!.smoke.slide, Offset.zero);
      expect(seen, isEmpty);
      release();
      release();
      await v.scroll(v.page, 130);
      await v.run();
      expect(v.top('page')!.smoke.slide, isNot(Offset.zero));
      expect(seen, isNotEmpty);
      expect(seen.last, v.top('page')!.smoke.slide);
      final count = seen.length;
      unfollow();
      await v.scroll(v.page, 140);
      await v.run();
      expect(seen, hasLength(count));
    });

    testWidgets('takes everything it put on the view away when it goes', (tester) async {
      final v = await view(tester, foot: true, header: 40);
      await v.scroll(v.page, 120);
      await v.run(2);
      await tester.pumpWidget(const SizedBox());
      // Nothing is left moving, and nothing is left on the clock (the binding checks for a timer left behind).
      await v.run(3);
      expect(WispDrift.instance.at(WispBand.page), WispDriftAt.rest);
    });

    testWidgets('with reduced motion keeps the fade and loses the bend, and starts no drift', (tester) async {
      final v = await view(tester, foot: true, still: true, safeTop: 36);
      await v.scroll(v.page, 120);
      await v.run();
      expect(v.strips('page').whereType<WispSmokeStrip>(), isEmpty);
      final fades = v.strips('page').whereType<WispFadeStrip>().toList();
      expect(fades.map((s) => s.rect), [const Rect.fromLTRB(0, 0, 400, 44), const Rect.fromLTRB(0, 800 - 32, 400, 800)]);
      expect(WispDrift.instance.at(WispBand.page), WispDriftAt.rest);
      expect(footSmokes(true, still: true), isFalse);
    });

    testWidgets('on a desktop hangs a blur under the header and fades the foot, with no smoke and no drift', (tester) async {
      WispSettings.instance.head = WispHead.blur;
      final v = await view(tester, header: 60, foot: true);
      expect(v.strips('page').whereType<WispFadeStrip>().single.rect, const Rect.fromLTRB(0, 800 - 28, 400, 800));
      await v.scroll(v.page, 120);
      await tester.pump(const Duration(milliseconds: 80));
      final rising = v.strips('page').whereType<WispBlurStrip>().single;
      expect(rising.rect, const Rect.fromLTWH(0, 60, 400, 28));
      expect(rising.opacity, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(v.strips('page').whereType<WispBlurStrip>().single.opacity, 1);
      expect(v.strips('page').whereType<WispSmokeStrip>(), isEmpty);
      await v.run();
      expect(WispDrift.instance.at(WispBand.page), WispDriftAt.rest);
      await v.scroll(v.page, 0);
      await tester.pump(const Duration(milliseconds: 400));
      expect(v.strips('page').whereType<WispBlurStrip>(), isEmpty);
    });

    testWidgets('draws the torn mask when it is asked for by name', (tester) async {
      await tester.runAsync(() => wispMaskBands());
      final v = await view(tester, header: 60, foot: true, draw: WispDraw.mask);
      await v.scroll(v.page, 120);
      final masks = v.strips('page').whereType<WispMaskStrip>().toList();
      expect(masks, hasLength(2));
      // The top tears down to 76px past the lip; its band's lip is 160px down its picture.
      expect(masks[0].rect, const Rect.fromLTRB(0, 0, 400, 60 + 12 + 76));
      expect(masks[0].bandAt.dy, 60 + 12 - wispMaskAbove);
      expect(masks[0].band, isNotNull);
      expect(masks[1].rect.top, 800 - wispTearFoot);
      expect(tester.takeException(), isNull);
    });
  });

  /*
   * Settings' split view scrolls a column beside a page, both smoking at their tops at once under headers of
   * different heights, each with a band of its own.
   */
  group('a column\'s band beside the page\'s', () {
    testWidgets('places each under its own header, and takes only its own away at the top', (tester) async {
      final v = await pageAndColumn(tester);
      await v.scroll(v.page, 120);
      await v.scroll(v.column, 120);
      // The page's lip at its own top, as if the column were not there; the column's under its 54px header.
      expect(v.top('page')!.smoke.lipA, wispEdgeBand);
      expect(v.top('column')!.smoke.lipA, 54 + wispEdgeDrop + wispEdgeBand);
      await v.scroll(v.column, 0);
      expect(v.strips('column'), isEmpty);
      expect(v.top('page')!.smoke.lipA, wispEdgeBand);
    });

    testWidgets('holds the column to the budget together with the page beside it', (tester) async {
      // Two device pixels to the logical pixel, as on the Mac. At 1800 x 1100 the pair fits, and both smoke.
      var v = await pageAndColumn(tester, window: const Size(1800, 1100));
      await v.scroll(v.page, 120);
      await v.scroll(v.column, 120);
      expect(v.top('page'), isNotNull);
      expect(v.top('column'), isNotNull);
      await tester.pumpWidget(const SizedBox());
      // At 2200 x 1300 the page's region fits on its own and the pair does not: the column keeps its plain edge.
      v = await pageAndColumn(tester, window: const Size(2200, 1300));
      await v.scroll(v.page, 120);
      await v.scroll(v.column, 120);
      expect(v.top('page'), isNotNull);
      expect(v.strips('column'), isEmpty);
      expect(wispRegionFits(view: const Size(400, 800), window: const Size(2200, 1300), band: WispBand.page, ratio: 2), isTrue);
      expect(wispRegionFits(view: const Size(400, 800), window: const Size(2200, 1300), band: WispBand.column, ratio: 2, right: 400), isFalse);
      // A column standing 100px in reaches 500px across.
      expect(wispRegionFits(view: const Size(400, 800), window: const Size(1800, 1100), band: WispBand.column, ratio: 2, right: 500), isTrue);
    });

    testWidgets('eases the column\'s lip down over the first px of its scroll, and leaves the page\'s where it is', (tester) async {
      final v = await pageAndColumn(tester);
      double lip() => v.top('column')!.smoke.lipA!;
      await v.scroll(v.column, 10);
      final early = lip();
      await v.scroll(v.column, 20);
      expect(lip(), early + 10);
      await v.scroll(v.column, 120);
      // Settled a band's depth below where it began, and there it stays.
      expect(lip(), early + wispEdgeEase - 10);
      await v.scroll(v.column, 400);
      expect(lip(), early + wispEdgeEase - 10);
      // Under no header, at its own top, and never eased: the page's first lines are not at an edge.
      await v.scroll(v.page, 10);
      expect(v.top('page')!.smoke.lipA, wispEdgeBand);
    });

    testWidgets('never smokes a column at its foot, asked or not', (tester) async {
      final v = await pageAndColumn(tester, foot: true);
      await v.scroll(v.column, 120);
      expect(v.foot('column'), isNull);
      expect(v.top('column'), isNotNull);
    });

    testWidgets('drifts a masked column\'s smoke on the column, not on the page', (tester) async {
      final v = await pageAndColumn(tester, draw: WispDraw.mask);
      await v.scroll(v.column, 120);
      await v.run();
      final band = v.strips('column').whereType<WispMaskStrip>().single;
      // Its lip a band's depth further down than where it began, and its smoke slid.
      expect(band.bandAt.dy - WispDrift.instance.at(WispBand.column).slide.dy, 54 + wispEdgeDrop - wispMaskAbove);
      expect(WispDrift.instance.at(WispBand.column).slide.dy, isNot(0));
      expect(WispDrift.instance.at(WispBand.page), WispDriftAt.rest);
    });

    testWidgets('puts the column\'s band back to rest at its top, and leaves the page\'s drifted', (tester) async {
      final v = await pageAndColumn(tester);
      await v.scroll(v.page, 120);
      await v.scroll(v.column, 120);
      await v.run();
      expect(WispDrift.instance.at(WispBand.column).slide.dy, isNot(0));
      final pageDrift = WispDrift.instance.at(WispBand.page);
      expect(pageDrift.slide.dy, isNot(0));
      await v.scroll(v.column, 0);
      expect(WispDrift.instance.at(WispBand.column), WispDriftAt.rest);
      expect(WispDrift.instance.at(WispBand.page), pageDrift);
    });

    testWidgets('drifts only the band being scrolled: the column\'s smoke holds while the page beside it scrolls', (tester) async {
      final v = await pageAndColumn(tester);
      await v.scroll(v.column, 120);
      await v.run();
      final held = WispDrift.instance.at(WispBand.column);
      expect(held.slide.dy, isNot(0));
      expect(WispDrift.instance.at(WispBand.page), WispDriftAt.rest);
      // The column's scrolling stops; the page's starts, and goes on for a while.
      await tester.pump(const Duration(milliseconds: 200));
      await v.scroll(v.page, 120);
      await v.run();
      await v.scroll(v.page, 160);
      await v.run();
      expect(WispDrift.instance.at(WispBand.page).slide.dy, isNot(0));
      expect(WispDrift.instance.at(WispBand.column), held);
      // And the column picks up again when it is scrolled.
      await v.scroll(v.column, 160);
      await v.run();
      expect(WispDrift.instance.at(WispBand.column), isNot(held));
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('whether the foot smokes, for a note to keep its caret clear of it', () {
    test('smokes where it is drawn as smoke, and not with the preference off', () {
      expect(footSmokes(true, still: false), isTrue);
      expect(footSmokes(false, still: false), isFalse);
    });

    test('does not on a desktop, whose foot is a plain fade', () {
      WispSettings.instance.head = WispHead.blur;
      expect(wispModeFor(), WispMode.fade);
      expect(footSmokes(true, still: false), isFalse);
      // A view that asks for a drawing by name gets it, desktop or not.
      expect(wispModeFor(WispDraw.filter), WispMode.filter);
    });

    test('does not with reduced motion, which takes the filter away, but the mask stays', () {
      WispSettings.instance.head = WispHead.smoke;
      expect(footSmokes(true, still: true), isFalse);
      WispSettings.instance.draw = WispDraw.mask;
      expect(footSmokes(true, still: true), isTrue);
    });

    test('is the filter on a phone unless the mask is asked for by name', () {
      expect(wispDraw(), WispDraw.filter);
      WispSettings.instance.draw = WispDraw.mask;
      expect(wispDraw(), WispDraw.mask);
      expect(wispModeFor(), WispMode.mask);
      expect(dockBends(), isFalse);
      WispSettings.instance.draw = null;
      expect(dockBends(), isTrue);
    });
  });
}
