// The app's one carry (lib/core/hold_drag.dart), driven by synthetic pointers: the cases of the web's
// book/rowDrag.test.tsx and editor/boards.test.ts ('dragging a card') that are the gesture's own, and the ones the
// arena adds here (a scroll before the hold, none after it).
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/hold_drag.dart';
import 'package:glacier/glacier.dart' show setHapticsEnabled;

/// What a gesture told its thing, in order.
class Heard {
  final List<String> said = <String>[];

  HoldDragHooks get hooks => HoldDragHooks(
    lift: (at) => said.add('lift ${at.dx.round()},${at.dy.round()}'),
    move: (at) => said.add('move ${at.dx.round()},${at.dy.round()}'),
    drop: (at) => said.add('drop ${at.dx.round()},${at.dy.round()}'),
    end: (lifted) => said.add('end $lifted'),
  );
}

/// A screen 400 x 600 with an overlay, as the app has one.
Future<void> pumpStage(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(400, 600)),
        child: Overlay(initialEntries: <OverlayEntry>[OverlayEntry(builder: (context) => child)]),
      ),
    ),
  );
}

/// A thing 100 x 40 at the top left that starts the gesture when pressed.
Widget thing(Heard heard, {Key? key}) => Align(
  alignment: Alignment.topLeft,
  child: Listener(
    onPointerDown: (event) => holdDrag(event, heard.hooks),
    child: SizedBox(key: key, width: 100, height: 40, child: const ColoredBox(color: Color(0xff808080))),
  ),
);

const Duration held = Duration(milliseconds: 230);

void main() {
  group('press and hold', () {
    testWidgets('lifts after the hold under a mouse, is carried, and lands where it is let go', (tester) async {
      final heard = Heard();
      await pumpStage(tester, thing(heard));
      final mouse = await tester.startGesture(const Offset(20, 20), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 200));
      expect(heard.said, isEmpty, reason: 'not before the hold is up');
      await tester.pump(const Duration(milliseconds: 30));
      expect(heard.said, <String>['lift 20,20']);
      await mouse.moveTo(const Offset(60, 110));
      await mouse.up();
      await tester.pump();
      expect(heard.said, <String>['lift 20,20', 'move 60,110', 'drop 60,110', 'end true']);
    });

    testWidgets('is not started by a mouse\'s other buttons', (tester) async {
      final heard = Heard();
      await pumpStage(tester, thing(heard));
      final mouse = await tester.startGesture(const Offset(20, 20), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pump(held);
      await mouse.up();
      expect(heard.said, isEmpty);
    });

    testWidgets('under a finger, lifts only after the hold, and a move before it is a scroll', (tester) async {
      final heard = Heard();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpStage(
        tester,
        SingleChildScrollView(
          controller: scroll,
          child: Column(children: <Widget>[thing(heard), const SizedBox(height: 2000)]),
        ),
      );
      final finger = await tester.startGesture(const Offset(20, 30));
      await finger.moveBy(const Offset(0, -30));
      await finger.moveBy(const Offset(0, -30));
      await tester.pump(held);
      expect(heard.said, <String>['end false'], reason: 'moved before the hold: left alone');
      expect(scroll.offset, greaterThan(0), reason: 'and the page scrolled under the finger');
      await finger.up();
      await tester.pumpAndSettle();
      expect(heard.said, <String>['end false']);
    });

    testWidgets('lifted, the finger is the drag\'s: nothing scrolls under it', (tester) async {
      final heard = Heard();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpStage(
        tester,
        SingleChildScrollView(
          controller: scroll,
          child: Column(children: <Widget>[thing(heard), const SizedBox(height: 2000)]),
        ),
      );
      final finger = await tester.startGesture(const Offset(20, 20));
      await tester.pump(held);
      await finger.moveBy(const Offset(0, 100));
      await finger.moveBy(const Offset(0, -150));
      await tester.pump();
      expect(scroll.offset, 0);
      await finger.up();
      await tester.pump();
      expect(heard.said, <String>['lift 20,20', 'move 20,120', 'move 20,-30', 'drop 20,-30', 'end true']);
    });

    testWidgets('a tap\'s recognizer on the thing loses to the lift, and wins a quick tap', (tester) async {
      final heard = Heard();
      var taps = 0;
      await pumpStage(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: Listener(
            onPointerDown: (event) => holdDrag(event, heard.hooks),
            child: GestureDetector(onTap: () => taps += 1, child: const SizedBox(width: 100, height: 40, child: ColoredBox(color: Color(0xff808080)))),
          ),
        ),
      );
      await tester.tap(find.byType(ColoredBox));
      await tester.pump();
      expect(taps, 1);
      expect(heard.said, <String>['end false'], reason: 'let go before the hold: never lifted');
      heard.said.clear();
      final finger = await tester.startGesture(const Offset(20, 20));
      await tester.pump(held);
      await finger.up();
      await tester.pump();
      expect(taps, 1, reason: 'a held press is the carry, not a tap');
      expect(heard.said, <String>['lift 20,20', 'drop 20,20', 'end true']);
    });

    testWidgets('ends when the cancel arrives, with nothing dropped', (tester) async {
      final heard = Heard();
      await pumpStage(tester, thing(heard));
      final finger = await tester.startGesture(const Offset(20, 20));
      await tester.pump(held);
      await finger.moveTo(const Offset(200, 300));
      await finger.cancel();
      await tester.pump();
      expect(heard.said, <String>['lift 20,20', 'move 200,300', 'end true']);
    });

    testWidgets('pays no mind to another finger', (tester) async {
      final heard = Heard();
      await pumpStage(tester, thing(heard));
      final finger = await tester.startGesture(const Offset(20, 20), pointer: 7);
      await tester.pump(held);
      final other = await tester.startGesture(const Offset(300, 400), pointer: 8);
      await other.moveTo(const Offset(320, 300));
      await other.up();
      await tester.pump();
      expect(heard.said, <String>['lift 20,20'], reason: 'still held');
      await finger.moveTo(const Offset(40, 60));
      await finger.up();
      await tester.pump();
      expect(heard.said, <String>['lift 20,20', 'move 40,60', 'drop 40,60', 'end true']);
    });

    testWidgets('is not picked up by a finger that lets go, or moves away, before the hold is up', (tester) async {
      final heard = Heard();
      await pumpStage(tester, thing(heard));
      var finger = await tester.startGesture(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 100));
      await finger.up();
      await tester.pump(held);
      expect(heard.said, <String>['end false']);
      heard.said.clear();
      finger = await tester.startGesture(const Offset(20, 20));
      // Within the slop: still resting.
      await finger.moveBy(const Offset(6, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(heard.said, isEmpty);
      await finger.moveBy(const Offset(6, 0));
      expect(heard.said, <String>['end false']);
      await tester.pump(held);
      await finger.up();
      expect(heard.said, <String>['end false']);
    });

    testWidgets('can be given up early, before the lift or after it', (tester) async {
      final heard = Heard();
      late VoidCallback giveUp;
      await pumpStage(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: Listener(
            onPointerDown: (event) => giveUp = holdDrag(event, heard.hooks),
            child: const SizedBox(width: 100, height: 40, child: ColoredBox(color: Color(0xff808080))),
          ),
        ),
      );
      var finger = await tester.startGesture(const Offset(20, 20));
      giveUp();
      await tester.pump(held);
      await finger.up();
      expect(heard.said, <String>['end false']);
      heard.said.clear();
      finger = await tester.startGesture(const Offset(20, 20));
      await tester.pump(held);
      giveUp();
      giveUp();
      await finger.moveBy(const Offset(0, 50));
      await finger.up();
      await tester.pump();
      expect(heard.said, <String>['lift 20,20', 'end true']);
    });

    testWidgets('ticks the phone as the thing lifts', (tester) async {
      final buzzed = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') buzzed.add('${call.arguments}');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      setHapticsEnabled(true);
      addTearDown(() => setHapticsEnabled(false));
      final heard = Heard();
      await pumpStage(tester, thing(heard));
      final finger = await tester.startGesture(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 100));
      expect(buzzed, isEmpty);
      await tester.pump(held);
      expect(buzzed, <String>['HapticFeedbackType.selectionClick']);
      await finger.up();
      await tester.pump();
    });
  });

  group('the copy in the air', () {
    testWidgets('is drawn over the page at the thing\'s own place and width, and follows by the spot it was taken by', (tester) async {
      final key = GlobalKey();
      Ghost? ghost;
      await pumpStage(tester, Padding(padding: const EdgeInsets.only(left: 30, top: 50), child: Align(alignment: Alignment.topLeft, child: SizedBox(key: key, width: 120, height: 40))));
      final context = key.currentContext!;
      ghost = liftGhost(context, box: const Rect.fromLTWH(30, 50, 120, 40), at: const Offset(50, 60), builder: (_) => const SizedBox(key: ValueKey<String>('copy'), height: 40));
      await tester.pump();
      final copy = find.byKey(const ValueKey<String>('copy'));
      expect(tester.getRect(copy), const Rect.fromLTWH(30, 50, 120, 40));
      ghost!.follow(const Offset(200, 300));
      await tester.pump();
      expect(tester.getRect(copy), const Rect.fromLTWH(180, 290, 120, 40));
      // Nothing under it is kept from the pointer.
      expect(tester.hitTestOnBinding(const Offset(200, 300)).path.any((entry) => entry.target == tester.renderObject(copy)), isFalse);
      ghost.remove();
      ghost.remove();
      await tester.pump();
      expect(copy, findsNothing);
    });
  });

  group('rolling at an edge', () {
    Future<(ScrollController, EdgeRoller, List<int>)> stage(WidgetTester tester, Axis axis) async {
      final scroll = ScrollController(initialScrollOffset: 100);
      addTearDown(scroll.dispose);
      await pumpStage(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 400,
            child: SingleChildScrollView(controller: scroll, scrollDirection: axis, child: SizedBox(width: axis == Axis.horizontal ? 1000 : 300, height: axis == Axis.vertical ? 1000 : 400)),
          ),
        ),
      );
      final rolls = <int>[];
      final roller = EdgeRoller(
        CarryScroller(position: scroll.position, axis: axis, box: () => const Rect.fromLTWH(0, 0, 300, 400)),
        onRoll: () => rolls.add(scroll.offset.round()),
        window: () => 600,
      );
      addTearDown(roller.stop);
      return (scroll, roller, rolls);
    }

    testWidgets('rolls a step a frame while the pointer is near the end, and stops when it leaves', (tester) async {
      final (scroll, roller, rolls) = await stage(tester, Axis.horizontal);
      roller.at(const Offset(150, 200));
      await tester.pump(const Duration(milliseconds: 16));
      expect(scroll.offset, 100, reason: 'in the middle: nothing rolls');
      roller.at(const Offset(280, 200));
      expect(roller.lean, rollStep);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(scroll.offset, 100 + 2 * rollStep);
      expect(rolls, <int>[114, 128]);
      roller.at(const Offset(20, 200));
      expect(roller.lean, -rollStep);
      await tester.pump(const Duration(milliseconds: 16));
      expect(scroll.offset, 100 + rollStep);
      roller.at(const Offset(150, 200));
      await tester.pump(const Duration(milliseconds: 16));
      expect(scroll.offset, 100 + rollStep);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('only the scroller the pointer is over rolls, and never past its ends', (tester) async {
      final (scroll, roller, _) = await stage(tester, Axis.vertical);
      // Beside it: a lane next to the one held near its foot stays where it is.
      roller.at(const Offset(350, 390));
      expect(roller.lean, 0);
      roller.at(const Offset(150, 390));
      expect(roller.lean, rollStep);
      for (var i = 0; i < 60; i += 1) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scroll.offset, scroll.position.maxScrollExtent);
      // At the end, the next move finds nothing left to roll.
      roller.at(const Offset(150, 391));
      expect(roller.lean, 0);
      scroll.jumpTo(0);
      roller.at(const Offset(150, 10));
      expect(roller.lean, 0, reason: 'at the top already');
    });

    testWidgets('keeps a wider zone under a header for a page', (tester) async {
      final scroll = ScrollController(initialScrollOffset: 100);
      addTearDown(scroll.dispose);
      await pumpStage(tester, SingleChildScrollView(controller: scroll, child: const SizedBox(height: 3000)));
      final roller = EdgeRoller(CarryScroller(position: scroll.position, axis: Axis.vertical, box: () => const Rect.fromLTWH(0, 0, 400, 900), zone: rollEdge * 2, under: 60), window: () => 600);
      addTearDown(roller.stop);
      roller.at(const Offset(100, 60 + 80));
      expect(roller.lean, -rollStep);
      roller.at(const Offset(100, 60 + 90));
      expect(roller.lean, 0);
      // The foot is the window's, not the box's.
      roller.at(const Offset(100, 600 - 80));
      expect(roller.lean, rollStep);
      roller.at(const Offset(100, 600 - 90));
      expect(roller.lean, 0);
    });
  });

  group('a thing carried in a list', () {
    /// Three rows of 40 in lane 'a' at the left, and lane 'b' at the right; a spot is the lane and the row under
    /// the pointer.
    Future<(Carry<String>, List<String>)> list(WidgetTester tester, {List<CarryScroller> Function(Offset at)? scrollers}) async {
      final dropped = <String>[];
      final carry = Carry<String>(
        spotAt: (at) => at.dy > 500 ? null : Spot(at.dx < 200 ? 'a' : 'b', (at.dy ~/ 40).clamp(0, 2)),
        onDrop: (item, from, to) => dropped.add('$item $from -> $to'),
        scrollers: scrollers,
      );
      addTearDown(carry.dispose);
      await pumpStage(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final (index, name) in <String>['one', 'two', 'three'].indexed)
                Builder(
                  builder: (context) => Listener(
                    onPointerDown: (event) => carry.press(event, context, name, Spot('a', index), ghost: (_) => SizedBox(key: ValueKey<String>('ghost $name'), height: 40)),
                    child: SizedBox(key: ValueKey<String>(name), width: 150, height: 40, child: const ColoredBox(color: Color(0xff808080))),
                  ),
                ),
            ],
          ),
        ),
      );
      return (carry, dropped);
    }

    testWidgets('holds what is carried and where it would land, and reports the drop', (tester) async {
      final (carry, dropped) = await list(tester);
      var told = 0;
      carry.addListener(() => told += 1);
      final finger = await tester.startGesture(const Offset(20, 50));
      await tester.pump(const Duration(milliseconds: 100));
      expect(carry.carried, isNull);
      await tester.pump(held);
      expect(carry.carried!.item, 'two');
      expect(carry.carried!.from, const Spot('a', 1));
      expect(carry.carried!.size, const Size(150, 40));
      expect(carry.over, const Spot('a', 1));
      expect(told, 1);
      // The copy is the thing, where the thing is.
      expect(tester.getRect(find.byKey(const ValueKey<String>('ghost two'))), const Rect.fromLTWH(0, 40, 150, 40));
      await finger.moveTo(const Offset(260, 90));
      await tester.pump();
      expect(carry.over, const Spot('b', 2));
      expect(told, 2);
      expect(tester.getRect(find.byKey(const ValueKey<String>('ghost two'))), const Rect.fromLTWH(240, 80, 150, 40));
      // Over nothing that would take it: it keeps the last place.
      await finger.moveTo(const Offset(260, 550));
      expect(carry.over, const Spot('b', 2));
      expect(told, 2);
      await finger.up();
      await tester.pump();
      expect(dropped, <String>['two Spot(a, 1) -> Spot(b, 2)']);
      expect(carry.carried, isNull);
      expect(carry.over, isNull);
      expect(find.byKey(const ValueKey<String>('ghost two')), findsNothing);
    });

    testWidgets('reports nothing for a thing put back where it came from, or called off', (tester) async {
      final (carry, dropped) = await list(tester);
      var finger = await tester.startGesture(const Offset(20, 10));
      await tester.pump(held);
      await finger.moveTo(const Offset(20, 100));
      await finger.moveTo(const Offset(30, 15));
      await finger.up();
      await tester.pump();
      expect(dropped, isEmpty);
      finger = await tester.startGesture(const Offset(20, 10));
      await tester.pump(held);
      await finger.moveTo(const Offset(260, 100));
      expect(carry.over, const Spot('b', 2));
      await finger.cancel();
      await tester.pump();
      expect(dropped, isEmpty);
      expect(carry.carried, isNull);
      expect(find.byKey(const ValueKey<String>('ghost one')), findsNothing);
    });

    testWidgets('carries one thing at a time', (tester) async {
      final (carry, dropped) = await list(tester);
      final finger = await tester.startGesture(const Offset(20, 10), pointer: 3);
      await tester.pump(held);
      final other = await tester.startGesture(const Offset(20, 90), pointer: 4);
      await tester.pump(held);
      expect(carry.carried!.item, 'one');
      await other.up();
      await finger.moveTo(const Offset(260, 50));
      await finger.up();
      await tester.pump();
      expect(dropped, <String>['one Spot(a, 0) -> Spot(b, 1)']);
    });

    testWidgets('is given up, and its copy taken away, when the list goes in the middle of one', (tester) async {
      final (carry, dropped) = await list(tester);
      final finger = await tester.startGesture(const Offset(20, 10));
      await tester.pump(held);
      expect(find.byKey(const ValueKey<String>('ghost one')), findsOneWidget);
      carry.abandon();
      await tester.pump();
      expect(carry.carried, isNull);
      expect(find.byKey(const ValueKey<String>('ghost one')), findsNothing);
      await finger.moveTo(const Offset(260, 50));
      await finger.up();
      await tester.pump();
      expect(dropped, isEmpty);
    });

    testWidgets('rolls what it is told to at the edges, and places the gap again as it rolls', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      // A scroller that is not on the page at all stands in for the list's: only its position is rolled.
      late Carry<String> carry;
      final spots = <int>[];
      carry = Carry<String>(
        spotAt: (at) {
          spots.add(scroll.offset.round());
          return Spot('a', (scroll.offset ~/ 14).toInt());
        },
        onDrop: (_, _, _) {},
        scrollers: (at) => <CarryScroller>[CarryScroller(position: scroll.position, axis: Axis.vertical, box: () => const Rect.fromLTWH(0, 0, 400, 600))],
        window: () => 600,
      );
      addTearDown(carry.dispose);
      await pumpStage(
        tester,
        Stack(
          children: <Widget>[
            SingleChildScrollView(controller: scroll, child: const SizedBox(height: 3000)),
            Align(
              alignment: Alignment.topLeft,
              child: Builder(
                builder: (context) => Listener(
                  onPointerDown: (event) => carry.press(event, context, 'x', const Spot('a', 0), ghost: (_) => const SizedBox(height: 40)),
                  child: const SizedBox(width: 150, height: 40, child: ColoredBox(color: Color(0xff808080))),
                ),
              ),
            ),
          ],
        ),
      );
      final finger = await tester.startGesture(const Offset(20, 20));
      await tester.pump(held);
      await finger.moveTo(const Offset(20, 580));
      spots.clear();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(scroll.offset, 3 * rollStep);
      expect(spots, <int>[14, 28, 42], reason: 'placed again under a finger that is still');
      expect(carry.over, const Spot('a', 3));
      await finger.up();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(scroll.offset, 3 * rollStep, reason: 'let go: nothing rolls on');
    });
  });
}
