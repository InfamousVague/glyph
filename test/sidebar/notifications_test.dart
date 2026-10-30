import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/core/preferences.dart' show NotificationPrefs;

/// The kinds table as words (core/notifications.dart): `core/notifications/kinds.test.ts` and `kindHues.test.ts` case
/// for case, then the rules a list of rows asks, which the web tests through its feed
/// (`core/notifications/feed.test.ts`).
FeedNotification row(String kind, {String id = 'x', int rev = 1, int at = 1, int? readAt, bool hidden = false, String? from, NotificationOrg? org, Map<String, Object?>? body, String? state}) =>
    FeedNotification(id: id, rev: rev, kind: kind, at: at, readAt: readAt, hidden: hidden, from: from, org: org, body: body, state: state);

const NotificationOrg ghost = (id: 'o1', name: 'Ghost');

void main() {
  group('the kinds', () {
    test('are the service’s nine, the account’s nine and a member’s mention, each in one category', () {
      expect(kinds, hasLength(19));
      expect(serverKinds, hasLength(9));
      expect(selfKinds, hasLength(9));
      expect(memberKinds, ['mention']);
      // A mention and a verified page run out are the person's own business, with no switch (Matt, 2026-10-30).
      expect(categoryOf('mention'), 'mentions');
      expect(categoryOf('page-expired'), 'mentions');
      expect(categories, ['team', 'claude', 'summaries', 'conflicts']);
      expect(categoryOf('invite'), 'invites');
      expect(serverKinds.where((k) => k != 'invite').every((k) => categoryOf(k) == 'team'), isTrue);
      expect(['note-created', 'note-edited', 'note-appended', 'journal-entry', 'rule-added'].every((k) => categoryOf(k) == 'claude'), isTrue);
      expect(categoryOf('summary-written'), 'summaries');
      expect(categoryOf('sync-conflict'), 'conflicts');
      expect(categoryOf('form-answer'), 'invites', reason: 'an answer to a form is shown as an invitation is, with no switch');
      expect(isKind('invite'), isTrue);
      expect(isKind('poke'), isFalse);
      expect(isKind(7), isFalse);
      expect(isSelfKind('note-edited'), isTrue);
      expect(isSelfKind('invite'), isFalse);
    });

    test('read a sealed payload only in the shape of a self kind', () {
      expect(NotificationDetails.fromJson({'kind': 'summary-written', 'noteId': 'n', 'title': 'T'}), isNotNull);
      expect(NotificationDetails.fromJson({'kind': 'invite', 'noteId': 'n', 'title': 'T'}), isNull);
      expect(NotificationDetails.fromJson({'kind': 'note-edited', 'title': 'T'}), isNull);
      expect(NotificationDetails.fromJson(null), isNull);
      final edit = NotificationDetails.fromJson({'kind': 'note-edited', 'noteId': 'n', 'title': 'T', 'by': 'Claude', 'added': 2, 'removed': 1, 'first': '- pack', 'at': 'l3'})!;
      expect([edit.by, edit.added, edit.removed, edit.first, edit.at], ['Claude', 2, 1, '- pack', 'l3']);
    });

    /// Matt: "color code different notification icons so they're easier to match at first sight".
    test('each wear one of the app’s hues, by what the news is', () {
      for (final kind in kinds) {
        expect(['ember', 'amber', 'moss', 'sea', 'violet', 'rose'], contains(kindHues[kind]), reason: kind);
      }
      expect(kindHues['member-joined'], kindHues['invite-accepted']);
      expect(kindHues['member-left'], kindHues['member-removed']);
      expect(kindHues['member-joined'], isNot(kindHues['member-left']));
      expect(kindHues['invite'], isNot(kindHues['sync-conflict']));
    });
  });

  group('the sentences', () {
    test('say what the service did about an organization, by whom', () {
      expect(sentenceOf(row('invite', from: 'sam', org: ghost, body: {'name': 'Ghost'}, state: 'pending')), 'sam invited you to Ghost');
      expect(sentenceOf(row('invite-accepted', from: 'sam', org: ghost)), 'sam accepted your invitation to Ghost');
      expect(sentenceOf(row('invite-declined', from: 'sam', org: ghost)), 'sam declined your invitation to Ghost');
      expect(sentenceOf(row('member-joined', from: 'sam', org: ghost)), 'sam joined Ghost');
      expect(sentenceOf(row('member-left', from: 'sam', org: ghost, body: {'name': 'Ghost'})), 'sam left Ghost');
      expect(sentenceOf(row('member-removed', from: 'sam', org: ghost, body: {'handle': 'kim'})), 'sam removed kim from Ghost');
      expect(sentenceOf(row('member-removed', from: 'sam', body: {'name': 'Ghost'})), 'sam removed you from Ghost');
      expect(sentenceOf(row('role-changed', from: 'sam', org: ghost, body: {'role': 'admin'})), 'sam made you an admin of Ghost');
      expect(sentenceOf(row('role-changed', from: 'sam', org: ghost, body: {'role': 'owner'})), 'sam made you the owner of Ghost');
      expect(sentenceOf(row('role-changed', from: 'sam', org: ghost, body: {'role': 'member'})), 'sam made you a member of Ghost');
      expect(sentenceOf(row('org-renamed', from: 'sam', org: ghost, body: {'name': 'Ghost', 'was': 'Boo'})), 'sam renamed Boo to Ghost');
      expect(sentenceOf(row('org-deleted', from: 'sam', body: {'name': 'Ghost'})), 'sam deleted Ghost');
    });

    test('say "Someone" for an account that is gone, and fall back to the name the row remembers', () {
      expect(sentenceOf(row('invite', body: {'name': 'Ghost'})), 'Someone invited you to Ghost');
      expect(sentenceOf(row('member-joined', org: ghost)), 'Someone joined Ghost');
      // The live name wins while the reader is a member; the body's when they are not; and then nothing.
      expect(sentenceOf(row('org-renamed', from: 'sam', org: (id: 'o1', name: 'Spectre'), body: {'name': 'Ghost', 'was': 'Boo'})), 'sam renamed Boo to Spectre');
      expect(sentenceOf(row('member-left', from: 'sam')), 'sam left an organization');
    });

    test('say what Claude did, with the note’s title once the seal is open and by kind before', () {
      NotificationDetails about(String kind, {String title = 'Trip to Lisbon', String by = 'Claude', int? added, int? removed, String? first, String? at, int? lines, String? journal}) =>
          NotificationDetails(kind: kind, noteId: 'n1', title: title, by: by, added: added, removed: removed, first: first, at: at, lines: lines, journal: journal);
      expect(sentenceOf(row('note-created'), about('note-created')), 'Claude created Trip to Lisbon');
      expect(sentenceOf(row('note-created')), 'Claude created a note');
      expect(sentenceOf(row('note-edited'), about('note-edited', added: 2, removed: 0, first: '- pack', at: 'l3')), 'Claude edited Trip to Lisbon · 2 lines changed');
      expect(sentenceOf(row('note-edited'), about('note-edited', added: 1, removed: 0, first: '', at: '')), 'Claude edited Trip to Lisbon · 1 line changed');
      expect(sentenceOf(row('note-edited')), 'Claude edited a note');
      expect(sentenceOf(row('note-appended'), about('note-appended', lines: 3, first: '- eggs')), 'Claude added 3 lines to Trip to Lisbon');
      expect(sentenceOf(row('note-appended')), 'Claude added to a note');
      expect(sentenceOf(row('journal-entry'), about('journal-entry', title: 'Journal', journal: 'Journal', first: 'A fine day')), 'Claude wrote an entry in Journal');
      expect(sentenceOf(row('journal-entry')), 'Claude wrote a journal entry');
      expect(sentenceOf(row('rule-added'), about('rule-added', title: 'Claude rules', first: 'Always be brief')), 'Claude added a rule to Claude rules');
      expect(sentenceOf(row('rule-added')), 'Claude added a rule');
      // The hosted server's name rides in `by`.
      expect(sentenceOf(row('note-created'), about('note-created', by: 'Claude (Mac)')), 'Claude (Mac) created Trip to Lisbon');
      // The kind inside the seal is the one trusted.
      expect(sentenceOf(row('note-created'), about('note-appended', lines: 1, first: 'x')), 'Claude added 1 line to Trip to Lisbon');
    });

    test('say what the app did for itself', () {
      expect(sentenceOf(row('summary-written'), const NotificationDetails(kind: 'summary-written', noteId: 'n1', title: 'Standup')), 'A meeting was written up: Standup');
      expect(sentenceOf(row('summary-written')), 'A meeting was written up');
      expect(sentenceOf(row('form-answer'), const NotificationDetails(kind: 'form-answer', noteId: 'n2', title: 'Crash on launch', by: 'Report a bug')), 'A new answer to Report a bug: Crash on launch');
      expect(sentenceOf(row('form-answer')), 'A form was answered');
      expect(sentenceOf(row('sync-conflict'), const NotificationDetails(kind: 'sync-conflict', noteId: 'n1', title: 'Trip to Lisbon')), 'Trip to Lisbon was kept twice: both devices had changed it');
      expect(sentenceOf(row('sync-conflict')), 'A note was kept twice');
    });

    test('carry the first changed line under the sentence, for the kinds that have one', () {
      expect(detailOf(const NotificationDetails(kind: 'note-edited', noteId: 'n1', title: 'T', by: 'Claude', added: 1, removed: 1, first: '- pack', at: 'l3')), '- pack');
      expect(detailOf(const NotificationDetails(kind: 'note-appended', noteId: 'n1', title: 'T', by: 'Claude', lines: 1, first: '')), isNull);
      expect(detailOf(const NotificationDetails(kind: 'summary-written', noteId: 'n1', title: 'T')), isNull);
      expect(detailOf(null), isNull);
    });
  });

  group('a row as it is kept', () {
    test('is read in the shape this build reads, and written back as it was', () {
      final kept = {
        'id': 'n1',
        'rev': 9,
        'kind': 'invite',
        'at': 100,
        'readAt': null,
        'hidden': false,
        'from': 'sam',
        'org': {'id': 'o2', 'name': 'Harbour Press'},
        'state': 'pending',
      };
      final n = FeedNotification.fromJson(kept)!;
      expect([n.id, n.rev, n.kind, n.at, n.readAt, n.hidden, n.from, n.org, n.state], ['n1', 9, 'invite', 100, null, false, 'sam', (id: 'o2', name: 'Harbour Press'), 'pending']);
      expect(n.toJson(), kept);
      // Half a row is no row; a state this build does not know is no state; a revision that is missing is 0.
      expect(FeedNotification.fromJson({'id': 'n1', 'kind': 'invite'}), isNull);
      expect(FeedNotification.fromJson('n1'), isNull);
      final loose = FeedNotification.fromJson({'id': 'n2', 'kind': 'poke', 'at': 5, 'state': 'maybe', 'hidden': 1})!;
      expect([loose.rev, loose.state, loose.hidden, loose.readAt], [0, null, false, null]);
      expect(n.copyWith(readAt: () => 7, hidden: true, state: 'accepted').toJson(), {...kept, 'readAt': 7, 'hidden': true, 'state': 'accepted'});
    });
  });

  group('the rows as a list asks of them', () {
    final a = row('member-joined', id: 'a', at: 10, rev: 1, from: 'sam', org: ghost);
    final b = row('invite', id: 'b', at: 20, rev: 2, from: 'sam', org: (id: 'o2', name: 'Press'), state: 'pending');
    final c = row('summary-written', id: 'c', at: 30, rev: 3, readAt: 31);
    final d = row('note-edited', id: 'd', at: 30, rev: 4, readAt: 31);

    test('are listed newest first, the later revision first of two at one moment, without the hidden and the unknown', () {
      final rows = listed([a, row('poke', id: 'p', at: 99), b, c, row('member-left', id: 'h', at: 50, hidden: true), d]);
      expect([for (final n in rows) n.id], ['d', 'c', 'b', 'a']);
    });

    test('count as unread what the person asked to see: an invitation always, team news unless switched off or muted', () {
      const prefs = NotificationPrefs();
      expect(unreadCount(prefs, [a, b, c, d]), 2);
      // Team news off: the invitation still counts; an organization muted: its news does not.
      expect(unreadCount(prefs.copyWith(team: false), [a, b, c, d]), 1);
      expect(unreadCount(prefs.copyWith(mutedOrgs: ['o1']), [a, b, c, d]), 1);
      // Muting the organization that invited does not hide its invitation.
      expect(unreadCount(prefs.copyWith(mutedOrgs: ['o1', 'o2']), [a, b, c, d]), 1);
      expect(isWanted(d, prefs), isTrue);
      expect(isWanted(c.copyWith(readAt: () => null), prefs.copyWith(summaries: false)), isFalse);
      expect(isWanted(d, prefs.copyWith(claude: false)), isFalse);
      expect(isWanted(row('sync-conflict'), prefs.copyWith(conflicts: false)), isFalse);
      expect(isWanted(row('poke'), prefs), isFalse);
    });

    test('keep an invitation not yet answered out of what Clear all takes', () {
      expect(isPendingInvite(b), isTrue);
      expect(isPendingInvite(b.copyWith(state: 'accepted')), isFalse);
      expect(isPendingInvite(a), isFalse);
      // The kinds whose row opens the organization: an invitation is answered on its own row instead.
      expect(orgKinds.contains('member-joined'), isTrue);
      expect(orgKinds.contains('invite'), isFalse);
      expect(orgKinds.contains('org-deleted'), isFalse);
    });
  });
}
