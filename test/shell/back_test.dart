import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

/// `core/back.test.ts`, case for case, and the stack behind Android's own back: what the activity asked the page on
/// the web, the route asks here.
void main() {
  group('the back gesture', () {
    test('gives the gesture to the newest screen that wants it', () {
      final stack = BackStack();
      final taken = <String>[];
      final offList = stack.onBack(() {
        taken.add('list');
        return false;
      });
      final offNote = stack.onBack(() {
        taken.add('note');
        return true;
      });
      expect(stack.goBack(), isTrue);
      expect(taken, ['note']);
      offNote();
      expect(stack.goBack(), isFalse);
      expect(taken, ['note', 'list']);
      offList();
      expect(stack.depth, 0);
    });

    test('always tells the system the app used it, so a back swipe never leaves the app', () {
      final stack = BackStack();
      // Nothing on screen: the gesture still counts as used.
      expect(stack.tookBack(), isTrue);
      final off = stack.onBack(() => true);
      expect(stack.tookBack(), isTrue);
      off();
    });

    test('steps back once for a swipe the app already used', () {
      var now = 1000;
      final stack = BackStack(now: () => now);
      var steps = 0;
      stack.onBack(() {
        steps += 1;
        return true;
      });
      // The app's own right-swipe closed a screen; Android offers the same swipe a moment later.
      stack.markSteppedBack();
      now += 100;
      expect(stack.tookBack(), isTrue);
      expect(steps, 0);
      // Half a second on it is another gesture.
      now += BackStack.sameSwipeMs;
      expect(stack.tookBack(), isTrue);
      expect(steps, 1);
    });

    test('says when a handler comes or goes, and an unregister run twice takes nothing else off', () {
      final stack = BackStack();
      var told = 0;
      stack.addListener(() => told += 1);
      final off = stack.onBack(() => true);
      final other = stack.onBack(() => true);
      expect(told, 2);
      off();
      off();
      expect(told, 3);
      expect(stack.depth, 1);
      other();
    });
  });

  group('the system’s back, through the route', () {
    setUpAll(loadAppFonts);

    Future<void> away(WidgetTester tester) async {
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('closes the newest thing open, then the screen under it, and never leaves the app', (tester) async {
      final stack = BackStack();
      final closed = <String>[];
      var sheet = true;
      late StateSetter redraw;
      await pumpApp(
        tester,
        home: BackScope(
          stack: stack,
          child: StatefulBuilder(
            builder: (context, setState) {
              redraw = setState;
              return OnBack(
                onBack: () => closed.add('note'),
                child: OnBack(active: sheet, onBack: () => closed.add('sheet'), child: const SizedBox.expand()),
              );
            },
          ),
        ),
      );
      expect(stack.depth, 2);
      expect(await tester.binding.handlePopRoute(), isTrue);
      expect(closed, ['sheet']);
      // The sheet is taken down: its handler goes with it.
      redraw(() => sheet = false);
      await tester.pump();
      expect(stack.depth, 1);
      expect(await tester.binding.handlePopRoute(), isTrue);
      expect(closed, ['sheet', 'note']);
      await away(tester);
      expect(stack.depth, 0);
    });

    testWidgets('uses the gesture with nothing open, as the web app does, unless told the app may be left', (tester) async {
      final stack = BackStack();
      await pumpApp(tester, home: BackScope(stack: stack, child: const SizedBox.expand()));
      expect(await tester.binding.handlePopRoute(), isTrue);
      // The app may be left: the system takes a gesture the stack has nothing for.
      await pumpApp(tester, home: BackScope(stack: stack, leavesAtRoot: true, child: const SizedBox.expand()));
      await tester.pump();
      expect(await tester.binding.handlePopRoute(), isFalse);
      // And not while something is up to close.
      var closed = 0;
      final off = stack.onBack(() {
        closed += 1;
        return true;
      });
      await tester.pump();
      expect(await tester.binding.handlePopRoute(), isTrue);
      expect(closed, 1);
      off();
      await away(tester);
    });

    testWidgets('leaves a gesture to the kit’s own menu while one is open, and steps back only once it has closed', (tester) async {
      final stack = BackStack();
      var steps = 0;
      var open = true;
      late StateSetter redraw;
      await pumpApp(
        tester,
        home: BackScope(
          stack: stack,
          child: OnBack(
            onBack: () => steps += 1,
            child: StatefulBuilder(
              builder: (context, setState) {
                redraw = setState;
                return Align(
                  alignment: Alignment.topLeft,
                  child: GlacierMenu(
                    open: open,
                    onOpenChange: (next) => redraw(() => open = next),
                    trigger: (context, trigger) => const SizedBox(width: 40, height: 40),
                    children: [GlacierMenuItem(onSelect: () {}, child: const Text('Rename'))],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Rename'), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      expect(open, isFalse);
      // The menu had the gesture: the screen under it stayed.
      expect(steps, 0);
      await tester.pump(const Duration(milliseconds: 400));
      expect(await tester.binding.handlePopRoute(), isTrue);
      expect(steps, 1);
      await away(tester);
    });

    testWidgets('answers Escape from the same stack, and leaves a key nothing took to whatever else is listening', (tester) async {
      final stack = BackStack();
      await pumpApp(tester, home: BackScope(stack: stack, child: const SizedBox.expand()));
      // Nothing on screen to close: the key is not claimed, unlike the system's gesture.
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isFalse);
      var closed = 0;
      final off = stack.onBack(() {
        closed += 1;
        return true;
      });
      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.escape), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      expect(closed, 1);
      off();
      await away(tester);
      // Taken down, it listens no more.
      stack.onBack(() {
        closed += 1;
        return true;
      });
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isFalse);
      expect(closed, 1);
    });

    testWidgets('hands a screen the app’s own stack where no scope brings another', (tester) async {
      var closed = 0;
      await pumpApp(tester, home: OnBack(onBack: () => closed += 1, child: const SizedBox.expand()));
      expect(backStack.depth, 1);
      expect(backStack.goBack(), isTrue);
      expect(closed, 1);
      await away(tester);
      expect(backStack.depth, 0);
    });
  });
}
