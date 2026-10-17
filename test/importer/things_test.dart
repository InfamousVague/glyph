import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/carry/sqlite_read.dart';
import 'package:ghost_md/core/book.dart' show chaptersOf, isBookBody;
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/importer/import_report.dart';
import 'package:ghost_md/importer/import_sources.dart';
import 'package:ghost_md/importer/importer.dart';
import 'package:ghost_md/importer/things.dart';
import 'package:ghost_md/importer/things_database.dart';

import 'support.dart';

/// Things 3's database (lib/importer/things.dart, things_database.dart), over a small one each test builds with the
/// system's SQLite in the layout things.py reads: two areas, a project with a When date, a deadline, a tag, notes,
/// two headings out of order and a to-do under each, a to-do with a checklist, one done and one cancelled, one in
/// the trash and one in a project in the trash, a repeating to-do's template, a project done, a project in no area,
/// a loose to-do in an area, one in the Inbox and one in Someday. And an older file: dates in seconds,
/// `actionGroup`, `dueDate`. Never the person's own database.
void main() {
  const root = 'workspaces/Imported from Things 2026-10-16';

  int packed(int y, int m, int d) => thingsPackedDay(y, m, d);
  double seconds(DateTime at) => at.millisecondsSinceEpoch / 1000;

  /// A database at [path] made of [statements], one at a time (lib/carry/sqlite_read.dart reads one statement a
  /// call; a file with nothing in it is an empty database, which the statements fill).
  void build(String path, List<String> statements) {
    File(path).writeAsBytesSync(const []);
    for (final statement in statements) {
      SqliteRead.rows(path, statement, ownCopy: true);
    }
  }

  String q(Object? value) => switch (value) {
        null => 'NULL',
        String text => "'${text.replaceAll("'", "''")}'",
        _ => '$value',
      };

  List<String> newSchema() {
    final rows = <List<Object?>>[
      // uuid, type, status, trashed, title, notes, area, project, heading, start, startDate, deadline, stopDate, index, rule
      ['P1', 1, 0, 0, 'Launch', 'Ship it.', 'A1', null, null, 1, packed(2026, 10, 20), packed(2026, 10, 30), null, 1, null],
      ['P2', 1, 0, 0, 'Garden', '', 'A2', null, null, 1, null, null, null, 2, null],
      ['P3', 1, 0, 0, 'Side project', '', null, null, null, 1, null, null, null, 3, null],
      ['P4', 1, 3, 0, 'Old project', '', 'A1', null, null, 1, null, null, seconds(DateTime(2026, 9, 1, 12)), 4, null],
      ['P5', 1, 0, 1, 'Binned project', '', 'A1', null, null, 1, null, null, null, 5, null],
      ['H1', 2, 0, 0, 'Press', '', null, 'P1', null, 1, null, null, null, 2, null],
      ['H2', 2, 0, 0, 'Build', '', null, 'P1', null, 1, null, null, null, 1, null],
      ['T1', 0, 0, 0, 'Write the post', 'Two paragraphs.\n\nOr three.', null, 'P1', null, 1, null, packed(2026, 10, 25), null, 1, null],
      ['T2', 0, 0, 0, 'Call the paper', '', null, null, 'H1', 1, packed(2026, 10, 21), null, null, 1, null],
      ['T3', 0, 0, 0, 'Set up CI', '', null, null, 'H2', 1, null, null, null, 1, null],
      ['T4', 0, 3, 0, 'Fix login', '', null, null, 'H2', 1, null, null, seconds(DateTime(2026, 10, 10, 12)), 2, null],
      ['T5', 0, 2, 0, 'Cancelled thing', '', null, 'P1', null, 1, null, null, seconds(DateTime(2026, 10, 11, 12)), 2, null],
      ['T6', 0, 0, 0, 'Buy bulbs', '', 'A2', null, null, 1, null, null, null, 1, null],
      ['T7', 0, 0, 0, 'Inbox item', '', null, null, null, 0, null, null, null, 1, null],
      ['T8', 0, 0, 0, 'Someday idea', '', null, null, null, 2, null, null, null, 2, null],
      ['T9', 0, 0, 1, 'Trashed', '', null, 'P1', null, 1, null, null, null, 3, null],
      ['T10', 0, 0, 0, 'Water plants', '', null, 'P1', null, 1, null, null, null, 4, 'rule'],
      ['T11', 0, 0, 0, 'In a binned project', '', null, 'P5', null, 1, null, null, null, 1, null],
      ['T12', 0, 0, 0, 'Sketch', '', null, 'P3', null, 1, null, null, null, 1, null],
      ['T13', 0, 3, 0, 'Old task', '', null, 'P4', null, 1, null, null, seconds(DateTime(2026, 9, 1, 12)), 1, null],
    ];
    return [
      'CREATE TABLE TMArea (uuid TEXT PRIMARY KEY, title TEXT, visible INTEGER, "index" INTEGER)',
      "INSERT INTO TMArea VALUES ('A1', 'Work', 1, 1), ('A2', 'Home', 1, 0)",
      'CREATE TABLE TMTag (uuid TEXT PRIMARY KEY, title TEXT, shortcut TEXT, "index" INTEGER)',
      "INSERT INTO TMTag VALUES ('G1', 'Errand', NULL, 0), ('G2', 'high energy', NULL, 1)",
      'CREATE TABLE TMTaskTag (tasks TEXT, tags TEXT)',
      "INSERT INTO TMTaskTag VALUES ('T1', 'G1'), ('P1', 'G2')",
      'CREATE TABLE TMChecklistItem (uuid TEXT PRIMARY KEY, title TEXT, status INTEGER, stopDate REAL, "index" INTEGER, task TEXT, userModificationDate REAL)',
      "INSERT INTO TMChecklistItem VALUES ('C2', 'Edit', 3, NULL, 1, 'T1', NULL), ('C1', 'Draft', 0, NULL, 0, 'T1', NULL)",
      'CREATE TABLE TMTask (uuid TEXT PRIMARY KEY, type INTEGER, status INTEGER, trashed INTEGER, title TEXT, notes TEXT, area TEXT, project TEXT, heading TEXT, start INTEGER, '
          'startDate INTEGER, deadline INTEGER, stopDate REAL, "index" INTEGER, rt1_recurrenceRule BLOB, creationDate REAL, userModificationDate REAL, todayIndex INTEGER)',
      for (final row in rows) 'INSERT INTO TMTask (uuid, type, status, trashed, title, notes, area, project, heading, start, startDate, deadline, stopDate, "index", rt1_recurrenceRule) VALUES (${row.map(q).join(', ')})',
    ];
  }

  late Directory scratch;
  late String database;
  setUp(() {
    scratch = Directory.systemTemp.createTempSync('ghost-things-');
    database = '${scratch.path}/main.sqlite';
    build(database, newSchema());
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  group('a database', () {
    late ImportHarness it;
    late ImportReport report;
    setUp(() async {
      it = ImportHarness();
      report = await importThingsLibrary(readThingsDatabase(database), it.target());
    });
    tearDown(() => it.dispose());

    test('counts what it brought and what it left', () {
      expect(report.notes, 6);
      expect(report.notebooks, 2);
      expect(report.tasks, 8);
      expect(report.skipped, ['3 done or cancelled to-dos, from the Logbook', '2 to-dos in the trash', 'the rule of one repeating to-do (its repeats are here)']);
      expect(importDoneSaid(report), 'Imported 6 notes, 8 to-dos and 2 notebooks, in the workspace Imported from Things 2026-10-16.');
    });

    test('a project: its tags and dates, its notes, its to-dos, then its headings in their order', () {
      expect(it.at('$root/Work/Launch.md')!.body, '''# Launch

#high-energy ⏳ 2026-10-20 📅 2026-10-30

Ship it.

- [ ] Write the post #Errand 📅 2026-10-25
  Two paragraphs.
  Or three.
  - [ ] Draft

## Build

- [ ] Set up CI

## Press

- [ ] Call the paper ⏳ 2026-10-21
''');
    });

    test('areas are notebooks of their pages, loose to-dos first; the rest at the top', () {
      final home = it.at('$root/Home.md')!.body;
      expect(isBookBody(home), isTrue);
      expect(chaptersOf(home).map((c) => c.title), ['Home to-dos', 'Garden']);
      expect(chaptersOf(it.at('$root/Work.md')!.body).map((c) => c.title), ['Launch']);
      expect(it.at('$root/Home/Home to-dos.md')!.body, '# Home to-dos\n\n- [ ] Buy bulbs\n');
      expect(it.at('$root/Home/Garden.md')!.body, '# Garden\n');
      expect(it.at('$root/Side project.md')!.body, '# Side project\n\n- [ ] Sketch\n');
      expect(it.at('$root/Inbox.md')!.body, '# Inbox\n\n- [ ] Inbox item\n');
      expect(it.at('$root/To-dos.md')!.body, '# To-dos\n\n- [ ] Someday idea\n');
      expect(it.at('$root/Work/Old project.md'), isNull, reason: 'done, and the Logbook not asked for');
      final id = it.workspaces.value.list.single.id;
      expect(report.noteIds.every((note) => it.workspaces.value.of[note] == id), isTrue);
    });
  });

  test('the Logbook, asked for: done and cancelled to-dos ticked with their days, a project done with them', () async {
    final it = ImportHarness();
    addTearDown(it.dispose);
    final report = await importThingsLibrary(readThingsDatabase(database), it.target(), done: true);
    expect(report.tasks, 12);
    expect(report.skipped, ['2 to-dos in the trash', 'the rule of one repeating to-do (its repeats are here)']);
    final launch = it.at('$root/Work/Launch.md')!.body;
    expect(launch, contains('  - [ ] Draft\n  - [x] Edit\n- [x] Cancelled thing ❌ 2026-10-11\n'));
    expect(launch, contains('## Build\n\n- [ ] Set up CI\n- [x] Fix login ✅ 2026-10-10\n'));
    expect(it.at('$root/Work/Old project.md')!.body, '# Old project\n\n- [x] Old task ✅ 2026-09-01\n');
    expect(chaptersOf(it.at('$root/Work.md')!.body).map((c) => c.title), ['Launch', 'Old project']);
  });

  test('an older file: dates in seconds, the heading as actionGroup, the deadline as dueDate', () async {
    final old = '${scratch.path}/old.sqlite';
    build(old, [
      'CREATE TABLE TMArea (uuid TEXT, title TEXT, "index" INTEGER)',
      "INSERT INTO TMArea VALUES ('A', 'Life', 0)",
      'CREATE TABLE TMTask (uuid TEXT, type INTEGER, status INTEGER, trashed INTEGER, title TEXT, notes TEXT, area TEXT, project TEXT, actionGroup TEXT, start INTEGER, '
          'startDate REAL, dueDate REAL, stopDate REAL, "index" INTEGER, recurrenceRule BLOB)',
      "INSERT INTO TMTask VALUES ('P', 1, 0, 0, 'Move', '<note xml:space=\"preserve\">Boxes &amp; tape</note>', 'A', NULL, NULL, 1, NULL, NULL, NULL, 0, NULL)",
      "INSERT INTO TMTask VALUES ('H', 2, 0, 0, 'Pack', '', NULL, 'P', NULL, 1, NULL, NULL, NULL, 0, NULL)",
      "INSERT INTO TMTask VALUES ('T', 0, 0, 0, 'Books', '', NULL, NULL, 'H', 1, ${seconds(DateTime(2026, 11, 1, 12))}, ${seconds(DateTime(2026, 11, 3, 12))}, NULL, 0, NULL)",
    ]);
    final it = ImportHarness();
    addTearDown(it.dispose);
    final report = await importThingsLibrary(readThingsDatabase(old), it.target());
    expect(it.at('$root/Life/Move.md')!.body, '# Move\n\nBoxes & tape\n\n## Pack\n\n- [ ] Books ⏳ 2026-11-01 📅 2026-11-03\n');
    expect(report.skipped, isEmpty);
  });

  test('days as Things packs them, and as seconds', () {
    expect(thingsPackedDay(2021, 3, 28), 132464128, reason: 'things.py’s own example');
    expect(thingsDay(132464128), '2021-03-28');
    expect(thingsDay(132464128.0), '2021-03-28');
    expect(thingsDay(seconds(DateTime(2026, 10, 16, 12))), '2026-10-16');
    expect(thingsDay(0), isNull);
    expect(thingsDay(null), isNull);
  });

  test('found where Things keeps it, newest layout first; read from a copy, its own file never touched', () async {
    final home = Directory('${scratch.path}/home')..createSync();
    expect(thingsDatabaseIn(home.path), isNull);
    final old = Directory('${home.path}/$thingsContainer/Things Database.thingsdatabase')..createSync(recursive: true);
    File(database).copySync('${old.path}/main.sqlite');
    expect(thingsDatabaseIn(home.path), '${old.path}/main.sqlite');
    final kept = Directory('${home.path}/$thingsContainer/ThingsData-7Q2RK/Things Database.thingsdatabase')..createSync(recursive: true);
    final file = File('${kept.path}/main.sqlite');
    File(database).copySync(file.path);
    expect(thingsDatabaseIn(home.path), file.path);

    final before = file.readAsBytesSync();
    final it = ImportHarness();
    addTearDown(it.dispose);
    final caches = Directory('${scratch.path}/cache')..createSync();
    final importer = Importer(picker: ImportPicker(), workspaces: WorkspaceStore(), target: it.target, home: () => home.path, scratch: () async => caches.path, onMac: true);
    expect(importer.thingsOnMacOffered, isTrue);
    final report = await importer.thingsOnMac();
    expect(report!.notes, 6);
    expect(file.readAsBytesSync(), before);
    expect(kept.listSync().map((e) => e.uri.pathSegments.last), ['main.sqlite'], reason: 'no journal, log or map made beside it');
    expect(caches.listSync(), isEmpty, reason: 'the copy thrown away');

    final nowhere = Importer(picker: ImportPicker(), workspaces: WorkspaceStore(), target: it.target, home: () => '${scratch.path}/no one', onMac: true);
    await expectLater(nowhere.thingsOnMac(), throwsA(isA<StateError>().having((e) => e.message, 'message', startsWith('Things was not found on this Mac.'))));
  });

  test('notes Things keeps in a <note>', () {
    expect(thingsNotesText('<note xml:space="preserve">a &lt;b&gt; &amp; c<br/>d</note>'), 'a <b> & c\nd');
    expect(thingsNotesText('Plain, kept as it is.'), 'Plain, kept as it is.');
  });
}
