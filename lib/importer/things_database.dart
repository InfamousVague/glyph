/// Things 3's own database on this Mac, read and never written (Settings › Import › From Things on this Mac).
///
/// **Where.** `~/Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac/ThingsData-*/Things
/// Database.thingsdatabase/main.sqlite` since Things 3.15.16, and before it the same without the `ThingsData-*`
/// folder ([thingsDatabaseIn]). The Mac asks the person once whether Ghost.md may read another app's data; the
/// App Store's build, sandboxed, cannot reach the folder at all, and says so.
///
/// **Never Things' own file.** The database, with its write-ahead log and its map beside it, is copied into a
/// folder of the import's own and the copy read (lib/carry/sqlite_read.dart, the system's SQLite over `dart:ffi`),
/// then thrown away: Things may be open and writing, and nothing here could ever take a lock on its file or fold
/// its log.
///
/// **What is read**, the tables things.py (the open-source reader of the same file) reads:
///
/// - `TMArea` (`uuid`, `title`, `"index"`): the areas.
/// - `TMTask`: every to-do (`type` 0), project (1) and heading (2), with `status` (0 open, 2 cancelled, 3 done),
///   `trashed`, `title`, `notes`, `area`, `project`, `heading` (a to-do's heading; `actionGroup` in older
///   files), `start` (0 Inbox, 1 Anytime, 2 Someday), `startDate` (When), `deadline` (`dueDate` in older files),
///   `stopDate` (done or cancelled), `"index"` and `rt1_recurrenceRule` (set on a repeating to-do's template).
/// - `TMTag` and `TMTaskTag` (`tasks`, `tags`): each item's tags.
/// - `TMChecklistItem` (`title`, `status`, `stopDate`, `"index"`, `task`): each to-do's checklist.
///
/// The columns a file has are asked first (`PRAGMA table_info`), so a column an older or newer Things lacks is
/// read as nothing rather than failing the import.
///
/// **Dates** ([thingsDay]). `startDate` and `deadline` are a day packed in an integer in the files things.py reads
/// now (its `Meta` `databaseVersion` above 21): `YYYYYYYYYYYMMMMDDDDD0000000` in binary, the year from bit 16, the
/// month from bit 12, the day from bit 7 (2021-03-28 is 132464128). Older files kept them as seconds since 1970, as
/// `stopDate` always is (a `REAL`); a value is read as whichever it can be, so both come in.
library;

import 'dart:io';

import '../carry/sqlite_read.dart';
import 'things.dart';

/// Things' folder in the Group Containers, under the home folder.
const String thingsContainer = 'Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac';

/// The database under [home], the newest layout first; null where there is none.
String? thingsDatabaseIn(String home) {
  final container = Directory('$home/$thingsContainer');
  try {
    if (!container.existsSync()) return null;
    final data = [
      for (final entry in container.listSync(followLinks: false))
        if (entry is Directory && entry.uri.pathSegments.where((s) => s.isNotEmpty).last.startsWith('ThingsData-')) entry.path,
    ]..sort();
    for (final folder in data) {
      final file = File('$folder/Things Database.thingsdatabase/main.sqlite');
      if (file.existsSync()) return file.path;
    }
    final old = File('${container.path}/Things Database.thingsdatabase/main.sqlite');
    if (old.existsSync()) return old.path;
  } on FileSystemException {
    throw StateError('Ghost.md may not read Things’ data on this Mac. Allow it in System Settings › Privacy & Security, or use Paste from Things.');
  }
  return null;
}

/// A day as Things keeps one, `YYYY-MM-DD`: a packed day, or seconds since 1970 (older files, and every
/// `stopDate`), read in this device's time. Null for none (null or 0). A packed day is below 2^27 with its low
/// seven bits clear; seconds that small would be 1974, before Things.
String? thingsDay(Object? said) {
  if (said is! num || said == 0) return null;
  if (said is int || said == said.truncateToDouble()) {
    final packed = said.toInt();
    final year = (packed & 0x7FF0000) >> 16, month = (packed & 0xF000) >> 12, day = (packed & 0xF80) >> 7;
    if (packed & 0x7F == 0 && packed < 0x8000000 && year >= 1900 && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    }
  }
  final at = DateTime.fromMillisecondsSinceEpoch((said * 1000).round());
  return '${at.year.toString().padLeft(4, '0')}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
}

/// A day as Things packs one: what a test writes its fixture's dates with.
int thingsPackedDay(int year, int month, int day) => year << 16 | month << 12 | day << 7;

ThingsStatus _status(Object? said) => switch (said) {
      2 => ThingsStatus.cancelled,
      3 => ThingsStatus.done,
      _ => ThingsStatus.open,
    };

/// What the database at [file] holds. [file] is a copy of the import's own ([readThingsCopy] makes one); read with
/// [SqliteRead], so on a device with no system SQLite this throws.
ThingsLibrary readThingsDatabase(String file) {
  List<List<Object?>> rows(String sql) => SqliteRead.rows(file, sql, ownCopy: true);
  Set<String> columns(String table) => {for (final row in rows('PRAGMA table_info($table)')) '${row[1]}'};
  final task = columns('TMTask');
  if (task.isEmpty) throw const FormatException('no TMTask: not a Things database');
  String pick(List<String> names) {
    for (final name in names) {
      if (task.contains(name)) return '"$name"';
    }
    return 'NULL';
  }

  final areaColumns = columns('TMArea');
  final areas = areaColumns.isEmpty
      ? <ThingsArea>[]
      : [
          for (final row in rows('SELECT uuid, title, ${areaColumns.contains('index') ? '"index"' : '0'} FROM TMArea'))
            ThingsArea(id: '${row[0]}', title: row[1] is String ? row[1] as String : '', order: row[2] is int ? row[2] as int : 0),
        ];

  final tagNames = columns('TMTag').isEmpty ? <String, String>{} : {for (final row in rows('SELECT uuid, title FROM TMTag')) '${row[0]}': row[1] is String ? row[1] as String : ''};
  final tags = <String, List<String>>{};
  if (columns('TMTaskTag').isNotEmpty) {
    for (final row in rows('SELECT tasks, tags FROM TMTaskTag')) {
      final name = tagNames['${row[1]}'];
      if (name != null && name.trim().isNotEmpty) (tags['${row[0]}'] ??= []).add(name);
    }
  }

  final checklists = <String, List<ThingsCheck>>{};
  final check = columns('TMChecklistItem');
  if (check.isNotEmpty) {
    final stop = check.contains('stopDate') ? 'stopDate' : 'NULL';
    final order = check.contains('index') ? '"index"' : '0';
    for (final row in rows('SELECT task, title, status, $stop, $order FROM TMChecklistItem')) {
      (checklists['${row[0]}'] ??= []).add(ThingsCheck(title: row[1] is String ? row[1] as String : '', status: _status(row[2]), stopped: thingsDay(row[3]), order: row[4] is int ? row[4] as int : 0));
    }
  }

  final sql = 'SELECT uuid, type, ${pick(['status'])}, ${pick(['trashed'])}, ${pick(['title'])}, ${pick(['notes'])}, ${pick(['area'])}, '
      '${pick(['project'])}, ${pick(['heading', 'actionGroup'])}, ${pick(['start'])}, ${pick(['startDate'])}, ${pick(['deadline', 'dueDate'])}, '
      '${pick(['stopDate'])}, ${pick(['index'])}, ${pick(['rt1_recurrenceRule', 'recurrenceRule'])} FROM TMTask';
  String? id(Object? said) => said is String && said.isNotEmpty ? said : null;
  final items = [
    for (final row in rows(sql))
      if (row[1] case final int kind when kind >= 0 && kind <= 2)
        ThingsItem(
          id: '${row[0]}',
          kind: ThingsKind.values[kind],
          status: _status(row[2]),
          trashed: row[3] == 1,
          title: row[4] is String ? row[4] as String : '',
          notes: row[5] is String ? row[5] as String : '',
          area: id(row[6]),
          project: id(row[7]),
          heading: id(row[8]),
          start: switch (row[9]) {
            0 => ThingsStart.inbox,
            2 => ThingsStart.someday,
            _ => ThingsStart.anytime,
          },
          when: thingsDay(row[10]),
          deadline: thingsDay(row[11]),
          stopped: thingsDay(row[12]),
          order: row[13] is int ? row[13] as int : 0,
          repeating: row[14] != null && !(row[14] is String && (row[14] as String).isEmpty),
          tags: tags['${row[0]}'] ?? const [],
          checklist: checklists['${row[0]}'] ?? const [],
        ),
  ];
  return ThingsLibrary(areas: areas, items: items);
}

/// [database] copied into a folder of its own under [scratch] with its log and map, read, and the copy removed.
Future<ThingsLibrary> readThingsCopy(String database, String scratch) async {
  final folder = await Directory(scratch).createTemp('things-');
  try {
    final copy = '${folder.path}/main.sqlite';
    await File(database).copy(copy);
    for (final side in ['-wal', '-shm']) {
      final beside = File('$database$side');
      if (await beside.exists()) await beside.copy('$copy$side');
    }
    return readThingsDatabase(copy);
  } on FileSystemException {
    throw StateError('Things’ data could not be read. Allow Ghost.md in System Settings › Privacy & Security, or use Paste from Things.');
  } on SqliteFailure catch (failure) {
    throw StateError('Things’ data could not be read (${failure.said}).');
  } on FormatException {
    throw StateError('That is not a Things database Ghost.md can read.');
  } finally {
    await folder.delete(recursive: true).then<void>((_) {}, onError: (Object _) {});
  }
}
