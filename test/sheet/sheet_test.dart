import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:ghost_md/sheet/sheet.dart';
import 'package:glacier/glacier.dart';

import '../sidebar/support.dart';
import '../support/render.dart';

/// The app's bottom sheet (sheet/sheet.dart, the web's editor/Sheet.tsx): how it opens, what closes it, how its
/// handle is pulled, where it sits over the keyboard, and the window it is on a desktop.
void main() {
  setUpAll(loadAppFonts);

  final panel = find.byKey(const ValueKey('sheet-panel'));
  final grip = find.byKey(const ValueKey('sheet-grip'));
  final scrim = find.byKey(const ValueKey('sheet-scrim'));

  /// A page with a sheet over it while [open], and a button under where the scrim will be.
  Widget page({required bool open, required VoidCallback onClose, VoidCallback? onBack, VoidCallback? onUnder, void Function(PointerDownEvent)? onScrimDown, List<Widget>? children}) {
    return BackScope(
      child: Stack(
        children: [
          Positioned(left: 20, top: 100, child: GestureDetector(key: const ValueKey('under'), onTap: onUnder, child: const SizedBox(width: 100, height: 60, child: Text('Under the sheet')))),
          if (open)
            Sheet(
              label: 'A sheet',
              onClose: onClose,
              onBack: onBack,
              onScrimPointerDown: onScrimDown,
              children: children ??
                  [
                    SheetTitle.text('A sheet'),
                    const SheetNote('What it is for.'),
                    SheetGroup(children: [SheetRow(label: 'One', onPress: () {}), SheetRow(label: 'Two', onPress: () {})]),
                  ],
            ),
        ],
      ),
    );
  }

  group('opening', () {
    testWidgets('is over the page as a dialog of its name, takes no room where it is built, and comes up from the foot', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPage(tester, page(open: true, onClose: () {}));
      // The first frame: on its way in.
      expect(tester.widget<Opacity>(find.ancestor(of: scrim, matching: find.byType(Opacity)).first).opacity, lessThan(1));
      expect(tester.getSize(find.byType(Sheet)), Size.zero);
      await settle(tester);
      expect(tester.widget<Opacity>(find.ancestor(of: scrim, matching: find.byType(Opacity)).first).opacity, 1);
      final at = tester.getRect(panel);
      expect([at.left, at.width, at.bottom], [0, 390, 844]);
      final node = tester.getSemantics(find.bySemanticsLabel('A sheet').first);
      expect(node.role, SemanticsRole.dialog);
      expect(node.flagsCollection.scopesRoute, isTrue);
      // `aria-modal="true"`: what is under it is not read.
      expect(find.bySemanticsLabel('Under the sheet'), findsNothing);
      handle.dispose();
      await away(tester);
    });

    testWidgets('asked for less motion, is there at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpPage(tester, page(open: true, onClose: () {}));
      expect(tester.widget<Opacity>(find.ancestor(of: scrim, matching: find.byType(Opacity)).first).opacity, 1);
      expect(tester.getRect(panel).bottom, 844);
      await away(tester);
    });

    // What the web page measured at 390 x 844 (Chromium, 2026-10-07) for a workspace's sheet opened from the home
    // page: the scrim the window, the panel's sides and foot the window's, 22px corners at its top, its grip band
    // 345.38 x 30.78 starting 9.93 under its top edge with a 44 x 4 bar in it.
    testWidgets('is the web page’s shell: the window’s width at its foot, the grip under its top edge', (tester) async {
      await pumpPage(tester, page(open: true, onClose: () {}));
      await settle(tester);
      final at = tester.getRect(panel);
      near(tester.getRect(scrim), [0, 0, 390, 844]);
      near(tester.getRect(grip), [22.31, at.top + 9.93, 345.38, 30.78], what: 'the grip');
      final bar = tester.getRect(find.descendant(of: grip, matching: find.byType(Container)));
      near(bar, [(390 - 44) / 2, at.top + 9.93 + 13.39, 44, 4], what: 'the bar');
      // `calc(var(--app-safe-bottom) + var(--glacier-space-5))` under the last block and its margin.
      final t = tester.element(panel).tokens;
      expect(844 - tester.getRect(find.byType(SheetGroup)).bottom, closeTo(t.space(3) + t.space(5), 0.05));
      await away(tester);
    });

    testWidgets('keeps the gesture bar’s height under its last block', (tester) async {
      await pumpPage(tester, page(open: true, onClose: () {}), bare: false);
      await settle(tester);
      final t = tester.element(panel).tokens;
      expect(t.len('app-safe-bottom'), 20);
      expect(844 - tester.getRect(find.byType(SheetGroup)).bottom, closeTo(t.space(3) + t.space(5) + 20, 0.05));
      await away(tester);
    });
  });

  group('closing', () {
    testWidgets('closes on a tap on the scrim, which the page under it does not get, and keeps its own taps', (tester) async {
      var closed = 0, under = 0, downs = 0, rows = 0;
      await pumpPage(
        tester,
        page(
          open: true,
          onClose: () => closed += 1,
          onUnder: () => under += 1,
          onScrimDown: (_) => downs += 1,
          children: [SheetTitle.text('A sheet'), SheetGroup(children: [SheetRow(label: 'One', onPress: () => rows += 1)])],
        ),
      );
      await settle(tester);
      // On the panel: a title is not a button, and the tap goes no further.
      await tester.tap(find.text('A sheet'));
      await tester.tap(find.text('One'));
      expect([closed, under, downs, rows], [0, 0, 0, 1]);
      await tester.tapAt(const Offset(60, 120));
      expect([closed, under, downs], [1, 0, 1]);
      await away(tester);
    });

    testWidgets('closes on the back gesture and on Escape, before whatever is under it', (tester) async {
      var closed = 0, screen = 0;
      await pumpPage(tester, OnBack(onBack: () => screen += 1, child: page(open: true, onClose: () => closed += 1)));
      await settle(tester);
      await tester.binding.handlePopRoute();
      expect([closed, screen], [1, 0]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect([closed, screen], [2, 0]);
      // Shut: the gesture is the screen's again.
      await pumpPage(tester, OnBack(onBack: () => screen += 1, child: page(open: false, onClose: () => closed += 1)));
      await tester.binding.handlePopRoute();
      expect([closed, screen], [2, 1]);
      await away(tester);
    });

    testWidgets('steps back through pages of its own where it has them', (tester) async {
      var closed = 0, back = 0;
      await pumpPage(tester, page(open: true, onClose: () => closed += 1, onBack: () => back += 1));
      await settle(tester);
      await tester.binding.handlePopRoute();
      expect([closed, back], [0, 1]);
      await away(tester);
    });
  });

  group('the handle', () {
    double pulled(WidgetTester tester) => tester.getRect(panel).bottom - 844;

    testWidgets('follows the finger down, and closes when let go past 96 px', (tester) async {
      var closed = 0;
      await pumpPage(tester, page(open: true, onClose: () => closed += 1));
      await settle(tester);
      final gesture = await tester.startGesture(tester.getCenter(grip));
      await gesture.moveBy(const Offset(0, 50), timeStamp: const Duration(milliseconds: 200));
      await tester.pump();
      expect(pulled(tester), closeTo(50, 0.01));
      await gesture.moveBy(const Offset(0, 50), timeStamp: const Duration(milliseconds: 400));
      await gesture.up(timeStamp: const Duration(milliseconds: 600));
      await tester.pump();
      expect(closed, 1);
      expect(pulled(tester), 0);
      await away(tester);
    });

    testWidgets('springs back when let go short of it, and gives a little when pulled up', (tester) async {
      var closed = 0;
      await pumpPage(tester, page(open: true, onClose: () => closed += 1));
      await settle(tester);
      final gesture = await tester.startGesture(tester.getCenter(grip));
      await gesture.moveBy(const Offset(0, -300), timeStamp: const Duration(milliseconds: 200));
      await tester.pump();
      expect(pulled(tester), lessThan(0));
      expect(pulled(tester), greaterThan(-28));
      await gesture.moveBy(const Offset(0, 360), timeStamp: const Duration(milliseconds: 600));
      await tester.pump();
      expect(pulled(tester), closeTo(60, 0.01));
      await gesture.up(timeStamp: const Duration(milliseconds: 1000));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      // On its way back: `transform 220ms cubic-bezier(0.2, 0.9, 0.3, 1)`.
      expect(pulled(tester), inExclusiveRange(0, 30));
      await tester.pump(const Duration(milliseconds: 120));
      expect(pulled(tester), 0);
      expect(closed, 0);
      await away(tester);
    });

    testWidgets('closes on a flick, and is not a second finger’s to pull', (tester) async {
      var closed = 0;
      await pumpPage(tester, page(open: true, onClose: () => closed += 1));
      await settle(tester);
      final first = await tester.startGesture(tester.getCenter(grip), pointer: 1);
      final second = await tester.startGesture(tester.getCenter(grip) + const Offset(40, 0), pointer: 2);
      await second.moveBy(const Offset(0, 200), timeStamp: const Duration(milliseconds: 100));
      await second.up(timeStamp: const Duration(milliseconds: 200));
      await tester.pump();
      expect([closed, pulled(tester)], [0, 0]);
      await first.moveBy(const Offset(0, 10), timeStamp: const Duration(milliseconds: 300));
      // Let go 30 px on, 20 ms later: 1.5 px/ms between the last movement and the release, as the page judges it.
      final from = tester.getCenter(grip);
      await tester.sendEventToBinding(PointerUpEvent(pointer: 1, position: from + const Offset(0, 40), timeStamp: const Duration(milliseconds: 320)));
      expect(closed, 1);
      await away(tester);
    });

    testWidgets('is the handle’s alone: a drag on it does not scroll what is in the sheet', (tester) async {
      await pumpPage(
        tester,
        page(open: true, onClose: () {}, children: [SheetTitle.text('A sheet'), for (var i = 0; i < 30; i++) SheetGroup(children: [SheetRow(label: 'Row $i', onPress: () {})])]),
      );
      await settle(tester);
      // Taller than `85dvh` allows: it scrolls inside.
      expect(tester.getRect(panel).height, closeTo(844 * 0.85, 0.01));
      final scroller = tester.state<ScrollableState>(find.descendant(of: panel, matching: find.byType(Scrollable)));
      await tester.drag(find.text('Row 5'), const Offset(0, -200));
      await tester.pump();
      final scrolled = scroller.position.pixels;
      expect(scrolled, greaterThan(100));
      await tester.drag(find.text('Row 5'), const Offset(0, 500));
      await tester.pump();
      expect(scroller.position.pixels, 0);
      final gesture = await tester.startGesture(tester.getCenter(grip));
      await gesture.moveBy(const Offset(0, -80), timeStamp: const Duration(milliseconds: 100));
      await tester.pump();
      expect(scroller.position.pixels, 0);
      await gesture.up(timeStamp: const Duration(milliseconds: 600));
      await settle(tester);
      await away(tester);
    });
  });

  group('over the keyboard', () {
    testWidgets('sits on the keyboard, and takes 85% of what the keyboard leaves at most', (tester) async {
      await pumpPage(
        tester,
        page(open: true, onClose: () {}, children: [SheetTitle.text('A sheet'), for (var i = 0; i < 30; i++) SheetGroup(children: [SheetRow(label: 'Row $i', onPress: () {})])]),
      );
      await settle(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 2);
      await tester.pump();
      final at = tester.getRect(panel);
      expect(at.bottom, 844 - 300);
      expect(at.height, closeTo((844 - 300) * 0.85, 0.01));
      await away(tester);
    });
  });

  group('on a desktop', () {
    // What the web page measured at 1280 x 800 (Chromium, 2026-10-07) for the new-workspace sheet: 544 wide (34rem),
    // centred, 26.34 of padding inside a 1px border, no grip.
    testWidgets('is a window in the middle of the screen, at a reading width, with no grip', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      var closed = 0;
      await pumpPage(tester, page(open: true, onClose: () => closed += 1), size: const Size(1280, 800));
      await settle(tester);
      final at = tester.getRect(panel);
      expect([at.left, at.width], [368, 544]);
      expect(at.center.dy, closeTo(400, 0.01));
      expect(grip, findsNothing);
      near(tester.getRect(find.text('A sheet')), [395.33, at.top + 27.33, 489.34, 26], what: 'the title');
      // A click outside closes it; one inside does not.
      await tester.tapAt(at.center);
      await tester.tapAt(const Offset(40, 400));
      expect(closed, 1);
      await away(tester);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('is never taller than 82% of the window, nor wider than the window less its margin', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await pumpPage(
        tester,
        page(open: true, onClose: () {}, children: [SheetTitle.text('A sheet'), for (var i = 0; i < 30; i++) SheetGroup(children: [SheetRow(label: 'Row $i', onPress: () {})])]),
        size: const Size(500, 600),
      );
      await settle(tester);
      final t = tester.element(panel).tokens;
      final at = tester.getRect(panel);
      expect(at.height, closeTo(600 * 0.82, 0.01));
      expect(at.width, closeTo(500 - 2 * t.space(6), 0.01));
      await away(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  for (final theme in ['light', 'dark']) {
    testWidgets('the picture: a sheet of rows, $theme', (tester) async {
      await pumpPage(
        tester,
        PageUnder(
          children: [
            Sheet(
              label: 'Reading it',
              onClose: () {},
              children: [
                SheetTitle.text('Reading it'),
                const SheetNote('How this note is shown. It changes nothing in the note itself.'),
                const SheetHeading('Look'),
                SheetGroup(
                  children: [
                    SheetRow(label: 'Plain', hint: 'The words as they are typed.', chosen: true, onPress: () {}),
                    SheetRow(label: 'Reading', hint: 'A page to read, with a title.', chosen: false, onPress: () {}),
                    const SheetRow(label: 'Map', hint: 'Needs a place in the note.'),
                  ],
                ),
                SheetGroup(
                  children: [
                    const SheetField(label: 'Called', value: 'Weekend trip'),
                    SheetRow(label: 'Rename', onPress: () {}, disabled: true),
                    SheetRow(label: 'Delete', danger: true, onPress: () {}),
                  ],
                ),
              ],
            ),
          ],
        ),
        theme: theme,
        bare: false,
      );
      await shot(tester, 'sheet-rows-$theme');
    });
  }
}
