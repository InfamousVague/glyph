// A cleanup applied and taken back (lib/plugins/cleanup/apply.dart; docs/CLEANUP.md, "Applying" and "Undo and the
// record"; Matt, 2026-11-02): only the ticked items, each note written once over the revision that was read, a copy
// to the Trash and never deleted, a stale note to the Archive, an organization's note never moved out of it, every
// move read back, a note changed since left alone and named, and the whole run undone in one, now or from its record.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/library_config.dart' show MemoryConfigFile;
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/plugins/cleanup/cleanup.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/core/stored.dart';

import 'support.dart';

/// A store whose filing of [stuck] never lands: a move that did not happen, as a failed sync once left them.
class _StuckStore extends WorkspaceStore {
  _StuckStore(this.stuck, {super.storage, super.trash});
  final String stuck;

  @override
  void fileNote(String noteId, String? id) {
    if (noteId == stuck) return;
    super.fileNote(noteId, id);
  }
}

void main() {
  late CleanupWorld world;
  late CleanupScope scope;
  setUp(() {
    world = CleanupWorld();
    scope = world.scope('work');
  });

  CleanupPlan planOf(List<CleanupItem> items, [CleanupScope? within]) => CleanupPlan(scope: within ?? scope, options: const CleanupOptions(passes: {...CleanupPass.values}), items: items);

  /// Every pass once: a new folder and a move into it, a move into Clients, a title, a merge, a tidy, tags and an
  /// archive.
  CleanupPlan everything() {
    final messy = scope.note('messy')!;
    final invoice = scope.note('invoice')!;
    return planOf([
      const NewFolderItem(key: 'work/meetings', name: 'Meetings', parentId: 'work'),
      const MoveItem(noteId: 'standup', from: 'work', to: 'folder:work/meetings'),
      const MoveItem(noteId: 'kiln-call', from: 'work', to: 'clients'),
      const TitleItem(noteId: 'kiln-call', from: 'Untitled', to: 'Kiln spring menu call'),
      const MergeItem(keepId: 'standup', others: ['standup-copy']),
      EditItem(noteId: 'messy', pass: CleanupPass.tidy, before: messy.body, after: '# Plan\n\n### Steps\n\n- one\n- two\n\n## Done\n\nAll good.'),
      EditItem(noteId: 'invoice', pass: CleanupPass.links, before: invoice.body, after: withTags(invoice.body, ['admin']), tags: const ['admin']),
      const ArchiveItem(noteId: 'idea'),
    ]);
  }

  Future<CleanupApplied> apply(CleanupPlan plan, Set<String> ticked) => applyCleanup(plan: plan, ticked: ticked, library: world.library, workspaces: world.workspaces, trash: world.trash, aiName: 'Fake AI', now: DateTime.fromMillisecondsSinceEpoch(cleanupNow));

  String? filed(String id) => world.workspaces.workspaceOf(id)?.id;
  String body(String id) => world.library.noteOf(id)!.body;

  test('everything ticked is applied, read back, and recorded; nothing is deleted', () async {
    final plan = everything();
    final done = await apply(plan, {for (final i in plan.items) i.id});
    final meetings = world.workspaces.value.list.firstWhere((w) => w.name == 'Meetings');
    expect(meetings.parent, 'work');
    expect(filed('standup'), meetings.id);
    expect(filed('kiln-call'), 'clients');
    expect(body('kiln-call'), startsWith('# Kiln spring menu call\n\nCall with the Kiln shop'));
    // The copy's line the kept note lacked is in it; the copy is in the Trash, still in the library.
    expect(body('standup'), contains('## From “Standup (shared)”\n\n- [ ] Ask Sam about the map tiles'));
    expect(world.trash.isTrashed('standup-copy'), isTrue);
    expect(world.library.noteOf('standup-copy'), isNotNull);
    expect(body('messy'), '# Plan\n\n### Steps\n\n- one\n- two\n\n## Done\n\nAll good.');
    expect(body('invoice'), startsWith('---\ntags: [admin]\n---\n'));
    expect(world.library.noteOf('idea')!.archivedAt, isNotNull);
    expect(world.trash.isTrashed('idea'), isFalse);
    expect(done.applied, 8);
    expect(done.skipped, isEmpty);
    expect(done.misplaced, isEmpty);
    expect(done.record.summary, '1 new folder · 2 moved · 4 edited · 1 to the Trash · 1 archived');
    expect(world.library.value, hasLength(cleanupNotes().length), reason: 'nothing is deleted');
  });

  test('only the ticked items; a new folder only where a ticked move goes into it', () async {
    final plan = everything();
    final done = await apply(plan, {'folder:work/meetings', 'title:kiln-call'});
    expect(world.workspaces.value.list.where((w) => w.name == 'Meetings'), isEmpty);
    expect(filed('kiln-call'), 'work');
    expect(body('kiln-call'), startsWith('# Kiln spring menu call'));
    expect(body('messy'), scope.note('messy')!.body);
    expect(world.trash.isTrashed('standup-copy'), isFalse);
    expect(done.applied, 1);
  });

  test('the whole run is undone in one: moves back, words back, out of the Trash and the Archive, the new folder gone', () async {
    final before = {for (final note in world.library.value) note.id: note.body};
    final plan = everything();
    final done = await apply(plan, {for (final i in plan.items) i.id});
    final undone = await undoCleanup(record: done.record, library: world.library, workspaces: world.workspaces, trash: world.trash);
    expect(undone.left, isEmpty);
    expect(undone.undone, done.record.changes.length);
    for (final note in world.library.value) {
      expect(note.body, before[note.id], reason: note.id);
    }
    expect(filed('standup'), 'work');
    expect(filed('kiln-call'), 'work');
    expect(world.trash.isTrashed('standup-copy'), isFalse);
    expect(world.library.noteOf('idea')!.archivedAt, isNull);
    expect(world.workspaces.value.list.where((w) => w.name == 'Meetings'), isEmpty);
  });

  test('a note changed since the plan is skipped and named, never written over; Undo leaves a note changed since', () async {
    final plan = everything();
    final call = world.library.noteOf('kiln-call')!;
    await world.library.update('kiln-call', '${call.body}\n\nA line typed meanwhile.', call.revision);
    final copy = world.library.noteOf('standup-copy')!;
    await world.library.update('standup-copy', '${copy.body}\n- [ ] Typed meanwhile', copy.revision);
    final done = await apply(plan, {for (final i in plan.items) i.id});
    expect(body('kiln-call'), endsWith('A line typed meanwhile.'));
    expect(body('kiln-call'), startsWith('# Untitled'));
    expect(done.skipped, contains('1 change to “Untitled”: it changed since the plan was made'));
    // Its copy changed, so the merge is held back whole: no lines brought in, nothing to the Trash.
    expect(done.skipped, contains('the merge into “Standup”: a copy changed since the plan was made'));
    expect(world.trash.isTrashed('standup-copy'), isFalse);
    expect(body('standup'), isNot(contains('From “Standup (shared)”')));
    // The move still went, since a move is no edit: the note is where the plan said.
    expect(filed('kiln-call'), 'clients');

    final messy = world.library.noteOf('messy')!;
    await world.library.update('messy', '${messy.body}\nTyped after the run.', messy.revision);
    final undone = await undoCleanup(record: done.record, library: world.library, workspaces: world.workspaces, trash: world.trash);
    expect(undone.left, contains('“Plan” changed since, so its words are left as they are'));
    expect(body('messy'), endsWith('Typed after the run.'));
  });

  group('an organization’s notes', () {
    test('a move out of the organization, or into it, is refused and the note stays where it was', () async {
      final team = world.scope('org-o1');
      final out = await apply(planOf([const MoveItem(noteId: 'team-standup', from: 'org-o1', to: 'work')], team), {'move:team-standup'});
      expect(filed('team-standup'), 'org-o1');
      expect(out.applied, 0);
      expect(out.skipped.single, contains('it would leave the organization'));
      final into = await apply(planOf([const MoveItem(noteId: 'invoice', from: 'work', to: 'org-o1')]), {'move:invoice'});
      expect(filed('invoice'), 'work');
      expect(into.skipped.single, contains('it would leave your own notes'));
    });

    test('within the organization a note moves, a new folder is the organization’s, and Undo brings it back', () async {
      final team = world.scope('org-o1');
      final plan = planOf([
        const NewFolderItem(key: 'org-o1/updates', name: 'Updates', parentId: 'org-o1'),
        const MoveItem(noteId: 'team-standup', from: 'org-o1', to: 'folder:org-o1/updates'),
        MoveItem(noteId: 'team-plan', from: world.plansId, to: 'org-o1'),
      ], team);
      final done = await apply(plan, {for (final i in plan.items) i.id});
      final updates = world.workspaces.value.list.firstWhere((w) => w.name == 'Updates');
      expect(world.workspaces.orgOf(updates.id), 'o1');
      expect(filed('team-standup'), updates.id);
      expect(filed('team-plan'), 'org-o1');
      expect(done.misplaced, isEmpty);
      await undoCleanup(record: done.record, library: world.library, workspaces: world.workspaces, trash: world.trash);
      expect(filed('team-standup'), 'org-o1');
      expect(filed('team-plan'), world.plansId);
      expect(world.workspaces.value.list.where((w) => w.name == 'Updates'), isEmpty);
    });

    test('a merge in an organization’s folders is never made, whoever planned it: a team copy in one member’s Trash would stay everyone else’s', () async {
      final team = world.scope('org-o1');
      final done = await apply(planOf([const MergeItem(keepId: 'team-plan', others: ['team-standup'])], team), {'merge:team-plan'});
      expect(world.trash.isTrashed('team-standup'), isFalse);
      expect(body('team-plan'), world.library.noteOf('team-plan')!.body);
      expect(done.record.changes, isEmpty);
      expect(done.skipped.single, contains('merges are not made in an organization’s folders'));
      expect(done.record.org, 'o1');
    });
  });

  test('a move that did not land is read back and named, never counted as done', () async {
    final stuck = _StuckStore('kiln-call', storage: MemoryWorkspaceStorage(world.workspaces.value.asSheet), trash: world.trash);
    final done = await applyCleanup(
      plan: planOf([const MoveItem(noteId: 'kiln-call', from: 'work', to: 'clients'), const MoveItem(noteId: 'invoice', from: 'work', to: 'clients')]),
      ticked: {'move:kiln-call', 'move:invoice'},
      library: world.library,
      workspaces: stuck,
      trash: world.trash,
      aiName: 'Fake AI',
      now: DateTime.fromMillisecondsSinceEpoch(cleanupNow),
    );
    expect(stuck.workspaceOf('invoice')?.id, 'clients');
    expect(done.misplaced, ['“Untitled” is not in Work › Clients (it is in Work)']);
    expect(done.record.misplaced, done.misplaced);
  });

  group('the record', () {
    test('kept in the plugin’s storage, read back whole, the newest first, marked once undone', () async {
      useStored(MemoryStored());
      usePluginGround(PluginGround());
      final records = CleanupRecords(storage: cleanupHost.storage);
      final plan = everything();
      final done = await apply(plan, {for (final i in plan.items) i.id});
      records.add(done.record);
      final back = CleanupRecords(storage: cleanupHost.storage).all.single;
      expect(back.toJson(), done.record.toJson());
      expect(back.changes, hasLength(done.record.changes.length));
      records.markUndone(done.record.id);
      expect(CleanupRecords(storage: cleanupHost.storage).byId(done.record.id)!.undone, isTrue);
      // Undo from the record, read back from storage, puts everything back.
      final undone = await undoCleanup(record: back, library: world.library, workspaces: world.workspaces, trash: world.trash);
      expect(undone.left, isEmpty);
      expect(filed('standup'), 'work');
    });

    test('a personal folder’s runs are kept in the Library’s file; an organization’s stay on this device', () async {
      useStored(MemoryStored());
      usePluginGround(PluginGround());
      final file = MemoryConfigFile();
      final records = CleanupRecords(storage: cleanupHost.storage, file: file);
      final personal = await apply(everything(), {for (final i in everything().items) i.id});
      final team = world.scope('org-o1');
      final teamRun = await apply(planOf([MoveItem(noteId: 'team-plan', from: world.plansId, to: 'org-o1')], team), {'move:team-plan'});
      records.add(personal.record);
      records.add(teamRun.record);
      await records.written;
      final kept = jsonDecode(file.text!) as Map<String, Object?>;
      expect(kept['version'], 1);
      expect([for (final r in kept['runs']! as List) (r as Map)['id']], [personal.record.id], reason: 'a team’s words never go into a file git backup commits');
      expect(file.text, isNot(contains('Team plan')));
      expect(CleanupRecords(storage: cleanupHost.storage).all.map((r) => r.id), [teamRun.record.id]);
      expect(records.all.map((r) => r.id), unorderedEquals([personal.record.id, teamRun.record.id]));
      // Another device that shares the folder reads the run, and its Undo is everyone's.
      final there = CleanupRecords(file: file);
      await there.reread();
      expect(there.all.single.toJson(), personal.record.toJson());
      there.markUndone(personal.record.id);
      await there.written;
      await records.reread();
      expect(records.byId(personal.record.id)!.undone, isTrue);
    });

    test('a run another device wrote meanwhile is kept when this one writes; a file that cannot be read keeps nothing', () async {
      final file = MemoryConfigFile();
      final here = CleanupRecords(file: file), there = CleanupRecords(file: file);
      CleanupRecord run(String id, int minutes) => CleanupRecord(id: id, at: DateTime.utc(2026, 11, 2, 12, minutes), folderId: 'work', folderPath: 'Work', aiName: 'Claude', changes: const [CleanupChange.archive('idea')]);
      here.add(run('a', 1));
      await here.written;
      there.add(run('b', 2));
      await there.written;
      await here.reread();
      expect(here.all.map((r) => r.id), ['b', 'a']);
      await file.write('{not json');
      await here.reread();
      expect(here.all, isEmpty);
      final none = CleanupRecords();
      await none.useFile(null);
      none.add(run('c', 3));
      expect(none.all.single.id, 'c', reason: 'with no file the run is kept on the device');
    });

    test('the service applies the ticked, keeps the record, and undoes it once', () async {
      final service = world.service(ais: [scriptedAi((_, _) => '{}')]);
      service.choose('work');
      await service.look();
      expect(service.stage, CleanupStage.review);
      expect(service.plan!.items.single.id, 'merge:standup');
      service.tick('merge:standup', false);
      expect(await service.apply(), isA<CleanupApplied>());
      expect(service.records.all, isEmpty, reason: 'nothing ticked, nothing changed, nothing to record');
      service.again();
      await service.look();
      final done = await service.apply(all: true);
      expect(done!.applied, 1);
      expect(service.stage, CleanupStage.applied);
      expect(service.records.all.single.id, done.record.id);
      expect(world.trash.isTrashed('standup-copy'), isTrue);
      expect(await service.undo(done.record.id), isA<CleanupUndone>());
      expect(world.trash.isTrashed('standup-copy'), isFalse);
      expect(await service.undo(done.record.id), isNull, reason: 'once');
    });
  });
}

extension on Workspaces {
  WorkspaceSheet get asSheet => WorkspaceSheet(list: list, notes: of, current: current?.id);
}
