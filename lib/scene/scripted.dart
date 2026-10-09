/// The scene played from a script (the developer's scene bench, and `?scene=` in a browser): the review's stages and
/// its run as a phone would report them, with pretend models, so the layout, the pictures and the steps can be
/// looked at without a recording - which is what Matt asked to review on his Fold. Three scripts: with a heat
/// reading, without one (a phone that hides its thermal zones), and with no readings at all (the Mac, or a binary
/// before generation 14). A port of `src/app/scene/scripted.ts`.
///
/// The run is handed to the engine the way the browser's `?review` hands its own (ai/runs.dart [simulateRuns]),
/// round `startRun` alone, so no real run is ever played by the script.
///
/// What differs: a script is an enum whose [Enum.name] is the web's word. The clock the script reads (`Date.now()`)
/// is a parameter, [scriptedReview]'s `now`, so a test's clock can be the one its timers run on; left out, it is the
/// wall clock. A stopped run fails with an [AiFailure] saying `cancelled`, which ai/runs.dart reads as a stop (the page threw
/// `new Error('cancelled')`). [sceneQuery] is given the address to read: the app is never a page in a browser, so
/// with none it answers null, as the page did under Tauri.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../ai/backend.dart';
import '../ai/review_stage.dart';

/// `SceneScript`; [name] is the web's word.
enum SceneScript { heat, cold, none }

/// What the pretend fast model heard, "seat bar" and all (the review simulation's mishearing). `SCRIPT_HEARD`.
const String scriptHeard = 'Notes from the planning call this morning. '
    'The seat bar on the player still jumps when the tape is scrubbed quickly. '
    'Hey Ghost, add a task fix the seat bar before the demo on Thursday. '
    'HelloTrade want the summary page ready by the end of the month. '
    'The onboarding flame reads well on the dark theme and less well on paper. '
    'Remember to measure the smoke on the Fold with the switch off and on. '
    'Groceries after work, milk, eggs, coffee and something for the garden. '
    'Call the plumber back about the boiler service.';

/// The note those words made (`SCRIPT_BODY`).
const String scriptBody = '# Planning call\n'
    '\n'
    'Notes from the planning call this morning.\n'
    'The seat bar on the player still jumps when the tape is scrubbed quickly.\n'
    '\n'
    '- [ ] Fix the seat bar before the demo on Thursday\n'
    '\n'
    'HelloTrade want the summary page ready by the end of the month.\n'
    'The onboarding flame reads well on the dark theme and less well on paper.\n'
    'Remember to measure the smoke on the Fold with the switch off and on.\n'
    '\n'
    'Groceries after work, milk, eggs, coffee and something for the garden.\n'
    'Call the plumber back about the boiler service.';

/// The prompt the pretend run is given; the script never reads it (`SCRIPT_PROMPT`).
const String scriptPrompt = 'AS HEARD:\n$scriptHeard\n\nAS SAVED:\n$scriptBody';

/// The thought the pretend model streams: the browser's own (the review simulation's), a little longer.
const String _thought = 'Thinking Process:\n'
    '\n'
    '1. Words. The two transcripts disagree in a few places. The slower model heard "seek bar" where the fast one heard "seat bar"; a seek bar is the scrubber in a player, so "seek" is right, and the task says the same words.\n'
    '2. Structure. The heading names the note, the to-do is a thing to do, and nothing else looks like a list. The groceries could be one, but they were said as a sentence.\n'
    '3. Commands. The one spoken command landed where its words said, as a task under the line about the player.\n'
    '4. Names. HelloTrade is written as one word in the note titles, and the note has it that way.';

/// The findings the pretend model writes, typed in as JSON so the open "what" shows as the pen line.
const List<Map<String, String>> _findings = <Map<String, String>>[
  {
    'check': 'words',
    'what': '“seek bar”, not “seat bar”',
    'why': 'The slower speech model heard it this way, and a seek bar is the scrubber in a player.',
    'find': 'The seat bar on the player still jumps when the tape is scrubbed quickly.',
    'replace': 'The seek bar on the player still jumps when the tape is scrubbed quickly.',
  },
  {
    'check': 'structure',
    'what': 'The groceries as a list',
    'why': 'Four things to buy were said in one breath; a list is what they are.',
    'find': 'Groceries after work, milk, eggs, coffee and something for the garden.',
    'replace': '## Groceries after work\n\n- Milk\n- Eggs\n- Coffee\n- Something for the garden',
  },
];

/// The report cadence, as the engine's.
const int _reportMs = 120;

/// Loading is one report, then silence while the model comes into memory.
const int _loadMs = 1800;
const int _promptTokens = 1040;
const int _prefillStep = 128;
const int _prefillMs = 2400;

/// Six characters every thirty milliseconds (the review simulation's), at the report cadence.
const int _charsAReport = 24;

/// The stages before the run: listening again 0 to 100 in tens every quarter second, then comparing for a moment,
/// then null. Answers the way to stop early. `scriptedStages`.
VoidCallback scriptedStages(void Function(ReviewStage? stage) onStage) {
  var stopped = false;
  Timer? timer;
  const detail = 'The slower speech model is listening to the recording again.';
  var percent = 0;
  void listen() {
    if (stopped) return;
    onStage(ReviewStage(what: 'Listening again', detail: detail, percent: percent));
    if (percent < 100) {
      percent += 10;
      timer = Timer(const Duration(milliseconds: 250), listen);
      return;
    }
    timer = Timer(const Duration(milliseconds: 250), () {
      if (stopped) return;
      onStage(const ReviewStage(what: 'Comparing', detail: '3 places where the two models heard different words.', percent: null));
      timer = Timer(const Duration(milliseconds: 600), () {
        if (!stopped) onStage(null);
      });
    });
  }

  listen();
  return () {
    stopped = true;
    timer?.cancel();
  };
}

/// The phone under the pretend model: the readings ramp as a real run's do.
Hardware? _hardwareAt(SceneScript script, int sinceRunMs, int sinceStartMs, bool first) {
  if (script == SceneScript.none) return null;
  final busy = first ? 0.0 : math.min(1.0, sinceRunMs / 1000);
  return Hardware(
    cores: 8,
    threads: 6,
    rssBytes: 3100000000,
    totalBytes: 12000000000,
    freeBytes: 4000000000,
    cpuPercent: (640 * busy + 0.5).floorToDouble(),
    tempC: script == SceneScript.heat ? ((31 + 13 * math.min(1.0, sinceStartMs / 12000)) * 10 + 0.5).floorToDouble() / 10 : null,
  );
}

int _wallClock() => DateTime.now().millisecondsSinceEpoch;

/// The pretend model, handed to the engine round `startRun` (ai/runs.dart [simulateRuns]). `scriptedReview`. [now]
/// is the clock it reads, in milliseconds; the wall clock when left out.
Run Function(RunOptions options) scriptedReview(SceneScript script, {int Function()? now}) {
  final clock = now ?? _wallClock;
  return (options) {
    var cancelled = false;

    /// Ends the sleep under way, answering cancelled at once rather than at its end.
    VoidCallback? wake;
    Future<void> sleep(num ms) {
      final slept = Completer<void>();
      final timer = Timer(Duration(microseconds: (ms * 1000).round()), () {
        wake = null;
        slept.complete();
      });
      wake = () {
        timer.cancel();
        wake = null;
        slept.completeError(const AiFailure('cancelled'));
      };
      return slept.future;
    }

    final text = '<think>\n$_thought\n</think>\n\n${const JsonEncoder.withIndent(' ').convert(_findings)}';
    Future<Output> play() async {
      final started = clock();
      void report({required Phase phase, required int promptTokensDone, required int outputTokens, required double tokensPerSecond, required String partial, Hardware? hardware}) {
        if (cancelled) throw const AiFailure('cancelled');
        options.onProgress(Progress(
          id: 'scene',
          promptTokens: _promptTokens,
          thinking: true,
          phase: phase,
          promptTokensDone: promptTokensDone,
          outputTokens: outputTokens,
          tokensPerSecond: tokensPerSecond,
          partial: partial,
          hardware: hardware,
          elapsedMs: clock() - started,
        ));
      }

      report(phase: Phase.loading, promptTokensDone: 0, outputTokens: 0, tokensPerSecond: 0, partial: '');
      await sleep(_loadMs);
      // Reading: ticks of a hundred and a bit up to the prompt's length, at about 430 a second.
      final ticks = (_promptTokens / _prefillStep).ceil();
      final runFrom = clock();
      for (var i = 1; i <= ticks; i += 1) {
        await sleep(_prefillMs / ticks);
        final read = math.min(_promptTokens, i * _prefillStep);
        report(
          phase: Phase.prefill,
          promptTokensDone: read,
          outputTokens: 0,
          tokensPerSecond: (read / math.max(1, clock() - runFrom) * 1000 + 0.5).floorToDouble(),
          partial: '',
          hardware: _hardwareAt(script, clock() - runFrom, clock() - started, i == 1),
        );
      }
      // Writing: the thought, then the findings, a few characters a report.
      final writeFrom = clock();
      for (var at = _charsAReport; at < text.length + _charsAReport; at += _charsAReport) {
        await sleep(_reportMs);
        final partial = text.substring(0, math.min(text.length, at));
        final outputTokens = (partial.length / 4 + 0.5).floor();
        report(
          phase: Phase.generating,
          promptTokensDone: _promptTokens,
          outputTokens: outputTokens,
          tokensPerSecond: (outputTokens / math.max(1, clock() - writeFrom) * 1000 * 10 + 0.5).floorToDouble() / 10,
          partial: partial,
          hardware: _hardwareAt(script, clock() - runFrom, clock() - started, false),
        );
      }
      final ms = clock() - started;
      final outputTokens = (text.length / 4 + 0.5).floor();
      return Output(
        text: text,
        promptTokens: _promptTokens,
        outputTokens: outputTokens,
        ms: ms,
        cachedTokens: 0,
        prefillMs: _prefillMs,
        loadMs: _loadMs,
        tokensPerSecond: (outputTokens / math.max(1, ms - _loadMs - _prefillMs) * 1000 * 10 + 0.5).floorToDouble() / 10,
        truncated: false,
        thinking: true,
      );
    }

    return Run(
      done: play(),
      cancel: () {
        cancelled = true;
        wake?.call();
      },
    );
  };
}

/// `?scene=heat|cold|none` in a browser plays the bench at launch; nothing on the phone, where the Developer page is
/// the way in. `sceneQuery`. [address] is where the app was opened from, when it was opened from an address at all.
SceneScript? sceneQuery({Uri? address}) {
  if (address == null) return null;
  final asked = address.queryParameters['scene'];
  for (final script in SceneScript.values) {
    if (script.name == asked) return script;
  }
  return null;
}
