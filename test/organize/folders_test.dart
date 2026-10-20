import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_marks.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/notes/all_notes_screen.dart';
import 'package:ghost_md/notes/folder_strip.dart';
import 'package:ghost_md/notes/icon_browser.dart';
import 'package:ghost_md/orgs/ui/organization_screen.dart';

import '../orgs_ui/support.dart' show Device, endSettings, ghost;
import '../support/render.dart';
import 'support.dart';

/// The folders above the lists and the icon view (GHST-107; Matt, 2026-10-19: "I'd like to be able to sort notes
/// into folders and display them above the flat lists and support showing a icon file browser based view in
/// addition to the list views"): on home, on All notes, and on an organization's dashboard, over the invented
/// library (Work › Clients › Kiln, Home › Garden, Reading alone).
void main() {
  setUpAll(loadAppFonts);
  setUp(NoteMarks.debugForget);

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

  /// A chip's words as the page says them: "Clients, 2 notes".
  String? chip(WidgetTester tester, String id) {
    final found = find.byKey(ValueKey('folder-chip-$id'));
    if (found.evaluate().isEmpty) return null;
    return tester.getSemantics(found).label;
  }

  group('the folders and their counts', () {
    test('are the workspaces inside the chosen one, each counting its notes and those of the folders under it, never the archive', () {
      final sheet = organizeSpaces();
      final tiles = folderTiles(sheet.list, sheet.notes, organizeNotes(), 'work');
      expect(tiles.map((t) => t.folder.name), ['Clients']);
      // Clients holds the invoice, and Kiln inside it the kickoff.
      expect(tiles.single.count, 2);
      expect(folderTiles(sheet.list, sheet.notes, organizeNotes(), 'home').map((t) => '${t.folder.name} ${t.count}'), ['Garden 2']);
      expect(folderTiles(sheet.list, sheet.notes, organizeNotes(), 'reading'), isEmpty);
      // Work's own archived plan is not counted anywhere; the count of Work itself leaves it out too.
      expect(notesUnder(sheet.list, sheet.notes, organizeNotes(), 'work'), 3);
      expect(FolderStrip.shows(sheet.list, 'work'), isTrue);
      expect(FolderStrip.shows(sheet.list, 'kiln'), isTrue, reason: 'inside another: the line above is a way up');
      expect(FolderStrip.shows(sheet.list, 'reading'), isFalse);
    });

    test('read an organization’s workspace as a parent the moment one holds folders', () {
      // What slice 1 of GHST-107 will make: a folder whose parent is `org-<id>`. The strip asks nothing else.
      const list = [Workspace(id: 'org-acme', name: 'Acme', hue: 'violet'), Workspace(id: 'f1', name: 'Launch', parent: 'org-acme'), Workspace(id: 'f2', name: 'Press', parent: 'f1')];
      final notes = [Note(id: 'a', body: '# A', createdAt: 0, updatedAt: 0), Note(id: 'b', body: '# B', createdAt: 0, updatedAt: 0)];
      expect(folderTiles(list, const {'a': 'f1', 'b': 'f2'}, notes, 'org-acme').map((t) => '${t.folder.name} ${t.count}'), ['Launch 2']);
      expect(folderPath(list, 'f2').map((w) => w.name), ['Acme', 'Launch', 'Press']);
    });
  });

  group('on home', () {
    Widget home(WorkspaceStore store, {List<String>? made, bool simple = false}) => HomeScreen(
          notes: organizeNotes(),
          workspaces: store,
          onOpen: (_) {},
          onNew: () {},
          onAllNotes: () {},
          onSearch: () {},
          clock: () => organizeNow,
          onNewFolder: made == null ? null : (parent) => made.add(parent ?? ''),
          simple: simple,
        );

    testWidgets('draws the folders inside the chosen workspace with their counts, a tap enters one, and the line above is the way back', (tester) async {
      final store = spaces()..chooseWorkspace('work');
      final made = <String>[];
      await page(tester, home(store, made: made));
      await settle(tester);
      expect(find.byKey(const ValueKey('home-folders')), findsOneWidget);
      expect(find.bySemanticsLabel('Folders, 1'), findsOneWidget);
      expect(chip(tester, 'clients'), 'Clients, 2 notes');
      // At the top: no line above.
      expect(find.byKey(const ValueKey('folder-crumbs')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('folder-chip-clients')));
      await settle(tester);
      expect(store.value.current?.id, 'clients');
      expect(find.bySemanticsLabel('In Work › Clients'), findsOneWidget);
      expect(chip(tester, 'kiln'), 'Kiln, 1 note');
      expect(chip(tester, 'clients'), isNull);
      // New folder asks for one inside Clients.
      await tester.tap(find.byKey(const ValueKey('folder-new')));
      expect(made, ['clients']);
      // The first part of the line goes up to Work.
      await tester.tap(find.byKey(const ValueKey('crumb-work')));
      await settle(tester);
      expect(store.value.current?.id, 'work');
      expect(chip(tester, 'clients'), 'Clients, 2 notes');
      await down(tester);
    });

    testWidgets('offers New folder alone in a workspace with none, and draws nothing for every workspace or in simple mode', (tester) async {
      final store = spaces()..chooseWorkspace('reading');
      final made = <String>[];
      await page(tester, home(store, made: made));
      await settle(tester);
      // No folders in Reading yet: the strip is only its New folder, so the first one is plain to make (2026-10-19).
      expect(find.byKey(const ValueKey('home-folders')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('folder-chip-')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('folder-new')));
      expect(made, ['reading']);
      store.chooseWorkspace(null);
      await settle(tester);
      expect(find.byKey(const ValueKey('home-folders')), findsNothing);
      await down(tester);

      await page(tester, home(spaces()..chooseWorkspace('work'), made: [], simple: true));
      await settle(tester);
      expect(find.byKey(const ValueKey('home-folders')), findsNothing);
      await down(tester);
    });

    testWidgets('offers no New folder where the page has nowhere to make one', (tester) async {
      await page(tester, home(spaces()..chooseWorkspace('work')));
      await settle(tester);
      expect(chip(tester, 'clients'), isNotNull);
      expect(find.byKey(const ValueKey('folder-new')), findsNothing);
      await down(tester);
    });
  });

  group('on All notes', () {
    Widget allNotes(WorkspaceStore store, {Stored? stored, List<String>? opened, List<String>? made, bool simple = false}) => AllNotesScreen(
          notes: organizeNotes(),
          workspaces: store,
          onOpen: opened?.add ?? (_) {},
          onBack: () {},
          stored: stored ?? MemoryStored(),
          clock: () => organizeNow,
          wisp: false,
          onNewFolder: made == null ? null : (parent) => made.add(parent ?? ''),
          simple: simple,
        );

    testWidgets('draws the strip under the order words with a pill chosen, and a tap enters the folder', (tester) async {
      final store = spaces()..chooseWorkspace('work');
      await page(tester, allNotes(store));
      await settle(tester);
      expect(find.byKey(const ValueKey('folder-strip')), findsOneWidget);
      expect(chip(tester, 'clients'), 'Clients, 2 notes');
      // The strip stands between the order words and the cards.
      expect(tester.getTopLeft(find.byKey(const ValueKey('folder-strip'))).dy, greaterThan(tester.getBottomLeft(find.byKey(const ValueKey('all-notes-controls'))).dy));
      expect(tester.getTopLeft(find.byKey(const ValueKey('card-roadmap'))).dy, greaterThan(tester.getBottomLeft(find.byKey(const ValueKey('folder-strip'))).dy));
      await tester.tap(find.byKey(const ValueKey('folder-chip-clients')));
      await settle(tester);
      expect(store.value.current?.id, 'clients');
      expect(find.bySemanticsLabel('In Work › Clients'), findsOneWidget);
      expect(chip(tester, 'kiln'), 'Kiln, 1 note');
      // Clients' own note and Kiln's, as the pills always showed them.
      expect(find.byKey(const ValueKey('card-invoice')), findsOneWidget);
      expect(find.byKey(const ValueKey('card-kickoff')), findsOneWidget);
      await down(tester);
    });

    testWidgets('draws no strip with every note shown, for a workspace with no folders, or while a search is typed', (tester) async {
      final store = spaces();
      await page(tester, allNotes(store));
      await settle(tester);
      expect(find.byKey(const ValueKey('folder-strip')), findsNothing);
      store.chooseWorkspace('reading');
      await settle(tester);
      expect(find.byKey(const ValueKey('folder-strip')), findsNothing);
      store.chooseWorkspace('work');
      await settle(tester);
      expect(find.byKey(const ValueKey('folder-strip')), findsOneWidget);
      await tester.enterText(find.byType(EditableText).first, 'menu');
      await settle(tester);
      expect(find.byKey(const ValueKey('folder-strip')), findsNothing);
      await down(tester);
    });

    testWidgets('Icons lists the folders first, then the notes in the page’s order; a tap opens a note; the choice is kept', (tester) async {
      final store = spaces()..chooseWorkspace('work');
      final kept = MemoryStored();
      final opened = <String>[];
      await page(tester, allNotes(store, stored: kept, opened: opened));
      await settle(tester);
      expect(find.byKey(const ValueKey('all-notes-view')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('view-icons')));
      await settle(tester);
      expect(kept.readText(browseViewKey), 'icons');
      expect(find.byKey(const ValueKey('all-notes-icons')), findsOneWidget);
      // No strip apart from the tiles; the cards are gone.
      expect(find.byKey(const ValueKey('folder-strip')), findsNothing);
      expect(find.byKey(const ValueKey('card-roadmap')), findsNothing);
      final tiles = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('tile-'));
      expect([for (final e in tiles.evaluate()) (e.widget.key! as ValueKey<String>).value], ['tile-folder-clients', 'tile-note-kickoff', 'tile-note-invoice', 'tile-note-roadmap']);
      expect(tester.getSemantics(find.byKey(const ValueKey('tile-folder-clients'))).label, 'Clients, folder, 2 notes');
      expect(tester.getSemantics(find.byKey(const ValueKey('tile-note-kickoff'))).label, 'Kickoff with the shop, pinned, 1 hr ago');
      await tester.tap(find.byKey(const ValueKey('tile-note-roadmap')));
      expect(opened, ['roadmap']);
      // A folder's tile enters it, and the line above says where the page is.
      await tester.tap(find.byKey(const ValueKey('tile-folder-clients')));
      await settle(tester);
      expect(store.value.current?.id, 'clients');
      expect(find.bySemanticsLabel('In Work › Clients'), findsOneWidget);
      expect(find.byKey(const ValueKey('tile-folder-kiln')), findsOneWidget);
      await down(tester);

      // Opened again, the page is in icons: the choice was the device's.
      final again = spaces()..chooseWorkspace('home');
      await page(tester, allNotes(again, stored: kept));
      await settle(tester);
      expect(find.byKey(const ValueKey('all-notes-icons')), findsOneWidget);
      expect(find.byKey(const ValueKey('tile-note-seeds')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('view-cards')));
      await settle(tester);
      expect(kept.readText(browseViewKey), 'cards');
      expect(find.byKey(const ValueKey('card-seeds')), findsOneWidget);
      await down(tester);
    });

    testWidgets('Icons with nothing chosen: the workspaces at the top first, each with its count, then the notes in none; a tap on one chooses its pill', (tester) async {
      final store = spaces()..ensureOrgWorkspace(const OrgLike(id: 'acme', name: 'Acme', hue: 'violet'));
      store.fileNote('trip', 'org-acme');
      final kept = MemoryStored()..writeText(browseViewKey, 'icons');
      final opened = <String>[];
      final made = <String>[];
      await page(tester, allNotes(store, stored: kept, opened: opened, made: made));
      await settle(tester);
      expect(find.byKey(const ValueKey('all-notes-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('all-notes-icons')), findsOneWidget);
      // No line above at All, and no strip: the pills are the way across.
      expect(find.byKey(const ValueKey('folder-crumbs')), findsNothing);
      expect(find.byKey(const ValueKey('folder-strip')), findsNothing);
      final tiles = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('tile-'));
      final keys = [for (final e in tiles.evaluate()) (e.widget.key! as ValueKey<String>).value];
      // The workspaces at the top, in the order they were made (Clients, Kiln and Garden are inside others).
      expect(keys.take(4), ['tile-folder-work', 'tile-folder-home', 'tile-folder-reading', 'tile-folder-org-acme']);
      // Then the notes filed in no workspace, as a folder's own notes follow its folders (2026-10-19: no All, so the
      // root is a folder like any other; the list view is still every note).
      expect(keys.skip(4), ['tile-folder-new', 'tile-note-packing'], reason: 'New folder after the folders, a top-level one here');
      await tester.tap(find.byKey(const ValueKey('tile-folder-new')));
      expect(made, [''], reason: 'made at the top: no parent');
      // Work counts the roadmap, the invoice and the kickoff; the archived plan is left out.
      expect(tester.getSemantics(find.byKey(const ValueKey('tile-folder-work'))).label, 'Work, folder, 3 notes');
      expect(tester.getSemantics(find.byKey(const ValueKey('tile-folder-reading'))).label, 'Reading, folder, 1 note');
      expect(tester.getSemantics(find.byKey(const ValueKey('tile-folder-org-acme'))).label, 'Acme, organization, 1 note');
      // A tap on a workspace chooses its pill, and the page is that workspace's.
      await tester.tap(find.byKey(const ValueKey('tile-folder-work')));
      await settle(tester);
      expect(store.value.current?.id, 'work');
      expect(find.byKey(const ValueKey('tile-folder-clients')), findsOneWidget);
      expect(find.byKey(const ValueKey('tile-folder-home')), findsNothing);
      // And a note's tile still opens it.
      await tester.tap(find.byKey(const ValueKey('tile-note-roadmap')));
      expect(opened, ['roadmap']);
      await down(tester);
    });

    testWidgets('simple mode draws none of it: no strip, no view words, cards whatever the device kept', (tester) async {
      final kept = MemoryStored()..writeText(browseViewKey, 'icons');
      await page(tester, allNotes(spaces()..chooseWorkspace('work'), stored: kept, simple: true));
      await settle(tester);
      expect(find.byKey(const ValueKey('folder-strip')), findsNothing);
      expect(find.byKey(const ValueKey('all-notes-view')), findsNothing);
      expect(find.byKey(const ValueKey('all-notes-icons')), findsNothing);
      expect(find.byKey(const ValueKey('card-roadmap')), findsOneWidget);
      await down(tester);
    });
  });

  group('on an organization’s dashboard', () {
    testWidgets('offers Cards or Icons on its Notes heading, the device’s one choice, and the folders’ strip once its workspace holds one', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      final notes = [device.keep('n1', '# Launch plan', at: 3000), device.keep('n2', '# Press list', at: 2000)];
      for (final note in notes) {
        device.workspaces.fileNote(note.id, orgWorkspaceId(id));
      }
      final opened = <String>[];
      String? allNotesWith;
      var asked = 0;
      await device.pump(
        tester,
        OrganizationScreen(
          services: device.services,
          orgId: id,
          notes: notes,
          wisp: false,
          onBack: () {},
          onOpenNote: opened.add,
          onNew: () {},
          onAllNotes: (folder) {
            asked += 1;
            allNotesWith = folder;
          },
          onSettings: () {},
          onOpenOrganization: (_) {},
          onLog: () {},
          onAccount: () {},
          onNewFolder: (_) {},
        ),
        scroll: false,
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('org-notes-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('card-n1')), findsOneWidget);
      // No folder in the organization's workspace yet: the strip is its New folder alone.
      expect(find.byKey(const ValueKey('org-folders')), findsOneWidget);
      expect(find.byKey(const ValueKey('folder-new')), findsOneWidget);
      // The way to all of them, as it was.
      await tester.tap(find.byKey(const ValueKey('org-all-notes')));
      expect((asked, allNotesWith), (1, null));
      await tester.tap(find.byKey(const ValueKey('view-icons')));
      await settle(tester);
      expect(device.kept.readText(browseViewKey), 'icons');
      expect(find.byKey(const ValueKey('org-notes-icons')), findsOneWidget);
      expect(find.byKey(const ValueKey('card-n1')), findsNothing);
      expect(find.byKey(const ValueKey('tile-note-n1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tile-note-n2')));
      expect(opened, ['n2']);
      await endSettings(tester);
    });

    testWidgets('draws the folders inside its workspace once there are any (slice 1), a tap going to All notes with the folder chosen', (tester) async {
      final device = await Device.make();
      final id = await ghost(device);
      final launch = device.workspaces.addWorkspace('Launch', 'moss', orgWorkspaceId(id))!;
      final notes = [device.keep('n1', '# Launch plan', at: 3000), device.keep('n2', '# Press list', at: 2000)];
      device.workspaces.fileNote('n1', launch.id);
      device.workspaces.fileNote('n2', orgWorkspaceId(id));
      final made = <String>[];
      String? allNotesWith;
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
          onAllNotes: (folder) => allNotesWith = folder,
          onSettings: () {},
          onOpenOrganization: (_) {},
          onLog: () {},
          onAccount: () {},
          onNewFolder: (parent) => made.add(parent ?? ''),
        ),
        scroll: false,
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('org-folders')), findsOneWidget);
      expect(chip(tester, launch.id), 'Launch, 1 note');
      // The organization's workspace is the root: no line above.
      expect(find.byKey(const ValueKey('folder-crumbs')), findsNothing);
      // Both notes are the organization's, the folder's with them.
      expect(find.byKey(const ValueKey('card-n1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('folder-new')));
      expect(made, [orgWorkspaceId(id)]);
      await tester.tap(find.byKey(ValueKey('folder-chip-${launch.id}')));
      expect(allNotesWith, launch.id);
      // In icons, the folder is the first tile.
      await tester.tap(find.byKey(const ValueKey('view-icons')));
      await settle(tester);
      expect(find.byKey(const ValueKey('org-folders')), findsNothing);
      final tiles = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('tile-'));
      expect([for (final e in tiles.evaluate()) (e.widget.key! as ValueKey<String>).value], ['tile-folder-${launch.id}', 'tile-folder-new', 'tile-note-n1', 'tile-note-n2']);
      await endSettings(tester);
    });
  });
}
