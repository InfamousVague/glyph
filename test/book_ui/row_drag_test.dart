import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/row_drag.dart';
import 'package:glacier/glacier.dart' show setHapticsEnabled;

/// Rows dragged by their grip, by the app's one drag (lib/core/hold_drag.dart): a mouse and a finger both lift after
/// a hold - and one that moves before the hold is scrolling, not dragging. The row's new place comes back on
/// release, and only when it changed. The web's `book/rowDrag.test.tsx`, case for case; its last case's refusals
/// (`contextmenu`, `selectstart`) are the gesture arena's here, so it is told with a long press under the grip.

const List<String> names = ['a', 'b', 'c', 'd'];

/// Four rows, each 40px tall, one under another from the top of the page, in a page that scrolls.
class Rows extends StatefulWidget {
  const Rows({super.key, required this.onMove, this.onLongPress});
  final void Function(int from, int to) onMove;
  final VoidCallback? onLongPress;

  @override
  State<Rows> createState() => RowsState();
}

class RowsState extends State<Rows> {
  late final RowDrag drag = RowDrag((from, to) => widget.onMove(from, to));

  @override
  void dispose() {
    drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: GestureDetector(
          onLongPress: widget.onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, name) in names.indexed)
                DragRow(
                  drag: drag,
                  index: i,
                  child: SizedBox(
                    width: 300,
                    height: 40,
                    child: Row(
                      children: [
                        Listener(
                          key: ValueKey('grip-$name'),
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (event) => drag.press(event, i, names.length, ghost: (context) => SizedBox(key: const ValueKey('ghost'), height: 40, child: Text(name))),
                          child: const SizedBox(width: 40, height: 40),
                        ),
                        Text(name),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      );
}

Future<RowDrag> showRows(WidgetTester tester, void Function(int from, int to) onMove, {VoidCallback? onLongPress}) async {
  setHapticsEnabled(false);
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(400, 600)),
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xff000000), fontSize: 14),
          child: Overlay(initialEntries: [OverlayEntry(builder: (context) => Rows(onMove: onMove, onLongPress: onLongPress))]),
        ),
      ),
    ),
  );
  return tester.state<RowsState>(find.byType(Rows)).drag;
}

const Duration held = Duration(milliseconds: 230);
Offset grip(int row) => Offset(20, row * 40 + 20);

/// A grip pressed and held while the row lifts (`holdGrip`).
Future<TestGesture> holdGrip(WidgetTester tester, int row, {PointerDeviceKind kind = PointerDeviceKind.mouse}) async {
  final pointer = await tester.startGesture(grip(row), kind: kind);
  await tester.pump(held);
  return pointer;
}

void main() {
  group('rows dragged by their grip', () {
    testWidgets('lifts after a hold under a mouse, a copy follows it, and it lands where it is let go', (tester) async {
      final moves = <(int, int)>[];
      final drag = await showRows(tester, (from, to) => moves.add((from, to)));
      final tap = await tester.startGesture(grip(0), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(drag.lifted, isNull);
      await tap.up();
      await tester.pump();
      final mouse = await holdGrip(tester, 0);
      expect(drag.lifted, 0);
      // The copy in the air is the row's own, outside the list.
      expect(find.byKey(const ValueKey('ghost')), findsOneWidget);
      await mouse.moveTo(const Offset(20, 110));
      await tester.pump();
      // The gap stands where the row would land: two rows down.
      expect(drag.shiftOf(0), 80);
      expect(tester.getTopLeft(find.byKey(const ValueKey('ghost'))).dy, 90);
      await mouse.up();
      await tester.pump();
      expect(moves, [(0, 2)]);
      expect(drag.lifted, isNull);
      expect(find.byKey(const ValueKey('ghost')), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('under a finger, lifts only after the hold, and a move before it is a scroll', (tester) async {
      final moves = <(int, int)>[];
      final drag = await showRows(tester, (from, to) => moves.add((from, to)));
      final scrolling = await tester.startGesture(grip(1));
      await tester.pump();
      expect(drag.lifted, isNull);
      await scrolling.moveTo(const Offset(20, 30));
      await tester.pump(held);
      expect(drag.lifted, isNull);
      await scrolling.up();
      await tester.pumpAndSettle();
      expect(moves, isEmpty);
      // The page went with the finger; put back for the second press.
      tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(0);
      await tester.pump();

      final finger = await holdGrip(tester, 1, kind: PointerDeviceKind.touch);
      expect(drag.lifted, 1);
      await finger.moveTo(const Offset(20, 10));
      await finger.up();
      await tester.pump();
      expect(moves, [(1, 0)]);
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('says nothing when a row is let go where it was', (tester) async {
      final moves = <(int, int)>[];
      await showRows(tester, (from, to) => moves.add((from, to)));
      final mouse = await holdGrip(tester, 2);
      await mouse.moveTo(const Offset(20, 104));
      await mouse.up();
      await tester.pump();
      expect(moves, isEmpty);
    });

    testWidgets('makes room as a row goes by: the rows it passes move a row the other way', (tester) async {
      final moves = <(int, int)>[];
      final drag = await showRows(tester, (from, to) => moves.add((from, to)));
      // Down: a's middle (20) moved 130px is 150, past the middles of b, c and d, which each move up a row.
      var mouse = await holdGrip(tester, 0);
      await mouse.moveTo(const Offset(20, 150));
      await tester.pump();
      expect([for (final row in [1, 2, 3]) drag.shiftOf(row)], [-40, -40, -40]);
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getTopLeft(find.byKey(const ValueKey('grip-b'))).dy, 0);
      await mouse.up();
      await tester.pump();
      expect(moves.last, (0, 3));
      await tester.pump(const Duration(milliseconds: 150));
      // Up: d's middle (140) moved 130px is 10, above the middles of a, b and c, which each move down a row.
      mouse = await holdGrip(tester, 3);
      await mouse.moveTo(const Offset(20, 10));
      await tester.pump();
      expect([for (final row in [0, 1, 2]) drag.shiftOf(row)], [40, 40, 40]);
      await mouse.up();
      await tester.pump();
      expect(moves.last, (3, 0));
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('lands past the last row as the last, and a cancelled drag moves nothing', (tester) async {
      final moves = <(int, int)>[];
      final drag = await showRows(tester, (from, to) => moves.add((from, to)));
      var mouse = await holdGrip(tester, 1);
      await mouse.moveTo(const Offset(20, 590));
      await mouse.up();
      await tester.pump();
      expect(moves, [(1, 3)]);
      moves.clear();
      await tester.pump(const Duration(milliseconds: 150));
      mouse = await holdGrip(tester, 1);
      await mouse.moveTo(const Offset(20, 590));
      await mouse.cancel();
      await tester.pump();
      expect(moves, isEmpty);
      expect(drag.lifted, isNull);
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('keeps a held row up through the phone’s long press: no menu, no cancel', (tester) async {
      final moves = <(int, int)>[];
      var menus = 0;
      final drag = await showRows(tester, (from, to) => moves.add((from, to)), onLongPress: () => menus += 1);
      final finger = await holdGrip(tester, 0, kind: PointerDeviceKind.touch);
      expect(drag.lifted, 0);
      // Half a second on, the phone's long press: the menu it would raise is refused.
      await tester.pump(const Duration(milliseconds: 400));
      expect(menus, 0);
      expect(drag.lifted, 0);
      await finger.moveTo(const Offset(20, 110));
      await finger.up();
      await tester.pump();
      expect(moves, [(0, 2)]);
      await tester.pump(const Duration(milliseconds: 150));
      // Put down, the page has its long press back.
      await tester.longPressAt(const Offset(44, 100));
      await tester.pump();
      expect(menus, 1);
    });

    testWidgets('gives up a drag in flight when its list is taken off the page', (tester) async {
      final moves = <(int, int)>[];
      await showRows(tester, (from, to) => moves.add((from, to)));
      final mouse = await holdGrip(tester, 0);
      await mouse.moveTo(const Offset(20, 110));
      await tester.pumpWidget(const SizedBox.shrink());
      await mouse.up();
      await tester.pump();
      expect(moves, isEmpty);
    });
  });
}
