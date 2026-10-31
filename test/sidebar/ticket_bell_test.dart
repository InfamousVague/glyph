// A ticket's watchers in the bell, the morning's digest and its page, and its settings (Matt, 2026-10-31): a ticket's
// row reads who changed what and offers Unwatch; the digest's row opens its page, which lists each ticket a tap away;
// Settings › Notifications › Ticket digest sets it on, its time and its note. With pictures, on a phone and a desktop,
// light and dark, into build/feature-shots/tickets-team/ under --update-goldens.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/ticket_digest.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/notes/notifications_drawer.dart';
import 'package:ghost_md/notes/ticket_digest_sheet.dart';
import 'package:ghost_md/settings/panes/ticket_digest_section.dart';
import 'package:glacier/glacier.dart';

import '../support/feature_shot.dart';
import '../support/render.dart';
import 'support.dart';

const NotificationOrg ghost = (id: 'o1', name: 'Ghost');
const int now = 1790000000000;

final List<FeedNotification> rows = [
  const FeedNotification(id: 't1', rev: 9, kind: 'ticket', at: now - 3 * 60000, from: 'sam', org: ghost, body: {'name': 'Ghost', 'generation': 1}, blob: 'sealed'),
  const FeedNotification(id: 't2', rev: 8, kind: 'ticket', at: now - 40 * 60000, from: 'ana', org: ghost, body: {'name': 'Ghost', 'generation': 1}, blob: 'sealed'),
  const FeedNotification(id: 'd1', rev: 7, kind: 'ticket-digest', at: now - 3600000, blob: 'sealed'),
  const FeedNotification(id: 'm1', rev: 6, kind: 'mention', at: now - 7200000, from: 'sam', org: ghost, body: {'name': 'Ghost', 'generation': 1}, blob: 'sealed'),
];

NotificationDetails? opened(FeedNotification n) => switch (n.id) {
      't1' => NotificationDetails.fromJson({'kind': 'ticket', 'noteId': 'n12', 'title': 'GHO-12 Fix the login loop', 'by': 'sam', 'first': 'In progress → In review · Due 2026-11-06', 'what': 'changed'}),
      't2' => NotificationDetails.fromJson({'kind': 'ticket', 'noteId': 'n9', 'title': 'GHO-9 Book the venue', 'by': 'ana', 'first': 'To do → Done', 'what': 'closed'}),
      'd1' => NotificationDetails.fromJson({'kind': 'ticket-digest', 'noteId': digestNoteId, 'title': '2 due today · 1 overdue', 'first': 'GHO-2 Book the venue, GHO-1 Ship the beta'}),
      'm1' => NotificationDetails.fromJson({'kind': 'mention', 'noteId': 'n1', 'title': 'Launch plan', 'by': 'sam', 'first': 'Ask @matt to look', 'at': 'line:3'}),
      _ => null,
    };

const TicketDigest digest = TicketDigest(
  day: '2026-10-31',
  dueToday: [DigestItem(noteId: 'n1', key: 'GHO-1', title: 'Ship the beta', due: '2026-10-31'), DigestItem(noteId: 'me1', key: 'ME-1', title: 'Renew the passport', due: '2026-10-31')],
  overdue: [DigestItem(noteId: 'n2', key: 'GHO-2', title: 'Book the venue', due: '2026-10-28')],
  blocked: [DigestItem(noteId: 'n6', key: 'GHO-6', title: 'Launch', waitsOn: ['GHO-2'])],
);

void main() {
  setUpAll(loadAppFonts);

  Future<List<String>> show(WidgetTester tester, {Size size = const Size(390, 844), String theme = 'light'}) async {
    final said = <String>[];
    await pumpPage(
      tester,
      PageUnder(
        children: [
          NotificationsDrawer(
            notifications: rows,
            memberOf: const {'o1'},
            detailsOf: opened,
            now: now,
            onClose: () => said.add('close'),
            onOpenNote: (id, at) => said.add('note $id'),
            onOpenOrganization: (id) => said.add('org $id'),
            onAccount: () {},
            onUnwatch: (id) => said.add('unwatch $id'),
          ),
        ],
      ),
      size: size,
      theme: theme,
    );
    await tester.pump(const Duration(milliseconds: 400));
    return said;
  }

  testWidgets('a ticket watched reads who changed what, and Unwatch is on its row', (tester) async {
    final said = await show(tester);
    expect(find.text('sam changed GHO-12 Fix the login loop'), findsOneWidget);
    expect(find.text('In progress → In review · Due 2026-11-06'), findsOneWidget);
    expect(find.text('ana closed GHO-9 Book the venue'), findsOneWidget);
    expect(find.text('Your tickets today: 2 due today · 1 overdue'), findsOneWidget);
    expect(find.byKey(const ValueKey('unwatch-t1')), findsOneWidget);
    expect(find.byKey(const ValueKey('unwatch-m1')), findsNothing, reason: 'a mention is not a ticket watched');
    await tester.tap(find.byKey(const ValueKey('unwatch-t1')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(said, ['unwatch n12']);
    await tester.tap(find.text('Your tickets today: 2 due today · 1 overdue'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(said.last, 'note $digestNoteId', reason: 'the root opens the digest page for it');
    await away(tester);
  });

  testWidgets('the digest’s page lists each ticket under its part, a tap away', (tester) async {
    final opened = <String>[];
    var closed = false;
    await pumpPage(tester, PageUnder(children: [TicketDigestSheet(digest: digest, onOpen: opened.add, onClose: () => closed = true)]));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Your tickets today'), findsWidgets);
    expect(find.text('GHO-2 Book the venue'), findsOneWidget);
    expect(find.text('Waits on GHO-2'), findsOneWidget);
    await tester.tap(find.text('GHO-1 Ship the beta'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(opened, ['n1']);
    expect(closed, isTrue);
    await away(tester);
  });

  testWidgets('Settings › Notifications › Ticket digest: on at 8:30, a time picked, and its note', (tester) async {
    final store = PreferencesStore(keepAfter: Duration.zero);
    await pumpPage(tester, PageUnder(children: [TicketDigestSection(store: store)]));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('8:30'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('digest-time')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('digest-time:7:0')));
    await tester.pump(const Duration(milliseconds: 500));
    expect((digestSettingsOf(store.value).hour, digestSettingsOf(store.value).minute), (7, 0));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('digest-note')), matching: find.byType(GlacierSwitch)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(digestSettingsOf(store.value).note, isTrue);
    await away(tester);
  });

  for (final theme in ['light', 'dark']) {
    for (final (size, where) in [(const Size(390, 844), 'phone'), (const Size(1280, 800), 'desktop')]) {
      testWidgets('the bell with a ticket watched and the morning’s digest, $where, $theme', (tester) async {
        await show(tester, size: size, theme: theme);
        await featureShot(tester, 'tickets-team', 'bell-$where-$theme');
        await away(tester);
      });

      testWidgets('the digest’s page, $where, $theme', (tester) async {
        await pumpPage(tester, PageUnder(children: [TicketDigestSheet(digest: digest, onOpen: (_) {}, onClose: () {})]), size: size, theme: theme);
        await tester.pump(const Duration(milliseconds: 500));
        await featureShot(tester, 'tickets-team', 'digest-$where-$theme');
        await away(tester);
      });

      testWidgets('the digest’s settings, $where, $theme', (tester) async {
        await pumpPage(tester, PageUnder(children: [TicketDigestSection(store: PreferencesStore(keepAfter: Duration.zero))]), size: size, theme: theme);
        await tester.pump(const Duration(milliseconds: 300));
        await featureShot(tester, 'tickets-team', 'digest-settings-$where-$theme');
        await away(tester);
      });
    }
  }
}
