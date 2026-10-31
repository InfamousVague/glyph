// A ticket's planning, drawn where a query lists it (lib/editor/queries/plan_marks.dart, lib/core/query/planning.dart;
// Matt, 2026-10-31): the board of the current cycle with its carry bar, a card's coloured priority, estimate and
// stale, the burndown, velocity and the roadmap, on a phone and on a desktop's wide window, and nothing of it where
// the host draws no planning.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/planning/history.dart';
import 'package:ghost_md/editor/gantt/gantt_chart.dart' show GanttChart;
import 'package:ghost_md/editor/queries/queries.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:ghost_md/sheet/sheet.dart';

import '../../query/planning_library.dart' as planned;
import '../../support/render.dart';
import 'support.dart';

String fence(String lines) => '# Kiln planning\n\n```query\n$lines\n```\n';

Finder sheetRow(String label) => find.descendant(of: find.byType(SheetRow), matching: find.text(label));

late Asked asked;

/// KLN-5 finished on the 3rd, by its versions.
final TicketHistory past = TicketHistory((id) async => const [])..hold('k5', const [StatusChange(day: '2026-11-02', status: 'To do'), StatusChange(day: '2026-11-03', status: 'Done')]);

QueryOptions options({bool planning = true}) => QueryOptions(
  notes: () => planned.library,
  noteId: 'here',
  open: (noteId, line) => asked.opened.add((noteId, line)),
  write: (noteId, change) => asked.written.add((noteId, change)),
  history: planning ? () => past : null,
);

Future<EditorView> open(WidgetTester tester, String lines, {double screen = 390, bool planning = true}) =>
    pumpQueries(tester, fence(lines), options: options(planning: planning), today: planned.today, screen: screen);

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// What the screen was asked to write into note [id], made of its words.
String writtenTo(String id) {
  final (noteId, change) = asked.written.lastWhere((each) => each.$1 == id);
  return change(planned.library.firstWhere((note) => note.id == noteId).body)!;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => asked = Asked());

  for (final (size, screen) in const [('a phone', 390.0), ('a desktop', 1100.0)]) {
    group('on $size', () {
      testWidgets('the current cycle’s board offers to carry the last one’s unfinished tickets on, in one action', (tester) async {
        await open(tester, 'from: tickets [[Kiln]]\nwhere: cycle = current\nshow: board', screen: screen);
        final carry = said('Move 1 unfinished to 2026-C45');
        expect(carry, findsOneWidget);
        expect(find.text('2026-C43 ended with 1 unfinished'), findsOneWidget);
        await tester.tap(carry);
        await settle(tester);
        final carried = writtenTo('k3');
        expect(carried, contains('cycle: 2026-C45\n'));
        // A team note's comments come through untouched.
        expect(carried, endsWith(planned.comments));
        expect(tester.takeException(), isNull);
      });

      testWidgets('a card has its priority as a coloured chip, its estimate and how long it has sat', (tester) async {
        await open(tester, 'from: tickets [[Kiln]]\nshow: board', screen: screen);
        await tester.ensureVisible(said('Priority: Urgent. Change it'));
        expect(said('Priority: Urgent. Change it'), findsOneWidget);
        expect(find.text('Urgent'), findsOneWidget);
        expect(said('Estimate: 5 pts. Change it'), findsOneWidget);
        expect(said(RegExp(r'^Stale: 16 days')), findsOneWidget);
        // An epic says so, and its points.
        expect(find.text('Epic'), findsOneWidget);
        expect(find.text('5 of 18 pts'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('a card’s estimate is changed from its sheet', (tester) async {
    await open(tester, 'from: tickets [[Kiln]]\nwhere: cycle = current\nshow: board');
    final chip = said('Estimate: 8 pts. Change it');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await settle(tester);
    expect(find.byType(Sheet), findsOneWidget);
    await tester.tap(sheetRow('13 pts'));
    await settle(tester);
    expect(writtenTo('k6'), contains('estimate: 13\n'));
  });

  testWidgets('a card in a cycle with no estimate offers one, and the sheet takes one typed', (tester) async {
    final notes = [for (final note in planned.library) note.id == 'k6' ? note.withBody(note.body.replaceFirst('estimate: 8\n', '')) : note];
    await pumpQueries(
      tester,
      fence('from: tickets [[Kiln]]\nwhere: cycle = current\nshow: board'),
      options: QueryOptions(notes: () => notes, noteId: 'here', open: (_, _) {}, write: (id, change) => asked.written.add((id, change)), history: () => past),
      today: planned.today,
    );
    final chip = said('Estimate: none. Set it');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await settle(tester);
    await tester.enterText(find.descendant(of: find.byType(Sheet), matching: find.byType(EditableText)), '3h');
    await tester.pump();
    expect(sheetRow('Set it to 3h'), findsOneWidget);
    // The keyboard's done key sets what is typed.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    final (id, change) = asked.written.single;
    expect(id, 'k6');
    expect(change(notes.firstWhere((note) => note.id == 'k6').body), contains('estimate: 3h\n'));
  });

  testWidgets('a card’s priority is picked from a ticket’s four, and Urgent is written as urgent', (tester) async {
    await open(tester, 'from: tickets [[Kiln]]\nwhere: cycle = current\nshow: board');
    final priority = said(RegExp('^Priority: Medium'));
    await tester.ensureVisible(priority);
    await tester.tap(priority);
    await settle(tester);
    expect(find.byKey(const ValueKey('priority-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('priority:lowest')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('priority:urgent')));
    await settle(tester);
    expect(writtenTo('k6'), contains('priority: urgent\n'));
  });

  testWidgets('a list’s rows and a table’s say stale beside the name', (tester) async {
    await open(tester, 'from: tickets [[Kiln]]\nwhere: stale\nshow: list');
    expect(said(RegExp(r'^Stale: ')), findsNWidgets(3));
    await open(tester, 'from: tickets [[Kiln]]\nwhere: stale\nshow: table');
    expect(said(RegExp(r'^Stale: ')), findsNWidgets(3));
  });

  testWidgets('a burndown is the chart view’s line, remaining and ideal, and velocity its bars', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester, 'from: tickets [[Kiln]]\nshow: burndown');
    expect(find.byType(QueryChart), findsOneWidget);
    expect(find.semantics.byLabel('2 Nov · Remaining: 13, Ideal: 13'), findsOne);
    expect(find.semantics.byLabel('3 · Remaining: 12, Ideal: 12'), findsOne);
    // A day still to come has the ideal alone.
    expect(find.semantics.byLabel('15 · Ideal: 0'), findsOne);
    // A day picked lists what was still open at its end.
    tester.semantics.tap(find.semantics.byLabel('3 · Remaining: 12, Ideal: 12'));
    await tester.pump();
    expect(wordsOf(tester, parts('chartRows')), allOf(contains('Vent the room'), contains('Price list'), isNot(contains('Order shelves'))));
    await open(tester, 'from: tickets [[Kiln]]\nshow: velocity');
    expect(find.semantics.byLabel('C43: 5'), findsOne);
    expect(find.semantics.byLabel('C45: 1'), findsOne);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  // The timeline is the Gantt chart since 2026-10-31 (lib/editor/queries/query_gantt.dart).
  testWidgets('a roadmap is drawn on the timeline: the epic and the milestone', (tester) async {
    await open(tester, 'from: notes [[Kiln]]\nshow: roadmap');
    expect(find.byType(GanttChart), findsOneWidget);
    expect(parts('ganttName'), findsNWidgets(2));
    expect(wordsOf(tester, find.byType(GanttChart)), allOf(contains('Second kiln'), contains('v2 launch')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('where the host draws no planning, a card is as the page drew it', (tester) async {
    await open(tester, 'from: tickets [[Kiln]]\nshow: board', planning: false);
    expect(said('Priority: Urgent. Change it'), findsNothing);
    expect(said('Priority: highest. Change it'), findsOneWidget);
    expect(said(RegExp(r'^Estimate')), findsNothing);
    expect(said(RegExp(r'^Stale')), findsNothing);
    // The carry offer is the planning's too.
    await open(tester, 'from: tickets [[Kiln]]\nwhere: cycle = current\nshow: board', planning: false);
    expect(said(RegExp('^Move 1 unfinished')), findsNothing);
  });
}
