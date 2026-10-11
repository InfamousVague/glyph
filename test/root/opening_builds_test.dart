// A note opening builds its view once: the canvas, the notebook's index or the words' editor is made as the note's
// screen is first built, and nothing that happens as the screen settles (the editor's view arriving a frame later,
// the AI saying it has that view) builds it again.
//
// Counted by the framework's own word for an element built (`debugOnRebuildDirtyWidget`), from the press that
// opens the note until eight frames on, with an engine for the AI and without one: the AI of a note tells its
// listeners once as it is given the editor's view, and the desk was one of them and built itself, the screen and
// the view again for it (lib/root/note_desk.dart `_aiSaid`); and the screen set its own state as the editor's view
// arrived, which built the view again too (lib/note/note_screen.dart `_view0`).
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart';
import 'package:ghost_md/book/book_view.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/recorder.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/format/gist.dart' show forgetGistRunner;
import 'package:ghost_md/note/note_editor.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/note_desk.dart';
import 'package:ghost_md/root/voice_wiring.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../ai/fake_backend.dart';
import '../support/render.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  tearDown(() => useAiBackend(const NoAiBackend()));

  Voice voiceFor(SampleLibrary notes, {required bool engine}) {
    if (engine) {
      useAiBackend(FakeAiBackend(generation: 30)
        ..answers['ai_models'] = [
          {'id': 'qwen3.5-2b', 'file': 'Qwen3.5-2B-Q4_K_M.gguf', 'bytes': 1280835840, 'present': true, 'path': '/models/q'},
        ]
        ..answers['ai_device'] = {'cores': 8, 'totalRamBytes': 8000000000});
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

  const watched = <Type>{NoteDesk, NoteScreen, CanvasView, BookView, NoteEditorHost};

  /// How many times each watched widget's element was built from the press that opens `noteId` until it has
  /// settled.
  Future<Map<Type, int>> builtOpening(WidgetTester tester, String noteId, {required bool engine}) async {
    forgetGistRunner();
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
    // The engine's answers (its models, the phone) are in before the note is opened: what is counted is the
    // opening, not the AI being found.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    final counted = <Type, int>{for (final type in watched) type: 0};
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      final type = element.widget.runtimeType;
      if (counted.containsKey(type)) counted[type] = counted[type]! + 1;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    tester.state<AppShellState>(find.byType(AppShell)).openNote(noteId);
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    debugOnRebuildDirtyWidget = null;
    expect(find.byType(NoteScreen), findsOneWidget);
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 30));
    forgetGistRunner();
    return counted;
  }

  String wordsId() => seedLibrary(seedNow).firstWhere((note) => !note.body.contains('"nodes"') && !note.body.contains('book: true') && !note.body.contains('type: ticket')).id;
  String bookId() => seedLibrary(seedNow).firstWhere((note) => note.body.contains('book: true') && !note.body.contains('journal: true')).id;

  for (final engine in <bool>[false, true]) {
    final where = engine ? 'with an engine for the AI' : 'with no engine';

    testWidgets('a canvas is built once as its note opens, $where', (tester) async {
      final counted = await builtOpening(tester, 'cabin-canvas', engine: engine);
      // ignore: avoid_print
      print('a canvas opening, $where: $counted');
      expect(counted[CanvasView], 1, reason: 'the canvas is made once: $counted');
      expect(counted[NoteDesk], 1, reason: 'the desk is built once: $counted');
    });

    testWidgets('a notebook\'s index is built once as it opens, $where', (tester) async {
      final counted = await builtOpening(tester, bookId(), engine: engine);
      // ignore: avoid_print
      print('a notebook opening, $where: $counted');
      expect(counted[BookView], 1, reason: 'the index is made once: $counted');
      expect(counted[NoteDesk], 1, reason: 'the desk is built once: $counted');
    });

    testWidgets('a note of words builds its desk once as it opens, $where', (tester) async {
      final counted = await builtOpening(tester, wordsId(), engine: engine);
      // ignore: avoid_print
      print('a note of words opening, $where: $counted');
      expect(counted[NoteDesk], 1, reason: 'the desk is built once: $counted');
    });
  }
}
