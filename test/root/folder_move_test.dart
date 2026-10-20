import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note_folders.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/notes/folder_drag.dart';
import 'package:ghost_md/notes/icon_browser.dart' show browseViewKey;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/screen.dart';

import '../library/support.dart' show FakeCore, libraryOver;
import '../support/render.dart';

/// A note carried onto a folder in the app put together (Matt, 2026-10-20: "the notes are not being moved
/// successfully when dragging them into a folder, it says them moved with the undo but the UI doesn't update";
/// "I dropped the baby notes from the root folder into the baby folder in the family org"). The library is the
/// fake core's, so each filing moves the note's file as the phone's does (lib/core/note_folders.dart), and the page
/// is looked at as the person sees it: right after the drop, after the file has moved, and after Undo.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const family = 'org-fam';

  /// Family, an organization, with Baby inside it; Home, a personal workspace, with Garden inside it. Two baby notes
  /// at Family's own folder, one in Baby already; a garden note at Home's own folder.
  WorkspaceSheet sheet() => const WorkspaceSheet(
        list: [
          Workspace(id: family, name: 'Family', hue: 'rose'),
          Workspace(id: 'baby', name: 'Baby', parent: family),
          Workspace(id: 'home', name: 'Home'),
          Workspace(id: 'garden', name: 'Garden', parent: 'home'),
        ],
        notes: {'feeds': family, 'naps': family, 'names': 'baby', 'seeds': 'home'},
      );

  late FakeCore core;
  late NoteFolders folders;
  late WorkspaceStore store;

  Future<void> open(WidgetTester tester, {required String chosen, bool icons = false}) async {
    core = FakeCore()
      ..seed('feeds', '# Feeds\n\nEvery three hours.', path: 'orgs/Family/Feeds.md')
      ..seed('naps', '# Naps\n\nTwo a day.', path: 'orgs/Family/Naps.md')
      ..seed('names', '# Names\n\nIris, June.', path: 'orgs/Family/Baby/Names.md')
      ..seed('seeds', '# Seeds\n\nTomatoes.', path: 'workspaces/Home/Seeds.md');
    final it = libraryOver(core);
    await tester.runAsync(it.library.load);
    folders = NoteFolders(it.library, log: it.said.add, workspaces: () => store.value.list);
    store = WorkspaceStore(storage: MemoryWorkspaceStorage(sheet()), onFiled: folders.fileNotesInFolder)..chooseWorkspace(chosen);
    final kept = MemoryStored();
    if (icons) kept.writeText(browseViewKey, 'icons');
    await pumpApp(
      tester,
      size: const Size(900, 1000),
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: it.library, workspaces: store, stored: kept),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The files' moves asked for so far, waited for, the page drawn again after.
  Future<void> moved(WidgetTester tester) async {
    var done = false;
    unawaited(folders.fileNotesInFolder(const [], null).then((_) => done = true));
    for (var i = 0; i < 200 && !done; i += 1) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(done, isTrue, reason: 'the files moved');
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    folderCarrying.value = null;
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  }

  /// A finger's carry from [from] to [to]: held until it lifts, then let go there.
  Future<void> drag(WidgetTester tester, Finder from, Finder to) async {
    final gesture = await tester.startGesture(tester.getCenter(from));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, 4));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(to));
    await tester.pump();
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  Finder tile(String id) => find.byKey(ValueKey('tile-note-$id'));
  Finder folderTile(String id) => find.byKey(ValueKey('tile-folder-$id'));

  /// What a folder's tile says: "Baby, folder, 2 notes".
  String said(WidgetTester tester, Finder found) => tester.getSemantics(found).label;

  Future<void> allNotes(WidgetTester tester) async {
    tester.state<AppShellState>(find.byType(AppShell)).show(const Screen.notes());
    await settle(tester);
  }

  testWidgets('icons: an organization’s note carried from its root onto its folder leaves the root, is in the folder, and Undo brings it back', (tester) async {
    await open(tester, chosen: family, icons: true);
    await allNotes(tester);
    expect(find.byKey(const ValueKey('all-notes-icons')), findsOneWidget);
    // At Family's root: Baby's tile, and the notes filed at the root itself; Baby's own note is inside Baby's tile.
    expect(tile('feeds'), findsOneWidget);
    expect(tile('naps'), findsOneWidget);
    expect(tile('names'), findsNothing, reason: 'a folder shows its own notes; what is in Baby is behind Baby’s tile');
    expect(said(tester, folderTile('baby')), 'Baby, folder, 1 note');

    await drag(tester, tile('feeds'), folderTile('baby'));
    expect(find.text('Moved “Feeds” to Family › Baby'), findsOneWidget);
    expect(store.value.of['feeds'], 'baby');
    // At once: gone from the root, counted in Baby.
    expect(tile('feeds'), findsNothing);
    expect(said(tester, folderTile('baby')), 'Baby, folder, 2 notes');
    // And once the file has moved and the library has read itself again, it holds.
    await moved(tester);
    expect(core.files, contains('orgs/Family/Baby/Feeds.md'));
    expect(store.value.of['feeds'], 'baby');
    expect(tile('feeds'), findsNothing);
    // Inside Baby, it is there.
    await tester.tap(folderTile('baby'));
    await settle(tester);
    expect(tile('feeds'), findsOneWidget);
    expect(tile('names'), findsOneWidget);
    await close(tester);
  });

  testWidgets('icons: Undo puts the note back at the root, file and all', (tester) async {
    await open(tester, chosen: family, icons: true);
    await allNotes(tester);
    await drag(tester, tile('naps'), folderTile('baby'));
    expect(tile('naps'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(store.value.of['naps'], family);
    expect(tile('naps'), findsOneWidget);
    expect(said(tester, folderTile('baby')), 'Baby, folder, 1 note');
    await moved(tester);
    expect(core.files, contains('orgs/Family/Naps.md'));
    expect(tile('naps'), findsOneWidget);
    await close(tester);
  });

  testWidgets('icons: a personal note carried into its workspace’s folder leaves the workspace’s root', (tester) async {
    await open(tester, chosen: 'home', icons: true);
    await allNotes(tester);
    expect(tile('seeds'), findsOneWidget);
    await drag(tester, tile('seeds'), folderTile('garden'));
    expect(store.value.of['seeds'], 'garden');
    expect(tile('seeds'), findsNothing);
    expect(said(tester, folderTile('garden')), 'Garden, folder, 1 note');
    await moved(tester);
    expect(core.files, contains('workspaces/Home/Garden/Seeds.md'));
    expect(tile('seeds'), findsNothing);
    await close(tester);
  });

  /// Whether the card of [id] says it is in a folder, and which.
  String? cardFolder(WidgetTester tester, String id) {
    final mark = find.descendant(of: find.byKey(ValueKey('card-$id')), matching: find.byKey(const ValueKey('folder-place')));
    if (mark.evaluate().isEmpty) return null;
    return (tester.widget<Text>(find.descendant(of: mark, matching: find.byType(Text))).data);
  }

  testWidgets('cards: a workspace lists its folders’ notes too, so a note carried onto a folder’s chip stays and says where it went; Undo takes it off', (tester) async {
    await open(tester, chosen: family);
    final chip = find.byKey(const ValueKey('folder-chip-baby'));
    expect(find.byKey(const ValueKey('card-feeds')), findsOneWidget);
    // Names is in Baby already, and says so; Feeds is at Family's own level, and says nothing.
    expect(cardFolder(tester, 'names'), 'Baby');
    expect(cardFolder(tester, 'feeds'), isNull);
    await drag(tester, find.byKey(const ValueKey('card-feeds')), chip);
    expect(find.text('Moved “Feeds” to Family › Baby'), findsOneWidget);
    expect(store.value.of['feeds'], 'baby');
    // At once: the card says Baby, and Baby's chip counts it.
    expect(cardFolder(tester, 'feeds'), 'Baby');
    expect(tester.getSemantics(chip).label, contains('2 notes'));
    // The file moved, and it holds.
    await moved(tester);
    expect(core.files, contains('orgs/Family/Baby/Feeds.md'));
    expect(cardFolder(tester, 'feeds'), 'Baby');
    // Undo: back at Family's own level, file and all.
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(store.value.of['feeds'], family);
    expect(cardFolder(tester, 'feeds'), isNull);
    await moved(tester);
    expect(core.files, contains('orgs/Family/Feeds.md'));
    expect(cardFolder(tester, 'feeds'), isNull);
    await close(tester);
  });

  testWidgets('the sidebar: a note’s row carried onto its organization’s folder is listed under the folder', (tester) async {
    await open(tester, chosen: family);
    await tester.tap(find.bySemanticsLabel('All your notes'));
    await settle(tester);
    Finder under(String folder, String id) => find.descendant(of: find.byKey(ValueKey('folder-$folder')), matching: find.byKey(ValueKey('note-row-$id')));
    expect(under('baby', 'feeds'), findsNothing);
    await drag(tester, find.byKey(const ValueKey('note-row-feeds')), find.byKey(const ValueKey('folder-row-baby')));
    await settle(tester);
    expect(store.value.of['feeds'], 'baby');
    expect(under('baby', 'feeds'), findsOneWidget);
    await moved(tester);
    expect(under('baby', 'feeds'), findsOneWidget);
    await close(tester);
  });
}
