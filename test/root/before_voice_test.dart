// A note that is on screen before voice is made, in the app put together (lib/root).
//
// Voice is made a moment after the root is up (lib/root/root_voice.dart `_speakUp`: the recorder over the core's
// Whisper, the queues, the phone's half), and a note can be opened before it is: the app started by
// `ghostmd://note/<id>`, by a tap on "Written up", or on a phone slow to attach its half. docs/PARITY.md,
// "Regressions found on 2026-10-11", found beside, 1 and 2.
import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/recorder.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/media/clip_refs.dart' show TapeIds;
import 'package:ghost_md/editor/media/clips.dart' show Tape, tapeSource;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/voice_wiring.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/tapes/note_tape.dart';

import '../support/render.dart';
import '../tapes/fake_player.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));

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

  /// Voice as the app makes it over [kept]: the recorder names its tapes in this device's own memory
  /// (lib/root/voice_wiring.dart `tapes: TapeIds(kept)`).
  Voice voiceOver(SampleLibrary notes, Stored kept) => Voice(
        recorder: Recorder(
          engine: CaptureEngine(backend: null, hasNativeGeneration: (_) async => true),
          store: LibraryRecorderStore(notes),
          tapes: TapeIds(kept),
          native: false,
          simulate: false,
          enqueueRefine: (_) {},
          setRecorderLive: (_) {},
        ),
      );

  /// Packing, spoken, with a voice memo that names the tape it is a stretch of.
  Future<Note> taped(WidgetTester tester, SampleLibrary library, {required String tape}) async {
    final note = library.value.firstWhere((note) => noteTitle(note.body) == 'Packing');
    await tester.runAsync(
      () => library.apply(
        Note(
          id: note.id,
          body: '${note.body}\n\n![voice 0:02](tape:1000-3000@$tape)\n',
          createdAt: note.createdAt,
          updatedAt: note.updatedAt,
          source: NoteSource.capture,
          recordingMs: 4000,
          segments: const [Segment(text: 'Bring the long lens', startMs: 0, endMs: 2000), Segment(text: 'and the tripod', startMs: 2000, endMs: 4000)],
          revision: note.revision,
        ),
      ),
    );
    return library.noteOf(note.id)!;
  }

  // Found beside, 1. The desks' world took `tapes: _voice?.recorder.tapes` once, the first time a note's screen was
  // built: opened before voice, every note of that run had no tape ids, so a memo that names its tape was a quiet
  // mark and Remove left the tape's id behind (and, until voice came, wrote nothing and said it had). The page reads
  // `tapeId(note.id)` from this device's own memory, which no recorder has to be there for (core/clips.ts;
  // NoteScreen.tsx `tapeId={tape.length > 0 ? tapeId(note.id) : null}`), and writes a recording through its store.
  testWidgets('a note opened before voice is made knows its tape by name, and its memo is a player and not a quiet mark', (tester) async {
    final library = SampleLibrary.seeded();
    final kept = MemoryStored();
    final made = Completer<void>();
    final player = FakeTapePlayer(lengths: const {}), memos = FakeTapePlayer(lengths: const {});
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        library: library,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        stored: kept,
        tapePlayer: player,
        clipPlayer: memos,
        voice: voiceOver(library, kept),
        voiceWhen: made.future,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final note = await taped(tester, library, tape: 'take-7');
    // The recorder named this note's tape when it was spoken, in a run before this one.
    TapeIds(kept).setTapeId(note.id, 'take-7');
    await settle(tester, 2);

    shellOf(tester).openNote(note.id);
    await settle(tester);
    final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
    expect(view.state.facet(tapeSource), Tape(src: note.id, id: 'take-7'), reason: 'the tape is named before there is a recorder');
    expect(find.byKey(const ValueKey<String>('cm-clipLength')), findsOneWidget, reason: 'the memo is a player');
    expect(find.byKey(const ValueKey<String>('cm-clipQuiet-words')), findsNothing, reason: 'and not a quiet mark');

    // Voice comes: nothing of the note's tape is another.
    made.complete();
    await settle(tester);
    expect(identical(tester.state<NoteScreenState>(find.byType(NoteScreen)).view, view), isTrue);
    expect(view.state.facet(tapeSource), Tape(src: note.id, id: 'take-7'));
    await close(tester);
  });

  testWidgets('Remove on the tape of a note opened before voice takes the tape\'s name off, and Undo puts it back', (tester) async {
    final library = SampleLibrary.seeded();
    final kept = MemoryStored();
    final player = FakeTapePlayer(lengths: const {});
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        library: library,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        stored: kept,
        tapePlayer: player,
        clipPlayer: FakeTapePlayer(lengths: const {}),
        voice: voiceOver(library, kept),
        // Never, in this test: the whole of it is before voice.
        voiceWhen: Completer<void>().future,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final note = await taped(tester, library, tape: 'take-7');
    TapeIds(kept).setTapeId(note.id, 'take-7');
    await settle(tester, 2);
    shellOf(tester).openNote(note.id);
    await settle(tester);

    tester.widget<NoteTape>(find.byType(NoteTape)).onRemove();
    await settle(tester);
    expect(find.text('Recording removed. Its voice memos are quiet until you undo.'), findsOneWidget);
    expect(TapeIds(kept).tapeId(note.id), isNull, reason: 'the removed recording\'s name is not left for the next take\'s memos to match');
    expect(library.noteOf(note.id)!.recordingMs, isNull, reason: 'and what the toast says was done: the length is off the note');
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(TapeIds(kept).tapeId(note.id), 'take-7');
    expect(library.noteOf(note.id)!.recordingMs, 4000);
    await close(tester);
  });
}
