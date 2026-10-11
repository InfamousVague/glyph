// The run machine (lib/ai/runs.dart). A port of `src/app/ai/runs.test.ts`, case for case.
//
// A model that answers when the test says so: the web mocked `generate` in core/ai.ts; here `simulateRuns` is that
// seam, and each call hands back its progress callback and a way to end it.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/log.dart';
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/core/stored.dart';

class Fake {
  Fake(this.options);

  final RunOptions options;
  final Completer<Output> _done = Completer<Output>();
  bool cancelled = false;

  Run get run => Run(
        done: _done.future,
        cancel: () {
          cancelled = true;
          if (!_done.isCompleted) _done.completeError(StateError('cancelled'));
        },
      );

  void report({Phase phase = Phase.generating, int promptTokensDone = 100, String partial = '', bool? thinking}) => options.onProgress(
        Progress(id: 'x', phase: phase, promptTokens: 100, promptTokensDone: promptTokensDone, outputTokens: 10, tokensPerSecond: 12, elapsedMs: 1000, partial: partial, thinking: thinking),
      );

  void finish(String text, {bool? thinking}) =>
      _done.complete(Output(text: text, promptTokens: 100, outputTokens: 20, ms: 2000, cachedTokens: 0, prefillMs: 100, loadMs: 100, tokensPerSecond: 12, truncated: false, thinking: thinking));

  void fail(String message) => _done.completeError(StateError(message));
}

final List<Fake> fakes = [];

Future<void> tick() => Future<void>.delayed(Duration.zero);

RunRequest request(String noteId) => RunRequest(noteId: noteId, kind: RunKind.format, model: 'qwen3.5-4b', system: 'Format.', prompt: 'hello', maxTokens: 200);

void main() {
  setUp(() {
    useStored(MemoryStored());
    fakes.clear();
    simulateRuns((options) {
      final fake = Fake(options);
      fakes.add(fake);
      return fake.run;
    });
  });

  tearDown(() {
    forgetAllRuns();
    simulateRuns(null);
  });

  group('cutting the text at whole lines', () {
    test('keeps the line under the pen apart from the lines that are finished', () {
      expect(splitLines('').lines, isEmpty);
      expect(splitLines('').partial, '');
      expect(splitLines('# Trip').lines, isEmpty);
      expect(splitLines('# Trip').partial, '# Trip');
      expect(splitLines('# Trip\n').lines, ['# Trip']);
      expect(splitLines('# Trip\n').partial, '');
      expect(splitLines('# Trip\n\n- [ ] Call the plum').lines, ['# Trip', '']);
      expect(splitLines('# Trip\n\n- [ ] Call the plum').partial, '- [ ] Call the plum');
    });

    test('reads a finished text as all its lines, the trailing newline not one of them', () {
      expect(allLines('# Trip\n\n- a\n'), ['# Trip', '', '- a']);
      expect(allLines(''), isEmpty);
    });
  });

  group('a run', () {
    test('streams whole lines as they finish, then lands the whole text', () async {
      final seen = <List<String>>[];
      final off = subscribeRuns((run) => seen.add([...run.lines]));
      final handle = startRun(request('n1'));
      await tick();
      expect(runFor('n1')?.phase, RunPhase.loading);
      final fake = fakes[0];
      fake.report(phase: Phase.prefill, promptTokensDone: 40);
      expect(runFor('n1')?.phase, RunPhase.prefill);
      expect(runFor('n1')?.promptTokensDone, 40);
      fake.report(partial: '# Trip\n\n- [ ] Call the plum');
      expect(runFor('n1')?.lines, ['# Trip', '']);
      expect(runFor('n1')?.partial, '- [ ] Call the plum');
      fake.report(partial: '# Trip\n\n- [ ] Call the plumber.\n- [ ] Eggs');
      expect(runFor('n1')?.lines, ['# Trip', '', '- [ ] Call the plumber.']);
      fake.finish('# Trip\n\n- [ ] Call the plumber.\n- [ ] Eggs and coffee.\n');
      final last = await handle.done;
      expect(last.phase, RunPhase.done);
      expect(last.text, '# Trip\n\n- [ ] Call the plumber.\n- [ ] Eggs and coffee.\n');
      expect(last.lines, ['# Trip', '', '- [ ] Call the plumber.', '- [ ] Eggs and coffee.']);
      expect(last.partial, '');
      // Lines only ever grew.
      for (var i = 1; i < seen.length; i += 1) {
        expect(seen[i].length, greaterThanOrEqualTo(seen[i - 1].length));
      }
      off();
      final kept = runsOf('n1')[0];
      expect(kept.kind, RunKind.format);
      expect(kept.model, 'qwen3.5-4b');
      expect(kept.outcome, RunOutcome.done);
    });

    test('writes no line of its own in the log for a press of Fill, whose queue writes the press’s one (docs/DESIGN.md §145)', () async {
      final handle = startRun(request('fill-note').copyWith(kind: RunKind.fill, batch: const RunBatch(id: 'b1', before: 0, asked: 2, total: 2)));
      await tick();
      fakes[0].finish('[1] midweek\n[2] Canberra');
      final last = await handle.done;
      expect(last.batch, const RunBatch(id: 'b1', before: 0, asked: 2, total: 2));
      expect(runsOf('fill-note'), isEmpty);
      sayRun('fill-note', last.id, 'Filled 2 blanks with Qwen3.5 4B in 0:02.');
      expect(runFor('fill-note')?.said, 'Filled 2 blanks with Qwen3.5 4B in 0:02.');
    });

    test('puts the links and tables back with the caller’s restore, and tidies once at the end', () async {
      final handle = startRun(request('n2').copyWith(restore: (text, isFinal) => isFinal ? '${text.trim()}!\n' : text.replaceAll('link-1', 'https://a')));
      await tick();
      fakes[0].report(partial: 'see [a](link-1)\nmore');
      expect(runFor('n2')?.lines, ['see [a](https://a)']);
      fakes[0].finish('see [a](link-1)\nmore\n');
      final last = await handle.done;
      expect(last.text, 'see [a](link-1)\nmore!\n');
    });

    test('keeps a thinking model’s reasoning apart from its answer', () async {
      final handle = startRun(request('n3').copyWith(think: true));
      await tick();
      fakes[0].report(partial: '<think>Is the name right?', thinking: true);
      expect(runFor('n3')?.thought, 'Is the name right?');
      expect(runFor('n3')?.lines, isEmpty);
      fakes[0].report(partial: '<think>Is the name right?</think>[]\n', thinking: true);
      expect(runFor('n3')?.lines, ['[]']);
      fakes[0].finish('<think>Is the name right?</think>[]\n', thinking: true);
      final last = await handle.done;
      expect(last.thought, 'Is the name right?');
      expect(last.text, '[]\n');
    });

    test('waits behind a run on another note, and goes once it ends', () async {
      final first = startRun(request('a'));
      final second = startRun(request('b'));
      await tick();
      expect(fakes.length, 1);
      expect(runFor('b')?.phase, RunPhase.queued);
      expect(isRunning('b'), isTrue);
      fakes[0].finish('done a\n');
      await first.done;
      await tick();
      expect(fakes.length, 2);
      expect(runFor('b')?.phase, RunPhase.loading);
      fakes[1].finish('done b\n');
      expect((await second.done).text, 'done b\n');
    });

    test('takes the place of an earlier run on the same note', () async {
      final first = startRun(request('same'));
      await tick();
      final second = startRun(request('same').copyWith(kind: RunKind.summarize));
      final ended = await first.done;
      expect(ended.phase, RunPhase.stopped);
      expect(fakes[0].cancelled, isTrue);
      await tick();
      expect(runFor('same')?.kind, RunKind.summarize);
      fakes[1].finish('short\n');
      expect((await second.done).phase, RunPhase.done);
    });

    test('stops when asked, and says so; and says why it failed', () async {
      final handle = startRun(request('s'));
      await tick();
      fakes[0].report(partial: 'one\ntwo');
      await cancelRun('s');
      final last = await handle.done;
      expect(last.phase, RunPhase.stopped);
      expect(last.lines, ['one']);
      expect(last.text, isNull);
      expect(runsOf('s')[0].outcome, RunOutcome.stopped);

      final failing = startRun(request('f'));
      await tick();
      fakes[1].fail('The model is not on this phone yet.');
      final failed = await failing.done;
      expect(failed.phase, RunPhase.failed);
      expect(failed.message, 'The model is not on this phone yet.');
      expect(runsOf('f')[0].outcome, RunOutcome.failed);
      expect(runsOf('f')[0].message, 'The model is not on this phone yet.');
    });

    test('stops a run that was still waiting without ever starting it', () async {
      startRun(request('going'));
      final waiting = startRun(request('later'));
      await tick();
      await cancelRun('later');
      expect((await waiting.done).phase, RunPhase.stopped);
      expect(fakes.length, 1);
      fakes[0].finish('x\n');
    });

    test('is put away once dismissed, and only once it has ended', () async {
      final handle = startRun(request('d'));
      await tick();
      dismissRun('d');
      expect(runFor('d'), isNotNull);
      fakes[0].finish('x\n');
      await handle.done;
      dismissRun('d');
      expect(runFor('d'), isNull);
    });

    test('tells a screen whether the model is on any note, as a run starts and as it ends', () async {
      // The screen is a listener of `useAnyRunning()`, which draws what it was last told.
      final watching = useAnyRunning();
      var busy = watching.value;
      void draw() => busy = watching.value;
      watching.addListener(draw);
      addTearDown(() => watching.removeListener(draw));
      expect(anyRunning(), isFalse);
      expect(busy, isFalse);
      final handle = startRun(request('any'));
      await tick();
      expect(anyRunning(), isTrue);
      expect(busy, isTrue);
      fakes[0].finish('x\n');
      await handle.done;
      // The ended state is said again once nothing is active, so the answer changes the moment the run ends.
      expect(anyRunning(), isFalse);
      expect(busy, isFalse);
    });
  });
}
