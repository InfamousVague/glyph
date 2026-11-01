import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/folder_adopter.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_folders.dart';
import 'package:ghost_md/core/workspaces.dart';

import '../library/support.dart';

/// Folders restored from the directory tree (lib/core/folder_adopter.dart; docs/MARKDOWN_FIRST.md §5, gap 2): a
/// Library tree with folders and notes but empty preferences opens with the folders and the filings right, and
/// nothing is moved, deleted or unfiled on the way.
void main() {
  /// A library of files as a clone brings them, with no preferences for them: the restore.
  Future<({FakeCore core, WorkspaceStore workspaces, List<Note> notes})> restored({WorkspaceStorage? storage}) async {
    final (:core, :library, waits: _, said: _) = libraryOver();
    core
      ..seed('plan', '# Plan\n\nthe plan', path: 'workspaces/Work/Clients/Plan.md')
      ..seed('standup', '# Standup\n\nnotes', path: 'workspaces/Work/Standup.md')
      ..seed('trip', '# Trip\n\npack', path: 'workspaces/Home/Trip.md')
      ..seed('loose', '# Loose\n\nunfiled', path: 'Inbox/Loose.md')
      ..seed('deal', '# Deal\n\nthe deal', path: 'orgs/Acme/Clients/Deal.md');
    await library.load();
    // The files follow the filings, as the root wires them (lib/root/ghost_root.dart).
    late final WorkspaceStore workspaces;
    final folders = NoteFolders(library, workspaces: () => workspaces.value.list);
    workspaces = WorkspaceStore(storage: storage ?? MemoryWorkspaceStorage(), onFiled: folders.fileNotesInFolder);
    return (core: core, workspaces: workspaces, notes: library.value);
  }

  group('a Library tree opened with empty preferences', () {
    test('gets its personal folders back, nested as the paths nest them, with the ids their places give them', () async {
      final (:core, :workspaces, :notes) = await restored();
      final done = adoptFolders(workspaces, notes);
      expect((done.folders, done.filed, done.waiting), (3, 3, 1));

      final list = workspaces.value.list;
      final work = list.singleWhere((w) => w.name == 'Work'), home = list.singleWhere((w) => w.name == 'Home'), clients = list.singleWhere((w) => w.name == 'Clients');
      expect((work.parent, home.parent, clients.parent), (null, null, work.id));
      expect(work.id, folderIdFor(list, 'Work', null));
      expect(clients.id, folderIdFor(list, 'Clients', work.id));

      expect(workspaces.workspaceOf('plan'), clients);
      expect(workspaces.workspaceOf('standup'), work);
      expect(workspaces.workspaceOf('trip'), home);
      expect(workspaces.workspaceOf('loose'), isNull, reason: 'the inbox is no folder');
      expect(workspaces.workspaceOf('deal'), isNull, reason: 'its organization is not known yet');

      // The files stayed where they were: filing a note where its path already is asks for no move.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(core.files, ['Inbox/Loose.md', 'orgs/Acme/Clients/Deal.md', 'workspaces/Home/Trip.md', 'workspaces/Work/Clients/Plan.md', 'workspaces/Work/Standup.md']);
      expect(core.asked('store_apply'), 0);
    });

    test('is the same on a second device, and a second pass adds nothing', () async {
      final a = await restored(), b = await restored();
      adoptFolders(a.workspaces, a.notes);
      adoptFolders(b.workspaces, b.notes);
      expect([for (final w in a.workspaces.value.list) (w.id, w.name, w.parent)], [for (final w in b.workspaces.value.list) (w.id, w.name, w.parent)]);
      final again = adoptFolders(a.workspaces, a.notes);
      expect((again.folders, again.filed), (0, 0));
    });

    test('leaves a filing the preferences already have, and a folder they already have, as they are', () async {
      final (core: _, :workspaces, :notes) = await restored();
      final work = workspaces.addWorkspace('Work', 'moss')!;
      final other = workspaces.addWorkspace('Elsewhere')!;
      workspaces.fileNote('plan', other.id);
      final done = adoptFolders(workspaces, notes);
      // Work was there (in moss, which stays); Clients and Home were made under it and beside it, Clients for a
      // directory whose one note is filed elsewhere: a directory is a folder whether or not its notes are known.
      expect(done.folders, 2);
      expect(workspaces.value.list.singleWhere((w) => w.name == 'Work').hue, 'moss');
      expect(workspaces.value.list.singleWhere((w) => w.name == 'Clients').parent, work.id);
      expect(workspaces.workspaceOf('plan'), other, reason: 'the preferences know where this note goes');
      expect(workspaces.workspaceOf('standup'), work);
    });

    test('files a team note once its organization is known, by the config or by the organization’s folder', () async {
      final (core: _, :workspaces, :notes) = await restored();
      // The config says which organization `orgs/Acme` is, but the device has not signed in: still waiting.
      expect(adoptFolders(workspaces, notes, orgFolders: {'orgs/Acme': 'o1'}).waiting, 1);
      workspaces.ensureOrgWorkspace(const OrgLike(id: 'o1', name: 'Acme Corp', hue: 'sea'));
      // Renamed since the folder was written: the config's word matches it where the name alone would not.
      expect(adoptFolders(workspaces, notes).waiting, 1);
      final done = adoptFolders(workspaces, notes, orgFolders: {'orgs/Acme': 'o1'});
      expect((done.filed, done.waiting), (1, 0));
      final clients = workspaces.workspaceOf('deal')!;
      expect((clients.name, clients.parent), ('Clients', orgWorkspaceId('o1')));
      expect(workspaces.orgOf(clients.id), 'o1');
    });

    test('files a team note by the organization’s folder name when no config says', () async {
      final (core: _, :workspaces, :notes) = await restored();
      workspaces.ensureOrgWorkspace(const OrgLike(id: 'o1', name: 'Acme'));
      final done = adoptFolders(workspaces, notes);
      expect(done.waiting, 0);
      expect(workspaces.orgOf(workspaces.workspaceOf('deal')!.id), 'o1');
    });

    test('matches a folder by the name its directory is given, in any case', () async {
      final (core: _, :workspaces, :notes) = await restored();
      workspaces.addWorkspace('work');
      final done = adoptFolders(workspaces, notes);
      expect(done.folders, 2, reason: 'Clients and Home; `work` is Work');
      expect(workspaces.value.list.where((w) => w.name.toLowerCase() == 'work').length, 1);
    });
  });

  // Matt, 2026-11-01, "Leaving an org": about a thousand notes left loose at the top when Hello HQ was deleted, their
  // files still under orgs/Hello HQ/. Once the organizations are known, each goes in a folder of the person's named
  // after it, its folders kept.
  group('the notes of an organization that is no longer the person’s', () {
    test('go in a folder of theirs named after it, the folders under it kept; filed notes, the trash, the inbox and a known organization’s paths are left', () async {
      final (:core, :library, waits: _, said: _) = libraryOver();
      core
        ..seed('spec', '# Spec', path: 'orgs/Hello HQ/Engineering Tasks/Spec.md')
        ..seed('top', '# Top', path: 'orgs/Hello HQ/Top.md')
        ..seed('kept', '# Kept', path: 'orgs/Hello HQ/Kept.md')
        ..seed('binned', '# Binned', path: '.trash/orgs/Hello HQ/Binned.md')
        ..seed('team', '# Team', path: 'orgs/HelloTrade/Plans/Team.md')
        ..seed('loose', '# Loose', path: 'Inbox/Loose.md');
      await library.load();
      late final WorkspaceStore workspaces;
      final folders = NoteFolders(library, workspaces: () => workspaces.value.list);
      workspaces = WorkspaceStore(storage: MemoryWorkspaceStorage(), onFiled: folders.fileNotesInFolder);
      workspaces.ensureOrgWorkspace(const OrgLike(id: 'trade', name: 'HelloTrade'));
      final mine = workspaces.addWorkspace('Mine')!;
      workspaces.fileNote('kept', mine.id);
      expect(fileFormerOrgNotes(workspaces, library.value), 2);
      final home = workspaces.value.list.singleWhere((w) => w.name == 'Hello HQ');
      expect((home.parent, workspaces.orgOf(home.id)), (null, null));
      final tasks = workspaces.childrenOf(home.id).single;
      expect(tasks.name, 'Engineering Tasks');
      expect(workspaces.workspaceOf('spec'), tasks);
      expect(workspaces.workspaceOf('top'), home);
      expect(workspaces.workspaceOf('kept'), mine, reason: 'a filing stands');
      expect(workspaces.workspaceOf('binned'), isNull);
      expect(workspaces.workspaceOf('team'), isNull, reason: 'HelloTrade is the person’s: its path is its team’s, waiting');
      expect(workspaces.workspaceOf('loose'), isNull);
      // The moves asked for, waited on: the folders' queue settled.
      await folders.fileNotesInFolder(const [], null);
      expect(core.files, containsAll(['workspaces/Hello HQ/Engineering Tasks/Spec.md', 'workspaces/Hello HQ/Top.md', 'Inbox/Loose.md', 'orgs/HelloTrade/Plans/Team.md']));
      expect(core.files.where((path) => path.startsWith('orgs/Hello HQ/')), isEmpty);
      expect(fileFormerOrgNotes(workspaces, library.value), 0, reason: 'a second pass files nothing');
    });
  });
}
