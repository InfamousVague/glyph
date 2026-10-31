import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/gantt/gantt.dart';
import 'package:ghost_md/editor/editor.dart' show redoNote, undoNote;
import 'package:ghost_md/editor/gantt/gantt.dart';

import '../support/render.dart';
import 'support.dart';

/// The chart a ```gantt fence draws (lib/editor/gantt), by hand: each gesture, on a Mac's width with a mouse and a
/// keyboard and on a phone's with a finger, and the exact lines of the fence it writes; what waits pushed along; a
/// loop refused; undo and redo through the note's own.
const String fence = '''title: Launch
today: 2026-11-04
## Build
- Design [2026-11-02 → 2026-11-04] @matt 50%
- Build [2026-11-05 +3d] after: Design
- ◆ Ship [2026-11-12] after: Build
## Later
- Tell the press [2026-11-16]''';

const String doc = '# Plan\n\n```gantt\n$fence\n```\n\nAfter.\n';

/// The fence's lines as the note has them now.
List<String> lines(dynamic view) => fenceBody(view).split('\n');

Future<void> mouseDrag(WidgetTester tester, Offset from, Offset by) async {
  final mouse = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await tester.pump();
  await mouse.moveBy(by / 2);
  await tester.pump();
  await mouse.moveBy(by / 2);
  await tester.pump();
  await mouse.up();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> click(WidgetTester tester, Offset at) async {
  final mouse = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
  await tester.pump();
  await mouse.up();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(loadAppFonts);

  group('on a Mac, with a mouse', () {
    testWidgets('a bar carried writes its days alone, pushes what waits along, and undoes as one step', (tester) async {
      final view = await pumpGantt(tester, doc, screen: 1100);
      final wide = ganttChart(tester).dayWide;
      await mouseDrag(tester, barAt(tester, 'L3'), Offset(2 * wide, 0));
      expect(lines(view)[3], '- Design [2026-11-04 → 2026-11-06] @matt 50%');
      expect(lines(view)[4], '- Build [2026-11-07 +3d] after: Design', reason: 'pushed along to start after Design');
      expect(lines(view)[5], '- ◆ Ship [2026-11-12] after: Build', reason: 'Build still ends before it');
      expect(view.state.doc.toString(), contains('# Plan\n\n```gantt\ntitle: Launch'), reason: 'nothing else in the note moved');
      undoNote(view);
      await tester.pump();
      expect(fenceBody(view), fence, reason: 'one gesture, one undo');
      redoNote(view);
      await tester.pump();
      expect(lines(view)[3], '- Design [2026-11-04 → 2026-11-06] @matt 50%');
    });

    testWidgets('its ends make it longer or shorter, a length staying a length', (tester) async {
      final view = await pumpGantt(tester, doc, screen: 1100);
      final wide = ganttChart(tester).dayWide;
      await mouseDrag(tester, barAt(tester, 'L4', where: 'end'), Offset(2 * wide, 0));
      expect(lines(view)[4], '- Build [2026-11-05 +5d] after: Design');
      await mouseDrag(tester, barAt(tester, 'L3', where: 'start'), Offset(-wide, 0));
      expect(lines(view)[3], '- Design [2026-11-01 → 2026-11-04] @matt 50%');
    });

    testWidgets('a wait drawn from a bar’s round to another, a loop refused, and an arrow clicked away', (tester) async {
      final view = await pumpGantt(tester, doc, screen: 1100);
      // Hovered, Tell the press shows its round; dragged to Design, Design waits on it and is pushed after it.
      final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await hover.addPointer(location: barAt(tester, 'L7'));
      await hover.moveTo(barAt(tester, 'L7'));
      await tester.pump();
      await mouseDrag(tester, barAt(tester, 'L7', where: 'knob'), barAt(tester, 'L3') - barAt(tester, 'L7', where: 'knob'));
      expect(lines(view)[3], '- Design [2026-11-17 → 2026-11-19] @matt after: Tell the press 50%');
      undoNote(view);
      await tester.pump();
      // Ship waits on Build, which waits on Design: Design cannot wait on Ship.
      await hover.moveTo(barAt(tester, 'L5'));
      await tester.pump();
      await mouseDrag(tester, barAt(tester, 'L5', where: 'knob'), barAt(tester, 'L3') - barAt(tester, 'L5', where: 'knob'));
      expect(fenceBody(view), fence);
      expect(find.text('That would make a loop: “Ship” already waits on “Design”.'), findsOneWidget);
      await hover.removePointer();
      // The arrow from Design to Build, clicked on its upright, is taken away.
      final state = ganttChart(tester);
      final arrow = state.arrows(state.frame, state.rows).firstWhere((each) => each.to == 'L4');
      final origin = tester.getTopLeft(find.byKey(const ValueKey<String>('gantt-days')));
      await click(tester, origin + Offset.lerp(arrow.points[1], arrow.points[2], 0.5)!);
      expect(lines(view)[4], '- Build [2026-11-05 +3d]');
      expect(find.text('“Build” no longer waits on “Design”.'), findsOneWidget);
    });

    testWidgets('a double-click in a row’s empty days adds a task there, named in its panel, and Enter adds the next', (tester) async {
      final view = await pumpGantt(tester, doc, screen: 1100);
      final at = dayInRow(tester, 'L7', '2026-11-18');
      await click(tester, at);
      await click(tester, at);
      await tester.pump();
      expect(lines(view)[8], '- New task [2026-11-18]');
      expect(ganttChart(tester).selected, 'L8');
      expect(find.byType(GanttPanel), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey<String>('gantt-field:name')), matching: find.byType(EditableText)), 'Blog post');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(lines(view)[8], '- Blog post [2026-11-18]', reason: 'its name written over, its days kept');
      expect(find.byType(GanttPanel), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(lines(view)[9], '- New task [2026-11-19]', reason: 'the day after it, as long as it');
    });

    testWidgets('a click opens the panel: how far along, a person and a wait written each as one line', (tester) async {
      final view = await pumpGantt(tester, doc, screen: 1100);
      await click(tester, barAt(tester, 'L4'));
      await tester.pump();
      expect(find.byType(GanttPanel), findsOneWidget);
      expect(find.text('Nothing waits on it.'), findsNothing);
      expect(find.byKey(const ValueKey<String>('gantt-follow-words')), findsOneWidget);
      expect((tester.widget(find.byKey(const ValueKey<String>('gantt-follow-words'))) as Text).data, 'Moving it pushes the task that waits on it along (follow: true).');
      Finder field(String name) => find.descendant(of: find.byKey(ValueKey<String>('gantt-field:$name')), matching: find.byType(EditableText));
      await tester.enterText(field('progress'), '30');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(lines(view)[4], '- Build [2026-11-05 +3d] after: Design 30%');
      await tester.enterText(field('person'), '@sam');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(lines(view)[4], '- Build [2026-11-05 +3d] @sam after: Design 30%');
      await tester.enterText(field('waits'), 'Design, Nobody');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('no task is called “Nobody”.'), findsOneWidget);
      expect(lines(view)[4], '- Build [2026-11-05 +3d] @sam after: Design 30%');
      await tester.tap(find.byKey(const ValueKey<String>('gantt-colour:purple')));
      await tester.pump();
      expect(lines(view)[4], '- Build [2026-11-05 +3d] @sam colour: purple after: Design 30%');
    });

    testWidgets('in simple mode the colour, follow and working days wait behind More', (tester) async {
      await pumpGantt(tester, doc, screen: 1100, simple: true);
      await click(tester, barAt(tester, 'L4'));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('gantt-colour:purple')), findsNothing);
      expect(find.byKey(const ValueKey<String>('gantt-follow')), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('gantt-more')));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('gantt-colour:purple')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('gantt-follow')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('gantt-workdays')), findsOneWidget);
    });

    testWidgets('the keyboard: arrows move a day, shift and arrows resize, up and down choose, Delete takes out, Enter adds', (tester) async {
      final view = await pumpGantt(tester, doc, screen: 1100);
      ganttChart(tester).select('L7');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(lines(view)[7], '- Tell the press [2026-11-17]');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(lines(view)[7], '- Tell the press [2026-11-17 → 2026-11-18]');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(ganttChart(tester).selected, 'L5');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(lines(view)[5], '- ◆ Ship [2026-11-11] after: Build');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(fenceBody(view), contains('## Later'));
      expect(fenceBody(view).contains('Ship'), isFalse);
      expect(ganttChart(tester).selected, 'L6', reason: 'the next task, where its line now is');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(lines(view)[5], '- ◆ Ship [2026-11-11] after: Build', reason: 'cmd-Z is the note’s undo');
    });

    testWidgets('a row’s name dragged into another section moves its line', (tester) async {
      final view = await pumpGantt(tester, doc, screen: 1100);
      final from = tester.getCenter(find.byKey(const ValueKey<String>('gantt-name:L3')));
      final to = tester.getBottomLeft(find.byKey(const ValueKey<String>('gantt-name:L7'))) + Offset(from.dx - tester.getBottomLeft(find.byKey(const ValueKey<String>('gantt-name:L7'))).dx, -2);
      await mouseDrag(tester, from, to - from);
      expect(lines(view).sublist(2), ['## Build', '- Build [2026-11-05 +3d] after: Design', '- ◆ Ship [2026-11-12] after: Build', '## Later', '- Tell the press [2026-11-16]', '- Design [2026-11-02 → 2026-11-04] @matt 50%']);
      expect(ganttChart(tester).widget.model.byKey['L7']!.group, 1);
    });

    testWidgets('zoom with the buttons, and with cmd and the wheel', (tester) async {
      await pumpGantt(tester, doc, screen: 1100);
      await tester.tap(find.byKey(const ValueKey<String>('gantt-zoom-quarter')));
      await tester.pump();
      expect(ganttChart(tester).dayWide, ganttDayWidth(GanttZoom.quarter));
      await tester.tap(find.byKey(const ValueKey<String>('gantt-zoom-in')));
      await tester.pump();
      expect(ganttChart(tester).dayWide, ganttDayWidth(GanttZoom.quarter) * 1.5);
      final before = ganttChart(tester).dayWide;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(barAt(tester, 'L3')));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(ganttChart(tester).dayWide, greaterThan(before));
    });
  });

  group('on a phone, with a finger', () {
    testWidgets('a tap chooses, a second opens the sheet, and a long press then a drag carries', (tester) async {
      final view = await pumpGantt(tester, doc);
      await tester.tapAt(barAt(tester, 'L7'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(ganttChart(tester).selected, 'L7');
      expect(find.byType(GanttSheet), findsNothing);
      await tester.tapAt(barAt(tester, 'L7'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GanttSheet), findsOneWidget);
      ganttChart(tester).select(null);
      await tester.pump(const Duration(milliseconds: 500));
      final wide = ganttChart(tester).dayWide;
      final finger = await tester.startGesture(barAt(tester, 'L3'));
      await tester.pump(const Duration(milliseconds: 600));
      await finger.moveBy(Offset(wide * 1.1, 0));
      await tester.pump();
      await finger.moveBy(Offset(wide * 1, 0));
      await tester.pump();
      await finger.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(lines(view)[3], '- Design [2026-11-04 → 2026-11-06] @matt 50%');
    });

    testWidgets('a swipe across a bar not chosen scrolls the days and writes nothing', (tester) async {
      final view = await pumpGantt(tester, doc);
      final scroll = tester.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey<String>('gantt-scroll')), matching: find.byType(Scrollable)));
      final was = scroll.position.pixels;
      await tester.dragFrom(barAt(tester, 'L3'), const Offset(-120, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(scroll.position.pixels, isNot(was));
      expect(fenceBody(view), fence);
    });

    testWidgets('a chosen bar’s end is taken at once by a finger', (tester) async {
      final view = await pumpGantt(tester, doc);
      ganttChart(tester).select('L4');
      await tester.pump();
      final wide = ganttChart(tester).dayWide;
      await tester.dragFrom(barAt(tester, 'L4', where: 'end'), Offset(wide * 2, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(lines(view)[4], '- Build [2026-11-05 +5d] after: Design');
    });

    testWidgets('a long press on empty days adds a task there', (tester) async {
      final view = await pumpGantt(tester, doc);
      final finger = await tester.startGesture(dayInRow(tester, 'L7', '2026-11-18'));
      await tester.pump(const Duration(milliseconds: 600));
      await finger.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(lines(view)[8], '- New task [2026-11-18]');
      expect(find.byType(GanttSheet), findsOneWidget, reason: 'its sheet open to name it');
    });
  });

  testWidgets('a read-only note draws the chart and carries nothing', (tester) async {
    final view = await pumpGantt(tester, doc, screen: 1100, readOnly: true);
    await mouseDrag(tester, barAt(tester, 'L3'), const Offset(80, 0));
    expect(fenceBody(view), fence);
    expect(find.byKey(const ValueKey<String>('gantt-add')), findsNothing);
  });

  testWidgets('the pencil shows the fence’s lines to type', (tester) async {
    final view = await pumpGantt(tester, doc, screen: 1100);
    await tester.tap(find.byKey(const ValueKey<String>('gantt-text')));
    await tester.pump();
    expect(find.byType(GanttChart), findsNothing);
    expect(view.state.selection.main.head, view.state.doc.line(4).from);
  });
}
