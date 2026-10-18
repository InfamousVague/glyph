// The dock grows smaller while the page under it scrolls (lib/shell/page_dock.dart `DockShrink`, docs/DOCK.md "How
// it moves"). Matt, 2026-10-17: "when we scroll make the dock bar animate to be 33% smaller", then "the navbar should
// only get 20% smaller 33% is too small, also it should stay small until scrolling back to the top of the page". Four
// fifths of itself once the person scrolls the page down, held to its bottom end corner; small however long the page
// is still; its own size again at the page's top, whoever took it there; its rings pressed where they are drawn while
// it is small; a carousel or a scroller inside the page leaves it as it is; under reduced motion it is one size or
// the other at once. The halo goes with it, and the home page's dock does the same.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/dock_smoke.dart';
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/shell/page_dock.dart';
import 'package:glacier/glacier.dart';

import '../home/support.dart';
import '../support/render.dart';
import 'dock_support.dart';

void main() {
  setUpAll(loadAppFonts);

  /// A page of [lines] under a dock of a page of notes, with whatever the page holds at its head.
  Widget page(List<String> asked, {List<Widget> head = const <Widget>[], PageDockSeam? seam}) => PageDockFrame(
        seam: seam ?? notesDock(asked),
        child: ListView(
          key: const ValueKey('page-scroll'),
          children: [
            ...head,
            for (var i = 0; i < 60; i++) SizedBox(height: 48, child: Text('line $i')),
          ],
        ),
      );

  Rect dock(WidgetTester tester) => tester.getRect(find.byType(PageDock));

  /// Holds a drag up the page from [from], and moves it a little at a time, as a thumb does.
  Future<TestGesture> scrollHeld(WidgetTester tester, {Offset from = const Offset(100, 500), Offset by = const Offset(0, -40)}) async {
    final gesture = await tester.startGesture(from);
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(by);
      await tester.pump(const Duration(milliseconds: 16));
    }
    return gesture;
  }

  ScrollPosition pageScroll(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  /// The page taken back to its top by a drag down, as a thumb does, and let go.
  Future<void> dragToTop(WidgetTester tester, {Offset from = const Offset(100, 300)}) async {
    final gesture = await tester.startGesture(from);
    while (pageScroll(tester).pixels > 0) {
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  void expectScaled(Rect now, Rect rested, double scale, {String? reason}) {
    expect(now.width, closeTo(rested.width * scale, 0.05), reason: reason);
    expect(now.height, closeTo(rested.height * scale, 0.05), reason: reason);
    // Held to its bottom end corner, where the thumb is.
    expect(now.right, closeTo(rested.right, 0.05), reason: reason);
    expect(now.bottom, closeTo(rested.bottom, 0.05), reason: reason);
  }

  group('while the page scrolls', () {
    testWidgets('the dock is four fifths of itself, in its corner, small however long the page is still, and its own size again at the top', (tester) async {
      expect(dockScrolledScale, 0.8);
      await pumpApp(tester, home: page([]));
      await tester.pump(const Duration(milliseconds: 500));
      final rested = dock(tester);
      expectInCorner(tester);

      final gesture = await scrollHeld(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(pageScroll(tester).pixels, greaterThan(0));
      expectScaled(dock(tester), rested, dockScrolledScale, reason: 'small while the thumb is on the page');
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expectScaled(dock(tester), rested, dockScrolledScale, reason: 'still small, the page still and not at its top');

      final back = await tester.startGesture(const Offset(100, 300));
      await back.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 16));
      expect(pageScroll(tester).pixels, greaterThan(dockTopSlack));
      await tester.pump(const Duration(milliseconds: 300));
      expectScaled(dock(tester), rested, dockScrolledScale, reason: 'scrolled up, but not to the top');
      await back.up();
      await tester.pumpAndSettle();
      await dragToTop(tester);
      expect(dock(tester), rested, reason: 'its own size at the top, where it was');
      await done(tester);
    });

    testWidgets('the page glided back to its top by the app makes it whole too', (tester) async {
      await pumpApp(tester, home: page([]));
      await tester.pump(const Duration(milliseconds: 500));
      final rested = dock(tester);
      final gesture = await scrollHeld(tester);
      await gesture.up();
      await tester.pumpAndSettle();
      expectScaled(dock(tester), rested, dockScrolledScale);
      pageScroll(tester).animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.linear);
      await tester.pumpAndSettle();
      expect(dock(tester), rested);
      await done(tester);
    });

    testWidgets('its rings are pressed where they are drawn while it is small', (tester) async {
      final asked = <String>[];
      await pumpApp(tester, home: page(asked));
      await tester.pump(const Duration(milliseconds: 500));
      final ring = GlacierTheme.of(tester.element(find.byType(PageDock))).len('app-ring');
      final gesture = await scrollHeld(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(find.byKey(const ValueKey('dock-settings'))).width, closeTo(ring * dockScrolledScale, 0.05));
      await pressAll(tester);
      expect(asked, ['claude', 'search', 'new', 'speak', 'settings']);
      await gesture.up();
      await tester.pumpAndSettle();
      await done(tester);
    });

    testWidgets('a carousel across the page, or a scroller inside it, leaves the dock as it is', (tester) async {
      await pumpApp(
        tester,
        home: page(
          [],
          head: [
            SizedBox(
              height: 120,
              child: ListView(key: const ValueKey('carousel'), scrollDirection: Axis.horizontal, children: [for (var i = 0; i < 20; i++) SizedBox(width: 120, child: Text('card $i'))]),
            ),
            SizedBox(
              height: 240,
              child: ListView(key: const ValueKey('inner'), children: [for (var i = 0; i < 40; i++) SizedBox(height: 40, child: Text('inner $i'))]),
            ),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final rested = dock(tester);
      final carousel = await scrollHeld(tester, from: const Offset(200, 60), by: const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(dock(tester), rested, reason: 'a carousel moving sideways');
      await carousel.up();
      await tester.pump(const Duration(milliseconds: 500));

      final inner = await scrollHeld(tester, from: const Offset(200, 300), by: const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('inner')), matching: find.byType(Scrollable))).position.pixels, greaterThan(0));
      expect(dock(tester), rested, reason: 'a scroller inside the page');
      await inner.up();
      await tester.pump(const Duration(milliseconds: 500));
      await done(tester);
    });

    testWidgets('the page moved by the app, not the person, leaves it as it is', (tester) async {
      await pumpApp(tester, home: page([]));
      await tester.pump(const Duration(milliseconds: 500));
      final rested = dock(tester);
      final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      position.animateTo(600, duration: const Duration(milliseconds: 300), curve: Curves.linear);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(position.pixels, greaterThan(0));
      expect(dock(tester), rested);
      await tester.pump(const Duration(milliseconds: 400));
      position.jumpTo(100);
      await tester.pump();
      expect(dock(tester), rested);
      await done(tester);
    });

    testWidgets('under reduced motion it is one size or the other at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpApp(tester, home: page([]));
      await tester.pump(const Duration(milliseconds: 500));
      final rested = dock(tester);
      final gesture = await tester.startGesture(const Offset(100, 500));
      await gesture.moveBy(const Offset(0, -40));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      expectScaled(dock(tester), rested, dockScrolledScale, reason: 'small at the first frame of the scroll');
      await gesture.up();
      await tester.pumpAndSettle();
      pageScroll(tester).jumpTo(0);
      await tester.pump();
      expect(dock(tester), rested, reason: 'whole at the first frame at the top');
      await done(tester);
    });

    testWidgets('the halo goes with it, round the dock as it is drawn', (tester) async {
      await pumpApp(
        tester,
        home: page([], seam: PageDockSeam(halo: (context, it) => DockSmoke(behind: it.behind, dock: it.dock, alignment: it.alignment, padding: it.padding, shown: it.shown, scale: it.scale), actions: notesDock([]).actions, foot: notesDock([]).foot)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final rested = dock(tester);
      DockHalo halo() => tester.widget<DockHalo>(find.byType(DockHalo));
      expect(halo().dock, rested);
      expect(halo().reach, dockSmokeReach);
      final gesture = await scrollHeld(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      final small = dock(tester);
      expectScaled(small, rested, dockScrolledScale);
      expect(halo().dock!.left, closeTo(small.left, 0.05));
      expect(halo().dock!.top, closeTo(small.top, 0.05));
      expect(halo().dock!.size.width, closeTo(small.width, 0.05));
      expect(halo().dock!.size.height, closeTo(small.height, 0.05));
      expect(halo().reach, closeTo(dockSmokeReach * dockScrolledScale, 0.01));
      await gesture.up();
      await tester.pumpAndSettle();
      await dragToTop(tester);
      await tester.pump();
      expect(halo().dock, rested);
      await done(tester);
    });
  });

  group('the home page’s dock', () {
    testWidgets('is four fifths of itself once the page is scrolled, and whole again at its top', (tester) async {
      final it = seeded();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      final rested = dock(tester);
      final gesture = await scrollHeld(tester, from: const Offset(150, 600));
      await tester.pump(const Duration(milliseconds: 300));
      expectScaled(dock(tester), rested, dockScrolledScale);
      await tester.tap(find.byKey(const ValueKey('dock-add')));
      expect(it.asked.said, contains('new'));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expectScaled(dock(tester), rested, dockScrolledScale, reason: 'small, the page still and not at its top');
      pageScroll(tester).jumpTo(0);
      await tester.pumpAndSettle();
      expect(dock(tester), rested);
      expect(find.byType(HomeScreen), findsOneWidget);
      await done(tester);
    });
  });
}
