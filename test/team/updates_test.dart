// The Updates inbox (lib/team/updates.dart, lib/notes/notifications_drawer.dart; docs/TEAMSPACES.md, "Follow a doc
// and Updates"; Matt, 2026-10-31: "watching sends that page's changes to your Updates (the bell, as an inbox with
// filters: Mentions, Tickets, Docs, Team)"): which filter a row is under, the chips there are, the changes to the
// pages followed read from their versions (someone else's, since following began, not cleared), read and cleared kept
// per account on the device, and the drawer drawing both kinds of row under its chips.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/versions_log.dart';
import 'package:ghost_md/notes/notifications_drawer.dart';
import 'package:ghost_md/team/follow.dart';
import 'package:ghost_md/team/updates.dart';

import '../sidebar/support.dart';
import '../support/render.dart';

const NotificationOrg ghost = (id: 'o1', name: 'Ghost');
const int now = 1790000000000;

FeedNotification row(String id, String kind, {int ago = 60000}) => FeedNotification(id: id, rev: 1, kind: kind, at: now - ago, from: 'sam', org: ghost, body: const {'name': 'Ghost'}, blob: 'sealed');

Change change(String note, int n, {required String by, required int at, bool first = false}) =>
    Change(noteId: note, n: n, at: at, by: by, added: 2, removed: 1, peek: (kind: 'add', text: 'Ship the beta on Friday'), first: first);

Note note(String id, String body) => Note(id: id, body: body, createdAt: 0, updatedAt: 0);

void main() {
  setUpAll(loadAppFonts);

  group('the filters', () {
    test('each kind is under one filter besides All, or All alone', () {
      expect(filterOf(row('a', 'mention')), UpdatesFilter.mentions);
      expect(filterOf(row('b', 'ticket')), UpdatesFilter.tickets);
      expect(filterOf(row('c', 'ticket-digest')), UpdatesFilter.tickets);
      expect(filterOf(row('d', ticketRuleKind)), UpdatesFilter.tickets);
      expect(filterOf(row('e', 'page-expired')), UpdatesFilter.docs);
      for (final kind in serverKinds) {
        expect(filterOf(row('f', kind)), UpdatesFilter.team, reason: kind);
      }
      for (final kind in ['note-edited', 'summary-written', 'sync-conflict']) {
        expect(filterOf(row('g', kind)), isNull, reason: kind);
        expect(shownUnder(UpdatesFilter.all, row('g', kind)), isTrue);
      }
    });

    test('the chips are All and each filter with a row, once something of your own is there to filter to', () {
      expect(inboxFilters([row('a', 'member-joined'), row('b', 'note-edited')], const []), [UpdatesFilter.all]);
      expect(inboxFilters([row('a', 'member-joined'), row('b', 'mention')], const []), [UpdatesFilter.all, UpdatesFilter.mentions, UpdatesFilter.team]);
      final doc = DocUpdate(noteId: 'n', n: 2, title: 'Roadmap', by: 'sam', at: now);
      expect(inboxFilters([row('a', 'ticket')], [doc]), [UpdatesFilter.all, UpdatesFilter.tickets, UpdatesFilter.docs]);
    });
  });

  group('the changes to followed pages', () {
    test('are someone else’s, after following began, not cleared, newest first', () {
      final got = docUpdatesOf(
        changes: [
          change('road', 3, by: 'sam', at: now - 1000),
          change('road', 2, by: 'matt', at: now - 2000),
          change('road', 1, by: 'sam', at: now - 900000, first: true),
          change('spec', 4, by: 'ana', at: now - 500),
          change('other', 9, by: 'sam', at: now),
          change('spec', 3, by: 'me', at: now - 600),
        ],
        followed: {'road', 'spec'},
        since: {'road': now - 600000, 'spec': now - 600000},
        me: 'Matt',
        titles: {'road': 'Roadmap', 'spec': 'Spec'},
      );
      expect([for (final u in got) u.key], ['spec:4', 'road:3'], reason: 'not mine, not before following, not an unfollowed page');
      expect(got.last.sentence, 'sam edited Roadmap · 3 lines changed');
      expect(got.last.peek, 'Ship the beta on Friday');
      expect(docUpdatesOf(changes: [change('road', 3, by: 'sam', at: now)], followed: {'road'}, since: const {}, me: 'matt', titles: const {}), isEmpty, reason: 'no word of when following began: none yet');
      expect(docUpdatesOf(changes: [change('road', 3, by: 'sam', at: now)], followed: {'road'}, since: {'road': 0}, me: 'matt', titles: const {}, hidden: {'road:3'}), isEmpty);
      expect(const DocUpdate(noteId: 'r', n: 1, title: 'Roadmap', by: 'sam', at: 0, first: true).sentence, 'sam created Roadmap');
    });

    test('the feed finds the followed team pages, starts each from when it saw it, and keeps read and cleared per account', () {
      var clock = now - 10000;
      final memory = MemoryStored();
      final notes = ValueNotifier<List<Note>>([
        note('road', withFollowing('# Roadmap\n', 'matt', true)),
        note('mine', withFollowing('# Mine\n', 'matt', true)),
        note('spec', '# Spec\n'),
      ]);
      final changes = ValueNotifier<ChangesRead>(const ChangesRead());
      final watched = <List<String>>[];
      DocUpdatesFeed make() => DocUpdatesFeed(notes: notes, changes: changes, watch: watched.add, me: () => 'matt', team: (id) => id != 'mine', stored: memory, now: () => clock);
      final feed = make();
      expect(feed.followed, ['road'], reason: 'a personal note is no team page');
      expect(watched.last, ['road']);
      clock = now;
      changes.value = ChangesRead(changes: [change('road', 1, by: 'sam', at: now - 20000), change('road', 2, by: 'sam', at: now - 5000)]);
      expect([for (final u in feed.value) u.key], ['road:2'], reason: 'the version from before it was seen followed is history');
      expect(feed.value.single.title, 'Roadmap');
      expect(feed.unread, 1);
      feed.markRead(feed.value.single);
      expect(feed.unread, 0);
      changes.value = ChangesRead(changes: [...changes.value.changes, change('road', 3, by: 'ana', at: now - 100)]);
      expect(feed.unread, 1);
      feed.markAllRead();
      expect(feed.unread, 0);
      feed.hide(['road:2']);
      expect([for (final u in feed.value) u.key], ['road:3']);
      // Followed later: another page joins, from then on.
      notes.value = [...notes.value.where((n) => n.id != 'spec'), note('spec', withFollowing('# Spec\n', 'matt', true))];
      expect(feed.followed, ['road', 'spec']);
      feed.dispose();
      // The device remembers: a feed made again reads the same.
      final again = make();
      changes.value = ChangesRead(changes: [change('road', 2, by: 'sam', at: now - 5000), change('road', 3, by: 'ana', at: now - 100)]);
      expect([for (final u in again.value) u.key], ['road:3']);
      expect(again.unread, 0);
      again.dispose();
    });
  });

  group('the inbox', () {
    final docs = [
      const DocUpdate(noteId: 'road', n: 3, title: 'Roadmap', by: 'ana', at: now - 2 * 60000, added: 1, peek: 'Ship the beta on Friday'),
    ];
    final rows = [row('m1', 'mention', ago: 60000), row('t1', 'ticket', ago: 3 * 60000), row('j1', 'member-joined', ago: 4 * 60000), row('e1', 'note-edited', ago: 5 * 60000)];

    Future<List<String>> show(WidgetTester tester, {Set<String> read = const {}}) async {
      final said = <String>[];
      await pumpPage(
        tester,
        PageUnder(
          children: [
            NotificationsDrawer(
              notifications: rows,
              memberOf: const {'o1'},
              now: now,
              docs: docs,
              docRead: (u) => read.contains(u.key),
              onDocRead: (u) => said.add('read ${u.key}'),
              onDocsAllRead: () => said.add('all docs read'),
              onDocsHide: (keys) => said.add('hide ${keys.join(',')}'),
              onMarkAllRead: () => said.add('all read'),
              onClose: () => said.add('close'),
              onOpenNote: (id, at) => said.add('note $id'),
              onOpenOrganization: (id) => said.add('org $id'),
              onAccount: () {},
            ),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      return said;
    }

    Finder feedRow(String id) => find.byKey(ValueKey('notification-$id'));
    final Finder docRow = find.byKey(const ValueKey('doc-update-road:3'));

    testWidgets('has a chip for All, Mentions, Tickets, Docs and Team, each showing only its rows', (tester) async {
      await show(tester);
      for (final name in ['all', 'mentions', 'tickets', 'docs', 'team']) {
        expect(find.byKey(ValueKey('filter-$name')), findsOneWidget, reason: name);
      }
      expect(docRow, findsOneWidget);
      expect(find.text('ana edited Roadmap · 1 line changed'), findsOneWidget);
      // Newest first, the doc between the mention and the ticket.
      expect(tester.getTopLeft(feedRow('m1')).dy, lessThan(tester.getTopLeft(docRow).dy));
      expect(tester.getTopLeft(docRow).dy, lessThan(tester.getTopLeft(feedRow('t1')).dy));
      Future<void> only(String name) async {
        await tester.ensureVisible(find.byKey(ValueKey('filter-$name')));
        await tester.pump();
        await tester.tap(find.byKey(ValueKey('filter-$name')));
        await tester.pump(const Duration(milliseconds: 300));
      }

      await only('docs');
      expect(docRow, findsOneWidget);
      for (final id in ['m1', 't1', 'j1', 'e1']) {
        expect(feedRow(id), findsNothing, reason: id);
      }
      await only('tickets');
      expect(feedRow('t1'), findsOneWidget);
      expect(docRow, findsNothing);
      await only('team');
      expect(feedRow('j1'), findsOneWidget);
      expect(feedRow('e1'), findsNothing);
      await only('mentions');
      expect(feedRow('m1'), findsOneWidget);
      await only('all');
      expect(feedRow('e1'), findsOneWidget);
      await away(tester);
    });

    testWidgets('a doc row unread is counted and marked; pressed, it is read and opens its page', (tester) async {
      final said = await show(tester);
      expect(find.descendant(of: docRow, matching: find.byKey(const ValueKey('doc-update-unread'))), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('notifications-count')), matching: find.text('5')), findsOneWidget);
      await tester.tap(find.text('Mark all read'));
      await tester.pump();
      expect(said, containsAll(['all read', 'all docs read']));
      await tester.tap(docRow);
      await tester.pump(const Duration(milliseconds: 300));
      expect(said, containsAllInOrder(['read road:3', 'close', 'note road']));
      await away(tester);
    });

    testWidgets('a doc row read has no dot and is not counted', (tester) async {
      await show(tester, read: {'road:3'});
      expect(find.descendant(of: docRow, matching: find.byKey(const ValueKey('doc-update-unread'))), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('notifications-count')), matching: find.text('4')), findsOneWidget);
      await away(tester);
    });
  });
}
