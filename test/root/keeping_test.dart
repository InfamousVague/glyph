// Unwired 9 (docs/PARITY.md): what the app does about a note beside trashing, restoring and deleting it
// (notes/useNoteActions.ts `remove`, `resumeWriteUp`, `forgetKept`). The root's actions were given none of it: a
// trashed meeting went on being written up, a restored one was never asked for again, and a note deleted for good
// left its gist, its summary and its job behind. The meeting's cases are `useNoteActions.test.tsx`'s, through the
// app put together.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/summaries.dart';
import 'package:ghost_md/ai/summary_keep.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/recorder.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/format/results.dart';
import 'package:ghost_md/notes/note_menu.dart';
import 'package:ghost_md/notes/notes_drawer.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/voice_wiring.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';
import 'part_of.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  late List<String> cancelled;
  late List<(String, bool)> writtenUp;
  late List<RecordingJobState> phoneJobs;
  late Summaries queue;
  Voice? voice;

  RecordingJobState job(String id, RecordingJobPhase phase) => RecordingJobState(id: id, title: 'Meeting', phase: phase);

  Future<SampleLibrary> open(WidgetTester tester, {String summaries = 'meetings'}) async {
    final library = SampleLibrary.seeded();
    final kept = MemoryStored();
    cancelled = [];
    writtenUp = [];
    phoneJobs = [];
    queue = Summaries(
      isTauri: () => true,
      preferences: () => preferences.value,
      stored: kept,
      refineHeld: () => false,
      refinePending: (_) => false,
      onRefineHold: (_) => () {},
      canNotifyNow: () => false,
      recordingJobState: () async => phoneJobs,
      takeRecordingResult: (_) async => null,
      writeUpOnHost: (id, now) {
        writtenUp.add((id, now));
        // The phone takes the job up again: queued, where the trash had cancelled it.
        phoneJobs = [for (final each in phoneJobs) if (each.id != id) each, job(id, RecordingJobPhase.queued)];
        return true;
      },
      answerHost: (_, _) => () {},
      getNote: library.get,
      updateNote: library.update,
      isTrashed: (_) => false,
      syncNow: () async {},
      syncSettled: () async {},
      record: (_, _) async {},
      visible: () => true,
      onVisible: (_) => () {},
      onNotesChanged: (_) => () {},
      sendJobConfig: () async {},
    );
    await pumpApp(
      tester,
      prefs: Preferences(theme: 'light', summaries: summaries),
      home: GhostRoot(
        launch: false,
        library: library,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        stored: kept,
        voice: voice = Voice(
          recorder: Recorder(engine: CaptureEngine(backend: null, hasNativeGeneration: (_) async => true), store: LibraryRecorderStore(library), native: false, simulate: false, enqueueRefine: (_) {}, setRecorderLive: (_) {}),
          summaries: queue,
          cancelWriteUp: (id) async => cancelled.add(id),
        ),
      ),
    );
    await settle(tester);
    return library;
  }

  /// A meeting among the notes: a note the preferences name as one.
  Note meeting(SampleLibrary library, String body) {
    final note = library.create(body);
    preferences.update((now) => now.copyWith(meetings: {...now.meetings, note.id: 1}));
    return note;
  }

  NoteMenuHost menu(WidgetTester tester) => tester.widget<NoteMenuHost>(find.byType(NoteMenuHost));

  /// The sidebar as the root would draw it, for its Trash rows' presses.
  NotesDrawer sidebar(WidgetTester tester) {
    final shell = tester.state<AppShellState>(find.byType(AppShell));
    return partOf<NotesDrawer>(shell.context, tester.widget<AppShell>(find.byType(AppShell)).sidebarBuilder!(shell.context, shell, () {}));
  }

  Future<void> close(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    // A voice a test brought is the test's to let go: the summary queue's own looks stop with it.
    voice?.dispose();
    voice = null;
    await tester.pump(const Duration(seconds: 6));
  }

  testWidgets('a meeting has its write-up cancelled as it goes into the Trash, even with Summaries off; any other note asks nothing of the phone', (tester) async {
    final library = await open(tester, summaries: 'off');
    final met = meeting(library, '# Meeting, 26 Sep 14:05\n');
    await settle(tester, 2);
    menu(tester).onDelete(library.noteOf(met.id)!);
    await settle(tester, 2);
    expect(cancelled, [met.id]);
    menu(tester).onDelete(library.value.firstWhere((note) => note.id != met.id));
    await settle(tester, 2);
    expect(cancelled, [met.id]);
    await close(tester);
  });

  testWidgets('a meeting is written up again by the toast\'s Undo where the phone still holds its job, and a summary is queued for it', (tester) async {
    final library = await open(tester);
    final met = meeting(library, '# Meeting, 26 Sep 14:05\n');
    await settle(tester, 2);
    menu(tester).onDelete(library.noteOf(met.id)!);
    await settle(tester, 2);
    phoneJobs = [job(met.id, RecordingJobPhase.cancelled)];
    await tester.tap(find.text('Undo'));
    await settle(tester, 3);
    expect(writtenUp, [(met.id, false)]);
    expect(queue.summaryNative(met.id), isTrue);
    await close(tester);
  });

  testWidgets('a restored meeting is not listened to again once its words are in the note and the phone holds nothing for it; one stopped half way is', (tester) async {
    final library = await open(tester);
    final met = meeting(library, '# Meeting, 26 Sep 14:05\n\n## Transcript\n\nWe agreed, as I corrected it.\n');
    await settle(tester, 2);
    sidebar(tester).onRestore!(library.noteOf(met.id)!);
    await settle(tester, 3);
    expect(writtenUp, isEmpty);
    phoneJobs = [job(met.id, RecordingJobPhase.cancelled)];
    sidebar(tester).onRestore!(library.noteOf(met.id)!);
    await settle(tester, 3);
    expect(writtenUp, [(met.id, false)]);
    // With no words and no job yet it is asked for afresh.
    final bare = meeting(library, '# Meeting, 27 Sep 09:00\n');
    await settle(tester, 2);
    phoneJobs = [];
    sidebar(tester).onRestore!(library.noteOf(bare.id)!);
    await settle(tester, 3);
    expect(writtenUp.last, (bare.id, false));
    await close(tester);
  });

  testWidgets('a note deleted for good takes what the app kept beside it: its line, its summary and the job to write one', (tester) async {
    final library = await open(tester);
    final note = library.value.first;
    keepGist(note.id, Gist(text: 'A line under the card.', forBody: note.body.length, model: 'qwen3.5-2b'));
    keepSummary(note.id, const KeptSummary(text: '## Summary\n\n- One thing.', model: 'qwen3.5-2b', at: 1, forMs: 4000));
    queue.enqueueSummary(note.id, SummaryKind.recording);
    expect((readGist(note.id) != null, keptText(note.id) != null, queue.summaryPending(note.id)), (true, true, true));
    sidebar(tester).onEmptyTrash!();
    await settle(tester, 3);
    // The Trash was empty: nothing was forgotten.
    expect(keptText(note.id), isNotNull);
    menu(tester).onDelete(note);
    await settle(tester, 2);
    sidebar(tester).onEmptyTrash!();
    await settle(tester, 3);
    expect(library.noteOf(note.id), isNull);
    expect((readGist(note.id), keptText(note.id), queue.summaryPending(note.id)), (null, null, false));
    await close(tester);
  });
}

Future<void> settle(WidgetTester tester, [int beats = 6]) async {
  for (var i = 0; i < beats; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}
