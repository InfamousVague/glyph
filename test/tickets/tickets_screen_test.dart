import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/front_matter.dart' show frontMatterValue;
import 'package:ghost_md/core/query/query.dart' show queryMe;
import 'package:ghost_md/tickets/ui/tickets_screen.dart';

import 'screen_support.dart';

/// My tickets and Triage drawn (lib/tickets/ui/tickets_screen.dart): the inbox's groups on a phone and a wide window,
/// a status changed from a row, the triage keys and the swipes that stand in for them on a phone.
void main() {
  setUp(() => queryMe = const ['matt']);
  tearDown(() => queryMe = const []);

  Finder text(String words) => find.text(words);

  /// A finger across [row], a step at a time as a finger moves.
  Future<void> swipe(WidgetTester tester, Finder row, double step) async {
    final gesture = await tester.startGesture(tester.getCenter(row));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(step, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  group('My tickets', () {
    for (final (name, size) in [('a phone', const Size(390, 844)), ('a wide window', const Size(1180, 820))]) {
      testWidgets('on $name: the groups in order, each ticket with its key, its place and its labels', (tester) async {
        final desk = Desk();
        await pumpTickets(tester, desk, size: size);
        final groups = [for (final key in ['overdue', 'today', 'thisWeek', 'later', 'noDate']) find.byKey(ValueKey('inbox-group-$key'))];
        for (final group in groups) {
          expect(group, findsOneWidget);
        }
        final tops = [for (final group in groups) tester.getTopLeft(group).dy];
        expect(tops, [...tops]..sort());
        expect(text('Refund webhook'), findsOneWidget);
        expect(text('HelloTrade · Payments'), findsOneWidget);
        expect(find.byKey(const ValueKey('label-chip-bug')), findsNWidgets(2));
        expect(text('Card form focus'), findsNothing);
        expect(text('6 tickets · 1 overdue'), findsOneWidget);
        // The ticket in This week is under its heading and over Later's.
        expect(tester.getTopLeft(text('Pricing page')).dy, inExclusiveRange(tops[2], tops[3]));
      });
    }

    testWidgets('a row opens its ticket, and its status mark sets the status in a sheet', (tester) async {
      final desk = Desk();
      await pumpTickets(tester, desk);
      await tester.tap(text('Confirm page copy'));
      expect(desk.opened, ['wait2']);
      await tester.tap(find.byKey(const ValueKey('ticket-status-wait2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('status:In progress')));
      await tester.pumpAndSettle();
      expect(frontMatterValue(desk.bodies['wait2']!, 'status'), 'In progress');
    });
  });

  group('Triage', () {
    Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    testWidgets('J and K move the current ticket, T is done triaging and takes it out', (tester) async {
      final desk = Desk();
      await pumpTickets(tester, desk, page: TicketsPage.triage, size: const Size(1180, 820));
      expect(find.byKey(const ValueKey('triage-keys')), findsOneWidget);
      // The first is current: its Done is drawn.
      expect(find.byKey(const ValueKey('triage-done-wait4')), findsOneWidget);
      await key(tester, LogicalKeyboardKey.keyJ);
      expect(find.byKey(const ValueKey('triage-done-pay3')), findsOneWidget);
      await key(tester, LogicalKeyboardKey.keyJ);
      await key(tester, LogicalKeyboardKey.keyK);
      expect(find.byKey(const ValueKey('triage-done-pay3')), findsOneWidget);
      await key(tester, LogicalKeyboardKey.keyT);
      expect(frontMatterValue(desk.bodies['pay3']!, 'triaged'), '2026-10-28');
      expect(find.byKey(const ValueKey('triage-row-pay3')), findsNothing);
      // The next one is current where it stood.
      expect(find.byKey(const ValueKey('triage-done-loose1')), findsOneWidget);
    });

    testWidgets('A assigns, P sets the priority, L a label, S the status, each in its sheet', (tester) async {
      final desk = Desk();
      await pumpTickets(tester, desk, page: TicketsPage.triage, size: const Size(1180, 820));
      await key(tester, LogicalKeyboardKey.keyA);
      await tester.tap(find.byKey(const ValueKey('person:Sam')));
      await tester.pumpAndSettle();
      expect(frontMatterValue(desk.bodies['wait4']!, 'assignee'), 'Sam');

      await key(tester, LogicalKeyboardKey.keyP);
      await tester.tap(find.byKey(const ValueKey('priority:high')));
      await tester.pumpAndSettle();
      expect(frontMatterValue(desk.bodies['wait4']!, 'priority'), 'high');

      await key(tester, LogicalKeyboardKey.keyL);
      await tester.enterText(find.byType(EditableText).first, 'spam');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('label-make')));
      await tester.pumpAndSettle();
      expect(frontMatterValue(desk.bodies['wait4']!, 'labels'), '[spam]');
      // Put away by a tap beside it, and the keys are the list's again.
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      await key(tester, LogicalKeyboardKey.keyS);
      await tester.tap(find.byKey(const ValueKey('status:In progress')));
      await tester.pumpAndSettle();
      expect(frontMatterValue(desk.bodies['wait4']!, 'status'), 'In progress');
      // Still waiting: nobody said it was looked at.
      expect(find.byKey(const ValueKey('triage-row-wait4')), findsOneWidget);
    });

    testWidgets('D closes it as a duplicate of a ticket picked, and E opens it', (tester) async {
      final desk = Desk();
      await pumpTickets(tester, desk, page: TicketsPage.triage, size: const Size(1180, 820));
      await key(tester, LogicalKeyboardKey.keyE);
      expect(desk.opened, ['wait4']);
      await key(tester, LogicalKeyboardKey.keyD);
      await tester.enterText(find.byType(EditableText).first, 'WAIT-1');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick-ticket:WAIT-1')));
      await tester.pumpAndSettle();
      final body = desk.bodies['wait4']!;
      expect(frontMatterValue(body, 'duplicate-of'), '[[WAIT-1]]');
      expect(isDone(body), isTrue);
      expect(find.byKey(const ValueKey('triage-row-wait4')), findsNothing);
    });

    testWidgets('narrowed to a notebook, it lists that notebook’s alone', (tester) async {
      final desk = Desk();
      await pumpTickets(tester, desk, page: TicketsPage.triage, size: const Size(1180, 820));
      await tester.tap(find.byKey(const ValueKey('triage-in-Payments')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('triage-row-pay3')), findsOneWidget);
      expect(find.byKey(const ValueKey('triage-row-wait4')), findsNothing);
    });

    testWidgets('on a phone, a swipe right is done and a swipe left offers the actions; the keys go unsaid', (tester) async {
      final desk = Desk();
      await pumpTickets(tester, desk, page: TicketsPage.triage);
      expect(find.byKey(const ValueKey('triage-keys')), findsNothing);
      await swipe(tester, find.byKey(const ValueKey('triage-row-wait4')), -22);
      expect(find.byKey(const ValueKey('triage-act-assign')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('triage-act-done')));
      await tester.pumpAndSettle();
      expect(frontMatterValue(desk.bodies['wait4']!, 'triaged'), '2026-10-28');
      await swipe(tester, find.byKey(const ValueKey('triage-row-pay3')), 22);
      expect(frontMatterValue(desk.bodies['pay3']!, 'triaged'), '2026-10-28');
      expect(find.byKey(const ValueKey('triage-row-pay3')), findsNothing);
    });

    testWidgets('in simple mode the keys still work but go unsaid', (tester) async {
      final desk = Desk();
      await pumpTickets(tester, desk, page: TicketsPage.triage, size: const Size(1180, 820), simple: true);
      expect(find.byKey(const ValueKey('triage-keys')), findsNothing);
      await key(tester, LogicalKeyboardKey.keyT);
      expect(frontMatterValue(desk.bodies['wait4']!, 'triaged'), '2026-10-28');
    });
  });
}
