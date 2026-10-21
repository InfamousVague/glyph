import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/calendar/event.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/home_screen/home_data.dart';
import 'package:ghost_md/home_screen/home_host.dart';
import 'package:ghost_md/home_screen/home_screen_data.dart';

import '../support/fake_reminders.dart';

/// What the home screen's widgets and the icon's shortcuts are handed (lib/home_screen/home_data.dart,
/// home_screen_data.dart): the Today widget's to-dos, the pinned notes and the notes opened last, each handed over
/// only when it is another than the last.

Note note(String id, String body, {int updatedAt = 1, int createdAt = 1, bool starred = false, int? archivedAt, int? recordingMs}) =>
    Note(id: id, body: body, createdAt: createdAt, updatedAt: updatedAt, starred: starred, archivedAt: archivedAt, recordingMs: recordingMs);

void main() {
  final now = DateTime(2026, 10, 2, 8);

  group('Today', () {
    test('the open to-dos due by a week on, overdue first, from every note', () {
      final notes = [
        note('a', '# Errands\n- [ ] Call the plumber 📅 2026-10-02\n- [x] Called 📅 2026-10-01\n- [ ] Next month 📅 2026-11-02'),
        note('b', '# Work\n- [ ] Send the report 📅 2026-09-30\n- Plain item 📅 2026-10-02\n- [ ] Plan 📅 2026-10-09'),
        note('c', '---\ntype: ticket\nstatus: To do\ndue: 2026-10-01\n---\n# Fix the login'),
      ];
      final items = todayItems(notes, now: now);
      expect([for (final item in items) '${item.due} ${item.words} (${item.note}:${item.line})'], [
        '2026-09-30 Send the report (Work:2)',
        '2026-10-01 Fix the login (Fix the login:0)',
        '2026-10-02 Call the plumber (Errands:2)',
        '2026-10-09 Plan (Work:4)',
      ]);
    });

    test('nothing from the archive or the Trash', () {
      final notes = [note('a', '- [ ] One 📅 2026-10-02', archivedAt: 3), note('b', '- [ ] Two 📅 2026-10-02')];
      expect(todayItems(notes, now: now, skip: (n) => n.id == 'b'), isEmpty);
    });

    test('as the widget is handed it', () {
      final json = jsonDecode(todayJson(todayItems([note('a', '# Errands\n- [ ] 📅 2026-10-02')], now: now))) as Map;
      expect(json['items'], [
        {'note': 'a', 'line': 2, 'words': 'Untitled to-do', 'due': '2026-10-02', 'title': 'Errands', 'tick': true},
      ]);
    });
  });

  group('Pinned and recent', () {
    test('the pinned notes, the one written in last first', () {
      final notes = [note('a', '# Old pin', starred: true, updatedAt: 1), note('b', '# New pin', starred: true, updatedAt: 9), note('c', '# Not pinned'), note('d', '', starred: true, updatedAt: 5)];
      expect(pinnedNotes(notes), [(id: 'b', title: 'New pin'), (id: 'd', title: 'Untitled'), (id: 'a', title: 'Old pin')]);
    });

    test('the notes opened last, newest first, three of them', () {
      expect(openedLast(['a', 'b', 'c'], 'b'), ['b', 'a', 'c']);
      expect(openedLast(['a', 'b', 'c'], 'd'), ['d', 'a', 'b']);
    });
  });

  test('handed over only when another than the last, and a note opened moves to the front of the recent ones', () async {
    final home = FakeHome();
    final kept = MemoryStored();
    final data = HomeScreenData(host: home, kept: kept, clock: () => now);
    final notes = [note('a', '# Errands\n- [ ] Call 📅 2026-10-02', starred: true), note('b', '# Work')];
    Note? noteOf(String id) => notes.where((n) => n.id == id).firstOrNull;
    await data.pass(notes, noteOf);
    await data.pass(notes, noteOf);
    expect(home.puts.map((kind, puts) => MapEntry(kind, puts.length)), {HomeKind.look: 1, HomeKind.todos: 1, HomeKind.notes: 1, HomeKind.voice: 1, HomeKind.calendar: 1, HomeKind.recent: 1});
    await data.opened('b', noteOf);
    await data.opened('a', noteOf);
    await data.opened('a', noteOf);
    expect(home.puts[HomeKind.recent], hasLength(3));
    expect(jsonDecode(home.puts[HomeKind.recent]!.last), {
      'notes': [
        {'id': 'a', 'title': 'Errands'},
        {'id': 'b', 'title': 'Work'},
      ],
    });
    expect(HomeScreenData(host: home, kept: kept).recent, ['a', 'b'], reason: 'kept on the device');
    // A new note with no words yet is not offered.
    notes.add(note('c', ''));
    await data.opened('c', noteOf);
    expect(HomeScreenData(host: home, kept: kept).recent, ['a', 'b']);
  });

  group('the four widgets', () {
    test('To-dos: the dated ones by a week on as Today had them, then those with no date, in the words the To-dos view shows', () {
      final notes = [
        note('a', '# Errands\n- [ ] Call [[Bob]] 📅 2026-10-02\n- [ ] Buy milk\n- [x] Done already\n- [ ] Far off 📅 2026-12-01', updatedAt: 5),
        note('b', '# Work\n- [ ] Send the report 📅 2026-09-30\n- [ ] Tidy the desk', updatedAt: 9),
        note('c', '# Gone\n- [ ] Trashed one', updatedAt: 20),
      ];
      final todos = homeTodos(notes, now: now, skip: (n) => n.id == 'c');
      expect([for (final t in todos) '${t.due ?? 'someday'} ${t.words} [${t.match}] (${t.note}:${t.line})'], [
        '2026-09-30 Send the report [Send the report] (Work:2)',
        '2026-10-02 Call [[Bob]] [Call [[Bob]]] (Errands:2)',
        'someday Tidy the desk [Tidy the desk] (Work:3)',
        'someday Buy milk [Buy milk] (Errands:3)',
      ]);
      final json = jsonDecode(todosJson(todos)) as Map;
      expect((json['todos'] as List).first, {'note': 'b', 'line': 2, 'words': 'Send the report', 'match': 'Send the report', 'title': 'Work', 'due': '2026-09-30'});
      expect((json['todos'] as List).last, {'note': 'a', 'line': 3, 'words': 'Buy milk', 'match': 'Buy milk', 'title': 'Errands'}, reason: 'no due day said for one with none');
    });

    test('To-dos: a priority worth a word, as the To-dos view says it', () {
      final todos = homeTodos([note('a', '# Work\n- [ ] Ship it ⏫ 📅 2026-10-02\n- [ ] Someday 🔼')], now: now);
      expect([for (final t in todos) t.priority], ['high', null]);
    });

    test('To-dos: the words with every field taken off, a reminder too', () {
      final todos = homeTodos([note('a', '# Day\n- [ ] Snooze ⏰ 2026-10-16 13:53')], now: now);
      expect([for (final t in todos) (t.words, t.match)], [('Snooze', 'Snooze')]);
    });

    test('To-dos: no more undated ones than asked for', () {
      final notes = [note('a', ['# Many', for (var i = 0; i < 40; i += 1) '- [ ] Thing $i'].join('\n'))];
      expect(homeTodos(notes, now: now, someday: 5), hasLength(5));
    });

    test('Recent notes: the notes touched last, with how each starts, its kind and when; blank ones, the archive and the Trash out', () {
      final notes = [
        note('a', '# Groceries\nEggs, milk', updatedAt: 100),
        note('b', '# Standup\nWe talked', updatedAt: 300, recordingMs: 40000, starred: true),
        note('c', '', updatedAt: 400),
        note('d', '# Old', updatedAt: 200, archivedAt: 5),
        note('e', '# Trashed', updatedAt: 500),
      ];
      final listed = homeNotes(notes, skip: (n) => n.id == 'e');
      expect([for (final n in listed) n.id], ['b', 'a']);
      expect(jsonDecode(notesJson(listed)), {
        'notes': [
          {'id': 'b', 'title': 'Standup', 'line': 'We talked', 'updated': 300, 'pinned': true, 'kind': 'tape', 'ms': 40000},
          {'id': 'a', 'title': 'Groceries', 'line': 'Eggs, milk', 'updated': 100, 'kind': 'note'},
        ],
      });
    });

    test('Voice note: the recordings, the last recorded first, three of them', () {
      final notes = [
        for (var i = 1; i <= 5; i += 1) note('t$i', '# Take $i\nWords', createdAt: i * 10, updatedAt: 1000 - i, recordingMs: i * 1000),
        note('w', '# Written\nNo tape', createdAt: 99),
      ];
      expect([for (final n in homeRecordings(notes)) '${n.id} ${n.ms} ${n.updated}'], ['t5 5000 50', 't4 4000 40', 't3 3000 30']);
    });

    test('Calendar: off says so and hands no events; on, the events from today to a week on, in the order a day lists them', () {
      expect(jsonDecode(calendarJson(on: false, events: const [], now: now)), {'calendar': false, 'events': []});
      CalendarEvent event(String id, DateTime start, DateTime end, {bool allDay = false, String title = 'Thing'}) =>
          CalendarEvent(id: id, source: 'ical:x', calendar: 'Home', title: title, start: start, end: end, allDay: allDay);
      final events = [
        event('past', DateTime(2026, 9, 20, 9), DateTime(2026, 9, 20, 10)),
        event('late', DateTime(2026, 10, 2, 15), DateTime(2026, 10, 2, 16), title: 'Dentist'),
        event('day', DateTime(2026, 10, 2), DateTime(2026, 10, 3), allDay: true, title: 'Holiday'),
        event('far', DateTime(2026, 11, 2, 9), DateTime(2026, 11, 2, 10)),
      ];
      final json = jsonDecode(calendarJson(on: true, events: events, now: now)) as Map;
      expect(json['calendar'], true);
      expect([for (final e in json['events'] as List) '${e['title']} ${e['start']} ${e['end']} ${e['allDay']}'], ['Holiday 2026-10-02 2026-10-03 true', 'Dentist ${DateTime(2026, 10, 2, 15).toUtc().toIso8601String()} ${DateTime(2026, 10, 2, 16).toUtc().toIso8601String()} false']);
    });

    test('the look: the side of the app theme', () {
      expect(jsonDecode(lookJson('dark')), {'theme': 'dark'});
      expect(jsonDecode(lookJson('light')), {'theme': 'light'});
      expect(jsonDecode(lookJson('system')), {'theme': 'system'});
    });
  });
}
