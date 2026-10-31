// A ticket's planning in its panel (lib/editor/tickets/ticket_panel.dart, ticket_planning.dart; Matt, 2026-10-31): its
// cycle and the cycles it can move to, its milestone, its priority as a coloured chip from a ticket's four, how long it
// has sat, and an epic's progress by points; on a phone and a desktop's width, and behind More in Simple mode. The
// tickets are a team's (test/query/planning_library.dart), read through the library's own planning.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/editor/queries/query_look.dart';
import 'package:ghost_md/editor/tickets/ticket_panel.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:glacier/glacier.dart';

import '../../query/planning_library.dart' as planned;
import '../../support/render.dart';
import 'support.dart';

/// The front matter of one of the library's tickets, fences and all.
String frontOf(String id) {
  final body = planned.library.firstWhere((note) => note.id == id).body;
  return body.substring(0, body.indexOf('\n---', 3) + 4);
}

final PlanningIndex plan = PlanningIndex(libraryOf(planned.library), planned.today);

Future<void> draw(WidgetTester tester, String id, {double width = 390, bool simple = false, String? front, bool planning = true}) async {
  final options = TicketOptions(
    statuses: () => defaultStatuses,
    people: () => const ['Sam', 'Priya'],
    choices: () => const <TicketChoice>[],
    find: (_) => null,
    open: (_) {},
    subTickets: () => [
      for (final child in plan.children[id] ?? const <QueryRecord>[]) TicketChoice(key: child.ticket!.id, title: child.title, status: child.ticket!.status, category: child.ticket!.category),
    ],
    planning: planning ? () => ticketPlanningOf(plan, id) : null,
  );
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
              child: TicketPanel(
                look: QueryLook.of(context, null),
                front: front ?? frontOf(id),
                options: options,
                editable: true,
                today: planned.today,
                locale: 'en-GB',
                simple: simple,
                write: (key, value) => written.add((key, value)),
                openLines: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  debugDisableShadows = true;
  await tester.pump();
}

late List<(String, Object?)> written;

Future<void> press(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => written = []);

  for (final (size, width) in const [('a phone', 390.0), ('a desktop', 1024.0)]) {
    testWidgets('on $size, a ticket’s cycle, milestone, priority and age are in its panel', (tester) async {
      await draw(tester, 'k3', width: width);
      expect(said(RegExp(r'^Cycle: 2026-C43 · 19 Oct – 1 Nov')), findsOneWidget);
      expect(said('Priority: Urgent. Change it'), findsOneWidget);
      expect(find.text('Urgent'), findsOneWidget);
      expect(said(RegExp(r'^Stale: 16 days')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a cycle is picked from the notebook’s, today’s marked, and written by its name', (tester) async {
    await draw(tester, 'k3');
    await press(tester, said(RegExp(r'^Cycle: ')));
    expect(find.byKey(const ValueKey('cycle-sheet')), findsOneWidget);
    expect(find.text('2026-C45 (now)'), findsOneWidget);
    expect(find.text('2–15 Nov'), findsOneWidget);
    await press(tester, find.text('2026-C47'));
    expect(written.last, ('cycle', '2026-C47'));
    await press(tester, said(RegExp(r'^Cycle: ')));
    await press(tester, find.text('No cycle'));
    expect(written.last, ('cycle', null));
  });

  testWidgets('a milestone is picked from the milestone notes, written as a link; one its epic gives says so', (tester) async {
    await draw(tester, 'k3');
    // Its milestone is its epic's: no row of its own until More.
    expect(said(RegExp(r'^Milestone: ')), findsNothing);
    await press(tester, said(RegExp(r'^Blocked by, Milestone, Labels')));
    expect(said(RegExp(r'^Milestone: v2 launch · .*\(its epic’s\)')), findsOneWidget);
    await press(tester, said(RegExp(r'^Milestone: ')));
    expect(find.byKey(const ValueKey('milestone-sheet')), findsOneWidget);
    await press(tester, find.descendant(of: find.byType(SheetRow), matching: find.text('v2 launch')));
    expect(written.last, ('milestone', '[[v2 launch]]'));
  });

  testWidgets('a priority is picked from a ticket’s four, each its chip, and Urgent is written urgent', (tester) async {
    await draw(tester, 'k6');
    expect(find.text('Medium'), findsOneWidget);
    await press(tester, said(RegExp(r'^Priority: Medium')));
    expect(find.byKey(const ValueKey('priority-sheet')), findsOneWidget);
    await press(tester, find.byKey(const ValueKey('priority:urgent')));
    expect(written.last, ('priority', 'urgent'));
    await press(tester, said(RegExp(r'^Priority: ')));
    await press(tester, find.byKey(const ValueKey('priority:none')));
    expect(written.last, ('priority', null));
  });

  testWidgets('an epic says so, and how far its tickets are, by their points', (tester) async {
    await draw(tester, 'k1');
    expect(find.text('Epic'), findsOneWidget);
    expect(said('In this epic, 2 of 4 done · 5 of 18 points'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Simple mode the cycle and the milestone wait behind More, set or not', (tester) async {
    await draw(tester, 'k3', simple: true);
    expect(said(RegExp(r'^Cycle: ')), findsNothing);
    expect(said(RegExp(r'^Milestone: ')), findsNothing);
    await press(tester, said(RegExp(r'^Cycle, Blocked by, Milestone')));
    expect(said(RegExp(r'^Cycle: 2026-C43')), findsOneWidget);
  });

  testWidgets('without the library’s planning, a written cycle is its words and nothing is offered', (tester) async {
    await draw(tester, 'k3', planning: false);
    expect(find.textContaining('2026-C43'), findsOneWidget);
    expect(said(RegExp(r'^Cycle: ')), findsNothing);
    expect(find.text('Urgent'), findsNothing);
  });
}
