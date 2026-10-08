// What the strip says about a run (lib/ai/words.dart). A port of `src/app/ai/words.test.ts`, case for case.

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/log.dart';
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/ai/words.dart';

const RunState base = RunState(
  id: 'r',
  noteId: 'n',
  kind: RunKind.format,
  instruction: null,
  model: 'qwen3.5-4b',
  scope: null,
  phase: RunPhase.generating,
  lines: [],
  partial: '',
  thought: '',
  text: null,
  promptTokens: 400,
  promptTokensDone: 400,
  outputTokens: 50,
  maxTokens: 200,
  tokensPerSecond: 31.4,
  elapsedMs: 12000,
  hardware: null,
  truncated: false,
  message: null,
  startedAt: 0,
  endedAt: null,
  hash: null,
);

void main() {
  group('what the strip says', () {
    test('names the phase, the model, the pace and the time', () {
      expect(runSentence(base.copyWith(phase: RunPhase.queued)), 'Waiting for the model, which is on another note.');
      expect(runSentence(base.copyWith(phase: RunPhase.loading)), 'Loading Qwen3.5 4B.');
      expect(runSentence(base.copyWith(phase: RunPhase.prefill, promptTokensDone: 120)), 'Reading the note, 120 of 400.');
      expect(runSentence(base.copyWith(phase: RunPhase.prefill, promptTokens: 0)), 'Reading the note.');
      expect(runSentence(base), 'Formatting with Qwen3.5 4B, 31 tokens a second, 0:12.');
      expect(runSentence(base.copyWith(lines: ['a', 'b'], tokensPerSecond: 7.25)), 'Formatting with Qwen3.5 4B, 7.3 tokens a second, 0:12, 2 lines.');
      expect(runSentence(base.copyWith(lines: ['a'])), contains(', 1 line.'));
      // The pace's number alone, for a tile: a tenth under ten, whole above.
      expect([paceNumber(7.25), paceNumber(9.96), paceNumber(31.4)], ['7.3', '10.0', '31']);
    });

    test('says what an ask was asked, since the verb alone says nothing', () {
      expect(runSentence(base.copyWith(kind: RunKind.ask, instruction: 'make it shorter')), '“make it shorter” with Qwen3.5 4B, 31 tokens a second, 0:12.');
    });

    test('says how a run ended', () {
      expect(runSentence(base.copyWith(phase: RunPhase.done, elapsedMs: 42000)), 'Formatted by Qwen3.5 4B in 0:42.');
      expect(runSentence(base.copyWith(phase: RunPhase.done, kind: RunKind.summarize, truncated: true)), 'Summarized by Qwen3.5 4B in 0:12. It ran out of room. Try a shorter note.');
      expect(runSentence(base.copyWith(phase: RunPhase.stopped)), 'Stopped.');
      expect(runSentence(base.copyWith(phase: RunPhase.failed, message: 'The model went away.')), 'The model went away.');
      expect(runSentence(base.copyWith(phase: RunPhase.failed)), 'The model stopped.');
    });

    test('measures the bar against the note while reading and the budget while writing', () {
      expect(progressOf(base.copyWith(phase: RunPhase.prefill, promptTokensDone: 100)), 0.25);
      expect(progressOf(base.copyWith(outputTokens: 50, maxTokens: 200)), 0.25);
      expect(progressOf(base.copyWith(outputTokens: 500, maxTokens: 200)), 1);
      expect(progressOf(base.copyWith(phase: RunPhase.loading)), isNull);
      expect(progressOf(base.copyWith(phase: RunPhase.queued)), isNull);
      expect(progressOf(base.copyWith(phase: RunPhase.done)), 1);
      expect(progressOf(base.copyWith(phase: RunPhase.stopped)), isNull);
    });

    test('reads a clock as minutes and seconds', () {
      expect(clock(0), '0:00');
      expect(clock(61500), '1:02');
    });

    test('writes the log in one line each', () {
      expect(recordSentence(kind: RunKind.format, instruction: null, model: 'qwen3.5-2b', ms: 9000, outcome: RunOutcome.done, message: null), 'Format by Qwen3.5 2B in 0:09.');
      expect(recordSentence(kind: RunKind.ask, instruction: 'add a title', model: 'qwen3.5-2b', ms: 9000, outcome: RunOutcome.done, message: null), '“add a title” by Qwen3.5 2B in 0:09.');
      expect(recordSentence(kind: RunKind.enhance, instruction: null, model: 'qwen3.5-2b', ms: 3000, outcome: RunOutcome.stopped, message: null), 'Enhance, stopped after 0:03.');
      expect(recordSentence(kind: RunKind.fix, instruction: null, model: 'qwen3.5-2b', ms: 3000, outcome: RunOutcome.failed, message: 'No room.'), 'Fix spelling failed: No room.');
    });
  });

  group('a press of Fill in the strip and the log (docs/DESIGN.md §145)', () {
    test('counts the answers as they are written, and the blank it is on across several generations', () {
      expect(runSentence(base.copyWith(kind: RunKind.fill, lines: ['[1] midweek'], batch: const RunBatch(id: 'b', before: 0, asked: 3, total: 3))), 'Filling with Qwen3.5 4B, 31 tokens a second, 0:12, 1 of 3.');
      expect(runSentence(base.copyWith(kind: RunKind.fill, batch: const RunBatch(id: 'b', before: 1, asked: 1, total: 5))), 'Filling 2 of 5 blanks with Qwen3.5 4B.');
    });

    test('says the press’s whole count once it has ended, in the strip and the log', () {
      expect(runSentence(base.copyWith(kind: RunKind.fill, phase: RunPhase.done, said: 'Filled 3 blanks with Qwen3.5 4B in 0:08.')), 'Filled 3 blanks with Qwen3.5 4B in 0:08.');
      expect(filledSentence(1, 'qwen3.5-4b', 2000), 'Filled 1 blank with Qwen3.5 4B in 0:02.');
      expect(recordSentence(kind: RunKind.fill, instruction: 'what day', model: 'qwen3.5-4b', ms: 8000, outcome: RunOutcome.done, message: null, filled: 3), 'Filled 3 blanks with Qwen3.5 4B in 0:08.');
    });
  });
}
