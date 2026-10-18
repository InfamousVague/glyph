import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/notes/note_tabs.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/wide_screen.dart' show simpleListColumn;
import 'package:ghost_md/simple/simple_bar.dart';
import 'package:ghost_md/simple/simple_home.dart';
import 'package:ghost_md/simple/simple_pane.dart';

import '../support/render.dart';

/// Simple mode on a wide window, in the app put together (GHST-105), at the Fold's unfolded size (704 x 933 at
/// 2.625): the list in a column at the start and the note beside it, the quiet pane while none is open, the switch
/// and the pair in the column rather than along the foot, and the phone folded shut going back to one window with
/// the note's own Back.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const unfolded = Size(704, 933);
  const cover = Size(475, 751);

  Future<SampleLibrary> open(WidgetTester tester, {Size size = unfolded}) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      size: size,
      ratio: 2.625,
      prefs: const Preferences(theme: 'dark', experience: 'simple', experienceChosen: true),
      home: GhostRoot(launch: false, library: library, stored: MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return library;
  }

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));
  Note titled(SampleLibrary library, String title) => library.value.firstWhere((note) => noteTitle(note.body) == title);

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 2.625;
    await settle(tester, 4);
  }

  testWidgets('is the list beside a quiet pane, then beside the note opened from it, with no bar and no tree', (tester) async {
    final library = await open(tester);
    expect(find.byType(NoteTabs), findsNothing);
    expect(find.byType(NoteTree), findsNothing);
    final list = find.bySemanticsLabel('Your notes');
    expect(list, findsOneWidget);
    expect(tester.getSize(list).width, simpleListColumn(unfolded.width));
    final home = tester.widget<SimpleHome>(find.byType(SimpleHome));
    expect(home.pane, isTrue);
    expect(find.byType(SimpleBar), findsNothing, reason: 'the switch is in the column, not along the window\'s foot');
    expect(find.byKey(const ValueKey('simple-switch')), findsOneWidget);
    expect(find.byKey(const ValueKey('simple-new')), findsOneWidget);
    expect(find.byType(SimpleEmptyPane), findsOneWidget);
    expect(find.text('Pick a note, or make one.'), findsOneWidget);

    // A row tapped: the note on the right, the list still there, and the note without a Back of its own.
    final standup = titled(library, 'Monday standup');
    await tester.tap(find.byKey(ValueKey('simple-row-${standup.id}')));
    await settle(tester);
    expect(shellOf(tester).shown, standup.id);
    expect(find.byType(SimpleEmptyPane), findsNothing);
    expect(find.byType(NoteScreen), findsOneWidget);
    expect(find.byType(SimpleHome), findsOneWidget);
    expect(tester.widget<NoteScreen>(find.byType(NoteScreen)).back, isFalse);
    expect(find.byKey(const ValueKey('note-back')), findsNothing);
    expect(tester.getRect(find.byType(NoteScreen)).left, closeTo(simpleListColumn(unfolded.width), 1));
    expect(preferences.value.openNotes, [standup.id]);

    // Another row: the same one tab.
    final weekend = titled(library, 'Weekend trip');
    await tester.tap(find.byKey(ValueKey('simple-row-${weekend.id}')));
    await settle(tester);
    expect(shellOf(tester).shown, weekend.id);
    expect(preferences.value.openNotes, [weekend.id]);
    await close(tester);
  });

  testWidgets('folded shut is one window with the note and its own Back, and opened out is the list beside it again', (tester) async {
    final library = await open(tester);
    final groceries = titled(library, 'Groceries');
    shellOf(tester).openNote(groceries.id);
    await settle(tester);
    expect(find.byType(SimpleHome), findsOneWidget);
    await resize(tester, cover);
    expect(tester.takeException(), isNull);
    expect(find.byType(SimpleHome), findsNothing, reason: 'the note is the whole window');
    expect(find.bySemanticsLabel('Your notes'), findsNothing);
    expect(tester.widget<NoteScreen>(find.byType(NoteScreen)).back, isTrue);
    expect(find.byKey(const ValueKey('note-back')), findsOneWidget);
    await resize(tester, unfolded);
    expect(find.byType(SimpleHome), findsOneWidget);
    expect(find.byType(NoteScreen), findsOneWidget);
    expect(tester.widget<NoteScreen>(find.byType(NoteScreen)).back, isFalse);
    // Shut again, Back goes home: the simple page, the whole window, with the bar along its foot.
    await resize(tester, cover);
    await tester.tap(find.byKey(const ValueKey('note-back')));
    await settle(tester);
    expect(find.byType(SimpleHome), findsOneWidget);
    expect(tester.widget<SimpleHome>(find.byType(SimpleHome)).pane, isFalse);
    expect(find.byType(SimpleBar), findsOneWidget);
    expect(preferences.value.openNotes, isEmpty);
    await close(tester);
  });
}
