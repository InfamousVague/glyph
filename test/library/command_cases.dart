import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/command_mutations.dart';
import 'package:ghost_md/core/library.dart';
import 'package:ghost_md/core/note.dart';

/// A command's write and its undo, as any [NoteLibrary] must answer them: the cases of the web's
/// `core/store.test.ts` ("a command’s write, and its undo, in a browser"), and the one of
/// `src-tauri/src/library/tests.rs` the browser's have no like of
/// (`undoing_a_created_note_removes_it_but_never_a_note_edited_since`).
///
/// [open] answers the library a case runs over. [id] makes a case's ids its own where every case shares one
/// library, as they do over the real core (one process has one); left out, an id is the web's.
///
/// "offers the latest undo only while its result stands, and for ten minutes" is here less its ten minutes, which
/// need a clock the real core does not take from a test; they are tried in memory
/// (test/library/command_mutations_test.dart).
void commandCases(Future<NoteLibrary> Function() open, {String Function(String name)? id, String? skip}) {
  String named(String name) => id == null ? name : id(name);

  /// An append to note [noteId], as it was previewed over [before] at [beforeRevision].
  CommandMutationRequest append(String mutationId, String noteId, String? before, String after, [int? beforeRevision = 1]) => CommandMutationRequest(
        mutationId: mutationId,
        noteId: noteId,
        kind: 'append',
        beforeRevision: beforeRevision,
        beforeBody: before,
        afterBody: after,
        source: NoteSource.capture,
      );

  /// A new note [noteId] with those words.
  CommandMutationRequest create(String mutationId, String noteId, String after) =>
      CommandMutationRequest(mutationId: mutationId, noteId: noteId, kind: 'create', beforeRevision: null, beforeBody: null, afterBody: after, source: NoteSource.capture);

  test('applies exactly the body previewed while the note is as it was, and refuses once it has changed', () async {
    final library = await open();
    final a = named('a'), m1 = named('m1'), m2 = named('m2');
    await library.createNote('milk', id: a);
    final applied = await library.applyCommandMutation(append(m1, a, 'milk', 'milk\neggs'));
    expect(applied.status, 'applied');
    applied as CommandMutationResultApplied;
    expect((applied.mutationId, applied.note.id, applied.note.body, applied.note.revision), (m1, a, 'milk\neggs', 2));
    final refused = await library.applyCommandMutation(append(m2, a, 'milk', 'milk\nbread'));
    expect(refused.status, 'conflict');
    expect((refused as CommandMutationResultConflict).current?.body, 'milk\neggs');
    expect((await library.get(a))!.body, 'milk\neggs');
  }, skip: skip);

  test('makes a new note only where there is none', () async {
    final library = await open();
    final a = named('a'), m1 = named('m1'), m2 = named('m2');
    final applied = await library.applyCommandMutation(create(m1, a, 'Groceries'));
    expect(applied.status, 'applied');
    final made = (applied as CommandMutationResultApplied).note;
    expect((made.id, made.body, made.source, made.revision), (a, 'Groceries', NoteSource.capture, 1));
    final again = await library.applyCommandMutation(create(m2, a, 'Groceries'));
    expect(again.status, 'conflict');
    expect((again as CommandMutationResultConflict).current?.id, a);
  }, skip: skip);

  test('offers the latest undo only while its result stands', () async {
    final library = await open();
    final a = named('late'), m1 = named('l1');
    await library.createNote('milk', id: a);
    // A moment after whatever another case applied: the latest is told by when, to the millisecond.
    await Future<void>.delayed(const Duration(milliseconds: 3));
    await library.applyCommandMutation(append(m1, a, 'milk', 'milk\neggs'));
    final latest = await library.latestCommandMutation();
    expect((latest?.mutationId, latest?.noteId, latest?.kind), (m1, a, 'append'));
    await library.update(a, 'milk\neggs\nand more', 2);
    expect((await library.latestCommandMutation())?.mutationId, isNot(m1));
  }, skip: skip);

  test('undoes an append back to the words before it, once, and an undone create takes the note away', () async {
    final library = await open();
    final a = named('a'), b = named('b'), m1 = named('m1'), m2 = named('m2');
    await library.createNote('milk', id: a);
    await library.applyCommandMutation(append(m1, a, 'milk', 'milk\neggs'));
    final undone = await library.undoCommandMutation(m1);
    expect(undone.status, 'undone');
    undone as CommandUndoResultUndone;
    expect((undone.mutationId, undone.note?.body, undone.note?.revision), (m1, 'milk', 3));
    expect((await library.get(a))!.body, 'milk');
    expect((await library.undoCommandMutation(m1)).status, 'already-undone');
    expect((await library.undoCommandMutation(named('never'))).status, 'not-found');

    expect((await library.applyCommandMutation(create(m2, b, 'Groceries'))).status, 'applied');
    final gone = await library.undoCommandMutation(m2);
    expect(gone.status, 'undone');
    gone as CommandUndoResultUndone;
    expect((gone.mutationId, gone.note), (m2, null));
    expect(await library.get(b), isNull);
  }, skip: skip);

  test('will not undo over an edit made since', () async {
    final library = await open();
    final a = named('a'), m1 = named('m1');
    await library.createNote('milk', id: a);
    await library.applyCommandMutation(append(m1, a, 'milk', 'milk\neggs'));
    await library.update(a, 'milk\neggs\nbread', 2);
    final refused = await library.undoCommandMutation(m1);
    expect(refused.status, 'conflict');
    expect((refused as CommandUndoResultConflict).current?.body, 'milk\neggs\nbread');
    expect((await library.get(a))!.body, 'milk\neggs\nbread');
  }, skip: skip);

  test('never takes away a note a command made that was edited since', () async {
    final library = await open();
    final a = named('new'), c2 = named('c2');
    await library.applyCommandMutation(create(c2, a, 'Apartment stuff\n'));
    final later = await library.update(a, 'Apartment stuff\n\nand more\n', 1);
    final refused = await library.undoCommandMutation(c2);
    expect(refused.status, 'conflict');
    expect((refused as CommandUndoResultConflict).current?.revision, later.revision);
    expect((await library.get(a))?.body, 'Apartment stuff\n\nand more\n', reason: 'an undo never throws away a later edit');
  }, skip: skip);
}
