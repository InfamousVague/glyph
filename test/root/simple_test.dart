import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/claude/claude_settings.dart' show claudeSettings;
import 'package:ghost_md/note/note_tools.dart' show NoteSimpleHeader;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/notes/all_notes_screen.dart';
import 'package:ghost_md/notes/new_sheet.dart';
import 'package:ghost_md/note/note_screen.dart' show NoteScreen;
import 'package:ghost_md/notes/note_tabs.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/notes/notes_drawer.dart';
import 'package:ghost_md/notes/notices.dart' show ExperienceCard;
import 'package:ghost_md/guide/guide_state.dart' show guideSeenKey, guideSeenValue;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/header_toolbar.dart' show HeaderAct;
import 'package:ghost_md/shell/page_dock.dart' show PageDock;
import 'package:ghost_md/simple/simple_todos.dart' show SimpleTodos;
import 'package:ghost_md/simple/simple_home.dart';

import '../shell/dock_support.dart' show dockOrder;
import '../support/render.dart';
import 'part_of.dart';

/// Simple mode through the root (GHST-103; Matt, 2026-10-17: "allow selecting between simple and advanced mode
/// where simple mode has a much more approachable UI with fancy features hidden behind more"): the root reads the
/// experience preference and hands each surface its answer, and a change of the preference reaches every one of
/// them at once. Each surface's own trimming is its own test; here is that the root says so to each.
///
/// Since GHST-105 (Matt, 2026-10-18: "it still is a bit complex with the tabs and such") simple mode's home page is
/// lib/simple/simple_home.dart in place of HomeScreen, and the shell draws no bar over it: the cases that held the
/// bar to a trim, and the advanced page to its simple dock, are the new truth's now.
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

  /// The bar's button for you (lib/shell/header/header_kit.dart `youAct`), in the bar's own row.
  Finder you() => find.descendant(of: find.byType(NoteTabs), matching: find.byKey(HeaderAct.keyOf('you')));

  testWidgets('tells the shell, the home page, the sidebars, the + and All notes they are simple, and takes Claude off the docks', (tester) async {
    await open(tester, experience: 'simple');
    await settle(tester);
    expect(preferences.value.simple, isTrue);

    // The shell: no bar at all over the home page (GHST-105), and the simple page in HomeScreen's place.
    expect(shellWidget(tester).simple, isTrue);
    expect(find.byType(NoteTabs), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    final home = tester.widget<SimpleHome>(find.byType(SimpleHome));
    expect(home.pane, isFalse, reason: 'a phone: the page is the whole window');
    expect(home.onSettings, isNotNull);
    expect(home.onNewLong, isNotNull);
    expect(home.onSpeak, isNull, reason: 'this build records nothing and Claude is off: no microphone');
    expect(find.byKey(const ValueKey('simple-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('simple-new')), findsOneWidget);
    expect(find.byKey(const ValueKey('simple-speak')), findsNothing);
    expect(find.byType(PageDock), findsNothing, reason: 'no dock of rings on the simple page');

    // The card's sidebar, though the plain shell draws it not: no Browse files, graph, Tags or smart notebooks, and
    // the tree's own tools trimmed, for whoever asks the builder. (The wide window's is advanced mode's alone, and is
    // simple's list itself: lib/root/root_parts.dart `_listColumn`.)
    final shell = shellOf(tester);
    expect(find.byType(NoteTree), findsNothing);
    expect(find.byType(NotesDrawer), findsNothing);
    final drawer = partOf<NotesDrawer>(shell.context, shellWidget(tester).sidebarBuilder!(shell.context, shell, () {}));
    expect(drawer.simple, isTrue);
    expect(drawer.onTags, isNull);
    // The Market is advanced mode's, as Settings › Plugins was (Matt, 2026-10-26).
    expect(drawer.onMarket, isNull);
    expect(drawer.onGraph, isNull);
    expect(drawer.smart, isNull);

    // The +: Note, then More.
    expect(tester.widget<NewSheet>(find.byType(NewSheet)).simple, isTrue);

    // All notes: no pills, no Save, and its dock Search, +, Settings with no Claude.
    shell.showAllNotes();
    await settle(tester);
    final all = tester.widget<AllNotesScreen>(find.byType(AllNotesScreen));
    expect(all.simple, isTrue);
    expect(all.onSaveSearch, isNull);
    final dock = dockOrder(tester, within: find.byType(AllNotesScreen));
    expect(dock, isNot(contains('claude')));
    expect(dock, containsAllInOrder(['search', 'add', 'settings']));
    expect(find.byType(NoteTabs), findsNothing, reason: 'no bar over All notes either');
    await close(tester);
  });

  testWidgets('opens a note from the simple page in the one tab there is, with its own Back, and leaves it on the way home', (tester) async {
    final library = await open(tester, experience: 'simple');
    await settle(tester);
    final standup = library.value.firstWhere((note) => note.body.startsWith('# Monday standup'));
    await tester.tap(find.byKey(ValueKey('simple-row-${standup.id}')));
    await settle(tester);
    expect(shellOf(tester).shown, standup.id);
    expect(preferences.value.openNotes, [standup.id]);
    expect(find.byType(NoteTabs), findsNothing);
    final screen = tester.widget<NoteScreen>(find.byType(NoteScreen));
    expect(screen.back, isTrue, reason: 'no bar with Home: the note draws its own Back');
    await tester.tap(find.byKey(NoteSimpleHeader.backKey));
    await settle(tester);
    expect(find.byType(SimpleHome), findsOneWidget);
    expect(preferences.value.openNotes, isEmpty);
    await close(tester);
  });

  testWidgets('is the whole app in advanced, and follows the preference as it changes', (tester) async {
    // Claude heads the advanced dock once an API key is entered (2026-10-19); with none it is not there at all.
    await tester.runAsync(() => claudeSettings.setKey('sk-ant-test-0000000000'));
    addTearDown(() => claudeSettings.setKey(null));
    await open(tester, experience: 'advanced');
    await settle(tester);
    expect(shellWidget(tester).simple, isFalse);
    // Advanced's bar, Grouped command's by default: the button for you, which holds the bell, the organizations and
    // Settings, and Home.
    expect(you(), findsOneWidget);
    expect(find.byKey(HeaderAct.keyOf('home')), findsOneWidget);
    expect(tester.widget<HomeScreen>(find.byType(HomeScreen)).simple, isFalse);
    expect(dockOrder(tester, within: find.byType(HomeScreen)).first, 'claude');
    final shell = shellOf(tester);
    // The sidebar on a wide window is simple's list (Matt, 2026-10-24), under the bar, with no gear of its own.
    final docked = partOf<SimpleHome>(shell.context, shellWidget(tester).dockedSidebarBuilder!(shell.context, shell));
    expect((docked.pane, docked.underBar, docked.onSettings), (true, true, null));
    final drawer = partOf<NotesDrawer>(shell.context, shellWidget(tester).sidebarBuilder!(shell.context, shell, () {}));
    expect(drawer.onTags, isNotNull);
    expect(drawer.onMarket, isNotNull);
    expect(drawer.onGraph, isNotNull);
    expect(tester.widget<NewSheet>(find.byType(NewSheet)).simple, isFalse);

    // Simple chosen (Settings, the card): every surface hears it on the next frame.
    preferences.update((now) => now.choosing('simple'));
    await settle(tester);
    expect(shellWidget(tester).simple, isTrue);
    expect(find.byType(NoteTabs), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(SimpleHome), findsOneWidget);
    // The + sheet is built as it opens (its part sleeps while it is shut), and opens on Note and More: from the +
    // held, since a press makes a note straight away.
    tester.widget<SimpleHome>(find.byType(SimpleHome)).onNewLong!();
    await settle(tester);
    expect(tester.widget<NewSheet>(find.byType(NewSheet)).simple, isTrue);
    expect(find.text('More…'), findsOneWidget);
    tester.widget<NewSheet>(find.byType(NewSheet)).onClose();
    await settle(tester);
    final again = partOf<NotesDrawer>(shell.context, shellWidget(tester).sidebarBuilder!(shell.context, shell, () {}));
    expect(again.simple, isTrue);
    expect(again.onTags, isNull);
    expect(again.onMarket, isNull);

    // And back.
    preferences.update((now) => now.choosing('advanced'));
    await settle(tester);
    expect(shellWidget(tester).simple, isFalse);
    expect(you(), findsOneWidget);
    expect(find.byType(SimpleHome), findsNothing);
    expect(dockOrder(tester, within: find.byType(HomeScreen)).first, 'claude');
    await close(tester);
  });
  testWidgets('asks an install from before the choice once, on home, and the answer is the preference (Matt, 2026-10-18: "existing users see it on the card one time")', (tester) async {
    // The walkthrough was seen on this device long ago, and no mode was ever chosen, here or elsewhere.
    final kept = MemoryStored({guideSeenKey: guideSeenValue});
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, stored: kept),
    );
    await settle(tester);
    expect(preferences.value.experienceChosen, isFalse);
    expect(find.byType(ExperienceCard), findsOneWidget);
    // It says where the choice is kept from then on: Appearance's first card since 2026-10-24.
    expect(find.descendant(of: find.byType(ExperienceCard), matching: find.textContaining('Change it any time in Settings › Appearance.')), findsOneWidget);
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
  testWidgets('the To-dos tab lists every open to-do across the notes, and a tick is written into its note (GHST-105)', (tester) async {
    final library = await open(tester, experience: 'simple');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('simple-tab-todos')));
    await settle(tester);
    expect(find.byType(SimpleTodos), findsOneWidget);
    expect(find.bySemanticsLabel('Tick Send the deposit'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Tick Send the deposit'));
    await settle(tester, 8);
    final flat = library.value.firstWhere((note) => note.body.contains('Send the deposit'));
    expect(flat.body, contains('- [x] Send the deposit'));
    await close(tester);
  });
}
