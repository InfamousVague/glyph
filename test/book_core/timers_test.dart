// Time on a ticket (lib/book/time_log.dart, lib/book/timers.dart, lib/core/durations.dart; Matt, 2026-10-31, "time
// tracking"): the log's lines and `spent:`, a timer started and stopped, one a device, a long one asking, the timer
// on another device, and the totals in a query and a rollup.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/summary_handoff.dart' show SummaryDevice;
import 'package:ghost_md/book/time_log.dart';
import 'package:ghost_md/book/timers.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/durations.dart';
import 'package:ghost_md/core/front_matter.dart' show frontMatterValue;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/core/stored.dart' show MemoryStored;
import 'package:ghost_md/sync/prefs.dart' show merged;

const int t0 = 1790000000000;
const int minute = 60000;

const String fresh = '---\ntype: ticket\nid: HT-12\nstatus: Doing\n---\n# Fix the login\n\nThe form forgets the email.\n';

void main() {
  group('durations', () {
    test('read as a person writes them, and nothing else', () {
      expect(spentMinutes('3h 20m'), 200);
      expect(spentMinutes('1.5h'), 90);
      expect(spentMinutes('45 min'), 45);
      expect(spentMinutes('2 hours, 5 minutes'), 125);
      expect(spentMinutes('3'), isNull);
      expect(spentMinutes('3 days'), isNull);
      expect(spentMinutes(r'$300'), isNull);
      expect(spentWords(200), '3h 20m');
      expect(spentWords(45), '45m');
      expect(spentWords(120), '2h');
      expect(spentTotal(['3h 20m', '45m', '']), '4h 5m');
      expect(spentTotal(['3h', '2']), isNull);
    });
  });

  group('the log', () {
    test('a first line makes the section at the foot and writes spent', () {
      final once = withTimeLogged(fresh, const TimeEntry(day: '2026-10-30', minutes: 80, who: 'Matt'));
      expect(once, '---\ntype: ticket\nid: HT-12\nstatus: Doing\nspent: 1h 20m\n---\n# Fix the login\n\nThe form forgets the email.\n\n## Time\n\n- 2026-10-30 · 1h 20m · Matt\n');
      final twice = withTimeLogged(once, const TimeEntry(day: '2026-10-31', minutes: 45, who: 'Sam', note: 'fixed the flaky test'));
      expect(twice, endsWith('## Time\n\n- 2026-10-30 · 1h 20m · Matt\n- 2026-10-31 · 45m · Sam · fixed the flaky test\n'));
      expect(frontMatterValue(twice, 'spent'), '2h 5m');
      expect(spentOf(twice), 125);
      expect(timeLogOf(twice), const [TimeEntry(day: '2026-10-30', minutes: 80, who: 'Matt'), TimeEntry(day: '2026-10-31', minutes: 45, who: 'Sam', note: 'fixed the flaky test')]);
    });

    test('a line typed by hand reads the same, and a section with words after it keeps them', () {
      const typed = '---\ntype: ticket\n---\n# A\n\n## Time\n- 2026-10-01 - 2h - Priya\n- 2026-10-02, 30m\n- not a line\n\n## Notes\nMore.\n';
      expect(timeLogOf(typed), const [TimeEntry(day: '2026-10-01', minutes: 120, who: 'Priya'), TimeEntry(day: '2026-10-02', minutes: 30, who: '')]);
      expect(spentOf(typed), 150, reason: 'no spent: the lines total');
      final logged = withTimeLogged(typed, const TimeEntry(day: '2026-10-03', minutes: 15, who: 'Sam'));
      expect(logged, contains('- not a line\n- 2026-10-03 · 15m · Sam\n\n## Notes\nMore.\n'));
      expect(frontMatterValue(logged, 'spent'), '2h 45m');
    });

    test('time written by hand before anything was logged is kept', () {
      final logged = withTimeLogged(fresh.replaceFirst('status: Doing', 'status: Doing\nspent: 2h'), const TimeEntry(day: '2026-10-30', minutes: 30, who: 'Matt'));
      expect(frontMatterValue(logged, 'spent'), '2h 30m');
    });
  });

  group('the timers', () {
    late Map<String, String> notes;
    late Map<String, Object?> account;
    setUp(() {
      final kept = MemoryStored();
      useActivity(Activity(clock: () => DateTime.fromMillisecondsSinceEpoch(t0), store: () => kept));
      notes = {'n12': fresh, 'n13': fresh.replaceFirst('HT-12', 'HT-13')};
      account = {};
    });

    ({TicketTimers timers, ValueNotifier<Preferences> prefs, void Function() sync, List<int> clock}) device(String id) {
      final prefs = ValueNotifier<Preferences>(const Preferences());
      final clock = [t0];
      var base = <String, Object?>{};
      void sync() {
        final out = merged(base, prefs.value.more, account, now: clock[0]);
        account = {...out};
        base = {...out};
        prefs.value = prefs.value.copyWith(more: {...out});
      }

      final timers = TicketTimers(
        device: () => SummaryDevice(id: id, name: id == 'mac' ? 'Mac' : 'phone'),
        preferences: () => prefs.value,
        setPreferences: (change) => prefs.value = change(prefs.value),
        prefsChanged: prefs,
        write: (noteId, change) async => notes[noteId] = change(notes[noteId]!),
        who: () => 'Matt',
        clock: () => clock[0],
      );
      addTearDown(timers.dispose);
      return (timers: timers, prefs: prefs, sync: sync, clock: clock);
    }

    test('start, stop: the log line and the total, and the timer’s job with its time so far', () async {
      final mac = device('mac');
      await mac.timers.start('n12', title: 'Fix the login', key: 'HT-12');
      expect(mac.timers.mine!.named, 'HT-12');
      expect(activity['timer:n12']!.title, 'Timer on HT-12');
      mac.clock[0] = t0 + 80 * minute;
      expect(mac.timers.elapsed(mac.timers.mine!), '1h 20m');
      final entry = await mac.timers.stop();
      expect(entry, const TimeEntry(day: '2026-09-21', minutes: 80, who: 'Matt'));
      expect(notes['n12'], contains('spent: 1h 20m'));
      expect(notes['n12'], endsWith('## Time\n\n- 2026-09-21 · 1h 20m · Matt\n'));
      expect(mac.timers.mine, isNull);
      expect(activity['timer:n12'], isNull);
      expect(activity.log.today.counts['timer logged|timers logged'], 1);
    });

    test('one a device: starting another stops the first and logs it', () async {
      final mac = device('mac');
      await mac.timers.start('n12', title: 'Fix the login', key: 'HT-12');
      mac.clock[0] = t0 + 30 * minute;
      await mac.timers.start('n13', title: 'Fix the login', key: 'HT-13');
      expect(notes['n12'], contains('spent: 30m'));
      expect(mac.timers.mine!.noteId, 'n13');
      expect(mac.timers.all, hasLength(1));
    });

    test('a timer of more than ten hours asks: all of it, some, or nothing; no answer leaves it running', () async {
      final mac = device('mac');
      final asked = <int>[];
      LongTimerAnswer? answer;
      mac.timers.confirmLong = (timer, minutes) async {
        asked.add(minutes);
        return answer;
      };
      await mac.timers.start('n12', title: 'Fix the login', key: 'HT-12');
      mac.clock[0] = t0 + 9 * 60 * minute;
      expect(asksBeforeLogging(9 * 60), isFalse);
      mac.clock[0] = t0 + 11 * 60 * minute;
      expect(activity['timer:n12']!.line, isNot(contains('Still going')), reason: 'its line is put right each minute');
      expect(await mac.timers.stop(), isNull);
      expect(asked, [660]);
      expect(mac.timers.mine, isNotNull, reason: 'left running');
      answer = (minutes: 120);
      expect((await mac.timers.stop())!.minutes, 120);
      expect(notes['n12'], contains('spent: 2h'));
      await mac.timers.start('n13', title: 'x', key: 'HT-13');
      mac.clock[0] = t0 + 30 * 60 * minute;
      answer = (minutes: null);
      expect(await mac.timers.stop(), isNull);
      expect(mac.timers.mine, isNull, reason: 'logged as nothing');
      expect(notes['n13'], isNot(contains('spent')));
    });

    test('the running timer is on the other device, as that device’s, and stopping it there logs it once', () async {
      final mac = device('mac');
      final phone = device('phone');
      await mac.timers.start('n12', title: 'Fix the login', key: 'HT-12');
      mac.sync();
      phone.sync();
      final there = phone.timers.on('n12')!;
      expect(there.device, 'mac');
      expect(there.deviceName, 'Mac');
      expect(phone.timers.mine, isNull);
      final elsewhere = activity.value.where((job) => !job.here).toList();
      expect(elsewhere.map((job) => job.deviceWords), contains('on your Mac'));
      phone.clock[0] = mac.clock[0] = t0 + 25 * minute;
      final entry = await phone.timers.stop(there);
      expect(entry!.minutes, 25);
      phone.sync();
      mac.sync();
      expect(mac.timers.mine, isNull);
      expect(activity['timer:n12'], isNull, reason: 'its job went with it on the Mac');
      expect(RegExp('## Time').allMatches(notes['n12']!), hasLength(1));
      expect(notes['n12'], contains('spent: 25m'));
    });

    test('time added by hand is the same line', () async {
      final mac = device('mac');
      await mac.timers.add('n12', 45, day: '2026-10-29', note: 'pairing');
      expect(notes['n12'], endsWith('- 2026-10-29 · 45m · Matt · pairing\n'));
      expect(await mac.timers.add('n12', 0), isNull);
    });
  });

  group('totals', () {
    QueryNote at(String id, String spent) => QueryNote(id: id, body: '---\ntype: ticket\nid: $id\nstatus: Doing\nspent: $spent\nproject: "[[Launch]]"\n---\n# $id\n', createdAt: 0, updatedAt: 0);
    QueryResult run(String query, List<QueryNote> notes) => runQuery(readQuery(query).query!, libraryOf(notes), '2026-10-30');
    List<QueryRow> rows(QueryResult result) => [for (final group in result.groups) ...group.rows];

    test('a query’s total of spent adds time as time', () {
      final result = run('from: tickets\ntotal: spent', [at('HT-1', '3h 20m'), at('HT-2', '45m')]);
      expect(result.totals.single.text, '4h 5m');
    });

    test('a rollup’s sum of spent, and spent compared in hours', () {
      final notes = [QueryNote(id: 'p', body: '# Launch\n', createdAt: 0, updatedAt: 0), at('HT-1', '3h 20m'), at('HT-2', '45m')];
      final result = run('from: notes\nwhere: title = Launch\nrollup: spent = sum(spent of backlinks.project)\ncolumns: title, spent', notes);
      final cell = rows(result).single.cells.last;
      expect(cell, isA<NumberCell>());
      expect((cell as NumberCell).text, '4h 5m');
      final long = run('from: tickets\nwhere: spent > 2\ncolumns: title', [at('HT-1', '3h 20m'), at('HT-2', '45m')]);
      expect([for (final row in rows(long)) row.name], ['HT-1']);
    });
  });
}
