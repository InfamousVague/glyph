import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/ai_strip.dart' show AiStrip;
import 'package:ghost_md/plugins/claude/claude.dart' show claudeHandle;
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/note_ai.dart';
import 'package:ghost_md/ai/summaries.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/recorder.dart';
import 'package:ghost_md/commands/command_bar.dart';
import 'package:ghost_md/commands/palette.dart';
import 'package:ghost_md/editor/editor.dart' show ChangeSpec, TransactionSpec;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/marks/marks.dart' show wispStill;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/format/gist.dart' show forgetGistRunner;
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/voice_wiring.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/tapes/note_tape.dart';
import 'package:ghost_md/tapes/player.dart' show TapePlayer;

import '../ai/fake_backend.dart';
import '../support/render.dart';
import '../tapes/fake_player.dart';

/// The AI in the app put together (lib/root): one `NoteAi` to an open note where there is an engine, with its
/// extensions in the editor, its layer over the page, and a run from the More sheet; and none of it without one.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  late FakeAiBackend backend;

  tearDown(() => useAiBackend(const NoAiBackend()));

  Voice voiceFor(SampleLibrary notes, {required bool engine, bool present = true, Summaries? summaries}) {
    if (engine) {
      backend = FakeAiBackend(generation: 30)
        ..answers['ai_models'] = [
          {'id': 'qwen3.5-2b', 'file': 'Qwen3.5-2B-Q4_K_M.gguf', 'bytes': 1280835840, 'present': present, 'path': present ? '/models/q' : null},
        ]
        ..answers['ai_device'] = {'cores': 8, 'totalRamBytes': 8000000000};
      useAiBackend(backend);
    }
    return Voice(
      recorder: Recorder(
        engine: CaptureEngine(backend: null, hasNativeGeneration: (_) async => true),
        store: LibraryRecorderStore(notes),
        native: false,
        simulate: false,
        enqueueRefine: (_) {},
        setRecorderLive: (_) {},
      ),
      models: engine ? ModelsController() : null,
      summaries: summaries,
    );
  }

  /// The summary queue over a library, with nothing of the phone behind it (lib/ai/summaries.dart).
  Summaries summariesOver(SampleLibrary notes, Stored kept) => Summaries(
        isTauri: () => true,
        preferences: () => preferences.value,
        stored: kept,
        refineHeld: () => false,
        refinePending: (_) => false,
        onRefineHold: (_) => () {},
        canNotifyNow: () => false,
        recordingJobState: () async => const [],
        takeRecordingResult: (_) async => null,
        writeUpOnHost: (_, _) => false,
        answerHost: (_, _) => () {},
        getNote: notes.get,
        updateNote: notes.update,
        isTrashed: (_) => false,
        syncNow: () async {},
        syncSettled: () async {},
        record: (_, _) async {},
        visible: () => true,
        onVisible: (_) => () {},
        onNotesChanged: (_) => () {},
        sendJobConfig: () async {},
      );

  Future<SampleLibrary> open(WidgetTester tester, {required bool engine, bool present = true, Summaries? Function(SampleLibrary notes, Stored kept)? summaries, TapePlayer? tapePlayer}) async {
    final library = SampleLibrary.seeded();
    final kept = MemoryStored();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        library: library,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        stored: kept,
        voice: voiceFor(library, engine: engine, present: present, summaries: summaries?.call(library, kept)),
        tapePlayer: tapePlayer,
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    return library;
  }

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    // The gists' runner and a run's own waits are the app's, not a screen's: let them come due.
    await tester.pump(const Duration(seconds: 30));
  }

  testWidgets('with no model on the phone the gists\' runner is shown nothing, and the home page\'s first cards once one is there', (tester) async {
    forgetGistRunner();
    await open(tester, engine: true, present: false);
    // Shown notes owed a line and no model to write one, the runner asked the engine for its models every 800 ms
    // and told the whole app twice each time, for as long as the app was open. Thirty seconds on, nothing has asked
    // but the catalogue's own readings.
    final before = backend.calls('ai_models').length;
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(backend.calls('ai_models').length, before, reason: 'the runner has nothing to ask about');
    expect(backend.calls('ai_generate'), isEmpty);
    // A model arrives (a download ended): the home page's cards are the runner's, and it writes for one.
    backend.answers['ai_models'] = [
      {'id': 'qwen3.5-2b', 'file': 'Qwen3.5-2B-Q4_K_M.gguf', 'bytes': 1280835840, 'present': true, 'path': '/models/q'},
    ];
    // The catalogue's answer comes outside the test's clock, and so does the runner's first wait (a second and a
    // half) begun as it is heard.
    await tester.runAsync(() async {
      await tester.widget<GhostRoot>(find.byType(GhostRoot)).voice!.models!.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 1800));
    });
    await tester.pump(const Duration(seconds: 1));
    expect(backend.calls('ai_models').length, greaterThan(before + 1), reason: 'the runner looked for the smallest model');
    forgetGistRunner();
    await close(tester);
  });

  testWidgets('a note has the AI\'s layer over its page, its rows in More and its blanks drawn, where there is an engine', (tester) async {
    final library = await open(tester, engine: true);
    final note = library.value.firstWhere((note) => noteTitle(note.body) == 'Packing');
    shellOf(tester).openNote(note.id);
    await settle(tester);
    expect(find.byType(NoteAiLayer), findsOneWidget);
    final screen = tester.state<NoteScreenState>(find.byType(NoteScreen));
    expect(tester.widget<NoteScreen>(find.byType(NoteScreen)).seams.onAi, isNotNull);
    // The editor was told the motion it may use, and the layer's AI holds this editor.
    final view = screen.view!;
    expect(view.state.facet(wispStill), isFalse);
    final ai = tester.widget<NoteAiLayer>(find.byType(NoteAiLayer)).ai;
    expect(identical(ai.view, view), isTrue);
    expect(ai.noteId, note.id);
    // A run asked for from the More sheet reaches the engine with the model that is on the phone.
    backend.script('A shorter Packing.');
    tester.widget<NoteScreen>(find.byType(NoteScreen)).seams.onAi!(view, 'summarize');
    await settle(tester, 8);
    expect(backend.requests, isNotEmpty);
    expect(backend.requests.first['model'], 'qwen3.5-2b');
    // The strip is up for the run: the page keeps its room clear under the header, by what the layer measured.
    final layer = tester.widget<NoteAiLayer>(find.byType(NoteAiLayer));
    expect(layer.onRoom, isNotNull);
    final room = tester.widget<NoteScreen>(find.byType(NoteScreen)).seams.headRoom!;
    final strip = tester.getSize(find.byType(AiStrip));
    if (strip.height > 0) expect(room.value, strip.height + 8);
    await tester.pump(const Duration(seconds: 2));
    // Claude's page reads who is signed in from the app: nobody, in a build with no account.
    expect(claudeHandle, isNotNull);
    expect(claudeHandle!(), isNull);
    await close(tester);
  });

  // Unwired 5 (docs/PARITY.md): the palette's This note commands. `paletteDoingFor` was given no `setView` and no
  // `noteAi`, and the world no count of blanks, so none of the five was ever offered (App.tsx `paletteDoing`).
  testWidgets('the palette offers the open note its view and its runs, and Fill the blanks once it has one', (tester) async {
    final library = await open(tester, engine: true);
    final note = library.value.firstWhere((note) => noteTitle(note.body) == 'Packing');
    shellOf(tester).openNote(note.id);
    await settle(tester);
    final bar = tester.widget<CommandBar>(find.byType(CommandBar));
    Map<String, PaletteCommand> commands() => {for (final command in paletteCommands(bar.worldNow!(), bar.doingNow!())) command.descriptor.id: command};
    final offered = commands();
    expect([for (final id in offered.keys) if (id.startsWith('note:')) id].take(5), ['note:speak', 'note:view', 'note:fix', 'note:shape', 'note:continue']);
    expect(offered['note:view']!.descriptor.label, 'Show it formatted');
    expect(offered.containsKey('note:fill'), isFalse);

    // Show it formatted is the preference the note's own switch writes.
    offered['note:view']!.run();
    await tester.pump();
    expect(preferences.value.noteView, 'formatted');
    expect(commands()['note:view']!.descriptor.label, 'Show the marks');

    // A run goes through the note's screen, as a spoken instruction does, and reaches the engine.
    backend.script('Packing, spelled right.');
    offered['note:fix']!.run();
    await settle(tester, 8);
    expect(backend.requests, isNotEmpty);
    await tester.pump(const Duration(seconds: 2));

    // A blank typed in the note: counted half a second after the typing stops, and Fill the blanks is offered.
    final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.length, insert: '\n\nThe capital of France is {?the capital of France}.'), userEvent: 'input.type'));
    await settle(tester, 8);
    expect(commands()['note:fill']?.descriptor.label, 'Fill the blanks');
    await close(tester);
  });

  // Unwired 7 (docs/PARITY.md): `NoteTape` was never given its `queue`, nor `behind`, so the tape said nothing of
  // its summary and Summarize stayed pressable in the middle of a run (tapes/NoteTape.tsx `useSummaries`,
  // `useRefining`, `useRun`; NoteScreen.tsx `behind: summaryBehind(note.id, tape.length)`).
  testWidgets('a spoken note\'s tape says what the queues say of its summary', (tester) async {
    late Summaries queue;
    final library = await open(tester, engine: true, summaries: (notes, kept) => queue = summariesOver(notes, kept), tapePlayer: FakeTapePlayer(lengths: const {}));
    final note = library.value.firstWhere((note) => noteTitle(note.body) == 'Packing');
    Note taped(int ms) => Note(id: note.id, body: library.noteOf(note.id)!.body, createdAt: note.createdAt, updatedAt: note.updatedAt, source: NoteSource.capture, recordingMs: ms, segments: const [Segment(text: 'Bring the long lens', startMs: 0, endMs: 2000)], revision: library.noteOf(note.id)!.revision);
    await tester.runAsync(() => library.apply(taped(4000)));
    await settle(tester, 2);
    shellOf(tester).openNote(note.id);
    await settle(tester);
    NoteTape tape() => tester.widget<NoteTape>(find.byType(NoteTape, skipOffstage: false));
    expect(tape().summary, isNotNull);
    expect((tape().queue.summarizing, tape().queue.held), (false, false));
    expect(find.text('Summarize', skipOffstage: false), findsOneWidget);

    // Summarize pressed: queued, started in the open note, and the tape says so until the words come.
    final words = Completer<Object?>();
    backend.answers['ai_generate'] = (Object? args) => words.future;
    tape().summary!.ask(false);
    await settle(tester, 8);
    expect(tape().queue.summarizing, isTrue);
    expect(find.text('Summarizing', skipOffstage: false), findsOneWidget);
    expect(find.text('Summarize', skipOffstage: false), findsNothing);
    words.complete({'text': 'Pack the long lens.'});
    await settle(tester, 12);
    await tester.pump(const Duration(seconds: 2));
    await settle(tester, 4);
    expect(tape().queue.summarizing, isFalse);
    expect(queue.useSummaries.value.pending, isEmpty);
    expect(tape().summary!.behind, isFalse);
    expect(find.text('Summary is from before the last take.', skipOffstage: false), findsNothing);

    // A take added since: the tape has grown past what the summary was written for.
    await tester.runAsync(() => library.apply(taped(9000)));
    await settle(tester, 4);
    expect(tape().summary!.behind, isTrue);
    expect(find.text('Summary is from before the last take.', skipOffstage: false), findsOneWidget);
    await close(tester);
  });

  testWidgets('a note has none of it in an app with no engine', (tester) async {
    final library = await open(tester, engine: false);
    shellOf(tester).openNote(library.value.firstWhere((note) => noteTitle(note.body) == 'Packing').id);
    await settle(tester);
    expect(find.byType(NoteAiLayer), findsNothing);
    expect(tester.widget<NoteScreen>(find.byType(NoteScreen)).seams.onAi, isNull);
    await close(tester);
  });
}
