import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/kept_workspaces.dart';
import 'package:ghost_md/core/note_folders.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/tree.dart';

import '../core/make_note.dart';
import '../library/support.dart' show FakeCore, libraryOver;

/// Folders inside folders (lib/core/workspaces.dart `Workspace.parent`, lib/core/note_folders.dart `folderFor`,
/// lib/notes/tree.dart `noteTree`).
void main() {
  /// A store, and every filing it asked for: the note ids and the folder each was asked to go to.
  ({WorkspaceStore store, List<String> filed}) storeOf([WorkspaceSheet sheet = const WorkspaceSheet()]) {
    final filed = <String>[];
    late final WorkspaceStore store;
    store = WorkspaceStore(
      storage: MemoryWorkspaceStorage(sheet),
      onFiled: (ids, workspace) => filed.add('${ids.join(',')} to ${folderFor(workspace, store.value.list)}'),
    );
    return (store: store, filed: filed);
  }

  test('a folder is made inside another, and its folder on disk is inside its parent’s', () {
    final it = storeOf();
    final work = it.store.addWorkspace('Work')!;
    final clients = it.store.addWorkspace('Clients', 'sea', work.id)!;
    final acme = it.store.addWorkspace('Acme', 'ink', clients.id)!;
    expect(clients.parent, work.id);
    expect(it.store.childrenOf(null).map((w) => w.name), ['Work']);
    expect(it.store.childrenOf(work.id).map((w) => w.name), ['Clients']);
    expect(folderFor(acme, it.store.value.list), 'workspaces/Work/Clients/Acme');
    // Without the list, or with a parent whose name is no folder, the folder is at the top.
    expect(folderFor(acme), 'workspaces/Acme');
    expect(workspacePathName(it.store.value.list, acme.id), 'Work › Clients › Acme');
    // An organization's workspace holds folders too (GHST-107), under its own folder on disk.
    final team = it.store.ensureOrgWorkspace(const OrgLike(id: 'abc', name: 'Team'));
    final inside = it.store.addWorkspace('Inside', 'ink', team.id)!;
    expect(inside.parent, team.id);
    expect(folderFor(team, it.store.value.list), 'orgs/Team');
    expect(folderFor(inside, it.store.value.list), 'orgs/Team/Inside');
  });

  test('a workspace shows the notes of the folders inside it', () {
    final it = storeOf();
    final work = it.store.addWorkspace('Work')!;
    final clients = it.store.addWorkspace('Clients', 'ink', work.id)!;
    it.store.fileNote('a', work.id);
    it.store.fileNote('b', clients.id);
    it.store.fileNote('c', null);
    final notes = [makeNote('a'), makeNote('b'), makeNote('c')];
    expect(ids(it.store.inWorkspace(notes, work.id, (n) => n.id)), ['a', 'b']);
    expect(ids(it.store.inWorkspace(notes, clients.id, (n) => n.id)), ['b']);
  });

  test('moving a folder moves it with the folders inside it, and never into itself', () {
    final it = storeOf();
    final work = it.store.addWorkspace('Work')!;
    final home = it.store.addWorkspace('Home')!;
    final clients = it.store.addWorkspace('Clients', 'ink', work.id)!;
    final acme = it.store.addWorkspace('Acme', 'ink', clients.id)!;
    it.store.fileNote('n1', clients.id);
    it.store.fileNote('n2', acme.id);
    it.filed.clear();

    expect(it.store.canMove(work.id, acme.id), isFalse);
    expect(it.store.canMove(work.id, work.id), isFalse);
    it.store.moveWorkspace(work.id, acme.id);
    expect(it.store.value.list.firstWhere((w) => w.id == work.id).parent, isNull);

    it.store.moveWorkspace(clients.id, home.id);
    expect(it.store.value.list.firstWhere((w) => w.id == clients.id).parent, home.id);
    expect(it.filed, [
      'n1 to workspaces/Home/Clients',
      'n2 to workspaces/Home/Clients/Acme',
    ]);
    it.filed.clear();
    it.store.moveWorkspace(clients.id, null);
    expect(it.filed.first, 'n1 to workspaces/Clients');
  });

  test('renaming a folder moves the files of every folder inside it', () {
    final it = storeOf();
    final work = it.store.addWorkspace('Work')!;
    final clients = it.store.addWorkspace('Clients', 'ink', work.id)!;
    it.store.fileNote('n0', work.id);
    it.store.fileNote('n1', clients.id);
    it.filed.clear();
    it.store.renameWorkspace(work.id, 'Office');
    expect(it.filed, [
      'n0 to workspaces/Office',
      'n1 to workspaces/Office/Clients',
    ]);
  });

  test('removing a folder keeps the folders inside it, a level up', () {
    final it = storeOf();
    final work = it.store.addWorkspace('Work')!;
    final clients = it.store.addWorkspace('Clients', 'ink', work.id)!;
    final acme = it.store.addWorkspace('Acme', 'ink', clients.id)!;
    it.store.fileNote('n1', clients.id);
    it.store.fileNote('n2', acme.id);
    it.filed.clear();
    it.store.removeWorkspace(clients.id);
    expect(it.store.value.list.map((w) => w.name), ['Work', 'Acme']);
    expect(it.store.value.list.firstWhere((w) => w.id == acme.id).parent, work.id);
    expect(it.filed, [
      'n1 to Inbox',
      'n2 to workspaces/Work/Acme',
    ]);
  });

  test('a parent that is gone, one on an organization’s workspace, or a loop is read as none; an organization’s as a parent stands', () {
    final it = storeOf(const WorkspaceSheet(list: [
      Workspace(id: 'a', name: 'A', parent: 'b'),
      Workspace(id: 'b', name: 'B', parent: 'a'),
      Workspace(id: 'c', name: 'C', parent: 'gone'),
      Workspace(id: 'org-x', name: 'X'),
      Workspace(id: 'd', name: 'D', parent: 'org-x'),
      Workspace(id: 'org-y', name: 'Y', parent: 'a'),
    ]));
    expect({for (final w in it.store.value.list) w.id: w.parent}, {'a': null, 'b': null, 'c': null, 'org-x': null, 'd': 'org-x', 'org-y': null});
  });

  test('the parent travels in the preferences, and a store from before it reads every folder at the top', () {
    final prefs = PreferencesStore()..startWithoutStorage();
    final storage = KeptWorkspaceStorage(prefs: prefs, stored: MemoryStored());
    final store = WorkspaceStore(storage: storage);
    final work = store.addWorkspace('Work')!;
    store.addWorkspace('Clients', 'ink', work.id);
    final json = prefs.value.toJson()['workspaces'] as Map;
    expect((json['list'] as List).last, {'id': (json['list'] as List).last['id'], 'name': 'Clients', 'parent': work.id});
    final again = Preferences.fromJson(prefs.value.toJson());
    expect(again.workspaces.list.last.parent, work.id);
    expect(Preferences.fromJson({'workspaces': {'list': [{'id': 'w', 'name': 'W'}], 'notes': {}}}).workspaces.list.single.parent, isNull);
    storage.dispose();
  });

  test('the sidebar’s tree holds folders inside folders, each with its own notes', () {
    final spaces = Workspaces(
      list: const [Workspace(id: 'work', name: 'Work'), Workspace(id: 'clients', name: 'Clients', parent: 'work'), Workspace(id: 'home', name: 'Home')],
      of: const {'a': 'work', 'b': 'clients'},
    );
    final tree = noteTreeOf([makeNote('a', updatedAt: 2), makeNote('b', updatedAt: 3), makeNote('c', updatedAt: 1)], spaces);
    expect(tree.folders.map((f) => f.name), ['Work', 'Home']);
    final work = tree.folders.first;
    expect(ids(work.notes), ['a']);
    expect(work.folders.single.name, 'Clients');
    expect(ids(work.folders.single.notes), ['b']);
    expect(work.count, 2);
    expect(ids(tree.loose), ['c']);
  });

  test('the files move with the folder on disk', () async {
    final core = FakeCore()..seed('n1', '# Weekend trip', path: 'workspaces/Work/Weekend trip.md');
    final it = libraryOver(core);
    await it.library.load();
    late final WorkspaceStore store;
    final folders = NoteFolders(it.library, log: it.said.add, workspaces: () => store.value.list);
    store = WorkspaceStore(storage: MemoryWorkspaceStorage(const WorkspaceSheet(list: [Workspace(id: 'work', name: 'Work'), Workspace(id: 'home', name: 'Home')], notes: {'n1': 'work'})), onFiled: folders.fileNotesInFolder);
    store.moveWorkspace('work', 'home');
    await folders.fileNotesInFolder(const [], null);
    expect(core.files, ['workspaces/Home/Work/Weekend trip.md']);
  });
}
