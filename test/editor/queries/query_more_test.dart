// What a drawn query does that the page's own cases do not hold (it has none for `QueryBuilder.tsx`, the switcher
// or a board's height), and that `show: gantt` is the app's own Gantt chart (lib/editor/queries/query_gantt.dart), with
// nothing asked of Mermaid.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/editor/diagrams/diagrams.dart';
import 'package:ghost_md/editor/gantt/gantt_chart.dart' show GanttChart;
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

  // The Mermaid picture `show: gantt` was (docs/PARITY.md, Differs 23) is the app's own Gantt chart now
  // (lib/editor/queries/query_gantt.dart; Matt, 2026-10-31): nothing is asked of Mermaid, and the chart is drawn.
  group('a Gantt chart', () {
    late HeldBridge bridge;

    setUp(() {
      bridge = HeldBridge();
      diagramStore = DiagramStore(bridge: bridge, decode: smallPicture);
    });

    testWidgets('show: gantt and show: timeline are the app’s own chart, and nothing is asked of Mermaid', (tester) async {
      for (final show in ['gantt', 'timeline']) {
        await open(tester, fence('from: tickets\nshow: $show\ngroup: status'));
        expect(find.byType(GanttChart), findsOneWidget);
        expect(bridge.asked, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });
}
