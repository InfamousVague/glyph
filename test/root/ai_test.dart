import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/ai/note_ai.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/recorder.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/marks/marks.dart' show wispStill;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/voice_wiring.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../ai/fake_backend.dart';
import '../support/render.dart';

/// The AI in the app put together (lib/root): one `NoteAi` to an open note where there is an engine, with its
/// extensions in the editor, its layer over the page, and a run from the More sheet; and none of it without one.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  late FakeAiBackend backend;

  tearDown(() => useAiBackend(const NoAiBackend()));

  Voice voiceFor(SampleLibrary notes, {required bool engine}) {
    if (engine) {
      backend = FakeAiBackend(generation: 30)
        ..answers['ai_models'] = [
          {'id': 'qwen3.5-2b', 'file': 'Qwen3.5-2B-Q4_K_M.gguf', 'bytes': 1280835840, 'present': true, 'path': '/models/q'},
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
    );
  }

  Future<SampleLibrary> open(WidgetTester tester, {required bool engine}) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        library: library,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        stored: MemoryStored(),
        voice: voiceFor(library, engine: engine),
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
    await tester.pump(const Duration(seconds: 2));
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
