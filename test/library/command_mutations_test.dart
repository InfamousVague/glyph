import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/command_mutations.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';

import 'command_cases.dart';
import 'support.dart';

/// A spoken command's write and its undo (lib/core/command_mutations.dart, [NoteLibrary.applyCommandMutation] and
/// [NoteLibrary.undoCommandMutation]): the web's `core/store.test.ts` cases (command_cases.dart) over the library
/// in memory, which is the browser half of `core/store.ts`, and over the library on the core, against a fake of
/// `src-tauri/src/library/mutations.rs`. The same cases cross the real core in
/// test/native/command_mutations_test.dart.
Matcher refuses(String sentence) => throwsA(isA<CoreError>().having((e) => e.message, 'message', sentence));

void main() {
  group('a command’s write, and its undo, in memory', () {
    commandCases(() async => SampleLibrary(const []));

    // Missing 10 (docs/PARITY.md): `latestCommandMutation`, the web's "offers the latest undo only while its result
    // stands, and for ten minutes", with a clock a test can move.
    test('offers the latest undo for ten minutes, and not once it was taken back', () async {
      var now = 100000;
      final library = SampleLibrary([makeNote('a', body: 'milk', updatedAt: 1)], clock: () => now);
      expect(await library.latestCommandMutation(), isNull);
      await library.applyCommandMutation(const CommandMutationRequest(mutationId: 'm1', noteId: 'a', kind: 'append', beforeRevision: 1, beforeBody: 'milk', afterBody: 'milk\neggs', source: NoteSource.capture));
      final latest = await library.latestCommandMutation();
      expect((latest?.mutationId, latest?.noteId, latest?.kind, latest?.createdAt), ('m1', 'a', 'append', 100000));
      now = 100000 + 10 * 60000 + 1;
      expect(await library.latestCommandMutation(), isNull);
      now = 100000;
      await library.undoCommandMutation('m1');
      expect(await library.latestCommandMutation(), isNull);
    });

    test('keeps the note where it was in the list, and tells its listeners of each change', () async {
      final library = SampleLibrary([makeNote('a', body: 'milk', updatedAt: 1), makeNote('z', body: 'other', updatedAt: 2)], clock: () => 5000);
      var told = 0;
      library.addListener(() => told += 1);
      await library.applyCommandMutation(const CommandMutationRequest(mutationId: 'm1', noteId: 'a', kind: 'append', beforeRevision: 1, beforeBody: 'milk', afterBody: 'milk\neggs', source: NoteSource.editor));
      expect(ids(library.value), ['a', 'z']);
      expect((library.noteOf('a')!.body, library.noteOf('a')!.updatedAt), ('milk\neggs', 5000));
      await library.undoCommandMutation('m1');
      expect(library.noteOf('a')!.body, 'milk');
      expect(told, 2);
      // A conflict writes nothing and tells nobody.
      await library.undoCommandMutation('m1');
      await library.applyCommandMutation(const CommandMutationRequest(mutationId: 'm2', noteId: 'a', kind: 'append', beforeRevision: 1, beforeBody: 'milk', afterBody: 'late', source: NoteSource.editor));
      expect((library.noteOf('a')!.body, told), ('milk', 2));
    });
  });

  group('a command’s write, and its undo, over the core', () {
    commandCases(() async {
      final it = libraryOver();
      await it.library.load();
      return it.library;
    });

    test('asks the core by the web’s own names, with every field of the request and no other', () async {
      final it = libraryOver();
      await it.library.createNote('milk', id: 'a');
      await it.library.applyCommandMutation(const CommandMutationRequest(mutationId: 'm1', noteId: 'a', kind: 'append', beforeRevision: 1, beforeBody: 'milk', afterBody: 'milk\neggs', source: NoteSource.capture));
      final applied = it.core.sent.lastWhere((each) => each.command == 'apply_command_mutation');
      expect(applied.args, {
        'request': {'mutationId': 'm1', 'noteId': 'a', 'kind': 'append', 'beforeRevision': 1, 'beforeBody': 'milk', 'afterBody': 'milk\neggs', 'source': 'capture'},
      });
      await it.library.undoCommandMutation('m1');
      expect(it.core.sent.lastWhere((each) => each.command == 'undo_command_mutation').args, {'mutationId': 'm1'});
    });

    test('puts what a command wrote in the list before it answers, takes an undone new note out, and tells sync', () async {
      final it = libraryOver();
      await it.library.load();
      await it.library.createNote('milk', id: 'a');
      var saved = 0;
      it.library.touched.addListener(() => saved += 1);
      it.core.now = 2000;
      await it.library.applyCommandMutation(const CommandMutationRequest(mutationId: 'm1', noteId: 'a', kind: 'append', beforeRevision: 1, beforeBody: 'milk', afterBody: 'milk\neggs', source: NoteSource.capture));
      expect((it.library.noteOf('a')!.body, it.library.noteOf('a')!.revision), ('milk\neggs', 2));
      it.core.now = 3000;
      await it.library.applyCommandMutation(const CommandMutationRequest(mutationId: 'm2', noteId: 'b', kind: 'create', beforeRevision: null, beforeBody: null, afterBody: '# Groceries', source: NoteSource.capture));
      expect(ids(it.library.value), ['b', 'a']);
      expect(saved, 2);

      await it.library.undoCommandMutation('m1');
      expect((it.library.noteOf('a')!.body, it.library.noteOf('a')!.revision), ('milk', 3));
      await it.library.undoCommandMutation('m2');
      expect(ids(it.library.value), ['a']);
      expect(it.core.files, ['Inbox/milk.md']);
      expect(saved, 4);
    });

    test('shows the note in the list at once where the list cannot be read again', () async {
      final it = libraryOver();
      await it.library.load();
      await it.library.createNote('milk', id: 'a');
      it.core.fail('list_notes', times: 2);
      final applied = await it.library.applyCommandMutation(const CommandMutationRequest(mutationId: 'm1', noteId: 'a', kind: 'append', beforeRevision: 1, beforeBody: 'milk', afterBody: 'milk\neggs', source: NoteSource.capture));
      expect(applied.status, 'applied');
      expect(it.library.noteOf('a')!.body, 'milk\neggs');
      final undone = await it.library.undoCommandMutation('m1');
      expect(undone.status, 'undone');
      expect(it.library.noteOf('a')!.body, 'milk');
      expect(it.said.where((line) => line.contains('could not be read again')).length, 2);
    });

    test('says the core’s refusal of a request it will not take, and writes nothing', () async {
      final it = libraryOver();
      await it.library.createNote('milk', id: 'a');
      const bad = CommandMutationRequest(mutationId: 'm1', noteId: '../a', kind: 'append', beforeRevision: 1, beforeBody: 'milk', afterBody: 'x', source: NoteSource.capture);
      await expectLater(it.library.applyCommandMutation(bad), refuses('a command mutation needs plain bounded ids'));
      const shapeless = CommandMutationRequest(mutationId: 'm1', noteId: 'a', kind: 'append', beforeRevision: null, beforeBody: null, afterBody: 'x', source: NoteSource.capture);
      await expectLater(it.library.applyCommandMutation(shapeless), refuses('an append command needs the previewed note revision'));
      const replacing = CommandMutationRequest(mutationId: 'm1', noteId: 'a', kind: 'create', beforeRevision: 1, beforeBody: 'milk', afterBody: 'x', source: NoteSource.capture);
      await expectLater(it.library.applyCommandMutation(replacing), refuses('a create command cannot replace an existing note'));
      expect((await it.library.get('a'))!.body, 'milk');
    });
  });

  group('the core’s answers', () {
    test('are read by their status, each with what it carries', () {
      final note = {'id': 'a', 'body': 'milk', 'createdAt': 1, 'updatedAt': 2, 'source': 'capture', 'revision': 3};
      final applied = commandMutationResultFromJson({'status': 'applied', 'mutationId': 'm1', 'note': note}) as CommandMutationResultApplied;
      expect((applied.mutationId, applied.note.body, applied.note.revision), ('m1', 'milk', 3));
      expect((commandMutationResultFromJson({'status': 'conflict', 'current': null}) as CommandMutationResultConflict).current, isNull);
      expect((commandMutationResultFromJson({'status': 'conflict', 'current': note}) as CommandMutationResultConflict).current?.id, 'a');

      final undone = commandUndoResultFromJson({'status': 'undone', 'mutationId': 'm1', 'note': note}) as CommandUndoResultUndone;
      expect((undone.mutationId, undone.note?.body), ('m1', 'milk'));
      expect((commandUndoResultFromJson({'status': 'undone', 'mutationId': 'm2', 'note': null}) as CommandUndoResultUndone).note, isNull);
      expect((commandUndoResultFromJson({'status': 'conflict', 'current': note}) as CommandUndoResultConflict).current?.revision, 3);
      expect(commandUndoResultFromJson({'status': 'already-undone'}).status, 'already-undone');
      expect(commandUndoResultFromJson({'status': 'not-found'}).status, 'not-found');
    });

    test('are an error where they are in no shape the library answers', () {
      for (final answer in [null, 'applied', {'status': 'applied', 'mutationId': 'm1'}, {'status': 'undone'}]) {
        expect(() => commandMutationResultFromJson(answer), throwsA(isA<CoreError>()), reason: '$answer');
      }
      for (final answer in [null, {'status': 'applied'}, {'status': 'undone', 'note': null}]) {
        expect(() => commandUndoResultFromJson(answer), throwsA(isA<CoreError>()), reason: '$answer');
      }
    });
  });
}
