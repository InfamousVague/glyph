// Sub-tickets and blockers in a ticket's panel (lib/editor/tickets/ticket_panel.dart, lib/book/ticket_links.dart; Matt,
// 2026-10-30, of a list of plain-Markdown features: "add all 12"): the parent's bar and its Sub-tickets, Add
// sub-ticket, a move to done that asks while the ticket still waits on another, and a ring refused in words. On a
// phone and on a Mac's width.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/editor/queries/query_look.dart';
import 'package:ghost_md/editor/tickets/tickets.dart';
import 'package:ghost_md/sheet/ask_first.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import 'support.dart';

const TicketChoice cookie = TicketChoice(key: 'GHO-9', title: 'Fix the session cookie', status: 'In review', category: StatusCategory.doing);
const TicketChoice beta = TicketChoice(key: 'GHO-3', title: 'Ship the beta', status: 'Done', category: StatusCategory.done);
const TicketChoice docs = TicketChoice(key: 'GHO-14', title: 'Write the docs', status: 'To do', category: StatusCategory.todo);

const String front = '---\ntype: ticket\nid: GHO-12\nstatus: In progress\nassignee: Sam\n---';

late List<(String, Object?)> written;
late List<String> added;
late List<FirstAsk> asks;
bool answer = true;

TicketOptions options({List<TicketChoice> children = const [], String? Function(String key, Object? value)? problem}) => TicketOptions(
  statuses: () => defaultStatuses,
  people: () => const ['Sam'],
  choices: () => const [cookie, beta, docs],
  find: (target) => const [cookie, beta, docs].where((choice) => choice.key == target.toUpperCase()).firstOrNull,
  open: (_) {},
  subTickets: () => children,
  addSubTicket: added.add,
  problem: problem,
);

Future<void> draw(WidgetTester tester, {String front = front, TicketOptions? given, double width = 390, bool editable = true}) async {
  await pumpApp(
    tester,
    size: Size(width, 900),
    home: Builder(
      builder: (context) => BackScope(
        child: ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: TicketPanel(look: QueryLook.of(context, null), front: front, options: given ?? options(), editable: editable, today: '2026-10-30', locale: 'en-GB', write: (key, value) => written.add((key, value)), openLines: () {}),
            ),
          ),
        ),
      ),
    ),
  );
  debugDisableShadows = true;
  await tester.pump();
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Finder sheetRow(String label) => find.descendant(of: find.byType(SheetRow), matching: find.textContaining(RegExp('^${RegExp.escape(label)}')));

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    written = [];
    added = [];
    asks = [];
    answer = true;
    debugAskFirst = (ask) async {
      asks.add(ask);
      return answer;
    };
  });
  tearDown(() => debugAskFirst = null);

  for (final (where, width) in [('a phone', 390.0), ('a Mac', 1100.0)]) {
    group('on $where', () {
      testWidgets('a parent shows how many of its sub-tickets are done, each a tap away, and adds another', (tester) async {
        await draw(tester, given: options(children: const [beta, docs]), width: width);
        expect(wordsOf(tester, parts('progressWords')).trim(), '1 of 2 done');
        expect(find.bySemanticsLabel('Sub-tickets, 1 of 2 done'), findsOneWidget);
        expect(find.byType(TicketProgressBar), findsOneWidget);
        expect(said('GHO-3 Ship the beta'), findsOneWidget);
        expect(said('GHO-14 Write the docs'), findsOneWidget);
        await tester.tap(said('Add sub-ticket'));
        await settle(tester);
        await tester.enterText(find.byType(EditableText).last, 'Write the changelog');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('sub-ticket-add')));
        await settle(tester);
        expect(added, ['Write the changelog']);
      });

      testWidgets('a ticket with none offers Sub-ticket at its foot', (tester) async {
        await draw(tester, width: width);
        expect(parts('subTickets'), findsNothing);
        expect(parts('addSub'), findsOneWidget);
        await tester.tap(said('Add sub-ticket'));
        await settle(tester);
        expect(find.byKey(const ValueKey('sub-ticket-sheet')), findsOneWidget);
      });
    });
  }

  testWidgets('a blocked ticket asks before it is moved to done, and is not moved when the answer is no', (tester) async {
    await draw(tester, front: '${front.substring(0, front.length - 3)}blocked-by: ["[[GHO-9]]", "[[GHO-3]]"]\n---');
    // GHO-3 is done: only GHO-9 still blocks it.
    expect(wordsOf(tester, parts('waiting')).replaceAll('\n', ''), 'Waiting onGHO-9Fix the session cookie');
    answer = false;
    await tester.tap(said('Status: In progress. Change it'));
    await settle(tester);
    await tester.tap(sheetRow('Done'));
    await settle(tester);
    expect(asks.single.title, 'Move GHO-12 to Done?');
    expect(asks.single.note, 'It still waits on GHO-9, which isn’t done.');
    expect(written, isEmpty);
    answer = true;
    await tester.tap(said('Status: In progress. Change it'));
    await settle(tester);
    await tester.tap(sheetRow('Done'));
    await settle(tester);
    expect(written, [('status', 'Done')]);
    // Any other status is written without a word.
    asks.clear();
    await tester.tap(said('Status: In progress. Change it'));
    await settle(tester);
    await tester.tap(sheetRow('In review'));
    await settle(tester);
    expect(asks, isEmpty);
    expect(written.last, ('status', 'In review'));
  });

  testWidgets('a ticket whose blockers are all done moves to done without asking', (tester) async {
    await draw(tester, front: '${front.substring(0, front.length - 3)}blocked-by: "[[GHO-3]]"\n---');
    expect(parts('waiting'), findsNothing, reason: 'the lock cleared itself: GHO-3 is done');
    await tester.tap(said('Status: In progress. Change it'));
    await settle(tester);
    await tester.tap(sheetRow('Done'));
    await settle(tester);
    expect(asks, isEmpty);
    expect(written, [('status', 'Done')]);
  });

  testWidgets('a Blocked by that would go round in a circle is refused in words, and nothing is written', (tester) async {
    await draw(tester, front: '${front.substring(0, front.length - 3)}blocked-by: "[[GHO-3]]"\n---', given: options(problem: (key, value) => key == 'blocked-by' && '$value'.contains('GHO-9') ? 'GHO-9 already waits on GHO-12, so this would go round in a circle: GHO-12 → GHO-9 → GHO-12.' : null));
    await tester.tap(said('Change Blocked by'));
    await settle(tester);
    await tester.tap(sheetRow('GHO-9'));
    await settle(tester);
    expect(find.text('GHO-9 already waits on GHO-12, so this would go round in a circle: GHO-12 → GHO-9 → GHO-12.'), findsOneWidget);
    expect(written, isEmpty);
    await tester.tap(sheetRow('GHO-14'));
    await settle(tester);
    expect(written.single.$1, 'blocked-by');
  });

  testWidgets('a panel that cannot be edited shows the progress and adds nothing', (tester) async {
    await draw(tester, given: options(children: const [beta]), editable: false);
    expect(wordsOf(tester, parts('progressWords')).trim(), '1 of 1 done');
    expect(said('Add sub-ticket'), findsNothing);
  });
}
