// What a drawn query does that the page's own cases do not hold (it has none for `QueryBuilder.tsx`, the switcher
// or a board's height), and the timeline (lib/editor/queries/query_timeline.dart): that Mermaid is handed the text
// `ganttOf` writes, with the card's rules, and what stands in the card before, after and in place of its picture.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/editor/diagrams/diagrams.dart';
import 'package:ghost_md/editor/queries/queries.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:ghost_md/sheet/sheet.dart';

import '../../support/render.dart';
import '../diagrams/support.dart';
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

  // docs/PARITY.md, Differs 23. QueryView.tsx `GanttView`: `drawDiagram(result.gantt.code)`, Mermaid's own gantt in
  // `<div className="cm-mermaid gantt">`; the text in a `<pre>` until it is drawn; "This timeline could not be drawn
  // here." when it cannot be; and the count of what has no day.
  group('a timeline', () {
    QueryResult run(String lines) => runQuery(readQuery(lines).query!, libraryOf(library), today);
    late HeldBridge bridge;

    setUp(() {
      bridge = HeldBridge();
      diagramStore = DiagramStore(bridge: bridge, decode: smallPicture);
    });

    testWidgets('hands Mermaid the text the page hands it, drawn for the card: its width, its type, no gutter, and the card\'s three inks', (tester) async {
      await open(tester, fence('from: tickets\nshow: gantt\ngroup: status'));
      final result = run('from: tickets\nshow: gantt\ngroup: status');
      expect(bridge.asked, hasLength(1));
      final ask = bridge.asked.single;
      expect(ask.code, result.gantt!.code);
      expect(ask.code, startsWith('%%{init: '));
      expect(ask.code, contains('\ngantt\n'));
      final look = QueryLook.of(tester.element(drawn), null);
      expect(ask.gutter, 0, reason: '.gantt { padding-inline: 0 !important }');
      expect(ask.em, look.em, reason: 'the card\'s own size');
      expect(ask.note, ask.ui, reason: 'the card is set in the interface\'s face');
      expect(ask.room, closeTo(boxOf(tester, parts('lines')).width, 0.01), reason: 'as wide as the card\'s room');
      expect(ask.timeline, isNotNull);
      expect((ask.timeline!.tick, ask.timeline!.rule, ask.timeline!.section), (look.ink3, look.rule, look.ink2));
      expect(ask.toJson()['timeline'], isA<Map<String, Object?>>());
      expect(ask.timeline!.day, today, reason: 'the card\'s own today');
      // A diagram in a note asks with none, and is never taken for a timeline's picture.
      expect(askFor(ask.code).key, isNot(ask.key));
    });

    testWidgets('shows its text until the picture comes, then the picture, called Timeline; and says what it could not place', (tester) async {
      await open(tester, fence('from: tickets\nshow: gantt\ngroup: status'));
      expect(parts('lines'), findsOneWidget);
      expect(wordsOf(tester, parts('lines')), contains('dateFormat YYYY-MM-DD'));
      expect(parts('gantt'), findsNothing);
      expect(wordsOf(tester, drawn), isNot(contains('could not be drawn')));
      bridge.finish(0, block: const Size(300, 150), at: const Rect.fromLTWH(0, 10, 300, 130));
      await tester.pump();
      await tester.pump();
      expect(parts('gantt'), findsOneWidget);
      expect(parts('lines'), findsNothing);
      expect(find.bySemanticsLabel('Timeline'), findsOneWidget);
      expect(tester.getSize(parts('gantt')).height, closeTo(150, 0.01), reason: 'the block Mermaid drew, its padding with it');
      expect(wordsOf(tester, drawn), contains('One has no start or due day, and is not on the timeline.'));
      expect(find.byType(CustomPaint).evaluate().where((e) => (e.widget as CustomPaint).painter.runtimeType.toString() == 'GanttPainter'), isEmpty, reason: 'no drawing of the app\'s own');
    });

    // Mermaid draws a line down the bars at today, and the page drew a timeline again each time the app was opened
    // (mermaid.ts `drawn` is a map in memory). A picture here outlives the app, in the folder, by its key.
    testWidgets('a picture kept is today\'s only: the same card on another day is drawn again', (tester) async {
      final doc = fence('from: tickets\nshow: gantt\ngroup: status');
      await open(tester, doc);
      bridge.finish(0, block: const Size(300, 150), at: const Rect.fromLTWH(0, 10, 300, 130));
      await tester.pump();
      await tester.pump();
      await open(tester, doc);
      expect(bridge.asked, hasLength(1), reason: 'the same day: the picture it has');
      expect(parts('gantt'), findsOneWidget);
      await pumpQueries(tester, doc, options: optionsOver(() => library, Asked()), today: '2026-10-09');
      expect(bridge.asked, hasLength(2), reason: 'the next day: asked again');
      expect(bridge.asked.last.code, bridge.asked.first.code);
      expect(bridge.asked.last.timeline!.day, '2026-10-09');
      expect(bridge.asked.last.key, isNot(bridge.asked.first.key));
    });

    testWidgets('a timeline that cannot be drawn keeps its text and says so, in the page\'s words', (tester) async {
      await open(tester, fence('from: tickets\nshow: gantt'));
      bridge.fail(0, '');
      await tester.pump();
      await tester.pump();
      expect(parts('lines'), findsOneWidget);
      expect(wordsOf(tester, drawn), contains('This timeline could not be drawn here.'));
    });

    testWidgets('is one sentence where no record has a day, and nothing is asked of Mermaid', (tester) async {
      await open(tester, fence('from: tickets\nwhere: id = GHO-4\nshow: gantt'));
      expect(wordsOf(tester, drawn), contains('Nothing here has a start or a due day to put on a timeline.'));
      expect(bridge.asked, isEmpty);
    });
  });
}
