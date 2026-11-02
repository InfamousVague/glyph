// A Mermaid gantt drawn as the app's own chart, read only (lib/editor/diagrams/diagrams.dart `DrawnMermaidGantt`;
// Matt, 2026-11-02, from the Fold's cover screen: "Clean up the gantt chart viewing experience to be scrolling on
// mobile and bigger right now it's very cluttered and impossible to parse"): no picture asked of Mermaid; the names
// in their column, as Mermaid writes them, two lines at most and never over the days; the days scrolling sideways on a
// phone and fitting whole on a desktop; today in sight as it opens; the days' head staying in sight as the page
// scrolls; the pencil opening the fence; the chart's own full screen; and the words never touched.
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/gantt/gantt.dart';
import 'package:ghost_md/editor/diagrams/diagrams.dart';
import 'package:ghost_md/editor/gantt/gantt.dart';

import '../editor/diagrams/support.dart' show HeldBridge, smallPicture;
import '../support/render.dart';
import 'support.dart';

const String code = '''gantt
    title The renovation, done May 17, 2027
    dateFormat YYYY-MM-DD
    axisFormat %b %d

    section Phases
    First phase (weeks 1-13)         :t1, 2026-08-10, 2026-11-09
    Second phase (weeks 14-27)       :t2, 2026-11-09, 2027-02-15
    Third phase (weeks 28-40)        :t3, 2027-02-15, 2027-05-17

    section Getting ready
    Planning and permits             :p1, 2026-09-28, 2026-12-07
    Tools packed, waiting            :p4, 2027-04-12, 2027-05-17

    section Usual inspections and checks
    First structural inspection (weeks 11-14) :s1, 2026-10-19, 2026-11-16
    Final safety check (weeks 36-37) :s5, 2027-04-12, 2027-04-26

    section Done
    Done date                        :milestone, due, 2027-05-17, 0d''';

const String doc = '# The renovation\n\n```mermaid\n$code\n```\n\nAfter the chart.\n';

late HeldBridge bridge;

final Finder _days = find.byKey(const ValueKey<String>('gantt-days'));
final Finder _head = find.byKey(const ValueKey<String>('gantt-head'));

ScrollableState _across(WidgetTester tester) =>
    tester.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey<String>('gantt-scroll')).first, matching: find.byType(Scrollable)).first);

void main() {
  setUpAll(loadAppFonts);

  setUp(() {
    bridge = HeldBridge();
    diagramStore = DiagramStore(bridge: bridge, decode: smallPicture);
    rememberDiagramHeights = false;
  });

  test('the model keeps Mermaid’s names, commas and all, and has none for a gantt with no task', () {
    final model = mermaidGanttModel(code, today: '2026-11-02')!;
    expect(model.title, 'The renovation, done May 17, 2027');
    expect([for (final group in model.groups) group.name], ['Phases', 'Getting ready', 'Usual inspections and checks', 'Done']);
    expect(model.items.map((item) => item.name), contains('Tools packed, waiting'));
    final first = model.items.first;
    expect((first.start, first.end), ('2026-08-10', '2026-11-08'), reason: 'Mermaid’s end is the day after the bar');
    expect(model.items.last.milestone, isTrue);
    expect(mermaidGanttModel('gantt\n  title Nothing yet', today: '2026-11-02'), isNull);
  });

  testWidgets('on a phone: the app’s chart, no picture asked, names in their column on two lines at most', (tester) async {
    final view = await pumpGantt(tester, doc, screen: 390, height: 1400, today: '2026-11-02');
    expect(find.byType(GanttChart), findsOneWidget);
    expect(bridge.asked, isEmpty, reason: 'Mermaid draws nothing for a gantt now');
    final days = tester.getRect(find.byKey(const ValueKey<String>('gantt-scroll')));
    final state = ganttChart(tester);
    expect(state.rows.row, greaterThanOrEqualTo(ganttRow), reason: 'a row a finger can take');
    for (final name in ['First phase (weeks 1-13)', 'Tools packed, waiting', 'First structural inspection (weeks 11-14)']) {
      final words = tester.getRect(find.text(name));
      expect(words.right, lessThanOrEqualTo(days.left + 0.5), reason: '“$name” stays in its column, off the days');
      expect(words.height, lessThanOrEqualTo(state.rows.row), reason: '“$name” on two lines at most');
      final text = tester.widget<Text>(find.text(name));
      expect(text.maxLines, 2);
      expect(text.style?.fontFamily, isNot(contains('Mono')), reason: 'the app’s face, not the typewriter’s');
    }
    expect(_across(tester).position.maxScrollExtent, greaterThan(0), reason: 'nine months scroll sideways on a phone');
    // Today in sight as it opens.
    final todayX = days.left + state.frame.x('2026-11-02') + state.frame.wide / 2 - _across(tester).position.pixels;
    final viewport = tester.getRect(find.byKey(const ValueKey<String>('gantt-scroll')));
    expect(todayX, inInclusiveRange(viewport.left, viewport.right));
    expect(view.state.doc.toString(), doc, reason: 'only the drawing changed');
  });

  testWidgets('on a desktop the same chart fits its nine months whole', (tester) async {
    await pumpGantt(tester, doc, screen: 1280, height: 1100, today: '2026-11-02');
    expect(_across(tester).position.maxScrollExtent, 0);
  });

  testWidgets('the days’ head stays in sight as the page scrolls the rows up under it', (tester) async {
    await pumpGantt(tester, doc, screen: 390, height: 700, today: '2026-11-02');
    expect(ganttChart(tester).lift, 0);
    final top = tester.getRect(_days).top;
    final page = tester.state<ScrollableState>(find.byType(Scrollable).first);
    page.position.jumpTo(top + 100);
    await tester.pump();
    final head = tester.getRect(_head);
    expect(head.top, closeTo(0, 1), reason: 'at the top of the page’s view');
    page.position.jumpTo(0);
    await tester.pump();
    expect(ganttChart(tester).lift, 0);
  });

  testWidgets('its pencil opens the fence, and a read-only note has none', (tester) async {
    final view = await pumpGantt(tester, doc, screen: 390, today: '2026-11-02');
    await tester.tap(find.byKey(const ValueKey<String>('gantt-text')));
    await tester.pump();
    expect(find.byType(GanttChart), findsNothing);
    expect(view.state.selection.main.head, view.state.doc.line(3).from);
    expect(view.state.doc.toString(), doc);
  });

  testWidgets('a read-only note draws it with no pencil and no Convert', (tester) async {
    await pumpGantt(tester, doc, screen: 390, today: '2026-11-02', readOnly: true);
    expect(find.byType(GanttChart), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('gantt-text')), findsNothing);
    expect(find.byKey(const ValueKey<String>('diagram-convert-gantt')), findsNothing);
  });

  testWidgets('full screen is the same chart over the app, its head staying as its rows scroll, closed by Escape', (tester) async {
    await pumpGantt(tester, doc, screen: 390, height: 600, today: '2026-11-02');
    await tester.tap(find.byKey(const ValueKey<String>('gantt-full')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(GanttLayer), findsOneWidget);
    final inLayer = find.descendant(of: find.byType(GanttLayer), matching: find.byType(GanttChart));
    expect(inLayer, findsOneWidget);
    final scroll = tester.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey<String>('gantt-full-scroll')), matching: find.byType(Scrollable)).first);
    final viewTop = tester.getRect(find.byKey(const ValueKey<String>('gantt-full-scroll'))).top;
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    final head = tester.getRect(find.descendant(of: find.byType(GanttLayer), matching: _head));
    expect(head.top, closeTo(viewTop, 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(GanttLayer), findsNothing);
  });

  testWidgets('a Mermaid gantt with no task is still Mermaid’s picture', (tester) async {
    await pumpGantt(tester, '# A\n\n```mermaid\ngantt\n  title Nothing yet\n```\n', screen: 390);
    expect(find.byType(GanttChart), findsNothing);
    expect(bridge.asked, hasLength(1));
  });
}
