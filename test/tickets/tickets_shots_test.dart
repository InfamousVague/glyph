import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/properties.dart' show defaultStatuses;
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/editor/queries/queries.dart';
import 'package:ghost_md/editor/tickets/ticket_panel.dart' show TicketOptions;
import 'package:ghost_md/tickets/ui/bulk_bar.dart';
import 'package:ghost_md/tickets/ui/tickets_screen.dart';

import '../editor/queries/support.dart' as query;
import '../editor/tickets/support.dart' as panel;
import '../support/feature_shot.dart';
import '../support/render.dart';
import 'screen_support.dart';
import 'support.dart' show notes;

/// Pictures of the tickets queue (Matt, 2026-10-31): My tickets and Triage on a phone and a wide window, light and
/// dark; a triage ticket's actions and the label picker; a board's tickets picked with the bar over them; and a
/// ticket's labels in its panel. Written to `build/feature-shots/tickets-queue/*.png` under `--update-goldens`, to
/// be looked at, not held as goldens.
const String folder = 'tickets-queue';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => queryMe = const ['matt']);
  tearDown(() => queryMe = const []);

  Future<void> done(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  const phone = Size(390, 844);
  const wide = Size(1180, 820);

  for (final theme in ['light', 'dark']) {
    testWidgets('my tickets on a phone, $theme', (tester) async {
      await pumpTickets(tester, Desk(), theme: theme, shadows: true);
      await featureShot(tester, folder, 'my-tickets-phone-$theme');
      await done(tester);
    });

    testWidgets('triage on a wide window, $theme', (tester) async {
      await pumpTickets(tester, Desk(), page: TicketsPage.triage, size: wide, theme: theme, shadows: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
      await featureShot(tester, folder, 'triage-wide-$theme');
      await done(tester);
    });
  }

  testWidgets('my tickets on a wide window', (tester) async {
    await pumpTickets(tester, Desk(), size: wide, shadows: true);
    await featureShot(tester, folder, 'my-tickets-wide-light');
    await done(tester);
  });

  testWidgets('triage on a phone, and a ticket’s actions from a swipe to the left', (tester) async {
    await pumpTickets(tester, Desk(), page: TicketsPage.triage, size: phone, shadows: true);
    await featureShot(tester, folder, 'triage-phone-light');
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('triage-row-pay3'))));
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(14, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await featureShot(tester, folder, 'triage-phone-swiping', beats: 1);
    await gesture.up();
    await tester.pumpAndSettle();
    final left = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('triage-row-wait4'))));
    for (var i = 0; i < 10; i++) {
      await left.moveBy(const Offset(-22, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await left.up();
    await tester.pumpAndSettle();
    await featureShot(tester, folder, 'triage-phone-actions');
    await done(tester);
  });

  testWidgets('the label picker from L', (tester) async {
    await pumpTickets(tester, Desk(), page: TicketsPage.triage, size: wide, shadows: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'sp');
    await tester.pumpAndSettle();
    await featureShot(tester, folder, 'triage-label-picker');
    await done(tester);
  });

  Future<void> board(WidgetTester tester, String lines, {double screen = 1180, String theme = 'light'}) async {
    await query.pumpQueries(
      tester,
      '# This week\n\n```query\n$lines\n```\n',
      screen: screen,
      today: '2026-10-28',
      theme: theme,
      shadows: true,
      options: QueryOptions(
        notes: () => notes,
        noteId: 'here',
        open: (_, _) {},
        write: (_, _) {},
        bulk: BulkActions(edit: (_, _) async {}, move: (_, _) async {}, trash: (_) {}, notebooks: () => const [], labels: () => const ['bug', 'ui']),
        labelColours: (id) => id.startsWith('wait') ? const {'bug': 'amber', 'ui': 'purple'} : const {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> commandTap(WidgetTester tester, String title) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(find.text(title).first, kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  for (final theme in ['light', 'dark']) {
    testWidgets('a board grouped by label, two cards picked and the bar over them, $theme', (tester) async {
      await board(tester, 'from: tickets\nwhere: labels is not empty\ngroup: labels\nshow: board', theme: theme);
      await commandTap(tester, 'Card form focus');
      await commandTap(tester, 'Confirm page copy');
      await featureShot(tester, folder, 'board-by-label-picked-$theme');
      await done(tester);
    });
  }

  testWidgets('a table of tickets with their labels, three picked', (tester) async {
    await board(tester, 'from: tickets\nwhere: status != Done\ncolumns: id, title, status, assignee, labels, due\nsort: id\nshow: table');
    await commandTap(tester, 'Refund webhook');
    await commandTap(tester, 'Card form focus');
    await commandTap(tester, 'Invite emails bounce');
    await featureShot(tester, folder, 'table-picked');
    await done(tester);
  });

  testWidgets('a list on a phone, two held and picked, the bar at the foot', (tester) async {
    await board(tester, 'from: tickets\nwhere: assignee = me and checked = no\nsort: due\nshow: list', screen: 390);
    final gesture = await tester.startGesture(tester.getCenter(find.text('Refund webhook')));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pricing page'));
    await tester.pumpAndSettle();
    await featureShot(tester, folder, 'list-phone-picked');
    await done(tester);
  });

  testWidgets('a ticket’s labels in its panel', (tester) async {
    await panel.pumpTickets(
      tester,
      '---\ntype: ticket\nid: WAIT-1\nstatus: In progress\nassignee: Matt\npriority: high\ndue: 2026-10-26\nlabels: [bug, email, signup]\ncomponent: Waitlist\n---\n# Invite emails bounce\n\nThe welcome mail is refused by two providers.\n',
      shadows: true,
      today: '2026-10-28',
      options: TicketOptions(
        statuses: () => defaultStatuses,
        people: () => const ['Matt', 'Sam'],
        choices: () => const <TicketChoice>[],
        find: (_) => null,
        open: (_) {},
        labels: () => const ['bug', 'ui', 'email', 'signup'],
        labelColours: () => const {'bug': 'amber', 'signup': 'teal'},
      ),
    );
    await featureShot(tester, folder, 'panel-labels');
    await tester.tap(panel.said('Change labels'));
    await tester.pumpAndSettle();
    await featureShot(tester, folder, 'panel-label-picker');
    await done(tester);
  });
}
