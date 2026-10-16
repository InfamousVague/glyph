import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_folders.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/importer/import_paths.dart';

/// Where an import puts each note (lib/importer/import_paths.dart), and the two changes beside it: filing many notes
/// at once (`WorkspaceStore.fileNotes`) and a note kept in a folder inside its workspace's (`NoteFolders`).
void main() {
  test('names cleaned as the library cleans a file’s', () {
    expect(cleanStem('  Plan: v2 / #draft [old]?  '), 'Plan v2 draft old');
    expect(cleanStem('.hidden.'), 'hidden');
    expect(cleanStem('***'), 'Untitled');
    expect(cleanStem('a' * 100).length, 80);
    expect(cleanStem('${'word ' * 30}end'), hasLength(lessThanOrEqualTo(80)));
  });

  test('a group named for the day, and numbered when the day has one', () {
    final at = DateTime(2026, 10, 16, 9);
    expect(importGroupName('Obsidian', at, const ['Work']), 'Imported from Obsidian 2026-10-16');
    expect(importGroupName('Obsidian', at, const ['imported from obsidian 2026-10-16']), 'Imported from Obsidian 2026-10-16 (2)');
    expect(importGroupName('Obsidian', at, const ['Imported from Obsidian 2026-10-16', 'Imported from Obsidian 2026-10-16 (2)']), 'Imported from Obsidian 2026-10-16 (3)');
  });

  test('paths are free, ignoring case, and each rename is kept', () {
    final paths = ImportPaths(taken: const ['workspaces/G/Notes/Plan.md'], group: 'G');
    expect(paths.place(['Notes'], 'Plan', original: 'Notes/Plan.md'), 'workspaces/G/Notes/Plan 2.md');
    expect(paths.place(['Notes'], 'plan'), 'workspaces/G/Notes/plan 3.md');
    expect(paths.place(['Other'], 'Plan'), 'workspaces/G/Other/Plan.md');
    expect(paths.place(['a:b'], 'x?y'), 'workspaces/G/ab/xy.md');
    expect(paths.renamed, [(from: 'Notes/Plan.md', to: 'Plan 2.md'), (from: 'plan.md', to: 'plan 3.md')]);
  });

  test('many notes filed at once: one change, one word to the folders', () {
    final told = <String>[];
    final store = WorkspaceStore(onFiled: (ids, w) => told.add('${ids.join(',')} ${w?.name}'));
    final g = store.addWorkspace('G')!;
    var changes = 0;
    store.addListener(() => changes += 1);
    store.fileNotes(['a', 'b', 'c'], g.id);
    expect(store.value.of, {'a': g.id, 'b': g.id, 'c': g.id});
    expect(changes, 1);
    expect(told, ['a,b,c G']);
    store.fileNotes(['a', 'b', 'd'], g.id);
    expect(told.last, 'd G', reason: 'only what moved');
    store.fileNotes(['a'], 'nobody');
    expect(store.value.of['a'], g.id);
  });

  test('a note in a folder inside its workspace’s stays there; one outside is moved in', () async {
    final library = SampleLibrary([
      const Note(id: 'deep', body: 'Deep', createdAt: 1, updatedAt: 1, path: 'workspaces/G/Projects/Deep.md'),
      const Note(id: 'loose', body: 'Loose', createdAt: 1, updatedAt: 1, path: 'Inbox/Loose.md'),
    ]);
    final folders = NoteFolders(library, log: (_) {});
    const g = Workspace(id: 'g', name: 'G');
    await folders.fileNotesInFolder(['deep', 'loose'], g);
    expect(library.noteOf('deep')!.path, 'workspaces/G/Projects/Deep.md');
    expect(library.noteOf('loose')!.path, 'workspaces/G/Loose.md');
  });
}
