import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/folder_dirs.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/page_tree.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/folder_menu.dart';
import 'package:ghost_md/notes/folder_strip.dart';
import 'package:ghost_md/notes/icon_browser.dart';
import 'package:ghost_md/notes/note_actions.dart';
import 'package:ghost_md/notes/note_menu.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/notes/space_pages.dart';
import 'package:ghost_md/notes/workspace_sheet.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:glacier/glacier.dart' show GlacierMenuItem;

import '../library/support.dart';
import '../sidebar/support.dart' show away, pumpPage;
import '../support/render.dart';
import 'support.dart';

/// A folder deleted with everything in it (Matt, 2026-11-01: "add ability to context menu delete folders and items
/// inside them"), and the context menus of the file folder view, All notes by folder (Matt, 2026-11-01: "Also add
/// context menus to all the items in the file folder view to delete notes"): the counts and the question
/// (lib/core/workspaces.dart `folderDeleteQuestion`), the store's removal and its Undo, the actions' delete
/// (lib/notes/note_actions.dart `deleteFolder`: a personal folder's notes to the Trash with an Undo, an
/// organization's deleted for every member with none), the menu's rows (lib/notes/folder_menu.dart) on a personal
/// folder, a folder inside one and an organization's, none on an organization's own workspace, the sheet's question
/// (lib/notes/workspace_sheet.dart), a folder's page's menu in the spaces' tree, a finger's hold on a tile opening its
/// menu, and the empty directories taken off the disk (lib/core/folder_dirs.dart).
void main() {
  setUpAll(loadAppFonts);

  const org = OrgLike(id: 'o1', name: 'Ghost.md', hue: 'sea');

  /// Work › Clients › Kiln, Home › Garden and Reading (support.dart), and Plans inside the organization's workspace
  /// with Q1 inside it, holding the team's two notes.
  WorkspaceStore storeOf({Trash? trash}) {
    final store = WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()), trash: trash)..ensureOrgWorkspace(org);
    final plans = store.addWorkspace('Plans', 'ink', 'org-o1')!;
    final q1 = store.addWorkspace('Q1', 'ink', plans.id)!;
    store.fileNote('team-plan', plans.id);
    store.fileNote('team-q1', q1.id);
    return store;
  }

  String plansId(WorkspaceStore store) => store.value.list.firstWhere((w) => w.name == 'Plans').id;

  List<Note> notesOf() => [
        ...organizeNotes(),
        Note(id: 'team-plan', body: '# Team plan\n', createdAt: organizeNow, updatedAt: organizeNow),
        Note(id: 'team-q1', body: '# Q1 goals\n', createdAt: organizeNow, updatedAt: organizeNow),
      ];

  group('the counts and the question', () {
    test('a folder with folders inside, one without, an empty one, an organization’s, and its own workspace', () {
      final store = storeOf();
      final work = store.folderContents('work')!;
      expect(work.folders, ['clients', 'kiln']);
      expect(work.notes, unorderedEquals(['roadmap', 'invoice', 'kickoff']));
      expect(work.team, isFalse);
      expect(folderDeleteQuestion('Work', folders: work.folders.length, notes: work.notes.length), 'Delete Work, 2 folders and 3 notes?');
      expect(folderDeleteQuestion('Plans', folders: 3, notes: 24), 'Delete Plans, 3 folders and 24 notes?');
      expect(folderDeleteQuestion('Kiln', folders: 0, notes: 1), 'Delete Kiln and its note?');
      expect(folderDeleteQuestion('Garden', folders: 0, notes: 2), 'Delete Garden and its 2 notes?');
      expect(folderDeleteQuestion('Home', folders: 1, notes: 0), 'Delete Home and the folder in it?');
      expect(folderDeleteQuestion('Empty', folders: 0, notes: 0), 'Delete Empty?');
      final plans = store.folderContents(plansId(store))!;
      expect(plans.team, isTrue);
      expect(plans.org, 'o1');
      expect(plans.notes, unorderedEquals(['team-plan', 'team-q1']));
      expect(store.folderContents('org-o1'), isNull, reason: "an organization's own workspace is never deleted by hand");
      // A note in the trash is not counted, and a filing whose note has gone is not either.
      final trashed = storeOf(trash: MemoryTrash({'invoice': 1}));
      final counted = trashed.folderContents('work', has: (id) => id != 'kickoff')!;
      expect(counted.notes, ['roadmap']);
      expect(counted.trashed, ['invoice']);
    });

    test('removed with every folder under it, and put back where each stood, its notes filed again', () {
      final store = storeOf()..chooseWorkspace('clients');
      final before = [for (final w in store.value.list) w.id];
      final gone = store.removeFolderFamily('work')!;
      expect(store.value.list.map((w) => w.id), isNot(contains('work')));
      expect(store.value.list.map((w) => w.id), isNot(contains('clients')));
      expect(store.value.list.map((w) => w.id), isNot(contains('kiln')));
      expect(store.value.list.map((w) => w.id), contains('home'));
      expect(store.value.of.keys, isNot(contains('roadmap')));
      expect(store.value.of.keys, isNot(contains('kickoff')));
      expect(store.value.of['beds'], 'garden', reason: 'another folder is untouched');
      expect(store.value.current, isNull);
      expect(store.removeFolderFamily('org-o1'), isNull);
      store.putBackFolders(gone);
      expect([for (final w in store.value.list) w.id], before);
      expect(store.value.of['roadmap'], 'work');
      expect(store.value.of['invoice'], 'clients');
      expect(store.value.of['kickoff'], 'kiln');
      expect(store.value.current?.id, 'clients');
    });
  });

  group('the delete', () {
    test('a personal folder: its notes to the Trash, its folders gone, and Undo brings both back', () async {
      final trash = MemoryTrash();
      final library = SampleLibrary(notesOf());
      final store = storeOf(trash: trash);
      final said = <NoteToast>[], trashed = <String>[], restored = <String>[], dirs = <List<String>>[];
      final actions = NoteActions(
        library: library,
        workspaces: store,
        trash: trash,
        say: said.add,
        onTrashed: (note) => trashed.add(note.id),
        onRestored: (note) => restored.add(note.id),
        onFoldersGone: dirs.add,
      );
      await actions.deleteFolder('work');
      expect(trash.value.keys, unorderedEquals(['roadmap', 'invoice', 'kickoff']));
      expect(trashed, unorderedEquals(['roadmap', 'invoice', 'kickoff']));
      expect(store.value.list.map((w) => w.id), isNot(anyOf(contains('work'), contains('clients'), contains('kiln'))));
      expect(library.noteOf('roadmap'), isNotNull, reason: 'in the Trash, not deleted');
      expect(said.single.message, 'Deleted Work, 2 folders and 3 notes. They are in the Trash.');
      expect(said.single.undo, isNotNull);
      said.single.undo!();
      expect(trash.value, isEmpty);
      expect(restored, unorderedEquals(['roadmap', 'invoice', 'kickoff']));
      expect(store.value.list.map((w) => w.id), containsAll(['work', 'clients', 'kiln']));
      expect(store.value.of['kickoff'], 'kiln');
      expect(dirs, isEmpty, reason: 'undone: the directories stay');
      actions.dispose();
    });

    testWidgets('a personal folder’s directories go once its Undo has run out', (tester) async {
      final trash = MemoryTrash();
      final store = storeOf(trash: trash);
      final dirs = <List<String>>[];
      final actions = NoteActions(library: SampleLibrary(notesOf()), workspaces: store, trash: trash, say: (_) {}, onFoldersGone: dirs.add);
      await actions.deleteFolder('work');
      expect(dirs, isEmpty);
      await tester.pump(noteUndo + const Duration(milliseconds: 10));
      expect(dirs, [
        ['workspaces/Work/Clients/Kiln', 'workspaces/Work/Clients', 'workspaces/Work'],
      ]);
      actions.dispose();
    });

    test('an organization’s folder: its notes deleted for every member, nothing to undo, the folders gone', () async {
      final trash = MemoryTrash({'team-q1': 1});
      final library = SampleLibrary(notesOf());
      final store = storeOf(trash: trash);
      final said = <NoteToast>[], forgot = <String>[], dirs = <List<String>>[];
      final actions = NoteActions(library: library, workspaces: store, trash: trash, say: said.add, onForget: forgot.add, onFoldersGone: dirs.add);
      await actions.deleteFolder(plansId(store));
      expect(library.noteOf('team-plan'), isNull, reason: 'deleted, which deletes the row for every member');
      expect(library.noteOf('team-q1'), isNull, reason: 'one in this person’s Trash goes too: it is still in the folder for everyone else');
      expect(trash.value, isEmpty);
      expect(forgot, unorderedEquals(['team-plan', 'team-q1']));
      expect(store.value.list.map((w) => w.name), isNot(anyOf(contains('Plans'), contains('Q1'))));
      expect(store.value.list.map((w) => w.id), contains('org-o1'));
      expect(said.single.message, 'Deleted Plans, 1 folder and 1 note for every member.');
      expect(said.single.undo, isNull);
      expect(dirs, [
        ['orgs/Ghost.md/Plans/Q1', 'orgs/Ghost.md/Plans'],
      ]);
      // An organization's own workspace is never deleted.
      await actions.deleteFolder('org-o1');
      expect(store.value.list.map((w) => w.id), contains('org-o1'));
      actions.dispose();
    });
  });

  group('the menus', () {
    Future<List<String>> pump(WidgetTester tester, WorkspaceStore store, Widget child, {NoteMenuController? menu}) async {
      final did = <String>[];
      await pumpApp(
        tester,
        size: const Size(390, 844),
        ratio: 2,
        prefs: const AppPreferences(),
        home: BackScope(
          child: FolderMenuScope(
            store: store,
            onRename: (w) => did.add('rename ${w.id}'),
            onDelete: (w) => did.add('remove ${w.id}'),
            onDeleteAll: (w) => did.add('delete all ${w.id}'),
            deleteAll: (w) => did.add('deleted ${w.id}'),
            onNoteMenu: menu?.open ?? (id, _) => did.add('note menu $id'),
            child: child,
          ),
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

    Future<void> hold(WidgetTester tester, Finder on) async {
      await tester.longPress(on);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
    }

    Widget icons(WorkspaceStore store, {String? at}) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: IconBrowser(folders: folderTiles(store.value.list, store.value.of, notesOf(), at), notes: notesOf().take(3).toList(), onFolder: (_) {}, onOpen: (_) {}, now: organizeNow, store: store),
          ),
        );

    Finder remove = find.byKey(const ValueKey('folder-menu-remove'));
    Finder deleteAll = find.byKey(const ValueKey('folder-menu-delete-all'));

    testWidgets('a personal folder, one inside it and an organization’s: Remove, keep its notes… and Delete folder and its notes…', (tester) async {
      final store = storeOf();
      final did = await pump(tester, store, icons(store));
      await rightClick(tester, find.byKey(const ValueKey('tile-folder-work')));
      expect(remove, findsOneWidget);
      expect(find.text('Remove folder, keep its notes…'), findsOneWidget);
      expect(find.text('Delete folder and its notes…'), findsOneWidget);
      await tester.tap(deleteAll);
      await tester.pump(const Duration(milliseconds: 300));
      expect(did, ['delete all work'], reason: 'the menu opens the question; nothing is deleted from it');
      expect(store.value.list.map((w) => w.id), contains('work'));
      await rightClick(tester, find.byKey(const ValueKey('tile-folder-org-o1')));
      expect(deleteAll, findsNothing, reason: "an organization's own workspace has no menu");
      await away(tester);

      // A folder inside another, on a chip of its strip; and an organization's folder, inside its workspace.
      final more = await pump(tester, store, Column(children: [FolderStrip(list: store.value.list, of: store.value.of, notes: notesOf(), chosen: 'work', onChoose: (_) {}, store: store)]));
      await rightClick(tester, find.byKey(const ValueKey('folder-chip-clients')));
      await tester.tap(remove);
      await tester.pump(const Duration(milliseconds: 300));
      await away(tester);
      final team = await pump(tester, store, icons(store, at: 'org-o1'));
      await rightClick(tester, find.byKey(ValueKey('tile-folder-${plansId(store)}')));
      await tester.tap(deleteAll);
      await tester.pump(const Duration(milliseconds: 300));
      expect(more, ['remove clients']);
      expect(team, ['delete all ${plansId(store)}']);
      await away(tester);
    });

    testWidgets('simple mode keeps both', (tester) async {
      final store = storeOf();
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: const AppPreferences(),
        home: BackScope(child: FolderMenuScope(store: store, onRename: (_) {}, onDelete: (_) {}, onDeleteAll: (_) {}, child: icons(store))),
      );
      final was = preferences.value;
      preferences.value = was.copyWith(experience: 'simple', experienceChosen: true);
      addTearDown(() => preferences.value = was);
      await tester.pump();
      await rightClick(tester, find.byKey(const ValueKey('tile-folder-work')));
      expect(remove, findsOneWidget);
      expect(deleteAll, findsOneWidget);
      await away(tester);
    });

    testWidgets('in the file folder view a finger held on a tile opens its menu: a note’s, with Delete, and a folder’s', (tester) async {
      final store = storeOf();
      final menu = NoteMenuController();
      final deleted = <String>[];
      final did = await pump(
        tester,
        store,
        Stack(
          children: [
            Positioned.fill(child: icons(store)),
            Positioned.fill(child: NoteMenuHost(controller: menu, notes: notesOf(), onOpen: (_) {}, onPin: (_) {}, onArchive: (_, _) {}, onDelete: (note) => deleted.add(note.id), workspaces: store)),
          ],
        ),
        menu: menu,
      );
      final first = notesOf().first;
      await hold(tester, find.byKey(ValueKey('tile-note-${first.id}')));
      expect(menu.value?.id, first.id);
      expect(find.text('Open'), findsWidgets);
      expect(find.text('Delete'), findsOneWidget);
      // The app's own note menu, Delete in it: the row's own press, as the menu's tests of the sidebar press it.
      tester.widget<GlacierMenuItem>(find.ancestor(of: find.text('Delete'), matching: find.byType(GlacierMenuItem))).onSelect!();
      await tester.pump(const Duration(milliseconds: 300));
      expect(deleted, [first.id]);
      await hold(tester, find.byKey(const ValueKey('tile-folder-work')));
      expect(deleteAll, findsOneWidget);
      expect(remove, findsOneWidget);
      await tester.tap(deleteAll);
      await tester.pump(const Duration(milliseconds: 300));
      expect(did, ['delete all work']);
      // Held and carried away, it was a carry: no menu.
      final drag = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('tile-folder-home'))));
      await tester.pump(const Duration(milliseconds: 600));
      await drag.moveBy(const Offset(0, 120));
      await tester.pump();
      await drag.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(deleteAll, findsNothing);
      await away(tester);
    });

    testWidgets('a folder’s page in the spaces’ tree: its menu ends with the folder’s two deletes', (tester) async {
      const work = Workspace(id: 'w-work', name: 'Work');
      const plan = Workspace(id: 'w-plan', name: 'Plan', parent: 'w-work');
      final store = WorkspaceStore(storage: MemoryWorkspaceStorage(const WorkspaceSheet(list: [work, plan], notes: {'plan': 'w-plan', 'step': 'w-plan'})));
      var clock = 0;
      Note at(String id, String path, [String? body]) => Note(id: id, body: body ?? '# ${path.split('/').last.replaceAll('.md', '')}\n', createdAt: 0, updatedAt: clock += 1, path: path);
      final notes = [at('plan', 'workspaces/Work/Plan/index.md', '# Plan\n\nThe plan.'), at('step', 'workspaces/Work/Plan/Step one.md'), at('standup', 'workspaces/Work/Standup.md')];
      final did = <String>[];
      await pumpPage(
        tester,
        BackScope(
          child: FolderMenuScope(
            store: store,
            onRename: (_) {},
            onDelete: (w) => did.add('remove ${w.id}'),
            onDeleteAll: (w) => did.add('delete all ${w.id}'),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                child: NoteTree(
                  notes: notes,
                  activeId: null,
                  onOpen: (_) {},
                  onNew: () {},
                  workspaces: store,
                  stored: MemoryStored(),
                  onTrashNotes: (_) {},
                  spaces: SidebarSpaces(mover: PageMover(library: libraryOver().library, workspaces: WorkspaceStore())),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Unfold Work'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('More for Plan'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('page-menu-delete')), findsOneWidget, reason: 'the page itself, to the Trash');
      expect(remove, findsOneWidget);
      await tester.tap(deleteAll);
      await tester.pump(const Duration(milliseconds: 300));
      expect(did, ['delete all w-plan']);
      await tester.tap(find.bySemanticsLabel('More for Standup'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(deleteAll, findsNothing, reason: 'a plain page is no folder');
      await away(tester);
    });
  });

  group('the question', () {
    Future<void> show(WidgetTester tester, Widget sheet) async {
      await pumpApp(tester, size: const Size(390, 844), prefs: const AppPreferences(), home: BackScope(child: sheet));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('opened from the menu: the counts, the Trash, and Delete does it', (tester) async {
      final store = storeOf();
      final deleted = <String>[];
      var closed = 0;
      await show(tester, WorkspaceManageSheet(store: store, editing: store.value.list.firstWhere((w) => w.id == 'work'), deletingAll: true, onDeleteAll: (w) => deleted.add(w.id), onClose: () => closed += 1));
      expect(find.text('Delete Work, 2 folders and 3 notes?'), findsOneWidget);
      expect(find.text('Notes go to the Trash, where they can be restored until it is emptied.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('folder-delete-all-yes')));
      await tester.pump();
      expect(deleted, ['work']);
      expect(closed, 1);
      await away(tester);
    });

    testWidgets('an organization’s folder: for every member, cannot be undone', (tester) async {
      final store = storeOf();
      await show(tester, WorkspaceManageSheet(store: store, editing: store.value.list.firstWhere((w) => w.name == 'Plans'), deletingAll: true, onDeleteAll: (_) {}, onClose: () {}));
      expect(find.text('Delete Plans, 1 folder and 2 notes?'), findsOneWidget);
      expect(find.text('They are deleted for every member of Ghost.md, on every device. This cannot be undone.'), findsOneWidget);
      expect(find.widgetWithText(SheetRow, 'Delete for everyone'), findsOneWidget);
      await away(tester);
    });

    testWidgets('the question about the notes offers both, and Cancel on the counts goes back to it', (tester) async {
      final store = storeOf();
      final deleted = <String>[];
      await show(tester, WorkspaceManageSheet(store: store, editing: store.value.list.firstWhere((w) => w.id == 'work'), deleting: true, onDeleteAll: (w) => deleted.add(w.id), onClose: () {}));
      expect(find.widgetWithText(SheetRow, 'Remove folder, keep its notes'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('folder-delete-all')));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Delete Work, 2 folders and 3 notes?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('folder-delete-all-no')));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Delete Work?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('folder-delete-keep')));
      await tester.pump();
      expect(store.value.list.map((w) => w.id), isNot(contains('work')));
      expect(store.value.list.map((w) => w.id), contains('clients'), reason: 'kept, a level up');
      expect(deleted, isEmpty);
      await away(tester);
    });
  });

  group('the directories', () {
    test('only the empty ones go, the deepest first, never a dot or a climb', () async {
      final root = Directory.systemTemp.createTempSync('folder-dirs');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/workspaces/Work/Clients/Kiln').createSync(recursive: true);
      File('${root.path}/workspaces/Work/Clients/.DS_Store').writeAsStringSync('');
      Directory('${root.path}/workspaces/Home').createSync(recursive: true);
      File('${root.path}/workspaces/Home/Kept.md').writeAsStringSync('# Kept');
      final gone = await removeEmptyFolderDirs(root.path, ['workspaces/Work/Clients/Kiln', 'workspaces/Work/Clients', 'workspaces/Work', 'workspaces/Home', '../x', '.trash']);
      expect(gone, 3);
      expect(Directory('${root.path}/workspaces/Work').existsSync(), isFalse);
      expect(File('${root.path}/workspaces/Home/Kept.md').existsSync(), isTrue);
    });
  });
}
