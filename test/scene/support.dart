import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/review_stage.dart';
import 'package:ghost_md/ai/runs.dart';

/// A run as the web's tests make one (`run(over)`): a review of note `n` by Qwen3.5 4B, in [phase], with whatever a
/// case says over it.
RunState run({
  RunKind kind = RunKind.review,
  RunPhase phase = RunPhase.loading,
  List<String> lines = const <String>[],
  String partial = '',
  String thought = '',
  String? text,
  int promptTokens = 0,
  int promptTokensDone = 0,
  int outputTokens = 0,
  int elapsedMs = 0,
  Hardware? hardware,
  bool truncated = false,
  String? message,
  int? endedAt,
}) =>
    RunState(
      id: 'run-1',
      noteId: 'n',
      kind: kind,
      instruction: null,
      model: 'qwen3.5-4b',
      scope: null,
      phase: phase,
      lines: lines,
      partial: partial,
      thought: thought,
      text: text,
      promptTokens: promptTokens,
      promptTokensDone: promptTokensDone,
      outputTokens: outputTokens,
      maxTokens: 1900,
      tokensPerSecond: 0,
      elapsedMs: elapsedMs,
      hardware: hardware,
      truncated: truncated,
      message: message,
      startedAt: 0,
      endedAt: endedAt,
      hash: null,
    );

ReviewStage listening(int? percent) => ReviewStage(what: 'Listening again', detail: 'The slower speech model is listening to the recording again.', percent: percent);
ReviewStage comparing(String detail) => ReviewStage(what: 'Comparing', detail: detail, percent: null);
