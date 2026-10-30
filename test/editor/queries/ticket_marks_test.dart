// A ticket's lock and its sub-tickets' progress on a query's board and list (lib/editor/queries/ticket_marks.dart;
// Matt, 2026-10-30, of a list of plain-Markdown features: "add all 12"), and a blocked ticket's card dragged to Done,
// which asks first and moves nothing on Cancel.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/ticket_links.dart' show TicketProgress;
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/editor/queries/queries.dart';
import 'package:ghost_md/editor/queries/ticket_marks.dart';
import 'package:ghost_md/sheet/ask_first.dart';

import '../../support/render.dart';
import 'support.dart';

const String today = '2026-10-08';
const QueryNote blocked = QueryNote(id: 'gho1', body: '---\ntype: ticket\nid: GHO-1\nstatus: In review\nblocked-by: "[[GHO-9]]"\n---\n# Fix the login loop\n', createdAt: 0, updatedAt: 0);
const QueryNote parent = QueryNote(id: 'gho2', body: '---\ntype: ticket\nid: GHO-2\nstatus: To do\n---\n# Ship the beta\n', createdAt: 0, updatedAt: 0);

String fence(String lines) => '# This week\n\n```query\n$lines\n```\n';

void main() {
  setUpAll(loadAppFonts);
  late Asked asked;
  late List<FirstAsk> asks;
  var answer = false;
  setUp(() {
    asked = Asked();
    asks = [];
    debugAskFirst = (ask) async {
      asks.add(ask);
      return answer;
    };
  });
  tearDown(() => debugAskFirst = null);

  TicketMarks marks(String id) => switch (id) {
        'gho1' => (blockers: const ['GHO-9'], progress: null),
        'gho2' => (blockers: const <String>[], progress: const TicketProgress(done: 1, total: 3)),
        _ => null,
      };

  QueryOptions options() => QueryOptions(
    notes: () => const [blocked, parent],
    noteId: 'here',
    open: (noteId, line) => asked.opened.add((noteId, line)),
    write: (noteId, change) => asked.written.add((noteId, change)),
    ticketMarks: marks,
  );

  for (final (where, width) in [('a phone', 390.0), ('a Mac', 1100.0)]) {
    testWidgets('a board’s cards show the lock and the progress, on $where', (tester) async {
      await pumpQueries(tester, fence('from: tickets\nshow: board'), options: options(), today: today, screen: width);
      expect(find.byType(QueryTicketMarks), findsNWidgets(2));
      expect(find.bySemanticsLabel('Waiting on GHO-9'), findsOneWidget);
      expect(find.bySemanticsLabel('Sub-tickets, 1 of 3 done'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
    });
  }

  testWidgets('a list’s rows show them in words', (tester) async {
    await pumpQueries(tester, fence('from: tickets\nshow: list'), options: options(), today: today);
    expect(find.bySemanticsLabel('Waiting on GHO-9'), findsOneWidget);
    expect(find.text('1/3 done'), findsOneWidget);
  });

  testWidgets('a blocked ticket dragged to Done asks first, and stays on Cancel; moved on the yes', (tester) async {
    for (final yes in [false, true]) {
      answer = yes;
      asked = Asked();
      asks.clear();
      await pumpQueries(tester, fence('from: tickets\nshow: board'), options: options(), today: today, screen: 1600);
      final card = boxOf(tester, find.ancestor(of: find.text('Fix the login loop'), matching: parts('card')).first);
      final done = boxOf(tester, parts('lane').last);
      expect(tester.getSemantics(parts('lane').last).label.split('\n').first, startsWith('Done'));
      final finger = await holdAt(tester, card.topLeft + const Offset(30, 12));
      await finger.moveTo(Offset(done.left + 60, done.center.dy));
      await tester.pump();
      await finger.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(asks.single.title, 'Move GHO-1 to Done?');
      expect(asks.single.note, 'It still waits on GHO-9, which isn’t done.');
      if (yes) {
        expect(asked.written.single.$1, 'gho1');
        expect(asked.written.single.$2(blocked.body), contains('status: Done'));
      } else {
        expect(asked.written, isEmpty);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }
  });
}
