/// A run of the model on a note, as the screen watches it: the one engine behind the More sheet's runs, a spoken
/// instruction and the review after a recording. A port of `src/app/ai/runs.ts`.
///
/// Matt: "more real time, more interactive, with UI updates, iconography and general feedback". So a run is not a
/// future that completes with a text a minute later; it is a state the app can draw at every report (which phase,
/// which model, how fast, the phone underneath) and, the part the editor lands, THE LINES AS THEY FINISH. The model
/// writes token by token and reports about every 120 ms with everything so far (ai/backend.dart); this module cuts
/// that at the last newline, so [RunState.lines] only ever grows by whole lines and [RunState.partial] is the one
/// under the pen. A line the model has finished does not change, which is what lets the editor put it in the note
/// the moment it arrives.
///
/// One model, one pass (Matt), and one run at a time: the phone has one set of cores and Rust queues generations
/// anyway, so a second run on another note waits here as `queued`, where the strip can say so, rather than in the
/// dark. A second run on the SAME note takes the first one's place: the newest ask is the one meant.
///
/// Everything here is module state on purpose: a run outlives the screen that started it, and a note opened while
/// its run is on finds it going. The latest run of each note stays readable after it ends, until the strip is
/// dismissed or the next run replaces it, so "Formatted by Qwen 4B in 0:42" is there to read when the person looks
/// up.
///
/// What differs: [RunState] is an immutable class, changed by [RunState.copyWith]; a phase, a placement and a batch
/// are an enum and a class with the web's words. The hooks `useRun` and `useAnyRunning` answer a [ValueListenable]
/// that follows the runs while anything listens to it. The web's tests replaced `generate` by mocking its module;
/// here [simulateRuns] is that seam as well as the browser's scripted model. A listener that stops listening from
/// inside its own call is allowed, as it was in a JavaScript `Set`.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'backend.dart';
import 'kinds.dart';
import 'log.dart';
import 'support/failure.dart';
import 'support/watched.dart';

/// Where a run is (`RunPhase`); [name] is the web's word.
enum RunPhase { queued, loading, prefill, generating, done, stopped, failed }

/// The span of the note a run works on, as offsets into the body when it started: the words after the front matter
/// (`RunScope`).
@immutable
class RunScope {
  const RunScope({required this.from, required this.to});

  final int from;
  final int to;

  @override
  bool operator ==(Object other) => other is RunScope && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'RunScope($from, $to)';
}

/// Where a run's lines go: over the words in its scope, above the note, or under it (`Placement`; ai/start.dart
/// `placementOf`).
enum Placement { replace, prepend, append }

/// One generation of a press of Fill (`RunBatch`): the press's id, the blanks answered before this generation, the
/// blanks it asks, and the press's whole count.
@immutable
class RunBatch {
  const RunBatch({required this.id, required this.before, required this.asked, required this.total});

  final String id;
  final int before;
  final int asked;
  final int total;

  @override
  bool operator ==(Object other) => other is RunBatch && other.id == id && other.before == before && other.asked == asked && other.total == total;

  @override
  int get hashCode => Object.hash(id, before, asked, total);

  @override
  String toString() => 'RunBatch($id, before $before, asked $asked, total $total)';
}

/// What a run is asked (`RunRequest`).
@immutable
class RunRequest {
  const RunRequest({
    required this.noteId,
    required this.kind,
    this.instruction,
    required this.model,
    required this.system,
    required this.prompt,
    this.context,
    required this.maxTokens,
    this.temperature,
    this.think,
    this.thinkBudget,
    this.restore,
    this.hash,
    this.scope,
    this.placement,
    this.batch,
  });

  final String noteId;
  final RunKind kind;

  /// The words the person gave, for a kind that takes some.
  final String? instruction;

  /// The model to run, already one that is on the phone (ai/available.dart `modelFor`).
  final String model;
  final String system;

  /// The words it works on, links and tables already swapped for tokens it can copy (format/links.dart, tables.dart).
  final String prompt;
  final String? context;
  final int maxTokens;

  /// 0.3 when not said.
  final double? temperature;
  final bool? think;
  final int? thinkBudget;

  /// The model's text so far as the note's words, the links and tables put back, and, with `isFinal`, the tidy-up
  /// once it has finished. The identity when absent.
  final String Function(String text, bool isFinal)? restore;

  /// The hash of the body it was written from (format/pipeline.dart `noteHash`), for what is kept.
  final int? hash;
  final RunScope? scope;

  /// Where its lines land when the kind's own rule is not the one meant: a recording's summary lands over its scope.
  final Placement? placement;

  /// One generation of a press of Fill (ai/fills/queue.dart). The press writes its one line in the log, so a run with
  /// a batch writes none of its own (docs/DESIGN.md §145, 7.3).
  final RunBatch? batch;

  /// This request with some of it changed: a test's, and a caller's that asks the same thing of another note.
  RunRequest copyWith({
    String? noteId,
    RunKind? kind,
    String? instruction,
    String? model,
    String? system,
    String? prompt,
    String? context,
    int? maxTokens,
    double? temperature,
    bool? think,
    int? thinkBudget,
    String Function(String text, bool isFinal)? restore,
    int? hash,
    RunScope? scope,
    Placement? placement,
    RunBatch? batch,
  }) =>
      RunRequest(
        noteId: noteId ?? this.noteId,
        kind: kind ?? this.kind,
        instruction: instruction ?? this.instruction,
        model: model ?? this.model,
        system: system ?? this.system,
        prompt: prompt ?? this.prompt,
        context: context ?? this.context,
        maxTokens: maxTokens ?? this.maxTokens,
        temperature: temperature ?? this.temperature,
        think: think ?? this.think,
        thinkBudget: thinkBudget ?? this.thinkBudget,
        restore: restore ?? this.restore,
        hash: hash ?? this.hash,
        scope: scope ?? this.scope,
        placement: placement ?? this.placement,
        batch: batch ?? this.batch,
      );
}

const Object _keep = Object();

/// A run as it is now (`RunState`).
@immutable
class RunState {
  const RunState({
    required this.id,
    required this.noteId,
    required this.kind,
    required this.instruction,
    required this.model,
    required this.scope,
    this.placement,
    required this.phase,
    required this.lines,
    required this.partial,
    required this.thought,
    required this.text,
    required this.promptTokens,
    required this.promptTokensDone,
    required this.outputTokens,
    required this.maxTokens,
    required this.tokensPerSecond,
    required this.elapsedMs,
    required this.hardware,
    required this.truncated,
    required this.message,
    required this.startedAt,
    required this.endedAt,
    required this.hash,
    this.batch,
    this.said,
  });

  final String id;
  final String noteId;
  final RunKind kind;
  final String? instruction;
  final String model;
  final RunScope? scope;

  /// Where its lines land when not by its kind's rule (a recording's summary): null for the kind's own.
  final Placement? placement;
  final RunPhase phase;

  /// The lines the model has finished, as the note's words. Only ever grows while it runs.
  final List<String> lines;

  /// The line under its pen, not finished.
  final String partial;

  /// Its reasoning so far, for a run asked to think; empty otherwise.
  final String thought;

  /// The whole answer once it is done, restored and tidied; null until then, and after a stop or a failure.
  final String? text;
  final int promptTokens;
  final int promptTokensDone;
  final int outputTokens;

  /// The most it may write: what the bar is measured against.
  final int maxTokens;
  final double tokensPerSecond;
  final int elapsedMs;
  final Hardware? hardware;

  /// Stopped by the budget rather than by finishing.
  final bool truncated;

  /// Why it failed, for a run that did.
  final String? message;

  /// When it was asked for, in ms since the epoch.
  final int startedAt;
  final int? endedAt;
  final int? hash;

  /// A press of Fill's generation, as its request said.
  final RunBatch? batch;

  /// What the strip says once it has ended, when the one who ran it knows better than the run: a press's whole
  /// count.
  final String? said;

  /// This state with some of it changed. The fields that may be null are taken as given when given, null included.
  RunState copyWith({
    String? id,
    String? noteId,
    RunKind? kind,
    Object? instruction = _keep,
    String? model,
    Object? scope = _keep,
    Object? placement = _keep,
    RunPhase? phase,
    List<String>? lines,
    String? partial,
    String? thought,
    Object? text = _keep,
    int? promptTokens,
    int? promptTokensDone,
    int? outputTokens,
    int? maxTokens,
    double? tokensPerSecond,
    int? elapsedMs,
    Object? hardware = _keep,
    bool? truncated,
    Object? message = _keep,
    int? startedAt,
    Object? endedAt = _keep,
    Object? hash = _keep,
    Object? batch = _keep,
    Object? said = _keep,
  }) =>
      RunState(
        id: id ?? this.id,
        noteId: noteId ?? this.noteId,
        kind: kind ?? this.kind,
        instruction: identical(instruction, _keep) ? this.instruction : instruction as String?,
        model: model ?? this.model,
        scope: identical(scope, _keep) ? this.scope : scope as RunScope?,
        placement: identical(placement, _keep) ? this.placement : placement as Placement?,
        phase: phase ?? this.phase,
        lines: lines ?? this.lines,
        partial: partial ?? this.partial,
        thought: thought ?? this.thought,
        text: identical(text, _keep) ? this.text : text as String?,
        promptTokens: promptTokens ?? this.promptTokens,
        promptTokensDone: promptTokensDone ?? this.promptTokensDone,
        outputTokens: outputTokens ?? this.outputTokens,
        maxTokens: maxTokens ?? this.maxTokens,
        tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
        elapsedMs: elapsedMs ?? this.elapsedMs,
        hardware: identical(hardware, _keep) ? this.hardware : hardware as Hardware?,
        truncated: truncated ?? this.truncated,
        message: identical(message, _keep) ? this.message : message as String?,
        startedAt: startedAt ?? this.startedAt,
        endedAt: identical(endedAt, _keep) ? this.endedAt : endedAt as int?,
        hash: identical(hash, _keep) ? this.hash : hash as int?,
        batch: identical(batch, _keep) ? this.batch : batch as RunBatch?,
        said: identical(said, _keep) ? this.said : said as String?,
      );

  @override
  String toString() => 'RunState($id, $noteId, ${kind.id}, ${phase.name}, ${lines.length} lines)';
}

/// A run in hand (`RunHandle`).
class RunHandle {
  const RunHandle({required this.id, required this.done, required this.cancel});

  final String id;

  /// Completes with the run's last state, however it ended. Never fails.
  final Future<RunState> done;
  final void Function() cancel;
}

class _Entry {
  _Entry(this.state, this.request);

  RunState state;
  final RunRequest request;

  /// Stops the generation, once one is going.
  void Function()? stop;
  bool stopped = false;
  final Completer<RunState> completer = Completer<RunState>();

  Future<RunState> get done => completer.future;
}

/// What hears every state of every run (`Listener`).
typedef RunListener = void Function(RunState run);

final Set<RunListener> _listeners = {};

/// The run the model is on, and the ones waiting for it, in order.
_Entry? _active;
final List<_Entry> _waiting = [];

/// The latest run of each note, going or ended, until it is dismissed or the next one replaces it.
final Map<String, RunState> _latest = {};
int _count = 0;

/// The model played by a script, for a browser trying a flow (ai/review_simulation.dart) and for a test; null for
/// the real one.
Run Function(RunOptions options)? _simulator;

/// Puts [fn] in the model's place, or the model back with null (`simulateRuns`).
void simulateRuns(Run Function(RunOptions options)? fn) {
  _simulator = fn;
}

/// [listener] at every state of every run; answers the way to stop (`subscribeRuns`).
VoidCallback subscribeRuns(RunListener listener) {
  _listeners.add(listener);
  return () => _listeners.remove(listener);
}

/// Whether a run is over, however it ended (`ended`).
bool ended(RunState run) => run.phase == RunPhase.done || run.phase == RunPhase.stopped || run.phase == RunPhase.failed;

int _now() => DateTime.now().millisecondsSinceEpoch;

void _tell(RunState state) {
  for (final listener in [..._listeners]) {
    listener(state);
  }
}

void _publish(_Entry entry) {
  _latest[entry.state.noteId] = entry.state;
  _tell(entry.state);
}

void _set(_Entry entry, RunState next) {
  entry.state = next;
  _publish(entry);
}

/// The text cut at its last newline: the lines that are finished, and the rest (`splitLines`). A model writes a
/// line's last word and then its newline in one or two reports, so a line is only "finished" once the newline is
/// there.
({List<String> lines, String partial}) splitLines(String text) {
  final cut = text.lastIndexOf('\n');
  if (cut < 0) return (lines: <String>[], partial: text);
  return (lines: text.substring(0, cut).split('\n'), partial: text.substring(cut + 1));
}

final RegExp _thinkOpen = RegExp(r'^\s*<think>\s*');
final RegExp _answerLead = RegExp(r'^[ \t]*\n+');
final RegExp _edges = RegExp(r'^\s+|\s+$');
const String _thinkClose = '</think>';

/// A reasoning run's text as its thought and its answer, the answer's own newlines kept (`splitThinking`): the
/// answer is never trimmed, since a trimmed answer never ends in the newline that says its last line is finished.
({String thought, String answer}) splitThinking(String text, bool thinking) {
  if (!thinking) return (thought: '', answer: text);
  final body = text.replaceFirst(_thinkOpen, '');
  final end = body.indexOf(_thinkClose);
  if (end < 0) return (thought: body.replaceAll(_edges, ''), answer: '');
  return (thought: body.substring(0, end).replaceAll(_edges, ''), answer: body.substring(end + _thinkClose.length).replaceFirst(_answerLead, ''));
}

final RegExp _trailingNewlines = RegExp(r'\n+$');

/// Every line of a finished text, the trailing newline not counted as an empty one (`allLines`).
List<String> allLines(String text) {
  final trimmed = text.replaceFirst(_trailingNewlines, '');
  return trimmed.isNotEmpty ? trimmed.split('\n') : <String>[];
}

/// Starts a run, or queues it behind the one going (`startRun`).
RunHandle startRun(RunRequest request) {
  final id = 'run-${_now().toRadixString(36)}-${_count += 1}';
  final state = RunState(
    id: id,
    noteId: request.noteId,
    kind: request.kind,
    instruction: request.instruction,
    model: request.model,
    scope: request.scope,
    placement: request.placement,
    phase: RunPhase.queued,
    lines: const [],
    partial: '',
    thought: '',
    text: null,
    promptTokens: 0,
    promptTokensDone: 0,
    outputTokens: 0,
    maxTokens: request.maxTokens,
    tokensPerSecond: 0,
    elapsedMs: 0,
    hardware: null,
    truncated: false,
    message: null,
    startedAt: _now(),
    endedAt: null,
    hash: request.hash,
    batch: request.batch,
  );
  final entry = _Entry(state, request);
  // The newest ask for a note is the one meant: an earlier one on the same note ends first.
  _stopNote(request.noteId);
  _waiting.add(entry);
  _publish(entry);
  _pump();
  return RunHandle(id: id, done: entry.done, cancel: () => _stopEntry(entry));
}

/// Stops a note's run, going or waiting; completes once it has ended (`cancelRun`).
Future<void> cancelRun(String noteId) {
  final entries = [..._waiting, ?_active].where((e) => e.state.noteId == noteId).toList();
  _stopNote(noteId);
  return Future.wait([for (final e in entries) e.done]).then((_) {});
}

void _stopNote(String noteId) {
  for (final entry in [..._waiting]) {
    if (entry.state.noteId == noteId) _stopEntry(entry);
  }
  final active = _active;
  if (active != null && active.state.noteId == noteId) _stopEntry(active);
}

void _stopEntry(_Entry entry) {
  if (entry.stopped || ended(entry.state)) return;
  entry.stopped = true;
  if (identical(entry, _active)) {
    // The generation answers "cancelled", and the run ends there.
    entry.stop?.call();
    return;
  }
  _waiting.remove(entry);
  _end(entry, RunPhase.stopped, null, null);
}

void _pump() {
  while (_active == null) {
    if (_waiting.isEmpty) return;
    final next = _waiting.removeAt(0);
    if (next.stopped) continue;
    _active = next;
    unawaited(_execute(next));
  }
}

Future<void> _execute(_Entry entry) async {
  _set(entry, entry.state.copyWith(phase: RunPhase.loading));
  final request = entry.request;
  final run = (_simulator ?? generate)(RunOptions(
    model: request.model,
    system: request.system,
    context: request.context,
    prompt: request.prompt,
    maxTokens: request.maxTokens,
    temperature: request.temperature ?? 0.3,
    think: request.think,
    thinkBudget: request.thinkBudget,
    onProgress: (progress) => _onProgress(entry, progress),
  ));
  entry.stop = run.cancel;
  // Stopped between being queued and started: the flag was raised, and the generation has only just been asked for.
  if (entry.stopped) run.cancel();
  try {
    final output = await run.done;
    _end(entry, RunPhase.done, null, output);
  } catch (failure) {
    final message = failureText(failure);
    _end(entry, message == 'cancelled' ? RunPhase.stopped : RunPhase.failed, message == 'cancelled' ? null : message, null);
  }
}

String _same(String text, bool isFinal) => text;

void _onProgress(_Entry entry, Progress progress) {
  if (entry.stopped || ended(entry.state)) return;
  // The end comes with the output, not the last report.
  final RunPhase phase;
  switch (progress.phase) {
    case Phase.done || Phase.error || Phase.cancelled:
      return;
    case Phase.loading:
      phase = RunPhase.loading;
    case Phase.prefill:
      phase = RunPhase.prefill;
    case Phase.generating:
      phase = RunPhase.generating;
  }
  final parted = splitThinking(progress.partial, progress.thinking ?? false);
  final restore = entry.request.restore ?? _same;
  final cut = splitLines(restore(parted.answer, false));
  _set(
    entry,
    entry.state.copyWith(
      phase: phase,
      lines: List<String>.unmodifiable(cut.lines),
      partial: cut.partial,
      thought: parted.thought,
      promptTokens: progress.promptTokens,
      promptTokensDone: progress.promptTokensDone,
      outputTokens: progress.outputTokens,
      tokensPerSecond: progress.tokensPerSecond,
      elapsedMs: progress.elapsedMs,
      hardware: progress.hardware,
    ),
  );
}

void _end(_Entry entry, RunPhase phase, String? message, Output? output) {
  if (ended(entry.state)) return;
  final endedAt = _now();
  var next = entry.state.copyWith(phase: phase, message: message, endedAt: endedAt, elapsedMs: output?.ms ?? math.max(entry.state.elapsedMs, endedAt - entry.state.startedAt));
  if (output != null) {
    final parted = splitThinking(output.text, output.thinking ?? false);
    final restore = entry.request.restore ?? _same;
    final text = restore(parted.answer, true);
    next = next.copyWith(
      text: text,
      lines: List<String>.unmodifiable(allLines(text)),
      partial: '',
      thought: parted.thought.isNotEmpty ? parted.thought : entry.state.thought,
      outputTokens: output.outputTokens,
      promptTokens: output.promptTokens,
      promptTokensDone: output.promptTokens,
      tokensPerSecond: output.tokensPerSecond,
      truncated: output.truncated,
    );
  }
  _set(entry, next);
  final state = entry.state;
  // A press of Fill writes one line for all its generations (ai/fills/queue.dart).
  if (entry.request.batch == null) {
    recordRun(RunRecord(
      id: state.id,
      noteId: state.noteId,
      kind: state.kind,
      instruction: state.instruction,
      model: state.model,
      at: state.startedAt,
      ms: state.elapsedMs,
      outputTokens: state.outputTokens,
      outcome: phase == RunPhase.done ? RunOutcome.done : (phase == RunPhase.stopped ? RunOutcome.stopped : RunOutcome.failed),
      message: message,
      truncated: state.truncated,
    ));
  }
  entry.completer.complete(state);
  if (identical(entry, _active)) {
    _active = null;
    _pump();
    // The ended state was published while this was still the active run: said again now nothing is, so a listener
    // asking whether the model is on any note (`useAnyRunning`) hears the answer change.
    if (_active == null) _tell(state);
  }
}

/// What the strip says for a run that has ended, when its caller knows the whole of it: a press of Fill counts the
/// blanks every generation filled (`sayRun`). Nothing if the note's latest run is another.
void sayRun(String noteId, String runId, String said) {
  final run = _latest[noteId];
  if (run == null || run.id != runId) return;
  final next = run.copyWith(said: said);
  _latest[noteId] = next;
  _tell(next);
}

/// The latest run of a note, going or ended, or null (`runFor`).
RunState? runFor(String noteId) => _latest[noteId];

/// Whether a run is going, or waiting to, for this note (`isRunning`).
bool isRunning(String noteId) => (_active != null && _active!.state.noteId == noteId) || _waiting.any((e) => e.state.noteId == noteId);

/// Whether the model is on any note at all (`anyRunning`).
bool anyRunning() => _active != null || _waiting.isNotEmpty;

/// An ended run put away: the strip has nothing more to say about it (`dismissRun`).
void dismissRun(String noteId) {
  final run = _latest[noteId];
  if (run == null || !ended(run)) return;
  _latest.remove(noteId);
  _tell(run);
}

/// Nothing going, nothing remembered: for a reset, and for tests (`forgetAllRuns`).
void forgetAllRuns() {
  for (final entry in [..._waiting]) {
    _stopEntry(entry);
  }
  final active = _active;
  if (active != null) _stopEntry(active);
  _latest.clear();
}

VoidCallback _subscribeChanges(VoidCallback listener) => subscribeRuns((_) => listener());

/// A note's latest run as the screen sees it, told on every report (`useRun`).
ValueListenable<RunState?> useRun(String noteId) => Watched<RunState?>(() => _latest[noteId], _subscribeChanges);

/// Whether the model is on any note, live: for a surface that must not start a run of its own beside a real one
/// (`useAnyRunning`).
ValueListenable<bool> useAnyRunning() => Watched<bool>(anyRunning, _subscribeChanges);
