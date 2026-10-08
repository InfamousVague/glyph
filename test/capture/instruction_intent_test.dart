import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/command.dart';
import 'package:ghost_md/capture/instruction_intent.dart';
import 'package:ghost_md/capture/list_append.dart' show placeInstruction, placeWords;
import 'package:ghost_md/capture/offers.dart' show placingOf;
import 'package:ghost_md/capture/take_types.dart';

import 'support/shapes.dart';

/// What the on-device model says a command asks for (lib/capture/instruction_intent.dart), case for case with the
/// web's `capture/instructionIntent.test.ts`.

TakeCandidate<TakeNote> named(String id, String title, String body) => TakeCandidate(id: id, title: title, note: TakeNote(id: id, body: body));

final notes = [named('attack', 'AttackFM', '# AttackFM'), named('weekend-a', 'Weekend trip', 'Weekend trip'), named('weekend-b', 'Weekend plans', 'Weekend plans')];

/// The model's answer as it arrives, checked as the boundary checks it: the web's `inferred(value as …)`.
InferenceRun inferred(Map<String, Object?> value) => InferenceRun(done: Future.value(validateInference(value)!), cancel: () {});

void main() {
  group('instruction inference contract', () {
    test('strictly validates all fields and rejects malformed IPC values', () {
      expect(
        validateInference({
          'status': 'intent',
          'model': 'qwen3.5-2b',
          'intent': {'action': 'append', 'target': 'Attack FM', 'content': 'losing position at 42%', 'placement': 'bugs'},
        }),
        matchObject({'status': 'intent', 'intent': {'action': 'append', 'target': 'Attack FM'}}),
      );
      expect(validateInference({'status': 'intent', 'model': 'qwen3.5-2b', 'intent': {'action': 'create', 'target': '', 'content': null}}), isNull);
      expect(
        validateInference({
          'status': 'intent',
          'model': 'qwen3.5-2b',
          'intent': {'action': 'append', 'target': 'AttackFM', 'content': 'x', 'placement': 'bugs', 'id': 'attack'},
        }),
        isNull,
      );
      expect(validateInference({'status': 'unavailable', 'reason': ''}), isNull);
      expect(validateInference('{"status":"intent"}'), isNull);
      for (final content in ['bad\nheading', 'bad\ttable', 'bad${String.fromCharCode(0)}value']) {
        expect(
          validateInference({'status': 'intent', 'model': 'qwen3.5-2b', 'intent': {'action': 'append', 'target': 'AttackFM', 'content': content, 'placement': 'bugs'}}),
          isNull,
        );
        expect(validateInference({'status': 'intent', 'model': 'qwen3.5-2b', 'intent': {'action': 'create', 'target': 'Safe', 'content': content}}), isNull);
      }
    });

    test('gives the deterministic parser absolute precedence', () async {
      var called = 0;
      InferenceRun fallback(String _) {
        called += 1;
        return inferred({'status': 'unavailable', 'reason': 'must not run'});
      }

      final run = interpretWakeCommand('Put a bug about losing playback position in Attack FM', notes: notes, startInference: fallback);
      final read = await run.done;
      // "a bug about" is the kind of thing, not the thing: OBJECT_NOUN consumes it and routes the phrase to bug
      // placement, matching instructionCorpus attackfm-clean.
      expect(read, matchObject({'source': 'deterministic', 'plan': {'kind': 'place', 'note': {'id': 'attack'}, 'text': 'losing playback position'}}));
      expect(called, 0);
    });

    test('uses inference only on parser miss, then resolves the title deterministically', () async {
      var called = 0;
      InferenceRun fallback(String _) {
        called += 1;
        return inferred({
          'status': 'intent',
          'model': 'qwen3.5-2b',
          'intent': {'action': 'append', 'target': 'Attack FM', 'content': 'losing playback position', 'placement': 'bugs'},
        });
      }

      final read = await interpretWakeCommand('log losing playback position as a bug against Attack FM', notes: notes, startInference: fallback).done;
      expect(called, 1);
      expect(read, matchObject({'source': 'inferred', 'note': {'id': 'attack'}, 'intent': {'placement': 'bugs'}}));
    });

    test('uses application-owned list semantics for generic deterministic phrases', () async {
      final targets = [named('groceries', 'Groceries', 'Groceries'), named('todo', 'To Do', 'To Do')];
      final groceries = await interpretWakeCommand('add eggs to groceries', notes: targets).done;
      final todo = await interpretWakeCommand('add call Sam to to do', notes: targets).done;

      expect(groceries, matchObject({'source': 'deterministic', 'plan': {'kind': 'place'}}));
      expect(todo, matchObject({'source': 'deterministic', 'plan': {'kind': 'place'}}));
      if (groceries is InterpretedCommandDeterministic<TakeCandidate<TakeNote>> && todo is InterpretedCommandDeterministic<TakeCandidate<TakeNote>>) {
        final first = groceries.plan, second = todo.plan;
        if (first is PlanPlace<TakeCandidate<TakeNote>> && second is PlanPlace<TakeCandidate<TakeNote>>) {
          expect(placeWords(first.note.note.body, first.text, placingOf(first.placement)).body, 'Groceries\n\n- Eggs\n');
          expect(placeWords(second.note.note.body, second.text, placingOf(second.placement)).body, 'To Do\n\n- [ ] Call Sam\n');
        }
      }
    });

    test('uses the same policy when inferred placement is unspecified', () {
      expect(placeInstruction('Groceries', 'eggs', null).body, 'Groceries\n\n- Eggs\n');
      expect(placeInstruction('To Do', 'call Sam', null).body, 'To Do\n\n- [ ] Call Sam\n');
    });

    test('rejects ambiguous and unavailable results without an action', () async {
      final ambiguous = await interpretWakeCommand(
        'record book the hotel under weekend',
        notes: notes,
        startInference: (_) => inferred({
          'status': 'intent',
          'model': 'qwen3.5-2b',
          'intent': {'action': 'append', 'target': 'weekend', 'content': 'book it', 'placement': 'tasks'},
        }),
      ).done;
      expect(ambiguous, matchObject({'source': 'rejected'}));

      final unavailable = await interpretWakeCommand(
        'make a note named apartment stuff',
        notes: notes,
        startInference: (_) => inferred({'status': 'unavailable', 'reason': 'No compatible installed model.'}),
      ).done;
      expect(unavailable, const InterpretedCommandRejected<TakeCandidate<TakeNote>>(reason: 'No compatible installed model.'));
    });

    test('starts each inference with only that Speak session’s current utterance', () async {
      final prompts = <String>[];
      InferenceRun fallback(String words) {
        prompts.add(words);
        return inferred({'status': 'intent', 'model': 'qwen3.5-2b', 'intent': {'action': 'create', 'target': words, 'content': null}});
      }

      await interpretWakeCommand('first session Brofries', notes: notes, startInference: fallback).done;
      await interpretWakeCommand('second session groceries', notes: notes, startInference: fallback).done;

      expect(prompts, ['first session Brofries', 'second session groceries']);
      expect(prompts[1], isNot(contains('Brofries')));
    });

    test('accepts create title and optional body but no ids or Markdown decisions', () async {
      final read = await interpretWakeCommand(
        'make a new note called apartment stuff',
        notes: notes,
        startInference: (_) => inferred({
          'status': 'intent',
          'model': 'qwen3.5-2b',
          'intent': {'action': 'create', 'target': 'apartment stuff', 'content': 'call landlord at 5'},
        }),
      ).done;
      expect(
        read,
        const InterpretedCommandInferred<TakeCandidate<TakeNote>>(intent: InstructionIntentCreate(target: 'apartment stuff', content: 'call landlord at 5')),
      );
    });
  });
}
