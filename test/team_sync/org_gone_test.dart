// An organization left or deleted, and team notes moved between organizations, on whole devices (Matt, 2026-11-01,
// "Leaving an org" and "Moves between orgs"). What happened that day: the connector filed 26 of Hello HQ's notes into
// a folder of HelloTrade's; Matt deleted Hello HQ; the 26 were gone everywhere, the settings saying HelloTrade and
// HelloTrade's team never having held them; and about a thousand of his notes the settings had filed under Hello HQ
// were left loose at the top, in no folder.
//
// What must hold, and is played here:
// - an organization deleted leaves every note of it the person's devices hold, the team's and their own, in a folder
//   of theirs named after it, each folder that was inside it inside that one, on both devices, none at the top or in
//   the inbox (lib/core/workspaces.dart `dropOrgWorkspace`);
// - a note filed straight from one organization into another is held by the second before the first lets go of it
//   (lib/team/sync.dart `mayLetGo`), and deleting the first while it is on its way loses nothing;
// - a note filed back into an organization it once left is put over its old row, not deleted (`_putRow`);
// - a note the settings file in an organization that never had it, which no device holds, comes from the account's
//   copy and is put to it, the account's row kept until the team has it (lib/sync/notes.dart `owed`).
//
// The devices are whole (test/e2e/world.dart): the real engine, account, organizations and keys, the real crypto and
// CRDT over the Mac's core (tool/build-native.sh host; skipped out loud without it), the service in memory, which
// holds one account. Each device's notes' files follow their filing (`folders`).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/workspaces.dart';

import '../e2e/world.dart';
import 'support.dart';

const String _password = 'correct horse battery';

void main() {
  late GhostCore core;
  late FakeWorld world;
  final devices = <Device>[];

  setUpAll(() async {
    if (!coreBuilt) return;
    core = await GhostCore.open(libraryPath: File(coreLibrary).absolute.path);
    world = FakeWorld(core);
  });

  tearDownAll(() async {
    if (coreBuilt) await core.close();
  });

  setUp(() async {
    if (coreBuilt) await world.fresh();
  });

  tearDown(() async {
    for (final each in devices) {
      await each.close();
    }
    devices.clear();
  });

  Device device(String label) {
    final made = Device(world, core, label: label, folders: true);
    devices.add(made);
    return made;
  }

  /// The team's live rows, by id.
  Set<String> live(String orgId) => {for (final MapEntry(:key, :value) in world.service.teamNotes(orgId).entries) if (!value.deleted) key};

  /// The rows the team ever held that are deleted now.
  Set<String> deleted(String orgId) => {for (final MapEntry(:key, :value) in world.service.teamNotes(orgId).entries) if (value.deleted) key};

  /// The person's own folder at the top called [name], and none of an organization's.
  Workspace personalTop(Device on, String name) => on.workspaces.value.list.singleWhere((w) => w.parent == null && w.name == name && on.workspaces.orgOf(w.id) == null);

  int conflicts(List<Device> each) => each.fold(0, (sum, d) => sum + d.engine.status.value.conflicts);

  test('deleting an organization keeps every note of it in a folder of the person’s named after it, its folders inside as they were, on both devices: none at the top, none in the inbox', () async {
    final phone = device('phone'), mac = device('mac');
    await phone.account.signUp('matt', _password);
    await mac.account.signIn('matt', _password);
    final hello = await phone.orgs.createOrg('Hello HQ', hue: 'amber');
    await phone.sync();
    final root = orgWorkspaceId(hello.id);
    final tasks = phone.workspaces.addWorkspace('Engineering Tasks', 'moss', root)!;
    final sprint = phone.workspaces.addWorkspace('Sprint 12', 'ink', tasks.id)!;
    phone.write('spec', '# Spec\n\nThe team’s.');
    phone.workspaces.fileNote('spec', tasks.id);
    phone.write('ticket', '# Ticket\n\n- [ ] ship');
    phone.workspaces.fileNote('ticket', sprint.id);
    phone.write('roadmap', '# Roadmap');
    phone.workspaces.fileNote('roadmap', root);
    phone.write('groceries', '# Groceries');
    for (var pass = 0; pass < 2; pass += 1) {
      await phone.sync();
      await mac.sync();
    }
    expect(live(hello.id), {'spec', 'ticket', 'roadmap'});
    expect(mac.notes.keys.toSet(), {'spec', 'ticket', 'roadmap', 'groceries'});
    expect(phone.workspaces.orgHoldings(hello.id), (folders: 2, notes: 3));

    await phone.orgs.deleteOrg(hello.id);
    for (var pass = 0; pass < 3; pass += 1) {
      await phone.sync();
      await mac.sync();
    }

    expect(world.service.teamNotes(hello.id), isEmpty, reason: 'the team’s rows went with it');
    for (final each in [phone, mac]) {
      final home = personalTop(each, 'Hello HQ');
      expect(home.hue, 'amber', reason: 'in the organization’s colour');
      expect(each.workspaces.value.list.where((w) => each.workspaces.orgOf(w.id) != null), isEmpty);
      // The same folders, by id, inside the new one.
      final kept = {for (final w in each.workspaces.value.list) w.id: w};
      expect((kept[tasks.id]?.name, kept[tasks.id]?.parent, kept[tasks.id]?.hue), ('Engineering Tasks', home.id, 'moss'));
      expect((kept[sprint.id]?.name, kept[sprint.id]?.parent), ('Sprint 12', tasks.id));
      expect(each.workspaces.workspaceOf('spec')?.id, tasks.id);
      expect(each.workspaces.workspaceOf('ticket')?.id, sprint.id);
      expect(each.workspaces.workspaceOf('roadmap')?.id, home.id);
      expect(each.workspaces.workspaceOf('groceries'), isNull);
      expect(each.notes['spec']!.path, 'workspaces/Hello HQ/Engineering Tasks/spec.md');
      expect(each.notes['ticket']!.path, 'workspaces/Hello HQ/Engineering Tasks/Sprint 12/ticket.md');
      expect(each.notes['roadmap']!.path, 'workspaces/Hello HQ/roadmap.md');
      expect(each.notes['spec']!.body, '# Spec\n\nThe team’s.');
      expect(each.notes['ticket']!.body, '# Ticket\n\n- [ ] ship');
      for (final id in ['spec', 'ticket', 'roadmap']) {
        expect(each.workspaces.workspaceOf(id), isNotNull, reason: '$id is in a folder, not loose at the top');
        expect(each.notes[id]!.path, isNot(startsWith('Inbox/')));
      }
    }
    // The person's own now: the account holds each, so a device signed in tomorrow has them too.
    for (final id in ['spec', 'ticket', 'roadmap']) {
      expect(world.service.notes[id]?.deleted, isFalse, reason: '$id is the account’s');
    }
    expect(conflicts([phone, mac]), 0);
  }, skip: coreSkip);

  test('a note filed straight from one organization into another: the second holds it before the first lets go, one copy on both devices, its words once', () async {
    final phone = device('phone'), mac = device('mac');
    await phone.account.signUp('matt', _password);
    await mac.account.signIn('matt', _password);
    // HelloTrade first, Ghost.md second, the order a pass takes their channels in: the note leaves the first, whose
    // pass runs before the second has put it.
    final hello = await phone.orgs.createOrg('HelloTrade', hue: 'violet');
    final ghost = await phone.orgs.createOrg('Ghost.md', hue: 'sea');
    await phone.sync();
    phone.write('brief', '# Brief\n\nFor whoever has it.');
    phone.workspaces.fileNote('brief', orgWorkspaceId(hello.id));
    for (var pass = 0; pass < 2; pass += 1) {
      await phone.sync();
      await mac.sync();
    }
    expect(live(hello.id), {'brief'});

    // The note's Workspace picker, straight across: the filing alone, the sync does the rest.
    phone.workspaces.fileNote('brief', orgWorkspaceId(ghost.id));
    expect(await phone.engine.movesPending(hello.id), {'Ghost.md': 1});
    await phone.sync();
    // Ghost.md holds it, and HelloTrade has not let go: it was never only on the phone.
    expect(live(ghost.id), {'brief'});
    expect(live(hello.id), {'brief'});
    expect(await phone.engine.movesPending(hello.id), isEmpty);
    await phone.sync();
    expect(live(hello.id), isEmpty);
    expect(deleted(hello.id), {'brief'});
    expect(live(ghost.id), {'brief'});
    for (var pass = 0; pass < 2; pass += 1) {
      await mac.sync();
      await phone.sync();
    }
    for (final each in [phone, mac]) {
      expect(each.notes.keys.toSet(), {'brief'});
      expect(each.notes['brief']!.body, '# Brief\n\nFor whoever has it.', reason: 'its words once, never doubled');
      expect(each.workspaces.workspaceOf('brief')?.id, orgWorkspaceId(ghost.id));
    }
    expect(conflicts([phone, mac]), 0);
  }, skip: coreSkip);

  test('an organization deleted while a note is on its way out of it into another: the note is not lost, and lands in the other', () async {
    final phone = device('phone'), mac = device('mac');
    await phone.account.signUp('matt', _password);
    await mac.account.signIn('matt', _password);
    final hello = await phone.orgs.createOrg('Hello HQ', hue: 'amber');
    final trade = await phone.orgs.createOrg('HelloTrade', hue: 'violet');
    await phone.sync();
    final plans = phone.workspaces.addWorkspace('Plans', 'ink', orgWorkspaceId(trade.id))!;
    phone.write('brief', '# Brief\n\nMoving house.');
    phone.workspaces.fileNote('brief', orgWorkspaceId(hello.id));
    for (var pass = 0; pass < 2; pass += 1) {
      await phone.sync();
      await mac.sync();
    }
    expect(live(hello.id), {'brief'});

    // Filed into HelloTrade › Plans on the phone, and before any pass, Hello HQ deleted on the Mac, which has not
    // heard of the move: Hello HQ's rows go with it on the service.
    phone.workspaces.fileNote('brief', plans.id);
    expect(await phone.engine.movesPending(hello.id), {'HelloTrade': 1});
    await mac.orgs.deleteOrg(hello.id);
    expect(world.service.teamNotes(hello.id), isEmpty);
    for (var pass = 0; pass < 3; pass += 1) {
      await phone.sync();
      await mac.sync();
    }

    // On both devices, with its words; held by a team or by the account, never by no one.
    for (final each in [phone, mac]) {
      expect(each.notes['brief']?.body, '# Brief\n\nMoving house.');
    }
    expect(live(trade.id).contains('brief') || world.service.notes['brief']?.deleted == false, isTrue, reason: 'held on the service');
    expect(phone.workspaces.workspaceOf('brief')?.id, mac.workspaces.workspaceOf('brief')?.id, reason: 'the same folder on both');
  }, skip: coreSkip);

  test('the screen’s check: deleting waits while a note is still on its way to another organization, and not once it is there', () async {
    final phone = device('phone');
    await phone.account.signUp('matt', _password);
    final hello = await phone.orgs.createOrg('Hello HQ');
    final trade = await phone.orgs.createOrg('HelloTrade');
    await phone.sync();
    phone.write('a', '# A');
    phone.write('b', '# B');
    phone.workspaces.fileNotes(['a', 'b'], orgWorkspaceId(hello.id));
    await phone.sync();
    expect(await phone.engine.movesPending(hello.id), isEmpty);
    phone.workspaces.fileNotes(['a', 'b'], orgWorkspaceId(trade.id));
    expect(await phone.engine.movesPending(hello.id), {'HelloTrade': 2});
    // A move to the person's own notes is not waited on: the account takes it in the same pass.
    phone.workspaces.fileNote('b', phone.workspaces.addWorkspace('Mine')!.id);
    expect(await phone.engine.movesPending(hello.id), {'HelloTrade': 1});
    await phone.sync();
    expect(await phone.engine.movesPending(hello.id), isEmpty);
    expect(live(trade.id), {'a'});
  }, skip: coreSkip);

  test('a note filed back into an organization it left is put over its old row there, never deleted', () async {
    final phone = device('phone'), mac = device('mac');
    await phone.account.signUp('matt', _password);
    await mac.account.signIn('matt', _password);
    final org = await phone.orgs.createOrg('HelloTrade');
    await phone.sync();
    final root = orgWorkspaceId(org.id);
    phone.write('plan', '# Plan\n\nBack and forth.');
    phone.workspaces.fileNote('plan', root);
    for (var pass = 0; pass < 2; pass += 1) {
      await phone.sync();
      await mac.sync();
    }
    final home = phone.workspaces.addWorkspace('Home')!;
    phone.workspaces.fileNote('plan', home.id);
    for (var pass = 0; pass < 2; pass += 1) {
      await phone.sync();
      await mac.sync();
    }
    expect(deleted(org.id), {'plan'});
    // And back in: the team's row of it is a deletion now, which a put from nothing meets.
    phone.workspaces.fileNote('plan', root);
    for (var pass = 0; pass < 3; pass += 1) {
      await phone.sync();
      await mac.sync();
    }
    expect(live(org.id), {'plan'});
    for (final each in [phone, mac]) {
      expect(each.notes['plan']?.body, '# Plan\n\nBack and forth.', reason: 'on both devices, with its words');
      expect(each.workspaces.workspaceOf('plan')?.id, root);
    }
    expect(conflicts([phone, mac]), 0);
  }, skip: coreSkip);

  test('a note the settings file in an organization that never had it, on no device, comes from the account’s copy and is put to it; the account’s row goes only after', () async {
    final phone = device('phone');
    await phone.account.signUp('matt', _password);
    final trade = await phone.orgs.createOrg('HelloTrade');
    await phone.sync();
    final plans = phone.workspaces.addWorkspace('Plans', 'ink', orgWorkspaceId(trade.id))!;
    phone.write('stray', '# Stray\n\nOnly the account has me.');
    await phone.sync();
    await phone.sync();
    expect(world.service.notes['stray']?.deleted, isFalse);

    // What the connector's filing left (2026-11-01): the settings say HelloTrade › Plans, the account holds the
    // note, and no device has it. Played on the phone by letting go of its copy and of what it knew of the row, with
    // its account state as a build before this one kept it.
    final accountId = phone.account.session!.accountId;
    final key = 'glyph-sync-$accountId-notes';
    final state = Map<String, Object?>.from(phone.kept.read<Object?>(key, null)! as Map);
    state['notes'] = Map<String, Object?>.from(state['notes']! as Map)..remove('stray');
    state.remove('aside');
    phone.kept.write(key, state);
    phone.notes.remove('stray');
    phone.workspaces.fileNote('stray', plans.id);
    expect(live(trade.id), isEmpty);

    await phone.sync();
    expect(phone.notes['stray']?.body, '# Stray\n\nOnly the account has me.', reason: 'taken from the account’s copy');
    expect(live(trade.id), {'stray'}, reason: 'put to the team it is filed in');
    expect(world.service.notes['stray']?.deleted, isFalse, reason: 'the account’s row stays until the team holds it');
    await phone.sync();
    expect(world.service.notes['stray']?.deleted, isTrue, reason: 'and goes once it does');
    expect(live(trade.id), {'stray'});
    expect(phone.workspaces.workspaceOf('stray')?.id, plans.id);
    expect(phone.notes['stray']!.path, startsWith('orgs/HelloTrade/Plans/'));
  }, skip: coreSkip);

  test('a row the account’s feed passed over for a team’s note, on no device, is taken once the organization is gone, into its folder', () async {
    final phone = device('phone');
    await phone.account.signUp('matt', _password);
    final hello = await phone.orgs.createOrg('Hello HQ');
    await phone.sync();
    // A note of the account's that the settings filed in Hello HQ while no device had it, and that no device put to
    // the team: played on the phone by letting go of its copy and of what it knew of the row, its account state as a
    // build before this one kept it, and Hello HQ's channel read from nothing.
    phone.write('x', '# X\n\nThe account’s.');
    await phone.sync();
    final accountId = phone.account.session!.accountId;
    final key = 'glyph-sync-$accountId-notes';
    final state = Map<String, Object?>.from(phone.kept.read<Object?>(key, null)! as Map);
    state['notes'] = Map<String, Object?>.from(state['notes']! as Map)..remove('x');
    state.remove('aside');
    phone.kept.write(key, state);
    phone.kept.write('glyph-sync-$accountId-team-${hello.id}', null);
    phone.notes.remove('x');
    phone.workspaces.fileNote('x', orgWorkspaceId(hello.id));
    // The feed read again from its start once; the team cannot say yet it never had the note, so its row is passed
    // over and kept aside, never taken on a guess.
    await phone.sync();
    expect(phone.notes.containsKey('x'), isFalse);
    expect((phone.kept.read<Object?>(key, null)! as Map)['aside'], contains('x'));
    expect(live(hello.id), isEmpty);

    await phone.orgs.deleteOrg(hello.id);
    await phone.sync();
    expect(phone.notes['x']?.body, '# X\n\nThe account’s.', reason: 'taken once it is no team’s');
    expect(phone.workspaces.workspaceOf('x')?.id, personalTop(phone, 'Hello HQ').id);
    expect(phone.notes['x']!.path, 'workspaces/Hello HQ/x.md');
    expect(world.service.notes['x']?.deleted, isFalse);
  }, skip: coreSkip);
}
