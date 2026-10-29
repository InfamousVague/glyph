/// Better words after the recording: the post-pass. A port of `src/app/capture/refine.ts`.
///
/// The live transcript comes from a small, fast model so the words keep up with speech. A larger one makes about
/// half as many mistakes but cannot keep up, so it runs afterwards, in the background, over the recording the
/// capture kept (native generation 7): one pass per take, then the note's words are replaced with the better ones -
/// only if the note still reads exactly as Done saved it, because an edit in between is the person's and wins.
///
/// The queue lives in the device's storage, so a pass the phone did not get to (the app was closed, the recorder was
/// opened again) runs on the next launch. One pass at a time, never while the recorder is on screen: both models
/// want the same cores. The first pass downloads the larger model (190 MB); until it is there, notes simply keep
/// their live words. What the note reads as with the better words - commands left out - is refine_text.dart.
///
/// Nor over a note that is open (`holdNote`): the editor's saving must be the only writer of an open note, or its
/// next keystroke's save conflicts and every save after it in that visit is dropped. A recording that opens its note
/// at Done has its better words land after the note is left.
///
/// The summary queue and the gist runner follow this queue's hold (`onRefineHold`): the recorder wins the cores, so
/// a run of theirs in flight is cancelled the moment it comes up, and their queues look again once it has gone. A
/// summary that landed between Done and the better words does not stop the better words: the note must read as Done
/// saved it with the app's own section written in at its place, and the section is carried into the better words. A
/// section that is not the app's - typed, or the app's and then edited - is the person's, and the usual rule holds.
///
/// A job is marked `started` before its pass runs, and a job found `started` at launch counts that as one try, so a
/// pass that kills the app cannot kill it at every launch: three tries and the job is dropped.
///
/// A meeting's job (`meeting`, the Mac's recorder) renders its better phrases as the transcript the note was written
/// with (markdown.dart `renderTranscript`), in place of the transcript it has, with the summary above it left as it
/// stands. A meeting recorded by the phone's service never has a job here: its phrases are the write-up's own. And
/// no pass starts while that write-up is running (meeting_live.dart `writeUpRunning`), since both want the same
/// speech model; Rust's own guard is the hard one, and this the polite one.
///
/// What differs:
/// - The web's module is one queue for the page, with its state in module variables. Here it is a [Refining], made
///   once by whoever wires the app, with the module's functions as its methods under the web's names.
/// - What the web imports, a [Refining] is given: the native capture ([CaptureBackend]; null where `isTauri()` is
///   false) for the three `capture_refine*` commands and their two progress events, `hasNativeGeneration`, the
///   preferences, the device's storage ([Stored]), the note store's `getNote`, `updateNote` and `setNoteRecording`,
///   the summary's `keptText` and `summaryUnchanged` (`ai/summaryKeep.ts`), `writeUpRunning`, the app coming back to
///   the screen (`onVisible`, the document's `visibilitychange`), and where a warning is written (`console.warn`).
/// - `useRefining` is [Refining.refining], an [ExternalStore] a widget listens to.
/// - A job from `Omit<RefineJob, 'tries'>` is a [RefineJob] whose `tries` was left at 0.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/background_jobs.dart';
import '../core/note.dart' show Note;
import '../core/preferences.dart' show Preferences;
import '../core/stored.dart';
import '../core/summary_text.dart' show summarySection, withSummary;
import '../meet/speakers.dart' show namedTranscript;
import 'engine.dart' show CaptureBackend, CaptureEventRefineModelProgress, CaptureEventRefineProgress;
import 'markdown.dart' show Segment, renderTranscript, withTranscript;
import 'meeting_live.dart' show ExternalStore;
import 'place.dart' show Placing;
import 'refine_text.dart' show refinedBody, refinedSegments;
import 'take_types.dart' show Span;

/// A pass over one take, as the queue keeps it.
@immutable
class RefineJob {
  const RefineJob({
    required this.id,
    required this.fromMs,
    required this.recordingMs,
    required this.baseBody,
    required this.savedBody,
    required this.titled,
    required this.priorSegments,
    required this.promptTail,
    this.skip,
    this.clips,
    this.keywordAt,
    this.placing,
    this.live,
    this.tries = 0,
    this.started,
    this.meeting,
  });

  /// The note.
  final String id;

  /// Where this take starts on the recording's timeline.
  final int fromMs;

  /// The recording's whole length after this take.
  final int recordingMs;

  /// The note's text before this take: empty for a new note.
  final String baseBody;

  /// What Done saved: the text that must still stand for the words to be replaced.
  final String savedBody;

  /// Whether the take is the note's first, and so may take a title.
  final bool titled;

  /// The phrases before this take, already on the recording's timeline.
  final List<Segment> priorSegments;

  /// The tail of the text before the take, so the model continues its casing.
  final String promptTail;

  /// Stretches of the recording that were commands ("Glyph, add buy milk to HelloTrade"), on the recording's
  /// timeline: the better words leave them out, as the live words did. Absent on jobs from before.
  final List<Span>? skip;

  /// The voice memos a take left, each already written as its mark, on the recording's timeline: the better words
  /// never heard them - their stretches are in `skip` - so they are put back where they were. A recording no longer
  /// makes a memo, so a new job has none; one queued by a build that still did may.
  final List<Segment>? clips;

  /// Phrases that were words and then "Glyph": the better words keep what came before the keyword.
  final List<Span>? keywordAt;

  /// Where the take's words went in the note (place.dart): into its lists rather than on its end. Absent on jobs
  /// from before, and for the end, which is what those always meant.
  final Placing? placing;

  /// The take's own phrases as the live reader kept them, on the recording's timeline: a better phrase that ran a
  /// command and what it sent together is replaced by these, so it neither erases the item nor brings the command
  /// back. Absent on jobs from before, and on takes the live reader did nothing in.
  final List<Segment>? live;
  final int tries;

  /// Set as the pass starts and cleared as it ends however it ends: found set at launch, the pass killed the app.
  final bool? started;

  /// A meeting's take (capture/meeting.dart): rendered as a transcript, never as a dictated note. Set from the
  /// preferences' meetings as it is queued.
  final bool? meeting;

  /// The web's spread: this job with some of it said again.
  RefineJob copyWith({
    String? id,
    int? fromMs,
    int? recordingMs,
    String? baseBody,
    String? savedBody,
    bool? titled,
    List<Segment>? priorSegments,
    String? promptTail,
    List<Span>? skip,
    List<Segment>? clips,
    List<Span>? keywordAt,
    Placing? placing,
    List<Segment>? live,
    int? tries,
    bool? started,
    bool? meeting,
  }) =>
      RefineJob(
        id: id ?? this.id,
        fromMs: fromMs ?? this.fromMs,
        recordingMs: recordingMs ?? this.recordingMs,
        baseBody: baseBody ?? this.baseBody,
        savedBody: savedBody ?? this.savedBody,
        titled: titled ?? this.titled,
        priorSegments: priorSegments ?? this.priorSegments,
        promptTail: promptTail ?? this.promptTail,
        skip: skip ?? this.skip,
        clips: clips ?? this.clips,
        keywordAt: keywordAt ?? this.keywordAt,
        placing: placing ?? this.placing,
        live: live ?? this.live,
        tries: tries ?? this.tries,
        started: started ?? this.started,
        meeting: meeting ?? this.meeting,
      );

  /// The job as the queue writes it: the web's keys, and none for what is absent.
  Map<String, Object?> toJson() => {
        'id': id,
        'fromMs': fromMs,
        'recordingMs': recordingMs,
        'baseBody': baseBody,
        'savedBody': savedBody,
        'titled': titled,
        'priorSegments': [for (final s in priorSegments) _segmentJson(s)],
        'promptTail': promptTail,
        if (skip != null) 'skip': [for (final s in skip!) _spanJson(s)],
        if (clips != null) 'clips': [for (final s in clips!) _segmentJson(s)],
        if (keywordAt != null) 'keywordAt': [for (final s in keywordAt!) _spanJson(s)],
        if (placing != null) 'placing': placing!.toJson(),
        if (live != null) 'live': [for (final s in live!) _segmentJson(s)],
        'tries': tries,
        if (started != null) 'started': started,
        if (meeting != null) 'meeting': meeting,
      };

  /// A job as the queue kept it, or null for anything without an id. What a job from an older build lacks is read
  /// as absent, or as the quiet value of a field that is never absent.
  static RefineJob? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String) return null;
    return RefineJob(
      id: id,
      fromMs: _int(raw['fromMs']) ?? 0,
      recordingMs: _int(raw['recordingMs']) ?? 0,
      baseBody: raw['baseBody'] is String ? raw['baseBody'] as String : '',
      savedBody: raw['savedBody'] is String ? raw['savedBody'] as String : '',
      titled: raw['titled'] == true,
      priorSegments: _segments(raw['priorSegments']) ?? const [],
      promptTail: raw['promptTail'] is String ? raw['promptTail'] as String : '',
      skip: _spans(raw['skip']),
      clips: _segments(raw['clips']),
      keywordAt: _spans(raw['keywordAt']),
      placing: Placing.fromJson(raw['placing']),
      live: _segments(raw['live']),
      tries: _int(raw['tries']) ?? 0,
      started: raw['started'] is bool ? raw['started'] as bool : null,
      meeting: raw['meeting'] is bool ? raw['meeting'] as bool : null,
    );
  }
}

int? _int(Object? value) => value is num && value.isFinite ? value.round() : null;

Map<String, Object?> _segmentJson(Segment s) => {'text': s.text, 'startMs': s.startMs, 'endMs': s.endMs};
Map<String, Object?> _spanJson(Span s) => {'startMs': s.startMs, 'endMs': s.endMs};

List<Segment>? _segments(Object? raw) {
  if (raw is! List) return null;
  return [
    for (final s in raw)
      if (s is Map) Segment(text: s['text'] is String ? s['text'] as String : '', startMs: _int(s['startMs']) ?? 0, endMs: _int(s['endMs']) ?? 0),
  ];
}

List<Span>? _spans(Object? raw) {
  if (raw is! List) return null;
  return [
    for (final s in raw)
      if (s is Map) Span(startMs: _int(s['startMs']) ?? 0, endMs: _int(s['endMs']) ?? 0),
  ];
}

/// The binary generation that has `capture_refine` (`REFINE_GENERATION`).
const int _refineGeneration = 7;
const String _queueKey = 'glyph-refine-queue';
const int _maxTries = 3;

/// How long to wait before trying again after "busy" or a failure (`RETRY_MS`).
const int _retryMs = 20000;

final RegExp _busy = RegExp('busy|cancelled', caseSensitive: false);

/// What the screen sees of the queue.
@immutable
class RefineState {
  const RefineState({required this.pending, required this.download});

  /// Notes whose better words are being worked out right now, or waiting their turn.
  final Set<String> pending;

  /// The larger model's download, while one is under way.
  final ({int received, int total})? download;
}

/// The pass after a recording: its queue, when it runs and when it waits, and what it writes.
class Refining {
  Refining({
    required this.backend,
    required this.hasNativeGeneration,
    required this.preferences,
    required this.stored,
    required this.getNote,
    required this.updateNote,
    required this.setNoteRecording,
    required this.keptText,
    required this.summaryUnchanged,
    required this.writeUpRunning,
    this.onVisible,
    void Function(String message)? warn,
  }) : warn = warn ?? debugPrint;

  /// The native capture, or null where there is none (the web's `isTauri()` false).
  final CaptureBackend? backend;

  /// `core/nativeGeneration.ts` `hasNativeGeneration`.
  final Future<bool> Function(int wanted) hasNativeGeneration;

  /// `core/preferences.ts` `preferences()`: its `refine`, `localOnly` and `meetings` are read.
  final Preferences Function() preferences;

  /// The device's storage (`core/stored.ts`), where the queue is kept.
  final Stored stored;

  /// The note store's three (`core/store.ts`): a note whole, a revision-checked write, and a tape's length and
  /// phrases written beside its note.
  final Future<Note?> Function(String id) getNote;
  final Future<Note> Function(String id, String body, int expectedRevision) updateNote;
  final Future<Note?> Function(String id, int? recordingMs, List<Segment> segments) setNoteRecording;

  /// The summary section the app last wrote into a note, or null (`ai/summaryKeep.ts` `keptText`), and whether a
  /// section is still that one, word for word (`summaryUnchanged`).
  final String? Function(String id) keptText;
  final bool Function(String id, String text) summaryUnchanged;

  /// Whether a meeting's write-up has the speech model now (meeting_live.dart `writeUpRunning`).
  final bool Function() writeUpRunning;

  /// Calls its listener each time the app comes back to the screen; answers the way to stop (the document's
  /// `visibilitychange`, when it says `visible`). Null where nothing says so.
  final VoidCallback Function(VoidCallback listener)? onVisible;

  /// Where a pass that failed is written down (`console.warn`).
  final void Function(String message) warn;

  // ---- the queue ---------------------------------------------------------------------------------------------------

  List<RefineJob> _readQueue() => stored.read<List<RefineJob>>(
        _queueKey,
        <RefineJob>[],
        (value) => value is List ? [for (final raw in value) ?RefineJob.fromJson(raw)] : <RefineJob>[],
      );

  /// No storage: the job runs now or not at all.
  void _writeQueue(List<RefineJob> jobs) => stored.write(_queueKey, [for (final job in jobs) job.toJson()]);

  // ---- what the screen sees ----------------------------------------------------------------------------------------

  /// The queue as a screen follows it (`useRefining`).
  final ExternalStore<RefineState> refining = ExternalStore<RefineState>(const RefineState(pending: <String>{}, download: null));

  void _syncPending() {
    final pending = {for (final job in _readQueue()) job.id};
    refining.update((was) => RefineState(pending: pending, download: was.download));
  }

  void _publishDownload(({int received, int total})? download) {
    refining.update((was) => RefineState(pending: was.pending, download: download));
  }

  // ---- running -----------------------------------------------------------------------------------------------------

  /// A screen that wants the cores is up - the recorder, or a review running its own pass: no queued pass starts.
  bool _held = false;

  /// Notes open in the editor, whose passes wait until they are left: the editor is the one writer of an open note.
  final Set<String> _heldNotes = <String>{};
  bool _running = false;
  Timer? _timer;
  VoidCallback? _onChanged;

  /// Who follows the hold: the summary queue and the gist runner, which stop their runs while it is on.
  final Set<void Function(bool on)> _holdListeners = <void Function(bool on)>{};

  /// Whether the recorder or a review is up: no background run of any kind starts while one is.
  bool refineHeld() => _held;

  /// Whether a note's better words are still to come: a pass for it is queued or running.
  bool refinePending(String id) => _readQueue().any((j) => j.id == id);

  /// Called with `true` as the recorder or a review comes up and `false` as it goes; answers the way to stop
  /// listening.
  VoidCallback onRefineHold(void Function(bool on) listener) {
    _holdListeners.add(listener);
    return () {
      _holdListeners.remove(listener);
    };
  }

  bool _same(RefineJob j, RefineJob job) => j.id == job.id && j.fromMs == job.fromMs;

  /// Ask for a pass over a finished take. Runs when the recorder has gone and the phone is free.
  void enqueueRefine(RefineJob job) {
    if (backend == null || !preferences().refine) return;
    final queue = _readQueue().where((j) => !_same(j, job)).toList();
    // A meeting is known by its preference, whichever site queued the job.
    final meeting = job.meeting ?? preferences().meetings.containsKey(job.id);
    queue.add(job.copyWith(tries: 0, meeting: meeting ? true : null));
    _writeQueue(queue);
    _syncPending();
    _kick();
  }

  /// No queued pass starts while `on`; let go, the queue looks again a moment later. One flag for both screens that
  /// hold it.
  void _hold(bool on) {
    if (_held == on) return;
    _held = on;
    for (final listener in _holdListeners.toList()) {
      listener(on);
    }
    if (!on) _kick(1500);
  }

  /// The recorder is on screen (or not): no pass runs while it is.
  void setRecorderLive(bool live) => _hold(live);

  /// A note open (or left): no pass writes it while it is, and the queue looks again a moment after it is left.
  void holdNote(String id, bool on) {
    if (on) {
      _heldNotes.add(id);
      return;
    }
    _heldNotes.remove(id);
    _kick(1500);
  }

  /// A take's pass taken out of the queue: its words were undone, so its better words must not write them back.
  void dropRefine(String id, int fromMs) {
    final queue = _readQueue();
    if (!queue.any((j) => j.id == id && j.fromMs == fromMs)) return;
    _writeQueue(queue.where((j) => !(j.id == id && j.fromMs == fromMs)).toList());
    _syncPending();
  }

  /// Wire the runner to the app: called once, with what to do when a note's words changed.
  VoidCallback startRefining(VoidCallback changed) {
    _onChanged = changed;
    // A job found started was running when the app stopped: that pass counts as a try, and its third drops the job.
    final queue = _readQueue();
    if (queue.any((j) => j.started == true)) {
      _writeQueue([
        for (final j in queue)
          if (j.started != true)
            j
          else if (j.tries + 1 < _maxTries)
            j.copyWith(started: false, tries: j.tries + 1),
      ]);
    }
    _syncPending();
    final offVisible = onVisible?.call(() => _kick(2000));
    _kick(4000);
    return () {
      offVisible?.call();
      _timer?.cancel();
      _onChanged = null;
    };
  }

  void _kick([int delay = 0]) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: delay), () => unawaited(_runNext()));
  }

  Future<bool> _canRefine() async {
    if (backend == null || !preferences().refine) return false;
    return hasNativeGeneration(_refineGeneration);
  }

  /// The larger model, downloaded on first use with its progress shown.
  Future<bool> _ensureRefineModel() async {
    final backend = this.backend!;
    ({bool present, int bytes})? status;
    try {
      status = await backend.refineModelStatus();
    } catch (_) {
      status = null;
    }
    if (status == null) return false;
    if (status.present) return true;
    // Local only: the better words wait until the model is on the phone.
    if (preferences().localOnly) return false;
    _publishDownload((received: 0, total: status.bytes));
    // On the app's record of running work (lib/core/background_jobs.dart; docs/ACTIVITY.md): a ring filling, green.
    // Asked for again by the next pass when it does not come, so a failure goes quietly here.
    final job = activity.begin(refineModelJobId, kind: JobKind.downloads, title: 'Downloading the better-words model', line: 'Downloading', fraction: 0);
    final unlisten = backend.events.listen((event) {
      if (event is! CaptureEventRefineModelProgress) return;
      _publishDownload((received: event.receivedBytes, total: event.totalBytes));
      if (event.totalBytes > 0) job.progress(fraction: event.receivedBytes / event.totalBytes, steps: downloadSteps(event.receivedBytes, event.totalBytes));
    });
    try {
      final fetched = await backend.fetchRefineModel();
      fetched.present ? job.done(tally: const JobTally('model downloaded', 'models downloaded')) : job.stopped();
      return fetched.present;
    } catch (error) {
      warn('[glyph] the larger voice model did not download: $error');
      job.stopped();
      return false;
    } finally {
      unawaited(unlisten.cancel());
      _publishDownload(null);
    }
  }

  /// The first job in the queue, if the phone can take it now. What comes next is decided by how this one went: the
  /// next job half a second after one that finished or was given up on, and this one again after a wait when the
  /// model was not there or the pass failed. Each outcome picks its one wait, and the runner is kicked once, after
  /// it: a phone without the larger model - Local only on, say - that was kicked again at the half-second would ask
  /// for the model twice a second for as long as the app stayed open.
  Future<void> _runNext() async {
    if (_running || _held) return;
    final queue = _readQueue();
    // The first whose note is not open: an open note's pass waits until it is left.
    RefineJob? job;
    for (final j in queue) {
      if (!_heldNotes.contains(j.id)) {
        job = j;
        break;
      }
    }
    if (job == null) return;
    if (!(await _canRefine())) return;
    // A meeting's write-up has the speech model: this pass looks again once it has let go.
    if (writeUpRunning()) {
      _kick(_retryMs);
      return;
    }
    _running = true;
    var next = 500;
    final mine = job;
    try {
      if (!(await _ensureRefineModel())) {
        next = _retryMs * 3;
        return;
      }
      _mark(mine, true);
      // Better words on the app's record of running work: the teal reels while the larger model listens again.
      activity.begin(refineJobId(mine.id), kind: JobKind.audio, title: 'Better words', line: 'Listening again with the larger model', onOpen: activityRoutes.noteOpener(mine.id));
      final refined = await backend!.refine(id: mine.id, fromMs: mine.fromMs, promptTail: mine.promptTail);
      await _apply(mine, refined);
      _finish(mine);
      activity.handle(refineJobId(mine.id))?.done(tally: const JobTally('recording heard again', 'recordings heard again'));
      _onChanged?.call();
    } catch (error) {
      final message = _failureText(error);
      if (_busy.hasMatch(message)) {
        next = _retryMs;
      } else {
        warn('[glyph] the better words did not come: $message');
        if (mine.tries + 1 >= _maxTries) {
          _finish(mine);
        } else {
          _writeQueue([for (final j in _readQueue()) _same(j, mine) ? j.copyWith(tries: j.tries + 1) : j]);
          next = _retryMs;
        }
      }
    } finally {
      // Tried again after a wait, or given up on after its tries, as before: either way quietly.
      activity.handle(refineJobId(mine.id))?.stopped();
      _mark(mine, false);
      _running = false;
      if (_readQueue().isNotEmpty) _kick(next);
    }
  }

  /// The job's `started` flag, written through to the queue while the job is still in it.
  void _mark(RefineJob job, bool started) {
    final queue = _readQueue();
    if (!queue.any((j) => _same(j, job) && (j.started == true) != started)) return;
    _writeQueue([for (final j in queue) _same(j, job) ? j.copyWith(started: started) : j]);
  }

  /// The better words go in only if the note still reads as Done left it - the app's own summary section aside,
  /// which may have landed since and is carried into the better words as it stands; the better phrases go in either
  /// way. A section of the person's own is theirs: one Done saved is in the better words already, and one written
  /// since is an edit, which wins.
  Future<void> _apply(RefineJob job, List<Segment> refined) async {
    if (refined.isEmpty) return;
    final note = await getNote(job.id);
    if (note == null) return;
    final kept = keptText(job.id);
    final section = summarySection(note.body, kept);
    final ours = section != null && summaryUnchanged(job.id, section.text);
    // The editor's landing puts a newline after the note's last line; that is not an edit.
    final asSaved = (ours ? withSummary(job.savedBody, section.text, kept: kept) : job.savedBody).trimRight();
    if (note.body.trimRight() == asSaved) {
      // A meeting's better phrases are its transcript again, under whatever stands above it (the title, its summary),
      // with the speakers its words named kept on them (lib/meet/speakers.dart `namedTranscript`; Matt, 2026-10-26),
      // and unnamed, as before, where they named none.
      final better = job.meeting == true ? withTranscript(note.body, namedTranscript(refined, note.body) ?? renderTranscript(refined)) : refinedBody(job, refined);
      try {
        await updateNote(job.id, ours && summarySection(better, kept) == null ? withSummary(better, section.text, kept: kept) : better, note.revision);
      } catch (_) {
        // The note moved on between the read and the write: its words are the person's, and stay.
      }
    }
    try {
      await setNoteRecording(job.id, job.recordingMs, refinedSegments(job, refined));
    } catch (_) {
      // The tape keeps the phrases it had.
    }
  }

  void _finish(RefineJob job) {
    _writeQueue(_readQueue().where((j) => !_same(j, job)).toList());
    _syncPending();
  }

  // ---- listening again for a review --------------------------------------------------------------------------------

  /// The review after a recording runs this take's pass itself, now, and shows its progress instead of letting the
  /// queue do it later: the careful words are what the fast ones are checked against. Answers the better phrases,
  /// commands included (the review compares like with like), or null when this phone cannot listen again: an old
  /// binary, better words switched off, or the larger model not there and not fetched.
  Future<List<Segment>?> listenAgain(RefineJob job, void Function(num percent) onPercent) async {
    if (!(await _canRefine())) return null;
    if (!(await _ensureRefineModel())) return null;
    final backend = this.backend!;
    final unlisten = backend.events.listen((event) {
      if (event is CaptureEventRefineProgress && event.id == job.id) onPercent(event.percent);
    });
    try {
      return await backend.refine(id: job.id, fromMs: job.fromMs, promptTail: job.promptTail);
    } finally {
      unawaited(unlisten.cancel());
    }
  }

  /// The recording's phrases after a review: the better ones, commands left out, for the tape's transcript.
  Future<void> keepBetterPhrases(RefineJob job, List<Segment> refined) async {
    try {
      await setNoteRecording(job.id, job.recordingMs, refinedSegments(job.copyWith(tries: 0), refined));
    } catch (_) {
      // The tape keeps the phrases it had.
    }
  }

  /// No queued pass runs while a review is on screen: the review's own pass and its model want the cores.
  void holdRefining(bool on) => _hold(on);
}

/// The better words of a note, and the larger model's download, on the app's record of running work.
String refineJobId(String noteId) => 'refine:$noteId';
const String refineModelJobId = 'refine-model';

/// A caught thing as words (`core/failure.ts` `failureText`): an error's message, or the thing itself as text.
String _failureText(Object failure) {
  if (failure is String) return failure;
  final text = failure.toString();
  for (final lead in const ['Exception: ', 'Bad state: ']) {
    if (text.startsWith(lead)) return text.substring(lead.length);
  }
  return text;
}
