import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/notes/all_notes_screen.dart';
import 'package:ghost_md/notes/new_sheet.dart';
import 'package:ghost_md/notes/note_tabs.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/notes/notes_drawer.dart';
import 'package:ghost_md/notes/notices.dart' show ExperienceCard;
import 'package:ghost_md/guide/guide_state.dart' show guideSeenKey;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../shell/dock_support.dart' show dockOrder;
import '../support/render.dart';
import 'part_of.dart';

/// Simple mode through the root (GHST-103; Matt, 2026-10-17: "allow selecting between simple and advanced mode
/// where simple mode has a much more approachable UI with fancy features hidden behind more"): the root reads the
/// experience preference and hands each surface its answer, and a change of the preference reaches every one of
/// them at once. Each surface's own trimming is its own test; here is that the root says so to each.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  Future<SampleLibrary> open(WidgetTester tester, {required String experience}) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: Preferences(theme: 'light', experience: experience, experienceChosen: true),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, stored: MemoryStored()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return library;
  }

  Future<void> settle(WidgetTester tester, [int beats = 4]) async {
    for (var i = 0; i < beats; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester tester) async {
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));
  AppShell shellWidget(WidgetTester tester) => tester.widget<AppShell>(find.byType(AppShell));
  Finder bar(String label) => find.descendant(of: find.byType(NoteTabs), matching: find.bySemanticsLabel(label));

  testWidgets('tells the shell, the home page, the sidebars, the + and All notes they are simple, and takes Claude off the docks', (tester) async {
    await open(tester, experience: 'simple');
    await settle(tester);
    expect(preferences.value.simple, isTrue);

    // The shell: the bar without the people icon, the bell and Forward.
    expect(shellWidget(tester).simple, isTrue);
    expect(bar('Home'), findsOneWidget);
    expect(bar('Settings'), findsOneWidget);
    expect(bar('Organizations'), findsNothing);
    expect(bar('Notifications'), findsNothing);
    expect(bar('Forward again'), findsNothing);

    // Home: no Claude at the head of the dock, no Save, no events, no organizations.
    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    expect(home.simple, isTrue);
    expect(home.claude, isNull);
    expect(home.claudeTalk, isNull);
    expect(home.onSaveSearch, isNull);
    expect(home.events, isNull);
    expect(home.onNewOrganization, isNull);
    final dock = dockOrder(tester, within: find.byType(HomeScreen));
    expect(dock, isNot(contains('claude')));
    expect(dock, containsAllInOrder(['search', 'add', 'settings']));

    // Both sidebars: no Browse files, graph, Tags or smart notebooks, and the tree's own tools trimmed.
    final shell = shellOf(tester);
    final docked = partOf<NoteTree>(shell.context, shellWidget(tester).dockedSidebarBuilder!(shell.context, shell));
    expect(docked.simple, isTrue);
    expect(docked.onTags, isNull);
    expect(docked.onGraph, isNull);
    expect(docked.onBrowseFiles, isNull);
    expect(docked.smart, isNull);
    expect(docked.onSmart, isNull);
    final drawer = partOf<NotesDrawer>(shell.context, shellWidget(tester).sidebarBuilder!(shell.context, shell, () {}));
    expect(drawer.simple, isTrue);
    expect(drawer.onTags, isNull);
    expect(drawer.onGraph, isNull);
    expect(drawer.smart, isNull);

    // The +: Note, then More.
    expect(tester.widget<NewSheet>(find.byType(NewSheet)).simple, isTrue);

    // All notes: no pills, no Save, and the dock as home's.
    shell.showAllNotes();
    await settle(tester);
    final all = tester.widget<AllNotesScreen>(find.byType(AllNotesScreen));
    expect(all.simple, isTrue);
    expect(all.onSaveSearch, isNull);
    expect(dockOrder(tester, within: find.byType(AllNotesScreen)), dock);
    await close(tester);
  });

  testWidgets('is the whole app in advanced, and follows the preference as it changes', (tester) async {
    await open(tester, experience: 'advanced');
    await settle(tester);
    expect(shellWidget(tester).simple, isFalse);
    expect(bar('Organizations'), findsOneWidget);
    expect(bar('Notifications'), findsOneWidget);
    expect(bar('Forward again'), findsOneWidget);
    expect(tester.widget<HomeScreen>(find.byType(HomeScreen)).simple, isFalse);
    expect(dockOrder(tester, within: find.byType(HomeScreen)).first, 'claude');
    final shell = shellOf(tester);
    final docked = partOf<NoteTree>(shell.context, shellWidget(tester).dockedSidebarBuilder!(shell.context, shell));
    expect(docked.simple, isFalse);
    expect(docked.onTags, isNotNull);
    expect(docked.onGraph, isNotNull);
    expect(tester.widget<NewSheet>(find.byType(NewSheet)).simple, isFalse);

    // Simple chosen (Settings, the card): every surface hears it on the next frame.
    preferences.update((now) => now.choosing('simple'));
    await settle(tester);
    expect(shellWidget(tester).simple, isTrue);
    expect(bar('Organizations'), findsNothing);
    expect(tester.widget<HomeScreen>(find.byType(HomeScreen)).simple, isTrue);
    expect(dockOrder(tester, within: find.byType(HomeScreen)), isNot(contains('claude')));
    // The + sheet is built as it opens (its part sleeps while it is shut), and opens on Note and More.
    tester.widget<HomeScreen>(find.byType(HomeScreen)).onNew();
    await settle(tester);
    expect(tester.widget<NewSheet>(find.byType(NewSheet)).simple, isTrue);
    expect(find.text('More…'), findsOneWidget);
    tester.widget<NewSheet>(find.byType(NewSheet)).onClose();
    await settle(tester);
    final again = partOf<NoteTree>(shell.context, shellWidget(tester).dockedSidebarBuilder!(shell.context, shell));
    expect(again.simple, isTrue);
    expect(again.onTags, isNull);

    // And back.
    preferences.update((now) => now.choosing('advanced'));
    await settle(tester);
    expect(shellWidget(tester).simple, isFalse);
    expect(bar('Organizations'), findsOneWidget);
    expect(dockOrder(tester, within: find.byType(HomeScreen)).first, 'claude');
    await close(tester);
  });
  testWidgets('asks an install from before the choice once, on home, and the answer is the preference (Matt, 2026-10-18: "existing users see it on the card one time")', (tester) async {
    // The walkthrough was seen on this device long ago, and no mode was ever chosen, here or elsewhere.
    final kept = MemoryStored({guideSeenKey: '1'});
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, stored: kept),
    );
    await settle(tester);
    expect(preferences.value.experienceChosen, isFalse);
    expect(find.byType(ExperienceCard), findsOneWidget);
    // The whole app meanwhile: unchosen reads as advanced.
    expect(shellWidget(tester).simple, isFalse);

    await tester.tap(find.descendant(of: find.byType(ExperienceCard), matching: find.bySemanticsLabel('Simple')));
    await settle(tester);
    expect((preferences.value.experience, preferences.value.experienceChosen, preferences.value.noteView), ('simple', true, 'formatted'));
    expect(find.byType(ExperienceCard), findsNothing);
    expect(shellWidget(tester).simple, isTrue);
    await close(tester);
  });

  testWidgets('does not ask an install that never saw the walkthrough: that one is asked by the walkthrough itself', (tester) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, stored: MemoryStored()),
    );
    await settle(tester);
    expect(find.byType(ExperienceCard), findsNothing);
    await close(tester);
  });
}
