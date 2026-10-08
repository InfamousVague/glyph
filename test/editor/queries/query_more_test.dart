// What a drawn query does that the page's own cases do not hold (it has none for `QueryBuilder.tsx`, the switcher
// or a board's height), and the timeline, which is this app's own drawing (lib/editor/queries/query_gantt.dart):
// that it places the records `ganttOf` places, on the same days, ticked as `ticksFor` says.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/editor/queries/queries.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:ghost_md/sheet/sheet.dart';

import '../../support/render.dart';
import 'support.dart';

const String today = '2026-10-08';

const List<QueryNote> library = <QueryNote>[
  QueryNote(id: 'shop', body: '# Groceries\n\n- [ ] Milk 📅 2026-10-07 @sam\n- [ ] Bread\n', createdAt: 0, updatedAt: 0),
  QueryNote(id: 'gho1', body: '---\ntype: ticket\nid: GHO-1\nstatus: In progress\nstart: 2026-10-01\ndue: 2026-10-06\n---\n# Fix the login loop\n', createdAt: 0, updatedAt: 0),
  QueryNote(id: 'gho2', body: '---\ntype: ticket\nid: GHO-2\nstatus: To do\ndue: 2026-10-12\n---\n# Ship the pricing page\n', createdAt: 0, updatedAt: 0),
  QueryNote(id: 'gho3', body: '---\ntype: ticket\nid: GHO-3\nstatus: Done\nstart: 2026-10-05\ndue: 2026-09-28\n---\n# Write the changelog\n', createdAt: 0, updatedAt: 0),
  QueryNote(id: 'gho4', body: '---\ntype: ticket\nid: GHO-4\nstatus: To do\n---\n# Draw the icons\n', createdAt: 0, updatedAt: 0),
];

String fence(String lines, [String settings = '']) => '# This week\n\n```query$settings\n$lines\n```\n';

Future<EditorView> open(WidgetTester tester, String doc) => pumpQueries(tester, doc, options: optionsOver(() => library, Asked()), today: today);

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Finder sheetRow(String label) => find.descendant(of: find.byType(SheetRow), matching: find.text(label));

void main() {
  setUpAll(loadAppFonts);

  group('the switcher', () {
    testWidgets('writes only the show line, the rest of the query as it was', (tester) async {
      final view = await open(tester, fence('from: tickets\nwhere: status != Done'));
      expect(tester.getSemantics(said('Show as a table')).flagsCollection.isSelected.toBoolOrNull(), isTrue);
      await tester.tap(said('Show as a list'));
      await tester.pump();
      expect(view.state.doc.toString(), contains('```query\nfrom: tickets\nwhere: status != Done\nshow: list\n```'));
      expect(parts('row'), findsWidgets);
      // The one it is already drawn as writes nothing.
      final before = view.state.doc.toString();
      await tester.tap(said('Show as a list'));
      await tester.pump();
      expect(view.state.doc.toString(), before);
    });

    testWidgets('is not there where the note cannot be edited', (tester) async {
      await pumpQueries(tester, fence('from: tickets'), options: optionsOver(() => library, Asked()), readOnly: true, today: today);
      expect(said(RegExp('^Show as a ')), findsNothing);
      expect(said('Build the query'), findsNothing);
    });
  });

  group('the builder', () {
    testWidgets('writes a clause a tap, drops a filter meant for another kind, and leaves the lines it does not offer', (tester) async {
      final view = await open(tester, fence('from: tasks\nwhere: due < today\nsort: due'));
      await tester.tap(said('Build the query'));
      await settle(tester);
      expect(tester.widget<Sheet>(find.byType(Sheet)).label, 'Build the query');
      // What it has is lit: to-dos, overdue.
      expect(tester.widget<SheetRow>(find.byKey(const ValueKey<String>('kind:tasks'))).chosen, isTrue);
      expect(tester.widget<SheetRow>(find.byKey(const ValueKey<String>('only:late'))).chosen, isTrue);
      await tester.tap(sheetRow('Tickets'));
      await settle(tester);
      expect(view.state.doc.toString(), contains('```query\nfrom: tickets\nsort: due\n```'));
      await tester.tap(sheetRow('By status'));
      await settle(tester);
      expect(view.state.doc.toString(), contains('from: tickets\nsort: due\ngroup: status'));
      await tester.ensureVisible(sheetRow('Board'));
      await tester.pump();
      await tester.tap(sheetRow('Board'));
      await settle(tester);
      expect(view.state.doc.toString(), contains('show: board'));
      expect(parts('lane'), findsWidgets);
    });

    testWidgets('names a filter written by hand as the person’s own, and its row opens the lines', (tester) async {
      final view = await open(tester, fence('from: tickets\nwhere: estimate > 2 or priority = high'));
      await tester.tap(said('Build the query'));
      await settle(tester);
      expect(sheetRow('Your own: estimate > 2 or priority = high'), findsOneWidget);
      await tester.tap(sheetRow('Your own: estimate > 2 or priority = high'));
      await settle(tester);
      expect(find.byType(Sheet), findsNothing);
      expect(drawn, findsNothing);
      expect(view.state.doc.lineAt(view.state.selection.main.head).text, 'from: tickets');
    });
  });

  group('a board’s height', () {
    testWidgets('is the fence’s, and a step of the line under it is written into the fence', (tester) async {
      final view = await open(tester, fence('from: tickets\nshow: board', ' height=12'));
      final look = QueryLook.of(tester.element(drawn), view.look);
      expect(boxOf(tester, parts('lane').first).height, closeTo(12 * look.em, 0.01));
      final split = tester.getSemantics(said('Board height'));
      expect(split.value, '12');
      tester.semantics.increase(find.semantics.byLabel('Board height'));
      await tester.pump();
      expect(view.state.doc.toString(), contains('```query height=13\n'));
      expect(boxOf(tester, parts('lane').first).height, closeTo(13 * look.em, 0.01));
    });
  });

  group('a timeline', () {
    QueryResult run(String lines) => runQuery(readQuery(lines).query!, libraryOf(library), today);

    test('places the records the page’s chart places, on the same days', () {
      final result = run('from: tickets\nshow: gantt\ngroup: status');
      final chart = ganttChart(result.groups, 'Tickets')!;
      expect(chart.placed, result.gantt!.placed);
      expect(chart.placed, 3);
      expect(chart.named, isTrue);
      expect(<String>[for (final section in chart.sections) section.label], <String>['To do', 'In progress', 'Done']);
      final bars = <String, GanttBar>{for (final section in chart.sections) for (final bar in section.bars) bar.name: bar};
      // From its start to its due day, the due day whole.
      expect((bars['GHO-1 Fix the login loop']!.start, bars['GHO-1 Fix the login loop']!.end), ('2026-10-01', '2026-10-07'));
      // Only a due day: a bar of that day.
      expect((bars['GHO-2 Ship the pricing page']!.start, bars['GHO-2 Ship the pricing page']!.end), ('2026-10-12', '2026-10-13'));
      // A start written after the due day: the bar still runs between them.
      expect((bars['GHO-3 Write the changelog']!.start, bars['GHO-3 Write the changelog']!.end), ('2026-09-28', '2026-10-06'));
      // Under way, overdue, finished: what Mermaid's `active`, `crit` and `done` said.
      expect((bars['GHO-1 Fix the login loop']!.active, bars['GHO-1 Fix the login loop']!.crit, bars['GHO-1 Fix the login loop']!.done), (true, true, false));
      expect(bars['GHO-3 Write the changelog']!.done, isTrue);
      expect((chart.from, chart.to), ('2026-09-28', '2026-10-13'));
      // Every bar the page's text names is here, by the same words.
      for (final name in bars.keys) {
        expect(result.gantt!.code, contains('  $name :'));
      }
    });

    test('has no sections where the query is not grouped, and is nothing where no record has a day', () {
      final flat = ganttChart(run('from: tickets\nshow: gantt').groups)!;
      expect(flat.named, isFalse);
      expect(flat.sections.single.label, '');
      expect(ganttChart(run('from: tickets\nwhere: id = GHO-4\nshow: gantt').groups), isNull);
    });

    test('is ticked a day, a week, a month or three apart as its bars span days, weeks or months', () {
      expect(<String>[for (final tick in ganttTicks('2026-10-05', '2026-10-09')) tick.label], <String>['5', '6', '7', '8', '9']);
      // A week's tick is its Monday.
      expect(<String>[for (final tick in ganttTicks('2026-09-28', '2026-10-13')) tick.label], <String>['28 Sep', '5 Oct', '12 Oct']);
      expect(<String>[for (final tick in ganttTicks('2026-09-28', '2027-01-15')) tick.label], <String>['Oct', 'Nov', 'Dec', 'Jan']);
      expect(<String>[for (final tick in ganttTicks('2026-01-10', '2027-08-01')) tick.label], <String>['Apr 2026', 'Jul 2026', 'Oct 2026', 'Jan 2027', 'Apr 2027', 'Jul 2027']);
    });

    testWidgets('is drawn by the app’s own painter, and says what it could not place', (tester) async {
      await open(tester, fence('from: tickets\nshow: gantt\ngroup: status'));
      final painted = tester.widget<CustomPaint>(find.descendant(of: parts('gantt'), matching: find.byType(CustomPaint)).first);
      expect(painted.painter, isA<GanttPainter>());
      expect((painted.painter! as GanttPainter).chart.placed, 3);
      expect(wordsOf(tester, drawn), contains('One has no start or due day, and is not on the timeline.'));
      await open(tester, fence('from: tickets\nwhere: id = GHO-4\nshow: gantt'));
      expect(wordsOf(tester, drawn), contains('Nothing here has a start or a due day to put on a timeline.'));
    });
  });
}
