import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_folders.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/note/workspace_picker.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/team/folders.dart';

import '../core/make_note.dart';
import '../library/support.dart' show FakeCore, libraryOver;
import '../sidebar/support.dart' show away, pumpPage;
import '../support/render.dart' show loadAppFonts;

/// Folders inside an organization's workspace (GHST-107, slice 1): the model (lib/core/workspaces.dart,
/// lib/core/note_folders.dart), the channel's filing and tidying of them on one device (lib/team/folders.dart), the
/// note's Workspace picker, and the sidebar's drop rule. Two devices are test/team_sync/folders_test.dart.
void main() {
  const ghost = OrgLike(id: 'abc', name: 'Ghost.md', hue: 'sea');
  const root = 'org-abc';

  /// A store with the organization's workspace, and every filing it asked for.
  ({WorkspaceStore store, List<String> filed}) storeOf([WorkspaceSheet sheet = const WorkspaceSheet()]) {
    final filed = <String>[];
    late final WorkspaceStore store;
    store = WorkspaceStore(
      storage: MemoryWorkspaceStorage(sheet),
      onFiled: (ids, workspace) => filed.add('${ids.join(',')} to ${folderFor(workspace, store.value.list)}'),
    )..ensureOrgWorkspace(ghost);
    filed.clear();
    return (store: store, filed: filed);
  }

  group('the model', () {
    test('an organization’s workspace holds folders, to any depth, each an ordinary workspace inside it', () {
      final it = storeOf();
      final clients = it.store.addWorkspace('Clients', 'moss', root)!;
      final acme = it.store.addWorkspace('Acme', 'ink', clients.id)!;
      expect(clients.id, matches(RegExp(r'^w-[a-z0-9]{6}$')));
      expect(clients.parent, root);
      expect(acme.parent, clients.id);
      expect(it.store.childrenOf(root).map((w) => w.name), ['Clients']);
      expect(workspacePathName(it.store.value.list, acme.id), 'Ghost.md › Clients › Acme');
      // Its folder on disk is under the organization's.
      expect(folderFor(acme, it.store.value.list), 'orgs/Ghost.md/Clients/Acme');
      expect(folderFor(clients, it.store.value.list), 'orgs/Ghost.md/Clients');
      // The organization's own workspace stands for the organization; a folder under it stands for none, but is in it.
      expect(it.store.value.list.firstWhere((w) => w.id == root).org, 'abc');
      expect(acme.org, isNull);
      expect(orgOfWorkspace(it.store.value.list, root), 'abc');
      expect(orgOfWorkspace(it.store.value.list, clients.id), 'abc');
      expect(orgOfWorkspace(it.store.value.list, acme.id), 'abc');
      expect(it.store.orgOf(acme.id), 'abc');
      expect(orgOfWorkspace(it.store.value.list, 'w-nowhere'), isNull);
      final mine = it.store.addWorkspace('Mine')!;
      expect(it.store.orgOf(mine.id), isNull);
    });

    test('an organization’s own workspace refuses a parent, as it refuses a loop, however it is asked', () {
      final it = storeOf();
      final mine = it.store.addWorkspace('Mine')!;
      expect(it.store.canMove(root, mine.id), isFalse);
      expect(it.store.canMove(root, null), isFalse);
      it.store.moveWorkspace(root, mine.id);
      expect(it.store.value.list.firstWhere((w) => w.id == root).parent, isNull);
      // Kept with one anyway, by another build: read as none.
      final kept = WorkspaceStore(storage: MemoryWorkspaceStorage(const WorkspaceSheet(list: [Workspace(id: 'w-a', name: 'A'), Workspace(id: 'org-x', name: 'X', parent: 'w-a')])));
      expect(kept.value.list.last.parent, isNull);
    });

    test('a folder is never moved into an organization or out of one, and moves within it freely', () {
      final it = storeOf();
      final clients = it.store.addWorkspace('Clients', 'ink', root)!;
      final acme = it.store.addWorkspace('Acme', 'ink', clients.id)!;
      final mine = it.store.addWorkspace('Mine')!;
      final sub = it.store.addWorkspace('Sub', 'ink', mine.id)!;
      final other = it.store.ensureOrgWorkspace(const OrgLike(id: 'def', name: 'Other'));
      // Out: to the top, or to a personal folder. In: a personal folder to the organization's or one of its folders.
      expect(it.store.canMove(acme.id, null), isFalse);
      expect(it.store.canMove(acme.id, mine.id), isFalse);
      expect(it.store.canMove(sub.id, root), isFalse);
      expect(it.store.canMove(sub.id, clients.id), isFalse);
      expect(it.store.canMove(mine.id, root), isFalse);
      // Across organizations: no.
      expect(it.store.canMove(acme.id, other.id), isFalse);
      // Within: yes, except into itself or a folder inside it.
      expect(it.store.canMove(acme.id, root), isTrue);
      expect(it.store.canMove(clients.id, acme.id), isFalse);
      it.store.fileNote('n1', acme.id);
      it.filed.clear();
      it.store.moveWorkspace(acme.id, root);
      expect(it.store.value.list.firstWhere((w) => w.id == acme.id).parent, root);
      expect(it.filed, ['n1 to orgs/Ghost.md/Acme']);
      it.store.moveWorkspace(acme.id, null);
      expect(it.store.value.list.firstWhere((w) => w.id == acme.id).parent, root);
      // The personal folder is as free as before.
      expect(it.store.canMove(sub.id, null), isTrue);
      // Only a move the person was asked about crosses the line (lib/notes/folder_drag.dart): out, in and across,
      // never into itself, and never the organization's own workspace. The notes' files follow.
      expect(it.store.canMove(acme.id, null, acrossOrgs: true), isTrue);
      expect(it.store.canMove(sub.id, clients.id, acrossOrgs: true), isTrue);
      expect(it.store.canMove(acme.id, other.id, acrossOrgs: true), isTrue);
      expect(it.store.canMove(mine.id, sub.id, acrossOrgs: true), isFalse);
      expect(it.store.canMove(root, mine.id, acrossOrgs: true), isFalse);
      it.filed.clear();
      it.store.moveWorkspace(acme.id, mine.id, acrossOrgs: true);
      expect(it.store.value.list.firstWhere((w) => w.id == acme.id).parent, mine.id);
      expect(it.store.orgOf(acme.id), isNull);
      expect(it.filed, ['n1 to workspaces/Mine/Acme']);
    });

    test('a folder of the organization’s is renamed, recoloured, removed and deleted like any; the organization’s own is not', () {
      final it = storeOf();
      final clients = it.store.addWorkspace('Clients', 'ink', root)!;
      final acme = it.store.addWorkspace('Acme', 'ink', clients.id)!;
      it.store.fileNote('n1', clients.id);
      it.store.fileNote('n2', acme.id);
      it.filed.clear();
      it.store.renameWorkspace(clients.id, 'Customers');
      it.store.setWorkspaceHue(clients.id, 'rose');
      expect(it.store.value.list.firstWhere((w) => w.id == clients.id), Workspace(id: clients.id, name: 'Customers', hue: 'rose', parent: root));
      expect(it.filed, ['n1 to orgs/Ghost.md/Customers', 'n2 to orgs/Ghost.md/Customers/Acme']);
      it.filed.clear();
      // Removed, the folder inside it goes a level up, and so do its notes: still the organization's (Matt,
      // 2026-10-23), where unfiling them took them out of the team.
      it.store.removeWorkspace(clients.id);
      expect(it.store.value.list.firstWhere((w) => w.id == acme.id).parent, root);
      expect(it.store.workspaceOf('n1')?.id, root);
      expect(it.filed, ['n1 to orgs/Ghost.md', 'n2 to orgs/Ghost.md/Acme']);
      it.store.renameWorkspace(root, 'Mine');
      it.store.removeWorkspace(root);
      expect(it.store.value.list.firstWhere((w) => w.id == root).name, 'Ghost.md');
    });

    test('the organization’s workspace gone takes its folders with it, their notes unfiled and the filter cleared', () {
      final it = storeOf();
      final clients = it.store.addWorkspace('Clients', 'ink', root)!;
      final acme = it.store.addWorkspace('Acme', 'ink', clients.id)!;
      final mine = it.store.addWorkspace('Mine')!;
      it.store.fileNote('n1', root);
      it.store.fileNote('n2', acme.id);
      it.store.fileNote('n3', mine.id);
      it.store.chooseWorkspace(acme.id);
      it.filed.clear();
      it.store.dropOrgWorkspace('abc');
      expect(it.store.value.list, [mine]);
      expect(it.store.value.of, {'n3': mine.id});
      expect(it.store.value.current, isNull);
      expect(it.filed, ['n1,n2 to Inbox']);
      // Nothing of the organization's left: nothing happens, and nothing is said.
      it.filed.clear();
      it.store.dropOrgWorkspace('abc');
      expect(it.filed, isEmpty);
    });

    test('counts the notes in a folder and under it, and finds a folder by name inside its parent only', () {
      final it = storeOf();
      final clients = it.store.addWorkspace('Clients', 'ink', root)!;
      final acme = it.store.addWorkspace('Acme', 'ink', clients.id)!;
      it.store.fileNote('n1', root);
      it.store.fileNote('n2', clients.id);
      it.store.fileNote('n3', acme.id);
      expect(it.store.notesUnder(root), ['n1', 'n2', 'n3']);
      expect(it.store.notesUnder(clients.id), ['n2', 'n3']);
      expect(it.store.notesUnder(acme.id), ['n3']);
      expect(it.store.notesInWorkspace(clients.id), ['n2']);
      // The same name inside the same parent is the same folder; elsewhere it is another. Asked for without a
      // parent, a personal workspace of the name is found, never the organization's folder.
      expect(it.store.addWorkspace('clients', 'ink', root), same(clients));
      expect(it.store.addWorkspace('Clients', 'ink', acme.id)!.id, isNot(clients.id));
      final mine = it.store.addWorkspace('Clients')!;
      expect(mine.id, isNot(clients.id));
      expect(mine.parent, isNull);
      expect(it.store.addWorkspace('Clients'), same(mine));
    });

    test('a team note’s path names the folders to file it under', () {
      expect(orgFolderNames('orgs/Ghost.md/Clients/Acme/Plan.md'), ['Clients', 'Acme']);
      expect(orgFolderNames('orgs/Ghost.md/Clients/Plan.md'), ['Clients']);
      expect(orgFolderNames('orgs/Ghost.md/Plan.md'), isEmpty);
      expect(orgFolderNames('workspaces/Work/Plan.md'), isEmpty);
      expect(orgFolderNames('Inbox/Plan.md'), isEmpty);
      expect(orgFolderNames(null), isEmpty);
    });
  });

  group('the channel’s folders on one device', () {
    test('files a note from the team by its path, finding each folder by name or making it', () {
      final it = storeOf();
      final folders = OrgFolders(it.store, 'abc');
      folders.fileAt('n1', ['Clients', 'Acme']);
      final clients = it.store.childrenOf(root).single;
      final acme = it.store.childrenOf(clients.id).single;
      expect(clients.name, 'Clients');
      expect(acme.name, 'Acme');
      expect(it.store.workspaceOf('n1'), acme);
      expect(it.filed, ['n1 to orgs/Ghost.md/Clients/Acme']);
      // The same path again finds the same folders; a note at the organization's folder is filed in the workspace.
      folders.fileAt('n2', ['Clients']);
      expect(it.store.workspaceOf('n2'), clients);
      expect(it.store.childrenOf(root), [clients]);
      // A folder named for the file system matches by that name: "Clients?" holds `orgs/Ghost.md/Clients/`.
      it.store.renameWorkspace(clients.id, 'Clients?');
      folders.fileAt('n3', ['Clients']);
      expect(it.store.workspaceOf('n3')?.id, clients.id);
      // One named in another case is renamed to the path's, so the files are not moved back and forth.
      it.store.renameWorkspace(clients.id, 'clients');
      folders.fileAt('n4', ['Clients']);
      expect(it.store.value.list.firstWhere((w) => w.id == clients.id).name, 'Clients');
      expect(it.store.workspaceOf('n4')?.id, clients.id);
    });

    test('drops a folder the pass emptied, and leaves one that was empty before it, or that a path still names', () {
      final it = storeOf();
      final folders = OrgFolders(it.store, 'abc');
      final clients = it.store.addWorkspace('Clients', 'ink', root)!;
      final acme = it.store.addWorkspace('Acme', 'ink', clients.id)!;
      final fresh = it.store.addWorkspace('Ideas', 'ink', root)!;
      final mine = it.store.addWorkspace('Mine')!;
      it.store.fileNote('n1', acme.id);
      it.store.fileNote('n2', mine.id);
      Note at(String id, String path) => Note(id: id, body: '# $id', createdAt: 0, updatedAt: 0, path: path);
      final had = folders.filled([at('n1', 'orgs/Ghost.md/Clients/Acme/n1.md'), at('n2', 'workspaces/Mine/n2.md')]);
      expect(had, {clients.id, acme.id});
      // The pass moved the note out of Acme: Acme and Clients go, Ideas (empty before) and Mine (not the team's) stay.
      it.store.fileNote('n1', root);
      folders.prune(had, [at('n1', 'orgs/Ghost.md/n1.md'), at('n2', 'workspaces/Mine/n2.md')]);
      expect(it.store.value.list.map((w) => w.id), [root, fresh.id, mine.id]);
      // A folder empty of filings that a team note's path still names stays: the filing catches up next pass.
      final pending = it.store.addWorkspace('Pending', 'ink', root)!;
      it.store.fileNote('n3', pending.id);
      final again = folders.filled([at('n3', 'orgs/Ghost.md/Pending/n3.md')]);
      it.store.fileNote('n3', root);
      folders.prune(again, [at('n3', 'orgs/Ghost.md/Pending/n3.md')]);
      expect(it.store.value.list.any((w) => w.id == pending.id), isTrue);
      // Emptied on purpose before the pass: not the pass's to drop.
      folders.prune(folders.filled([at('n3', 'orgs/Ghost.md/n3.md')]), [at('n3', 'orgs/Ghost.md/n3.md')]);
      expect(it.store.value.list.any((w) => w.id == pending.id), isTrue);
      // A note the pass took away leaves its filing behind: the folder is empty all the same.
      final gone = it.store.addWorkspace('Gone', 'ink', root)!;
      it.store.fileNote('n4', gone.id);
      final held = folders.filled([at('n4', 'orgs/Ghost.md/Gone/n4.md')]);
      expect(held, {gone.id});
      folders.prune(held, const []);
      expect(it.store.value.list.any((w) => w.id == gone.id), isFalse);
    });

    test('a note filed up out of a folder moves its file, where an import’s own sub-folder keeps it', () async {
      final core = FakeCore()
        ..seed('n1', '# Plan', path: 'orgs/Ghost.md/Ideas/n1.md')
        ..seed('n2', '# Vault', path: 'workspaces/Work/Vault/n2.md')
        ..seed('n3', '# Brief', path: 'orgs/Ghost.md/Clients/Acme/n3.md');
      final it = libraryOver(core);
      await it.library.load();
      late final WorkspaceStore store;
      final folders = NoteFolders(it.library, log: it.said.add, workspaces: () => store.value.list);
      store = WorkspaceStore(
        storage: MemoryWorkspaceStorage(const WorkspaceSheet(
          list: [
            Workspace(id: root, name: 'Ghost.md'),
            Workspace(id: 'ideas', name: 'Ideas', parent: root),
            Workspace(id: 'clients', name: 'Clients', parent: root),
            Workspace(id: 'acme', name: 'Acme', parent: 'clients'),
            Workspace(id: 'work', name: 'Work'),
          ],
          notes: {'n1': 'ideas', 'n2': 'work', 'n3': 'acme'},
        )),
        onFiled: folders.fileNotesInFolder,
      );
      store.fileNote('n1', root);
      store.fileNote('n3', 'clients');
      // Filed again where it already is: an import's own folder inside Work stays.
      await folders.fileNotesInFolder(const ['n2'], store.value.list.firstWhere((w) => w.id == 'work'));
      expect(core.files, ['orgs/Ghost.md/Clients/n3.md', 'orgs/Ghost.md/n1.md', 'workspaces/Work/Vault/n2.md']);
    });
  });

  group('on screen', () {
    setUpAll(loadAppFonts);

    testWidgets('the note’s Workspace picker says a note in a folder of the organization’s is the team’s, and asks twice only to leave the organization', (tester) async {
      final it = storeOf();
      final clients = it.store.addWorkspace('Clients', 'ink', root)!;
      final mine = it.store.addWorkspace('Mine')!;
      it.store.fileNote('n1', clients.id);
      var done = 0;
      await pumpPage(tester, Align(alignment: Alignment.topLeft, child: SizedBox(width: 360, child: WorkspacePicker(noteId: 'n1', workspaces: it.store, onDone: () => done += 1))));
      expect(find.text('Filed in Ghost.md › Clients, this note is the team’s: everyone in it reads and edits it.'), findsOneWidget);
      // To the organization's own workspace: moved at once, still the team's.
      await tester.tap(find.byKey(const ValueKey('workspace:$root')));
      await tester.pump();
      expect(it.store.workspaceOf('n1')?.id, root);
      expect(done, 1);
      expect(find.text('Filed in Ghost.md, this note is the team’s: everyone in it reads and edits it.'), findsOneWidget);
      // Back into the folder: the same.
      await tester.tap(find.byKey(ValueKey('workspace:${clients.id}')));
      await tester.pump();
      expect(it.store.workspaceOf('n1')?.id, clients.id);
      expect(done, 2);
      // Out to a personal workspace: armed first, then gone.
      await tester.tap(find.byKey(ValueKey('workspace:${mine.id}')));
      await tester.pump();
      expect(it.store.workspaceOf('n1')?.id, clients.id);
      expect(find.text('This takes the note away from everyone in Ghost.md › Clients. Press again to go on.'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('workspace:${mine.id}')));
      await tester.pump();
      expect(it.store.workspaceOf('n1')?.id, mine.id);
      expect(done, 3);
      await tester.pump(const Duration(seconds: 5));
      await away(tester);
    });

    testWidgets('the sidebar takes a note into a folder of its own organization, and across the line only once asked', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final spaces = WorkspaceStore(storage: MemoryWorkspaceStorage(const WorkspaceSheet(
        list: [
          Workspace(id: root, name: 'Ghost.md', hue: 'sea'),
          Workspace(id: 'clients', name: 'Clients', parent: root),
          Workspace(id: 'acme', name: 'Acme', parent: 'clients'),
          Workspace(id: 'mine', name: 'Mine'),
        ],
        notes: {'plan': root, 'brief': 'clients', 'todo': 'mine'},
      )));
      final notes = [makeNote('plan', body: '# Plan'), makeNote('brief', body: '# Brief'), makeNote('todo', body: '# Todo'), makeNote('loose', body: '# Loose')];
      await pumpPage(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 320, child: NoteTree(notes: notes, activeId: null, onOpen: (_) {}, onNew: () {}, workspaces: spaces, stored: MemoryStored()..writeText('glyph-tree-compact', '1'))),
        ),
        size: const Size(900, 1000),
      );
      Future<void> drag(String fromKey, String toKey) async {
        final gesture = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(fromKey))), kind: PointerDeviceKind.mouse);
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump();
        await gesture.moveTo(tester.getCenter(find.byKey(ValueKey(toKey))));
        await tester.pump();
        await gesture.up();
        for (var i = 0; i < 4; i += 1) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      /// Whether a sheet asks, and its Cancel pressed: nothing across the line moves until its Move is.
      Future<bool> askedAndCancelled() async {
        final asked = find.byKey(const ValueKey('move-ask-no')).evaluate().isNotEmpty;
        if (asked) {
          await tester.tap(find.byKey(const ValueKey('move-ask-no')));
          await tester.pump(const Duration(milliseconds: 300));
        }
        return asked;
      }

      // Plan, at the organization's own folder, into Acme: filed there. Back onto the organization's row: filed there.
      await drag('note-row-plan', 'folder-row-acme');
      expect(spaces.value.of['plan'], 'acme');
      expect(await askedAndCancelled(), isFalse);
      await drag('note-row-plan', 'folder-row-$root');
      expect(spaces.value.of['plan'], root);
      // Todo, personal, onto Clients; Brief, the team's, onto Mine; Loose, unfiled, onto Acme: each asks, and
      // cancelled stays.
      await drag('note-row-todo', 'folder-row-clients');
      expect(await askedAndCancelled(), isTrue);
      expect(spaces.value.of['todo'], 'mine');
      await drag('note-row-brief', 'folder-row-mine');
      expect(await askedAndCancelled(), isTrue);
      expect(spaces.value.of['brief'], 'clients');
      await drag('note-row-loose', 'folder-row-acme');
      expect(await askedAndCancelled(), isTrue);
      expect(spaces.value.of['loose'], isNull);
      // Acme onto the organization's row: moved up, within it. Acme onto Mine, and Mine onto Clients: asked, and
      // cancelled.
      await drag('folder-row-acme', 'folder-row-$root');
      expect(spaces.value.list.firstWhere((w) => w.id == 'acme').parent, root);
      await drag('folder-row-acme', 'folder-row-mine');
      expect(await askedAndCancelled(), isTrue);
      expect(spaces.value.list.firstWhere((w) => w.id == 'acme').parent, root);
      await drag('folder-row-mine', 'folder-row-clients');
      expect(await askedAndCancelled(), isTrue);
      expect(spaces.value.list.firstWhere((w) => w.id == 'mine').parent, isNull);
      debugDefaultTargetPlatformOverride = null;
      await away(tester);
    });
  });
}
