import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/importer/import_report.dart';
import 'package:ghost_md/importer/import_sources.dart';
import 'package:ghost_md/importer/importer.dart';
import 'package:ghost_md/importer/things_paste.dart';

import 'support.dart';

/// Settings › Import › Paste from Things (lib/importer/things_paste.dart), over fixtures/things/Launch.txt: a list's
/// name and notes, to-dos as bullets, boxes and a ballot box, one done and one cancelled, a to-do's notes and its
/// checklist indented under it, a heading with a colon and one without, and a tag in a to-do's words; and the
/// titles alone that ⌘C gives on a Mac.
void main() {
  const root = 'workspaces/Imported from Things 2026-10-16';

  test('a list copied whole: its name, notes, to-dos, checklists and headings', () async {
    final it = ImportHarness();
    addTearDown(it.dispose);
    final report = await importThingsPaste(File(fixture('things/Launch.txt')).readAsStringSync(), it.target());
    expect(it.at('$root/Launch.md')!.body, '''# Launch

Everything for Friday.

- [ ] Write the post
  Two paragraphs.
  - [ ] Draft
  - [x] Outline
- [x] Pick a date
- [ ] Book the room

## Press

- [ ] Call the paper
- [x] Fax them

## Social

- [ ] Tweet it #social
''');
    expect(report.notes, 1);
    expect(report.tasks, 8);
    expect(importDoneSaid(report), 'Imported 1 note and 8 to-dos, in the workspace Imported from Things 2026-10-16.');
  });

  test('titles alone, one a line, each a to-do, in a note named for Things', () async {
    final it = ImportHarness();
    addTearDown(it.dispose);
    final report = await importThingsPaste('Buy milk\r\nCall mum\n  after six\n\n', it.target());
    expect(it.at('$root/From Things.md')!.body, '# From Things\n\n- [ ] Buy milk\n- [ ] Call mum\n  after six\n');
    expect(report.tasks, 2);
  });

  test('a `#` first line names the list', () {
    final read = readThingsPaste('# Errands\n\n- Post office\n');
    expect(read.title, 'Errands');
    expect(read.todos.single.title, 'Post office');
  });

  test('read off the clipboard; an empty one said, and nothing made', () async {
    final it = ImportHarness();
    addTearDown(it.dispose);
    var copied = '';
    final importer = Importer(picker: ImportPicker(), workspaces: WorkspaceStore(), target: it.target, clipboard: () async => copied);
    await expectLater(importer.thingsPaste(), throwsA(isA<StateError>().having((e) => e.message, 'message', startsWith('Nothing is copied.'))));
    expect(it.workspaces.value.list, isEmpty);
    copied = 'Groceries\n\n- Eggs\n';
    final report = await importer.thingsPaste();
    expect(report!.tasks, 1);
    expect(it.at('$root/Groceries.md')!.body, '# Groceries\n\n- [ ] Eggs\n');
  });
}
