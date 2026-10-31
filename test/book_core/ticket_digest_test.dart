import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/summary_handoff.dart' show SummaryDevice;
import 'package:ghost_md/book/ticket_digest.dart';
import 'package:ghost_md/book/tickets.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/reminders/reminder_plan.dart';

import '../core/make_note.dart';

/// The morning's ticket digest (lib/book/ticket_digest.dart; Matt, 2026-10-31): what it says - due today, overdue,
/// blocked, across notebooks and teams - when it is sent, and that one device sends it.
String ticket(String id, String title, {String status = 'To do', String? assignee, String? due, String more = ''}) =>
    '---\ntype: ticket\nid: $id\nstatus: $status\n${assignee == null ? '' : 'assignee: $assignee\n'}${due == null ? '' : 'due: $due\n'}$more---\n# $title\n';

final Map<String, String> bodies = {
  'today': ticket('GHO-1', 'Ship the beta', assignee: 'matt', due: '2026-10-31'),
  'late': ticket('GHO-2', 'Book the venue', assignee: '@Matt', due: '2026-10-28'),
  'later': ticket('GHO-3', 'Later on', assignee: 'matt', due: '2026-11-04'),
  'sams': ticket('GHO-4', 'Sam’s ticket', assignee: 'sam', due: '2026-10-31'),
  'done': ticket('GHO-5', 'Done already', status: 'Done', assignee: 'matt', due: '2026-10-29'),
  'blocked': ticket('GHO-6', 'Launch', assignee: 'matt', more: 'blocked-by: "[[GHO-2]]"\n'),
  'unblocked': ticket('GHO-7', 'Party', assignee: 'matt', more: 'blocked-by: "[[GHO-5]]"\n'),
  'mine-unassigned': ticket('ME-1', 'Renew the passport', due: '2026-10-31'),
  'team-unassigned': ticket('TM-1', 'Anyone’s', due: '2026-10-31'),
};

List<TicketEntry> library() => ticketsIn([for (final MapEntry(:key, :value) in bodies.entries) makeNote(key, body: value)]);

TicketDigest digest([String day = '2026-10-31']) => digestFor(library(), me: 'matt', today: day, team: (id) => id.startsWith('team'));

/// One of Matt's devices, its settings and what it sent, over the account's settings as a sync would carry them.
class Device {
  Device(this.account, this.id, {required this.phone});

  final Account account;
  final String id;
  final bool phone;
  Preferences prefs = Preferences.defaults;
  Object? base;
  final List<TicketDigest> sent = [];
  final List<TicketDigest> notes = [];
  int plans = 0;
  late final TicketDigestRunner runner = TicketDigestRunner(
    claims: DigestClaims(
      device: () => SummaryDevice(id: id, name: phone ? 'phone' : 'Mac'),
      preferences: () => prefs,
      setPreferences: (change) => prefs = change(prefs),
      syncNow: () async => sync(),
      accountHeld: () => account.held,
      clock: () => account.now.millisecondsSinceEpoch,
    ),
    choices: () => digestSettingsOf(prefs),
    digest: (day) => digestFor(library(), me: 'matt', today: day, team: (id) => id.startsWith('team')),
    send: (words) async => sent.add(words),
    writeNote: (words) async {
      notes.add(words);
      return 'note-${words.day}';
    },
    phone: () => phone,
    planChanged: () => plans += 1,
    clock: () => account.now,
  );

  /// A sync with the account: this device's claim written from what it last saw, the account's merge where another
  /// device wrote meanwhile (lib/sync/prefs.dart `merged`).
  void sync() {
    final mine = prefs.more[ticketDigestKey];
    final theirs = account.held[ticketDigestKey];
    final chosen = theirs != null && theirs != base ? chosenDigestClaim(mine, theirs) : mine;
    account.held = {...account.held, ticketDigestKey: chosen};
    prefs = prefs.copyWith(more: {...prefs.more, ticketDigestKey: chosen});
    base = chosen;
  }

  void set(DigestSettings settings) => prefs = withDigestSettings(prefs, settings);
}

class Account {
  Map<String, Object?> held = {};
  DateTime now = DateTime(2026, 10, 31, 7, 0);
}

void main() {
  group('what it says', () {
    test('due today, overdue and blocked: assigned to the person, or theirs and nobody’s, not done', () {
      final d = digest();
      expect([for (final item in d.dueToday) item.key], ['GHO-1', 'ME-1']);
      expect([for (final item in d.overdue) item.key], ['GHO-2']);
      expect([for (final item in d.blocked) '${item.key} waits on ${item.waitsOn.join(', ')}'], ['GHO-6 waits on GHO-2']);
      expect(d.empty, isFalse);
    });

    test('in a notification’s words and as a note’s Markdown', () {
      final d = digest();
      expect(d.title, '2 due today · 1 overdue · 1 blocked');
      expect(d.text, 'GHO-2 Book the venue, GHO-1 Ship the beta, ME-1 Renew the passport, GHO-6 Launch');
      expect(d.markdown, '# Tickets for 2026-10-31\n\n## Due today\n\n- [[GHO-1]] Ship the beta\n- [[ME-1]] Renew the passport\n\n## Overdue\n\n- [[GHO-2]] Book the venue · due 2026-10-28\n\n## Blocked\n\n- [[GHO-6]] Launch · waits on [[GHO-2]]\n');
    });

    test('a morning with nothing due, late or blocked is empty', () {
      final quiet = digestFor(ticketsIn([makeNote('a', body: ticket('GHO-1', 'Later', assignee: 'matt', due: '2026-12-01'))]), me: 'matt', today: '2026-10-31');
      expect(quiet.empty, isTrue);
      expect(quiet.title, '');
    });
  });

  group('its time', () {
    test('8:30 unless changed; a phone claims the next morning ahead and holds its alarm', () async {
      final account = Account();
      final phone = Device(account, 'phone-1', phone: true);
      expect(phone.runner.settings, const DigestSettings());
      await phone.runner.look();
      expect(phone.runner.alarm?.day, '2026-10-31');
      expect(phone.runner.alarm?.at, DateTime(2026, 10, 31, 8, 30));
      final reminder = digestReminderOf(phone.runner)!;
      expect((reminder.kind, reminder.title, reminder.text, reminder.noteId), (ReminderKind.digest, 'Your tickets: 2 due today · 1 overdue · 1 blocked', 'GHO-2 Book the venue, GHO-1 Ship the beta, ME-1 Renew the passport, GHO-6 Launch', digestNoteId));
      // After the time, the next morning's.
      account.now = DateTime(2026, 10, 31, 9, 0);
      await phone.runner.look();
      expect(phone.runner.alarm?.day, '2026-11-01');
      // Another time chosen: the alarm moves with it; turned off, it goes.
      phone.set(const DigestSettings(hour: 7, minute: 15));
      await phone.runner.look();
      expect(phone.runner.alarm?.at, DateTime(2026, 11, 1, 7, 15));
      phone.set(const DigestSettings(on: false));
      await phone.runner.look();
      expect(phone.runner.alarm, isNull);
      expect(phone.plans, greaterThanOrEqualTo(3), reason: 'the reminders asked for a pass each time it changed');
      phone.runner.dispose();
    });

    test('a Mac sends it at the time, once, and not before; a note too where asked for', () async {
      final account = Account();
      final mac = Device(account, 'mac-1', phone: false)..set(const DigestSettings(note: true));
      await mac.runner.look();
      expect(mac.sent, isEmpty, reason: 'before 8:30');
      account.now = DateTime(2026, 10, 31, 8, 31);
      await mac.runner.look();
      await mac.runner.look();
      expect(mac.sent.map((d) => d.day), ['2026-10-31']);
      expect(mac.notes.map((d) => d.day), ['2026-10-31']);
      // Opened in the afternoon, hours past its time: not sent so late.
      final late = Device(Account()..now = DateTime(2026, 10, 31, 16, 0), 'mac-2', phone: false);
      await late.runner.look();
      expect(late.sent, isEmpty);
      mac.runner.dispose();
      late.runner.dispose();
    });
  });

  group('sent once across devices', () {
    test('a phone that claimed the morning ahead holds it: the Mac sends nothing', () async {
      final account = Account();
      final phone = Device(account, 'phone-1', phone: true), mac = Device(account, 'mac-1', phone: false);
      await phone.runner.look();
      mac.sync();
      account.now = DateTime(2026, 10, 31, 8, 31);
      await mac.runner.look();
      expect(mac.sent, isEmpty);
      // The phone, looked at after its alarm rang, writes its note where asked for and claims the next morning, which
      // tells the Mac this one was dealt with.
      phone.set(const DigestSettings(note: true));
      await phone.runner.look();
      expect(phone.notes.map((d) => d.day), ['2026-10-31']);
      expect(phone.sent, isEmpty, reason: 'the phone’s alarm was its notification');
      expect(digestClaimOf(phone.prefs)?.day, '2026-11-01');
      mac.sync();
      await mac.runner.look();
      expect(mac.sent, isEmpty);
      phone.runner.dispose();
      mac.runner.dispose();
    });

    test('two Macs at 8:30: the account’s first claim sends, the other reads it and does not', () async {
      final account = Account()..now = DateTime(2026, 10, 31, 8, 31);
      final one = Device(account, 'mac-1', phone: false), two = Device(account, 'mac-2', phone: false);
      await Future.wait([one.runner.look(), two.runner.look()]);
      expect(one.sent.length + two.sent.length, 1);
      await one.runner.look();
      await two.runner.look();
      expect(one.sent.length + two.sent.length, 1);
      expect(digestRowId(7, '2026-10-31'), digestRowId(7, '2026-10-31'), reason: 'a second sending lands on the same row');
      one.runner.dispose();
      two.runner.dispose();
    });

    test('the merge: a day sent beats one claimed, the account’s claim beats this one’s, a later day beats an earlier', () {
      Map<String, Object?> claim(String day, String by, {int? sent}) => DigestClaim(day: day, by: by, at: 1, sent: sent).toJson();
      expect(chosenDigestClaim(claim('2026-10-31', 'a'), claim('2026-10-31', 'b')), claim('2026-10-31', 'b'));
      expect(chosenDigestClaim(claim('2026-10-31', 'a', sent: 5), claim('2026-10-31', 'b')), claim('2026-10-31', 'a', sent: 5));
      expect(chosenDigestClaim(claim('2026-11-01', 'a'), claim('2026-10-31', 'b', sent: 5)), claim('2026-11-01', 'a'));
      expect(chosenDigestClaim(null, claim('2026-10-31', 'b')), claim('2026-10-31', 'b'));
    });
  });
}
