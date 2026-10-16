import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/home_screen/home_data.dart';
import 'package:ghost_md/home_screen/home_host.dart';
import 'package:ghost_md/home_screen/home_screen_data.dart';

import '../support/fake_reminders.dart';

/// What the home screen's widgets and the icon's shortcuts are handed (lib/home_screen/home_data.dart,
/// home_screen_data.dart): the Today widget's to-dos, the pinned notes and the notes opened last, each handed over
/// only when it is another than the last.

Note note(String id, String body, {int updatedAt = 1, bool starred = false, int? archivedAt}) => Note(id: id, body: body, createdAt: 1, updatedAt: updatedAt, starred: starred, archivedAt: archivedAt);

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
    expect(home.puts.map((kind, puts) => MapEntry(kind, puts.length)), {HomeKind.today: 1, HomeKind.pinned: 1, HomeKind.recent: 1});
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
  });
}
