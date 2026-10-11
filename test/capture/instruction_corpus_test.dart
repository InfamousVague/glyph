import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/command.dart';
import 'package:ghost_md/capture/instruction_intent.dart';
import 'package:ghost_md/capture/instruction_mutation.dart';
import 'package:ghost_md/capture/list_append.dart' show placeInstruction;
import 'package:ghost_md/capture/take_types.dart';
import 'package:ghost_md/core/note.dart';

import 'support/memory_store.dart';
import 'support/shapes.dart';

/// The repeatable instruction evaluation corpus (test/capture/fixtures/instructionCorpus.json, the web's own file),
/// case for case with the web's `capture/instructionCorpus.test.ts`. The web's store is `support/memory_store.dart`.

typedef Named = TakeCandidate<Note>;

Future<List<Named>> seed(MemoryStore store) async {
  final attack = await store.createNote('attack', 'AttackFM\n\n## Bugs\n\n- Existing\n\n## Ideas\n\n- Later');
  final weekendA = await store.createNote('weekend-a', 'Weekend trip');
  final weekendB = await store.createNote('weekend-b', 'Weekend plans');
  return [
    for (final note in [attack, weekendA, weekendB]) TakeCandidate(id: note.id, title: note.body.split('\n')[0], note: note),
  ];
}

Map<String, Object?> intent(Map<String, Object?> intent) => {'status': 'intent', 'model': 'fixture', 'intent': intent};

final Map<String, Map<String, Object?>> fixtures = {
  'attackfm-messy': intent({'action': 'append', 'target': 'Attack FM', 'content': 'the playback position gets lost', 'placement': 'bugs'}),
  'create-clean': intent({'action': 'create', 'target': 'apartment stuff', 'content': null}),
  'create-with-body': intent({'action': 'create', 'target': 'apartment stuff', 'content': 'call the landlord at 5'}),
  'ambiguous': intent({'action': 'append', 'target': 'Weekend', 'content': 'book the hotel', 'placement': 'tasks'}),
  'missing': intent({'action': 'append', 'target': 'Groceries', 'content': 'milk', 'placement': 'list'}),
  'destructive': intent({'action': 'none', 'reason': 'destructive'}),
  'compound': intent({'action': 'none', 'reason': 'compound'}),
  'quoted-numeric': intent({'action': 'append', 'target': 'Attack FM', 'content': 'the player saying "error 404" at 42 percent', 'placement': 'bugs'}),
};

InferenceRun inferred(Map<String, Object?> result) => InferenceRun(done: Future.value(validateInference(result)!), cancel: () {});

Future<List<({String id, String body})>> bodies(MemoryStore store) async => [
  for (final note in await store.listNotes()) (id: note.id, body: note.body),
];

void main() {
  final corpus = [
    for (final item in jsonDecode(File('test/capture/fixtures/instructionCorpus.json').readAsStringSync()) as List<Object?>) item! as Map<String, Object?>,
  ];

  group('repeatable instruction evaluation corpus', () {
    test('evaluates expected action, target, content, placement, and rejection for every case', () async {
      const required = ['attackfm-clean', 'attackfm-messy', 'create-clean', 'create-with-body', 'ambiguous', 'missing', 'destructive', 'compound', 'quoted-numeric', 'ordinary-memo'];
      expect(corpus.map((item) => item['id']).toList(), required);

      for (final item in corpus) {
        final id = item['id']! as String;
        final utterance = item['utterance']! as String;
        final expected = item['expected']! as Map<String, Object?>;
        final store = MemoryStore();
        final notes = await seed(store);
        final before = await bodies(store);
        if (expected['action'] == 'memo') {
          expect(item['wakeWord'], false);
          expect(findKeyword(utterance), isNull);
          expect(planCommand(utterance, notes: notes), isNull);
          expect(await bodies(store), before);
          continue;
        }

        final deterministic = planCommand(utterance, notes: notes);
        if (deterministic == null) expect(fixtures[id], isNotNull, reason: 'missing model fixture for $id');
        final read = await interpretWakeCommand(utterance, notes: notes, startInference: (_) => inferred(fixtures[id]!)).done;
        if (expected['action'] == 'none') {
          expect(read.source, 'rejected', reason: id);
          expect(await bodies(store), before, reason: id);
          continue;
        }

        if (read is InterpretedCommandDeterministic<Named>) {
          final plan = read.plan;
          if (expected['action'] == 'create') {
            expect(plan, PlanCreateList<Named>(title: expected['target']! as String));
          } else {
            expect(plan, matchObject({'kind': 'place', 'note': {'title': expected['target']}, 'text': expected['content']}));
            expect(plan is PlanPlace<Named> ? plan.near : null, expected['placement']);
          }
          continue;
        }

        expect(read.source, 'inferred', reason: id);
        if (read is! InterpretedCommandInferred<Named>) continue;
        final meant = read.intent;
        expect(meant.action, expected['action'], reason: id);
        if (meant is InstructionIntentCreate) expect(meant.target, expected['target'], reason: id);
        final content = switch (meant) {
          InstructionIntentAppend(:final content) => content,
          InstructionIntentCreate(:final content) => content,
          InstructionIntentNone() => null,
        };
        expect(content, expected['content'], reason: id);
        final note = read.note;
        if (meant is InstructionIntentAppend && note != null) {
          expect(note.title, expected['target']);
          expect(meant.placement?.name, expected['placement']);
          final preview = placeInstruction(note.note.body, literalMarkdown(meant.content), meant.placement);
          final applied = await store.applyCommandMutation(
            mutationId: 'm-$id',
            noteId: note.id,
            kind: 'append',
            beforeRevision: note.note.revision,
            beforeBody: note.note.body,
            afterBody: preview.body,
            source: NoteSource.capture,
          );
          expect(applied.status, 'applied');
        } else if (meant is InstructionIntentCreate) {
          final body = instructionCreateBody(meant.target, meant.content);
          final applied = await store.applyCommandMutation(
            mutationId: 'm-$id',
            noteId: 'n-$id',
            kind: 'create',
            beforeRevision: null,
            beforeBody: null,
            afterBody: body,
            source: NoteSource.capture,
          );
          expect(applied.status, 'applied');
        }
      }
    });

    test('keeps the fixture harness honest: invalid or unavailable output cannot mutate', () async {
      final store = MemoryStore();
      final notes = await seed(store);
      final before = await store.listNotes();
      for (final result in <Map<String, Object?>>[
        {'status': 'unavailable', 'reason': 'model missing'},
        intent({'action': 'none', 'reason': 'unclear'}),
      ]) {
        final read = await interpretWakeCommand('log something against Attack FM', notes: notes, startInference: (_) => inferred(result)).done;
        expect(read.source, 'rejected');
      }
      expect(await store.listNotes(), before);
    });
  });
}
