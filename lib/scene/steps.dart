/// The steps, the title and the heat of the scene while the models work on a recording (scene/at_work.dart):
/// everything the scene says or shades, worked out from what the review is doing, with no widget in it, so each line
/// is a test. A port of `src/app/scene/steps.ts`.
///
/// Matt: "make the analyzing steps of the AI full screen high contrast SVG iconography with cool effects like a
/// piping hot phone CPU scrolling through the thoughts and transcriptions of the AI". The steps are the review's own
/// (ai/review_stage.dart): listening again with the careful speech model, comparing what the two heard, then the
/// thinking run - loading the model, reading the note, thinking it through, writing what it found. The list is
/// drawn whole from the start, in the order things really happen, so the steps can be seen coming; a stage the
/// review says wins over whatever run the note has, since the run is a later step.
///
/// Two kinds of heat, kept apart. WARMTH is state: a model at work is a fact, so the die's hatch, the column of
/// stipple and the shimmer say so on the phone and on the Mac alike. GLOW is measured: the rings and the pins light
/// only from the phone's own busy figure and temperature, which the engine samples with every report, and a phone
/// that gives none keeps them dark.
///
/// What differs: a step's id and state and the warmth are enums whose [Enum.name] is the web's word; [Step] and
/// [SceneInput] are immutable classes; the constants wear Dart's names ([holdMs] is `HOLD_MS`). A download is the
/// record lib/capture/refine.dart publishes. [pinsOf] asks the phone for its cores (`Platform.numberOfProcessors`)
/// where the page asked `navigator.hardwareConcurrency`.
library;

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../ai/backend.dart';
import '../ai/kinds.dart';
import '../ai/review_stage.dart';
import '../ai/runs.dart';
import '../ai/words.dart';

/// `StepId`; [name] is the web's word.
enum StepId { listen, load, read, think, write, done }

/// `StepState`; [name] is the web's word.
enum StepState { waiting, working, done, skipped }

/// One step of the list (`Step`).
@immutable
class Step {
  const Step({required this.id, required this.words, required this.state, this.detail});

  final StepId id;
  final String words;
  final StepState state;

  /// After the words, in the quiet ink: what the step found, or why it was skipped.
  final String? detail;

  @override
  bool operator ==(Object other) => other is Step && other.id == id && other.words == words && other.state == state && other.detail == detail;

  @override
  int get hashCode => Object.hash(id, words, state, detail);

  @override
  String toString() => 'Step(${id.name}, $words, ${state.name}, $detail)';
}

/// What the scene knows at one moment (`SceneInput`).
@immutable
class SceneInput {
  const SceneInput({this.stage, this.download, this.run, this.hasJob = true, this.compared, this.ended = false});

  /// The review's own stage before its run (listening again, comparing), or null.
  final ReviewStage? stage;

  /// The better voice model's download, while one is under way (capture/refine.dart).
  final ({int received, int total})? download;

  /// The note's run, going or ended; null before one has started, and for a run the scene ignores.
  final RunState? run;

  /// Whether a listen will happen at all: the recorder kept a recording.
  final bool hasJob;

  /// What Comparing said, once it has: kept after the stage clears, since the run replaces it.
  final String? compared;

  /// The review is over with no run to speak of: no thinking model, so only the words landed.
  final bool ended;
}

/// After an end, the scene holds the settle this long before it starts to leave: the die cools, the rings go back in
/// and the words dim over 600 ms, so the hold is long enough for that to be seen (400 was not; the review watched the
/// six ticks for under half a second). `HOLD_MS`.
const int holdMs = 900;

/// How long the fade out takes (`LEAVE_MS`).
const int leaveMs = 260;

/// How long the scene waits for a run after the stage clears before it takes the review as over (`GRACE_MS`).
const int graceMs = 1500;

/// How long the scene waits to see anything at all after opening before it leaves quietly (`OPEN_GRACE_MS`).
const int openGraceMs = 8000;

/// How often the haze may step, at most: one write a report, never more than this a second (`HAZE_HZ`).
const int hazeHz = 8;

/// The words' own share of the heat filter's bend (editor/marks/text_effects.dart `own`): the bend that still reads
/// as solid (`HAZE_OWN`).
const double hazeOwn = 0.3;

/// How many lines the pane holds at once (`PANE_LINES`).
const int paneLines = 24;

/// The words Comparing says when the careful model never spoke (`NOTHING_TO_COMPARE`).
const String nothingToCompare = 'Nothing to compare against.';

/// Where a run's phase sits in the order things happen; an ended run is placed by what it got to.
int _reached(RunState run) {
  switch (run.phase) {
    case RunPhase.queued:
      return 0;
    case RunPhase.loading:
      return 1;
    case RunPhase.prefill:
      return 2;
    case RunPhase.generating:
      return 3;
    case RunPhase.done:
      return 5;
    case RunPhase.stopped || RunPhase.failed:
      // Stopped or failed: nothing more ticks, so the steps stand where the evidence says it got to.
      if (run.lines.isNotEmpty || run.partial.isNotEmpty) return 4;
      if (run.thought.isNotEmpty || run.outputTokens != 0) return 3;
      if (run.promptTokensDone != 0) return 2;
      return 1;
  }
}

/// Whether the run's answer has begun: a thinking run is writing once anything follows its thought.
bool _answering(RunState run) => run.lines.isNotEmpty || run.partial.isNotEmpty;

/// The download's words, as notes/Notices.tsx `RefiningNotice` says them: change both together.
String downloadWords(({int received, int total}) download) => 'Getting the better voice model, ${megabytes(download.received)} of ${megabytes(download.total)} MB.';

/// `stepsOf`.
List<Step> stepsOf(SceneInput input) {
  final stage = input.stage;
  final download = input.download;
  final hasJob = input.hasJob;
  final compared = input.compared;
  final over = input.ended;
  // A stage wins: while the review says one, whatever run the note has is a later step, or an earlier ask's.
  final run = stage != null ? null : input.run;
  final kind = run?.kind ?? RunKind.review;
  final summary = kind != RunKind.review;
  final at = run != null ? _reached(run) : 0;
  final stopped = run != null && ended(run) && run.phase != RunPhase.done;
  final steps = <Step>[];
  StepState ticked(bool done) => done ? StepState.done : StepState.waiting;

  if (hasJob && !summary) {
    final skipped = compared == nothingToCompare;
    // Comparing is one frame, so it is this step's tick and its detail, not a line of its own.
    final done = compared != null || run != null || over;
    final listening = stage?.what == 'Listening again';
    steps.add(Step(
      id: StepId.listen,
      words: 'Listening again',
      state: skipped ? StepState.skipped : ticked(done),
      detail: download != null && listening ? downloadWords(download) : compared,
    ));
  }
  steps.add(Step(id: StepId.load, words: 'Loading the model', state: ticked(at >= 2 || over)));
  steps.add(Step(id: StepId.read, words: summary ? 'Reading the recording' : 'Reading the note', state: ticked(at >= 3 || over)));
  if (!summary) steps.add(Step(id: StepId.think, words: 'Thinking it through', state: ticked((run != null && at >= 3 && (_answering(run) || run.phase == RunPhase.done)) || over)));
  steps.add(Step(id: StepId.write, words: summary ? 'Writing the summary' : 'Writing what it found', state: ticked(at >= 5 || over)));
  steps.add(Step(id: StepId.done, words: 'Done', state: ticked(at >= 5 || over)));

  // The first step not done is the one working, unless the run stopped: then nothing is.
  if (!stopped) {
    final first = steps.indexWhere((step) => step.state == StepState.waiting);
    if (first >= 0) {
      final was = steps[first];
      steps[first] = Step(id: was.id, words: was.words, state: StepState.working, detail: was.detail);
    }
  }
  return steps;
}

/// The step at work now, or null once nothing is (`workingStep`).
StepId? workingStep(SceneInput input) {
  for (final step in stepsOf(input)) {
    if (step.state == StepState.working) return step.id;
  }
  return null;
}

/// The title: one sentence, in the strip's own words wherever it has them (ai/words.dart). `sceneTitle`.
String sceneTitle(SceneInput input) {
  final stage = input.stage;
  final download = input.download;
  final run = input.run;
  if (stage != null) {
    if (download != null) return downloadWords(download);
    final percent = stage.percent;
    return '${stage.what}${percent != null && percent > 0 ? ', $percent%' : ''}.';
  }
  if (run == null) return input.ended ? 'Done.' : 'Checking what was heard.';
  if (run.phase == RunPhase.generating) {
    final name = modelName(run.model);
    if (run.kind == RunKind.review) return '$name is ${_answering(run) ? 'writing what it found' : 'thinking it through'}.';
    return '${kindWords(run.kind).doing} with $name.';
  }
  return runSentence(run);
}

/// The line under the title (`sceneDetail`).
String sceneDetail(SceneInput input) {
  final stage = input.stage;
  final run = input.run;
  if (stage != null) return input.download != null ? 'Once, then it stays on the phone.' : stage.detail;
  if (run == null) return input.ended ? '' : 'The recording is saved.';
  switch (run.phase) {
    case RunPhase.loading:
      final spec = modelSpec(run.model);
      return spec != null ? '${gb(spec.bytes)} on this phone.' : '';
    case RunPhase.prefill:
      return 'The note and everything that was heard.';
    case RunPhase.generating:
      if (run.kind != RunKind.review) return '';
      return _answering(run) ? 'What it finds is checked against the note, then marked.' : 'Thinking it through out loud.';
    case RunPhase.queued || RunPhase.done || RunPhase.stopped || RunPhase.failed:
      return '';
  }
}

/// The hidden live line for a screen reader: the working step's words, or the end's sentence. No numbers.
/// `liveWords`.
String liveWords(SceneInput input) {
  for (final step in stepsOf(input)) {
    if (step.state == StepState.working) return '${step.words}.';
  }
  return sceneTitle(input);
}

final RegExp _numbers = RegExp(r', \d+%|, \d+ of \d+(?: MB)?| in \d+:\d\d');

/// The pieces of a title, its progress numbers apart, so they can be hidden from a screen reader that reads the
/// heading (`titlePieces`).
List<({String text, bool number})> titlePieces(String title) {
  // A split on a pattern that keeps what it matched, as JavaScript's does for a group: words, number, words, ...
  final split = <String>[];
  var from = 0;
  for (final match in _numbers.allMatches(title)) {
    split
      ..add(title.substring(from, match.start))
      ..add(match[0]!);
    from = match.end;
  }
  split.add(title.substring(from));
  final pieces = split.where((piece) => piece != '').toList();
  return [for (var i = 0; i < pieces.length; i += 1) (text: pieces[i], number: i.isOdd)];
}

/// `Warmth`; [name] is the web's word.
enum Warmth { cold, warm, hot }

/// State, not a reading: how alive the die is (`warmthOf`).
Warmth warmthOf(SceneInput input) {
  final run = input.run;
  if (input.ended) return Warmth.cold;
  if (input.stage != null || input.download != null) return Warmth.warm;
  if (run == null) return input.compared != null ? Warmth.warm : Warmth.cold;
  switch (run.phase) {
    case RunPhase.loading:
      return Warmth.warm;
    case RunPhase.prefill || RunPhase.generating:
      return Warmth.hot;
    case RunPhase.queued || RunPhase.done || RunPhase.stopped || RunPhase.failed:
      return Warmth.cold;
  }
}

double _clamp(double value) => math.min(1, math.max(0, value));

/// Measured: how brightly the rings glow, 0 to 1, from the phone's own readings. Nothing before a sample past loading
/// (loading's one sample is a new sampler's, and reads 0). Busy is the engine's share of the threads it runs on, so
/// six of eight cores at full tilt is full; heat, where the phone lets it be read, is the AI card's share; the blend
/// when both are there. An ended run has cooled. `glowOf`.
double glowOf(RunState? run) {
  final hardware = run?.hardware;
  if (run == null || hardware == null || ended(run) || run.phase == RunPhase.queued || run.phase == RunPhase.loading) return 0;
  final threads = hardware.threads;
  final held = math.min(6, math.max(2, hardware.cores));
  final over = threads != 0 ? threads : (held != 0 ? held : 1);
  final busy = _clamp(hardware.cpuPercent / (100 * over));
  final tempC = hardware.tempC;
  final heat = tempC != null ? heatShare(tempC) : null;
  return heat == null ? busy : 0.5 * busy + 0.5 * heat;
}

/// The glow as the ring it reaches, 0 to 5 (`glowStepOf`).
int glowStepOf(double glow) => (_clamp(glow) * 5 + 0.5).floor();

/// How many of the die's pins are lit: one per busy core, capped at the pins drawn (`litPinsOf`).
int litPinsOf(double cpuPercent, int pins) => math.min(pins, math.max(0, (cpuPercent / 100 + 0.5).floor()));

/// How many pins the die has: the phone's cores, capped at twelve so the die keeps its shape (`pinsOf`).
int pinsOf(int? cores) {
  var have = cores ?? 0;
  if (have == 0) have = Platform.numberOfProcessors;
  if (have == 0) have = 8;
  return math.max(2, math.min(12, have));
}
