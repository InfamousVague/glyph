import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/kept_trash.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/core/trash_files.dart';
import 'package:ghost_md/shell/visible_notes.dart';

import 'support.dart';

/// The trash as a folder (lib/core/trash_files.dart over library/trash.rs, here the fake core's copy of it): a note
/// trashed through the app has its file moved under `.trash/` and back, emptying deletes it, the synced map and the
/// files are read both ways at the first read (an old build's trashing, a library restored from a backup), and a
/// map entry landing from another device moves the file here too.
void main() {
  late PreferencesStore prefs;
  late KeptTrash trash;

  setUp(() {
    prefs = PreferencesStore()..startWithoutStorage();
    trash = KeptTrash(prefs: prefs, clock: () => 500);
    addTearDown(trash.dispose);
  });

  group('trash, restore and empty through the app', () {
    test('move the file under .trash/ at its own path, back again, and delete it for good', () async {
      final (:core, :library, waits: _, said: _) = libraryOver();
      await library.load();
      final filed = await library.createNote('# Plan\n\nwords\n');
      await library.apply((await library.get(filed.id))!.copyWith(path: () => 'workspaces/Work/Plan.md'));
      await core.invoke('versions_write', {'id': filed.id, 'text': '# Ghost.md versions 1\n'});
      final files = TrashFiles(library: library, trash: trash);
      addTearDown(files.dispose);

      trash.trashNote(filed.id);
      await files.settled();
      final trashed = library.noteOf(filed.id)!;
      expect(trashed.path, '.trash/workspaces/Work/Plan.md');
      expect(trashed.inTrash, isTrue);
      expect((trashed.revision, trashed.updatedAt), (filed.revision, filed.updatedAt), reason: 'a move is not an edit');
      expect(await core.invoke('versions_read', {'id': filed.id}), '# Ghost.md versions 1\n', reason: 'its versions went with it');
      // Out of every screen but the Trash's, by the map and by the file alike.
      final seen = visibleNotes(library.value, trash: trash.value);
      expect(ids(seen.visible), isEmpty);
      expect(ids(seen.trashed), [filed.id]);
      expect(ids(inTrash(library.value, const {})), [filed.id], reason: 'the file alone says it is trashed');
      expect(ids(outOfTrash(library.value, const {})), isEmpty);

      trash.restoreNote(filed.id);
      await files.settled();
      expect(library.noteOf(filed.id)!.path, 'workspaces/Work/Plan.md');
      expect(library.noteOf(filed.id)!.inTrash, isFalse);
      expect(ids(visibleNotes(library.value, trash: trash.value).visible), [filed.id]);

      // Emptied: deleted for good, then forgotten by the map; the forgetting moves nothing, the note being gone.
      trash.trashNote(filed.id);
      await files.settled();
      await library.destroy(filed.id);
      trash.forget([filed.id]);
      await files.settled();
      expect(library.value, isEmpty);
      expect(core.sent.where((call) => call.command == 'restore_note'), hasLength(2), reason: 'the restore, and the forgetting of a gone note, which the core answers with nothing');
      expect(await core.invoke('get_note', {'id': filed.id}), isNull);
    });

    test('a trash and its Undo inside the toast land in that order, and a note already where the map says costs a call and nothing more', () async {
      final (:core, :library, waits: _, said: _) = libraryOver();
      await library.load();
      final one = await library.createNote('# One\n');
      final files = TrashFiles(library: library, trash: trash);
      addTearDown(files.dispose);
      trash.trashNote(one.id);
      trash.restoreNote(one.id);
      await files.settled();
      expect(library.noteOf(one.id)!.path, 'Inbox/One.md');
      trash.trashNote(one.id);
      await files.settled();
      final before = library.noteOf(one.id)!;
      // Another device's settings landing with the same entry: nothing moves.
      prefs.update((now) => now.copyWith(trash: {one.id: 10}));
      await files.settled();
      expect(library.noteOf(one.id), same(before));
      expect(core.sent.where((call) => call.command == 'trash_note'), hasLength(2));
    });
  });

  group('the map and the files, read both ways at the first read', () {
    test('a note the map holds whose file is live (an old build trashed it) has its file moved in', () async {
      final (core: _, :library, waits: _, said: _) = libraryOver();
      await library.load();
      final one = await library.createNote('# One\n');
      final two = await library.createNote('# Two\n');
      prefs.value = Preferences.fromJson({'trash': {one.id: 10}});
      final files = TrashFiles(library: library, trash: trash);
      addTearDown(files.dispose);
      await files.settled();
      expect(library.noteOf(one.id)!.path, '.trash/Inbox/One.md');
      expect(library.noteOf(two.id)!.path, 'Inbox/Two.md');
    });

    test('a note in .trash/ the map does not know (a library restored from a backup) is in the trash, from now', () async {
      final (:core, :library, waits: _, said: _) = libraryOver();
      // The files as a clone or a backup left them: one note live, two trashed, one of them under a folder.
      await core.invoke('create_note', {'id': 'live', 'body': '# Live\n', 'source': 'editor'});
      await core.invoke('create_note', {'id': 'old', 'body': '# Old\n', 'source': 'editor'});
      await core.invoke('trash_note', {'id': 'old'});
      await core.invoke('create_note', {'id': 'gone', 'body': '# Gone\n', 'source': 'editor'});
      await core.invoke('store_apply', {'note': {...(await core.invoke('get_note', {'id': 'gone'}) as Map).cast<String, Object?>(), 'path': '.trash/workspaces/Work/Gone.md'}});
      final files = TrashFiles(library: library, trash: trash);
      addTearDown(files.dispose);
      expect(files.reconciled, isFalse, reason: 'nothing read yet');
      await library.load();
      await files.settled();
      expect(files.reconciled, isTrue);
      expect(trash.value, {'old': 500, 'gone': 500}, reason: 'trashed now: the thirty days start from this reading');
      expect(ids(visibleNotes(library.value, trash: trash.value).visible), ['live']);
      expect(library.noteOf('gone')!.path, '.trash/workspaces/Work/Gone.md', reason: 'the adoption moves nothing');
      // Restored from the Trash: its folder was never in this clone (only the trash's copy was), so it lands in the
      // Inbox, as a note whose folder is gone does.
      trash.restoreNote('gone');
      await files.settled();
      expect(library.noteOf('gone')!.path, 'Inbox/Gone.md');
    });

    test('is not run again for a note that later arrives trashed by sync: that device’s map entry is on its way', () async {
      final (:core, :library, waits: _, said: _) = libraryOver();
      await library.load();
      final files = TrashFiles(library: library, trash: trash);
      addTearDown(files.dispose);
      final theirs = await core.invoke('create_note', {'id': 'synced', 'body': '# Synced\n', 'source': 'editor'}) as Map;
      await library.apply(Note(id: 'synced', body: '# Synced\n', createdAt: theirs['createdAt'] as int, updatedAt: theirs['updatedAt'] as int, path: '.trash/Inbox/Synced.md'));
      await files.settled();
      expect(trash.value, isEmpty);
      expect(library.noteOf('synced')!.inTrash, isTrue);
      expect(ids(visibleNotes(library.value, trash: trash.value).visible), isEmpty, reason: 'never shown live meanwhile');
      // The entry lands: nothing to move. Its restore lands: the file comes back.
      prefs.update((now) => now.copyWith(trash: {'synced': 10}));
      await files.settled();
      expect(library.noteOf('synced')!.path, '.trash/Inbox/Synced.md');
      prefs.update((now) => now.copyWith(trash: {}));
      await files.settled();
      expect(library.noteOf('synced')!.path, 'Inbox/Synced.md');
    });
  });

  test('the invented library in memory keeps up: a trashed note is given a path in the trash and loses it again', () async {
    final library = SampleLibrary.seeded(now: 1000);
    final held = MemoryTrash();
    final files = TrashFiles(library: library, trash: held);
    addTearDown(files.dispose);
    final first = library.value.first;
    held.trashNote(first.id);
    await files.settled();
    expect(library.noteOf(first.id)!.inTrash, isTrue);
    expect(ids(outOfTrash(library.value, const {})), isNot(contains(first.id)));
    held.restoreNote(first.id);
    await files.settled();
    expect(library.noteOf(first.id)!.inTrash, isFalse);
    expect(library.noteOf(first.id)!.path, first.path);
  });

  test('the paths: under .trash/ at the root, and back', () {
    expect(isTrashedPath('.trash/Inbox/Plan.md'), isTrue);
    expect(isTrashedPath('Inbox/Plan.md'), isFalse);
    expect(isTrashedPath('Work/.trash/Plan.md'), isFalse, reason: 'another app’s trash in a folder');
    expect(isTrashedPath(null), isFalse);
    expect(trashedPathOf('workspaces/Work/Plan.md'), '.trash/workspaces/Work/Plan.md');
    expect(trashedPathOf('.trash/Inbox/Plan.md'), '.trash/Inbox/Plan.md');
    expect(livePathOf('.trash/workspaces/Work/Plan.md'), 'workspaces/Work/Plan.md');
    expect(livePathOf('Inbox/Plan.md'), 'Inbox/Plan.md');
    expect(livePathOf(null), isNull);
  });
}
