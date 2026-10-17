import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/importer/import_report.dart';
import 'package:ghost_md/importer/import_sources.dart';
import 'package:ghost_md/importer/todoist_csv.dart';

import 'support.dart';

/// Settings › Import › Todoist CSV export (lib/importer/todoist_csv.dart), over fixtures/todoist/Garden.csv: a byte
/// order mark, a meta row and an empty one, labels in the words, a comment, a quoted cell with a comma, another with
/// doubled quotes, a description across two lines, a section, sub-tasks three deep, every priority and an empty one,
/// and dates as an ISO day, a recurrence, `today at 11:00`, words with no day, and a month's name.
void main() {
  const root = 'workspaces/Imported from Todoist 2026-10-16';

  test('an export: its tasks, sections, labels, comments, priorities and dates', () async {
    final it = ImportHarness();
    addTearDown(it.dispose);
    final report = await importTodoistCsv([DirectoryFile(fixture('todoist/Garden.csv'))], it.target());
    expect(it.at('$root/Garden.md')!.body, '''# Garden

- [ ] Order seeds #shopping #spring ⏫ 📅 2026-10-20
  The heirloom ones
- [ ] Fix the fence, again 🔁 every Saturday

## Beds

Raised ones first.

- [ ] Dig the bed [deadline:: 2026-10-31] 🔼 📅 2026-10-16
  Two spades deep.
  Then compost.
  - [ ] Find the "good" spade [when:: next monday] 🔽
    - [ ] Oil it 📅 2026-10-25
- [ ] Water
''');
    expect(report.notes, 1);
    expect(report.notebooks, 0);
    expect(report.tasks, 6);
    expect(report.skipped, ['one date Ghost.md could not read as a day, kept in its words']);
    expect(importDoneSaid(report), 'Imported 1 note and 6 to-dos, in the workspace Imported from Todoist 2026-10-16.');
  });

  test('a file that is not an export is said, and the rest still come in', () async {
    final it = ImportHarness();
    addTearDown(it.dispose);
    final bad = File('${it.data.path}/Shopping.csv')..writeAsStringSync('Name,Price\nMilk,1\n');
    final report = await importTodoistCsv([DirectoryFile(bad.path), DirectoryFile(fixture('todoist/Garden.csv'))], it.target());
    expect(report.skipped.first, 'Shopping.csv, not a Todoist export Ghost.md can read');
    expect(report.notes, 1);
  });

  test('a spreadsheet’s semicolons, and a priority Todoist’s screens count', () {
    final read = todoistCsvProject('TYPE;CONTENT;PRIORITY;INDENT\ntask;Weed;2;1\r\ntask;Mow;9;1\n', 'Lawn', DateTime(2026, 10, 16));
    expect([for (final task in read.tasks) (task.content, task.priority)], [('Weed', 3), ('Mow', 1)]);
  });

  test('cells as RFC 4180 has them', () {
    expect(csvRows('a,"b,c","d ""e"""\n"f\ng",,h'), [
      ['a', 'b,c', 'd "e"'],
      ['f\ng', '', 'h'],
    ]);
    expect(csvRows('x\r\ny\r\n'), [['x'], ['y']]);
  });

  test('a day from Todoist’s words, or none', () {
    final today = DateTime(2026, 10, 16);
    expect(todoistDayFromWords('2026-11-02', today), '2026-11-02');
    expect(todoistDayFromWords('today at 11:00', today), '2026-10-16');
    expect(todoistDayFromWords('Tomorrow', today), '2026-10-17');
    expect(todoistDayFromWords('Oct 25', today), '2026-10-25');
    expect(todoistDayFromWords('Mar 3', today), '2027-03-03', reason: 'past this year: next year’s');
    expect(todoistDayFromWords('20 December 2026', today), '2026-12-20');
    expect(todoistDayFromWords('October 20, 2027', today), '2027-10-20');
    expect(todoistDayFromWords('Feb 30 2027', today), isNull);
    expect(todoistDayFromWords('next monday', today), isNull);
    expect(todoistDayFromWords('every friday', today), isNull);
    expect(todoistDayFromWords('Marching 3', today), isNull);
  });
}
