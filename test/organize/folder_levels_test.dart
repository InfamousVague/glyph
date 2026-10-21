import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note_marks.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/notes/all_notes_screen.dart';
import 'package:ghost_md/notes/icon_browser.dart';
import 'package:ghost_md/orgs/ui/organization_screen.dart';

import '../orgs_ui/support.dart' show Device, endSettings, ghost;
import '../support/render.dart';
import 'support.dart';

/// Browsing folders level by level (Matt, 2026-10-20: "When navigating into a folder sub folders should share the
/// same ability to have icons or list keeping the parents selection, additionally we should be able to nest folders
/// and files this way"): cards or icons chosen at a level carries down to the folders under it, the toggle is at
/// every level, New folder and New note make things in the level shown, and back goes up a level. Over the invented
/// library (Work › Clients › Kiln, Home › Garden, Reading alone).
void main() {
  setUpAll(loadAppFonts);
  setUp(NoteMarks.debugForget);

  const list = [
    Workspace(id: 'work', name: 'Work'),
    Workspace(id: 'clients', name: 'Clients', parent: 'work'),
    Workspace(id: 'kiln', name: 'Kiln', parent: 'clients'),
    Workspace(id: 'home', name: 'Home'),
  ];

  group('the view at a level', () {
    test('is cards until chosen, and the top’s choice wherever nothing below it chose', () {
      final kept = MemoryStored();
      expect(browseViewAt(list, null, kept), BrowseView.cards);
      expect(browseViewAt(list, 'kiln', kept), BrowseView.cards);
      // The device's one choice from before levels had their own reads as the top's.
      kept.writeText(browseViewKey, 'icons');
      expect(browseViewAt(list, 'kiln', kept), BrowseView.icons);
      expect(browseViewAt(list, 'home', kept), BrowseView.icons);
    });

    test('chosen at a workspace carries down to its folders at any depth, and nowhere else', () {
      final kept = MemoryStored();
      chooseBrowseView(list, 'work', BrowseView.icons, kept);
      expect(browseViewAt(list, 'work', kept), BrowseView.icons);
      expect(browseViewAt(list, 'clients', kept), BrowseView.icons);
      expect(browseViewAt(list, 'kiln', kept), BrowseView.icons);
      expect(browseViewAt(list, 'home', kept), BrowseView.cards);
      expect(browseViewAt(list, null, kept), BrowseView.cards);
    });

    test('chosen at a folder holds for it and those under it; chosen above again, the folder’s own is let go', () {
      final kept = MemoryStored();
      chooseBrowseView(list, 'work', BrowseView.icons, kept);
      chooseBrowseView(list, 'clients', BrowseView.cards, kept);
      expect(browseViewAt(list, 'work', kept), BrowseView.icons);
      expect(browseViewAt(list, 'clients', kept), BrowseView.cards);
      expect(browseViewAt(list, 'kiln', kept), BrowseView.cards);
      // Work chosen again: everything under it follows, Clients' cards forgotten.
      chooseBrowseView(list, 'work', BrowseView.icons, kept);
      expect(browseViewAt(list, 'clients', kept), BrowseView.icons);
      expect(browseViewAt(list, 'kiln', kept), BrowseView.icons);
      expect(kept.readText(browseViewsKey), '{"work":"icons"}');
    });

    test('a choice that is what the level shows anyway is not kept as its own, and the top’s lets every level’s go', () {
      final kept = MemoryStored();
      chooseBrowseView(list, 'kiln', BrowseView.cards, kept);
      expect(kept.readText(browseViewsKey), isNull);
      chooseBrowseView(list, 'kiln', BrowseView.icons, kept);
      chooseBrowseView(list, 'home', BrowseView.icons, kept);
      expect(kept.readText(browseViewsKey), '{"kiln":"icons","home":"icons"}');
      chooseBrowseView(list, null, BrowseView.cards, kept);
      expect(kept.readText(browseViewsKey), isNull);
      expect(kept.readText(browseViewKey), 'cards');
      expect(browseViewAt(list, 'kiln', kept), BrowseView.cards);
    });

    test('forgets the choices of workspaces the list no longer has, and reads nothing it cannot parse', () {
      final kept = MemoryStored()..writeText(browseViewsKey, '{"gone":"icons","work":"sideways"}');
      expect(browseViewAt(list, 'work', kept), BrowseView.cards);
      chooseBrowseView(list, 'home', BrowseView.icons, kept);
      expect(kept.readText(browseViewsKey), '{"home":"icons"}');
      kept.writeText(browseViewsKey, 'not json');
      expect(browseViewAt(list, 'home', kept), BrowseView.cards);
    });
  });

  Future<void> page(WidgetTester tester, Widget child, {Size size = const Size(390, 844)}) async {
    await pumpApp(tester, size: size, prefs: const AppPreferences(theme: 'light'), home: BackScope(child: child));
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> down(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  WorkspaceStore spaces() => WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()));

  Finder key(String value) => find.byKey(ValueKey(value));

  /// The note [id] as home lists it: a card, a row or a line, as the layout draws its section.
  Finder listed(String id) => find.byWidgetPredicate((w) => w.key is ValueKey<String> && const ['card-', 'row-', 'line-'].any((kind) => (w.key! as ValueKey<String>).value == '$kind$id'));

  for (final (name, size) in [('a phone', const Size(390, 844)), ('the Fold opened out', const Size(884, 1104)), ('a Mac window', const Size(1280, 900))]) {
    group('on home, on $name', () {
      Widget home(WorkspaceStore store, Stored kept, {List<String>? folders, List<String>? notes}) => HomeScreen(
            notes: organizeNotes(),
            workspaces: store,
            onOpen: (_) {},
            onNew: () {},
            onAllNotes: () {},
            onSearch: () {},
            clock: () => organizeNow,
            onNewFolder: (parent) => folders?.add(parent ?? ''),
            onNewNote: (at) => notes?.add(at),
            stored: kept,
          );

      testWidgets('the toggle is at every level, and icons chosen at Work is the view in Clients and in Kiln', (tester) async {
        final store = spaces()..chooseWorkspace('work');
        final kept = MemoryStored();
        await page(tester, home(store, kept), size: size);
        await settle(tester);
        expect(key('home-view'), findsOneWidget);
        expect(key('home-icons'), findsNothing, reason: 'cards until chosen');
        expect(key('folder-chip-clients'), findsOneWidget);
        await tester.tap(key('view-icons'));
        await settle(tester);
        expect(key('home-icons'), findsOneWidget);
        // The folders are the first tiles, not chips; Work's own note beside them.
        expect(key('folder-chip-clients'), findsNothing);
        expect(key('tile-folder-clients'), findsOneWidget);
        expect(key('tile-note-roadmap'), findsOneWidget);
        expect(key('tile-note-invoice'), findsNothing, reason: 'Clients’, behind its tile');

        await tester.tap(key('tile-folder-clients'));
        await settle(tester);
        expect(store.value.current?.id, 'clients');
        expect(key('home-view'), findsOneWidget);
        expect(key('home-icons'), findsOneWidget, reason: 'Work’s choice carries down');
        expect(key('tile-note-invoice'), findsOneWidget);

        await tester.tap(key('tile-folder-kiln'));
        await settle(tester);
        expect(store.value.current?.id, 'kiln');
        expect(key('home-view'), findsOneWidget);
        expect(key('home-icons'), findsOneWidget);
        expect(key('tile-note-kickoff'), findsOneWidget);
        expect(find.bySemanticsLabel('In Work › Clients › Kiln'), findsOneWidget);

        // Cards chosen in Kiln: Kiln's alone, Clients above it still icons.
        await tester.tap(key('view-cards'));
        await settle(tester);
        expect(key('home-icons'), findsNothing);
        expect(listed('kickoff'), findsOneWidget);
        await tester.tap(key('crumb-clients'));
        await settle(tester);
        expect(store.value.current?.id, 'clients');
        expect(key('home-icons'), findsOneWidget);
        // Home is not under Work: its cards.
        store.chooseWorkspace('home');
        await settle(tester);
        expect(key('home-view'), findsOneWidget);
        expect(key('home-icons'), findsNothing);
        await down(tester);
      });

      testWidgets('New folder and New note make things inside the level shown, in cards and in icons', (tester) async {
        final store = spaces()..chooseWorkspace('kiln');
        final kept = MemoryStored();
        final folders = <String>[], notes = <String>[];
        await page(tester, home(store, kept, folders: folders, notes: notes), size: size);
        await settle(tester);
        // Kiln has no folders: the strip is its New folder and New note.
        await tester.tap(key('folder-new'));
        await tester.tap(key('folder-new-note'));
        expect([folders, notes], [['kiln'], ['kiln']]);
        await tester.tap(key('view-icons'));
        await settle(tester);
        expect(key('folder-new'), findsNothing);
        await tester.tap(key('tile-folder-new'));
        await tester.tap(key('tile-note-new'));
        expect([folders, notes], [['kiln', 'kiln'], ['kiln', 'kiln']]);
        await down(tester);
      });

      testWidgets('back and Escape go up a level inside a folder, and are nothing of the page’s at a workspace at the top', (tester) async {
        final store = spaces()..chooseWorkspace('kiln');
        await page(tester, home(store, MemoryStored()), size: size);
        await settle(tester);
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(store.value.current?.id, 'clients');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(store.value.current?.id, 'work');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(store.value.current?.id, 'work', reason: 'at the top: the filter is the page’s to clear, as ever');
        await down(tester);
      });
    });
  }

  group('on All notes', () {
    Widget allNotes(WorkspaceStore store, Stored kept, {List<String>? folders, List<String>? notes, VoidCallback? onBack}) => AllNotesScreen(
          notes: organizeNotes(),
          workspaces: store,
          onOpen: (_) {},
          onBack: onBack ?? () {},
          stored: kept,
          clock: () => organizeNow,
          wisp: false,
          onNewFolder: (parent) => folders?.add(parent ?? ''),
          onNewNote: (at) => notes?.add(at ?? ''),
        );

    testWidgets('the toggle is at every level and the choice carries down; New folder and New note make things inside the level shown', (tester) async {
      final store = spaces()..chooseWorkspace('work');
      final kept = MemoryStored();
      final folders = <String>[], notes = <String>[];
      await page(tester, allNotes(store, kept, folders: folders, notes: notes));
      await settle(tester);
      await tester.tap(key('folder-new-note'));
      expect(notes, ['work']);
      await tester.tap(key('view-icons'));
      await settle(tester);
      for (final at in ['clients', 'kiln']) {
        await tester.tap(key('tile-folder-$at'));
        await settle(tester);
        expect(store.value.current?.id, at);
        expect(key('all-notes-view'), findsOneWidget);
        expect(key('all-notes-icons'), findsOneWidget, reason: 'Work’s icons, in $at');
      }
      await tester.tap(key('tile-folder-new'));
      await tester.tap(key('tile-note-new'));
      expect([folders, notes], [['kiln'], ['work', 'kiln']]);
      // At the top, New note files in none.
      store.chooseWorkspace(null);
      await settle(tester);
      expect(key('all-notes-icons'), findsNothing, reason: 'the top has its own choice: cards');
      await tester.tap(key('view-icons'));
      await settle(tester);
      await tester.tap(key('tile-note-new'));
      expect(notes.last, '');
      await down(tester);
    });

    testWidgets('back goes up a level inside a folder, and home from a workspace at the top', (tester) async {
      final store = spaces()..chooseWorkspace('kiln');
      var home = 0;
      await page(
        tester,
        // The shell's own OnBack for the page, under the page's.
        Builder(builder: (context) => OnBack(onBack: () => home += 1, child: allNotes(store, MemoryStored(), onBack: () => home += 1))),
      );
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect((store.value.current?.id, home), ('clients', 0));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect((store.value.current?.id, home), ('work', 0));
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect((store.value.current?.id, home), ('work', 1));
      await down(tester);
    });
  });

  group('on an organization’s dashboard', () {
    testWidgets('icons chosen on it is what its folders open in on home, and New note there is filed in its workspace', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      final launch = device.workspaces.addWorkspace('Launch', 'moss', orgWorkspaceId(id))!;
      final notes = [device.keep('n1', '# Launch plan', at: 3000), device.keep('n2', '# Press list', at: 2000)];
      device.workspaces.fileNote('n1', launch.id);
      device.workspaces.fileNote('n2', orgWorkspaceId(id));
      final made = <String>[];
      await device.pump(
        tester,
        OrganizationScreen(
          services: device.services,
          orgId: id,
          notes: notes,
          wisp: false,
          onBack: () {},
          onOpenNote: (_) {},
          onNew: () {},
          onAllNotes: (_) {},
          onSettings: () {},
          onOpenOrganization: (_) {},
          onLog: () {},
          onAccount: () {},
          onNewFolder: (_) {},
          onNewNote: made.add,
        ),
        scroll: false,
      );
      await settle(tester);
      expect(key('org-notes-view'), findsOneWidget);
      await tester.tap(key('folder-new-note'));
      expect(made, [orgWorkspaceId(id)]);
      await tester.tap(key('view-icons'));
      await settle(tester);
      await tester.tap(key('tile-note-new'));
      expect(made, [orgWorkspaceId(id), orgWorkspaceId(id)]);
      // Launch, on home, opens in the dashboard's icons.
      expect(browseViewAt(device.workspaces.value.list, launch.id, device.kept), BrowseView.icons);
      await endSettings(tester);
    });
  });
}
