// The AI in the open note (lib/ai/note_ai.dart, a port of `src/app/editor/useNoteAi.ts`). The page has no test of
// the hook by itself (its parts have their own, and the note screen's cover it drawn); these are the port's, one for
// each thing the hook did, over a real editor with `noteAiExtensions` and the strip's layer over it.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/ai_strip.dart';
import 'package:ghost_md/ai/available.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/log.dart';
import 'package:ghost_md/ai/marks.dart';
import 'package:ghost_md/ai/note_ai.dart';
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/ai/summary_ask.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/ai/ai_changes.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';
import 'fake_backend.dart';

/// A model that answers when the test says so.
class Model {
  Model(this.options);

  final RunOptions options;
  final Completer<Output> _done = Completer<Output>();

  Run get run => Run(
        done: _done.future,
        cancel: () {
          if (!_done.isCompleted) _done.completeError(StateError('cancelled'));
        },
      );

  void write(String partial) => options.onProgress(Progress(id: 'x', phase: Phase.generating, promptTokens: 10, promptTokensDone: 10, outputTokens: 5, tokensPerSecond: 9, elapsedMs: 500, partial: partial));
  void finish(String text) => _done.complete(Output(text: text, promptTokens: 10, outputTokens: 12, ms: 900, tokensPerSecond: 9));
}

const qwen = {'id': 'qwen3.5-4b', 'file': 'qwen3.5-4b.gguf', 'bytes': 2740937888, 'present': true, 'path': '/m'};

void main() {
  late FakeAiBackend phone;
  late AvailabilityController availability;
  final models = <Model>[];
  final said = <AiToast>[];
  final felt = <HapticKind>[];
  final made = <NoteAi>[];
  var flushed = 0;
  SummaryStarter? starter;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// A phone with a model on it, and the answer in.
  Future<void> ready({List<Object?> on = const [qwen]}) async {
    phone.answers['ai_models'] = on;
    availability = AvailabilityController(ios: false);
    for (var i = 0; i < 20 && availability.availability.waiting; i += 1) {
      await settle();
    }
  }

  (NoteAi, EditorView) open(String doc, {String noteId = 'n'}) {
    late EditorView view;
    final ai = NoteAi(
      noteId: noteId,
      flush: () => flushed += 1,
      body: () => view.state.doc.toString(),
      wisp: () => false,
      toast: said.add,
      onGetModel: () {},
      availability: availability,
      openForSummaries: (id, given) => starter = given,
    );
    made.add(ai);
    view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions(more: noteAiExtensions(ai))));
    addTearDown(view.destroy);
    ai.attach(view);
    return (ai, view);
  }

  setUp(() {
    useStored(MemoryStored());
    forgetAllRuns();
    models.clear();
    said.clear();
    felt.clear();
    flushed = 0;
    starter = null;
    phone = FakeAiBackend(generation: 30);
    useAiBackend(phone);
    phone.answers['ota_status'] = {'nativeGeneration': 30, 'nativeVersion': '1.15.0'};
    noteAiFelt = ([kind = HapticKind.light]) => felt.add(kind);
    simulateRuns((options) {
      final model = Model(options);
      models.add(model);
      return model.run;
    });
  });

  tearDown(() {
    for (final ai in made) {
      ai.dispose();
    }
    made.clear();
    availability.dispose();
    forgetAllRuns();
    simulateRuns(null);
    noteAiFelt = fireMotor;
  });

  group('the AI in the open note', () {
    test('flushes what is typed, starts the run, lands its lines as tracked changes and counts the marks', () async {
      await ready();
      final (ai, view) = open('call sam\nbuy eggs\n');
      var told = 0;
      ai.addListener(() => told += 1);
      ai.runAi(RunKind.format);
      expect(flushed, 1);
      expect(felt, [HapticKind.selection]);
      expect(ai.runningKind, RunKind.format);
      models[0].write('# Call Sam\n');
      expect(view.state.doc.toString(), '# Call Sam\nbuy eggs\n');
      await settle();
      expect(ai.marks, greaterThan(0));
      expect(told, greaterThan(0));
      models[0].finish('# Call Sam\n- Buy eggs\n');
      await settle();
      expect(ai.runningKind, isNull);
      expect(view.state.doc.toString(), endsWith('# Call Sam\n- Buy eggs\n'));
      expect(runsOf('n')[0].before, 'call sam\nbuy eggs\n');
    });

    test('says why it cannot run, with the way to a model where getting one is the fix', () async {
      await ready(on: const []);
      final (ai, _) = open('call sam\n');
      ai.runAi(RunKind.format);
      expect(models, isEmpty);
      expect(said.single.message, availability.availability.reason);
      expect(said.single.actionLabel, availability.availability.get == null ? isNull : 'Get a model');
      expect(felt, isEmpty);
    });

    test('says there are no blanks for a Fill with none, and starts nothing', () async {
      await ready();
      final (ai, _) = open('call sam\n');
      ai.runAi(RunKind.fill);
      expect(said.single.message, 'No blanks for the model in this note.');
      expect(models, isEmpty);
    });

    test('runs a spoken instruction the note opened with once, when the editor and the AI are ready', () async {
      await ready();
      final (ai, _) = open('call sam\n');
      ai.ask(const NoteAsk(kind: RunKind.fix, key: 3));
      expect(models, hasLength(1));
      expect(runFor('n')!.kind, RunKind.fix);
      // The same ask drawn again runs nothing more.
      ai.ask(const NoteAsk(kind: RunKind.fix, key: 3));
      expect(models, hasLength(1));
    });

    test('keeps the marks with the note a moment after they change, and puts them back when it is opened again', () async {
      await ready();
      final (_, view) = open('a\nNEW\nc\n');
      view.dispatch(TransactionSpec(effects: addAiChanges.of(const [AiChange(id: 'c1', runId: 'r1', from: 2, to: 5, removed: '', block: true)])));
      expect(loadMarks('n', 'a\nNEW\nc\n'), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(loadMarks('n', 'a\nNEW\nc\n'), hasLength(1));
      // Left and opened again: the marks are where they were.
      final (again, reopened) = open('a\nNEW\nc\n');
      expect(reopened.state.field(aiChangesField).single.id, 'c1');
      await settle();
      expect(again.marks, 1);
      // Keep all, from the strip, takes them away.
      again.keepAll();
      expect(reopened.state.field(aiChangesField), isEmpty);
    });

    test('undoes a run only while the note still reads as the run left it', () async {
      await ready();
      final (ai, view) = open('after\n');
      const record = RunRecord(id: 'r1', noteId: 'n', kind: RunKind.format, instruction: null, model: 'qwen3.5-4b', at: 0, ms: 0, outputTokens: 0, outcome: RunOutcome.done, message: null, truncated: false, before: 'before\n', after: 'after\n');
      recordRun(record);
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'mine ')));
      expect(ai.undoRun(record), isFalse);
      expect(said.last.message, 'The note has changed since, so that run can’t be undone.');
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, to: 5, insert: '')));
      expect(ai.undoRun(record), isTrue);
      expect(view.state.doc.toString(), 'before\n');
      expect(said.last.message, 'Put back as it was.');
      expect(felt.last, HapticKind.success);
      expect(runsOf('n')[0].before, isNull);
    });

    test('is the summary queue’s starter for its note while it is open, and not after', () async {
      await ready();
      final (ai, view) = open('# Planning call\n\nWe started with the launch.');
      expect(starter, isNotNull);
      final started = starter!(const SummaryAsk(words: 'That is the March launch settled.', model: 'qwen3.5-4b', maxTokens: 300, replace: false));
      expect(started, isA<SummaryRun>());
      expect(flushed, 1);
      expect(runFor('n')!.kind, RunKind.summarize);
      // The engine says it is writing before it has finished, as a real one always does.
      models[0].write('# March launch\nWhat the call ');
      models[0].finish('# March launch\nWhat the call settled.\n\n- Launch in March.');
      await settle();
      expect(view.state.doc.toString(), contains('## Summary\nWhat the call settled.'));
      ai.dispose();
      made.remove(ai);
      expect(starter, isNull);
    });
  });

  group('the layer over the page', () {
    setUpAll(loadAppFonts);

    testWidgets('puts the strip a space-2 under the header, tells the page the room to keep, and keeps all from it', (tester) async {
      phone.answers['ai_models'] = const [qwen];
      availability = AvailabilityController(ios: false);
      final (ai, view) = open('a\nNEW\nc\n');
      final rooms = <double>[];
      await pumpApp(tester, home: NoteAiLayer(ai: ai, top: 58, onRoom: rooms.add));
      debugDisableShadows = true;
      await tester.pump();
      // Nothing to say: nothing drawn, and no room kept.
      expect(tester.getSize(find.byType(AiStrip)).height, 0);
      view.dispatch(TransactionSpec(effects: addAiChanges.of(const [AiChange(id: 'c1', runId: 'r1', from: 2, to: 5, removed: '', block: true)])));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Past the strip's entrance.
      await tester.pump(const Duration(milliseconds: 400));
      final strip = tester.getRect(find.byKey(const ValueKey<String>('ai-strip-marks')));
      final space2 = tester.element(find.byType(AiStrip)).tokens.space(2);
      expect(strip.top, closeTo(58 + space2, 0.01));
      expect(rooms.last, closeTo(strip.height + 8, 0.01));
      await tester.tap(find.byKey(const ValueKey<String>('ai-strip-keep-all')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(view.state.field(aiChangesField), isEmpty);
      expect(rooms.last, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      // Past the editor's own waits (the blanks' pause), which a test's clock must see out.
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
