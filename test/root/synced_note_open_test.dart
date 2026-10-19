// A note that comes in from outside while home is up (sync; a meeting Ghost recorded, filed by lib/meet) opens when
// it is tapped on home (Matt, 2026-10-19, Fold on 2.3.1: "at the top of the app there are voice recordings for
// meetings from today but I cant click any of them to open the meeting notes").
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/untouched.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

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

  testWidgets('a meeting filed while home is up opens from its card on home', (tester) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      size: const Size(390, 844),
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        library: library,
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        stored: MemoryStored(),
        untouched: UntouchedNotes(kept: MemoryStored()),
      ),
    );
    await settle(tester, 3);
    // As syncMeet files it: through the library's own door, with its recording's length, newest of all.
    const id = 'meet-filed-1';
    const body = '# Tidepool Series A planning\n\nGhost was in this meeting on Oct 19, 13:21 to 13:38. It is being written up on your device.\n';
    await tester.runAsync(() => library.apply(Note(id: id, body: body, createdAt: seedNow, updatedAt: seedNow, source: NoteSource.capture, recordingMs: 869000)));
    await settle(tester, 4);
    final onHome = find.descendant(of: find.byType(HomeScreen), matching: find.byWidgetPredicate((w) => w.key == const ValueKey('card-$id') || w.key == const ValueKey('row-$id') || w.key == const ValueKey('line-$id')));
    expect(onHome, findsWidgets, reason: 'the meeting is on home');
    await tester.tap(onHome.first, warnIfMissed: false);
    await settle(tester, 4);
    expect(tester.state<AppShellState>(find.byType(AppShell)).shown, id, reason: 'the tap opened the meeting');
    expect(find.byWidgetPredicate((w) => w is NoteScreen && w.note.id == id), findsOneWidget);
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
