// A note carried across an organization's edge and the sheet's Move pressed (lib/notes/folder_drag.dart; Matt,
// 2026-10-29: "Allow dragging files into folders for orgs instead of sending the error message open a confirm
// dialog"), then synced: the move is the note's filing alone, and the sync does the rest. This is what must hold
// through the round trip, after the incidents of 2026-10-20 (33f600e7) and 2026-10-26 (ddeb6141, 108 team notes
// deleted for every member): one copy of the note, where it was put, on both of the person's devices and on another
// member's; gone from where it left; never a team note deleted that should stay, never a copy.
//
// The devices are whole (test/e2e/world.dart): the real SyncEngine, account, organizations and their keys, and the
// REAL crypto and CRDT, the Rust core's through the Mac's library (tool/build-native.sh host); without it every case
// is skipped, out loud. The service is the one in memory, which holds one account: the phone and the Mac are the
// person's, and the other member is a device of the team's channel alone (test/team_sync/support.dart) holding the
// organization's key, as test/team_sync/sync_test.dart's members do. Each device's notes' files follow their filing
// (`folders`), as the app's do, so a team note's row carries its folder.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/folder_drag.dart';
import 'package:ghost_md/team/crdt.dart';

import '../e2e/world.dart';
import 'support.dart';

const String _password = 'correct horse battery';

void main() {
  late GhostCore core;
  late FakeWorld world;
  final devices = <Device>[];
  final members = <TeamDevice>[];

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
    for (final each in members) {
      await each.docs.forget();
    }
    devices.clear();
    members.clear();
  });

  Device device(String label) {
    final made = Device(world, core, label: label, folders: true);
    devices.add(made);
    return made;
  }

  /// Another member's device: the organization's channel alone, under its key, its folders its own.
  TeamDevice member(Device of, String orgId) {
    final made = TeamDevice(
      crdt: Crdt(core.invoke),
      api: world.api(),
      crypto: CoreCrypto(core.invoke),
      token: () => of.account.session!.token,
      orgId: orgId,
      orgKey: of.orgKeys.orgKeyOf(orgId)!,
      folders: true,
    );
    members.add(made);
    return made;
  }

  /// The team's live rows, by id.
  Set<String> live(String orgId) => {for (final MapEntry(:key, :value) in world.service.teamNotes(orgId).entries) if (!value.deleted) key};

  /// The rows the team ever held that are deleted now.
  Set<String> deleted(String orgId) => {for (final MapEntry(:key, :value) in world.service.teamNotes(orgId).entries) if (value.deleted) key};

  /// The sheet's Move: the move as the drop makes it once asked, and only once asked.
  void moveAsked(Device on, String noteId, String title, String? to) {
    final carry = FolderCarry.note(noteId, title);
    expect(folderVerdict(on.workspaces, carry, to).landing, FolderLanding.asks, reason: 'a move across the edge asks');
    expect(moveCarried(on.workspaces, carry, to), isNull, reason: 'nothing crosses unasked');
    expect(moveCarried(on.workspaces, carry, to, asked: true), isNotNull);
  }

  int conflicts(List<Device> each) => each.fold(0, (sum, d) => sum + d.engine.status.value.conflicts);

  test('a personal note moved into an organization’s folder: one copy, in that folder, on both devices and a member’s; gone from the person’s own; no team note deleted; and back out again', () async {
    final phone = device('phone'), mac = device('mac');
    await phone.account.signUp('matt', _password);
    await mac.account.signIn('matt', _password);
    final org = await phone.orgs.createOrg('HelloTrade', hue: 'violet');
    await phone.sync();
    final root = orgWorkspaceId(org.id);
    final meetings = phone.workspaces.addWorkspace('Meetings', 'ink', root)!;
    final home = phone.workspaces.addWorkspace('Home', 'sea')!;
    // The team's two notes, and the person's own: Plan in Home, Groceries in no folder.
    phone.write('standup', '# Standup\n\nThe team’s own.');
    phone.workspaces.fileNote('standup', meetings.id);
    phone.write('roadmap', '# Roadmap\n\n- ship');
    phone.workspaces.fileNote('roadmap', root);
    phone.write('plan', '# Plan\n\nMine, for now.', at: 2);
    phone.workspaces.fileNote('plan', home.id);
    phone.write('groceries', '# Groceries');
    await phone.sync();
    await mac.sync();
    await phone.sync();
    expect(live(org.id), {'standup', 'roadmap'});
    expect(mac.workspaces.workspaceOf('plan')?.id, home.id);
    expect(world.service.notes['plan']?.deleted, isFalse);
    final other = member(phone, org.id);
    await other.sync();
    expect(other.notes.keys.toSet(), {'standup', 'roadmap'});

    // Plan carried onto Meetings on the phone, and Move pressed.
    moveAsked(phone, 'plan', 'Plan', meetings.id);
    await phone.sync();
    await mac.sync();
    await phone.sync();
    await mac.sync();
    await other.sync();

    // One copy of it on every device, with its words, in Meetings; the team holds it; nothing of the team's went.
    expect(live(org.id), {'standup', 'roadmap', 'plan'});
    expect(deleted(org.id), isEmpty);
    for (final each in [phone, mac]) {
      expect(each.notes.keys.toSet(), {'standup', 'roadmap', 'plan', 'groceries'});
      expect(each.notes['plan']!.body, '# Plan\n\nMine, for now.');
      expect(each.workspaces.workspaceOf('plan')?.id, meetings.id);
      expect(each.workspaces.orgOf(meetings.id), org.id);
      // Gone from the person's own library: Home holds nothing now.
      expect(each.workspaces.notesUnder(home.id), isEmpty);
    }
    expect(other.notes.keys.toSet(), {'standup', 'roadmap', 'plan'});
    expect(other.notes['plan']!.body, '# Plan\n\nMine, for now.');
    expect(other.workspaces!.workspaceOf('plan')?.name, 'Meetings');
    // The account's own row went: the team carries it now. Groceries is still the account's.
    expect(world.service.notes['plan']?.deleted, isTrue);
    expect(world.service.notes['groceries']?.deleted, isFalse);
    expect(conflicts([phone, mac]), 0);

    // A quiet round trip after it changes nothing.
    final revs = {for (final e in world.service.teamNotes(org.id).entries) e.key: e.value.rev};
    await phone.sync();
    await mac.sync();
    await other.sync();
    expect({for (final e in world.service.teamNotes(org.id).entries) e.key: e.value.rev}, revs);
    expect(mac.notes.keys.toSet(), {'standup', 'roadmap', 'plan', 'groceries'});

    // Back out to Home, from the Mac this time: the team's row goes, which deletes it on the other member's device;
    // both of the person's devices keep it, in Home, as the account's again. The team's other notes stay.
    moveAsked(mac, 'plan', 'Plan', home.id);
    await mac.sync();
    await phone.sync();
    await mac.sync();
    await phone.sync();
    await other.sync();
    expect(live(org.id), {'standup', 'roadmap'});
    expect(deleted(org.id), {'plan'});
    for (final each in [phone, mac]) {
      expect(each.notes.keys.toSet(), {'standup', 'roadmap', 'plan', 'groceries'}, reason: 'the person keeps it on every device of theirs');
      expect(each.notes['plan']!.body, '# Plan\n\nMine, for now.');
      expect(each.workspaces.workspaceOf('plan')?.id, home.id);
    }
    expect(other.notes.keys.toSet(), {'standup', 'roadmap'});
    expect(world.service.notes['plan']?.deleted, isFalse);
    expect(conflicts([phone, mac]), 0);
  }, skip: coreSkip);

  test('a team note goes from one organization to another only by way of the person’s own notes: refused straight across, and out then in leaves one copy, its words once, the new team’s, the old team’s row alone gone', () async {
    final phone = device('phone'), mac = device('mac');
    await phone.account.signUp('matt', _password);
    await mac.account.signIn('matt', _password);
    // HelloTrade first and Ghost.md second, the order each pass takes their channels in: the note leaves the second
    // and lands in the first, so on the Mac the new team's row would be taken before the old team's deletion.
    final hello = await phone.orgs.createOrg('HelloTrade', hue: 'violet');
    final ghost = await phone.orgs.createOrg('Ghost.md', hue: 'sea');
    await phone.sync();
    final meetings = phone.workspaces.addWorkspace('Meetings', 'ink', orgWorkspaceId(hello.id))!;
    phone.write('brief', '# Brief\n\nFor whoever has it.');
    phone.workspaces.fileNote('brief', orgWorkspaceId(ghost.id));
    phone.write('kept', '# Kept\n\nGhost.md’s, and stays.');
    phone.workspaces.fileNote('kept', orgWorkspaceId(ghost.id));
    phone.write('standup', '# Standup');
    phone.workspaces.fileNote('standup', meetings.id);
    await phone.sync();
    await mac.sync();
    await phone.sync();
    expect(live(ghost.id), {'brief', 'kept'});
    expect(live(hello.id), {'standup'});
    final atHello = member(phone, hello.id), atGhost = member(phone, ghost.id);
    await atHello.sync();
    await atGhost.sync();

    // Straight across: refused, and nothing moves, asked or not.
    const carried = FolderCarry.note('brief', 'Brief');
    expect(folderVerdict(phone.workspaces, carried, meetings.id).landing, FolderLanding.refused);
    expect(moveCarried(phone.workspaces, carried, meetings.id, asked: true), isNull);
    expect(phone.workspaces.workspaceOf('brief')?.id, orgWorkspaceId(ghost.id));

    // Out into a folder of the person's own, synced on both devices; then into HelloTrade › Meetings, synced again.
    final away = phone.workspaces.addWorkspace('Away')!;
    moveAsked(phone, 'brief', 'Brief', away.id);
    for (var pass = 0; pass < 2; pass += 1) {
      await phone.sync();
      await mac.sync();
    }
    expect(live(ghost.id), {'kept'});
    expect(mac.notes.containsKey('brief'), isTrue);
    expect(mac.workspaces.workspaceOf('brief')?.id, away.id);
    moveAsked(phone, 'brief', 'Brief', meetings.id);
    for (var pass = 0; pass < 3; pass += 1) {
      await phone.sync();
      await mac.sync();
    }
    await atHello.sync();
    await atGhost.sync();

    expect(live(hello.id), {'standup', 'brief'});
    expect(deleted(hello.id), isEmpty);
    expect(live(ghost.id), {'kept'});
    expect(deleted(ghost.id), {'brief'});
    for (final each in [phone, mac]) {
      expect(each.notes.keys.toSet(), {'brief', 'kept', 'standup'});
      expect(each.notes['brief']!.body, '# Brief\n\nFor whoever has it.', reason: 'its words once, never doubled');
      expect(each.workspaces.workspaceOf('brief')?.id, meetings.id);
    }
    expect(atHello.notes.keys.toSet(), {'standup', 'brief'});
    expect(atHello.notes['brief']!.body, '# Brief\n\nFor whoever has it.');
    expect(atHello.workspaces!.workspaceOf('brief')?.name, 'Meetings');
    expect(atGhost.notes.keys.toSet(), {'kept'});
    expect(conflicts([phone, mac]), 0);
  }, skip: coreSkip);
}
