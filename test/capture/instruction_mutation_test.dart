import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/instruction_mutation.dart';
import 'package:ghost_md/capture/list_append.dart' show InstructionArea;
import 'package:ghost_md/core/note.dart' show NoteSource;

import 'support/memory_store.dart';

/// What a command the model read writes (lib/capture/instruction_mutation.dart), case for case with the web's
/// `capture/instructionMutation.test.ts`. The web's store is `support/memory_store.dart` here.

const dangerous = [
  '# injected',
  '![alt](https://bad.example/image.png)',
  '[click](https://bad.example)',
  '**bold** and _emphasis_',
  '```js console.log(1) ```',
  '| column | value |',
];

void main() {
  group('model text is serialized only as literal Markdown text', () {
    for (final payload in dangerous) {
      test('escapes append payload $payload', () {
        final preview = previewSameNoteInstruction('AttackFM\n\n## Bugs\n\n- Existing', '', payload, InstructionArea.bugs);
        expect(preview.afterBody, contains(literalMarkdown(payload)));
        expect(preview.afterBody, isNot(contains('- ${payload[0].toUpperCase()}${payload.substring(1)}')));
      });
    }

    for (final payload in dangerous) {
      test('escapes create payload $payload', () {
        final body = instructionCreateBody('Safe note', payload);
        expect(body, 'Safe note\n\n${literalMarkdown(payload)}');
      });
    }

    test('escapes a model-proposed create title too', () {
      expect(instructionCreateBody('# injected', null), r'\# injected');
    });
  });

  group('active capture inferred-append handoff', () {
    test('preserves the command through a later segment and autosave without duplicating the earlier take', () async {
      final store = MemoryStore();
      const baseBefore = 'AttackFM\n\n## Bugs\n\n- Existing';
      final continued = await store.createNote('attack', baseBefore, NoteSource.capture);
      const firstTake = 'Discussed the player state.';
      final preview = previewSameNoteInstruction(baseBefore, firstTake, 'losing playback position', InstructionArea.bugs);

      // The current draft is flushed before confirmation, so its revision/body are the exact CAS base rather than
      // the stale note-list candidate.
      final flushed = await store.updateNote(continued.id, preview.beforeBody, continued.revision);
      final applied = await store.applyCommandMutation(
        mutationId: 'active-capture-command',
        noteId: flushed.id,
        kind: 'append',
        beforeRevision: flushed.revision,
        beforeBody: flushed.body,
        afterBody: preview.afterBody,
        source: NoteSource.capture,
      );
      expect(applied.status, 'applied');

      // Capture continues after confirmation. Autosave composes from baseAfter, not from the stale pre-command body
      // or the full command result.
      const laterTake = '$firstTake\n\nThen checked Android recovery.';
      await store.updateNote(flushed.id, resumeSameNoteCapture(preview.baseAfter, laterTake), (await store.getNote(flushed.id))?.revision ?? 1);
      final stored = (await store.getNote(flushed.id))!;
      expect(stored.body, contains('- Losing playback position'));
      expect(stored.body, contains('Then checked Android recovery.'));
      expect(RegExp(r'Discussed the player state\.').allMatches(stored.body), hasLength(1));
    });
  });
}
