import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/locale_dates.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';

/// The sample library (lib/core/sample_library.dart) against what the web's own code writes: seed.mjs's `library()`
/// and core/starterNotes.ts, boardNote.ts and sampleNote.ts, run and kept in test/core/fixtures/web_library.json.
void main() {
  final web = jsonDecode(File('test/core/fixtures/web_library.json').readAsStringSync()) as Map<String, dynamic>;

  test('holds seed.mjs’s notes, word for word, each as long ago as there', () {
    final notes = seedLibrary();
    final said = (web['notes'] as List).cast<Map<String, dynamic>>();
    expect([for (final n in notes) n.id], [for (final n in said) n['id']]);
    for (var i = 0; i < notes.length; i += 1) {
      final note = notes[i], want = said[i];
      expect(note.body, want['body'], reason: note.id);
      expect(note.starred, want['starred'], reason: note.id);
      expect(seedNow - note.createdAt, want['createdAgo'], reason: '${note.id} made');
      expect(seedNow - note.updatedAt, want['updatedAgo'], reason: '${note.id} touched');
    }
  });

  test('files the work notes under Work and the house notes under Home, as seed.mjs does', () {
    final store = WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces()));
    expect([for (final w in store.value.list) '${w.name} ${w.hue}'], ['Work moss', 'Home sea']);
    expect(store.workspaceOf('prd11')?.name, 'Work');
    expect(store.workspaceOf('flat')?.name, 'Home');
    expect(store.workspaceOf('weekend'), isNull);
    expect(store.inWorkspace(seedLibrary(), 'home', (n) => n.id).map((n) => n.id), ['house', 'groceries', 'flat']);
  });

  group('the example journal’s first entry is headed in the phone’s own words (core/locale_dates.dart)', () {
    tearDown(() => toldLocale = null);
    final at = DateTime.fromMillisecondsSinceEpoch(seedNow);

    test('an American phone has the month first after a comma', () {
      toldLocale = DateLocale.enUS;
      expect(exampleJournal(at).entry, contains('\n# Monday, September 28\n\n**10:00** The first entry.'));
    });

    test('a British phone has the day first and no comma', () {
      toldLocale = DateLocale.enGB;
      expect(exampleJournal(at).entry, contains('\n# Monday 28 September\n\n**10:00** The first entry.'));
    });
  });

  test('starts a fresh library with the app’s own examples, as core/seed.ts writes them', () {
    final starters = web['starters'] as Map<String, dynamic>;
    final at = DateTime.fromMillisecondsSinceEpoch(seedNow);
    expect(exampleTicketBodies(at), starters['tickets']);
    expect(exampleNotebookBody(), starters['notebook']);
    expect(boardNoteBody, starters['board']);
    expect(exampleJournal(at).journal, starters['journal']);
    expect(exampleJournal(at).entry, starters['entry']);
    expect(sampleNoteBody, starters['sample']);
    final notes = starterNotes(seedNow);
    expect(notes.length, 8);
    // Made oldest first, so the sample note, made last, is the newest.
    expect(notes.last.body, sampleNoteBody);
    expect([for (final n in notes) n.updatedAt], [for (var i = 0; i < 8; i += 1) seedNow + i]);
  });

  test('a simple install starts with the sample note alone, and the examples come with Advanced (GHST-103)', () {
    final alone = starterNotes(seedNow, examples: false);
    expect(alone.length, 1);
    expect(alone.single.body, sampleNoteBody);
    expect(alone.single.id, starterSampleId);
    final examples = starterExamples(seedNow);
    expect(examples.length, 7);
    expect(examples.any((note) => note.body == sampleNoteBody), isFalse);
    // Together, the eight a library from before the choice began with, sample last.
    expect([...examples, ...alone].map((note) => note.id), starterNotes(seedNow).map((note) => note.id));
  });

  group('the store', () {
    test('pins, archives, deletes and puts back, telling its listeners each time', () {
      var clock = 1000;
      final library = SampleLibrary.seeded(clock: () => clock);
      var told = 0;
      library.addListener(() => told += 1);

      library.pin('flat', pinned: true);
      expect(library.noteOf('flat')!.starred, isTrue);
      library.pin('flat', pinned: false);
      expect(library.noteOf('flat')!.starred, isFalse);

      library.archive('flat', archived: true);
      expect(library.noteOf('flat')!.archivedAt, 1000);
      library.archive('flat', archived: false);
      expect(library.noteOf('flat')!.archivedAt, isNull);

      final gone = library.delete('flat')!;
      expect(library.noteOf('flat'), isNull);
      expect(library.delete('flat'), isNull);
      library.restore(gone);
      expect(library.noteOf('flat')!.body, gone.body);
      library.restore(gone);
      expect(library.value.where((n) => n.id == 'flat').length, 1);
      expect(told, 6);

      // Nothing by that id: nothing happens, and nobody is told.
      library.pin('nobody', pinned: true);
      expect(told, 6);
    });

    test('makes a new note now, first in the list', () {
      var clock = 5000;
      final library = SampleLibrary(const [], clock: () => clock);
      final made = library.create('# New');
      clock = 6000;
      final spoken = library.create('# Said', source: NoteSource.capture);
      expect([for (final n in library.value) n.id], [spoken.id, made.id]);
      expect([made.createdAt, made.updatedAt, made.source], [5000, 5000, NoteSource.editor]);
      expect(spoken.source, NoteSource.capture);
      expect(made.id, isNot(spoken.id));
    });
  });
}
