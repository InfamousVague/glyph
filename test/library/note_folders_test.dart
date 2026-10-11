import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_folders.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';

import 'support.dart';

/// The folder a note is filed in (lib/core/note_folders.dart): the cases of the web's `core/noteFolders.test.ts`,
/// against a fake of the library where the web mocks its store.
const Workspace home = Workspace(id: 'w-home', name: 'Home');
const Workspace ghost = Workspace(id: 'org-abc', name: 'Ghost');

void main() {
  /// The `store_apply` notes sent so far, by their paths.
  List<Object?> applied(FakeCore core) => [
        for (final each in core.sent)
          if (each.command == 'store_apply') (each.args['note'] as Map)['path'],
      ];

  /// A library holding the one note these tests file, at [path].
  Future<({FakeCore core, NoteFolders folders})> filed(String path) async {
    final core = FakeCore()..seed('n1', '# Weekend trip', path: path);
    final it = libraryOver(core);
    await it.library.load();
    return (core: core, folders: NoteFolders(it.library, log: it.said.add));
  }

  group('the folder a note is filed in', () {
    test('names a folder after the workspace, and the inbox for none', () {
      expect(folderFor(home), 'workspaces/Home');
      expect(folderFor(null), 'Inbox');
      // What a file name cannot hold goes, and a name that cleans away to nothing is no folder at all.
      expect(folderName('Work/Clients: 2026?'), 'WorkClients 2026');
      expect(folderFor(const Workspace(id: 'w-1', name: '  ///  ')), isNull);
      expect(folderFor(const Workspace(id: 'w-1', name: '..')), isNull);
    });

    test('files an organization’s workspace under orgs/, apart from a personal workspace of the same name', () {
      expect(folderFor(ghost), 'orgs/Ghost');
      expect(folderFor(const Workspace(id: 'w-ghost', name: 'Ghost')), 'workspaces/Ghost');
      // The organization's name is another account's choice, and is cleaned like any other.
      expect(folderFor(const Workspace(id: 'org-abc', name: '../Ghost: 2026')), 'orgs/Ghost 2026');
      expect(folderFor(const Workspace(id: 'org-abc', name: '..')), isNull);
    });

    test('keeps a folder’s name to sixty characters, with no space left on its end', () {
      expect(folderName('${'a' * 59} bcd'), 'a' * 59);
      expect(folderName('  Many   spaces\tinside  '), 'Many spaces inside');
    });

    test('moves the file into the workspace folder, keeping its name', () async {
      final it = await filed('Inbox/Weekend trip.md');
      await it.folders.fileNoteInFolder('n1', home);
      expect(applied(it.core), ['workspaces/Home/Weekend trip.md']);
      expect(it.core.files, ['workspaces/Home/Weekend trip.md']);
      await it.folders.fileNoteInFolder('n1', ghost);
      expect(applied(it.core).last, 'orgs/Ghost/Weekend trip.md');
      expect(it.core.files, ['orgs/Ghost/Weekend trip.md']);
    });

    test('moves it back to the inbox when it leaves a workspace', () async {
      final it = await filed('workspaces/Home/Weekend trip.md');
      await it.folders.fileNoteInFolder('n1', null);
      expect(applied(it.core), ['Inbox/Weekend trip.md']);
    });

    test('leaves the words alone and asks for nothing it cannot do', () async {
      final it = await filed('Inbox/Weekend trip.md');
      await it.folders.fileNoteInFolder('n1', home);
      final sent = it.core.sent.lastWhere((each) => each.command == 'store_apply').args['note'] as Map;
      expect(sent['body'], '# Weekend trip');
      final before = applied(it.core).length;

      // Already there: nothing to ask for.
      await it.folders.fileNoteInFolder('n1', home);
      expect(applied(it.core), hasLength(before));

      // A name that cleans away to nothing: the note stays where it is.
      await it.folders.fileNoteInFolder('n1', const Workspace(id: 'w-1', name: '..'));
      expect(applied(it.core), hasLength(before));

      // A note nothing answers to.
      await it.folders.fileNoteInFolder('nobody', home);
      expect(applied(it.core), hasLength(before));
    });

    test('does nothing for a draft, which has no file to move', () async {
      final it = libraryOver();
      await it.library.load();
      await it.library.createNote('', id: 'd1');
      await NoteFolders(it.library).fileNoteInFolder('d1', home);
      expect(it.core.asked('store_apply'), 0);
    });

    test('does nothing over a library with no files at all, as in a browser', () async {
      final library = SampleLibrary([makeNote('n1', body: '# Weekend trip')]);
      await NoteFolders(library).fileNoteInFolder('n1', home);
      expect(library.noteOf('n1')!.path, isNull);
    });
  });

  group('the move itself', () {
    test('always hands back the note fetched whole, never the list’s copy: get, then apply', () async {
      final it = await filed('Inbox/Weekend trip.md');
      await it.core.invoke('set_note_recording', {
        'id': 'n1',
        'recordingMs': 400,
        'segments': [
          {'text': 'hello', 'startMs': 0, 'endMs': 400},
        ],
      });
      it.core.sent.clear();
      await it.folders.fileNoteInFolder('n1', home);
      expect([for (final each in it.core.sent.take(2)) each.command], ['get_note', 'store_apply']);
      // So what is kept beside the note is still there after it.
      final after = await it.core.invoke('get_note', {'id': 'n1'}) as Map;
      expect(after['segments'], hasLength(1));
      expect(after['path'], 'workspaces/Home/Weekend trip.md');
    });

    test('keeps the note’s own times, pin and revision: a note moved is not a note edited', () async {
      final core = FakeCore(now: 9000)..seed('n1', '# Weekend trip', at: 100, starred: true, revision: 6);
      final it = libraryOver(core);
      await it.library.load();
      await NoteFolders(it.library).fileNoteInFolder('n1', home);
      final Note moved = it.library.noteOf('n1')!;
      expect((moved.path, moved.updatedAt, moved.createdAt, moved.starred, moved.revision), ('workspaces/Home/Weekend trip.md', 100, 100, true, 6));
    });

    test('is quiet when the library refuses, and the note stays where it was', () async {
      final it = await filed('Inbox/Weekend trip.md');
      it.core.fail('store_apply', message: 'Permission denied');
      final said = <String>[];
      final library = libraryOver(it.core);
      await library.library.load();
      await NoteFolders(library.library, log: said.add).fileNoteInFolder('n1', home);
      expect(said.single, '[glyph] the note stayed where it was: Permission denied');
      expect(it.core.files, ['Inbox/Weekend trip.md']);
    });

    test('files several, one after another, in the order they were asked', () async {
      final core = FakeCore()
        ..seed('a', '# A')
        ..seed('b', '# B');
      final it = libraryOver(core);
      await it.library.load();
      final folders = NoteFolders(it.library);
      final first = folders.fileNotesInFolder(['a', 'b'], home);
      final second = folders.fileNotesInFolder(['a'], null);
      await Future.wait([first, second]);
      expect(core.files, ['Inbox/A.md', 'workspaces/Home/B.md']);
    });

    test('does not take a place another note’s file already has', () async {
      final core = FakeCore()
        ..seed('there', '# Weekend trip', path: 'workspaces/Home/Weekend trip.md')
        ..seed('n1', '# Weekend trip', path: 'Inbox/Weekend trip.md');
      final it = libraryOver(core);
      await it.library.load();
      await NoteFolders(it.library).fileNoteInFolder('n1', home);
      // library/mod.rs `apply_note` moves only to a path that is free; the note stays put.
      expect(core.files, ['Inbox/Weekend trip.md', 'workspaces/Home/Weekend trip.md']);
    });
  });
}
