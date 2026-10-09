import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/core_library.dart';
import 'package:ghost_md/core/library.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_json.dart';

import 'support.dart';

/// The notes over the core (lib/core/core_library.dart): the cases of the web's `core/store.test.ts` for the store
/// itself, run against a fake of the Rust library where the web runs them against its browser half, and the
/// `useNotes` hook's first read and read again, which the web has no test of.
///
/// Not here: the list's labels (`noteTitle`, test/core/note_text_test.dart), and a command's write and its undo,
/// which are test/library/command_mutations_test.dart's.
Matcher refuses(String sentence) => throwsA(isA<CoreError>().having((e) => e.message, 'message', sentence));

void main() {
  group('the list order', () {
    test('puts starred notes first and hides the archived', () {
      final notes = [makeNote('old', updatedAt: 1), makeNote('new', updatedAt: 3), makeNote('starred-old', updatedAt: 0, starred: true), makeNote('gone', updatedAt: 9, archivedAt: 5)];
      expect(ids(listOrder(notes)), ['starred-old', 'new', 'old']);
    });

    test('shows the archive most recently archived first', () {
      final notes = [makeNote('a', updatedAt: 1, archivedAt: 10), makeNote('b', updatedAt: 2, archivedAt: 20), makeNote('live', updatedAt: 3)];
      expect(ids(archiveOrder(notes)), ['b', 'a']);
    });
  });

  group('a new note’s id', () {
    test('is a random UUID the library compares as text', () {
      // note.rs `a_new_id_is_a_random_uuid_the_page_compares_as_text`.
      final one = newNoteId(), two = newNoteId();
      expect(one, isNot(two));
      expect(one, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(one.length, 36);
    });
  });

  group('the store over the core', () {
    test('stores a new note with its pin said, so a phone that syncs it is told', () async {
      final it = libraryOver();
      final made = await it.library.createNote('Made here', id: 'web-pin');
      expect(made.starred, isFalse);
      expect((await it.library.get('web-pin'))!.starred, isFalse);
    });

    test('makes a note at revision 1, lists newest first, and will not make one twice', () async {
      final it = libraryOver();
      var saved = 0;
      it.library.touched.addListener(() => saved += 1);
      await it.library.createNote('# First', id: 'a');
      it.core.now = 2000;
      final b = await it.library.createNote('# Second', source: NoteSource.capture, id: 'b');
      expect(noteToJson(b), {
        'id': 'b',
        'body': '# Second',
        'createdAt': 2000,
        'updatedAt': 2000,
        'source': 'capture',
        'starred': false,
        'archivedAt': null,
        'recordingMs': null,
        'segments': null,
        'formatted': null,
        'formattedFor': null,
        'formattedModel': null,
        'path': 'Inbox/Second.md',
        'revision': 1,
      });
      expect(ids(it.library.value), ['b', 'a']);
      await expectLater(it.library.createNote('again', id: 'a'), refuses('the note id already exists'));
      // The note that was there is still the one in the list.
      expect(it.library.noteOf('a')!.body, '# First');
      expect(saved, 2);
    });

    test('writes an edit only over the revision it read, keeping when the note was made', () async {
      final it = libraryOver();
      await it.library.createNote('one', id: 'a');
      it.core.now = 5000;
      final two = await it.library.update('a', 'two', 1);
      expect((two.body, two.createdAt, two.updatedAt, two.revision), ('two', 1000, 5000, 2));
      // A save from a screen that read revision 1 is stale now, and a deleted note is not brought back by one.
      await expectLater(it.library.update('a', 'stale', 1), refuses('the note was deleted or changed'));
      await it.library.destroy('a');
      await expectLater(it.library.update('a', 'resurrected', 2), refuses('the note was deleted or changed'));
      expect(await it.library.get('a'), isNull);
      expect(it.library.value, isEmpty);
    });

    test('pins and archives without counting as an edit', () async {
      final it = libraryOver();
      await it.library.createNote('words', id: 'a');
      it.core.now = 9000;
      await it.library.pin('a', pinned: true);
      expect((it.library.noteOf('a')!.starred, it.library.noteOf('a')!.updatedAt), (true, 1000));
      await it.library.archive('a', archived: true);
      expect((it.library.noteOf('a')!.archivedAt, it.library.noteOf('a')!.updatedAt), (9000, 1000));
      await it.library.archive('a', archived: false);
      expect(it.library.noteOf('a')!.archivedAt, isNull);
      expect((await it.library.get('a'))!.body, 'words');
      // A note that has gone answers nothing, and that is not an error.
      await it.library.pin('gone', pinned: true);
      expect(it.library.noteOf('gone'), isNull);
    });

    test('takes a note from another device whole, and does not tell sync it changed here', () async {
      final it = libraryOver();
      await it.library.createNote('mine', id: 'a');
      var saved = 0;
      it.library.touched.addListener(() => saved += 1);
      const theirs = Note(id: 'a', body: 'theirs', createdAt: 10, updatedAt: 20, starred: true, revision: 7);
      final stored = await it.library.apply(theirs);
      expect(noteToJson(stored), {...noteToJson(theirs), 'path': 'Inbox/theirs.md'});
      expect(noteToJson((await it.library.get('a'))!), noteToJson(stored));
      expect(it.library.noteOf('a')!.revision, 7);
      expect(saved, 0);
    });

    test('forgets a deleted note, and tells sync', () async {
      final it = libraryOver();
      await it.library.createNote('one', id: 'a');
      it.core.now = 2000;
      await it.library.createNote('two', id: 'b');
      var saved = 0;
      it.library.touched.addListener(() => saved += 1);
      await it.library.destroy('a');
      expect(ids(it.library.value), ['b']);
      expect(saved, 1);
      // Deleting one already gone is not an error: the page deletes from a list it drew some time ago.
      await it.library.destroy('a');
    });

    test('reads an answer that is not a list as no notes', () async {
      final library = CoreLibrary((command, [args = const {}]) async => 'not a list', resume: false, wait: (_) async {}, log: (_) {});
      await library.load();
      expect(library.value, isEmpty);
      expect(library.loading, isFalse);
    });
  });

  group('the first read of the notes', () {
    test('is loading until the list answers, and holds it newest first', () async {
      final core = FakeCore()
        ..seed('old', '# Old', at: 10)
        ..seed('new', '# New', at: 30)
        ..seed('mid', '# Mid', at: 20);
      final it = libraryOver(core);
      expect(it.library.loading, isTrue);
      expect(it.library.value, isEmpty);
      var told = 0;
      it.library.addListener(() => told += 1);
      await it.library.load();
      expect(it.library.loading, isFalse);
      expect(ids(it.library.value), ['new', 'mid', 'old']);
      expect(told, 1);
      expect(it.waits, isEmpty);
      // Asked twice, it reads once.
      await it.library.load();
      expect(core.asked('list_notes'), 1);
    });

    test('is tried again after 250, 900 and 2400 ms while the store will not answer', () async {
      final core = FakeCore()
        ..seed('a', '# A')
        ..fail('list_notes', times: 3);
      final it = libraryOver(core);
      await it.library.load();
      expect(it.waits, const [Duration(milliseconds: 250), Duration(milliseconds: 900), Duration(milliseconds: 2400)]);
      expect(core.asked('list_notes'), 4);
      expect(ids(it.library.value), ['a']);
      expect(it.library.loading, isFalse);
      expect(it.library.firstReadError, isNull);
    });

    test('gives up after the last retry, still loading as the page is, and says why', () async {
      final core = FakeCore()..fail('list_notes', times: 4, message: 'unable to open database file');
      final it = libraryOver(core);
      var told = 0;
      it.library.addListener(() => told += 1);
      await it.library.load();
      expect(core.asked('list_notes'), 4);
      expect(it.library.loading, isTrue);
      expect(it.library.firstReadError.toString(), 'unable to open database file');
      expect(told, 1);
      expect(it.said.single, contains('the notes could not be read'));
      // A later read that answers ends it.
      await it.library.refresh();
      expect(it.library.loading, isFalse);
      expect(it.library.firstReadError, isNull);
    });

    test('asks once more, 1200 ms on, when the first answer is empty', () async {
      final it = libraryOver();
      await it.library.load();
      expect(it.waits, const [Duration(milliseconds: 1200)]);
      expect(it.core.asked('list_notes'), 2);
      expect(it.library.loading, isFalse);
      expect(it.library.value, isEmpty);
    });

    test('does not ask again for an empty answer that came after a failure', () async {
      final core = FakeCore()..fail('list_notes');
      final it = libraryOver(core);
      await it.library.load();
      expect(it.waits, const [Duration(milliseconds: 250)]);
      expect(core.asked('list_notes'), 2);
    });

    test('finds on the second ask what the first missed', () async {
      final core = FakeCore();
      late final CoreLibrary library;
      library = CoreLibrary(
        core.invoke,
        resume: false,
        log: (_) {},
        // A note written by the capture while the list was being read.
        wait: (_) async => core.seed('late', '# Late'),
      );
      await library.load();
      expect(ids(library.value), ['late']);
    });

    test('lets a failed read again be the caller’s, as the page’s refresh rejects', () async {
      final core = FakeCore()..seed('a', '# A');
      final it = libraryOver(core);
      await it.library.load();
      core.fail('list_notes', message: 'database is locked');
      await expectLater(it.library.refresh(), refuses('database is locked'));
      // The list as it stood is still the best there is.
      expect(ids(it.library.value), ['a']);
    });
  });

  group('reading again', () {
    test('finds a note another process wrote, when asked', () async {
      final core = FakeCore()..seed('a', '# A', at: 10);
      final it = libraryOver(core);
      await it.library.load();
      core.seed('spoken', '# Said into the side key', at: 20, source: 'capture');
      expect(ids(it.library.value), ['a']);
      await it.library.refresh();
      expect(ids(it.library.value), ['spoken', 'a']);
      expect(it.library.noteOf('spoken')!.source, NoteSource.capture);
    });

    test('happens when the app comes back to the front', () async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      final core = FakeCore()..seed('a', '# A', at: 10);
      final library = CoreLibrary(core.invoke, wait: (_) async {}, log: (_) {});
      await library.load();
      addTearDown(library.dispose);
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        binding.handleAppLifecycleStateChanged(state);
      }
      core.seed('spoken', '# Said while the app was away', at: 20, source: 'capture');
      expect(core.asked('list_notes'), 1);
      for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        binding.handleAppLifecycleStateChanged(state);
      }
      await untilTrue(() => library.noteOf('spoken') != null);
      expect(core.asked('list_notes'), 2);
    });

    test('follows every write, so the list is the library’s by the time the write is answered', () async {
      final it = libraryOver();
      await it.library.load();
      final before = it.core.asked('list_notes');
      await it.library.createNote('# One', id: 'a');
      expect(it.core.asked('list_notes'), before + 1);
      await it.library.update('a', '# One, renamed', 1);
      expect(it.core.asked('list_notes'), before + 2);
      // The file was renamed with its title, and the list says where it is now.
      expect(it.library.noteOf('a')!.path, 'Inbox/One, renamed.md');
      await it.library.pin('a', pinned: true);
      await it.library.archive('a', archived: true);
      await it.library.destroy('a');
      expect(it.core.asked('list_notes'), before + 5);
    });

    test('is one read at a time, with one more for everyone who asked meanwhile', () async {
      final core = FakeCore()..seed('a', '# A');
      final it = libraryOver(core);
      await it.library.load();
      final before = core.asked('list_notes');
      await Future.wait([it.library.refresh(), it.library.refresh(), it.library.refresh()]);
      expect(core.asked('list_notes'), before + 2);
    });

    test('tells a listener of a write that the list could not be read after, and keeps the note it was answered', () async {
      final it = libraryOver();
      await it.library.load();
      await it.library.createNote('words', id: 'a');
      it.core.fail('list_notes');
      await it.library.pin('a', pinned: true);
      expect(it.library.noteOf('a')!.starred, isTrue);
      expect(it.said.last, contains('could not be read again'));
    });
  });

  group('a new note', () {
    test('is in the list at once, first, with an id of its own, and the write follows', () async {
      final core = FakeCore()..seed('a', '# A', at: 10);
      final it = libraryOver(core);
      await it.library.load();
      final made = it.library.create('# New');
      expect(made.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect((made.body, made.createdAt, made.revision, made.path), ('# New', 1000, 1, null));
      expect(ids(it.library.value), [made.id, 'a']);
      expect(core.asked('create_note'), 1);
      expect(core.sent.last.args, {'id': made.id, 'body': '# New', 'source': 'editor'});
      await untilTrue(() => it.library.noteOf(made.id)!.path != null);
      expect(it.library.noteOf(made.id)!.path, 'Inbox/New.md');
      expect(core.files, ['Inbox/A.md', 'Inbox/New.md']);
    });

    test('with no words is a draft: in the list here, with no file, until it has some', () async {
      final it = libraryOver();
      await it.library.load();
      final draft = await it.library.createNote('', id: 'd1');
      expect(draft.path, isNull);
      expect(it.core.files, isEmpty);
      // The core's list leaves a draft out; the library keeps the one it made, so the shell can open it.
      expect(ids(it.library.value), ['d1']);
      expect(it.library.isDraft('d1'), isTrue);
      await it.library.refresh();
      expect(ids(it.library.value), ['d1']);
      // Its first words write the file, from the revision the draft had.
      it.core.now = 3000;
      final written = await it.library.update('d1', '# Groceries\n\nmilk', draft.revision);
      expect((written.path, written.createdAt, written.revision), ('Inbox/Groceries.md', 1000, 2));
      expect(it.library.isDraft('d1'), isFalse);
      expect(ids(it.library.value), ['d1']);
      expect(it.library.noteOf('d1')!.path, 'Inbox/Groceries.md');
    });

    test('whose words are all taken out again goes back to being a draft, and stays in the list', () async {
      final it = libraryOver();
      await it.library.load();
      final draft = await it.library.createNote('', id: 'd1');
      final written = await it.library.update('d1', 'words', draft.revision);
      final emptied = await it.library.update('d1', '', written.revision);
      expect(emptied.path, isNull);
      expect(it.core.files, isEmpty);
      expect(ids(it.library.value), ['d1']);
      expect(it.library.isDraft('d1'), isTrue);
      await it.library.destroy('d1');
      expect(it.library.value, isEmpty);
    });

    test('that could not be made leaves the list, and the failure is the caller’s', () async {
      final it = libraryOver();
      await it.library.load();
      it.core.fail('create_note', message: 'No space left on device');
      await expectLater(it.library.createNote('# New', id: 'a'), refuses('No space left on device'));
      expect(it.library.value, isEmpty);
      // Made without waiting, the failure is said and the note is gone from the list.
      it.core.fail('create_note', message: 'No space left on device');
      final made = it.library.create('# New');
      expect(ids(it.library.value), [made.id]);
      await untilTrue(() => it.library.value.isEmpty);
      expect(it.said.last, contains('could not be made'));
    });
  });

  group('a save from the list’s copy', () {
    const transcript = '## Transcript\n\nWe settled the date.';

    test('lands over the revision the list holds', () async {
      final it = libraryOver();
      await it.library.createNote('one', id: 'a');
      final saved = await it.library.save('a', 'two');
      expect((saved.body, saved.revision), ('two', 2));
      expect((await it.library.save('a', 'three')).revision, 3);
    });

    test('is made again over the transcript the phone’s write-up appended meanwhile', () async {
      final it = libraryOver();
      await it.library.createNote('# Meeting\n', source: NoteSource.capture, id: 'm1');
      it.core.writeBehind('m1', withTranscript('# Meeting\n', transcript));
      final saved = await it.library.save('m1', '# Meeting\n\nMy own line.\n');
      expect(saved.body, withTranscript('# Meeting\n\nMy own line.\n', transcript));
      expect((await it.library.get('m1'))!.body, saved.body);
    });

    test('is refused where another writer changed the words, and for a note that has gone', () async {
      final it = libraryOver();
      await it.library.createNote('# Plan\n\nOne.\n', id: 'n1');
      it.core.writeBehind('n1', '# Plan\n\nOne, changed elsewhere.\n');
      await expectLater(it.library.save('n1', '# Plan\n\nOne, changed here.\n'), refuses('the note was deleted or changed'));
      expect((await it.library.get('n1'))!.body, '# Plan\n\nOne, changed elsewhere.\n');
      await expectLater(it.library.save('nobody', 'words'), refuses('the note was deleted or changed'));
    });
  });

  group('a note taken out of the list the old way', () {
    test('is hidden for this run and put back, and nothing in the library changes', () async {
      final core = FakeCore()..seed('a', '# A');
      final it = libraryOver(core);
      await it.library.load();
      final gone = it.library.delete('a')!;
      expect(it.library.value, isEmpty);
      expect(it.library.delete('a'), isNull);
      await it.library.refresh();
      expect(it.library.value, isEmpty);
      expect(core.asked('delete_note'), 0);
      expect(core.files, ['Inbox/A.md']);
      it.library.restore(gone);
      expect(ids(it.library.value), ['a']);
    });
  });
}

/// Waits, a turn at a time, for [done]: for a write nobody was handed the future of.
Future<void> untilTrue(bool Function() done) async {
  for (var turn = 0; turn < 200 && !done(); turn += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(done(), isTrue);
}
