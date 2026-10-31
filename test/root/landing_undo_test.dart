import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/landing.dart';
import 'package:ghost_md/capture/recorder.dart';
import 'package:ghost_md/capture/refine.dart';
import 'package:ghost_md/capture/take_writer.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/untouched.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart' as editor show StateCommandTarget, undo;
import 'package:ghost_md/editor/media/clip_refs.dart' show TapeIds;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/voice_wiring.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/screen.dart';

import '../support/render.dart';

/// The better words' queue, as far as an open note asks it anything: what it was told to drop.
class _Refining extends Refining {
  _Refining()
      : super(
          backend: null,
          hasNativeGeneration: (_) async => false,
          preferences: () => Preferences.defaults,
          stored: MemoryStored(),
          getNote: (_) async => null,
          updateNote: (_, _, _) async => throw StateError('nothing is written here'),
          setNoteRecording: (_, _, _) async => null,
          keptText: (_, _) => null,
          summaryUnchanged: (_, _, _) => true,
          writeUpRunning: () => false,
        );

  final List<(String, int)> drops = [];

  @override
  VoidCallback startRefining(VoidCallback changed) => () {};

  @override
  void holdNote(String id, bool on) {}

  @override
  void dropRefine(String id, int fromMs) => drops.add((id, fromMs));
}

/// What a recording wrote to notes other than the one that opens, taken back by the landing's Undo
/// (lib/root/note_desk.dart `_undoLanding`, a port of `editor/useLanding.ts`): the cases of the web's
/// `editor/NoteScreen.test.tsx` ("a note a recording just wrote into") that name another note, and the rule its
/// Undo keeps for a write it could not take back, which the web has no case of. Through the app put together, over
/// the library in memory (the browser half of `core/store.ts`, as the web's cases run over theirs);
/// test/native/command_mutations_test.dart crosses the real core.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const house = '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician\n';

  late SampleLibrary library;
  late _Refining refining;

  Note note(String id, String body) => Note(id: id, body: body, createdAt: 1, updatedAt: 1);

  CaptureLanding landing({String noteId = 'house', String title = 'House TODOs', List<String> blocks = const ['- [ ] Call an electrician'], List<String> others = const [], int? fromMs}) =>
      CaptureLanding(noteId: noteId, title: title, blocks: blocks, others: others, made: const [], fromMs: fromMs);

  /// A write a recording made to the note `work`: "- Call Sam" on its end, as `writeInto` stores it.
  Future<void> wroteIntoWork(String mutationId) async {
    final work = library.noteOf('work')!;
    final written = await library.applyCommandMutation(CommandMutationRequest(mutationId: mutationId, noteId: 'work', kind: 'append', beforeRevision: work.revision, beforeBody: work.body, afterBody: '# Work\n\n- Call Sam', source: NoteSource.editor));
    expect(written.status, 'applied');
  }

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));
  String doc(WidgetTester tester) => tester.state<NoteScreenState>(find.byType(NoteScreen)).view!.state.doc.toString();

  /// The app over [notes], with a recorder whose queue of better words is the test's.
  Future<void> open(WidgetTester tester, List<Note> notes) async {
    library = SampleLibrary(notes);
    refining = _Refining();
    var prefs = Preferences.defaults.copyWith(review: false, refine: false);
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        library: library,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        stored: MemoryStored(),
        untouched: UntouchedNotes(kept: MemoryStored()),
        voice: Voice(
          recorder: Recorder(
            engine: CaptureEngine(backend: null, hasNativeGeneration: (_) async => true, preferences: () => prefs),
            store: LibraryRecorderStore(library),
            refining: refining,
            preferences: () => prefs,
            setPreferences: (change) => prefs = change(prefs),
            tapes: TapeIds(MemoryStored()),
            native: false,
            simulate: false,
          ),
        ),
      ),
    );
    await settle(tester, 3);
  }

  /// The note opened as the recorder's route opens it after Done (lib/root/capture_route.dart `finished`).
  Future<void> land(WidgetTester tester, String id, CaptureLanding landing, {int key = 1}) async {
    shellOf(tester).show(ScreenNote(library.noteOf(id)!, landing: Keyed(landing, key)));
    await settle(tester, 4);
  }

  Future<void> undo(WidgetTester tester) async {
    await tester.tap(find.text('Undo'));
    await settle(tester, 3);
  }

  Future<void> close(WidgetTester tester) async {
    // Past the toasts' holds and the editor's save.
    await tester.pump(const Duration(seconds: 6));
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  const changed = 'House TODOs has changed since, so it was left as it is.';

  group('a note a recording just wrote into, and other notes with it', () {
    testWidgets('undoes what it wrote into other notes through the guarded undo', (tester) async {
      await open(tester, [note('work', '# Work'), note('house', house)]);
      await wroteIntoWork('m1');
      await land(tester, 'house', landing(others: ['m1']));
      expect(find.text('Added to House TODOs and one other note'), findsOneWidget);
      await undo(tester);
      expect(library.noteOf('work')!.body, '# Work');
      expect(doc(tester), '# House TODOs\n\n- [ ] Fix the gutter\n');
      expect(find.text(changed), findsNothing);
      await close(tester);
    });

    testWidgets('leaves another note that has changed since as it is, and says so', (tester) async {
      await open(tester, [note('work', '# Work'), note('house', house)]);
      await wroteIntoWork('m1');
      await library.update('work', '# Work\n\n- Call Sam\n- Typed since', library.noteOf('work')!.revision);
      await land(tester, 'house', landing(others: ['m1']));
      await undo(tester);
      expect(library.noteOf('work')!.body, '# Work\n\n- Call Sam\n- Typed since');
      // What went into this note is still taken out: each write stands or falls alone.
      expect(doc(tester), '# House TODOs\n\n- [ ] Fix the gutter\n');
      expect(find.text(changed), findsOneWidget);
      await close(tester);
    });

    testWidgets('counts a write taken back already as undone, and one the library knows nothing of as left', (tester) async {
      await open(tester, [note('work', '# Work'), note('house', house)]);
      await wroteIntoWork('m1');
      expect((await library.undoCommandMutation('m1')).status, 'undone');
      await land(tester, 'house', landing(others: ['m1']));
      await undo(tester);
      expect(library.noteOf('work')!.body, '# Work');
      expect(find.text(changed), findsNothing);

      await land(tester, 'house', landing(blocks: const [], others: ['never']), key: 2);
      expect(find.text('Added to House TODOs and one other note'), findsOneWidget);
      await undo(tester);
      expect(find.text(changed), findsOneWidget);
      await close(tester);
    });

    // Differs 34 (docs/PARITY.md): an Undo that emptied a note left its where-written tag behind, a note of nothing
    // but a place (editor/useLanding.ts: the tag goes in the same step, so one undo brings both back).
    testWidgets('takes a lone where-written tag off with the words when its Undo empties the note, as one step', (tester) async {
      const said = 'Call the electrician about the light sockets.';
      const tagged = '---\nlocation: 51.5074,-0.1278\nplace: "Trafalgar Square, London"\n---\n$said\n';
      await open(tester, [note('spoken', tagged)]);
      await land(tester, 'spoken', landing(noteId: 'spoken', title: 'Call the electrician', blocks: const [said]));
      await undo(tester);
      expect(doc(tester).trim(), isEmpty, reason: 'nothing left behind, its tag least of all');
      // One step: the editor's own undo brings the words and the tag back together.
      final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
      editor.undo(editor.StateCommandTarget(view.state, (tr) => view.dispatch(tr)));
      await tester.pump();
      expect(doc(tester), tagged);
      await close(tester);
    });

    testWidgets('leaves the tag of a note that still has words after its Undo', (tester) async {
      const tagged = '---\nlocation: 51.5074,-0.1278\n---\n# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician\n';
      await open(tester, [note('house', tagged)]);
      await land(tester, 'house', landing());
      await undo(tester);
      expect(doc(tester), '---\nlocation: 51.5074,-0.1278\n---\n# House TODOs\n\n- [ ] Fix the gutter\n');
      await close(tester);
    });

    testWidgets('drops the recording’s better words only for words its Undo took out of this note', (tester) async {
      await open(tester, [note('work', '# Work'), note('house', house), note('own', '# Kevin owns the release')]);
      await land(tester, 'house', landing(fromMs: 4000));
      await undo(tester);
      expect(refining.drops, [('house', 4000)]);
      shellOf(tester).backToList();
      await settle(tester, 3);

      refining.drops.clear();
      await wroteIntoWork('m2');
      await land(tester, 'own', landing(noteId: 'own', title: 'Kevin owns the release', blocks: const [], others: ['m2'], fromMs: 0), key: 2);
      await undo(tester);
      expect(library.noteOf('work')!.body, '# Work');
      expect(refining.drops, isEmpty);
      await close(tester);
    });
  });
}
