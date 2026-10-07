import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/workspaces.dart';

/// Workspaces (lib/core/workspaces.dart): the cases of the web's `core/workspaces.test.ts`, less the two about its
/// own storage (the old `glyph-workspaces` key, and rubbish in the preference), which have no counterpart here.
void main() {
  late WorkspaceStore store;
  setUp(() => store = WorkspaceStore());

  group('workspaces', () {
    test('starts empty, with all notes shown', () {
      expect(store.value.list, isEmpty);
      expect(store.value.of, isEmpty);
      expect(store.value.current, isNull);
    });

    test('makes a workspace once per name, tidied', () {
      final work = store.addWorkspace('  Work  ')!;
      expect(work.id, matches(RegExp(r'^w-[a-z0-9]{6}$')));
      expect(work.name, 'Work');
      expect(work.hue, isNull);
      expect(store.addWorkspace('work'), same(work));
      expect(store.addWorkspace('   '), isNull);
      expect(store.value.list, [work]);
    });

    test('files a note in one workspace at a time, and unfiles it', () {
      final work = store.addWorkspace('Work')!;
      final home = store.addWorkspace('Home')!;
      store.fileNote('n1', work.id);
      expect(store.workspaceOf('n1'), work);
      store.fileNote('n1', home.id);
      expect(store.workspaceOf('n1'), home);
      store.fileNote('n1', 'w-nowhere');
      expect(store.workspaceOf('n1'), home);
      store.fileNote('n1', null);
      expect(store.workspaceOf('n1'), isNull);
    });

    test('files a new note where the list is, and only when it is not filed', () {
      final work = store.addWorkspace('Work')!;
      store.fileNewNote('n1');
      expect(store.workspaceOf('n1'), isNull);
      store.chooseWorkspace(work.id);
      store.fileNewNote('n1');
      expect(store.workspaceOf('n1'), work);
      final home = store.addWorkspace('Home')!;
      store.chooseWorkspace(home.id);
      store.fileNewNote('n1');
      expect(store.workspaceOf('n1'), work);
    });

    test('filters notes by workspace, and shows all for null', () {
      final work = store.addWorkspace('Work')!;
      store.fileNote('n1', work.id);
      const notes = ['n1', 'n2'];
      expect(store.inWorkspace(notes, work.id, (id) => id), ['n1']);
      expect(store.inWorkspace(notes, null, (id) => id), notes);
    });

    test('renames, and removing unfiles its notes and clears the filter', () {
      final work = store.addWorkspace('Work')!;
      store.renameWorkspace(work.id, ' Day job ');
      expect(store.value.list[0].name, 'Day job');
      store.renameWorkspace(work.id, '');
      expect(store.value.list[0].name, 'Day job');
      store.fileNote('n1', work.id);
      store.chooseWorkspace(work.id);
      expect(store.value.current?.id, work.id);
      store.removeWorkspace(work.id);
      expect(store.value.list, isEmpty);
      expect(store.value.of, isEmpty);
      expect(store.value.current, isNull);
      expect(store.workspaceOf('n1'), isNull);
    });

    test('forgets a deleted note, and tells listeners once per change', () {
      final work = store.addWorkspace('Work')!;
      store.fileNote('n1', work.id);
      var told = 0;
      void listener() => told += 1;
      store.addListener(listener);
      store.forgetNote('n1');
      store.forgetNote('n1');
      expect(told, 1);
      expect(store.value.of, isEmpty);
      store.removeListener(listener);
    });

    test('reads workspaces another device sent again, and tells listeners once', () {
      final storage = MemoryWorkspaceStorage();
      final store = WorkspaceStore(storage: storage);
      var told = 0;
      store.addListener(() => told += 1);
      final work = store.addWorkspace('Work')!;
      expect(told, 1);
      // Settings from another device land in the storage, and the sheet is read again.
      const home = Workspace(id: 'w-home', name: 'Home');
      storage.write(WorkspaceSheet(list: [work, home], notes: const {'n1': 'w-home', 'n2': 'w-gone'}, current: 'w-gone'));
      store.reloadWorkspaces();
      expect(told, 2);
      expect(store.value.list, [work, home]);
      expect(store.workspaceOf('n1'), home);
      // A filing in a workspace that is not there, and a filter by one, are read as none.
      expect(store.value.of, {'n1': 'w-home'});
      expect(store.value.current, isNull);
    });

    test('hands a listener the same snapshot until something changes', () {
      final before = store.value;
      expect(store.value, same(before));
      store.addWorkspace('Work');
      expect(store.value, isNot(same(before)));
    });

    test('keeps what it is told in its storage, so the next store finds it', () {
      final storage = MemoryWorkspaceStorage();
      final first = WorkspaceStore(storage: storage);
      final work = first.addWorkspace('Work', 'moss')!;
      first.fileNote('n1', work.id);
      first.chooseWorkspace(work.id);
      final second = WorkspaceStore(storage: storage);
      expect(second.value.current, work);
      expect(second.workspaceOf('n1'), work);
    });
  });

  group('a workspace’s colour', () {
    test('is made with one, changed, and taken off again', () {
      final made = store.addWorkspace('Work', 'sea')!;
      expect(made.hue, 'sea');
      expect(store.value.list[0].hue, 'sea');
      store.setWorkspaceHue(made.id, 'moss');
      expect(store.value.list[0].hue, 'moss');
      // Ink is the app's own colour, and is kept as no colour at all rather than as a name.
      store.setWorkspaceHue(made.id, 'ink');
      expect(store.value.list[0].hue, isNull);
    });

    test('keeps its colour through a rename, and has none by default', () {
      final made = store.addWorkspace('Home', 'rose')!;
      store.renameWorkspace(made.id, 'House');
      expect([store.value.list[0].name, store.value.list[0].hue], ['House', 'rose']);
      expect(store.addWorkspace('Plain')?.hue, isNull);
    });

    test('ignores a colour it does not know, on the way in and on the way out', () {
      final made = store.addWorkspace('Work', 'amber')!;
      store.setWorkspaceHue(made.id, 'chartreuse');
      expect(store.value.list[0].hue, 'amber');
      store.setWorkspaceHue('w-nothing', 'sea');
      expect(store.value.list.length, 1);
      // A hue written by a phone further ahead reads as ink rather than as a broken colour; so does a kept ink.
      final kept = WorkspaceStore(
        storage: MemoryWorkspaceStorage(const WorkspaceSheet(list: [Workspace(id: 'w-1', name: 'Saved', hue: 'octarine'), Workspace(id: 'w-2', name: 'Old', hue: 'ink')])),
      );
      expect(kept.value.list, const [Workspace(id: 'w-1', name: 'Saved'), Workspace(id: 'w-2', name: 'Old')]);
    });
  });

  group('an organization’s workspace', () {
    const ghost = OrgLike(id: 'abc', name: 'Ghost', hue: 'sea');

    test('has the organization’s id, name and hue, and is made once however many times it is asked for', () {
      final made = store.ensureOrgWorkspace(ghost);
      expect(made, const Workspace(id: 'org-abc', name: 'Ghost', hue: 'sea'));
      expect(made.org, 'abc');
      expect(isOrgWorkspace(made.id), isTrue);
      expect(store.ensureOrgWorkspace(ghost), made);
      expect(store.value.list, [made]);
      // No hue, or one this build does not know, is the app's own ink.
      expect(store.ensureOrgWorkspace(const OrgLike(id: 'def', name: 'Boo')), const Workspace(id: 'org-def', name: 'Boo'));
      expect(store.ensureOrgWorkspace(const OrgLike(id: 'ghi', name: 'Eek', hue: 'octarine')), const Workspace(id: 'org-ghi', name: 'Eek'));
    });

    test('follows the organization’s name and hue, and keeps its filings through a rename', () {
      store.ensureOrgWorkspace(ghost);
      store.fileNote('n1', 'org-abc');
      store.renameOrgWorkspace(const OrgLike(id: 'abc', name: 'Spectre'));
      expect(store.value.list[0], const Workspace(id: 'org-abc', name: 'Spectre'));
      expect(store.workspaceOf('n1')?.id, 'org-abc');
      store.ensureOrgWorkspace(const OrgLike(id: 'abc', name: 'Spectre', hue: 'rose'));
      expect(store.value.list[0].hue, 'rose');
      // One this device has not got is nothing to rename.
      store.renameOrgWorkspace(const OrgLike(id: 'zzz', name: 'Nobody'));
      expect(store.value.list.length, 1);
    });

    test('is refused the personal rename, hue and removal: those are the organization’s', () {
      store.ensureOrgWorkspace(ghost);
      store.renameWorkspace('org-abc', 'Mine');
      store.setWorkspaceHue('org-abc', 'rose');
      store.removeWorkspace('org-abc');
      expect(store.value.list, const [Workspace(id: 'org-abc', name: 'Ghost', hue: 'sea')]);
    });

    test('goes when the person leaves, its notes unfiled and the filter cleared', () {
      store.ensureOrgWorkspace(ghost);
      store.fileNote('n1', 'org-abc');
      store.chooseWorkspace('org-abc');
      store.dropOrgWorkspace('abc');
      expect(store.value.list, isEmpty);
      expect(store.value.of, isEmpty);
      expect(store.value.current, isNull);
      store.dropOrgWorkspace('abc');
      expect(store.value.list, isEmpty);
    });

    test('may share its name with a personal workspace, which is deduped among the personal ones only', () {
      store.ensureOrgWorkspace(ghost);
      final mine = store.addWorkspace('ghost')!;
      expect(mine.id, startsWith('w-'));
      expect(store.addWorkspace('Ghost'), same(mine));
      expect(store.value.list.length, 2);
    });

    test('reads the organization from the id alone', () {
      expect(orgWorkspaceId('abc'), 'org-abc');
      expect(orgIdOf('org-abc'), 'abc');
      expect(orgIdOf('org-'), isNull);
      expect(orgIdOf('w-abc'), isNull);
    });
  });
}
