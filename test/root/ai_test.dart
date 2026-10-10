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
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/editor/ai/fill_panel.dart';
import 'package:ghost_md/ai/ai_changes.dart' show aiChangesField;
import 'package:ghost_md/ai/kinds.dart' show RunKind;
import 'package:ghost_md/editor/editor.dart' show ChangeSpec, EditorSelection, TransactionSpec;
import 'package:ghost_md/editor/plus/plus.dart' show PlusLayer, PlusLook, plusViewOf;
import 'package:ghost_md/root/note_desk.dart' show NoteDesk, NoteDeskState;
import 'package:ghost_md/editor/view/text_panel.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/phone_connection.dart' show Connection;
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
import 'package:ghost_md/settings/kit/settings_kit.dart' show SettingsFindableMark;
import 'package:ghost_md/settings/settings_sheet.dart';
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

  Voice voiceFor(SampleLibrary notes, {required bool engine, bool present = true, Summaries? summaries, Future<void>? engineAfter}) {
    if (engine) {
      const device = {'cores': 8, 'totalRamBytes': 8000000000};
      backend = FakeAiBackend(generation: 30)
        ..answers['ai_models'] = [
          {'id': 'qwen3.5-2b', 'file': 'Qwen3.5-2B-Q4_K_M.gguf', 'bytes': 1280835840, 'present': present, 'path': present ? '/models/q' : null},
        ]
        // The phone says what it is when the test lets it: until then the app has no engine to give a note.
        ..answers['ai_device'] = engineAfter == null
            ? device
            : () async {
                await engineAfter;
                return device;
              };
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

  /// What the phone's service says to the queue, by its name (`window.__glyph.recordingDone`).
  final hostSays = <String, void Function(String json)>{};

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
        answerHost: (name, handler) {
          hostSays[name] = handler;
          return () => hostSays.remove(name);
        },
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

  Future<SampleLibrary> open(WidgetTester tester, {required bool engine, bool present = true, Summaries? Function(SampleLibrary notes, Stored kept)? summaries, TapePlayer? tapePlayer, Connection? connection, Future<void>? engineAfter}) async {
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
        voice: voiceFor(library, engine: engine, present: present, summaries: summaries?.call(library, kept), engineAfter: engineAfter),
        tapePlayer: tapePlayer,
        connection: connection,
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

  // Differs 7 (docs/PARITY.md): the desk's AI was made with the desk or never, so a note opened before the engine was
  // up (a launch straight into a note, a slow phone) had no AI until it was opened again. The page's note always has
  // its `useNoteAi`, and the model arrives when it does.
  testWidgets('a note opened before the engine is up has its AI the moment it is, in the editor it already has', (tester) async {
    final engineUp = Completer<void>();
    final library = await open(tester, engine: true, engineAfter: engineUp.future);
    final note = library.value.firstWhere((note) => noteTitle(note.body) == 'Packing');
    shellOf(tester).openNote(note.id);
    await settle(tester);
    expect(find.byType(NoteAiLayer), findsNothing);
    expect(tester.widget<NoteScreen>(find.byType(NoteScreen)).seams.onAi, isNull);
    final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
    expect(view.state.fieldOrNull(aiChangesField), isNull);
    // Typed meanwhile.
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.length, insert: '\nTyped before the engine.'), userEvent: 'input.type'));
    await tester.pump();

    engineUp.complete();
    await settle(tester);
    // The same editor, with what was typed in it, and the AI's layer, rows and extensions now.
    expect(find.byType(NoteAiLayer), findsOneWidget);
    expect(identical(tester.state<NoteScreenState>(find.byType(NoteScreen)).view, view), isTrue);
    expect(view.state.doc.toString(), endsWith('Typed before the engine.'));
    final ai = tester.widget<NoteAiLayer>(find.byType(NoteAiLayer)).ai;
    expect(identical(ai.view, view), isTrue);
    expect(ai.noteId, note.id);
    expect(view.state.fieldOrNull(aiChangesField), isNotNull);
    // And a run asked for from the More sheet reaches the engine.
    backend.script('A shorter Packing.');
    tester.widget<NoteScreen>(find.byType(NoteScreen)).seams.onAi!(view, 'summarize');
    await settle(tester, 8);
    expect(backend.requests, isNotEmpty);
    await tester.pump(const Duration(seconds: 2));
    await close(tester);
  });

  // Differs 28 (docs/PARITY.md): `plusAllowed = … && (ai.runningKind === null || ai.runningKind === 'fill')`
  // (NoteScreen.tsx): the + stood beside an empty line while a run wrote into the note.
  testWidgets('the + is put away while a run writes into the note, and allowed again when the run has ended', (tester) async {
    final library = await open(tester, engine: true);
    final note = library.value.firstWhere((note) => noteTitle(note.body) == 'Packing');
    shellOf(tester).openNote(note.id);
    await settle(tester);
    final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
    // The caret rests on an empty line at the note's end: the + is beside it.
    final end = view.state.doc.length;
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: end, insert: '\n\n'), selection: EditorSelection.single(end + 2), userEvent: 'input.type'));
    await tester.pump();
    tester.state<NoteDeskState>(find.byType(NoteDesk)).editor.focus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final plus = tester.widget<PlusLayer>(find.byType(PlusLayer)).controller!;
    expect(plus.hooks.allowed(), isTrue);
    expect(plusViewOf(view)!.look, PlusLook.shown);

    // A run that has not answered yet.
    final answer = Completer<Object?>();
    backend.answers['ai_generate'] = (Object? args) => answer.future;
    tester.widget<NoteScreen>(find.byType(NoteScreen)).seams.onAi!(view, 'summarize');
    await settle(tester, 4);
    expect(tester.widget<NoteAiLayer>(find.byType(NoteAiLayer)).ai.runningKind, RunKind.summarize);
    expect(plus.hooks.allowed(), isFalse);
    expect(plusViewOf(view)!.look, isNot(PlusLook.shown));

    answer.complete({'text': 'A shorter Packing.'});
    await settle(tester, 8);
    expect(tester.widget<NoteAiLayer>(find.byType(NoteAiLayer)).ai.runningKind, isNull);
    expect(plus.hooks.allowed(), isTrue);
    await tester.pump(const Duration(seconds: 2));
    await close(tester);
  });

  // Differs 32 (docs/PARITY.md): "Get a model" opened Settings on AI with nothing lit; the page opens it at the Model
  // card, lit (App.tsx `setToModel`, SettingsSheet.tsx `{ id: 'ai', setting: 'Model' }`).
  testWidgets('Get a model opens Settings on AI with the Model card lit', (tester) async {
    final library = await open(tester, engine: true);
    final note = library.value.firstWhere((note) => noteTitle(note.body) == 'Packing');
    shellOf(tester).openNote(note.id);
    await settle(tester);
    tester.widget<NoteAiLayer>(find.byType(NoteAiLayer)).ai.onGetModel!();
    await tester.pump();
    final sheet = tester.widget<SettingsSheet>(find.byType(SettingsSheet));
    expect(sheet.open, isTrue);
    expect(sheet.toPage?.id, 'ai');
    expect(sheet.toPage?.setting, 'Model');
    // And the card is lit, as a search's result is: looked for over the frames its page takes to be drawn.
    bool lit() {
      final card = find.byWidgetPredicate((w) => w is SettingsFindableMark && w.name == 'Model', skipOffstage: false);
      if (card.evaluate().isEmpty) return false;
      final light = find.descendant(of: card, matching: find.byKey(SettingsFindableMark.lightKey, skipOffstage: false), skipOffstage: false);
      return light.evaluate().isNotEmpty && SettingsFindableMark.isLit(tester.widget(light.first));
    }

    var seen = false;
    for (var i = 0; i < 40 && !seen; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      seen = lit();
    }
    expect(seen, isTrue);
    await tester.pump(const Duration(seconds: 3));
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

  // Differs 15 (docs/PARITY.md): a summary that landed was said as "Summarized", with no title, for the kit's own
  // few seconds (shell/useHousekeeping.ts: `Summarized “${title}”`, ten seconds, Open).
  testWidgets('a summary that lands with the app on screen is said by the note\'s name, for ten seconds, with Open', (tester) async {
    late Summaries queue;
    final library = await open(tester, engine: true, summaries: (notes, kept) => queue = summariesOver(notes, kept), tapePlayer: FakeTapePlayer(lengths: const {}));
    final note = library.value.firstWhere((note) => noteTitle(note.body) == 'Packing');
    await tester.runAsync(() => library.apply(Note(id: note.id, body: note.body, createdAt: note.createdAt, updatedAt: note.updatedAt, source: NoteSource.capture, recordingMs: 4000, segments: const [Segment(text: 'Bring the long lens', startMs: 0, endMs: 2000)], revision: note.revision)));
    await settle(tester, 2);
    shellOf(tester).openNote(note.id);
    await settle(tester);
    backend.script('Pack the long lens.');
    queue.enqueueSummary(note.id, SummaryKind.recording);
    for (var i = 0; i < 30 && find.text('Summarized “Packing”').evaluate().isEmpty; i++) {
      await settle(tester, 2);
    }
    expect(find.text('Summarized “Packing”'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    // Still there after the kit's own few seconds, and gone after its ten.
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('Summarized “Packing”'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Summarized “Packing”'), findsNothing);
    await close(tester);
  });

  // Unwired 8 (docs/PARITY.md): `onRecordingChanged` had no caller, so a write-up was taken only as a note opened
  // (NoteScreen.tsx's effect: the note read again and adopted, when nothing typed is waiting to be saved).
  testWidgets('the open note takes the phone\'s write-up the moment it lands', (tester) async {
    final library = await open(tester, engine: true, summaries: summariesOver);
    final note = library.value.firstWhere((note) => noteTitle(note.body) == 'Packing');
    shellOf(tester).openNote(note.id);
    await settle(tester);
    final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
    expect(view.state.doc.toString(), isNot(contains('## Transcript')));

    // The service appends the transcript under the note, and says it is done with it.
    final now = library.noteOf(note.id)!;
    final written = '${now.body.trimRight()}\n\n## Transcript\n\nBring the long lens.\n';
    await tester.runAsync(() => library.apply(Note(id: now.id, body: written, createdAt: now.createdAt, updatedAt: now.updatedAt + 1, source: now.source, revision: now.revision + 1)));
    expect(hostSays['recordingDone'], isNotNull, reason: 'the queue answers the service once it is started');
    hostSays['recordingDone']!('{"id":"${note.id}","outcome":"failed"}');
    await settle(tester, 4);
    expect(view.state.doc.toString(), written);
    await close(tester);
  });

  // Unwired 12 (docs/PARITY.md): `startFills` was given no `onLine` and no `onOnline`, so a blank left "Waiting
  // for a connection" was tried again only by the one-minute timer (ai/fills/queue.ts `window.addEventListener(
  // 'online', …)`, `navigator.onLine`).
  testWidgets('the fills\' queue hears a connection come back, for as long as the app is up', (tester) async {
    final connection = _FakeConnection();
    await open(tester, engine: true, connection: connection);
    expect(connection.listeners, hasLength(1), reason: 'the queue asked to hear of a connection coming back');
    // What it does with the word is the queue's own (test/ai/fills): here, that the word reaches it and is let go.
    expect(connection.asked, 0);
    connection.listeners.single();
    await close(tester);
    expect(connection.listeners, isEmpty);
  });

  // Unwired 18 (docs/PARITY.md): `NoteAi.closePanels` had no caller, and nothing put away a mark's note or a
  // footnote's words either: a panel stayed where it was opened while the note went by under it (fillPanel.ts and
  // textPanel.ts `EditorView.domEventHandlers({ scroll })`).
  testWidgets('an answer\'s panel, a mark\'s note and a footnote\'s words are put away when the note scrolls', (tester) async {
    final library = await open(tester, engine: true);
    final long = library.create('# A long note\n\n${[for (var i = 0; i < 120; i++) 'A line of it, number $i.'].join('\n\n')}\n');
    await tester.pump();
    shellOf(tester).openNote(long.id);
    await settle(tester);
    final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
    fillPanelOf(view).value = const ShownFillPanel(at: 2, content: PanelContent(icon: Lucide.globe, title: 'Paris', lines: ['Looked up.'], actions: []));
    showTextPanel(view, 2, 'The words under it.', className: 'cm-footPanel', label: 'Footnote 1');
    showTextPanel(view, 2, 'A note on a mark.', className: 'cm-markNotePanel', label: 'Note');
    await tester.pump();
    expect(fillPanelOf(view).value, isNotNull);
    expect(textPanels(view).value, hasLength(2));
    final page = tester.state<ScrollableState>(find.descendant(of: find.byType(NoteScreen), matching: find.byType(Scrollable)).first).position;
    expect(page.maxScrollExtent, greaterThan(200));
    page.jumpTo(120);
    await tester.pump();
    expect(fillPanelOf(view).value, isNull);
    expect(textPanels(view).value, isEmpty);
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

/// A connection a test holds: who listens, and how often it was asked whether there is one.
class _FakeConnection implements Connection {
  final List<VoidCallback> listeners = [];
  int asked = 0;

  @override
  bool get onLine {
    asked += 1;
    return true;
  }

  @override
  VoidCallback onOnline(VoidCallback listener) {
    listeners.add(listener);
    return () => listeners.remove(listener);
  }
}
