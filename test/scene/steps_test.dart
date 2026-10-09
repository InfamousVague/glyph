import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/ai/words.dart';
import 'package:ghost_md/scene/steps.dart';

import 'support.dart';

/// The scene's words and heat, from what the review is doing: the steps in order, which is working, what the title
/// says (word for word the strip's own where they are shared), and the die's warmth and glow. The cases of
/// `src/app/scene/steps.test.ts`, by name.

List<String> ids(List<Step> steps) => [for (final s in steps) s.id.name];
List<String> states(List<Step> steps) => [for (final s in steps) '${s.id.name}:${s.state.name}'];

void main() {
  group('the steps', () {
    test('draws six in the order things happen with a job, and five without', () {
      expect(ids(stepsOf(const SceneInput())), ['listen', 'load', 'read', 'think', 'write', 'done']);
      expect(ids(stepsOf(const SceneInput(hasJob: false))), ['load', 'read', 'think', 'write', 'done']);
      // At the opening the first step is the one working, and the rest wait.
      expect(states(stepsOf(const SceneInput())), ['listen:working', 'load:waiting', 'read:waiting', 'think:waiting', 'write:waiting', 'done:waiting']);
    });

    test('ticks the listen step when Comparing arrives, with its detail kept after the stage clears', () {
      const detail = '3 places where the two models heard different words.';
      final compared = stepsOf(SceneInput(stage: comparing(detail), compared: detail));
      expect(compared[0], const Step(id: StepId.listen, words: 'Listening again', state: StepState.done, detail: detail));
      expect(compared[1].state, StepState.working);
      final later = stepsOf(SceneInput(compared: detail, run: run(phase: RunPhase.prefill)));
      expect(later[0].state, StepState.done);
      expect(later[0].detail, detail);
    });

    test('skips the listen step when there was nothing to compare against, with the reason as its detail', () {
      final steps = stepsOf(SceneInput(stage: comparing(nothingToCompare), compared: nothingToCompare));
      expect(steps[0], const Step(id: StepId.listen, words: 'Listening again', state: StepState.skipped, detail: nothingToCompare));
      expect(steps[1].state, StepState.working);
    });

    test('puts the download’s words in the listen step while it downloads', () {
      final steps = stepsOf(SceneInput(stage: listening(0), download: (received: 12000000, total: 190000000)));
      expect(steps[0].detail, 'Getting the better voice model, 12 of 190 MB.');
    });

    test('lets a stage win over a live run', () {
      final steps = stepsOf(SceneInput(stage: listening(40), run: run(phase: RunPhase.generating, kind: RunKind.ask)));
      expect(steps[0].state, StepState.working);
      expect(workingStep(SceneInput(stage: listening(40), run: run(phase: RunPhase.generating))), StepId.listen);
      expect(sceneTitle(SceneInput(stage: listening(40), run: run(phase: RunPhase.generating))), 'Listening again, 40%.');
    });

    test('advances the working step with each phase of the run', () {
      const compared = 'Both models heard the same words.';
      StepId? at(RunState r) => workingStep(SceneInput(compared: compared, run: r));
      expect(at(run(phase: RunPhase.queued)), StepId.load);
      expect(at(run(phase: RunPhase.loading)), StepId.load);
      expect(at(run(phase: RunPhase.prefill)), StepId.read);
      expect(at(run(phase: RunPhase.generating)), StepId.think);
      expect(at(run(phase: RunPhase.generating, thought: 'Is seat right?')), StepId.think);
      expect(at(run(phase: RunPhase.generating, thought: 'Is seat right?', partial: '[{"what": "')), StepId.write);
      expect(at(run(phase: RunPhase.done, text: '[]', lines: ['[]'])), isNull);
      expect(states(stepsOf(SceneInput(compared: compared, run: run(phase: RunPhase.done, text: '[]', lines: ['[]'])))), ['listen:done', 'load:done', 'read:done', 'think:done', 'write:done', 'done:done']);
    });

    test('shows the load step working while the run is queued', () {
      final load = stepsOf(SceneInput(run: run(phase: RunPhase.queued)))[1];
      expect(load.id, StepId.load);
      expect(load.state, StepState.working);
    });

    test('ticks nothing more once the run stopped or failed', () {
      final stopped = stepsOf(SceneInput(compared: 'x', run: run(phase: RunPhase.stopped, thought: 'Was thinking', endedAt: 1)));
      expect(states(stopped), ['listen:done', 'load:done', 'read:done', 'think:waiting', 'write:waiting', 'done:waiting']);
      expect(workingStep(SceneInput(compared: 'x', run: run(phase: RunPhase.failed, message: 'Out of memory.'))), isNull);
    });

    test('uses a summary’s words for a run of that kind, with no listen and no thinking', () {
      final steps = stepsOf(SceneInput(run: run(kind: RunKind.summarize, phase: RunPhase.prefill)));
      expect([for (final s in steps) s.words], ['Loading the model', 'Reading the recording', 'Writing the summary', 'Done']);
    });

    test('ticks every step when the review is over with no run', () {
      expect(states(stepsOf(const SceneInput(ended: true))), ['listen:done', 'load:done', 'read:done', 'think:done', 'write:done', 'done:done']);
    });
  });

  group('the title', () {
    test('says every line in the app’s voice, word for word the strip’s where they share one', () {
      expect(sceneTitle(const SceneInput()), 'Checking what was heard.');
      expect(sceneTitle(SceneInput(stage: listening(0), download: (received: 12000000, total: 190000000))), 'Getting the better voice model, 12 of 190 MB.');
      expect(sceneTitle(SceneInput(stage: listening(0))), 'Listening again.');
      expect(sceneTitle(SceneInput(stage: listening(40))), 'Listening again, 40%.');
      expect(sceneTitle(SceneInput(stage: comparing('x'))), 'Comparing.');
      final queued = run(phase: RunPhase.queued);
      expect(sceneTitle(SceneInput(run: queued)), 'Waiting for the model, which is on another note.');
      expect(sceneTitle(SceneInput(run: queued)), runSentence(queued));
      final loading = run(phase: RunPhase.loading);
      expect(sceneTitle(SceneInput(run: loading)), 'Loading Qwen3.5 4B.');
      expect(sceneTitle(SceneInput(run: loading)), runSentence(loading));
      final reading = run(phase: RunPhase.prefill, promptTokens: 1040, promptTokensDone: 312);
      expect(sceneTitle(SceneInput(run: reading)), 'Reading the note, 312 of 1040.');
      expect(sceneTitle(SceneInput(run: reading)), runSentence(reading));
      expect(sceneTitle(SceneInput(run: run(phase: RunPhase.prefill))), 'Reading the note.');
      expect(sceneTitle(SceneInput(run: run(phase: RunPhase.generating, thought: 'Hmm'))), 'Qwen3.5 4B is thinking it through.');
      expect(sceneTitle(SceneInput(run: run(phase: RunPhase.generating, thought: 'Hmm', partial: '['))), 'Qwen3.5 4B is writing what it found.');
      expect(sceneTitle(SceneInput(run: run(kind: RunKind.summarize, phase: RunPhase.generating))), 'Summarizing with Qwen3.5 4B.');
      final done = run(phase: RunPhase.done, elapsedMs: 72000, text: '[]', lines: ['[]']);
      expect(sceneTitle(SceneInput(run: done)), 'Reviewed by Qwen3.5 4B in 1:12.');
      expect(sceneTitle(SceneInput(run: done)), runSentence(done));
      final cut = run(phase: RunPhase.done, elapsedMs: 72000, text: '[]', lines: ['[]'], truncated: true);
      expect(sceneTitle(SceneInput(run: cut)), runSentence(cut));
      expect(sceneTitle(SceneInput(run: run(phase: RunPhase.stopped))), 'Stopped.');
      expect(sceneTitle(SceneInput(run: run(phase: RunPhase.failed, message: 'The model stopped.'))), 'The model stopped.');
      expect(sceneTitle(const SceneInput(ended: true)), 'Done.');
    });

    test('has a detail for each moment', () {
      expect(sceneDetail(const SceneInput()), 'The recording is saved.');
      expect(sceneDetail(SceneInput(stage: listening(0), download: (received: 0, total: 1))), 'Once, then it stays on the phone.');
      expect(sceneDetail(SceneInput(stage: listening(10))), 'The slower speech model is listening to the recording again.');
      expect(sceneDetail(SceneInput(run: run(phase: RunPhase.queued))), '');
      expect(sceneDetail(SceneInput(run: run(phase: RunPhase.loading))), '2.7 GB on this phone.');
      expect(sceneDetail(SceneInput(run: run(phase: RunPhase.prefill))), 'The note and everything that was heard.');
      expect(sceneDetail(SceneInput(run: run(phase: RunPhase.generating))), 'Thinking it through out loud.');
      expect(sceneDetail(SceneInput(run: run(phase: RunPhase.generating, partial: '['))), 'What it finds is checked against the note, then marked.');
      expect(sceneDetail(SceneInput(run: run(phase: RunPhase.done))), '');
      expect(sceneDetail(const SceneInput(ended: true)), '');
    });

    test('parts the progress numbers from the words, and leaves a model’s name whole', () {
      expect(titlePieces('Reading the note, 312 of 1040.'), [
        (text: 'Reading the note', number: false),
        (text: ', 312 of 1040', number: true),
        (text: '.', number: false),
      ]);
      expect(titlePieces('Listening again, 40%.'), [
        (text: 'Listening again', number: false),
        (text: ', 40%', number: true),
        (text: '.', number: false),
      ]);
      expect(titlePieces('Reviewed by Qwen3.5 4B in 1:12.'), [
        (text: 'Reviewed by Qwen3.5 4B', number: false),
        (text: ' in 1:12', number: true),
        (text: '.', number: false),
      ]);
      expect(titlePieces('Qwen3.5 4B is thinking it through.'), [(text: 'Qwen3.5 4B is thinking it through.', number: false)]);
    });

    test('changes the live line only with the step, never with a number', () {
      expect(liveWords(SceneInput(stage: listening(10))), 'Listening again.');
      expect(liveWords(SceneInput(stage: listening(40))), 'Listening again.');
      expect(liveWords(SceneInput(run: run(phase: RunPhase.prefill, promptTokens: 100, promptTokensDone: 10))), 'Reading the note.');
      expect(liveWords(SceneInput(run: run(phase: RunPhase.prefill, promptTokens: 100, promptTokensDone: 90))), 'Reading the note.');
      expect(liveWords(SceneInput(run: run(phase: RunPhase.generating))), 'Thinking it through.');
      expect(liveWords(SceneInput(run: run(phase: RunPhase.done, elapsedMs: 3000))), 'Reviewed by Qwen3.5 4B in 0:03.');
      expect(liveWords(const SceneInput(ended: true)), 'Done.');
    });
  });

  group('the heat', () {
    test('is cold, warm or hot by state', () {
      expect(warmthOf(const SceneInput()), Warmth.cold);
      expect(warmthOf(SceneInput(stage: listening(0))), Warmth.warm);
      expect(warmthOf(SceneInput(stage: listening(0), download: (received: 0, total: 1))), Warmth.warm);
      expect(warmthOf(SceneInput(run: run(phase: RunPhase.queued))), Warmth.cold);
      expect(warmthOf(SceneInput(run: run(phase: RunPhase.loading))), Warmth.warm);
      expect(warmthOf(SceneInput(run: run(phase: RunPhase.prefill))), Warmth.hot);
      expect(warmthOf(SceneInput(run: run(phase: RunPhase.generating))), Warmth.hot);
      expect(warmthOf(SceneInput(run: run(phase: RunPhase.done))), Warmth.cold);
      expect(warmthOf(SceneInput(run: run(phase: RunPhase.stopped))), Warmth.cold);
      expect(warmthOf(const SceneInput(ended: true)), Warmth.cold);
    });

    test('glows only from a sample past loading, busy over the engine’s threads, blended with the heat', () {
      Hardware hardware({double cpuPercent = 640, int threads = 6, double? tempC}) =>
          Hardware(rssBytes: 3000000000, freeBytes: 4000000000, totalBytes: 12000000000, cpuPercent: cpuPercent, threads: threads, cores: 8, tempC: tempC);
      expect(glowOf(null), 0);
      expect(glowOf(run(phase: RunPhase.prefill)), 0);
      expect(glowOf(run(phase: RunPhase.loading, hardware: hardware())), 0);
      // Six threads at full tilt is full, whatever the eighth core is doing.
      expect(glowOf(run(phase: RunPhase.generating, hardware: hardware())), 1);
      expect(glowOf(run(phase: RunPhase.generating, hardware: hardware(cpuPercent: 300))), 0.5);
      expect(glowOf(run(phase: RunPhase.generating, hardware: hardware(cpuPercent: 900))), 1);
      // With a temperature, half and half: 40 °C is half way from 20 to 60.
      expect(glowOf(run(phase: RunPhase.generating, hardware: hardware(tempC: 40))), 0.75);
      expect(glowOf(run(phase: RunPhase.generating, hardware: hardware(cpuPercent: 0, tempC: 70))), 0.5);
      // Cooled once it has ended.
      expect(glowOf(run(phase: RunPhase.done, hardware: hardware())), 0);
      // No threads reported: the cores, held between two and six.
      expect(glowOf(run(phase: RunPhase.generating, hardware: hardware(threads: 0, cpuPercent: 600))), 1);
    });

    test('steps the glow to a ring, and lights a pin a core', () {
      expect(glowStepOf(0), 0);
      expect(glowStepOf(0.5), 3);
      expect(glowStepOf(1), 5);
      expect(glowStepOf(1.4), 5);
      expect(litPinsOf(640, 8), 6);
      expect(litPinsOf(0, 8), 0);
      expect(litPinsOf(1200, 8), 8);
      expect(pinsOf(8), 8);
      expect(pinsOf(16), 12);
      expect(pinsOf(1), 2);
    });
  });
}
