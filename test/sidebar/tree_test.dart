import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart' show Workspace;
import 'package:ghost_md/notes/tree.dart';

/// `notes/tree.test.ts`, case for case.
Note makeNote(String id, {String? body, int updatedAt = 0, bool starred = false, int? archivedAt}) =>
    Note(id: id, body: body ?? '# $id', createdAt: 0, updatedAt: updatedAt, starred: starred, archivedAt: archivedAt);

List<String> ids(Iterable<Note> notes) => [for (final n in notes) n.id];

void main() {
  group('the notes as the sidebar shows them', () {
    test('puts each note in its workspace, and the rest below', () {
      final tree = noteTree(
        [makeNote('a'), makeNote('b'), makeNote('c')],
        list: const [Workspace(id: 'w1', name: 'Work'), Workspace(id: 'w2', name: 'Home')],
        of: const {'a': 'w1', 'b': 'w2'},
      );
      expect([for (final f in tree.folders) [f.name, ids(f.notes)]], [
        ['Work', ['a']],
        ['Home', ['b']],
      ]);
      expect(ids(tree.loose), ['c']);
    });

    test('keeps an empty workspace, so it can still be filed into', () {
      final tree = noteTree([makeNote('a')], list: const [Workspace(id: 'w1', name: 'Work')], of: const {});
      expect(tree.folders, hasLength(1));
      expect([tree.folders[0].id, tree.folders[0].name, tree.folders[0].hue, tree.folders[0].notes], ['w1', 'Work', null, isEmpty]);
      expect(ids(tree.loose), ['a']);
    });

    test('treats a note filed in a workspace that has gone as filed in none', () {
      final tree = noteTree([makeNote('a')], list: const [], of: const {'a': 'gone'});
      expect(ids(tree.loose), ['a']);
    });

    test('keeps archived notes out of the folders and in the archive', () {
      final tree = noteTree(
        [makeNote('a', body: '# a', archivedAt: 5), makeNote('b')],
        list: const [Workspace(id: 'w1', name: 'Work')],
        of: const {'a': 'w1', 'b': 'w1'},
      );
      expect(ids(tree.folders[0].notes), ['b']);
      expect(ids(tree.archived), ['a']);
    });

    test('orders a folder as the list does: pinned first, then the most recent', () {
      final tree = noteTree(
        [makeNote('old', updatedAt: 1), makeNote('new', updatedAt: 9), makeNote('pin', updatedAt: 0, starred: true)],
        list: const [Workspace(id: 'w1', name: 'Work')],
        of: const {'old': 'w1', 'new': 'w1', 'pin': 'w1'},
      );
      expect(ids(tree.folders[0].notes), ['pin', 'new', 'old']);
    });

    test('carries a workspace colour through', () {
      final tree = noteTree(const [], list: const [Workspace(id: 'w1', name: 'Work', hue: 'sea')], of: const {});
      expect(tree.folders[0].hue, 'sea');
    });
  });

  group('the list’s own order (core/store.ts)', () {
    test('keeps notes touched at the same moment in the order they came, as the page’s sort does', () {
      expect(ids(listOrder([makeNote('a'), makeNote('b'), makeNote('c'), makeNote('z', archivedAt: 0)])), ['a', 'b', 'c', 'z']);
    });

    test('puts the most recently archived first', () {
      expect(ids(archiveOrder([makeNote('a', archivedAt: 1), makeNote('b'), makeNote('c', archivedAt: 7)])), ['c', 'a']);
    });
  });

  group('which folders are closed', () {
    late MemoryStored local;
    setUp(() => local = MemoryStored());

    test('starts with only the archive closed', () {
      expect([...readClosed(local)], [archiveFolder]);
    });

    test('remembers what was closed on this device', () {
      writeClosed({'w1'}, local);
      expect([...readClosed(local)], ['w1']);
    });

    test('reads rubbish as the starting state', () {
      local.setItem('glyph-tree-closed', 'not json');
      expect([...readClosed(local)], [archiveFolder]);
    });

    test('asks the app’s own memory when handed none', () {
      final was = stored;
      addTearDown(() => useStored(was));
      useStored(local);
      writeClosed({'w2'});
      expect(local.getItem('glyph-tree-closed'), '["w2"]');
      expect([...readClosed()], ['w2']);
    });
  });

  group('the sidebar’s other switches, per device', () {
    test('keep the trash shut and the notes drawn small until they are changed, and remember each change', () {
      final local = MemoryStored();
      expect(readTrashOpen(local), isFalse);
      expect(readCompact(local), isFalse);
      writeTrashOpen(true, local);
      writeCompact(true, local);
      expect([readTrashOpen(local), readCompact(local)], [true, true]);
      expect([local.getItem('glyph-tree-trash-open'), local.getItem('glyph-tree-compact')], ['1', '1']);
      writeTrashOpen(false, local);
      expect(readTrashOpen(local), isFalse);
      expect(local.getItem('glyph-tree-trash-open'), '0');
    });
  });
}
