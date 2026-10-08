import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/kept_trash.dart';
import 'package:ghost_md/core/kept_workspaces.dart';
import 'package:ghost_md/core/note_folders.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';

import 'support.dart';

/// Workspaces kept where the web keeps them ([KeptWorkspaceStorage]): the cases of `core/workspaces.test.ts` that
/// are about its storage (the preference's shape, another device's settings landing, rubbish, a hue this build does
/// not know, the device's own filter), run through a [WorkspaceStore] as the app runs them. The rest of that file's
/// cases, which are the store's own rules, are test/core/workspaces_test.dart, over storage in memory; the few of
/// them that write through are here again so the preference is seen to follow.
///
/// Not carried: the set kept under the old `glyph-workspaces` key (two cases), which this app never kept.
void main() {
  late PreferencesStore prefs;
  late MemoryStored device;
  late KeptWorkspaceStorage storage;
  late WorkspaceStore store;

  WorkspaceStore open() {
    final next = KeptWorkspaceStorage(prefs: prefs, stored: device);
    addTearDown(next.dispose);
    return WorkspaceStore(storage: next);
  }

  Object? kept() => prefs.value.toJson()['workspaces'];

  setUp(() {
    prefs = PreferencesStore()..startWithoutStorage();
    device = MemoryStored();
    storage = KeptWorkspaceStorage(prefs: prefs, stored: device);
    store = WorkspaceStore(storage: storage);
    addTearDown(store.dispose);
    addTearDown(storage.dispose);
  });

  group('workspaces, kept in the preferences', () {
    test('starts empty, with all notes shown', () {
      expect(store.value.list, isEmpty);
      expect(store.value.of, isEmpty);
      expect(store.value.current, isNull);
    });

    test('are the web’s stored shape: the list and the filings travel, and the filter stays on the device', () {
      final work = store.addWorkspace('Work')!;
      final home = store.addWorkspace('Home', 'sea')!;
      store.fileNote('n1', home.id);
      store.chooseWorkspace(home.id);
      expect(kept(), {
        'list': [
          {'id': work.id, 'name': 'Work'},
          {'id': home.id, 'name': 'Home', 'hue': 'sea'},
        ],
        'notes': {'n1': home.id},
      });
      // The filter is a bare id under the device's own key, and nowhere in the preferences.
      expect(device.getItem('glyph-workspace-current'), home.id);
      expect(currentWorkspaceKey, 'glyph-workspace-current');
      store.chooseWorkspace(null);
      expect(device.getItem('glyph-workspace-current'), isNull);
    });

    test('are found by the next launch, filter and all', () {
      final work = store.addWorkspace('Work')!;
      store.fileNote('n1', work.id);
      store.chooseWorkspace(work.id);
      final next = open();
      expect(next.value.list, [work]);
      expect(next.value.of, {'n1': work.id});
      expect(next.value.current, work);
    });

    test('drop a filter that names no workspace here', () {
      store.addWorkspace('Work');
      device.setItem('glyph-workspace-current', 'w-gone');
      expect(open().value.current, isNull);
    });

    test('renames, and removing unfiles its notes and clears the filter', () {
      final work = store.addWorkspace('Work')!;
      store.renameWorkspace(work.id, ' Day job ');
      expect(store.value.list.first.name, 'Day job');
      store.renameWorkspace(work.id, '');
      expect(store.value.list.first.name, 'Day job');
      store.fileNote('n1', work.id);
      store.chooseWorkspace(work.id);
      expect(store.value.current?.id, work.id);
      store.removeWorkspace(work.id);
      expect(kept(), {'list': <Object?>[], 'notes': <String, Object?>{}});
      expect(device.getItem('glyph-workspace-current'), isNull);
      expect(store.workspaceOf('n1'), isNull);
    });

    test('forgets a deleted note, and tells listeners once per change', () {
      final work = store.addWorkspace('Work')!;
      store.fileNote('n1', work.id);
      var told = 0;
      store.addListener(() => told += 1);
      store.forgetNote('n1');
      store.forgetNote('n1');
      expect(told, 1);
      expect(store.value.of, isEmpty);
      expect((kept() as Map)['notes'], isEmpty);
    });

    test('reads workspaces another device sent again, and tells listeners once', () {
      var told = 0;
      store.addListener(() => told += 1);
      // Our own write is heard once, not again as it comes back through the preferences.
      final work = store.addWorkspace('Work')!;
      expect(told, 1);
      // Settings from another device land as a preference change (core/sync/prefs.ts).
      const home = Workspace(id: 'w-home', name: 'Home');
      prefs.update((now) => now.copyWith(
            workspaces: KeptWorkspaces(list: [KeptWorkspace(id: work.id, name: work.name), const KeptWorkspace(id: 'w-home', name: 'Home')], notes: const {'n1': 'w-home'}),
          ));
      expect(told, 2);
      expect(store.value.list, [work, home]);
      expect(store.workspaceOf('n1'), home);
      // Any other setting changing leaves the workspaces, and whoever watches them, alone.
      prefs.update((now) => now.copyWith(ripples: !now.ripples));
      expect(told, 2);
    });

    test('reads rubbish in the preference as no workspaces at all', () {
      prefs.value = Preferences.fromJson({'workspaces': 'not a sheet'});
      expect(store.value.list, isEmpty);
      // And a filing that points at no workspace is not a filing.
      prefs.value = Preferences.fromJson({
        'workspaces': {
          'list': [
            {'id': 'w-a', 'name': 'Work'},
            {'name': 'No id'},
            'not a workspace',
          ],
          'notes': {'n1': 'w-a', 'n2': 'w-gone', 'n3': 7},
        },
      });
      expect(store.value.list, [const Workspace(id: 'w-a', name: 'Work')]);
      expect(store.value.of, {'n1': 'w-a'});
    });

    test('hands a listener the same snapshot until something changes', () {
      final before = store.value;
      expect(store.value, same(before));
      store.addWorkspace('Work');
      expect(store.value, isNot(same(before)));
    });
  });

  group('a workspace’s colour, kept', () {
    test('is kept once it has one, and taken off again', () {
      final made = store.addWorkspace('Work', 'ember')!;
      expect((kept() as Map)['list'], [
        {'id': made.id, 'name': 'Work', 'hue': 'ember'},
      ]);
      store.setWorkspaceHue(made.id, 'ink');
      expect((kept() as Map)['list'], [
        {'id': made.id, 'name': 'Work'},
      ]);
    });

    test('ignores a colour it does not know, on the way in', () {
      // A hue written by a phone further ahead reads as ink rather than as a broken colour.
      prefs.update((now) => now.copyWith(workspaces: const KeptWorkspaces(list: [KeptWorkspace(id: 'w-1', name: 'Saved', hue: 'octarine')])));
      expect(store.value.list.first, const Workspace(id: 'w-1', name: 'Saved'));
    });

    test('reads a kept ink as no colour at all', () {
      prefs.update((now) => now.copyWith(workspaces: const KeptWorkspaces(list: [KeptWorkspace(id: 'w-1', name: 'Saved', hue: 'ink')])));
      expect(store.value.list.first, const Workspace(id: 'w-1', name: 'Saved'));
    });
  });

  group('an organization’s workspace, kept', () {
    test('is known by its id alone, so a build that stripped the marker, or another device, still reads it as the organization’s', () {
      prefs.value = Preferences.fromJson({
        'workspaces': {
          'list': [
            {'id': 'org-abc', 'name': 'Ghost'},
            {'id': 'w-1', 'name': 'Home'},
          ],
          'notes': {'n1': 'org-abc'},
        },
      });
      expect([for (final w in store.value.list) (w.id, w.name, w.org)], [('org-abc', 'Ghost', 'abc'), ('w-1', 'Home', null)]);
      // Adopted as it is: no second "Ghost".
      expect(store.ensureOrgWorkspace(const OrgLike(id: 'abc', name: 'Ghost')), const Workspace(id: 'org-abc', name: 'Ghost'));
      expect(store.value.list, hasLength(2));
      expect(store.workspaceOf('n1')?.org, 'abc');
      // A marker written by another device is never what decides.
      prefs.value = Preferences.fromJson({
        'workspaces': {
          'list': [
            {'id': 'w-2', 'name': 'Fake', 'org': 'abc'},
          ],
          'notes': <String, Object?>{},
        },
      });
      expect(store.value.list.first.org, isNull);
      // And it is never kept: the id says it.
      store.ensureOrgWorkspace(const OrgLike(id: 'xyz', name: 'Team', hue: 'moss'));
      expect(((kept() as Map)['list'] as List).last, {'id': 'org-xyz', 'name': 'Team', 'hue': 'moss'});
    });
  });

  group('a note’s file follows its filing', () {
    /// A library with two notes in the inbox, and a workspace store whose filings move their files.
    Future<({FakeCore core, WorkspaceStore store, NoteFolders folders, KeptTrash trash})> wired() async {
      final core = FakeCore()
        ..seed('n1', '# Weekend trip')
        ..seed('n2', '# Packing');
      final it = libraryOver(core);
      await it.library.load();
      final folders = NoteFolders(it.library);
      final trash = KeptTrash(prefs: prefs, clock: () => 700);
      final wired = WorkspaceStore(storage: KeptWorkspaceStorage(prefs: prefs, stored: device), trash: trash, onFiled: folders.fileNotesInFolder, clock: () => 700);
      addTearDown(trash.dispose);
      return (core: core, store: wired, folders: folders, trash: trash);
    }

    /// Every move asked for so far has been answered.
    Future<void> settled(NoteFolders folders) => folders.fileNotesInFolder(const [], null);

    test('into its workspace’s folder, and back to the inbox when it is taken out', () async {
      final it = await wired();
      final home = it.store.addWorkspace('Home')!;
      it.store.fileNote('n1', home.id);
      // The pill changes now; the file catches up when the library answers.
      expect(it.store.workspaceOf('n1'), home);
      await settled(it.folders);
      expect(it.core.files, ['Inbox/Packing.md', 'workspaces/Home/Weekend trip.md']);
      it.store.fileNote('n1', null);
      await settled(it.folders);
      expect(it.core.files, ['Inbox/Packing.md', 'Inbox/Weekend trip.md']);
      // Filing it where it already is asks for nothing.
      final before = it.core.asked('get_note');
      it.store.fileNote('n1', null);
      await settled(it.folders);
      expect(it.core.asked('get_note'), before);
    });

    test('into a folder of the new name when its workspace is renamed', () async {
      final it = await wired();
      final home = it.store.addWorkspace('Home')!;
      it.store.fileNote('n1', home.id);
      it.store.fileNote('n2', home.id);
      it.store.renameWorkspace(home.id, 'House');
      await settled(it.folders);
      expect(it.core.files, ['workspaces/House/Packing.md', 'workspaces/House/Weekend trip.md']);
    });

    test('back to the inbox when its workspace is removed', () async {
      final it = await wired();
      final home = it.store.addWorkspace('Home')!;
      it.store.fileNote('n1', home.id);
      it.store.removeWorkspace(home.id);
      await settled(it.folders);
      expect(it.core.files, ['Inbox/Packing.md', 'Inbox/Weekend trip.md']);
      expect(it.store.workspaceOf('n1'), isNull);
    });

    test('under orgs/ for an organization’s workspace, and out again when the person leaves', () async {
      final it = await wired();
      final team = it.store.ensureOrgWorkspace(const OrgLike(id: 'abc', name: 'Ghost'));
      it.store.fileNote('n1', team.id);
      await settled(it.folders);
      expect(it.core.files, ['Inbox/Packing.md', 'orgs/Ghost/Weekend trip.md']);
      it.store.renameOrgWorkspace(const OrgLike(id: 'abc', name: 'Ghost HQ'));
      await settled(it.folders);
      expect(it.core.files, ['Inbox/Packing.md', 'orgs/Ghost HQ/Weekend trip.md']);
      it.store.dropOrgWorkspace('abc');
      await settled(it.folders);
      expect(it.core.files, ['Inbox/Packing.md', 'Inbox/Weekend trip.md']);
    });

    test('a new note goes where the list is', () async {
      final it = await wired();
      final home = it.store.addWorkspace('Home')!;
      it.store.chooseWorkspace(home.id);
      it.store.fileNewNote('n2');
      await settled(it.folders);
      expect(it.core.files, ['Inbox/Weekend trip.md', 'workspaces/Home/Packing.md']);
    });
  });

  group('deleting a workspace', () {
    test('keeps its notes, only unfiled, or puts them in the trash with it', () {
      final trash = KeptTrash(prefs: prefs, clock: () => 700);
      addTearDown(trash.dispose);
      final wired = WorkspaceStore(storage: storage, trash: trash, clock: () => 700);
      final work = wired.addWorkspace('Work')!;
      final home = wired.addWorkspace('Home')!;
      wired.fileNote('n1', work.id);
      wired.fileNote('n2', work.id);
      wired.fileNote('n3', home.id);
      // One of them is in the trash already: it is not asked about, and keeps the time it went in.
      trash.trashNote('n2', 100);
      expect(wired.notesInWorkspace(work.id), ['n1']);
      wired.deleteWorkspace(work.id, trashNotes: true);
      expect(prefs.value.trash, {'n2': 100, 'n1': 700});
      expect(wired.value.list, [home]);
      expect(wired.value.of, {'n3': home.id});
      // Kept: the notes are unfiled and nothing more.
      wired.deleteWorkspace(home.id, trashNotes: false);
      expect(prefs.value.trash, {'n2': 100, 'n1': 700});
      expect(wired.value.list, isEmpty);
    });

    test('is refused for an organization’s, which goes when the person leaves it', () {
      final trash = KeptTrash(prefs: prefs);
      addTearDown(trash.dispose);
      final wired = WorkspaceStore(storage: storage, trash: trash);
      final team = wired.ensureOrgWorkspace(const OrgLike(id: 'abc', name: 'Ghost'));
      wired.fileNote('n1', team.id);
      wired.deleteWorkspace(team.id, trashNotes: true);
      expect(wired.value.list, [team]);
      expect(prefs.value.trash, isEmpty);
    });
  });
}
