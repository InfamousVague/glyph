/// The fills' queue: every press of Fill, run to its end and landed, whether its note stays open or not
/// (docs/DESIGN.md §145, 4.4 and 6.3). A port of `src/app/ai/fills/queue.ts`.
///
/// A module of the app, beside the summaries' queue, and not owned by the note screen, so closing a note changes
/// nothing about a fill already pressed: its answers land in the closed note the way a write-up does, read fresh and
/// written with the revision it was read at, and one that cannot be written is kept for the session and lands when
/// the note is next opened. With the app in view, a toast says so, with Open.
///
/// A press is a batch: its note, its blanks (each known by its question and its order among blanks with that
/// question, and while the note is open by its range too), the model, and an id. It is split into generations by the
/// model's rung and the room (ai/fills/message.dart), which run in order through the one engine (ai/runs.dart), so the
/// strip, Stop and the queue behind another note all work as for any run. A generation's answers are checked
/// (ai/fills/shape.dart) and land together in one change, the first with the AI's signature. A press is one line in
/// the log with one Undo, however many generations it took. A fill never stops another kind of run: it waits while
/// Format or Summarize runs on its note, and one of those asked while fills run is the newer ask, which stops them.
///
/// A live blank (ai/fills/web.dart) is looked up first: offline it waits, "Waiting for a connection", and goes on by
/// itself once the phone is online, never started but by the press. Local only holds it.
///
/// Only while the app runs: the queue is in memory, as every run is. Nothing is left half written, since each
/// generation lands in one change or not at all.
///
/// What differs:
/// - The shapes. A [FillTarget], a [FillStatus], a [FillOutcome] and a press ([FillBatch], which [pressToast] reads)
///   are classes; a status's phase, why a lookup is paused and why a blank did not fill are enums with the web's
///   words. The kit's `ToastOptions` is a [FillToast], its time in milliseconds as on the page.
/// - What the page reached for itself is handed to [startFills], each with a default that does nothing, since none of
///   it is under lib/ai: the store's `getNote` and `updateNote` (core/store.ts), the sync engine's `syncNow`
///   (core/sync/engine.ts), `navigator.onLine`, the window's `online` event and `document.visibilityState`. With none
///   of them given, a closed note is never read or written, the phone is taken to be online and the app in view.
/// - `externalStore` is a count a listener follows: [subscribeFills] as on the page, and [fillsVersion] for a widget.
/// - The once-a-device flag `glyph-fill-told` is kept through core/stored.dart ([Stored.flag], the word `on` under the
///   same key, as `deviceFlag` wrote it) rather than through core/preferences.dart's `DeviceFlag`, so a reset of the
///   device's storage, and a test's fresh one, clears it as `localStorage.clear()` did.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/blanks.dart';
import '../../core/days.dart';
import '../../core/fill_facts.dart';
import '../../core/item_syntax.dart' show jsTrim;
import '../../core/note.dart';
import '../../core/note_text.dart' show noteTitle;
import '../../core/preferences.dart';
import '../../core/stored.dart';
import '../backend.dart';
import '../kinds.dart';
import '../log.dart';
import '../runs.dart';
import '../support/failure.dart';
import '../words.dart';
import 'edits.dart';
import 'lane.dart';
import 'message.dart';
import 'prompts.dart';
import 'read.dart';
import 'shape.dart';
import 'source.dart';
import 'web.dart';

/// What a toast says (`ToastOptions`, the kit's): its words, how long it stands, and its one action.
@immutable
class FillToast {
  const FillToast({required this.message, this.duration, this.action});

  final String message;

  /// How long it stands, in milliseconds; the kit's own time where null.
  final int? duration;
  final FillToastAction? action;

  @override
  String toString() => 'FillToast($message${duration == null ? '' : ', $duration ms'}${action == null ? '' : ', ${action!.label}'})';
}

/// A toast's action: its word, and what pressing it does.
@immutable
class FillToastAction {
  const FillToastAction({required this.label, required this.onPress});

  final String label;
  final VoidCallback onPress;
}

/// An answer asked again: the whole mark as it stands, and its words, which the model is told it is not.
@immutable
class FillAgain {
  const FillAgain({required this.mark, required this.words});

  final String mark;
  final String words;
}

/// A blank a press asks, as the editor found it (`FillTarget`).
class FillTarget {
  const FillTarget({required this.key, required this.question, required this.order, this.again, this.anyway = false});

  /// Its question and its order among blanks with that question: [blankKey].
  final String key;
  final String question;
  final int order;

  /// An answer asked again: the whole mark as it stands, and its words, which the model is told it is not.
  final FillAgain? again;

  /// Ask the model anyway: a blank the app refused, asked of the model from memory, never looked up.
  final bool anyway;

  @override
  String toString() => 'FillTarget($question, $order${again == null ? '' : ', again'}${anyway ? ', anyway' : ''})';
}

/// Where a target is: the blank's identity, joined.
String blankKey(String question, int order) => '$question\u0000$order';

/// What an open note's editor gives the queue, so it is the one writer of an open note (the editor's fill landing).
abstract interface class FillHost {
  String text();

  /// A target's range as the editor has tracked it since the press, or null.
  ({int from, int to})? rangeOf(String key);

  /// Tracks the targets' ranges through every edit from now.
  void track(List<({String key, int from, int to})> targets);

  /// Lands the changes in one transaction, signed when [sign] holds one; answers the note after, or null.
  String? land(List<TextChange> changes, TextChange? sign);
}

/// Where a blank a press took is; each name is the page's own word.
enum FillPhase { waiting, filling, looking, paused }

/// Why a lookup is paused: no connection, or Local only.
enum PausedWhy {
  offline('offline'),
  localOnly('local-only');

  const PausedWhy(this.id);

  /// The page's word for it.
  final String id;
}

/// What is going on with a blank a press took (`FillStatus`).
@immutable
class FillStatus {
  const FillStatus.waiting()
      : phase = FillPhase.waiting,
        runId = null,
        why = null;

  const FillStatus.filling({required String this.runId})
      : phase = FillPhase.filling,
        why = null;

  const FillStatus.looking()
      : phase = FillPhase.looking,
        runId = null,
        why = null;

  const FillStatus.paused({required PausedWhy this.why})
      : phase = FillPhase.paused,
        runId = null;

  final FillPhase phase;

  /// The run that is filling it, while it is.
  final String? runId;

  /// Why it is paused, while it is.
  final PausedWhy? why;

  @override
  bool operator ==(Object other) => other is FillStatus && other.phase == phase && other.runId == runId && other.why == why;

  @override
  int get hashCode => Object.hash(phase, runId, why);

  @override
  String toString() => 'FillStatus(${phase.name}${runId == null ? '' : ', $runId'}${why == null ? '' : ', ${why!.id}'})';
}

/// Why a blank did not fill: the page's `'unknown' | 'none' | 'didnt-fit' | 'nothing'`, each as its [id].
enum FillWhy {
  unknown('unknown'),
  none('none'),
  didntFit('didnt-fit'),
  nothing('nothing');

  const FillWhy(this.id);

  /// The page's word for it.
  final String id;
}

/// What came of a blank that did not fill, kept for the session and drawn after it (6.7) (`FillOutcome`).
@immutable
class FillOutcome {
  const FillOutcome({required this.why, this.words, required this.model});

  final FillWhy why;

  /// The source's own sentence, for a lookup that found nothing.
  final String? words;
  final String model;

  @override
  bool operator ==(Object other) => other is FillOutcome && other.why == why && other.words == words && other.model == model;

  @override
  int get hashCode => Object.hash(why, words, model);

  @override
  String toString() => 'FillOutcome(${why.id}, $words, $model)';
}

class _Target extends FillTarget {
  _Target(FillTarget from) : super(key: from.key, question: from.question, order: from.order, again: from.again, anyway: from.anyway);

  /// Looked up on the web first, by this plan.
  LookupPlan? plan;
}

/// What did not fill in a press, counted.
class FillCounts {
  FillCounts({this.unknown = 0, this.none = 0, this.didntFit = 0, this.nothing = 0, this.changed = 0});

  int unknown;
  int none;
  int didntFit;
  int nothing;
  int changed;
}

/// How a press was stopped: by Stop, or by a newer ask of another kind for its note ([by]).
@immutable
class FillStopped {
  /// The page's `'stopped'`.
  const FillStopped() : by = null;

  /// The page's `{ by }`: the kind of run that took the note.
  const FillStopped.byKind(RunKind this.by);

  final RunKind? by;
}

/// A press (`Batch`). [pressToast] reads its counts; the rest is the queue's own.
class FillBatch {
  FillBatch({
    this.id = '',
    required this.noteId,
    this.model = '',
    List<FillTarget> targets = const [],
    this.landed = 0,
    FillCounts? counts,
    this.stopped,
    this.failed,
    this.closedTitle,
    this.parked = 0,
  })  : targets = [for (final target in targets) _Target(target)],
        counts = counts ?? FillCounts();

  final String id;
  final String noteId;
  final String model;
  final List<FillTarget> targets;

  /// The note before its first landing, for Undo; null until then.
  String? before;
  String? after;
  int landed;
  int? firstStart;
  int lastEnd = 0;
  String? lastRunId;
  int outputTokens = 0;
  final FillCounts counts;
  FillStopped? stopped;
  String? failed;

  /// The note's title when it landed closed, for the toast.
  String? closedTitle;

  /// Web jobs still waiting for a connection.
  int parked;

  List<_Target> get _targets => targets.cast<_Target>();
}

// ---- state ----------------------------------------------------------------------------------------------------------

final Map<String, FillHost> _hosts = {};
final Map<String, Map<String, FillStatus>> _statuses = {};
final Map<String, Map<String, FillOutcome>> _outcomes = {};

/// Answers a closed note could not take, kept to land when it is next opened.
final Map<String, List<({FillBatch batch, List<_Ready> ready})>> _pending = {};
final List<FillBatch> _batches = [];
final List<({FillBatch batch, _Target target})> _parked = [];
bool _working = false;
int _count = 0;

/// Bumped on every change a screen draws from.
final ValueNotifier<int> _version = ValueNotifier<int>(0);
void _bump() => _version.value += 1;

void Function(FillToast options)? _toaster;
void Function(String id)? _opener;
FillFetcher _fetcher = pageFetch;
DateTime Function() _now = DateTime.now;

Future<Note?> _noNote(String id) async => null;
Future<Note> _noWrite(String id, String body, int expectedRevision) => Future<Note>.error(StateError('No library to write to.'));
Future<void> _noSync() async {}
bool _yes() => true;

/// The store's `getNote` and `updateNote`, the sync engine's `syncNow`, `navigator.onLine` and whether the app is in
/// view (`document.visibilityState === 'visible'`): [startFills] gives them.
Future<Note?> Function(String id) _getNote = _noNote;
Future<Note> Function(String id, String body, int expectedRevision) _updateNote = _noWrite;
Future<void> Function() _syncNow = _noSync;
bool Function() _onLine = _yes;
bool Function() _visible = _yes;

int _ms() => DateTime.now().millisecondsSinceEpoch;

/// Follows every change to what the queue knows; answers the way to stop.
VoidCallback subscribeFills(VoidCallback listener) {
  _version.addListener(listener);
  return () => _version.removeListener(listener);
}

/// The count [subscribeFills] follows, for a widget that listens: it changes whenever a status or an outcome does.
ValueListenable<int> get fillsVersion => _version;

/// A blank's status, while a press has it.
FillStatus? fillStatus(String noteId, String key) => _statuses[noteId]?[key];

/// What came of a blank that did not fill, this session.
FillOutcome? fillOutcome(String noteId, String key) => _outcomes[noteId]?[key];

void _setStatus(String noteId, String key, FillStatus? status) {
  final mine = _statuses[noteId] ?? <String, FillStatus>{};
  if (status != null) {
    mine[key] = status;
  } else {
    mine.remove(key);
  }
  _statuses[noteId] = mine;
  _bump();
}

void _setOutcome(String noteId, String key, FillOutcome? outcome) {
  final mine = _outcomes[noteId] ?? <String, FillOutcome>{};
  if (outcome != null) {
    mine[key] = outcome;
  } else {
    mine.remove(key);
  }
  _outcomes[noteId] = mine;
  _bump();
}

/// Wire the queue to the app: how it says what happened, how Open opens a note. Called once, by whoever wires the app
/// (the page's shell/useHousekeeping.ts); answers the way to stop.
///
/// The rest is what the page reached for itself, and each has a default that does nothing:
/// - [getNote] and [updateNote] are the store's (core/store.ts): a note whole, or null for none, and a write that
///   fails unless the note is still at [updateNote]'s revision, with a failure whose words say `changed`, `deleted`
///   or `revision` for a note that has moved on. Without them a closed note is never read, and its answers are kept
///   for the next time it is opened.
/// - [syncNow] is the sync engine's (core/sync/engine.ts), asked before a closed note is read and after it is
///   written. It may fail; nothing is made of that.
/// - [onLine] is `navigator.onLine`: false keeps parked lookups parked. True when not given.
/// - [visible] is whether the app is in view (`document.visibilityState === 'visible'`): a note filled while closed
///   says so with Open only then, and parked lookups are tried each minute only then. True when not given.
/// - [onOnline] calls its listener when a connection comes back (the window's `online` event) and answers the way to
///   stop; the parked lookups go on then.
VoidCallback startFills(
  void Function(FillToast options) toast,
  void Function(String id) open, {
  Future<Note?> Function(String id)? getNote,
  Future<Note> Function(String id, String body, int expectedRevision)? updateNote,
  Future<void> Function()? syncNow,
  bool Function()? onLine,
  bool Function()? visible,
  VoidCallback Function(VoidCallback listener)? onOnline,
}) {
  _toaster = toast;
  _opener = open;
  _getNote = getNote ?? _noNote;
  _updateNote = updateNote ?? _noWrite;
  _syncNow = syncNow ?? _noSync;
  _onLine = onLine ?? _yes;
  _visible = visible ?? _yes;
  void online() => resumeParked();
  final offOnline = onOnline?.call(online);
  final timer = Timer.periodic(const Duration(milliseconds: 60000), (_) {
    if (_parked.isNotEmpty && _visible()) resumeParked();
  });
  return () {
    offOnline?.call();
    timer.cancel();
    _toaster = null;
    _opener = null;
    _getNote = _noNote;
    _updateNote = _noWrite;
    _syncNow = _noSync;
    _onLine = _yes;
    _visible = _yes;
  };
}

/// For tests: the network and the clock the queue uses.
void setFillWorld({FillFetcher? fetch, DateTime Function()? now}) {
  if (fetch != null) _fetcher = fetch;
  if (now != null) _now = now;
}

/// Nothing going, nothing remembered: for a reset, and for tests.
void forgetFills() {
  _batches.clear();
  _parked.clear();
  _statuses.clear();
  _outcomes.clear();
  _pending.clear();
  _working = false;
  _bump();
}

/// Whether this device may look live blanks up now.
Lookups lookupsHere() {
  final prefs = preferences.value;
  if (prefs.localOnly) return Lookups.localOnly;
  return prefs.lookUpBlanks ? Lookups.on : Lookups.off;
}

/// A note open in its editor: its answers land through it, in one transaction each, and anything kept for it while it
/// was closed lands now. Given null as the note is left.
void openForFills(String noteId, FillHost? host) {
  if (host == null) {
    _hosts.remove(noteId);
    return;
  }
  _hosts[noteId] = host;
  final kept = _pending[noteId];
  if (kept == null || kept.isEmpty) return;
  _pending.remove(noteId);
  for (final (:batch, :ready) in kept) {
    _landOpen(batch, host, ready);
    _finishBatch(batch);
  }
}

// ---- a press --------------------------------------------------------------------------------------------------------

final RegExp _fromTheWeb = RegExp(r'\bfrom (?:Open-Meteo|Frankfurter|Wikipedia)\b');

/// A press of Fill, Fill the blanks, Ask again or Ask the model anyway: its targets queue behind every earlier press.
/// The model is one on the phone (ai/available.dart `modelFor`); the caller has said why not where there is none.
void pressFill(String noteId, List<FillTarget> targets, String model) {
  if (targets.isEmpty) return;
  final text = _hosts[noteId]?.text();
  final batch = FillBatch(id: 'fill-${_ms().toRadixString(36)}-${_count += 1}', noteId: noteId, model: model, targets: targets);
  // Which are looked up on the web first: a live blank this device may look up.
  if (text != null) {
    final lookups = lookupsHere();
    for (final target in batch._targets) {
      if (target.anyway) continue;
      // Asked again, an answer from the web is looked up again, never answered from memory; one from the model or the
      // note is asked of the model as before.
      final again = target.again;
      if (again != null && !_fromTheWeb.hasMatch(again.mark)) continue;
      final found = _locate(noteId, target, text);
      if (found == null) continue;
      final (:note, :blank) = _asAsked(target, found, text);
      final lane = laneOf(blank, note, LaneOptions(clock: FactClock(now: _now()), learntUntil: learntUntil(model), lookups: lookups));
      if (lane is LiveLane && (lane.can == LiveCan.look || (again != null && lane.plan.kind != LookupKind.none))) target.plan = lane.plan;
    }
  }
  for (final target in batch.targets) {
    _setOutcome(noteId, target.key, null);
    _setStatus(noteId, target.key, const FillStatus.waiting());
  }
  _batches.add(batch);
  _bump();
  unawaited(_pump());
}

/// [text] between two offsets, each kept inside it, as JavaScript's `slice` keeps them.
String _slice(String text, int from, [int? to]) {
  final start = from.clamp(0, text.length);
  final end = (to ?? text.length).clamp(0, text.length);
  return end <= start ? '' : text.substring(start, end);
}

final RegExp _wholeBlank = RegExp('^$blankSource\$');

/// The blank or the asked-again mark a target is in [text]: by the editor's tracked range, else by its identity.
Blank? _locate(String noteId, _Target target, String text) {
  final range = _hosts[noteId]?.rangeOf(target.key);
  final again = target.again;
  if (again != null) {
    final at = range != null && _slice(text, range.from, range.to) == again.mark ? range.from : text.indexOf(again.mark);
    return at < 0 ? null : Blank(from: at, to: at + again.mark.length, question: target.question);
  }
  if (range != null) {
    final found = _wholeBlank.firstMatch(_slice(text, range.from, range.to));
    if (found != null && jsTrim(found.group(1) ?? '') == target.question) return Blank(from: range.from, to: range.to, question: target.question);
  }
  final same = blanksIn(text).where((b) => b.question == target.question).toList();
  return target.order >= 0 && target.order < same.length ? same[target.order] : null;
}

/// An ask for a target in [text]: a blank's shape, or an asked-again mark's shape as its blank had it.
Ask _askFor(_Target target, Blank blank, String text) {
  final again = target.again;
  if (again == null) return Ask(blank: blank, info: shapeOf(blank, text));
  final written = '{?${target.question}}';
  final pseudo = '${_slice(text, 0, blank.from)}$written${_slice(text, blank.to)}';
  return Ask(blank: blank, info: shapeOf(Blank(from: blank.from, to: blank.from + written.length, question: target.question), pseudo), again: Again(words: again.words));
}

/// The note's text now: its editor's, or the store's.
Future<String?> _currentText(String noteId) async {
  final host = _hosts[noteId];
  if (host != null) return host.text();
  try {
    return (await _getNote(noteId))?.body;
  } catch (_) {
    return null;
  }
}

// ---- running --------------------------------------------------------------------------------------------------------

Future<void> _pump() async {
  if (_working) return;
  _working = true;
  try {
    while (_batches.isNotEmpty) {
      final batch = _batches[0];
      await _runBatch(batch);
      if (_batches.isNotEmpty) _batches.removeAt(0);
      _finishBatch(batch);
    }
  } finally {
    _working = false;
  }
}

/// Completes once the note has no run but a fill's: a fill never stops Format or Summarize.
Future<void> _noOtherRun(String noteId) {
  bool other() => isRunning(noteId) && runFor(noteId)?.kind != RunKind.fill;
  if (!other()) return Future<void>.value();
  final done = Completer<void>();
  late final VoidCallback stop;
  stop = subscribeRuns((_) {
    if (other()) return;
    stop();
    if (!done.isCompleted) done.complete();
  });
  return done.future;
}

Future<void> _runBatch(FillBatch batch) async {
  final model = batch._targets.where((t) => t.plan == null).toList();
  final web = batch._targets.where((t) => t.plan != null).toList();
  if (model.isNotEmpty) {
    await _noOtherRun(batch.noteId);
    final text = await _currentText(batch.noteId);
    if (text == null) return;
    final located = [for (final target in model) (target: target, blank: _locate(batch.noteId, target, text))];
    for (final (:target, :blank) in located) {
      if (blank != null) continue;
      batch.counts.changed += 1;
      _setStatus(batch.noteId, target.key, null);
    }
    final asks = [
      for (final (:target, :blank) in located)
        if (blank != null) (target: target, ask: _askFor(target, blank, text)),
    ];
    final plan = fillPlan(text, [for (final a in asks) a.ask], rungFor(batch.model), _now());
    var before = 0;
    final total = asks.length;
    for (final generation in plan) {
      if (batch.stopped != null || batch.failed != null) break;
      final targets = [for (final ask in generation.asks) asks.firstWhere((a) => identical(a.ask, ask)).target];
      await _runGeneration(batch, targets, generation, (before: before, total: total));
      before += generation.asks.length;
    }
    // Anything a stop left: back to rest, a question still.
    for (final target in model) {
      final phase = fillStatus(batch.noteId, target.key)?.phase;
      if (phase == FillPhase.waiting || phase == FillPhase.filling) _setStatus(batch.noteId, target.key, null);
    }
  }
  for (final target in web) {
    if (batch.stopped != null || batch.failed != null) {
      _setStatus(batch.noteId, target.key, null);
      continue;
    }
    await _runWeb(batch, target);
  }
}

/// One generation: the targets found again in the note as it reads now, the model asked, the answers landed.
Future<void> _runGeneration(FillBatch batch, List<_Target> targets, Generation generation, ({int before, int total}) progress) async {
  await _noOtherRun(batch.noteId);
  final text = await _currentText(batch.noteId);
  if (text == null) return;
  final asks = <({_Target target, Ask ask})>[];
  for (final target in targets) {
    final blank = _locate(batch.noteId, target, text);
    if (blank == null) {
      batch.counts.changed += 1;
      _setStatus(batch.noteId, target.key, null);
      continue;
    }
    asks.add((target: target, ask: _askFor(target, blank, text)));
  }
  if (asks.isEmpty) return;
  final rung = rungFor(batch.model);
  final today = _now();
  String? worked(Blank blank) {
    final found = workOut(blank, text, FactClock(now: today));
    return found is WorkedAnswer ? found.answer : null;
  }

  final built = buildFill(text, [for (final a in asks) a.ask], rung: rung, today: today, worked: worked, tight: generation.tight);
  final state = await _runOne(batch, asks, (system: built.system, prompt: built.prompt, maxTokens: built.maxTokens), progress);
  if (state == null) return;
  final lines = readAsks(state.text ?? '', built.numbers);
  await _land(batch, [
    for (var i = 0; i < asks.length; i += 1)
      _Ready(target: asks[i].target, ask: asks[i].ask, lines: i < lines.length ? lines[i] : const [], truncated: state.truncated && i == asks.length - 1, source: null),
  ]);
}

final RegExp _unknownAlone = RegExp(r'^unknown\.?$', caseSensitive: false);
final RegExp _listMark = RegExp(r'^[-*]\s+');

/// A live target: looked up, then written by the model from what came back. Offline, it waits for a connection.
Future<void> _runWeb(FillBatch batch, _Target target) async {
  if (lookupsHere() != Lookups.on) {
    _park(batch, target, PausedWhy.localOnly);
    return;
  }
  _setStatus(batch.noteId, target.key, const FillStatus.looking());
  // Local only or the switch is read again before every request a lookup makes (a Wikipedia search is followed by two
  // Wikidata asks): turned on mid-lookup, nothing more goes.
  Future<({int status, Object? json})> held(String url) => lookupsHere() == Lookups.on ? _fetcher(url) : Future.error(StateError('held'));
  final found = await lookUp(target.plan!, held);
  if (lookupsHere() != Lookups.on) {
    _park(batch, target, PausedWhy.localOnly);
    return;
  }
  if (!found.ok && found.why == FoundWhy.offline) {
    _park(batch, target, PausedWhy.offline);
    return;
  }
  if (!found.ok) {
    batch.counts.nothing += 1;
    _setStatus(batch.noteId, target.key, null);
    _setOutcome(batch.noteId, target.key, FillOutcome(why: FillWhy.nothing, words: found.words, model: batch.model));
    return;
  }
  final source = found.source!;
  final facts = found.facts!;
  await _noOtherRun(batch.noteId);
  final text = await _currentText(batch.noteId);
  if (text == null) return;
  final blank = _locate(batch.noteId, target, text);
  if (blank == null) {
    batch.counts.changed += 1;
    _setStatus(batch.noteId, target.key, null);
    return;
  }
  final ask = _askFor(target, blank, text);
  // The weather and a rate are the app's own sentence from the source's data: no model writes them.
  final answer = found.answer;
  if (answer != null && answer.isNotEmpty) {
    await _land(batch, [_Ready(target: target, ask: ask, lines: [answer], truncated: false, source: FillSource.web(source), by: 'Ghost.md')]);
    return;
  }
  final today = _now();
  final built = buildFill(text, [ask], rung: 1, today: today);
  final state = await _runOne(batch, [(target: target, ask: ask)], (system: fillWebPrompt, prompt: webMessage(built.prompt, source, facts), maxTokens: built.maxTokens), (before: 0, total: 1));
  if (state == null) return;
  final read = readAsks(state.text ?? '', built.numbers);
  final lines = read.isNotEmpty ? read[0] : const <String>[];
  // A model's answer lands as the web's only if what came back holds it (web.dart `standsIn`); otherwise it is not
  // found.
  final said = lines.where((line) => jsTrim(line).isNotEmpty && !_unknownAlone.hasMatch(jsTrim(line))).toList();
  if (said.isNotEmpty && !said.every((line) => standsIn(line.replaceFirst(_listMark, ''), facts))) {
    batch.counts.nothing += 1;
    _setStatus(batch.noteId, target.key, null);
    _setOutcome(batch.noteId, target.key, FillOutcome(why: FillWhy.nothing, words: 'The answer wasn’t in what $source returned.', model: batch.model));
    return;
  }
  await _land(batch, [_Ready(target: target, ask: ask, lines: lines, truncated: state.truncated, source: FillSource.web(source))]);
}

void _park(FillBatch batch, _Target target, PausedWhy why) {
  _setStatus(batch.noteId, target.key, FillStatus.paused(why: why));
  _parked.add((batch: batch, target: target));
  batch.parked += 1;
}

/// A connection came back, or Local only went off: the parked lookups go on, in a press of their own each.
void resumeParked() {
  if (_parked.isEmpty || lookupsHere() == Lookups.localOnly || !_onLine()) return;
  final going = [..._parked];
  _parked.clear();
  for (final (:batch, :target) in going) {
    batch.parked -= 1;
    final again = FillBatch(id: '${batch.id}-web', noteId: batch.noteId, model: batch.model);
    again.targets.add(target);
    _batches.add(again);
  }
  _bump();
  unawaited(_pump());
}

/// Runs one generation through the engine, the targets filling meanwhile; the run's end, or null for a stop or a
/// failure.
Future<RunState?> _runOne(FillBatch batch, List<({_Target target, Ask ask})> asks, ({String system, String prompt, int maxTokens}) request, ({int before, int total}) progress) async {
  final instruction = [for (final a in asks) if (a.target.question.isNotEmpty) a.target.question].join(' · ');
  final handle = startRun(RunRequest(
    noteId: batch.noteId,
    kind: RunKind.fill,
    instruction: instruction.isNotEmpty ? instruction : null,
    model: batch.model,
    system: request.system,
    prompt: request.prompt,
    maxTokens: request.maxTokens,
    temperature: 0,
    think: false,
    batch: RunBatch(id: batch.id, before: progress.before, asked: asks.length, total: progress.total),
  ));
  batch.firstStart ??= _ms();
  for (final (:target, ask: _) in asks) {
    _setStatus(batch.noteId, target.key, FillStatus.filling(runId: handle.id));
  }
  final state = await handle.done;
  batch.lastRunId = handle.id;
  batch.lastEnd = _ms();
  batch.outputTokens += state.outputTokens;
  if (state.phase == RunPhase.done) return state;
  for (final (:target, ask: _) in asks) {
    _setStatus(batch.noteId, target.key, null);
  }
  if (state.phase == RunPhase.stopped) {
    final newer = runFor(batch.noteId);
    final stopped = newer != null && newer.id != handle.id && newer.kind != RunKind.fill ? FillStopped.byKind(newer.kind) : const FillStopped();
    batch.stopped = stopped;
    // The newer ask for the note is the one meant: every press of it still waiting goes too.
    for (final other in _batches) {
      if (!identical(other, batch) && other.noteId == batch.noteId) other.stopped = stopped;
    }
  } else {
    batch.failed = state.message ?? 'The model stopped.';
  }
  return null;
}

// ---- landing --------------------------------------------------------------------------------------------------------

/// One answer as read, before it is checked against the note as it reads when it lands.
class _Ready {
  const _Ready({required this.target, required this.ask, required this.lines, required this.truncated, required this.source, this.by});

  final _Target target;
  final Ask ask;
  final List<String> lines;
  final bool truncated;

  /// From the web, named; null for the model's own, whose source is worked out at landing.
  final FillSource? source;

  /// Who wrote the words, when not the model: the app, for a forecast or a rate it wrote from the source's own data.
  final String? by;
}

/// The note and the blank an answer is checked against: an asked-again mark read as the blank it was.
({String note, Blank blank}) _asAsked(_Target target, Blank blank, String text) {
  if (target.again == null) return (note: text, blank: blank);
  final written = '{?${target.question}}';
  return (
    note: '${_slice(text, 0, blank.from)}$written${_slice(text, blank.to)}',
    blank: Blank(from: blank.from, to: blank.from + written.length, question: target.question),
  );
}

/// The answers checked against their shapes and turned into landings on [text]: a refused answer writes nothing and
/// is counted. [text] is the note as it reads now; a target no longer there is dropped and counted. Asked again, the
/// old answer stays unless a different one passes, and a toast says which (7.2).
List<Landing> _landings(FillBatch batch, String text, List<_Ready> ready) {
  final out = <Landing>[];
  final name = modelName(batch.model);
  // A title or a summary is checked last, against the note with this press's other answers in it: once the capital
  // blank beside it has landed, "Lisbon" is the note's own word, and a summary of the note may say it. The shots found
  // "In one line" refused for naming what the press itself had just written.
  final found = [
    for (final one in ready)
      () {
        final blank = _locate(batch.noteId, one.target, text);
        final shape = blank != null ? _askFor(one.target, blank, text).info.shape : null;
        return (one: one, blank: blank, late: shape == Shape.title || shape == Shape.summary);
      }(),
  ];
  for (final (:one, :blank, :late) in [...found.where((f) => !f.late), ...found.where((f) => f.late)]) {
    _setStatus(batch.noteId, one.target.key, null);
    if (blank == null) {
      batch.counts.changed += 1;
      continue;
    }
    final again = one.target.again;
    final ask = _askFor(one.target, blank, text);
    final asked = _asAsked(one.target, blank, text);
    final others = late && out.isNotEmpty ? '${asked.note}\n\n${[for (final landing in out) landing.words.join('\n')].join('\n')}' : asked.note;
    final checked = checkShape(one.lines, asked.blank, ask.info, others, one.truncated);
    if (!checked.ok) {
      if (again != null) {
        _toaster?.call(FillToast(
          message: checked.why == CheckWhy.unknown
              ? '$name said it did not know this time.'
              : checked.why == CheckWhy.didntFit
                  ? 'The new answer didn’t fit, so the old one stays.'
                  : 'No new answer came, so the old one stays.',
        ));
        continue;
      }
      final FillWhy why;
      if (checked.why == CheckWhy.unknown) {
        batch.counts.unknown += 1;
        why = FillWhy.unknown;
      } else if (checked.why == CheckWhy.none) {
        batch.counts.none += 1;
        why = FillWhy.none;
      } else {
        batch.counts.didntFit += 1;
        why = FillWhy.didntFit;
      }
      _setOutcome(batch.noteId, one.target.key, FillOutcome(why: why, model: batch.model));
      continue;
    }
    if (again != null && jsTrim(checked.text!).toLowerCase() == jsTrim(again.words).toLowerCase()) {
      _toaster?.call(const FillToast(message: 'The same answer came back.'));
      continue;
    }
    final fromNote = checked.items.every((item) => fromThisNote(item, asked.blank, ask.info.shape, asked.note, asked.note));
    final source = one.source ?? (fromNote ? const FillSource.note() : const FillSource.memory());
    out.add(Landing(from: blank.from, to: blank.to, question: one.target.question, info: ask.info, words: checked.items, source: source, model: one.by ?? name, date: isoDay(_now())));
    _setOutcome(batch.noteId, one.target.key, null);
  }
  return out;
}

/// A generation's answers into its note: through its editor when it is open, else written to the store.
Future<void> _land(FillBatch batch, List<_Ready> ready) async {
  final host = _hosts[batch.noteId];
  if (host != null) {
    _landOpen(batch, host, ready);
  } else {
    await _landClosed(batch, ready);
  }
}

void _landOpen(FillBatch batch, FillHost host, List<_Ready> ready) {
  final text = host.text();
  final answers = _landings(batch, text, ready);
  if (answers.isEmpty) return;
  final sign = batch.landed == 0 ? signatureChange(text) : null;
  final after = host.land(allChanges(text, answers), sign);
  if (after == null) return;
  batch.before ??= text;
  batch.after = after;
  batch.landed += answers.length;
  _noteFirstFill();
}

/// `syncNow().catch(() => undefined)`: a sync that fails is nothing to a landing.
Future<void> _synced() async {
  try {
    await _syncNow();
  } catch (_) {
    // Not synced: the note is read and written as this device has it.
  }
}

final RegExp _movedOn = RegExp('changed|deleted|revision', caseSensitive: false);

/// Into a closed note, the way a write-up lands in one: synced, read fresh, found again by question and order,
/// written with the revision it was read at, read again once on a conflict, synced after. A note opened meanwhile
/// takes the answers through its editor; a write that still does not go through keeps them for the next open.
Future<void> _landClosed(FillBatch batch, List<_Ready> ready) async {
  await _synced();
  for (var attempt = 0; attempt < 2; attempt += 1) {
    final host = _hosts[batch.noteId];
    if (host != null) {
      _landOpen(batch, host, ready);
      return;
    }
    Note? note;
    try {
      note = await _getNote(batch.noteId);
    } catch (_) {
      note = null;
    }
    if (note == null) return;
    final answers = _landings(batch, note.body, ready);
    if (answers.isEmpty) return;
    final sign = batch.landed == 0 ? signatureChange(note.body) : null;
    final next = applyChanges(note.body, [...allChanges(note.body, answers), ?sign]);
    try {
      await _updateNote(batch.noteId, next, note.revision);
    } catch (error) {
      if (_movedOn.hasMatch(failureText(error))) continue;
      break;
    }
    batch.before ??= note.body;
    batch.after = next;
    batch.landed += answers.length;
    final title = noteTitle(next);
    batch.closedTitle = title.isNotEmpty ? title : 'Untitled';
    await _synced();
    _noteFirstFill();
    return;
  }
  // Kept for the session: they land when the note is next opened, while their blanks are still there.
  (_pending[batch.noteId] ??= []).add((batch: batch, ready: ready));
}

/// Once per device, after the first model answer lands: how to read one (6.4).
StoredFlag get _told => stored.flag('glyph-fill-told', value: 'on');
void _noteFirstFill() {
  if (_told.isMarked) return;
  _told.mark();
  _toaster?.call(const FillToast(message: 'The model’s answers have a dotted line. Tap one to see where it came from.', duration: 8000));
}

/// The press is over: its one line in the log, the strip's last word, and a toast for what did not fill.
void _finishBatch(FillBatch batch) {
  final noteId = batch.noteId;
  final lastRunId = batch.lastRunId;
  if (lastRunId != null && batch.landed != 0) {
    final span = batch.lastEnd - (batch.firstStart ?? batch.lastEnd);
    final ms = span > 0 ? span : 0;
    final instruction = [for (final t in batch.targets) if (t.question.isNotEmpty) t.question].join(' · ');
    recordRun(RunRecord(
      id: lastRunId,
      noteId: noteId,
      kind: RunKind.fill,
      instruction: instruction.isNotEmpty ? instruction : null,
      model: batch.model,
      at: batch.firstStart ?? _ms(),
      ms: ms,
      outputTokens: batch.outputTokens,
      outcome: batch.stopped != null ? RunOutcome.stopped : RunOutcome.done,
      message: null,
      truncated: false,
      filled: batch.landed,
    ));
    final before = batch.before;
    final after = batch.after;
    if (before != null && after != null && before != after) recordChange(noteId, lastRunId, before, after);
    sayRun(noteId, lastRunId, filledSentence(batch.landed, batch.model, ms));
  } else if (lastRunId != null && batch.stopped == null && batch.failed == null) {
    sayRun(noteId, lastRunId, filledSentence(0, batch.model, 0));
  }
  for (final target in batch.targets) {
    if (fillStatus(noteId, target.key)?.phase != FillPhase.paused) _setStatus(noteId, target.key, null);
  }
  final said = pressToast(batch);
  if (said != null) _toaster?.call(said);
  _bump();
}

final RegExp _tooLong = RegExp('too long', caseSensitive: false);

/// The toast after a press, built from its counts (6.5): none when everything filled.
FillToast? pressToast(FillBatch batch) {
  final counts = batch.counts;
  final failed = batch.failed;
  if (failed != null && failed.isNotEmpty) {
    return FillToast(message: _tooLong.hasMatch(failed) ? 'This part of the note is too long for the model. Try a shorter section.' : failed);
  }
  final by = batch.stopped?.by;
  if (by != null) {
    final left = batch.targets.length - batch.landed - batch.parked;
    final kind = by.id;
    final name = kind == 'summarize' ? 'Summarize' : kind.substring(0, 1).toUpperCase() + kind.substring(1);
    return FillToast(message: '$name stopped the fill. ${left == 1 ? '1 blank is still a question.' : '$left blanks are still questions.'}');
  }
  if (batch.stopped != null) return null;
  final parts = <String>[];
  if (counts.unknown != 0) parts.add('${counts.unknown} not known');
  if (counts.didntFit != 0) parts.add("${counts.didntFit} didn't fit");
  if (counts.none != 0) parts.add('${counts.none} had no answer');
  if (counts.nothing != 0) parts.add('${counts.nothing} not found online');
  // A live blank parked for a connection, or held by Local only, is said too: the press did something with it.
  final held = lookupsHere() == Lookups.localOnly;
  if (batch.parked != 0) parts.add('${batch.parked} ${held ? 'held by Local only' : 'waiting for a connection'}');
  final changed = counts.changed != 0
      ? (counts.changed == 1 ? '1 answer was not written. Its question had changed.' : '${counts.changed} answers were not written. Their questions had changed.')
      : '';
  var message = '';
  final onlyNone = counts.none > 0 && parts.length == 1;
  if (batch.landed != 0 && parts.isNotEmpty) {
    message = '${batch.landed} filled. ${parts.join(', ')}.';
  } else if (batch.landed == 0 && onlyNone) {
    message = 'Nothing filled. No answer came.';
  } else if (batch.landed == 0 && batch.parked != 0 && parts.length == 1) {
    message = held
        ? 'Local only is on, so ${isMacApp ? 'this Mac' : 'the phone'} looks nothing up.'
        : 'Waiting for a connection. ${isMacApp ? 'This Mac' : 'The phone'} looks ${batch.parked == 1 ? 'it' : 'them'} up once it is online.';
  } else if (batch.landed == 0 && parts.isNotEmpty) {
    message = 'Nothing filled. ${parts.join(', ')}.';
  }
  if (changed.isNotEmpty) message = message.isNotEmpty ? '$message $changed' : changed;
  final closedTitle = batch.closedTitle;
  if (closedTitle != null && closedTitle.isNotEmpty && batch.landed != 0 && _visible()) {
    final filled = 'Filled ${blanksWord(batch.landed)} in $closedTitle.';
    return FillToast(message: message.isNotEmpty ? '$filled $message' : filled, duration: 10000, action: FillToastAction(label: 'Open', onPress: () => _opener?.call(batch.noteId)));
  }
  return message.isNotEmpty ? FillToast(message: message) : null;
}
