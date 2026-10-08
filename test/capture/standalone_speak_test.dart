import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/command.dart';
import 'package:ghost_md/capture/instruction_mutation.dart';
import 'package:ghost_md/capture/list_append.dart' show placeWords;
import 'package:ghost_md/capture/offers.dart' show placingOf;
import 'package:ghost_md/capture/take_types.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;

import 'support/memory_store.dart';

/// Kevin's four standalone Speak sessions (command.dart, instruction_mutation.dart and list_append.dart together),
/// case for case with the web's `capture/standaloneSpeak.test.ts`. The web's store is `support/memory_store.dart`.

typedef Named = TakeCandidate<Note>;

Future<List<Named>> namedNotes(MemoryStore store) async => [
  for (final note in await store.listNotes()) TakeCandidate(id: note.id, title: noteTitle(note.body), note: note),
];

/// Test driver for the same deterministic preview + confirmed CAS path as the recorder.
Future<void> confirmedStandaloneSpeak(MemoryStore store, String utterance) async {
  expect(isStandaloneCommandLike(utterance), true);
  final notes = await namedNotes(store);
  final plan = planCommand(utterance, notes: notes);
  expect(plan, isNotNull, reason: utterance);
  if (plan == null) return;
  if (plan is PlanCreateList<Named>) {
    final title = listTitle(plan.title);
    final id = store.newNoteId();
    final applied = await store.applyCommandMutation(
      mutationId: store.newNoteId(),
      noteId: id,
      kind: 'create',
      beforeRevision: null,
      beforeBody: null,
      afterBody: instructionCreateBody(title, null),
      source: NoteSource.capture,
    );
    expect(applied.status, 'applied');
    return;
  }
  expect(plan.kind, 'place');
  if (plan is! PlanPlace<Named>) return;
  final preview = placeWords(plan.note.note.body, plan.text, placingOf(plan.placement));
  final applied = await store.applyCommandMutation(
    mutationId: store.newNoteId(),
    noteId: plan.note.id,
    kind: 'append',
    beforeRevision: plan.note.note.revision,
    beforeBody: plan.note.note.body,
    afterBody: preview.body,
    source: NoteSource.capture,
  );
  expect(applied.status, 'applied');
}

Note? firstWhere(List<Note> notes, bool Function(Note) test) {
  for (final note in notes) {
    if (test(note)) return note;
  }
  return null;
}

void main() {
  group('Kevin’s four standalone Speak sessions', () {
    test('creates two notes, appends five separate groceries, and never memo-saves command prose or End', () async {
      final store = MemoryStore();
      await confirmedStandaloneSpeak(store, 'make a new list called groceries');
      await confirmedStandaloneSpeak(store, 'add to the grocery list that I need eggs milk bread');
      await confirmedStandaloneSpeak(store, 'add to the grocery list that I need apples and oranges');
      await confirmedStandaloneSpeak(store, 'I need a new list called to do. End.');

      final notes = await store.listNotes();
      expect(notes, hasLength(2));
      final groceries = firstWhere(notes, (note) => noteTitle(note.body) == 'Groceries');
      final todo = firstWhere(notes, (note) => noteTitle(note.body) == 'To Do');
      expect(groceries?.body, 'Groceries\n\n- Eggs\n- Milk\n- Bread\n- Apples\n- Oranges\n');
      expect(todo?.body, 'To Do');
      for (final note in notes) {
        expect(note.body, isNot(matches(RegExp(r'make a new|add to the grocery|I need a new list|\bEnd\b', caseSensitive: false))));
      }
    });

    test('routes the requested full utterance to To-Do and leaves ordinary prose as a memo', () async {
      final store = MemoryStore();
      final todoId = store.newNoteId();
      await store.applyCommandMutation(
        mutationId: store.newNoteId(),
        noteId: todoId,
        kind: 'create',
        beforeRevision: null,
        beforeBody: null,
        afterBody: 'To-Do',
        source: NoteSource.editor,
      );

      await confirmedStandaloneSpeak(store, 'add to the to do list wash dishes, take out trash, and fold clothes');
      final todo = firstWhere(await store.listNotes(), (note) => note.id == todoId);
      expect(todo?.body, 'To-Do\n\n- [ ] Wash dishes\n- [ ] Take out trash\n- [ ] Fold clothes\n');

      final notes = await namedNotes(store);
      const prose = 'my thoughts about the new iPhone, I like the folding display and want to add more later';
      expect(isStandaloneCommandLike(prose), false);
      expect(planCommand(prose, notes: notes), isNull);
    });

    test('does not silently correct an unsafe ASR title or mutate it through a grocery reference', () async {
      final store = MemoryStore();
      await confirmedStandaloneSpeak(store, 'make a new list called Brofries');
      final notes = await namedNotes(store);
      expect(notes.isEmpty ? null : notes[0].title, 'Brofries');
      expect(planCommand('add to the grocery list that I need eggs', notes: notes), const PlanNoNote<Named>(name: 'grocery'));
    });
  });
}
