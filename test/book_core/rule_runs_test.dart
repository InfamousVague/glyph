// A notebook's rules, run (lib/book/rule_runs.dart; Matt, 2026-10-31, "Rules / automations"): each trigger and each
// action through fakes, a run on the record of running work with its plugin's mark and a Retry when it fails, a
// change's rules run once across two devices, and the clock's rules once, on the device that holds the sweep.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/summary_handoff.dart' show SummaryDevice;
import 'package:ghost_md/book/rule_runs.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/core_library.dart' show SavedHere;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/properties.dart' show withProperty;
import 'package:ghost_md/core/stored.dart' show MemoryStored;
import 'package:ghost_md/sync/prefs.dart' show merged;

const int day = 86400000;
const int t0 = 1790000000000;

const String notebookBody = '''---
title: Help desk
book: true
key: HT
---
# Help desk

- [[HT-12 Fix the login]]
- [[HT-13 Tidy the docs]]

```rules
When status becomes Done, post to Slack #eng "{id} {title} shipped"
When a ticket is created, set assignee to Sam
When a ticket is assigned to Priya, notify the assignee "{id} is yours"
When label bug is added, run the Claude rule "Triage a bug", then make a note from "Bug triage" in Kiln called "Triage {id}"
When due passes, notify me "{id} is overdue"
When blocked for 2 days, post to Discord #triage "{id} is stuck"
```
''';

String ticket(String id, {String status = 'To do', String? assignee, String? due, String labels = '', String title = 'Fix the login'}) => [
      '---',
      'type: ticket',
      'id: $id',
      'status: $status',
      if (assignee != null) 'assignee: $assignee',
      if (due != null) 'due: $due',
      if (labels.isNotEmpty) 'labels: [$labels]',
      '---',
      '# $title',
      '',
    ].join('\n');

/// The account's synced settings, and each device's merge into them, as lib/sync/prefs.dart merges them.
class Account {
  Map<String, Object?> held = {};
}

/// One of the account's devices: its settings, what it last saw of the account's, and what its rules did.
class Device {
  Device(this.id, this.account, {required this.notes, this.withAccount = true}) {
    rules = TicketRules(
      device: () => SummaryDevice(id: id, name: id),
      preferences: () => prefs,
      setPreferences: (change) => prefs = change(prefs),
      notes: () => notes,
      world: () => world,
      syncNow: sync,
      accountHeld: withAccount ? () => account.held : null,
      clock: () => now,
      quiet: const Duration(milliseconds: 10),
      warn: warned.add,
    );
  }

  final String id;
  final Account account;
  final bool withAccount;
  List<Note> notes;
  Preferences prefs = const Preferences();
  Map<String, Object?> _base = {};
  int now = t0;
  late final TicketRules rules;
  final List<String> did = [];
  final List<String> warned = [];
  Object? fail;

  /// A sync: this device's settings merged with the account's (the account's own rule for a claim), both left the same.
  Future<void> sync() async {
    final out = merged(_base, prefs.more, account.held, now: now);
    account.held = {...out};
    _base = {...out};
    prefs = prefs.copyWith(more: {...out});
  }

  Future<void> _maybeFail(String what) async {
    did.add(what);
    final failure = fail;
    if (failure != null) {
      fail = null;
      throw failure;
    }
  }

  late final RuleWorld world = RuleWorld(
    setFields: (noteId, fields) async {
      await _maybeFail('set $noteId ${fields.entries.map((e) => '${e.key}=${e.value}').join(',')}');
      notes = [for (final note in notes) if (note.id == noteId) note.copyWith(body: fields.entries.fold<String>(note.body, (body, e) => withProperty(body, e.key, e.value.isEmpty ? null : e.value))) else note];
    },
    post: (service, channel, text, body) async {
      await _maybeFail('post $service #$channel $text');
      return channel ?? 'general';
    },
    claude: (noteId, title, {rule, prompt}) => _maybeFail('claude $title rule=$rule'),
    notify: (notice) => _maybeFail('notify ${notice.person}: ${notice.words} (${notice.id.split('#').last})'),
    make: (template, place, title) {
      did.add('make $template in $place called $title');
      return template != 'Missing';
    },
  );
}

Note note(String id, String body, {int at = t0}) => Note(id: id, body: body, createdAt: at, updatedAt: at);

void main() {
  late Activity record;
  setUp(() {
    final kept = MemoryStored();
    record = Activity(clock: () => DateTime.fromMillisecondsSinceEpoch(t0), store: () => kept);
    useActivity(record);
  });

  List<Note> library({String status = 'To do', String? assignee, String? due, String labels = ''}) => [
        note('book', notebookBody),
        note('t12', ticket('HT-12', status: status, assignee: assignee, due: due, labels: labels)),
        note('t13', ticket('HT-13', title: 'Tidy the docs')),
      ];

  group('each trigger and action', () {
    test('a status moved to Done posts to Slack, with the ticket’s words in its braces, as a job with Slack’s mark', () async {
      final mac = Device('mac', Account(), notes: library());
      final before = mac.notes[1];
      final after = note('t12', ticket('HT-12', status: 'Done'), at: t0 + 1000);
      final runs = await mac.rules.changed(before, after);
      expect(mac.did, ['post slack #eng HT-12 Fix the login shipped']);
      expect(runs.single.id, startsWith('${runs.single.rule.id}:t12:status:done@${t0 + 1000}'));
      final job = record.log.today.rows.first;
      expect(job.plugin, 'slack');
      expect(job.failed, isFalse);
      expect(runsOf(mac.prefs).keys, [runs.single.id]);
    });

    test('a ticket made is given its assignee; a ticket assigned to Priya tells her', () async {
      final mac = Device('mac', Account(), notes: library());
      // A ticket with the notebook's key is the notebook's, listed in its index or not (lib/book/tickets.dart).
      mac.notes = [...mac.notes, note('t14', ticket('HT-14', title: 'New one'))];
      await mac.rules.changed(null, mac.notes.last);
      expect(mac.did, ['set t14 assignee=Sam']);
      mac.did.clear();
      await mac.rules.changed(mac.notes[1], note('t12', ticket('HT-12', assignee: 'Priya'), at: t0 + 5));
      expect(mac.did, ['notify Priya: HT-12 is yours (0)']);
    });

    test('a label added runs Claude, then makes a note from a template', () async {
      final mac = Device('mac', Account(), notes: library());
      await mac.rules.changed(mac.notes[1], note('t12', ticket('HT-12', labels: 'bug'), at: t0 + 5));
      expect(mac.did, ['claude Fix the login rule=Triage a bug', 'make Bug triage in Kiln called Triage HT-12']);
      expect(record.log.today.rows.first.plugin, 'claude');
    });

    test('a failure is the job’s red row with the cause and a Retry, which runs the rest from the one that failed', () async {
      final mac = Device('mac', Account(), notes: library());
      mac.fail = 'Slack has no channel called eng on this device.';
      final runs = await mac.rules.changed(mac.notes[1], note('t12', ticket('HT-12', status: 'Done'), at: t0 + 1000));
      final job = record[TicketRules.jobId(runs.single.id)]!;
      expect(job.state, JobState.failed);
      expect(job.cause, 'Slack has no channel called eng on this device.');
      expect(job.fix!.kind, JobFixKind.retry);
      job.fix!.onPress();
      await pumpEventQueue();
      expect(mac.did, ['post slack #eng HT-12 Fix the login shipped', 'post slack #eng HT-12 Fix the login shipped']);
      expect(record[TicketRules.jobId(runs.single.id)], isNull, reason: 'done, and so out of the live list');
    });

    test('nothing for a ticket in the Trash, a notebook it cannot edit, or one with no rules', () async {
      final mac = Device('mac', Account(), notes: library());
      final after = note('t12', ticket('HT-12', status: 'Done'), at: t0 + 1);
      final trashed = TicketRules(device: () => const SummaryDevice(id: 'mac', name: 'Mac'), preferences: () => mac.prefs, setPreferences: (c) => mac.prefs = c(mac.prefs), notes: () => mac.notes, world: () => mac.world, isTrashed: (id) => id == 't12');
      expect(await trashed.changed(mac.notes[1], after), isEmpty);
      final readOnly = TicketRules(device: () => const SummaryDevice(id: 'mac', name: 'Mac'), preferences: () => mac.prefs, setPreferences: (c) => mac.prefs = c(mac.prefs), notes: () => mac.notes, world: () => mac.world, canEdit: (book) => false);
      expect(await readOnly.changed(mac.notes[1], after), isEmpty);
      mac.notes = [note('book', notebookBody.substring(0, notebookBody.indexOf('```rules'))), ...mac.notes.skip(1)];
      expect(await mac.rules.changed(mac.notes[1], after), isEmpty);
      expect(mac.did, isEmpty);
    });

    test('a status typed letter by letter is one move, heard once the note is quiet', () async {
      final mac = Device('mac', Account(), notes: library());
      final start = mac.notes[1];
      for (final (i, typed) in ['D', 'Do', 'Don', 'Done'].indexed) {
        mac.rules.heard(SavedHereFor(before: i == 0 ? start : note('t12', ticket('HT-12', status: ['D', 'Do', 'Don'][i - 1]), at: t0 + i), after: note('t12', ticket('HT-12', status: typed), at: t0 + i + 1)).saved);
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(mac.did, ['post slack #eng HT-12 Fix the login shipped']);
    });

    test('a ring of rules is stopped three deep', () async {
      const ring = '---\nbook: true\nkey: HT\n---\n- [[HT-12 Fix the login]]\n\n```rules\nWhen status becomes Done, set status to Doing\nWhen status becomes Doing, set status to Done\n```\n';
      final mac = Device('mac', Account(), notes: [note('book', ring), note('t12', ticket('HT-12'))]);
      var at = t0;
      Note was = mac.notes[1];
      Note now = note('t12', ticket('HT-12', status: 'Done'), at: at += 1);
      for (var depth = 0; depth < 4; depth += 1) {
        await mac.rules.changed(was, now, depth: depth);
        was = now;
        now = note('t12', mac.notes[1].body, at: at += 1);
      }
      expect(mac.did, ['set t12 status=Doing', 'set t12 status=Done', 'set t12 status=Doing']);
      expect(mac.warned.single, contains('ring of rules'));
    });
  });

  group('once', () {
    test('a change’s rules run on the device that made it; the same change heard on another device runs nothing', () async {
      final account = Account();
      final mac = Device('mac', account, notes: library());
      final phone = Device('phone', account, notes: library());
      final after = note('t12', ticket('HT-12', status: 'Done'), at: t0 + 1000);
      expect(await mac.rules.changed(mac.notes[1], after), hasLength(1));
      await mac.sync();
      await phone.sync();
      // The phone never hears the Mac's save (sync applies it); and were it to hear it, its id is run already.
      expect(await phone.rules.changed(phone.notes[1], after), isEmpty);
      expect(await mac.rules.changed(mac.notes[1], after), isEmpty, reason: 'heard twice on the Mac too');
      expect(mac.did, hasLength(1));
      expect(phone.did, isEmpty);
      // Moved back and to Done again later is a change of its own.
      expect(await phone.rules.changed(note('t12', ticket('HT-12', status: 'Doing'), at: t0 + 2000), note('t12', ticket('HT-12', status: 'Done'), at: t0 + 3000)), hasLength(1));
    });

    test('the clock’s rules run on the one device that holds the sweep, once, and not again when the sweep moves', () async {
      final account = Account();
      final books = library(due: '2026-09-20');
      final mac = Device('mac', account, notes: books);
      final phone = Device('phone', account, notes: books);
      // Both look at once: the Mac's claim reaches the account first, and the phone's merge keeps it.
      final first = await Future.wait([mac.rules.sweep(), phone.rules.sweep()]);
      expect(first[0].map((run) => run.cause), ['due:2026-09-20']);
      expect(first[1], isEmpty);
      expect(mac.did, ['notify me: HT-12 is overdue (0)']);
      expect(phone.did, isEmpty);
      expect(await mac.rules.sweep(), isEmpty, reason: 'its run id is kept');
      // The Mac is put away: its claim runs out, and the phone takes the sweep, and runs nothing again.
      await mac.sync();
      phone.now = mac.now = t0 + sweepClaimMs + 1;
      await phone.sync();
      expect(await phone.rules.sweep(), isEmpty);
      expect(sweepClaimOf(phone.prefs)!.by, 'phone');
      expect(phone.did, isEmpty);
    });

    test('a block that lasts its days posts once, from when it was first found blocked', () async {
      final account = Account();
      final books = [note('book', notebookBody), note('t12', ticket('HT-12', status: 'Blocked')), note('t13', ticket('HT-13'))];
      final mac = Device('mac', account, notes: books);
      expect(await mac.rules.sweep(), isEmpty);
      mac.now = t0 + day;
      expect(await mac.rules.sweep(), isEmpty);
      mac.now = t0 + 2 * day;
      final runs = await mac.rules.sweep();
      expect(runs.single.cause, 'blocked:$t0');
      expect(mac.did, ['post discord #triage HT-12 is stuck']);
      expect(record.log.today.rows.first.plugin, 'discord');
      mac.now = t0 + 5 * day;
      expect(await mac.rules.sweep(), isEmpty);
      // Unblocked, then blocked again: a block of its own.
      mac.notes = [books[0], note('t12', ticket('HT-12', status: 'Doing')), books[2]];
      await mac.rules.sweep();
      mac.notes = books;
      mac.now = t0 + 6 * day;
      await mac.rules.sweep();
      mac.now = t0 + 8 * day;
      expect((await mac.rules.sweep()).single.cause, 'blocked:${t0 + 6 * day}');
    });

    test('a device that syncs nothing sweeps for itself', () async {
      final alone = Device('mac', Account(), notes: library(due: '2026-09-20'), withAccount: false);
      expect(await alone.rules.sweep(), hasLength(1));
    });
  });
}

/// A save heard, as the library tells one.
class SavedHereFor {
  SavedHereFor({required this.before, required this.after});
  final Note before;
  final Note after;
  SavedHere get saved => SavedHere(before: before, after: after);
}
