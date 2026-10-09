// The review after a recording, run in the note (lib/ai/note_review.dart), two ways: with the script that plays both
// models (`simulatingReview`, the page's `?review`), and as a phone runs it, where each model answers when the test
// says so. A port of `src/app/ai/useNoteReview.test.tsx`, case for case.
//
// The phone: the models it has, and a thinking run that answers on cue (ai/runs.dart `simulateRuns` is the seam, as
// in runs_test.dart). Listening again and the queue it hands the take back to are the recorder's
// (capture/refine.dart), stood in for here by the [ReviewHost], so a test can say what the slower speech model
// heard, or that it failed, or leave it listening. The note store is a map with revisions.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'package:ghost_md/ai/ai_changes.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/log.dart';
import 'package:ghost_md/ai/note_review.dart';
import 'package:ghost_md/ai/review.dart';
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/capture/refine.dart' show RefineJob;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import 'ai_changes_test.dart' show TestView;
import 'fake_backend.dart';
import 'runs_test.dart' show Fake;

final Map<String, Note> notes = {};
final List<ReviewStage?> stages = [];
final List<String> said = [];
final List<Fake> runs = [];
final List<String> calls = [];
final List<RefineJob> queued = [];
final List<(RefineJob, List<Segment>)> kept = [];
final List<HapticKind> felt = [];
Future<List<Segment>?> Function(RefineJob job, void Function(num percent) onPercent) listen = (job, onPercent) async => null;

void createNote(String id, String body) => notes[id] = Note(id: id, body: body, createdAt: 0, updatedAt: 0, source: NoteSource.capture, revision: 1);

Future<void> updateNote(String id, String body, int expected) async {
  final was = notes[id];
  if (was == null || was.revision != expected) throw StateError('the note was deleted or changed');
  notes[id] = Note(id: id, body: body, createdAt: was.createdAt, updatedAt: was.updatedAt, source: was.source, revision: was.revision + 1);
}

final ReviewHost host = ReviewHost(
  getNote: (id) async => notes[id],
  listNotes: () async => notes.values.toList(),
  updateNote: updateNote,
  enqueueRefine: queued.add,
  holdRefining: (on) => calls.add('hold $on'),
  keepBetterPhrases: (job, refined) async => kept.add((job, refined)),
  listenAgain: (job, onPercent) => listen(job, onPercent),
);

TestView editor(String doc) => TestView(EditorState.create(doc: doc, extensions: aiChangesState()));

NoteReview? mounted;

/// The note, drawn: the page's `<Note review editor />`.
NoteReview show(ReviewHandoff review, int key, TestView view) {
  final made = NoteReview(host, wisp: () => false, say: said.add);
  made.addListener(() => stages.add(made.value));
  mounted = made;
  made.attach(review, key, view);
  return made;
}

void unmount() {
  mounted?.dispose();
  mounted = null;
}

/// Lets what the review is waiting on settle.
Future<void> settle() => Future<void>.delayed(Duration.zero);

Future<void> waitUntil(bool Function() test) async {
  for (var i = 0; i < 200 && !test(); i += 1) {
    await settle();
  }
  expect(test(), isTrue);
}

void main() {
  late FakeAiBackend phone;

  setUp(() {
    useStored(MemoryStored());
    notes.clear();
    stages.clear();
    said.clear();
    runs.clear();
    calls.clear();
    queued.clear();
    kept.clear();
    felt.clear();
    listen = (job, onPercent) async => null;
    phone = FakeAiBackend();
    useAiBackend(phone);
    phone.answers['ai_models'] = const <Object?>[];
    reviewFelt = ([kind = HapticKind.light]) => felt.add(kind);
    simulateRuns((options) {
      final fake = Fake(options);
      runs.add(fake);
      return fake.run;
    });
  });

  tearDown(() {
    unmount();
    forgetAllRuns();
    simulateRuns(null);
    simulatingReview = () => false;
    reviewFelt = fireMotor;
    preferences.update((_) => const Preferences());
  });

  // End to end the way it is developed: the script plays the slower speech model and the thinking model
  // (ai/review_simulation.dart), so the stages, the run and the landing are the real ones and only the models are
  // not.
  group('the review after a recording, in the note', () {
    setUp(() => simulatingReview = () => true);

    testWidgets('listens again, thinks, and lands what the slower model heard as a tracked change', (tester) async {
      const body = '# Player\n- [ ] Fix the seat bar.\n';
      createNote('n1', body);
      final view = editor(body);
      show(const ReviewHandoff(noteId: 'n1', job: null, heard: 'Fix the seat bar.', commands: [], touched: []), 1, view);
      // A quarter of a second at a time, so each stage is drawn as the strip would draw it.
      for (var i = 0; i < 40; i += 1) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      for (var i = 0; i < 400 && (mounted!.value != null || isRunning('n1')); i += 1) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pump(const Duration(milliseconds: 30));
      // Listening again is a stage of its own, with its percent climbing. (Comparing takes no time with nothing to
      // wait on, so it is gone before it is drawn.)
      final listening = [for (final stage in stages) if (stage?.what == 'Listening again' && stage!.percent != null) stage.percent!];
      expect(listening.length, greaterThan(3));
      expect(listening, [...listening]..sort());
      // The stages give way to the run, and the strip follows that like any other.
      expect(stages.last, isNull);
      expect(view.state.doc.toString(), '# Player\n- [ ] Fix the seek bar.\n');
      expect([for (final change in view.state.field(aiChangesField)) change.removed], ['- [ ] Fix the seat bar.']);
      expect(said.last, matches(RegExp(r'found 1 thing to look at\. Each is marked in the note\.$')));
      // The log has the review, and the words before and after it, for Undo.
      final logged = runsOf('n1')[0];
      expect((logged.kind, logged.outcome, logged.before, logged.after), (RunKind.review, RunOutcome.done, body, '# Player\n- [ ] Fix the seek bar.\n'));
    });

    testWidgets('runs once for its handoff, however often the note draws', (tester) async {
      const body = '# Player\n- [ ] Fix the seat bar.\n';
      createNote('n2', body);
      final view = editor(body);
      const review = ReviewHandoff(noteId: 'n2', job: null, heard: 'Fix the seat bar.', commands: [], touched: []);
      final note = show(review, 7, view);
      for (var i = 0; i < 400; i += 1) {
        await tester.pump(const Duration(milliseconds: 250));
        if (runsOf('n2').isNotEmpty && !isRunning('n2') && note.value == null && said.isNotEmpty) break;
      }
      // The note draws again with the same handoff: the review has run, and does not run again.
      note.attach(const ReviewHandoff(noteId: 'n2', job: null, heard: 'Fix the seat bar.', commands: [], touched: []), 7, view);
      for (var i = 0; i < 40; i += 1) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(runsOf('n2').where((run) => run.kind == RunKind.review), hasLength(1));
      expect(view.state.doc.toString(), '# Player\n- [ ] Fix the seek bar.\n');
    });
  });

  group('the review after a recording, on a phone', () {
    const body = '# Player\n- [ ] Fix the seat bar.\n';
    const seek = '# Player\n- [ ] Fix the seek bar.\n';

    /// What the slower speech model heard: the fast one's words, but "seek".
    const better = [Segment(text: 'Fix the seek bar.', startMs: 0, endMs: 1500)];
    const qwen = ModelInfo(id: 'qwen3.5-4b', file: 'qwen3.5-4b.gguf', bytes: 2740937888, present: true, path: '/models/qwen3.5-4b.gguf');
    const noModel = 'No language model on this phone to think it through, so only the words the slower model heard differently are marked.';

    /// The take Stop saved, as the recorder hands it over.
    RefineJob take(String id) => RefineJob(id: id, fromMs: 0, recordingMs: 1500, baseBody: '', savedBody: body, titled: true, priorSegments: const [], promptTail: '');
    ReviewHandoff handoff(String noteId, {RefineJob? job, bool noJob = false, String heard = 'Fix the seat bar.', List<String> commands = const [], List<String> touched = const []}) =>
        ReviewHandoff(noteId: noteId, job: noJob ? null : (job ?? take(noteId)), heard: heard, commands: commands, touched: touched);

    test('hands the take back to the queue, once, when the note is left while it is listening again', () async {
      createNote('p1', body);
      final heard = Completer<List<Segment>?>();
      listen = (job, onPercent) => heard.future;
      final job = take('p1');
      final view = editor(body);
      show(handoff('p1', job: job), 1, view);
      await waitUntil(() => stages.isNotEmpty && stages.last?.what == 'Listening again');
      expect(calls.last, 'hold true');
      unmount();
      // Left mid-review: the pass the queue would have run anyway is queued, and the queue is free to run it.
      expect(queued, [job]);
      expect(calls.last, 'hold false');
      // The slower model answers after all: the note is gone, so nothing thinks, lands or is queued again.
      heard.complete(better);
      await settle();
      expect(queued, hasLength(1));
      expect(kept, isEmpty);
      expect(runs, isEmpty);
      expect(view.state.doc.toString(), body);
    });

    test('marks only the words the slower model heard when there is no model to think, and says so', () async {
      createNote('p2', body);
      listen = (job, onPercent) async => better;
      final job = take('p2');
      final view = editor(body);
      show(handoff('p2', job: job), 1, view);
      await waitUntil(() => kept.isNotEmpty);
      expect(view.state.doc.toString(), seek);
      expect(said, [noModel, 'The slower model found 1 thing to look at. Each is marked in the note.']);
      expect(runs, isEmpty);
      // The better words are kept for the recording's transcript, instead of queueing a pass to hear them again.
      expect(kept.single, (job, better));
      expect(queued, isEmpty);
      // Leaving the note after the review has ended hands nothing back a second time.
      unmount();
      expect(kept, hasLength(1));
      expect(calls, ['hold true', 'hold false']);
    });

    test('says why listening again failed, and hands the take back to the queue', () async {
      createNote('p3', body);
      listen = (job, onPercent) async => throw Exception('The slower speech model could not be loaded.');
      final job = take('p3');
      final view = editor(body);
      show(handoff('p3', job: job), 1, view);
      await waitUntil(() => queued.isNotEmpty);
      expect(said, ['The slower speech model could not be loaded.', noModel]);
      expect(view.state.doc.toString(), body);
      expect(queued, [job]);
      expect(kept, isEmpty);
      unmount();
      expect(queued, hasLength(1));
      expect(calls, ['hold true', 'hold false']);
    });

    for (final outcome in [RunOutcome.stopped, RunOutcome.failed]) {
      test('lands only the words when the thinking run is ${outcome.name}, and says nothing of its own', () async {
        final id = 'p4-${outcome.name}';
        createNote(id, body);
        phone.answers['ai_models'] = const [qwen];
        listen = (job, onPercent) async => better;
        final view = editor(body);
        show(handoff(id), 1, view);
        await waitUntil(() => runs.length == 1);
        // It thinks with the model chosen for formatting, a Qwen on the phone.
        expect(runs[0].options.model, 'qwen3.5-4b');
        if (outcome == RunOutcome.stopped) {
          await cancelRun(id);
        } else {
          runs[0].fail('out of memory');
        }
        await waitUntil(() => kept.isNotEmpty);
        final logged = runsOf(id)[0];
        expect((logged.kind, logged.outcome), (RunKind.review, outcome));
        // The words the slower speech model heard still land; the strip already says what happened to the run.
        expect(view.state.doc.toString(), seek);
        expect(said, isEmpty);
        expect(felt, isEmpty);
      });
    }

    test('writes a finding for another note into that note as it is now, through the guarded write', () async {
      createNote('p5', body);
      createNote('p6', '# HelloTrade\n- buy milk\n');
      phone.answers['ai_models'] = const [qwen];
      final view = editor(body);
      show(handoff('p5', noJob: true, heard: 'Fix the seat bar. Glyph, add buy milk to HelloTrade.', commands: ['Added “buy milk” to HelloTrade.'], touched: ['p6']), 1, view);
      await waitUntil(() => runs.length == 1);
      // While the model thinks, the other note gains a line: the finding is written over that, not over what was
      // read when the review began.
      final other = notes['p6']!;
      await updateNote('p6', '${other.body}- bread\n', other.revision);
      runs[0].finish(jsonEncode([
        {'check': 'commands', 'note': 'HelloTrade', 'what': 'Oat milk, not milk', 'why': 'It was said.', 'find': 'buy milk', 'replace': 'buy oat milk'},
      ]));
      await waitUntil(() => said.length == 1);
      expect(said[0], 'Qwen3.5 4B found 1 thing to look at, 1 in another note.');
      expect((notes['p6']!.body, notes['p6']!.revision), ('# HelloTrade\n- buy oat milk\n- bread\n', 3));
      // The note on screen had nothing to change.
      expect(view.state.doc.toString(), body);
    });
  });

  group('what the review tells the note’s tag', () {
    const qwen = ModelInfo(id: 'qwen3.5-4b', file: 'qwen3.5-4b.gguf', bytes: 2740937888, present: true, path: '/models/qwen3.5-4b.gguf');
    RefineJob take(String id) => RefineJob(id: id, fromMs: 0, recordingMs: 1500, baseBody: '', savedBody: '# Player\n', titled: true, priorSegments: const [], promptTail: '');

    test('says once when it has handed its job back, naming the note', () async {
      createNote('q1', '# Player\n');
      final handedBack = <String>[];
      final stop = onReviewHandedBack(handedBack.add);
      try {
        listen = (job, onPercent) => Completer<List<Segment>?>().future;
        show(ReviewHandoff(noteId: 'q1', job: take('q1'), heard: 'Player.', commands: const [], touched: const []), 1, editor('# Player\n'));
        await waitUntil(() => stages.isNotEmpty && stages.last?.what == 'Listening again');
        expect(handedBack, isEmpty);
        unmount();
        expect(handedBack, ['q1']);
        expect(queued, hasLength(1));
      } finally {
        stop();
      }
    });

    test('gives the thinking model the words after the front matter, never where the note was written', () async {
      const tagged = '---\nlocation: 51.5074,-0.1278\nplace: "London"\n---\n# Player\n- [ ] Fix the seat bar.\n';
      createNote('q2', tagged);
      createNote('q3', '---\nlocation: 48.8566,2.3522\n---\n# HelloTrade\n- buy milk\n');
      phone.answers['ai_models'] = const [qwen];
      show(const ReviewHandoff(noteId: 'q2', job: null, heard: 'Fix the seat bar.', commands: [], touched: ['q3']), 2, editor(tagged));
      await waitUntil(() => runs.length == 1);
      final prompt = runs[0].options.prompt;
      expect(prompt, contains('# Player\n- [ ] Fix the seat bar.'));
      expect(prompt, contains('# HelloTrade\n- buy milk'));
      expect(prompt, isNot(contains('location:')));
      expect(prompt, isNot(contains('place:')));
      expect(prompt, isNot(contains('51.5074')));
    });
  });
}
