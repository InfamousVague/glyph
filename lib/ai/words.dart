/// What the strip says about a run: one sentence per phase, in the words the robot's view and the AI card already
/// used, so nothing the person read before changes its name. Pure, so every sentence is a test. A port of
/// `src/app/ai/words.ts`.
///
/// What differs: `progressOf` takes the whole [RunState] where the page took the five fields it reads, and
/// `recordSentence` takes a record's fields by name, with [recordSentenceOf] for a [RunRecord] in hand.
library;

import 'dart:math' as math;

import 'backend.dart';
import 'kinds.dart';
import 'log.dart';
import 'runs.dart';

/// Milliseconds as m:ss (`clock`).
String clock(num ms) {
  final seconds = (ms / 1000 + 0.5).floor();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Tokens a second as a number: a tenth under ten, whole above (`paceNumber`).
String paceNumber(double perSecond) => perSecond.toStringAsFixed(perSecond < 10 ? 1 : 0);

/// `pace`.
String pace(double perSecond) => '${paceNumber(perSecond)} tokens a second';

/// What the strip says for [run] as it is now (`runSentence`).
String runSentence(RunState run) {
  final words = kindWords(run.kind);
  final name = modelName(run.model);
  final instruction = run.instruction;
  // An ask says what was asked, since "Working" alone says nothing.
  final doing = run.kind == RunKind.ask && instruction != null && instruction.isNotEmpty ? '“$instruction”' : words.doing;
  if (run.kind == RunKind.fill) {
    final said = _fillSentence(run, name);
    if (said != null && said.isNotEmpty) return said;
  }
  switch (run.phase) {
    case RunPhase.queued:
      return 'Waiting for the model, which is on another note.';
    case RunPhase.loading:
      return 'Loading $name.';
    case RunPhase.prefill:
      return run.promptTokens != 0 ? 'Reading the note, ${run.promptTokensDone} of ${run.promptTokens}.' : 'Reading the note.';
    case RunPhase.generating:
      if (run.kind == RunKind.review) {
        return '$name is ${run.lines.isNotEmpty || run.partial.isNotEmpty ? 'writing what it found' : 'thinking it through'}, ${pace(run.tokensPerSecond)}, ${clock(run.elapsedMs)}.';
      }
      final lines = run.lines.isNotEmpty ? ', ${run.lines.length} ${run.lines.length == 1 ? 'line' : 'lines'}' : '';
      return '$doing with $name, ${pace(run.tokensPerSecond)}, ${clock(run.elapsedMs)}$lines.';
    case RunPhase.done:
      return '${words.done} by $name in ${clock(run.elapsedMs)}.${run.truncated ? ' It ran out of room. Try a shorter note.' : ''}';
    case RunPhase.stopped:
      return 'Stopped.';
    case RunPhase.failed:
      return run.message ?? 'The model stopped.';
  }
}

/// Blanks as a count: "1 blank", "3 blanks" (`blanksWord`).
String blanksWord(int n) => '$n ${n == 1 ? 'blank' : 'blanks'}';

/// A press of Fill as the strip says it (docs/DESIGN.md §145, 14): the answers as they are written in one
/// generation, the blank it is on across several, and the press's whole count once it has ended. Null for a phase
/// said the usual way.
String? _fillSentence(RunState run, String name) {
  final batch = run.batch;
  if (run.phase == RunPhase.generating && batch != null) {
    if (batch.total > batch.asked) return 'Filling ${math.min(batch.total, batch.before + 1)} of ${blanksWord(batch.total)} with $name.';
    return 'Filling with $name, ${pace(run.tokensPerSecond)}, ${clock(run.elapsedMs)}, ${math.min(run.lines.length, batch.asked)} of ${batch.asked}.';
  }
  final said = run.said;
  if (run.phase == RunPhase.done && said != null && said.isNotEmpty) return said;
  return null;
}

/// A press of Fill's one line, in the strip once it has ended and in the log (`filledSentence`).
String filledSentence(int filled, String model, num ms) => filled != 0 ? 'Filled ${blanksWord(filled)} with ${modelName(model)} in ${clock(ms)}.' : 'Nothing filled by ${modelName(model)}.';

/// How far along a run is, 0 to 1, or null where there is no telling (`progressOf`): reading the note is prompt
/// tokens done of prompt tokens, writing is tokens written of the most it may write (a run usually finishes well
/// short of that, so the bar is a floor, not a promise), and a run that has ended is full.
double? progressOf(RunState run) {
  if (run.phase == RunPhase.prefill) return run.promptTokens != 0 ? math.min(1.0, run.promptTokensDone / run.promptTokens) : null;
  if (run.phase == RunPhase.generating) return run.maxTokens != 0 ? math.min(1.0, run.outputTokens / run.maxTokens) : null;
  if (run.phase == RunPhase.done) return 1;
  return null;
}

/// Marks left in the note with no run to speak of: how many, and that they are the AI's (`marksSentence`).
String marksSentence(int count) => count == 1 ? 'One change from the AI is marked in the note.' : '$count changes from the AI are marked in the note.';

/// A run's phase in the AI card's older dialect (ai/backend.dart [Phase]): waiting reads as loading, stopped as
/// cancelled, failed as error (`cardPhase`).
Phase cardPhase(RunState run) => switch (run.phase) {
      RunPhase.queued || RunPhase.loading => Phase.loading,
      RunPhase.prefill => Phase.prefill,
      RunPhase.generating => Phase.generating,
      RunPhase.done => Phase.done,
      RunPhase.stopped => Phase.cancelled,
      RunPhase.failed => Phase.error,
    };

/// A run's record as one line of the log: what, by which model, how long, and how it ended (`recordSentence`).
String recordSentence({required RunKind kind, required String? instruction, required String model, required num ms, required RunOutcome outcome, required String? message, int? filled}) {
  final words = kindWords(kind);
  if (kind == RunKind.fill && outcome == RunOutcome.done) return filledSentence(filled ?? 0, model, ms);
  final what = kind == RunKind.ask && instruction != null && instruction.isNotEmpty ? '“$instruction”' : words.label;
  if (outcome == RunOutcome.stopped) return '$what, stopped after ${clock(ms)}.';
  if (outcome == RunOutcome.failed) return '$what failed${message != null && message.isNotEmpty ? ': $message' : '.'}';
  return '$what by ${modelName(model)} in ${clock(ms)}.';
}

/// [recordSentence] for a record of the log as it is kept.
String recordSentenceOf(RunRecord record) =>
    recordSentence(kind: record.kind, instruction: record.instruction, model: record.model, ms: record.ms, outcome: record.outcome, message: record.message, filled: record.filled);
