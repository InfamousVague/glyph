import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/folder_menu.dart';
import 'package:ghost_md/notes/folder_strip.dart';
import 'package:ghost_md/notes/icon_browser.dart';
import 'package:ghost_md/notes/note_menu.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/notes/workspace_sheet.dart';
import 'package:ghost_md/sheet/kit.dart';

import '../sidebar/support.dart' show away;
import '../support/render.dart';
import 'support.dart';

/// A folder's menu at a right-click (Matt, 2026-10-23: "add a right click context menu to files and folders to delete
/// them"; lib/notes/folder_menu.dart): on a tile in the icon view, a chip on a folders' strip and a row in the
/// sidebar; Rename… and Delete folder… through the folder's own sheet, Delete at its question about the notes; none on
/// an organization's own workspace, and none without the app's scope. A note's tile has its menu too, from the scope
/// where its page was handed none. Pictures to build/feature-shots/organize/folder-menu-*.png.
void main() {
  setUpAll(loadAppFonts);

  const org = OrgLike(id: 'o1', name: 'Ghost.md', hue: 'sea');

  WorkspaceStore storeOf() => WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()))..ensureOrgWorkspace(org);

  /// [child] under the scope, with every row chosen written down.
  Future<List<String>> pump(WidgetTester tester, WorkspaceStore store, Widget child, {bool scoped = true, Size size = const Size(390, 844), String theme = 'light'}) async {
    final did = <String>[];
    await pumpApp(
      tester,
      size: size,
      ratio: 2,
      prefs: AppPreferences(theme: theme),
      home: BackScope(
        child: scoped
            ? FolderMenuScope(
                store: store,
                onRename: (w) => did.add('rename ${w.id}'),
                onDelete: (w) => did.add('delete ${w.id}'),
                onNoteMenu: (id, _) => did.add('note menu $id'),
                child: child,
              )
            : child,
      ),
    );
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
    return did;
  }

  Future<void> rightClick(WidgetTester tester, Finder on) async {
    final mouse = await tester.startGesture(tester.getCenter(on), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await mouse.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Widget icons(WorkspaceStore store, {void Function(String id)? onFolder}) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: IconBrowser(folders: folderTiles(store.value.list, store.value.of, organizeNotes(), null), notes: organizeNotes().take(3).toList(), onFolder: onFolder ?? (_) {}, onOpen: (_) {}, now: organizeNow, store: store),
        ),
      );

  testWidgets('a folder’s tile: Open, Rename…, Move to and Delete folder…, each doing what it says', (tester) async {
    final store = storeOf();
    final opened = <String>[];
    final did = await pump(tester, store, icons(store, onFolder: opened.add));
    await rightClick(tester, find.byKey(const ValueKey('tile-folder-work')));
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Rename…'), findsOneWidget);
    expect(find.byKey(const ValueKey('move-to-home')), findsOneWidget, reason: 'Move to, where a folder may go');
    expect(find.text('Delete folder…'), findsOneWidget);
    await tester.tap(find.text('Delete folder…'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(did, ['delete work']);
    expect(find.text('Delete folder…'), findsNothing);
    await rightClick(tester, find.byKey(const ValueKey('tile-folder-home')));
    await tester.tap(find.text('Rename…'));
    await tester.pump(const Duration(milliseconds: 300));
    await rightClick(tester, find.byKey(const ValueKey('tile-folder-reading')));
    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(did, ['delete work', 'rename home']);
    expect(opened, ['reading']);
    // Nothing was deleted by the menu itself: that is the sheet's to ask.
    expect(store.value.list.map((w) => w.id), containsAll(['work', 'home', 'reading']));
    await away(tester);
  });

  testWidgets('an organization’s own workspace has none; a note’s tile has the app’s note menu', (tester) async {
    final store = storeOf();
    final did = await pump(tester, store, icons(store));
    await rightClick(tester, find.byKey(const ValueKey('tile-folder-org-o1')));
    expect(find.text('Delete folder…'), findsNothing);
    await rightClick(tester, find.byKey(ValueKey('tile-note-${organizeNotes().first.id}')));
    expect(did, ['note menu ${organizeNotes().first.id}']);
    await away(tester);
  });

  testWidgets('without the app’s scope a right-click does nothing', (tester) async {
    final store = storeOf();
    await pump(tester, store, icons(store), scoped: false);
    await rightClick(tester, find.byKey(const ValueKey('tile-folder-work')));
    expect(find.text('Delete folder…'), findsNothing);
    await away(tester);
  });

  testWidgets('a chip on a folders’ strip, and a folder’s row in the sidebar', (tester) async {
    final store = storeOf()..chooseWorkspace('work');
    final did = await pump(
      tester,
      store,
      Column(
        children: [
          FolderStrip(list: store.value.list, of: store.value.of, notes: organizeNotes(), chosen: 'work', onChoose: (_) {}, store: store),
          Expanded(child: NoteTree(notes: organizeNotes(), activeId: null, onOpen: (_) {}, onNew: () {}, workspaces: store, stored: MemoryStored())),
        ],
      ),
    );
    await rightClick(tester, find.byKey(const ValueKey('folder-chip-clients')));
    await tester.tap(find.text('Delete folder…'));
    await tester.pump(const Duration(milliseconds: 300));
    await rightClick(tester, find.byKey(const ValueKey('folder-row-work')));
    expect(find.text('Open'), findsNothing, reason: 'a row opens and shuts by its own press');
    await tester.tap(find.text('Delete folder…'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(did, ['delete clients', 'delete work']);
    await away(tester);
  });

  testWidgets('Delete folder… opens the folder’s sheet at its question, whose Cancel shuts it', (tester) async {
    final store = WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()));
    var closed = 0;
    await pump(
      tester,
      store,
      WorkspaceManageSheet(store: store, editing: store.value.list.firstWhere((w) => w.id == 'reading'), deleting: true, notesIn: (id) => ['novel'], onTrashNotes: (_) {}, onClose: () => closed += 1),
      scoped: false,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Delete Reading?'), findsOneWidget);
    expect(find.widgetWithText(SheetRow, 'Delete, and move the notes to Trash'), findsOneWidget);
    await tester.tap(find.widgetWithText(SheetRow, 'Cancel'));
    await tester.pump();
    expect(closed, 1);
    await away(tester);
  });

  group('the pictures', () {
    for (final (sized, size, mac) in [('phone', const Size(390, 844), false), ('mac', const Size(1280, 800), true)]) {
      for (final theme in ['light', 'dark']) {
        for (final (stage, scoped) in [('before', false), ('after', true)]) {
          testWidgets('a folder’s tile right-clicked, $stage, $sized $theme', (tester) async {
            if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
            final store = storeOf();
            await pump(tester, store, icons(store), scoped: scoped, size: size, theme: theme);
            await rightClick(tester, find.byKey(const ValueKey('tile-folder-work')));
            await snap(tester, 'folder-menu-tile-$stage-$sized-$theme');
            debugDefaultTargetPlatformOverride = null;
          });
        }

        testWidgets('a note’s tile right-clicked, $sized $theme', (tester) async {
          if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final store = storeOf();
          final menu = NoteMenuController();
          final notes = organizeNotes();
          await pumpApp(
            tester,
            size: size,
            ratio: 2,
            prefs: AppPreferences(theme: theme),
            home: BackScope(
              child: FolderMenuScope(
                store: store,
                onRename: (_) {},
                onDelete: (_) {},
                onNoteMenu: menu.open,
                child: Stack(
                  children: [
                    Positioned.fill(child: icons(store)),
                    NoteMenuHost(controller: menu, notes: notes, onOpen: (_) {}, onPin: (_) {}, onArchive: (_, _) {}, onDelete: (_) {}, workspaces: store),
                  ],
                ),
              ),
            ),
          );
          tester.view.padding = FakeViewPadding.zero;
          tester.view.viewPadding = FakeViewPadding.zero;
          await tester.pump();
          await rightClick(tester, find.byKey(ValueKey('tile-note-${notes.first.id}')));
          await snap(tester, 'folder-menu-note-$sized-$theme');
          debugDefaultTargetPlatformOverride = null;
        });
      }
    }
  });
}
