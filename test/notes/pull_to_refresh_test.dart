import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/home/lazy_page.dart';
import 'package:ghost_md/notes/pull_to_refresh.dart';

import '../support/render.dart';

/// A pull to refresh over the page as the home page builds it: the scroller under the edge's blur, in the pull's
/// builder (lib/home/home_screen.dart `page`, lib/root/root_parts.dart `_headerEdge`).
///
/// Found beside Ghost.md on the emulator, 2026-10-11 (docs/AB_FINDINGS.json pull-1): after a quick pull the home
/// page took no touch at all, no scroll and no press on Filters or a card, until the app was started again. A
/// finger's first moves reach the app between two frames, so the scroller has begun its own drag by the time the
/// pull takes its physics away; the framework then cancels that drag in the middle of the layout, the scroller says
/// the scroll has ended, and the edge (the wisp's then, a blur now), hearing it, read its own box's size, which a debug build refuses to
/// anyone but the box's parent while a layout runs. The refusal came up through the cancel and left the scroller in
/// its drag, ignoring every pointer, with no recognizer to begin another.
void main() {
  setUpAll(loadAppFonts);

  /// A finger down at [from], [dy] further in [ms], let go: [steps] moves, a frame only after every [every] of them.
  Future<void> swipe(WidgetTester tester, Offset from, double dy, int ms, {int steps = 8, required int every}) async {
    final gesture = await tester.startGesture(from, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= steps; i += 1) {
      await gesture.moveBy(Offset(0, dy / steps), timeStamp: Duration(milliseconds: ms * i ~/ steps));
      if (i % every == 0) await tester.pump(Duration(milliseconds: ms * every ~/ steps));
    }
    await gesture.up();
    await tester.pump();
  }

  for (final every in [2, 3]) {
    testWidgets('a quick pull leaves the page one that scrolls and takes a tap (a frame every $every moves of the finger)', (tester) async {
      final controller = ScrollController();
      var refreshes = 0;
      final tapped = <int>[];
      await pumpApp(
        tester,
        home: PullToRefresh(
          controller: controller,
          onRefresh: () async => refreshes += 1,
          top: 100,
          builder: (context, pull) => BlurEdge(
            under: 60,
            foot: true,
            child: LayoutBuilder(
              builder: (context, box) => PageScroll(
                key: const ValueKey('home-scroll'),
                controller: controller,
                pull: pull,
                slivers: [
                  SliverList.builder(
                    itemCount: 60,
                    itemBuilder: (context, i) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => tapped.add(i),
                      child: SizedBox(height: 60, child: Text('row $i')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Two pulls, the second while the first is still shown.
      await swipe(tester, const Offset(200, 300), 300, 120, every: every);
      await tester.pump(const Duration(milliseconds: 700));
      await swipe(tester, const Offset(200, 300), 300, 120, every: every);
      for (var i = 0; i < 40; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(refreshes, greaterThan(0));
      expect(tester.takeException(), isNull);

      final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
      expect(position.activity, isA<IdleScrollActivity>(), reason: 'the drag the pull took over is ended, not left running');

      // A row takes a tap, and the page scrolls under a finger.
      await tester.tapAt(const Offset(200, 330));
      await tester.pump();
      expect(tapped, isNotEmpty, reason: 'the scroller is not ignoring its rows');
      await swipe(tester, const Offset(200, 600), -300, 300, every: 1);
      for (var i = 0; i < 10; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.offset, greaterThan(100), reason: 'the page scrolls after a pull');

      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
