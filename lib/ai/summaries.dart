/// The summary queue: a recording written up on the phone, in the background, into a section under the note's title
/// (docs/DESIGN.md §127 section 2). A port of `src/app/ai/summaries.ts`.
///
/// Matt: "I'm going to start recording meetings and stuff and letting the audio be transcribed then summarized by AI
/// so I get summarized recording notes automatically". He chose the on-device model for it, after the better words,
/// and never the server.
///
/// A job a note, kept in the device's storage on capture/refine.dart's pattern, so one the phone did not get to runs
/// at the next launch. A job is queued for a meeting as it starts (shell/useCaptureRoute.ts on the phone, natively;
/// the Mac's recorder at Done, as a page job), from the tape strip's Summarize word (tapes/NoteTape.tsx), and for a
/// long voice note when the setting says so (capture/CaptureScreen.tsx). Never again on its own: a summary is remade
/// only on purpose.
///
/// What it reads is the tape, not the note: the recording's phrases as the note keeps them, commands left out.
/// A transcript past twenty thousand characters goes in pieces (ai/summary_text.dart `transcriptPieces`), each
/// piece's notes checkpointed in the job so a kill after four of five starts at the fifth, and the joined notes then
/// go through the summary prompt.
///
/// The holds, in order: the recorder or a review up (`refineHeld`); the note's better words still to come
/// (`refinePending`, before the run and again before the write); a note's own run going (`anyRunning`, three
/// seconds); a note in the trash, which gets no write-up and whose job waits; a sync in flight. The recorder wins
/// the cores: when it comes up, a run in flight is cancelled and its job left queued, uncounted, and the hold is
/// read again after every wait and before every generation, so one that arrives mid-job starts nothing more. That
/// cut is the queue's own and is told from a stop by the person (the strip's Stop, the scene's, a run of their own
/// on the note): a job the person stopped is theirs to ask for again, and is dropped. A job is marked `started`
/// before it runs, and one found `started` at launch counts that as one try, so a run that kills the app cannot kill
/// it at every launch; three tries and it is `failed`, for the shelf's Try again. No model on the phone: the job
/// waits, looks again in a minute, and the shelf says "Needs a model".
///
/// A NATIVE job (`native`, §127 sections 4 and 5) is a meeting the phone's own service writes up, with the app
/// closed: the model is never run for it here. Its result is taken when it is there (core/recordings.ts
/// `takeRecordingResult`) - on every kick, when the service says it is done (`window.__glyph.recordingDone`), when
/// the page comes back to the front, and every fifteen seconds while one waits - and landed through the same
/// `write` every page summary goes through, or handed to the note's editor when the note is open: one rule for the
/// section, one set of tests. Its state on the shelf comes from the phone's own progress files
/// (`recordingJobState`): writing up, waiting to charge (with the word to write it up now), needing a model, or
/// failed, each with the way to ask again, which goes to the service (`GlyphHost.writeUp`) rather than to a model
/// the page would run.
///
/// Two writers. A closed note is written plain by `withSummary`, through `generate()`, since a background write can
/// make no marks. An open note lands through its editor, the one writer of an open note (§126): the note screen
/// registers a starter (`openForSummaries`), the queue hands it the words, and the summary is a run of ai/runs.dart
/// whose lines land as tracked changes with Keep and Revert. A note opened while its generation ran is handed the
/// finished answer instead, and the editor lands it at once: the plain write never lands under an open editor, whose
/// next save would conflict and every save of that visit after it be dropped (editor/useNoteSaving.ts). Both place
/// and shape the section by ai/summary_text.dart's rules. On success the list is refreshed and, with the page
/// visible, a toast says "Summarized" with Open (shell/useHousekeeping.ts); for a native job only when the phone
/// cannot notify, since its notification has said it otherwise, and with notifications refused the toast is the only
/// word.
///
/// Only in Tauri: a browser has no summariser, and shows what synced.
///
/// CLAUDE, FOR MEETINGS (Matt, 2026-10-19: "when claude is enabled the meeting summary should go through claude
/// instead of gemma"; ai/summary_claude.dart, docs/CLAUDE_APP.md "Meetings"). Where Claude is chosen (the Claude
/// plugin's switch on, an API key kept on this device), a meeting's job is written up by Claude, not by a model on the
/// phone: the same pieces, the same prompts, the same two writers and rules for the section, and no "Needs a model"
/// (none is looked for). PRIVACY: the meeting's transcript then goes to Anthropic, with the person's own key, and to
/// nobody else; nothing of a long voice note's does, whose summary stays the phone's. Held by Local only, the job
/// waits for Claude (`claudeHeld`, "The summary waits for Claude") and is asked once Local only is off; it does not go
/// to the phone's model instead, since a summary is never remade on its own. A Claude failure is said in Claude's
/// words beside the job (`reasons`): a refused key or request, or a decline, fails it at once for Try again; no
/// connection, too many requests or Claude overloaded counts as a try, as a model's failure does. A Claude job may run
/// with the app off the screen (no cores are taken); every other job waits for the screen as before.
///
/// The phone's service still makes a meeting's transcript with the app closed (Whisper is the phone's). With Claude
/// chosen it is sent a config with summaries off (ai/job_config.dart), so it writes no summary; the result it leaves,
/// summary or not, makes the job a page job here (`native` false) for Claude to write up. So with the app closed, a
/// meeting's transcript arrives as before and its write-up waits until the app runs again: the service's
/// notification ("The transcript is in the note") opens the app, which takes the result and starts Claude at once,
/// as does any return to the front or a `recordingDone` while the app is alive behind another. A result whose
/// summary the phone or the Mac's core wrote anyway (a config sent before Claude was chosen; the Mac, which is sent
/// none) is put aside for Claude's.
///
/// What differs:
/// - The web's module is one queue for the page, with its state in module variables. Here it is a [Summaries], made
///   once by whoever wires the app, with the module's exported functions as its methods under the web's names.
/// - What the web imports that is not a pure function, a [Summaries] is given, each as a field under the web's name:
///   `isTauri`, the preferences, the device's storage ([Stored], where the queue is kept), the better-words queue's
///   `refineHeld`, `refinePending` and `onRefineHold`, `canNotifyNow`, the phone's write-ups (`recordingJobState`,
///   `takeRecordingResult`, `writeUpOnHost`, `answerHost`), the note store's `getNote` and `updateNote`, `isTrashed`,
///   the sync engine's `syncNow` and `syncSettled`, the feed's `record`, whether the page is visible (`visible`, the
///   document's `visibilityState`) and its coming back (`onVisible`, the document's `visibilitychange`), the notes
///   changing (`onNotesChanged`, the window's `NOTES_CHANGED`), `sendJobConfig`, and where a warning is written
///   (`console.warn`).
/// - Used as they are, not given: the model (ai/backend.dart `generate`, `listModels`, `unloadModel`), the runs
///   (ai/runs.dart `anyRunning`), `modelFor`, `presentIds`, `cannotRun`, `markCannotRun`, `keepSummary` and
///   `readSummary`, which read the app's own engine and storage ([aiBackend], [stored]) as they do for every other
///   caller; and `noteTitle`, which is pure (core/note_text.dart).
/// - The module's `onRefineHold(pauseSummaries)`, made as it loaded, is made as a [Summaries] is constructed.
/// - `useSummaries` is [Summaries.useSummaries], an [ExternalStore] a widget listens to.
/// - `SummaryAsk`, `SummaryStarted` and `SummaryStarter` live in ai/summary_ask.dart and are handed on from here.
///   `RecordingJobState` and `RecordingResult` (`core/recordings.ts`) are here, with the JSON Rust answers read by
///   their `fromJson`; a phase this build has no word for is [RecordingJobPhase.other], which the shelf reads as
///   writing up, as the page read any word it did not test for.
/// - A [SummaryJob] is a class, written with the web's keys in one fixed order (the page's spread kept whichever
///   order the keys were first set in); a `kind` that is neither word reads as a recording's, and `tries` that is
///   not a number as 0.
/// - `patch(id, change)` takes the job's next self as a function of the job, where the page spread a partial.
/// - `throw new Error(…)` is an [AiFailure], whose message `failureText` reads.
/// - `typeof document === 'undefined'` has nothing to ask here: `visible` answers.
/// - A push from the service that is JSON but no object is ignored, where the page's handler threw in a promise
///   nobody awaited. The feed's `record` is likewise never let fail the queue.
/// - `toLocaleString('en')` is written out: a whole number with a comma between its thousands.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../capture/markdown.dart' show renderNote;
import '../claude/messages_api.dart' show ClaudeCancelled, ClaudeError;
import '../capture/meeting_live.dart' show ExternalStore;
import '../core/item_syntax.dart' show jsTrim;
import '../core/note.dart' show Note, Segment;
import '../core/note_text.dart' show noteTitle;
import '../core/preferences.dart' show Preferences;
import '../core/stored.dart';
import '../format/prompt.dart' show fill, notesContext, pieceContext, recordingNotesBudget, recordingNotesPrompt, recordingSummaryBudget, recordingSummaryPrompt, temperature;
import 'available.dart' show modelFor, presentIds;
import 'backend.dart' show AiFailure, ModelInfo, Run, RunOptions, generate, listModels, unloadModel;
import 'runs.dart' show RunHandle, RunPhase, anyRunning;
import 'summary_ask.dart';
import 'summary_claude.dart' show ClaudeWriting, MeetingClaude, claudeLasting;
import 'summary_keep.dart' show KeptSummary, keepSummary, readSummary;
import 'summary_text.dart' show carryTicked, shapeSummary, summaryHeading, summarySection, transcriptPieces, withSummary;
import 'support/failure.dart' show failureText;
import 'support/runnable.dart' show cannotRun, isTemplateFailure, markCannotRun;
import 'support/watched.dart';

export 'summary_ask.dart';

/// What a job is of (`SummaryKind`); [name] is the web's word.
enum SummaryKind {
  meeting,
  recording;

  /// The kind a kept job names; a recording's for a word this build does not know.
  static SummaryKind of(Object? word) => word == 'meeting' ? SummaryKind.meeting : SummaryKind.recording;
}

/// One note's summary, as the queue keeps it (`SummaryJob`).
@immutable
class SummaryJob {
  const SummaryJob({
    required this.id,
    required this.kind,
    this.tries = 0,
    this.started,
    this.pieces,
    this.text,
    this.model,
    this.native,
    this.failed,
    this.replace,
  });

  /// The note.
  final String id;
  final SummaryKind kind;
  final int tries;

  /// Set as the run starts and cleared as it ends however it ends: found set at launch, the run killed the app.
  final bool? started;

  /// The notes on each finished piece of a long transcript, in order: the checkpoint.
  final List<String>? pieces;

  /// The model's finished answer, kept when the write did not go through, so the next kick writes without asking
  /// again.
  final String? text;

  /// Which model wrote `text`, for a native result, whose model the page did not choose.
  final String? model;

  /// The write-up runs natively, with the app closed (§127 section 4): the job waits here for its result.
  final bool? native;

  /// The queue gave up: three tries. Try again clears it.
  final bool? failed;

  /// Replace the section the note has even if it was edited: the strip's Replace was tapped.
  final bool? replace;

  /// The web's spread: this job with some of it said again.
  SummaryJob copyWith({int? tries, bool? started, List<String>? pieces, String? text, String? model, bool? native, bool? failed, bool? replace}) => SummaryJob(
        id: id,
        kind: kind,
        tries: tries ?? this.tries,
        started: started ?? this.started,
        pieces: pieces ?? this.pieces,
        text: text ?? this.text,
        model: model ?? this.model,
        native: native ?? this.native,
        failed: failed ?? this.failed,
        replace: replace ?? this.replace,
      );

  /// The job as the queue writes it: the web's keys, and none for what is absent.
  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'tries': tries,
        if (started != null) 'started': started,
        if (pieces != null) 'pieces': pieces,
        if (text != null) 'text': text,
        if (model != null) 'model': model,
        if (native != null) 'native': native,
        if (failed != null) 'failed': failed,
        if (replace != null) 'replace': replace,
      };

  /// A job as the queue kept it, or null for anything without an id.
  static SummaryJob? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String) return null;
    final tries = raw['tries'];
    final pieces = raw['pieces'];
    bool? flag(String key) => raw[key] is bool ? raw[key] as bool : null;
    return SummaryJob(
      id: id,
      kind: SummaryKind.of(raw['kind']),
      tries: tries is num && tries.isFinite ? tries.round() : 0,
      started: flag('started'),
      pieces: pieces is List ? [for (final piece in pieces) if (piece is String) piece] : null,
      text: raw['text'] is String ? raw['text'] as String : null,
      model: raw['model'] is String ? raw['model'] as String : null,
      native: flag('native'),
      failed: flag('failed'),
      replace: flag('replace'),
    );
  }
}

/// What the shelf and the strip see of the queue (`SummariesState`).
@immutable
class SummariesState {
  const SummariesState({required this.pending, required this.native, required this.waiting, required this.failed, required this.needsModel, this.claudeHeld = const <String>{}, this.reasons = const <String, String>{}});

  /// Notes whose page summary is queued or running.
  final Set<String> pending;

  /// Notes a native write-up is running for (§127 section 4).
  final Set<String> native;

  /// Notes whose native write-up waits for the phone to charge, or be above half (§127 section 4).
  final Set<String> waiting;

  /// Notes whose summary the queue gave up on, for the caption's Try again.
  final Set<String> failed;

  /// Notes whose job waits for a language model that is not on the phone.
  final Set<String> needsModel;

  /// Notes whose meeting is Claude's to write up, and waits for it: Local only is on.
  final Set<String> claudeHeld;

  /// Why a failed job's last try failed, in Claude's words, for the caption beside Try again.
  final Map<String, String> reasons;
}

/// What the service says when a write-up ends (`window.__glyph.recordingDone`) (`RecordingOutcome`); [name] is the
/// web's word.
enum RecordingOutcome { done, needsModel, failed, cancelled }

/// Where a write-up is (`RecordingJobPhase`, core/recordings.ts); [name] is the word Rust says, but for [other].
enum RecordingJobPhase {
  queued,
  listening,
  summarizing,
  waiting,
  needsModel,
  failed,
  done,
  cancelled,

  /// A word this build does not know.
  other;

  /// The phase Rust named.
  static RecordingJobPhase of(Object? word) => values.firstWhere((p) => p != other && p.name == word, orElse: () => other);
}

/// One write-up as its progress file says it (src-tauri/src/jobs.rs `Progress`, the fields the page reads)
/// (`RecordingJobState`, core/recordings.ts).
@immutable
class RecordingJobState {
  const RecordingJobState({required this.id, required this.title, required this.phase, this.waitingFor, this.percent = 0, this.error, this.updatedAt = 0});

  /// A write-up as `recording_job_state` answers it.
  factory RecordingJobState.fromJson(Map<String, Object?> json) => RecordingJobState(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        phase: RecordingJobPhase.of(json['phase']),
        waitingFor: json['waitingFor'] as String?,
        percent: json['percent'] as num? ?? 0,
        error: json['error'] as String?,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String title;
  final RecordingJobPhase phase;

  /// What a `waiting` job waits for: the battery, the heat, a dictation, or a retry after an error.
  final String? waitingFor;
  final num percent;
  final String? error;
  final int updatedAt;
}

/// What a write-up left for the page (src-tauri/src/jobs.rs `JobResult`): the model's answer, raw, or null with
/// summaries off (`RecordingResult`, core/recordings.ts).
@immutable
class RecordingResult {
  const RecordingResult({required this.summary, required this.model, this.transcriptChars = 0, this.finishedAt = 0});

  /// A result as `recording_result_take` answers it.
  factory RecordingResult.fromJson(Map<String, Object?> json) => RecordingResult(
        summary: json['summary'] as String?,
        model: json['model'] as String? ?? '',
        transcriptChars: (json['transcriptChars'] as num?)?.toInt() ?? 0,
        finishedAt: (json['finishedAt'] as num?)?.toInt() ?? 0,
      );

  final String? summary;
  final String model;
  final int transcriptChars;
  final int finishedAt;
}

const String _queueKey = 'glyph-summary-queue';
const int _maxTries = 3;

/// How long to wait before trying again after "busy", "cancelled" or a failure (`RETRY_MS`).
const int _retryMs = 20000;

/// How long to wait before looking for a model again (`NO_MODEL_MS`).
const int _noModelMs = 60000;

/// How long to wait for a note's own run to end (`RUN_WAIT_MS`).
const int _runWaitMs = 3000;

/// How often to look for a native write-up's result while one waits and the page is visible (`NATIVE_POLL_MS`).
const int _nativePollMs = 15000;

final RegExp _busy = RegExp('busy|cancelled', caseSensitive: false);
final RegExp _conflict = RegExp('changed|deleted', caseSensitive: false);
final RegExp _spaces = RegExp(r'\s+');

/// How one job went (`Outcome`).
enum _Outcome { written, left, wait }

/// A whole number as `toLocaleString('en')` writes it: a comma between its thousands.
String _counted(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i += 1) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// The summary queue: its jobs, when each runs and when it waits, and what it writes.
class Summaries {
  Summaries({
    required this.isTauri,
    required this.preferences,
    required this.stored,
    required this.refineHeld,
    required this.refinePending,
    required VoidCallback Function(void Function(bool on) listener) onRefineHold,
    required this.canNotifyNow,
    required this.recordingJobState,
    required this.takeRecordingResult,
    required this.writeUpOnHost,
    required this.answerHost,
    required this.getNote,
    required this.updateNote,
    required this.isTrashed,
    required this.syncNow,
    required this.syncSettled,
    required this.record,
    required this.visible,
    required this.onVisible,
    required this.onNotesChanged,
    required this.sendJobConfig,
    void Function(String message)? warn,
    this.claude,
  }) : warn = warn ?? debugPrint {
    onRefineHold(pauseSummaries);
  }

  /// Whether there is a native core at all (`core/tauri.ts` `isTauri()`): false is a browser, which has no
  /// summariser.
  final bool Function() isTauri;

  /// `core/preferences.ts` `preferences()`: its `formatModel` is read.
  final Preferences Function() preferences;

  /// The device's storage (`core/stored.ts`), where the queue is kept.
  final Stored stored;

  /// The better-words queue's two questions (`capture/refine.ts`): whether the recorder or a review is up, and
  /// whether a note's better words are still to come. Its `onRefineHold` is given to the constructor, which follows
  /// it with [pauseSummaries] for as long as the queue lives.
  final bool Function() refineHeld;
  final bool Function(String id) refinePending;

  /// Whether Ghost.md may notify, fresh from the host (`capture/meetingLive.ts` `canNotifyNow`).
  final bool Function() canNotifyNow;

  /// Every write-up's state, as the phone has it; an empty list on a binary older than the write-up
  /// (`core/recordings.ts` `recordingJobState`).
  final Future<List<RecordingJobState>> Function() recordingJobState;

  /// The write-up's result for a note, taken once (the job's files go with it), or null: none yet, or an older
  /// binary (`core/recordings.ts` `takeRecordingResult`).
  final Future<RecordingResult?> Function(String id) takeRecordingResult;

  /// Queue a note's write-up with the service, now or when the phone is charging; false where there is no service
  /// (`core/host.ts` `writeUpOnHost`).
  final bool Function(String noteId, bool now) writeUpOnHost;

  /// Answer a call from the activity by its name; answers the way to stop (`core/host.ts` `answerHost`). Asked for
  /// `recordingDone` alone, whose handler is given the JSON the service said.
  final VoidCallback Function(String name, void Function(String json) handler) answerHost;

  /// The note store's two (`core/store.ts`): a note whole, and a revision-checked write, which fails with words
  /// that say `changed` or `deleted` when another writer won.
  final Future<Note?> Function(String id) getNote;
  final Future<Note> Function(String id, String body, int expectedRevision) updateNote;

  /// Whether a note is in the trash (`core/trash.ts` `isTrashed`).
  final bool Function(String id) isTrashed;

  /// The sync engine's two (`core/sync/engine.ts`): sync now, and wait for a sync in flight to end.
  final Future<void> Function() syncNow;
  final Future<void> Function() syncSettled;

  /// A row in the feed (`core/notifications/record.ts` `record`): asked for `summary-written` alone, with
  /// `{noteId, title}`.
  final Future<void> Function(String kind, Map<String, Object?> details) record;

  /// Whether the app is on the screen now (the document's `visibilityState` being `visible`).
  final bool Function() visible;

  /// Calls its listener each time the app comes back to the screen; answers the way to stop (the document's
  /// `visibilitychange`, when it says `visible`).
  final VoidCallback Function(VoidCallback listener) onVisible;

  /// Calls its listener each time the notes are said to have changed; answers the way to stop (the window's
  /// `NOTES_CHANGED`, `core/store.ts`).
  final VoidCallback Function(VoidCallback listener) onNotesChanged;

  /// The write-up's configuration sent to the phone, unless it is what was sent last (ai/job_config.dart
  /// `sendJobConfig`).
  final Future<void> Function() sendJobConfig;

  /// Where a summary that failed is written down (`console.warn`).
  final void Function(String message) warn;

  /// The app's own Claude, which writes meetings up where it is chosen (ai/summary_claude.dart); none is never.
  final MeetingClaude? claude;

  // ---- the queue ---------------------------------------------------------------------------------------------------

  List<SummaryJob> _readQueue() => stored.read<List<SummaryJob>>(
        _queueKey,
        <SummaryJob>[],
        (value) => value is List ? [for (final raw in value) ?SummaryJob.fromJson(raw)] : <SummaryJob>[],
      );

  void _writeQueue(List<SummaryJob> jobs) => stored.write(_queueKey, [for (final job in jobs) job.toJson()]);

  void _patch(String id, SummaryJob Function(SummaryJob job) change) {
    _writeQueue([for (final j in _readQueue()) j.id == id ? change(j) : j]);
  }

  // ---- what the shelf and the strip see ----------------------------------------------------------------------------

  static const SummariesState _none = SummariesState(pending: <String>{}, native: <String>{}, waiting: <String>{}, failed: <String>{}, needsModel: <String>{});
  final ExternalStore<SummariesState> _summaries = ExternalStore<SummariesState>(_none);

  /// Notes whose job is waiting for a model, said by the last look.
  final Set<String> _needsModel = <String>{};

  /// Notes whose meeting waits for Claude while Local only is on, said by the last look.
  final Set<String> _claudeHeld = <String>{};

  /// Why each job's last try failed, where Claude said (kept for this run of the app).
  final Map<String, String> _reasons = <String, String>{};

  /// The phone's own write-ups, as last read (core/recordings.ts): what a native job's caption is made of.
  List<RecordingJobState> _jobStates = const [];

  /// The five sets, from the queue and the phone's write-ups: a native job wears the phase its progress file says
  /// (waiting to charge, needing a model, failed), and one the service cancelled is dropped here too.
  void _publish() {
    var queue = _readQueue();
    RecordingJobState? stateOf(String id) {
      for (final s in _jobStates) {
        if (s.id == id) return s;
      }
      return null;
    }

    final cancelled = [
      for (final j in queue)
        if (j.native == true && j.failed != true && stateOf(j.id)?.phase == RecordingJobPhase.cancelled) j.id,
    ];
    if (cancelled.isNotEmpty) {
      queue = queue.where((j) => !cancelled.contains(j.id)).toList();
      _writeQueue(queue);
      for (final id in cancelled) {
        _forgetWaits(id);
      }
    }
    final nativeJobs = queue.where((j) => j.native == true && j.failed != true).toList();
    RecordingJobPhase? phaseOf(String id) => stateOf(id)?.phase;
    _summaries.set(SummariesState(
      pending: {
        for (final j in queue)
          if (j.failed != true && j.native != true) j.id,
      },
      native: {
        for (final j in nativeJobs)
          if (!(phaseOf(j.id) == RecordingJobPhase.needsModel ||
              phaseOf(j.id) == RecordingJobPhase.failed ||
              (phaseOf(j.id) == RecordingJobPhase.waiting && stateOf(j.id)?.waitingFor == 'battery')))
            j.id,
      },
      waiting: {
        for (final j in nativeJobs)
          if (phaseOf(j.id) == RecordingJobPhase.waiting && stateOf(j.id)?.waitingFor == 'battery') j.id,
      },
      failed: {
        for (final j in queue)
          if (j.failed == true) j.id,
        for (final j in nativeJobs)
          if (phaseOf(j.id) == RecordingJobPhase.failed) j.id,
      },
      needsModel: {
        for (final j in queue)
          if (j.failed != true && j.native != true && _needsModel.contains(j.id)) j.id,
        for (final j in nativeJobs)
          if (phaseOf(j.id) == RecordingJobPhase.needsModel) j.id,
      },
      claudeHeld: {
        for (final j in queue)
          if (j.failed != true && j.native != true && _claudeHeld.contains(j.id)) j.id,
      },
      reasons: {
        for (final j in queue)
          if (j.failed == true && _reasons.containsKey(j.id)) j.id: _reasons[j.id]!,
      },
    ));
  }

  /// The queue as the shelf and the strip follow it (`useSummaries`).
  ValueListenable<SummariesState> get useSummaries => _summaries;

  /// The state as it is now, for callers outside a widget and for tests.
  SummariesState summariesNow() => _summaries.get();

  /// Whether a page summary is queued or running for the note [id], as something to listen to: the page's
  /// `useSummaries().pending.has(id)`, which the at-work scene waits on (lib/scene/at_work.dart `summaryDue`). Not
  /// on the page as a function of its own.
  ValueListenable<bool> pendingFor(String id) => Watched<bool>(() => _summaries.get().pending.contains(id), _summaries.subscribe);

  // ---- running -----------------------------------------------------------------------------------------------------

  bool _running = false;
  bool _paused = false;
  Timer? _timer;
  VoidCallback? _onChanged;
  void Function(({String id, String title}) done)? _onSummarized;

  /// The generation or run in flight, so the recorder can cancel it.
  Run? _activeRun;
  RunHandle? _activeHandle;
  ClaudeWriting? _activeClaude;

  /// The run in flight was cut by the queue itself, for the recorder. A stop from anywhere else is the person's.
  bool _cut = false;

  /// The notes open in an editor, each with the way to run a summary in it.
  final Map<String, SummaryStarter> _starters = <String, SummaryStarter>{};

  /// Who wants to know a note's transcript or summary arrived from the phone's write-up (editor/NoteScreen.tsx).
  final Set<void Function(String id)> _recordingListeners = <void Function(String id)>{};

  /// Native jobs that were asked to be written up again after a model arrived, so they are asked once.
  final Set<String> _askedAfterModel = <String>{};

  /// Ask for a summary of the note's tape. Runs once the holds are clear; a job already queued for the note is
  /// replaced.
  void enqueueSummary(String id, SummaryKind kind, {bool native = false, bool replace = false}) {
    if (!isTauri()) return;
    final queue = _readQueue().where((j) => j.id != id).toList();
    queue.add(SummaryJob(id: id, kind: kind, tries: 0, native: native ? true : null, replace: replace ? true : null));
    _writeQueue(queue);
    // A state kept for an earlier write-up of this note - cancelled, say - is not this job's: the phone is asked again.
    _jobStates = _jobStates.where((s) => s.id != id).toList();
    _askedAfterModel.remove(id);
    _reasons.remove(id);
    _publish();
    _kick();
  }

  /// Try again, from the shelf's caption: the note's job back in the queue with its tries reset. A native job's
  /// again is the service's to run (`GlyphHost.writeUp`), from the front, straight away.
  void retrySummary(String id) {
    final queue = _readQueue();
    SummaryJob? job;
    for (final j in queue) {
      if (j.id == id) {
        job = j;
        break;
      }
    }
    if (job == null) return;
    _writeQueue([for (final j in queue) j.id == id ? j.copyWith(tries: 0, failed: false, started: false) : j]);
    _reasons.remove(id);
    if (job.native == true) {
      writeUpOnHost(id, true);
      _jobStates = _jobStates.where((s) => s.id != id).toList();
    }
    _publish();
    _kick();
  }

  /// "Write up now", from the shelf's caption under a meeting waiting to charge: the service asked to run it from
  /// the front.
  void writeUpNow(String id) {
    writeUpOnHost(id, true);
    _jobStates = _jobStates.where((s) => s.id != id).toList();
    _publish();
    _kick();
  }

  /// A note deleted for good: its job goes with it. Trashed, the job waits.
  void dropSummary(String id) {
    final queue = _readQueue();
    _forgetWaits(id);
    if (!queue.any((j) => j.id == id)) return;
    _writeQueue(queue.where((j) => j.id != id).toList());
    _publish();
  }

  /// Whether the note has a job queued or running.
  bool summaryPending(String id) => _readQueue().any((j) => j.id == id && j.failed != true);

  /// Whether the note's job is a native one, waiting on the phone's own write-up.
  bool summaryNative(String id) => _readQueue().any((j) => j.id == id && j.native == true);

  /// No run starts while `on`, and the one in flight is cancelled and its job left queued, uncounted: the recorder
  /// wins the cores. Let go, the queue looks again a moment later.
  void pauseSummaries(bool on) {
    if (_paused == on) return;
    _paused = on;
    if (on) {
      if (_activeRun != null || _activeHandle != null || _activeClaude != null) _cut = true;
      _activeRun?.cancel();
      _activeHandle?.cancel();
      _activeClaude?.cancel();
    } else {
      _kick(1500);
    }
  }

  /// A note open in its editor: its summary, when its turn comes, is handed here and lands as a run of the
  /// editor's. Given null as the note is left.
  void openForSummaries(String id, SummaryStarter? starter) {
    if (starter != null) {
      _starters[id] = starter;
    } else {
      _starters.remove(id);
    }
  }

  /// Hear that the phone's write-up changed a note - its transcript landed, or its result came; answers the way to
  /// stop.
  VoidCallback onRecordingChanged(void Function(String id) listener) {
    _recordingListeners.add(listener);
    return () {
      _recordingListeners.remove(listener);
    };
  }

  /// Wire the runner to the app: called once, with what to do when a note's words changed, and what to say once a
  /// summary has landed with the page visible.
  VoidCallback startSummaries(VoidCallback changed, void Function(({String id, String title}) done) summarized) {
    _onChanged = changed;
    _onSummarized = summarized;
    // A job found started was running when the app stopped: that run counts as a try, and its third fails the job.
    final queue = _readQueue();
    if (queue.any((j) => j.started == true)) {
      _writeQueue([
        for (final j in queue)
          if (j.started == true) j.copyWith(started: false, tries: j.tries + 1, failed: j.tries + 1 >= _maxTries ? true : null) else j,
      ]);
    }
    _publish();
    // Back to the front: at once when a native result may be waiting, else a moment later.
    final offVisible = onVisible(() {
      if (visible()) _kick(_anyNative() ? 0 : 2000);
    });
    // The activity's refresh, heard as the notes changing: a native result may have come while the app was away.
    final offNotesChanged = onNotesChanged(() {
      if (_anyNative()) _kick(0);
    });
    // The service says a write-up ended: its result taken now, or its state read, and the note screen told.
    final unanswer = answerHost('recordingDone', (json) => unawaited(_recordingDone(json)));
    // Claude chosen, switched off, held or let go: the queue looks again.
    final heard = claude?.changes;
    heard?.addListener(_claudeChanged);
    _kick(4000);
    return () {
      offVisible();
      offNotesChanged();
      unanswer();
      heard?.removeListener(_claudeChanged);
      _timer?.cancel();
      _onChanged = null;
      _onSummarized = null;
    };
  }

  /// What Claude is read from changed. A write-up asked of it that may no longer be (Local only on, the plugin off,
  /// the key forgotten) is stopped and its job left queued, uncounted, as the recorder's cut leaves one; and the queue
  /// looks again, for a job that waited for Claude.
  void _claudeChanged() {
    final claude = this.claude;
    if (claude == null) return;
    final now = (chosen: claude.chosen, enabled: claude.enabled);
    if (now == _claudeWas) return;
    _claudeWas = now;
    final writing = _activeClaude;
    if (writing != null && !now.enabled) {
      _cut = true;
      writing.cancel();
    }
    if (!_running && _owed()) _kick(500);
  }

  /// What Claude was when [_claudeChanged] last looked, so a change of something else it hears is let by.
  ({bool chosen, bool enabled})? _claudeWas;

  /// A job gone or done: nothing it waited for, and no reason, is kept for it.
  void _forgetWaits(String id) {
    _needsModel.remove(id);
    _claudeHeld.remove(id);
    _askedAfterModel.remove(id);
    _reasons.remove(id);
  }

  /// Whether a job is Claude's to write up: a meeting, with Claude chosen.
  Future<bool> _forClaude(SummaryJob job) async {
    final claude = this.claude;
    if (claude == null || job.kind != SummaryKind.meeting) return false;
    try {
      await claude.load();
    } catch (_) {
      return false;
    }
    return claude.chosen;
  }

  void _kick([int delay = 0]) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: delay), () => unawaited(_runNext()));
  }

  /// Whether any job could still run, for the kick after one.
  bool _owed() => _readQueue().any((j) => j.failed != true && j.native != true);

  /// Whether a native job waits for its result.
  bool _anyNative() => _readQueue().any((j) => j.native == true && j.failed != true);

  /// What the service said when a write-up ended.
  Future<void> _recordingDone(String json) async {
    Object? said;
    try {
      said = jsonDecode(json);
    } catch (_) {
      return;
    }
    if (said is! Map) return;
    final id = said['id'];
    if (id is! String) return;
    if (said['outcome'] == RecordingOutcome.cancelled.name) {
      dropSummary(id);
      return;
    }
    await _refreshJobStates();
    if (said['outcome'] == RecordingOutcome.done.name) await landNativeResult(id);
    _publish();
    // A result made into a job for Claude is written up now, the app on the screen or not.
    if (!_running && _owed()) _kick(0);
    _onChanged?.call();
    for (final listener in _recordingListeners.toList()) {
      listener(id);
    }
  }

  /// The catalogue with what is on the phone, or nothing when it will not say (`listModels().catch(() => [])`).
  Future<List<ModelInfo>> _models() async {
    try {
      return await listModels();
    } catch (_) {
      return const [];
    }
  }

  /// The phone's write-ups read again; a note whose write-up has left listening is said to have changed, since its
  /// transcript is in it now.
  Future<void> _refreshJobStates() async {
    final was = _jobStates;
    try {
      _jobStates = await recordingJobState();
    } catch (_) {
      _jobStates = was;
    }
    for (final before in was) {
      RecordingJobState? after;
      for (final s in _jobStates) {
        if (s.id == before.id) {
          after = s;
          break;
        }
      }
      if (before.phase == RecordingJobPhase.listening && after != null && after.phase != RecordingJobPhase.listening) {
        for (final listener in _recordingListeners.toList()) {
          listener(before.id);
        }
      }
    }
    // A write-up the phone could not start on its model's chat template (GLY-2): that model is remembered as one this
    // binary cannot run, and the phone's write-up is told the model it should use instead (support/runnable.dart).
    if (_jobStates.any((s) => s.phase == RecordingJobPhase.failed && isTemplateFailure(s.error ?? ''))) {
      final model = modelFor(presentIds(await _models()), preferences().formatModel);
      if (model != null && !cannotRun(model)) {
        await markCannotRun(model);
        try {
          await sendJobConfig();
        } catch (_) {
          // Sent again at the next change (ai/job_config.dart).
        }
      }
    }
  }

  /// The first job in the queue the holds let through, if the phone can take it now. What comes next is decided by
  /// how it went: the next job half a second after one that finished, and this one again after a wait when the model
  /// was not there, the phone was busy, or the run failed. The native jobs are looked at first, every time: a result
  /// that is there is landed, and their states are read for the shelf.
  ///
  /// One look at a time: a kick that comes while one is under way (a `recordingDone`, a change of Claude's) looks
  /// again a moment after it, rather than beside it, where both could take the same job.
  Future<void> _runNext() async {
    if (_looking) {
      _kick(500);
      return;
    }
    _looking = true;
    try {
      await _lookOnce();
    } finally {
      _looking = false;
    }
  }

  bool _looking = false;

  Future<void> _lookOnce() async {
    if (_running || _paused || !isTauri()) return;
    // Off the screen, only Claude's jobs: they take no cores. The rest wait for the app to come back.
    final away = !visible();
    if (away && !(claude?.enabled ?? false)) return;
    if (!away && _anyNative()) {
      await _refreshJobStates();
      // A write-up that needed a model is asked of the service again once one is on the phone.
      if (_jobStates.any((s) => s.phase == RecordingJobPhase.needsModel)) await _afterModelArrived(presentIds(await _models()));
      for (final job in _readQueue().where((j) => j.native == true && j.failed != true).toList()) {
        await landNativeResult(job.id);
      }
      _publish();
    }
    // The hold read at its source: the same answer as `paused`, which follows it and is what the cancel needs.
    if (refineHeld()) return;
    final queue = _readQueue();
    // The first that is not failed, not native, not in the trash and not waiting for its better words.
    SummaryJob? found;
    for (final j in queue) {
      if (j.failed != true && j.native != true && !isTrashed(j.id) && !refinePending(j.id) && (!away || j.kind == SummaryKind.meeting)) {
        found = j;
        break;
      }
    }
    if (found == null) {
      if (away) return;
      // A job held only by its better words looks again once they have come; a native one is looked at again in a
      // while.
      if (queue.any((j) => j.failed != true && j.native != true && !isTrashed(j.id))) {
        _kick(_retryMs);
      } else if (_anyNative()) {
        _kick(_nativePollMs);
      }
      return;
    }
    final job = found;
    if (anyRunning()) {
      _kick(_runWaitMs);
      return;
    }
    _running = true;
    var next = 500;
    try {
      await syncSettled();
      final viaClaude = await _forClaude(job);
      final String model;
      if (viaClaude) {
        // No model is looked for: Claude's, or waiting for Claude while Local only holds it.
        final claude = this.claude!;
        if (!claude.enabled) {
          if (_claudeHeld.add(job.id) | _needsModel.remove(job.id)) _publish();
          next = _noModelMs;
          return;
        }
        if (_claudeHeld.remove(job.id) | _needsModel.remove(job.id)) _publish();
        model = claude.model;
      } else {
        if (away) return;
        if (_claudeHeld.remove(job.id)) _publish();
        final present = presentIds(await _models());
        await _afterModelArrived(present);
        final local = modelFor(present, preferences().formatModel);
        if (local == null) {
          _needsModel.add(job.id);
          _publish();
          next = _noModelMs;
          return;
        }
        if (_needsModel.remove(job.id)) _publish();
        model = local;
      }
      _patch(job.id, (j) => j.copyWith(started: true));
      _cut = false;
      final outcome = await _summarize(job, model, viaClaude: viaClaude);
      if (outcome == _Outcome.written) {
        _finish(job);
        _onChanged?.call();
      } else if (outcome == _Outcome.left) {
        _finish(job);
      } else {
        next = _retryMs;
      }
    } catch (error) {
      final message = failureText(error);
      if (_paused || _busy.hasMatch(message)) {
        next = _retryMs;
      } else {
        warn('[glyph] the summary did not come: $message');
        // Claude's own words are kept for the caption; what asking again cannot mend fails the job at once.
        if (error is ClaudeError) _reasons[job.id] = message;
        final tries = claudeLasting(error) ? _maxTries : job.tries + 1;
        _patch(job.id, (j) => j.copyWith(tries: tries, failed: tries >= _maxTries ? true : null));
      }
    } finally {
      if (_readQueue().any((j) => j.id == job.id && j.started == true)) _patch(job.id, (j) => j.copyWith(started: false));
      _running = false;
      _activeRun = null;
      _activeHandle = null;
      _activeClaude = null;
      _publish();
      if (_owed()) {
        _kick(next);
      } else if (_anyNative()) {
        _kick(_nativePollMs);
      }
    }
  }

  /// A model has come: every native job that was waiting for one is asked of the service again, once. The
  /// write-up's config is sent first and waited for (ai/job_config.dart): it still names the model the phone lacked
  /// until it is, and a job asked again before it would end "Needs a model" a second time.
  Future<void> _afterModelArrived(List<String> present) async {
    if (modelFor(present, preferences().formatModel) == null) return;
    final waiting = [
      for (final job in _readQueue())
        if (job.native == true && job.failed != true && !_askedAfterModel.contains(job.id) && _jobStates.any((s) => s.id == job.id && s.phase == RecordingJobPhase.needsModel))
          job,
    ];
    if (waiting.isEmpty) return;
    try {
      await sendJobConfig();
    } catch (failure) {
      warn('[glyph] the write-up’s configuration was not kept: $failure');
    }
    for (final job in waiting) {
      _askedAfterModel.add(job.id);
      writeUpOnHost(job.id, false);
    }
  }

  /// A native write-up's result landed, in this order: an answer the job already holds is written without asking
  /// the phone (the take happened, the page died before the write); then the phone is asked, and a result makes the
  /// job if none exists and is written through the same `write` as every page summary, or handed to the note's
  /// editor when it is open. A result with no summary (summaries off) ends the job: the transcript is in the note
  /// from Rust already.
  Future<void> landNativeResult(String id) async {
    if (!isTauri()) return;
    // A page job is being written: this result is looked at again a moment after it.
    if (_running) {
      _kick(500);
      return;
    }
    _running = true;
    try {
      final had = _jobOf(id, native: true);
      if (had?.text != null) {
        await _landText(had!, had.text!);
        return;
      }
      RecordingResult? result;
      try {
        result = await takeRecordingResult(id);
      } catch (_) {
        result = null;
      }
      if (result == null) return;
      if (!_readQueue().any((j) => j.id == id)) {
        final queue = _readQueue();
        queue.add(SummaryJob(id: id, kind: SummaryKind.meeting, tries: 0, native: true));
        _writeQueue(queue);
      }
      final summary = result.summary;
      final none = summary == null || jsTrim(summary).isEmpty;
      if (await _forClaudeNative(id, result, none: none)) {
        // Claude's to write up: the transcript is in the note, and the job is the page's now (see the header).
        _patch(id, (j) => SummaryJob(id: j.id, kind: SummaryKind.meeting, native: false, replace: j.replace));
        _jobStates = _jobStates.where((s) => s.id != id).toList();
        _askedAfterModel.remove(id);
        return;
      }
      if (none) {
        final job = _jobOf(id);
        if (job != null) _finish(job);
        return;
      }
      final model = result.model;
      _patch(id, (j) => j.copyWith(text: summary, model: model, failed: false));
      final job = _jobOf(id);
      if (job != null) await _landText(job, summary);
    } catch (error) {
      warn('[glyph] the write-up did not land: ${failureText(error)}');
    } finally {
      _running = false;
      _publish();
    }
  }

  /// Whether a native result makes its job a page job for Claude: a meeting with words heard and summaries on, and
  /// either Claude chosen (whatever summary came is put aside) or no summary written, as the config says while Claude
  /// is chosen (should Claude have stopped being chosen since, that job is the phone's model's, from here).
  Future<bool> _forClaudeNative(String id, RecordingResult result, {required bool none}) async {
    if (claude == null || preferences().summaries == 'off' || result.transcriptChars <= 0) return false;
    if (none) return true;
    return _forClaude(SummaryJob(id: id, kind: SummaryKind.meeting));
  }

  /// The note's job as the queue has it now, or null; with [native], only a native one.
  SummaryJob? _jobOf(String id, {bool native = false}) {
    for (final j in _readQueue()) {
      if (j.id == id && (!native || j.native == true)) return j;
    }
    return null;
  }

  /// A native answer into its note, the way a page answer goes: plain when closed, through its editor when open.
  Future<void> _landText(SummaryJob job, String text) async {
    final note = await getNote(job.id);
    if (note == null) {
      _finish(job);
      return;
    }
    final ask = SummaryAsk(words: '', model: job.model ?? preferences().formatModel, maxTokens: 0, replace: job.replace == true, text: text);
    final starter = _starters[job.id];
    final outcome = starter != null ? await _throughEditor(job, starter, ask) : await _write(job, text, ask, note.recordingMs ?? 0);
    if (outcome == _Outcome.written) {
      _finish(job);
      _onChanged?.call();
    } else if (outcome == _Outcome.left) {
      _finish(job);
    }
  }

  /// One job: the tape's words, in pieces when they are many, through the model, and the section into the note - by
  /// its editor when the note is open, plain when it is closed. 'left' is a section the person edited that an
  /// automatic job must not touch, a note with nothing to summarise, or a run the person stopped; 'wait' is a write
  /// that did not go through this pass, or a run the recorder cut.
  Future<_Outcome> _summarize(SummaryJob job, String model, {bool viaClaude = false}) async {
    final note = await getNote(job.id);
    if (note == null) return _Outcome.left;
    final plain = renderNote(note.segments ?? const <Segment>[]).plain;
    if (jsTrim(plain).isEmpty) return _Outcome.left;
    final pieces = transcriptPieces(plain);
    final budget = recordingSummaryBudget(plain.length);
    var words = plain;
    String? context;
    if (pieces.length > 1) {
      final notes = [...?job.pieces].take(pieces.length).toList();
      for (var n = notes.length; n < pieces.length; n += 1) {
        final piece = pieces[n];
        final output = await _run(
          model: model,
          system: recordingNotesPrompt,
          prompt: '${fill(pieceContext, {'n': n + 1, 'm': pieces.length})}\n\n$piece',
          maxTokens: recordingNotesBudget(piece.length),
          viaClaude: viaClaude,
        );
        notes.add(jsTrim(output));
        // Each finished piece is checkpointed, so a kill after four of five starts at the fifth.
        final checkpoint = [...notes];
        _patch(job.id, (j) => j.copyWith(pieces: checkpoint));
      }
      words = notes.join('\n\n');
      context = fill(notesContext, {'words': _counted(plain.split(_spaces).where((word) => word.isNotEmpty).length)});
    }
    final ask = SummaryAsk(words: words, context: context, model: model, maxTokens: budget, replace: job.replace == true);
    final starter = _starters[job.id];
    // An open note's run is the phone's model's, in its editor. Claude's answer is asked here and handed to the
    // editor whole, which lands it at once as a run's lines land, with Keep and Revert.
    if (starter != null && !viaClaude) return _throughEditor(job, starter, job.text == null ? ask : ask.withText(job.text!));
    final text = job.text ?? (await _run(model: model, system: recordingSummaryPrompt, prompt: context != null && context.isNotEmpty ? '$context\n\n$words' : words, maxTokens: budget, viaClaude: viaClaude));
    _patch(job.id, (j) => j.copyWith(text: text));
    // A long tape's context is the largest the page asks for: the engine may let it go now rather than in five
    // minutes.
    if (pieces.length > 1 && !viaClaude) unawaited(unloadModel());
    final open = _starters[job.id];
    if (open != null) return _throughEditor(job, open, ask.withText(text));
    return _write(job, text, ask, note.recordingMs ?? 0);
  }

  /// One generation, cancellable by the recorder, and not started once it is up: the phone's model's, or with
  /// [viaClaude] Claude's (whose room is its own, not [maxTokens]: ai/summary_claude.dart).
  Future<String> _run({required String model, required String system, required String prompt, required int maxTokens, bool viaClaude = false}) async {
    if (_paused) throw const AiFailure('cancelled');
    if (viaClaude) {
      final claude = this.claude!;
      if (!claude.enabled) throw const AiFailure('cancelled');
      final writing = _activeClaude = claude.write(system: system, prompt: prompt);
      try {
        return await writing.done;
      } on ClaudeCancelled {
        throw const AiFailure('cancelled');
      } finally {
        _activeClaude = null;
      }
    }
    final run = generate(RunOptions(model: model, system: system, prompt: prompt, maxTokens: maxTokens, temperature: temperature, onProgress: (_) {}));
    _activeRun = run;
    try {
      return (await run.done).text;
    } finally {
      _activeRun = null;
    }
  }

  /// The summary as a run in the note's editor: the lines land there, and the section as it landed is what is kept -
  /// the run's text less the blank line it may open with. An answer the queue already had is landed at once. A run
  /// cut by the recorder leaves its job waiting, to land over whatever half of the section landed (`replace`, since
  /// that half is the app's own); a run the person stopped is left.
  Future<_Outcome> _throughEditor(SummaryJob job, SummaryStarter starter, SummaryAsk ask) async {
    if (_paused) throw const AiFailure('cancelled');
    final started = starter(ask);
    final String landed;
    switch (started) {
      case SummaryRefused(:final reason):
        if (reason == 'edited' || reason == 'nothing') return _Outcome.left;
        throw AiFailure(reason);
      case SummaryLanded():
        landed = started.landed;
      case SummaryRun(:final handle):
        _activeHandle = handle;
        final state = await handle.done;
        _activeHandle = null;
        if (state.phase == RunPhase.stopped) {
          if (!_cut) return _Outcome.left;
          _patch(job.id, (j) => j.copyWith(replace: true));
          return _Outcome.wait;
        }
        if (state.phase != RunPhase.done) throw AiFailure(state.message ?? 'the summary did not come');
        landed = summarySection(state.text ?? '')?.text ?? '';
    }
    Note? fresh;
    try {
      fresh = await getNote(job.id);
    } catch (_) {
      fresh = null;
    }
    keepSummary(job.id, KeptSummary(text: landed, model: ask.model, at: DateTime.now().millisecondsSinceEpoch, forMs: fresh?.recordingMs ?? 0));
    _said(job, fresh?.body ?? '');
    return _Outcome.written;
  }

  /// The section into a closed note, plain: read fresh, the better words checked again, placed and shaped by
  /// ai/summary_text.dart, with the ticked to-dos of the section it replaces carried in. A note opened meanwhile is
  /// handed the answer for its editor to land instead. A conflict is read again and applied once more, then given
  /// up for this pass; the text is kept on the job, so the next kick writes it without asking the model again. Any
  /// other failure of the write counts as a try. Sync runs before the read and after the write, so the window in
  /// which another device's edit could cross it is seconds.
  Future<_Outcome> _write(SummaryJob job, String text, SummaryAsk ask, int recordingMs) async {
    final shaped = shapeSummary(text);
    // Nothing under the heading (a label alone, say) is nothing to write.
    if (shaped.section.isEmpty || shaped.section == summaryHeading) return _Outcome.left;
    await _synced();
    for (var attempt = 0; attempt < 2; attempt += 1) {
      final note = await getNote(job.id);
      if (note == null) return _Outcome.left;
      if (refinePending(job.id)) return _Outcome.wait;
      // The note was opened while the model wrote: its editor is the one writer now, and lands the answer itself.
      final starter = _starters[job.id];
      if (starter != null) return _throughEditor(job, starter, ask.withText(text));
      final kept = readSummary(job.id);
      final current = summarySection(note.body, kept?.text);
      var section = shaped.section;
      if (current != null) {
        // Never remade behind the person's back: a section that is not the app's is left as it is.
        if (!(kept != null && kept.text == current.text) && job.replace != true) return _Outcome.left;
        section = carryTicked(current.text, section);
      }
      final next = withSummary(note.body, section, title: shaped.title, kept: kept?.text);
      try {
        await updateNote(job.id, next, note.revision);
      } catch (error) {
        // Another writer won: read again. Anything else is the write failing, and a try.
        if (_conflict.hasMatch(failureText(error))) continue;
        rethrow;
      }
      keepSummary(job.id, KeptSummary(text: section, model: ask.model, at: DateTime.now().millisecondsSinceEpoch, forMs: note.recordingMs ?? recordingMs));
      await _synced();
      _said(job, next);
      return _Outcome.written;
    }
    return _Outcome.wait;
  }

  /// A sync, whose failure is not the summary's (`syncNow().catch(() => undefined)`).
  Future<void> _synced() async {
    try {
      await syncNow();
    } catch (_) {
      // The next sync carries it.
    }
  }

  /// A summary landed in its note: a row in the feed, on every device, for a person who was not looking
  /// (docs/TEAMS.md, "Kinds"); and "Summarized" with Open, when the page is visible - for the page's jobs, and for
  /// a native one only where the phone could not say it itself.
  void _said(SummaryJob job, String body) {
    final title = noteTitle(body);
    final done = (id: job.id, title: title.isNotEmpty ? title : 'Untitled');
    unawaited(Future<void>.sync(() => record('summary-written', {'noteId': done.id, 'title': done.title})).then((_) {}, onError: (Object _) {}));
    if (!visible()) return;
    if (job.native == true && canNotifyNow()) return;
    _onSummarized?.call(done);
  }

  void _finish(SummaryJob job) {
    _forgetWaits(job.id);
    _writeQueue(_readQueue().where((j) => j.id != job.id).toList());
    _publish();
  }
}
