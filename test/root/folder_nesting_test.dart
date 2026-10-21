import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note_folders.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/notes/folder_drag.dart';
import 'package:ghost_md/notes/icon_browser.dart' show browseViewsKey;
import 'package:ghost_md/root/ghost_root.dart';

import '../library/support.dart' show FakeCore, libraryOver;
import '../support/render.dart';

/// Folders and notes made inside the folder being browsed, in the app put together (Matt, 2026-10-20: "we should be
/// able to nest folders and files this way"): from home's icon view inside an organization's folder, New note files
/// the note there (its file's folder the organization's on disk, so it is the team's), New folder makes a folder
/// inside it (an organization's folder, never a personal one), and the view chosen at the organization carries into
/// both. The dock's + inside an organization's folder offers only what may be the team's.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const family = 'org-fam';

  WorkspaceSheet sheet() => const WorkspaceSheet(
        list: [
          Workspace(id: family, name: 'Family', hue: 'rose'),
          Workspace(id: 'baby', name: 'Baby', parent: family),
          Workspace(id: 'home', name: 'Home'),
        ],
        notes: {'feeds': family, 'names': 'baby', 'seeds': 'home'},
      );

  late FakeCore core;
  late NoteFolders folders;
  late WorkspaceStore store;

  Future<void> open(WidgetTester tester, {required String chosen}) async {
    core = FakeCore()
      ..seed('feeds', '# Feeds\n\nEvery three hours.', path: 'orgs/Family/Feeds.md')
      ..seed('names', '# Names\n\nIris, June.', path: 'orgs/Family/Baby/Names.md')
      ..seed('seeds', '# Seeds\n\nTomatoes.', path: 'workspaces/Home/Seeds.md');
    final it = libraryOver(core);
    await tester.runAsync(it.library.load);
    folders = NoteFolders(it.library, log: it.said.add, workspaces: () => store.value.list);
    store = WorkspaceStore(storage: MemoryWorkspaceStorage(sheet()), onFiled: folders.fileNotesInFolder)..chooseWorkspace(chosen);
    // Icons chosen on Family's dashboard, for Family and every folder in it.
    final kept = MemoryStored()..writeText(browseViewsKey, '{"$family":"icons"}');
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

  Finder key(String value) => find.byKey(ValueKey(value));

  testWidgets('New note in an organization’s folder is filed there, its file in the organization’s folder on disk', (tester) async {
    await open(tester, chosen: 'baby');
    // Baby opens in Family's icons.
    expect(key('home-icons'), findsOneWidget);
    expect(key('tile-note-names'), findsOneWidget);
    final before = {...store.value.of.keys};
    await tester.tap(key('tile-note-new'));
    await settle(tester);
    final made = store.value.of.keys.where((id) => !before.contains(id)).toList();
    expect(made, hasLength(1));
    expect(store.value.of[made.single], 'baby');
    expect(store.orgOf(store.value.of[made.single]!), 'fam', reason: 'the team’s, as anything filed in its folders');
    // Its file's folder is the organization's, Baby's inside Family's (lib/core/note_folders.dart).
    expect(folderFor(store.workspaceOf(made.single), store.value.list), 'orgs/Family/Baby');
    await moved(tester);
    await close(tester);
  });

  testWidgets('New folder in an organization’s folder is made inside it, the organization’s, and opens in its icons', (tester) async {
    await open(tester, chosen: 'baby');
    await tester.tap(key('tile-folder-new'));
    await settle(tester);
    await tester.enterText(find.byType(EditableText).last, 'Sleep');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await settle(tester);
    final sleep = store.value.list.where((w) => w.name == 'Sleep').single;
    expect(sleep.parent, 'baby');
    expect(store.orgOf(sleep.id), 'fam');
    expect(workspacePathName(store.value.list, sleep.id), 'Family › Baby › Sleep');
    // The sheet chose it: the page is inside it, in icons, with the way up and its own New tiles.
    expect(store.value.current?.id, sleep.id);
    expect(key('home-icons'), findsOneWidget);
    expect(find.bySemanticsLabel('In Family › Baby › Sleep'), findsOneWidget);
    expect(key('tile-note-new'), findsOneWidget);
    await close(tester);
  });

  testWidgets('the dock’s + inside an organization’s folder files there and offers no Today; in a personal folder it does', (tester) async {
    await open(tester, chosen: 'baby');
    await tester.tap(find.bySemanticsLabel('Write a note'));
    await settle(tester);
    expect(key('new-note'), findsOneWidget);
    expect(key('new-today'), findsNothing, reason: 'a daily note is the account’s own, never the team’s');
    final before = {...store.value.of.keys};
    await tester.tap(key('new-note'));
    await settle(tester);
    final made = store.value.of.keys.where((id) => !before.contains(id)).single;
    expect(store.value.of[made], 'baby');
    await close(tester);

    await open(tester, chosen: 'home');
    await tester.tap(find.bySemanticsLabel('Write a note'));
    await settle(tester);
    expect(key('new-today'), findsOneWidget);
    await close(tester);
  });
}
