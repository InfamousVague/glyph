import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/aside/aside.dart' show readSidebarShown, writeSidebarShown;
import 'package:ghost_md/commands/command_bar.dart';
import 'package:ghost_md/commands/palette.dart';
import 'package:ghost_md/core/library_folder.dart' show filesChannel;
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/notes/all_notes_screen.dart';
import 'package:ghost_md/notes/note_tabs.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/notes/notes_drawer.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/app_tab_bar.dart';
import 'package:ghost_md/shell/desktop/mac_lights.dart';
import 'package:ghost_md/shell/wide_screen.dart' show simpleListColumn;
import 'package:ghost_md/simple/simple_home.dart';

import '../support/render.dart';

/// Advanced mode's sidebar on a wide window, in the app put together (Matt, 2026-10-24: "make the sidebar on advanced
/// mode the same as simple but just hide it by default"): simple mode's list in a column beside the note, hidden until
/// the bar's panel icon shows it and then kept as it was left; the Mac's bar and window buttons where they were, and
/// the note not made again as the column comes and goes; a phone's card as before; and everything the old tree held
/// still reached from somewhere in advanced mode.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const mac = Size(1280, 800);
  const fold = Size(704, 933);
  const phone = Size(390, 844);

  Future<SampleLibrary> open(WidgetTester tester, {required Size size, double ratio = 2, String sidebar = 'popover', String experience = 'advanced', Stored? stored}) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      size: size,
      ratio: ratio,
      prefs: Preferences(theme: 'light', sidebarStyle: sidebar, experience: experience, experienceChosen: true),
      home: GhostRoot(launch: false, library: library, stored: stored ?? MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    if (size == mac) {
      tester.view.padding = FakeViewPadding.zero;
      tester.view.viewPadding = FakeViewPadding.zero;
    }
    await tester.pump(const Duration(milliseconds: 100));
    return library;
  }

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));
  Finder bar(String label) => find.descendant(of: find.byType(NoteTabs), matching: find.bySemanticsLabel(label)).first;
  Finder column() => find.bySemanticsLabel('Your notes');

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    debugDefaultTargetPlatformOverride = null;
  }

  /// On the Mac: the platform the window buttons and the mouse are asked of, put back by [close].
  void onMac() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

  group('on the Mac', () {
    testWidgets('starts hidden, and the bar\'s panel icon shows simple\'s list beside the note and hides it, kept to the device', (tester) async {
      onMac();
      final local = MemoryStored();
      final library = await open(tester, size: mac, stored: local);
      expect(column(), findsNothing, reason: 'hidden by default, even under a mouse');
      expect(find.byType(SimpleHome), findsNothing);
      expect(find.byType(NoteTree), findsNothing);
      expect(readSidebarShown(local), isNull);

      // A note opens the whole window wide, as it did with the sidebar shut.
      final groceries = library.value.firstWhere((note) => noteTitle(note.body) == 'Groceries');
      shellOf(tester).openNote(groceries.id);
      await settle(tester);
      final note = tester.state<NoteScreenState>(find.byType(NoteScreen));
      expect(tester.getRect(find.byType(NoteScreen)).left, 0);
      final barAt = tester.getRect(find.byType(AppTabBar));
      final controls = {for (final label in ['All your notes', 'Home', 'Settings', 'Organizations']) label: tester.getRect(bar(label))};
      final lights = tester.getCenter(find.byType(MacLightsRow).last);

      await tester.tap(bar('All your notes'));
      await settle(tester);
      expect(readSidebarShown(local), isTrue);
      // Simple mode's list, as simple draws it beside a note, under the bar: no gear (the bar's cog is over it) and
      // no row of its own for the window buttons (the bar's top row holds them).
      final home = tester.widget<SimpleHome>(find.byType(SimpleHome));
      expect((home.pane, home.underBar, home.onSettings), (true, true, null));
      expect(tester.getRect(column()), Rect.fromLTWH(0, 0, simpleListColumn(mac.width), mac.height));
      expect(find.byKey(const ValueKey('simple-lights')), findsNothing);
      expect(find.byKey(const ValueKey('simple-settings')), findsNothing);
      expect(find.byKey(const ValueKey('simple-switch')), findsOneWidget);
      // No + and no microphone at its foot: the page's dock has both (Matt, 2026-10-29: "remove these icons from the
      // sidebar").
      expect(find.byKey(const ValueKey('simple-new')), findsNothing);
      expect(find.byKey(const ValueKey('simple-speak')), findsNothing);
      // Its title starts under the bar, not under it.
      expect(tester.getRect(find.text('Notes').first).top, greaterThan(barAt.bottom));
      // The note is the same screen, beside it; the bar, its controls and the window buttons have not moved.
      expect(tester.state<NoteScreenState>(find.byType(NoteScreen)), same(note));
      expect(tester.getRect(find.byType(NoteScreen)).left, simpleListColumn(mac.width));
      expect(tester.getRect(find.byType(AppTabBar)), barAt);
      for (final MapEntry(:key, :value) in controls.entries) {
        expect(tester.getRect(bar(key)), value, reason: key);
      }
      expect(tester.getCenter(find.byType(MacLightsRow).last), lights);

      // A row opens its note in advanced's way, a tab of its own, the list staying where it is.
      final standup = library.value.firstWhere((note) => note.body.startsWith('# Monday standup'));
      await tester.tap(find.byKey(ValueKey('simple-row-${standup.id}')));
      await settle(tester);
      expect(shellOf(tester).shown, standup.id);
      expect(shellOf(tester).tabs.open, containsAll([groceries.id, standup.id]));
      expect(column(), findsOneWidget);

      // And hidden again, which is kept too.
      await tester.tap(bar('All your notes'));
      await settle(tester);
      expect(column(), findsNothing);
      expect(readSidebarShown(local), isFalse);
      expect(tester.getRect(find.byType(NoteScreen)).left, 0);
      await close(tester);
    });

    testWidgets('opens as the device left it', (tester) async {
      onMac();
      final local = MemoryStored();
      writeSidebarShown(true, local);
      await open(tester, size: mac, stored: local);
      expect(column(), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget, reason: 'advanced home beside it');
      await close(tester);
    });

    testWidgets('starts hidden once for whoever had the old tree open', (tester) async {
      onMac();
      final local = MemoryStored()..setItem('glyph-sidebar-shown', '1');
      await open(tester, size: mac, sidebar: 'docked', stored: local);
      expect(column(), findsNothing);
      expect(find.byType(NoteTree), findsNothing);
      await tester.tap(bar('All your notes'));
      await settle(tester);
      expect(column(), findsOneWidget);
      expect(local.getItem('glyph-sidebar-shown'), isNull, reason: 'the old switch is forgotten at the first toggle');
      await close(tester);
    });

    testWidgets('simple mode is as it was: the list always beside the note, with its gear and its row for the window buttons', (tester) async {
      onMac();
      await open(tester, size: mac, experience: 'simple');
      expect(find.byType(NoteTabs), findsNothing);
      final home = tester.widget<SimpleHome>(find.byType(SimpleHome));
      expect((home.pane, home.underBar, home.onSettings != null, home.onBrowseFiles), (true, false, true, null));
      expect(find.byKey(const ValueKey('simple-lights')), findsOneWidget);
      expect(find.byKey(const ValueKey('simple-settings')), findsOneWidget);
      expect(tester.getRect(column()).width, simpleListColumn(mac.width));
      await close(tester);
    });
  });

  group('on the Fold opened out', () {
    for (final style in ['popover', 'docked']) {
      testWidgets('is the same list, hidden until asked for, with $style chosen', (tester) async {
        final local = MemoryStored();
        await open(tester, size: fold, ratio: 2.625, sidebar: style, stored: local);
        expect(column(), findsNothing);
        await tester.tap(bar('All your notes'));
        await settle(tester);
        expect(find.byType(NotesDrawer), findsNothing, reason: 'no card on a wide window');
        expect(tester.getRect(column()).width, simpleListColumn(fold.width));
        expect(find.byType(SimpleHome), findsOneWidget);
        expect(readSidebarShown(local), isTrue);
        await close(tester);
      });
    }

    testWidgets('carries Browse files at the foot of the list once the phone has said it can show the folder', (tester) async {
      final asked = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(filesChannel, (call) async {
        asked.add(call.method);
        return switch (call.method) { 'canBrowseFiles' => true, 'browseFiles' => null, _ => throw MissingPluginException() };
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(filesChannel, null));
      final local = MemoryStored();
      writeSidebarShown(true, local);
      await open(tester, size: fold, ratio: 2.625, stored: local);
      await settle(tester);
      final tool = find.descendant(of: column(), matching: find.bySemanticsLabel('Browse files'));
      expect(tool, findsOneWidget);
      await tester.tap(tool);
      await tester.pump();
      expect(asked, ['canBrowseFiles', 'browseFiles']);
      await close(tester);
    });
  });

  testWidgets('a phone keeps the card of the tree, and no column', (tester) async {
    final local = MemoryStored();
    writeSidebarShown(true, local);
    await open(tester, size: phone, stored: local);
    expect(column(), findsNothing);
    await tester.tap(bar('All your notes'));
    await settle(tester);
    expect(find.byType(NotesDrawer), findsOneWidget);
    expect(find.byType(NoteTree), findsOneWidget);
    expect(find.byType(SimpleHome), findsNothing);
    await close(tester);
  });

  // What the tree held that simple's list does not, and where each is in advanced mode on a wide window.
  testWidgets('everything the old tree held is still reached on a wide window', (tester) async {
    onMac();
    final local = MemoryStored();
    writeSidebarShown(true, local);
    await open(tester, size: mac, stored: local);
    final shell = shellOf(tester);

    // Home, a press of the bar's house away: the workspaces and their folders, New folder, a workspace's sheet,
    // and All notes.
    expect(bar('Home'), findsOneWidget);
    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    expect(home.workspaces.value.list.map((space) => space.name), containsAll(['Work', 'Home']));
    expect((home.onNewFolder != null, home.onManageWorkspace != null), (true, true));

    // The organizations: the bar's people icon (its picker, or Settings › Organizations).
    expect(bar('Organizations'), findsOneWidget);

    // All notes: the folders and New folder, the archive, and the trash's word while it holds any.
    shell.showAllNotes();
    await settle(tester);
    final all = tester.widget<AllNotesScreen>(find.byType(AllNotesScreen));
    expect((all.onNewFolder != null, all.notesInWorkspace != null, all.onTrash != null), (true, true, true));

    // The palette (the dock's Search, or its shortcut): All notes, the Trash, Tags, the graph, each workspace,
    // and Organizations.
    final palette = tester.widget<CommandBar>(find.byType(CommandBar));
    final offered = [for (final command in paletteCommands(palette.worldNow!(), palette.doingNow!())) command.descriptor.label];
    expect(offered, containsAll(['All notes', 'Trash', 'Tags', 'Graph of your notes', 'Show Work', 'Show Home', 'Organizations']));
    await close(tester);
  });
}
