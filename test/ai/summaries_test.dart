// The summary queue (lib/ai/summaries.dart): what it writes and where, the holds it waits behind, what the recorder
// does to a run in flight and what a person's Stop does, how a job fails and is tried again, the pieces of a long
// recording, and the hand-off to an open note's editor - including a note opened while the model wrote. A port of
// src/app/ai/summaries.test.ts, case for case. The model is a fake that answers when the test says so, the note
// store a map, the better-words queue a pair of flags, and the clock a fake one.
//
// What differs from the web's file:
// - The page mocked modules; a [Summaries] is given the same stand-ins as its fields, and the model is the scripted
//   engine (fake_backend.dart) under ai/backend.dart's own `generate`, so the queue's generations and a run's
//   (ai/runs.dart) are the same fakes in one list, as they were there.
// - The clock is the widget tester's (`tester.pump`), as test/capture/refine_test.dart's is. A future the page
//   awaited in a test (`handle.done`, `cancelRun`, `landNativeResult`) is asked for and then the clock is advanced
//   by nothing, which runs it to its end.
// - `window.GlyphHost.writeUp` is the `writeUpOnHost` the queue is given, and `window.__glyph.recordingDone` the
//   handler it registered with `answerHost`. The document's visibility is a flag and the listeners of its change.
// - The page's `EditorView` is a state and a dispatch (ai_changes_test.dart `TestView`), and
//   `startNoteRun(view, id, 'summarize', availability, { recording })` is `startRecordingRun`.
// - `console.warn` spied on and silenced is the queue's `warn`, kept in a list.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/ai_changes.dart' show aiChangesState;
import 'package:ghost_md/ai/available.dart' show Available;
import 'package:ghost_md/ai/backend.dart' as ai;
import 'package:ghost_md/ai/kinds.dart' show RunKind;
import 'package:ghost_md/ai/land.dart' show Lander, LanderOptions;
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/ai/start.dart' show startRecordingRun;
import 'package:ghost_md/ai/summaries.dart';
import 'package:ghost_md/ai/summary_keep.dart';
import 'package:ghost_md/ai/summary_text.dart' show onePassChars, summarySection;
import 'package:ghost_md/capture/markdown.dart' show renderNote;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/state/state.dart' show EditorState;
import 'package:ghost_md/format/prompt.dart' show fill, notesContext, pieceContext, recordingNotesPrompt, recordingSummaryPrompt;

import 'ai_changes_test.dart' show TestView;
import 'fake_backend.dart';

bool native = true;
final Map<String, Note> notes = {};
final List<({String command, Map<String, Object?> args})> invoked = [];

/// The note store as it answers unless a case says otherwise (`invoke`'s `update_note`).
Future<Note> realUpdate(Map<String, Object?> args) async {
  final was = notes[args['id']];
  if (was == null || was.revision != args['expectedRevision']) throw StateError('the note was deleted or changed');
  final next = note(was.id, args['body']! as String, revision: was.revision + 1, recordingMs: was.recordingMs, segments: was.segments);
  notes[next.id] = next;
  return next;
}

Future<Note> Function(Map<String, Object?> args) updateAnswer = realUpdate;

Note note(String id, String body, {int revision = 1, int? recordingMs, List<Segment>? segments}) =>
    Note(id: id, body: body, createdAt: 0, updatedAt: 0, revision: revision, recordingMs: recordingMs, segments: segments);

/// The note with some of it said again (`{ ...notes.get('n1')!, … }`).
Note with_(Note was, {String? body, List<Segment>? segments}) =>
    note(was.id, body ?? was.body, revision: was.revision, recordingMs: was.recordingMs, segments: segments ?? was.segments);

/// The model: each generation asked for, answered by the test.
class Fake {
  Fake(this.request);

  /// The `request` of the `ai_generate` (the web's `options`).
  final Map<String, Object?> request;
  final Completer<Object?> _done = Completer<Object?>();
  bool cancelled = false;

  String get system => request['system']! as String;
  String get prompt => request['prompt']! as String;
  String get model => request['model']! as String;
  Future<Object?> get done => _done.future;

  void finish(String text) {
    if (_done.isCompleted) return;
    _done.complete({'text': text, 'promptTokens': 10, 'outputTokens': 10, 'ms': 100, 'cachedTokens': 0, 'prefillMs': 1, 'loadMs': 1, 'tokensPerSecond': 10, 'truncated': false});
  }

  void fail(String message) {
    if (!_done.isCompleted) _done.completeError(message);
  }
}

final List<Fake> fakes = [];
List<String> present = ['qwen3.5-4b'];
late FakeAiBackend engine;

/// The better-words queue: whether the recorder is up, which notes still wait for their words, and who follows the
/// hold.
bool refineHeld = false;
final Set<String> refinePending = {};
final Set<void Function(bool on)> refineListeners = {};
void hold(bool on) {
  refineHeld = on;
  for (final listener in refineListeners.toList()) {
    listener(on);
  }
}

int syncedNow = 0;

/// What the next `syncSettled` answers, once (`mockImplementationOnce`).
Future<void> Function()? settledOnce;

/// The phone's own write-ups (core/recordings.ts): the result each left, the state each is in, and whether the
/// phone may notify.
final Map<String, RecordingResult> phoneResults = {};
List<RecordingJobState> phoneStates = [];
List<String> phoneTaken = [];
bool phoneCanNotify = true;

/// `window.GlyphHost.writeUp`, where a case has put one: every call of it.
List<(String, bool)>? writeUp;

/// What the queue answers the activity by (`window.__glyph`).
final Map<String, void Function(String json)> glyph = {};

bool isVisible = true;
final Set<void Function()> visibleListeners = {};
final Set<void Function()> notesListeners = {};

/// The document's `visibilityState` set (`visible(...)`).
void visible(bool on) => isVisible = on;

/// `document.dispatchEvent(new Event('visibilitychange'))`.
void visibilityChanged() {
  if (!isVisible) return;
  for (final listener in visibleListeners.toList()) {
    listener();
  }
}

Preferences prefs = Preferences.defaults;
Stored kept = MemoryStored();
final List<String> warned = [];
int sentConfig = 0;

const queueKey = 'glyph-summary-queue';
List<Map<String, Object?>> queued() => (jsonDecode(kept.readText(queueKey) ?? '[]') as List).cast<Map<String, Object?>>();
List<Map<String, Object?>> updates() => [for (final call in invoked) if (call.command == 'update_note') call.args];

const phrases = [
  Segment(text: 'That is the March launch settled.', startMs: 0, endMs: 2000),
  Segment(text: 'Sam owns the press list.', startMs: 2100, endMs: 4000),
];
const answer = '# March launch settled\nWhat the call settled.\n\n- Launch is in March.\n- Sam: the press list.\n\n- [ ] Book the venue before the tenth.';
const section = '## Summary\nWhat the call settled.\n\n- Launch is in March.\n- Sam: the press list.\n\n- [ ] Book the venue before the tenth.';

late Summaries summaries;
void Function()? stop;
int changed = 0;
final List<({String id, String title})> summarized = [];

void start() => stop = summaries.startSummaries(() => changed += 1, summarized.add);

Summaries make() => Summaries(
      isTauri: () => native,
      preferences: () => prefs,
      stored: kept,
      refineHeld: () => refineHeld,
      refinePending: refinePending.contains,
      onRefineHold: (listener) {
        refineListeners.add(listener);
        return () => refineListeners.remove(listener);
      },
      canNotifyNow: () => phoneCanNotify,
      recordingJobState: () async => phoneStates,
      takeRecordingResult: (id) async {
        phoneTaken.add(id);
        return phoneResults.remove(id);
      },
      writeUpOnHost: (noteId, now) {
        writeUp?.add((noteId, now));
        return writeUp != null;
      },
      answerHost: (name, handler) {
        glyph[name] = handler;
        return () {
          if (glyph[name] == handler) glyph.remove(name);
        };
      },
      getNote: (id) async {
        invoked.add((command: 'get_note', args: {'id': id}));
        return notes[id];
      },
      updateNote: (id, body, expectedRevision) {
        final args = <String, Object?>{'id': id, 'body': body, 'expectedRevision': expectedRevision};
        invoked.add((command: 'update_note', args: args));
        return updateAnswer(args);
      },
      isTrashed: (id) => prefs.trash.containsKey(id),
      syncNow: () async => syncedNow += 1,
      syncSettled: () {
        final once = settledOnce;
        settledOnce = null;
        return once != null ? once() : Future<void>.value();
      },
      record: (kind, details) async {},
      visible: () => isVisible,
      onVisible: (listener) {
        visibleListeners.add(listener);
        return () => visibleListeners.remove(listener);
      },
      onNotesChanged: (listener) {
        notesListeners.add(listener);
        return () => notesListeners.remove(listener);
      },
      sendJobConfig: () async => sentConfig += 1,
      warn: warned.add,
    );

/// The web's `beforeEach`, inside the tester's fake time.
void begin() {
  kept = MemoryStored();
  useStored(kept);
  prefs = Preferences.defaults;
  native = true;
  present = ['qwen3.5-4b'];
  notes.clear();
  invoked.clear();
  updateAnswer = realUpdate;
  fakes.clear();
  refineHeld = false;
  refinePending.clear();
  refineListeners.clear();
  syncedNow = 0;
  settledOnce = null;
  phoneResults.clear();
  phoneStates = [];
  phoneTaken = [];
  phoneCanNotify = true;
  writeUp = null;
  glyph.clear();
  isVisible = true;
  visibleListeners.clear();
  notesListeners.clear();
  warned.clear();
  sentConfig = 0;
  engine = FakeAiBackend();
  engine.answers['ai_models'] = () => [for (final m in ai.models) ai.ModelInfo(id: m.id, file: '', bytes: m.bytes, present: present.contains(m.id), path: '')];
  engine.answers['ai_generate'] = (Object? args) {
    final fake = Fake((((args as Map)['request']) as Map).cast<String, Object?>());
    fakes.add(fake);
    return fake.done;
  };
  engine.answers['ai_cancel'] = (Object? args) {
    final id = (args as Map)['id'];
    for (final fake in fakes) {
      if (fake.request['id'] != id) continue;
      fake.cancelled = true;
      fake.fail('cancelled');
    }
    return true;
  };
  ai.useAiBackend(engine);
  notes['n1'] = note('n1', '# March launch\n\nThat is the March launch settled. Sam owns the press list.', recordingMs: 4000, segments: phrases);
  changed = 0;
  summarized.clear();
  summaries = make();
  start();
}

/// The web's `afterEach`: the runner stopped, the recorder gone, every generation over, and no timer left on the
/// clock (`vi.clearAllTimers`, which here is the runner stopped once more).
Future<void> end(WidgetTester tester) async {
  stop?.call();
  summaries.pauseSummaries(false);
  summaries.openForSummaries('n1', null);
  for (final fake in fakes) {
    fake.fail('over');
  }
  forgetAllRuns();
  await tester.advance(0);
  stop?.call();
  ai.useAiBackend(const ai.NoAiBackend());
}

/// A case, between the web's `beforeEach` and `afterEach`.
void summaryTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    begin();
    try {
      await body(tester);
    } finally {
      await end(tester);
    }
  });
}

extension on WidgetTester {
  /// The web's `vi.advanceTimersByTimeAsync` (`tick`).
  Future<void> advance(int ms) => pump(Duration(milliseconds: ms));
}

/// `expect.objectContaining`.
Matcher containing(Map<String, Object?> part) => allOf([for (final entry in part.entries) containsPair(entry.key, entry.value)]);

/// An ask as the page's `toHaveBeenCalledWith` compared it, `maxTokens` aside (`expect.any(Number)`).
({String words, String? context, String model, bool replace, String? text}) asked(SummaryAsk ask) =>
    (words: ask.words, context: ask.context, model: ask.model, replace: ask.replace, text: ask.text);

/// A whole number as `toLocaleString('en')` writes it.
String en(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

/// A tape long enough to go in two pieces: the loop both of the page's long-recording cases open with.
List<Segment> longTape() {
  final long = <Segment>[];
  var at = 0;
  while (long.fold<int>(0, (n, s) => n + s.text.length + 1) < onePassChars + 2000) {
    long.add(Segment(text: 'Something that was said at $at, at some length, to fill the tape.', startMs: at, endMs: at + 2000));
    at += 4000;
  }
  return long;
}

void main() {
  group('a summary of a closed note', () {
    summaryTest('reads the tape, writes the section under the title, keeps what it wrote, refreshes the list and says so', (tester) async {
      summaries.enqueueSummary('n1', SummaryKind.recording);
      expect(summaries.summaryPending('n1'), isTrue);
      await tester.advance(0);
      expect(fakes, hasLength(1));
      expect(fakes[0].system, recordingSummaryPrompt);
      // The tape's words, not the note's.
      expect(fakes[0].prompt, 'That is the March launch settled. Sam owns the press list.');
      expect(fakes[0].model, 'qwen3.5-4b');
      fakes[0].finish(answer);
      await tester.advance(0);
      expect(notes['n1']?.body, '# March launch\n\n$section\n\nThat is the March launch settled. Sam owns the press list.');
      final written = readSummary('n1');
      expect((written?.text, written?.model, written?.forMs), (section, 'qwen3.5-4b', 4000));
      expect(queued(), isEmpty);
      expect(changed, 1);
      expect(summarized, contains((id: 'n1', title: 'March launch')));
      // Sync before the read and after the write.
      expect(syncedNow, 2);
    });

    summaryTest('is asked for only in the app, and never for a note with no words on its tape', (tester) async {
      native = false;
      summaries.enqueueSummary('n1', SummaryKind.recording);
      expect(queued(), isEmpty);
      native = true;
      notes['n2'] = note('n2', '# Quiet', recordingMs: 900, segments: const []);
      summaries.enqueueSummary('n2', SummaryKind.recording);
      await tester.advance(0);
      expect(fakes, isEmpty);
      expect(queued(), isEmpty);
    });

    summaryTest('waits behind the note’s better words, and runs once they have come', (tester) async {
      refinePending.add('n1');
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(30000);
      expect(fakes, isEmpty);
      expect(queued(), hasLength(1));
      refinePending.remove('n1');
      await tester.advance(20000);
      expect(fakes, hasLength(1));
    });

    summaryTest('waits three seconds behind a note’s own run', (tester) async {
      final handle = startRun(const RunRequest(noteId: 'other', kind: RunKind.format, model: 'qwen3.5-4b', system: 's', prompt: 'p', maxTokens: 10));
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(0);
      // The note's own generation was asked for first; the summary's is not.
      expect(fakes, hasLength(1));
      fakes[0].finish('done');
      RunState? ended;
      unawaited(handle.done.then((state) => ended = state));
      await tester.advance(0);
      expect(ended?.phase, RunPhase.done);
      await tester.advance(3000);
      expect(fakes, hasLength(2));
      expect(fakes[1].system, recordingSummaryPrompt);
    });

    summaryTest('is cancelled by the recorder and left queued, uncounted, then runs again once the recorder has gone', (tester) async {
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(0);
      expect(fakes, hasLength(1));
      hold(true);
      await tester.advance(0);
      expect(fakes[0].cancelled, isTrue);
      expect(queued(), [containing({'id': 'n1', 'tries': 0, 'started': false})]);
      await tester.advance(60000);
      expect(fakes, hasLength(1));
      hold(false);
      await tester.advance(1500);
      expect(fakes, hasLength(2));
    });

    summaryTest('counts a job found started at launch as one try, and fails one on its third', (tester) async {
      stop?.call();
      kept.writeText(
        queueKey,
        jsonEncode([
          {'id': 'n1', 'kind': 'recording', 'tries': 1, 'started': true},
          {'id': 'n2', 'kind': 'recording', 'tries': 2, 'started': true},
        ]),
      );
      start();
      expect(queued(), [
        {'id': 'n1', 'kind': 'recording', 'tries': 2, 'started': false},
        {'id': 'n2', 'kind': 'recording', 'tries': 3, 'started': false, 'failed': true},
      ]);
    });

    summaryTest('waits a minute for a model that is not on the phone, saying so, and runs once one is', (tester) async {
      present = [];
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(0);
      expect(fakes, isEmpty);
      expect(summaries.summariesNow().needsModel.contains('n1'), isTrue);
      present = ['qwen3.5-2b'];
      await tester.advance(59999);
      expect(fakes, isEmpty);
      await tester.advance(1);
      expect(fakes, hasLength(1));
      expect(fakes[0].model, 'qwen3.5-2b');
      expect(summaries.summariesNow().needsModel.contains('n1'), isFalse);
    });

    summaryTest('publishes what the shelf and the strip read: pending while queued and running, failed after three tries, cleared on finish and drop', (tester) async {
      // Not on the page: the one note's share of it, as the at-work scene listens to it (`pendingFor`).
      final due = summaries.pendingFor('n1');
      final told = <bool>[];
      void heard() => told.add(due.value);
      due.addListener(heard);
      addTearDown(() => due.removeListener(heard));
      expect(due.value, isFalse);
      summaries.enqueueSummary('n1', SummaryKind.recording);
      expect(summaries.summariesNow().pending.contains('n1'), isTrue);
      expect(due.value, isTrue);
      expect(told, [true]);
      await tester.advance(0);
      expect(summaries.summariesNow().pending.contains('n1'), isTrue);
      for (var n = 1; n <= 3; n += 1) {
        await tester.advance(n == 1 ? 0 : 20000);
        fakes[n - 1].fail('the model fell over');
        await tester.advance(0);
      }
      expect(summaries.summariesNow().failed.contains('n1'), isTrue);
      expect(summaries.summariesNow().pending.contains('n1'), isFalse);
      summaries.retrySummary('n1');
      expect(summaries.summariesNow().failed.contains('n1'), isFalse);
      expect(summaries.summariesNow().pending.contains('n1'), isTrue);
      await tester.advance(0);
      fakes[3].finish(answer);
      await tester.advance(0);
      final now = summaries.summariesNow();
      expect([now.pending, now.native, now.waiting, now.failed, now.needsModel], everyElement(isEmpty));
      summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      expect(summaries.summariesNow().native.contains('n1'), isTrue);
      summaries.dropSummary('n1');
      expect(summaries.summariesNow().native.contains('n1'), isFalse);
    });

    summaryTest('starts nothing once the recorder has come up during the sync wait', (tester) async {
      final release = Completer<void>();
      settledOnce = () => release.future;
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(0);
      expect(fakes, isEmpty);
      hold(true);
      release.complete();
      await tester.advance(0);
      expect(fakes, isEmpty);
      expect(queued(), [containing({'id': 'n1', 'tries': 0, 'started': false})]);
      hold(false);
      await tester.advance(1500);
      expect(fakes, hasLength(1));
    });

    summaryTest('takes the model’s heading as the title of a note still wearing a meeting’s date title', (tester) async {
      notes['n1'] = with_(notes['n1']!, body: '# Meeting, 26 Sep 14:05\n\nWords.');
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(0);
      fakes[0].finish(answer);
      await tester.advance(0);
      expect(notes['n1']?.body, '# March launch settled\n\n$section\n\nWords.');
      expect(summarized, contains((id: 'n1', title: 'March launch settled')));
    });

    summaryTest('holds the write, with the answer kept, when the better words came to be owed between the run and the write', (tester) async {
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(0);
      refinePending.add('n1');
      fakes[0].finish(answer);
      await tester.advance(0);
      expect(updates(), isEmpty);
      expect(queued()[0], containing({'id': 'n1', 'text': answer, 'tries': 0}));
      refinePending.remove('n1');
      await tester.advance(20000);
      expect(fakes, hasLength(1));
      expect(notes['n1']?.body, contains(section));
    });

    summaryTest('counts a write that failed for any reason but a conflict as a try, without asking the model again', (tester) async {
      updateAnswer = (args) async => throw StateError('the disk is full');
      try {
        summaries.enqueueSummary('n1', SummaryKind.recording);
        await tester.advance(0);
        fakes[0].finish(answer);
        await tester.advance(0);
        expect(queued()[0], containing({'tries': 1, 'text': answer}));
        await tester.advance(20000);
        await tester.advance(20000);
        expect(queued()[0], containing({'tries': 3, 'failed': true}));
        expect(fakes, hasLength(1));
      } finally {
        updateAnswer = realUpdate;
      }
    });

    summaryTest('gives up after three failures twenty seconds apart, and Try again puts the job back', (tester) async {
      summaries.enqueueSummary('n1', SummaryKind.recording);
      for (var n = 1; n <= 3; n += 1) {
        await tester.advance(n == 1 ? 0 : 20000);
        expect(fakes, hasLength(n));
        fakes[n - 1].fail('the model fell over');
        await tester.advance(0);
        expect(queued()[0]['tries'], n);
      }
      expect(queued()[0]['failed'], isTrue);
      await tester.advance(120000);
      expect(fakes, hasLength(3));
      summaries.retrySummary('n1');
      expect(queued()[0], containing({'tries': 0, 'failed': false}));
      await tester.advance(0);
      expect(fakes, hasLength(4));
    });

    summaryTest('waits while the note is in the trash, and drops the job when the note is deleted for good', (tester) async {
      prefs = prefs.copyWith(trash: {'n1': 1});
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(60000);
      expect(fakes, isEmpty);
      expect(queued(), hasLength(1));
      summaries.dropSummary('n1');
      expect(queued(), isEmpty);
      prefs = prefs.copyWith(trash: {});
      await tester.advance(60000);
      expect(fakes, isEmpty);
    });

    summaryTest('leaves a native job waiting for its result, and never runs the model for it', (tester) async {
      summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      await tester.advance(60000);
      expect(fakes, isEmpty);
      expect(queued(), [
        {'id': 'n1', 'kind': 'meeting', 'tries': 0, 'native': true},
      ]);
    });

    summaryTest('starts only while the page is visible, and looks again when it is', (tester) async {
      visible(false);
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(10000);
      expect(fakes, isEmpty);
      visible(true);
      visibilityChanged();
      await tester.advance(2000);
      expect(fakes, hasLength(1));
    });
  });

  group('the section already there', () {
    String body(String section) => '# March launch\n\n$section\n\nThat is the March launch settled. Sam owns the press list.';
    const next = '# Launch\nA newer line.\n\n- [ ] Book the venue.';

    summaryTest('is replaced whole when it still reads as the app wrote it, its ticked to-dos carried', (tester) async {
      const old = '## Summary\nThe old line.\n\n- [x] Send Sam the list.\n- [ ] Book the venue.';
      keepSummary('n1', const KeptSummary(text: old, model: 'm', at: 1, forMs: 2000));
      notes['n1'] = with_(notes['n1']!, body: body(old));
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(0);
      fakes[0].finish(next);
      await tester.advance(0);
      expect(notes['n1']?.body, body('## Summary\nA newer line.\n\n- [ ] Book the venue.\n- [x] Send Sam the list.'));
    });

    summaryTest('is left alone by a job of the queue’s own when the person edited it, and replaced when they asked for that', (tester) async {
      const edited = '## Summary\nMy own words.\n\n- [ ] Book the venue.';
      keepSummary('n1', const KeptSummary(text: '## Summary\nThe old line.\n\n- [ ] Book the venue.', model: 'm', at: 1, forMs: 2000));
      notes['n1'] = with_(notes['n1']!, body: body(edited));
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(0);
      fakes[0].finish(next);
      await tester.advance(0);
      expect(notes['n1']?.body, body(edited));
      expect(queued(), isEmpty);
      expect(summarized, isEmpty);

      summaries.enqueueSummary('n1', SummaryKind.recording, replace: true);
      await tester.advance(500);
      fakes[1].finish(next);
      await tester.advance(0);
      expect(notes['n1']?.body, body('## Summary\nA newer line.\n\n- [ ] Book the venue.'));
    });

    summaryTest('reads the note again after a conflict and writes once more, then keeps the text for the next pass', (tester) async {
      var conflicts = 3;
      updateAnswer = (args) async {
        if (conflicts > 0) {
          conflicts -= 1;
          throw StateError('the note was changed');
        }
        return realUpdate(args);
      };
      try {
        summaries.enqueueSummary('n1', SummaryKind.recording);
        await tester.advance(0);
        fakes[0].finish(answer);
        await tester.advance(0);
        // Two writes tried this pass, the answer kept on the job, and no model asked again next time.
        expect(conflicts, 1);
        expect(queued()[0], containing({'id': 'n1', 'text': answer, 'tries': 0}));
        await tester.advance(20000);
        expect(fakes, hasLength(1));
        expect(notes['n1']?.body, contains(section));
        expect(queued(), isEmpty);
      } finally {
        updateAnswer = realUpdate;
      }
    });
  });

  group('a long recording', () {
    summaryTest('goes through the notes prompt in pieces, each checkpointed, and then the summary prompt over the notes', (tester) async {
      final long = longTape();
      notes['n1'] = with_(notes['n1']!, segments: long);
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(0);
      expect(fakes, hasLength(1));
      expect(fakes[0].system, recordingNotesPrompt);
      expect(fakes[0].prompt.startsWith('${fill(pieceContext, {'n': 1, 'm': 2})}\n\n'), isTrue);
      expect(fakes[0].prompt.startsWith('Part 1 of 2 of one recording.\n\n'), isTrue);
      // The recorder up as the first piece ends: the next piece waits for it to go, the finished one kept.
      fakes[0].finish('- The first half.');
      hold(true);
      await tester.advance(0);
      expect(queued()[0]['pieces'], ['- The first half.']);
      expect(fakes, hasLength(1));
      hold(false);
      await tester.advance(1500);
      expect(fakes[1].prompt.startsWith('${fill(pieceContext, {'n': 2, 'm': 2})}\n\n'), isTrue);
      fakes[1].finish('- The second half.\n- [ ] Book the venue.');
      await tester.advance(0);
      expect(fakes[2].system, recordingSummaryPrompt);
      final words = renderNote(long).plain.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
      final parts = fill(notesContext, {'words': en(words)});
      expect(fakes[2].prompt, '$parts\n\n- The first half.\n\n- The second half.\n- [ ] Book the venue.');
      expect(parts, contains('about ${en(words)} words'));
      expect(en(words), contains(','));
      expect(parts, contains('measured against that, not against these notes'));
      fakes[2].finish(answer);
      await tester.advance(0);
      expect(notes['n1']?.body, contains(section));
      expect(queued(), isEmpty);
    });

    summaryTest('starts at the piece after the last one checkpointed', (tester) async {
      notes['n1'] = with_(notes['n1']!, segments: longTape());
      kept.writeText(
        queueKey,
        jsonEncode([
          {
            'id': 'n1',
            'kind': 'recording',
            'tries': 0,
            'pieces': ['- The first half.'],
          },
        ]),
      );
      stop?.call();
      start();
      await tester.advance(4000);
      expect(fakes, hasLength(1));
      expect(fakes[0].prompt.startsWith('${fill(pieceContext, {'n': 2, 'm': 2})}\n\n'), isTrue);
    });
  });

  group('an open note', () {
    summaryTest('is handed the words and lands the summary through its editor, and what landed is what is kept', (tester) async {
      final asks = <SummaryAsk>[];
      summaries.openForSummaries('n1', (ask) {
        asks.add(ask);
        final handle = startRun(RunRequest(noteId: 'n1', kind: RunKind.summarize, model: ask.model, system: recordingSummaryPrompt, prompt: ask.words, maxTokens: ask.maxTokens));
        return SummaryRun(handle);
      });
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(0);
      expect(asks.map(asked), [(words: 'That is the March launch settled. Sam owns the press list.', context: null, model: 'qwen3.5-4b', replace: false, text: null)]);
      // The run's generation is the one asked for; the queue asks for none of its own.
      expect(fakes, hasLength(1));
      fakes[0].finish(section);
      await tester.advance(0);
      final written = readSummary('n1');
      expect((written?.text, written?.model), (section, 'qwen3.5-4b'));
      expect(queued(), isEmpty);
      expect(summarized, contains((id: 'n1', title: 'March launch')));
      // Nothing written plain: the editor is the one writer of an open note.
      expect(updates(), isEmpty);
    });

    summaryTest('lands through the real editor run, and keeps the section as any body reads it, so a remake finds it unchanged', (tester) async {
      final view = TestView(EditorState.create(doc: '# March launch\n\nThat is the March launch settled.', extensions: aiChangesState()));
      const ready = Available(model: 'qwen3.5-4b', chosen: 'qwen3.5-4b');
      summaries.openForSummaries('n1', (ask) => startRecordingRun(view, 'n1', ready, ask));
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(0);
      expect(fakes, hasLength(1));
      // Landed as the note screen lands a run (ai/useLanding.ts): the finished lines through the lander.
      final lander = Lander(view, runFor('n1')!.id, const LanderOptions(wisp: false, haptic: false), view.state.doc.toString());
      fakes[0].finish(answer);
      await tester.advance(0);
      lander.finish(allLines(runFor('n1')!.text!));
      final doc = view.state.doc.toString();
      expect(doc, '# March launch\n\n$section\n\nThat is the March launch settled.');
      expect(readSummary('n1')?.text, section);
      expect(summaryUnchanged('n1', summarySection(doc, section)!.text), isTrue);
      expect(queued(), isEmpty);
      // Asked again from the strip, the run goes over the section the note has, not beside it.
      summaries.openForSummaries('n1', (ask) => startRecordingRun(view, 'n1', ready, ask));
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(500);
      expect(fakes, hasLength(2));
      expect(runFor('n1')?.scope, const RunScope(from: 16, to: 16 + section.length + 1));
    });

    summaryTest('hands the answer to the note’s editor when the note was opened while the model wrote, and writes nothing plain', (tester) async {
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(0);
      expect(fakes, hasLength(1));
      final asks = <SummaryAsk>[];
      summaries.openForSummaries('n1', (ask) {
        asks.add(ask);
        return const SummaryLanded(section);
      });
      fakes[0].finish(answer);
      await tester.advance(0);
      expect(asks.map(asked), [(words: 'That is the March launch settled. Sam owns the press list.', context: null, model: 'qwen3.5-4b', replace: false, text: answer)]);
      expect(updates(), isEmpty);
      final written = readSummary('n1');
      expect((written?.text, written?.model, written?.forMs), (section, 'qwen3.5-4b', 4000));
      expect(queued(), isEmpty);
      expect(summarized, contains((id: 'n1', title: 'March launch')));
      // An answer kept from a pass that could not write is handed over the same way at the next kick, the model not
      // asked again.
      kept.writeText(
        queueKey,
        jsonEncode([
          {'id': 'n1', 'kind': 'recording', 'tries': 0, 'text': answer},
        ]),
      );
      asks.clear();
      stop?.call();
      start();
      await tester.advance(4000);
      expect(fakes, hasLength(1));
      expect(asks.map((ask) => ask.text), [answer]);
      expect(queued(), isEmpty);
    });

    summaryTest('drops the job when the editor says the section was edited', (tester) async {
      summaries.openForSummaries('n1', (_) => const SummaryRefused('edited'));
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(0);
      expect(queued(), isEmpty);
    });

    summaryTest('leaves the job when the recorder cut the run, to land over what landed once the recorder has gone, and drops it when the person stopped it', (tester) async {
      final asks = <SummaryAsk>[];
      summaries.openForSummaries('n1', (ask) {
        asks.add(ask);
        return SummaryRun(startRun(const RunRequest(noteId: 'n1', kind: RunKind.summarize, model: 'qwen3.5-4b', system: 's', prompt: 'p', maxTokens: 10)));
      });
      summaries.enqueueSummary('n1', SummaryKind.recording);
      await tester.advance(0);
      expect(asks, hasLength(1));
      hold(true);
      await tester.advance(0);
      expect(runFor('n1')?.phase, RunPhase.stopped);
      // Uncounted, and marked to replace: the half that landed is the app's own, not an edit of the person's.
      expect(queued(), [containing({'id': 'n1', 'tries': 0, 'started': false, 'replace': true})]);
      await tester.advance(60000);
      expect(asks, hasLength(1));
      hold(false);
      await tester.advance(1500);
      expect(asks, hasLength(2));
      expect(asks.last.replace, isTrue);
      // The person's Stop, from the strip or the scene: theirs to ask for again.
      unawaited(cancelRun('n1'));
      await tester.advance(0);
      expect(queued(), isEmpty);
      await tester.advance(60000);
      expect(asks, hasLength(2));
      expect(fakes, hasLength(2));
    });
  });

  group('a native write-up', () {
    const result = RecordingResult(summary: answer, model: 'qwen3.5-2b', transcriptChars: 60, finishedAt: 1);
    RecordingJobState state(String phase, [String? waitingFor]) =>
        RecordingJobState.fromJson({'id': 'n1', 'title': 'Meeting, 26 Sep 14:05', 'phase': phase, 'waitingFor': waitingFor, 'percent': 0, 'error': null, 'updatedAt': 1});

    summaryTest('takes the result the phone left and lands it through the same write, refreshing the list and running no model, and says nothing while the phone can notify', (tester) async {
      summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      phoneResults['n1'] = result;
      await tester.advance(0);
      expect(fakes, isEmpty);
      expect(notes['n1']?.body, '# March launch\n\n$section\n\nThat is the March launch settled. Sam owns the press list.');
      final written = readSummary('n1');
      expect((written?.text, written?.model), (section, 'qwen3.5-2b'));
      expect(queued(), isEmpty);
      expect(changed, greaterThan(0));
      expect(summarized, isEmpty);
    });

    summaryTest('says it, with Open, when the phone cannot notify: the toast is the only word then', (tester) async {
      phoneCanNotify = false;
      summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      phoneResults['n1'] = result;
      await tester.advance(0);
      expect(summarized, contains((id: 'n1', title: 'March launch')));
    });

    summaryTest('lands an answer the job already holds without asking the phone: the take happened, the page died before the write', (tester) async {
      kept.writeText(
        queueKey,
        jsonEncode([
          {'id': 'n1', 'kind': 'meeting', 'tries': 0, 'native': true, 'text': answer, 'model': 'qwen3.5-2b'},
        ]),
      );
      stop?.call();
      start();
      await tester.advance(4000);
      expect(phoneTaken, isEmpty);
      expect(notes['n1']?.body, contains(section));
      expect(queued(), isEmpty);
    });

    summaryTest('makes the job for a result that has none, and lands it', (tester) async {
      phoneResults['n1'] = result;
      unawaited(summaries.landNativeResult('n1'));
      await tester.advance(0);
      expect(phoneTaken, ['n1']);
      expect(notes['n1']?.body, contains(section));
      expect(queued(), isEmpty);
    });

    summaryTest('ends the job with nothing written when the result has no summary: the transcript is in the note from the phone already', (tester) async {
      summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      phoneResults['n1'] = const RecordingResult(summary: null, model: 'qwen3.5-2b', transcriptChars: 60, finishedAt: 1);
      await tester.advance(0);
      expect(queued(), isEmpty);
      expect(notes['n1']?.body, isNot(contains('## Summary')));
      expect(updates(), isEmpty);
    });

    summaryTest('lands at once when the service says the write-up is done, and drops the job when it says cancelled', (tester) async {
      summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      await tester.advance(0);
      expect(queued(), hasLength(1));
      phoneResults['n1'] = result;
      glyph['recordingDone']!(jsonEncode({'id': 'n1', 'outcome': 'done'}));
      await tester.advance(0);
      expect(notes['n1']?.body, contains(section));
      expect(queued(), isEmpty);
      summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      glyph['recordingDone']!(jsonEncode({'id': 'n1', 'outcome': 'cancelled'}));
      await tester.advance(0);
      expect(queued(), isEmpty);
      // A push this build cannot read does nothing.
      expect(() => glyph['recordingDone']!('{'), returnsNormally);
    });

    summaryTest('wears the phase the phone’s progress file says: writing up, waiting to charge, needing a model, failed, and gone when cancelled', (tester) async {
      summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      phoneStates = [state('listening')];
      await tester.advance(0);
      expect(summaries.summariesNow().native.contains('n1'), isTrue);
      expect(summaries.summariesNow().waiting.contains('n1'), isFalse);
      phoneStates = [state('waiting', 'battery')];
      await tester.advance(15000);
      expect(summaries.summariesNow().waiting.contains('n1'), isTrue);
      expect(summaries.summariesNow().native.contains('n1'), isFalse);
      // Waiting for anything else - the heat, a dictation - is still writing up, as far as the shelf says.
      phoneStates = [state('waiting', 'thermal')];
      await tester.advance(15000);
      expect(summaries.summariesNow().native.contains('n1'), isTrue);
      expect(summaries.summariesNow().waiting.contains('n1'), isFalse);
      phoneStates = [state('needsModel')];
      await tester.advance(15000);
      expect(summaries.summariesNow().needsModel.contains('n1'), isTrue);
      expect(summaries.summariesNow().native.contains('n1'), isFalse);
      phoneStates = [state('failed')];
      await tester.advance(15000);
      expect(summaries.summariesNow().failed.contains('n1'), isTrue);
      expect(summaries.summariesNow().native.contains('n1'), isFalse);
      phoneStates = [state('cancelled')];
      await tester.advance(15000);
      expect(queued(), isEmpty);
      expect(summaries.summariesNow().failed.contains('n1'), isFalse);
    });

    summaryTest('sends Try again on a failed write-up and Write up now on a waiting one to the service, to run from the front', (tester) async {
      final asked = writeUp = [];
      summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      phoneStates = [state('failed')];
      await tester.advance(0);
      expect(summaries.summariesNow().failed.contains('n1'), isTrue);
      summaries.retrySummary('n1');
      expect(asked, contains(('n1', true)));
      // Until the phone says otherwise it is writing up again.
      expect(summaries.summariesNow().failed.contains('n1'), isFalse);
      expect(summaries.summariesNow().native.contains('n1'), isTrue);
      phoneStates = [state('waiting', 'battery')];
      await tester.advance(15000);
      expect(summaries.summariesNow().waiting.contains('n1'), isTrue);
      final before = asked.length;
      summaries.writeUpNow('n1');
      expect(asked.length, before + 1);
      expect(asked.last, ('n1', true));
      expect(summaries.summariesNow().waiting.contains('n1'), isFalse);
    });

    summaryTest('asks the service again, once, for a write-up that needed a model once one is on the phone', (tester) async {
      final asked = writeUp = [];
      present = [];
      summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      phoneStates = [state('needsModel')];
      await tester.advance(0);
      expect(summaries.summariesNow().needsModel.contains('n1'), isTrue);
      expect(asked, isEmpty);
      present = ['qwen3.5-4b'];
      await tester.advance(15000);
      expect(asked, [('n1', false)]);
      await tester.advance(15000);
      expect(asked, hasLength(1));
    });

    summaryTest('looks for a waiting result again when the page comes back to the front, and every fifteen seconds while one waits', (tester) async {
      summaries.enqueueSummary('n1', SummaryKind.meeting, native: true);
      await tester.advance(0);
      expect(phoneTaken, ['n1']);
      await tester.advance(15000);
      expect(phoneTaken, ['n1', 'n1']);
      visible(false);
      visibilityChanged();
      visible(true);
      visibilityChanged();
      await tester.advance(0);
      expect(phoneTaken, ['n1', 'n1', 'n1']);
    });
  });
}
