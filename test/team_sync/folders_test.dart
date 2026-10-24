// An organization's folders between two members' devices (lib/team/folders.dart, lib/team/sync.dart; GHST-107,
// slice 1): a note filed in a folder arrives on the other device in a folder of that name, at the same path; a
// note moved into a folder stays the team's and one moved out of the organization leaves it; a folder renamed or
// moved on one device moves its notes on the other, which drops the folder left empty; a folder empty before a pass
// is nobody's to drop; and the engine's hook hands the channel the folders.
//
// The CRDT is the REAL one, the Rust core's through the Mac's library (tool/build-native.sh host); without it every
// case is skipped, out loud, as test/team_sync/sync_test.dart's are. Each device has the organization's workspace
// and folders in a store of its own (support.dart `TeamDevice(folders: true)`), its filings moving the notes'
// paths as the app moves their files.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/orgs/types.dart';
import 'package:ghost_md/sync/engine.dart' show TeamPass;
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/sync.dart';

import '../feed/signed.dart' show apiOf, testAccount;
import '../support/fake_service.dart';
import 'support.dart';

void main() {
  final skip = coreSkip;
  late GhostCore core;
  late Crdt crdt;
  late FakeService service;
  late String orgId;
  late SealKey orgKey;
  final made = <TeamDevice>[];

  setUpAll(() async {
    if (!coreBuilt) return;
    core = await openCore();
    crdt = Crdt(core.invoke);
  });

  tearDownAll(() async {
    if (coreBuilt) await core.close();
  });

  setUp(() async {
    if (!coreBuilt) return;
    service = await FakeService.start(seed: testAccount);
    final answer = await apiOf(service).callMap('POST', 'orgs', token: service.signedIn(), body: {'name': 'Ghost', 'hue': 'sea'});
    orgId = (answer['org'] as Map)['id'] as String;
    orgKey = await service.crypto.importSealKey(service.crypto.randomBytes(32));
  });

  tearDown(() async {
    for (final device in made) {
      await device.docs.forget();
    }
    made.clear();
  });

  TeamDevice device() {
    final one = TeamDevice(crdt: crdt, api: apiOf(service), crypto: service.crypto, token: service.signedIn, orgId: orgId, orgKey: orgKey, folders: true);
    made.add(one);
    return one;
  }

  /// A device's folders under the organization's workspace, as paths: "Clients", "Clients › Acme".
  List<String> foldersOf(TeamDevice d) => [
        for (final w in d.workspaces!.value.list)
          if (w.id != d.root && d.workspaces!.orgOf(w.id) == orgId) workspacePathName(d.workspaces!.value.list, w.id).replaceFirst('Ghost › ', ''),
      ];

  /// Which folder a note is filed in on a device, as a path, or "Ghost" for the organization's own workspace.
  String? filedIn(TeamDevice d, String id) {
    final space = d.workspaces!.workspaceOf(id);
    return space == null ? null : workspacePathName(d.workspaces!.value.list, space.id);
  }

  test('a note filed in a new folder arrives on the other device in a folder of that name, at the same path', () async {
    final phone = device();
    final clients = phone.workspaces!.addWorkspace('Clients', 'moss', phone.root)!;
    final acme = phone.workspaces!.addWorkspace('Acme', 'ink', clients.id)!;
    phone.put('n1', '# Plan', into: clients.id);
    phone.put('n2', '# Brief', into: acme.id);
    phone.put('n3', '# Minutes');
    expect(phone.notes['n1']!.path, 'orgs/Ghost/Clients/n1.md');
    expect(phone.notes['n2']!.path, 'orgs/Ghost/Clients/Acme/n2.md');
    expect(saidOutcome(await phone.sync()), 'changed 0, sent 3, unsent 0, reason null');
    final mac = device();
    expect((await mac.sync()).changed, 3);
    // The folders, made by name under the organization's workspace, and the notes filed in them; the paths kept.
    expect(foldersOf(mac), ['Clients', 'Clients › Acme']);
    expect(filedIn(mac, 'n1'), 'Ghost › Clients');
    expect(filedIn(mac, 'n2'), 'Ghost › Clients › Acme');
    expect(filedIn(mac, 'n3'), 'Ghost');
    expect(mac.notes['n1']!.path, 'orgs/Ghost/Clients/n1.md');
    expect(mac.notes['n2']!.path, 'orgs/Ghost/Clients/Acme/n2.md');
    expect(mac.notes['n3']!.path, 'orgs/Ghost/n3.md');
    // Nothing of the folders crossed but the paths, and still each device made the same one: a folder's id is its
    // place's (lib/core/workspaces.dart `folderIdFor`, 2026-10-23), so the account's settings meet it as one.
    expect(mac.workspaces!.childrenOf(mac.root).single.id, clients.id);
    // A quiet pass changes nothing, and puts nothing again: the paths agree.
    expect(saidOutcome(await mac.sync()), 'changed 0, sent 0, unsent 0, reason null');
    expect(saidOutcome(await phone.sync()), 'changed 0, sent 0, unsent 0, reason null');
  }, skip: skip);

  test('a note moved into a folder stays the team’s, put again; one moved out of the organization leaves it, and its folder goes where it is empty', () async {
    final phone = device(), mac = device();
    phone.put('n1', '# Plan');
    await phone.sync();
    await mac.sync();
    expect(filedIn(mac, 'n1'), 'Ghost');
    // Into a folder: the path changed, so the row is put again; nothing is deleted.
    final acme = phone.workspaces!.addWorkspace('Acme', 'ink', phone.root)!;
    phone.workspaces!.fileNote('n1', acme.id);
    expect(phone.notes['n1']!.path, 'orgs/Ghost/Acme/n1.md');
    final before = service.calls.length;
    expect(saidOutcome(await phone.sync()), 'changed 0, sent 1, unsent 0, reason null');
    expect(service.calls.sublist(before).where((call) => call.startsWith('DELETE')), isEmpty);
    expect(service.teamNotes(orgId)['n1']!.deleted, isFalse);
    expect((await mac.sync()).changed, 1);
    expect(foldersOf(mac), ['Acme']);
    expect(filedIn(mac, 'n1'), 'Ghost › Acme');
    // Out of the organization, to a personal workspace: gone from the team, and from the mac, whose Acme is empty now.
    final mine = phone.workspaces!.addWorkspace('Mine')!;
    phone.workspaces!.fileNote('n1', mine.id);
    expect(phone.notes['n1']!.path, 'workspaces/Mine/n1.md');
    await phone.sync();
    expect(service.teamNotes(orgId)['n1']!.deleted, isTrue);
    expect((await mac.sync()).changed, 1);
    expect(mac.notes.containsKey('n1'), isFalse);
    expect(foldersOf(mac), isEmpty);
    // The phone's own Acme, empty before any pass of its own, stands.
    await phone.sync();
    expect(foldersOf(phone), ['Acme']);
  }, skip: skip);

  test('a folder renamed on one device moves its notes on the other into a folder of the new name, and the old one goes', () async {
    final phone = device(), mac = device();
    final clients = phone.workspaces!.addWorkspace('Clients', 'ink', phone.root)!;
    final acme = phone.workspaces!.addWorkspace('Acme', 'ink', clients.id)!;
    phone.put('n1', '# Plan', into: clients.id);
    phone.put('n2', '# Brief', into: acme.id);
    await phone.sync();
    await mac.sync();
    expect(foldersOf(mac), ['Clients', 'Clients › Acme']);
    // The rename moves the files of the folder and of the one inside it, before the next pass puts the rows again.
    phone.workspaces!.renameWorkspace(clients.id, 'Customers');
    expect(phone.notes['n1']!.path, 'orgs/Ghost/Customers/n1.md');
    expect(phone.notes['n2']!.path, 'orgs/Ghost/Customers/Acme/n2.md');
    expect(saidOutcome(await phone.sync()), 'changed 0, sent 2, unsent 0, reason null');
    expect((await mac.sync()).changed, 2);
    expect(foldersOf(mac), ['Customers', 'Customers › Acme']);
    expect(filedIn(mac, 'n1'), 'Ghost › Customers');
    expect(filedIn(mac, 'n2'), 'Ghost › Customers › Acme');
    expect(mac.notes['n1']!.path, 'orgs/Ghost/Customers/n1.md');
    expect(mac.notes['n2']!.path, 'orgs/Ghost/Customers/Acme/n2.md');
    // The mac's words are not lost to the move: edited there meanwhile, they merge as ever.
    mac.write('n2', '# Brief\n- read');
    await mac.sync();
    await phone.sync();
    expect(phone.notes['n2']!.body, '# Brief\n- read');
    expect(phone.notes['n2']!.path, 'orgs/Ghost/Customers/Acme/n2.md');
    // A move, the same way: Acme up to the organization's workspace on the mac, and Customers stands with n1 still in it.
    final macAcme = mac.workspaces!.value.list.firstWhere((w) => w.name == 'Acme');
    mac.workspaces!.moveWorkspace(macAcme.id, mac.root);
    expect(mac.notes['n2']!.path, 'orgs/Ghost/Acme/n2.md');
    await mac.sync();
    expect((await phone.sync()).changed, 1);
    expect(foldersOf(phone), ['Customers', 'Acme']);
    expect(filedIn(phone, 'n2'), 'Ghost › Acme');
    expect(phone.notes['n2']!.path, 'orgs/Ghost/Acme/n2.md');
    // And nothing more to say on either side.
    expect(saidOutcome(await phone.sync()), 'changed 0, sent 0, unsent 0, reason null');
    expect(saidOutcome(await mac.sync()), 'changed 0, sent 0, unsent 0, reason null');
  }, skip: skip);

  test('a folder empty before a pass is left alone: one just made here, or one emptied by hand', () async {
    final phone = device(), mac = device();
    phone.put('n1', '# Plan');
    await phone.sync();
    final ideas = mac.workspaces!.addWorkspace('Ideas', 'ink', mac.root)!;
    await mac.sync();
    expect(foldersOf(mac), ['Ideas']);
    // Filled, then emptied by hand between passes: still the person's own doing, not the team's.
    mac.workspaces!.fileNote('n1', ideas.id);
    await mac.sync();
    await phone.sync();
    expect(foldersOf(phone), ['Ideas']);
    mac.workspaces!.fileNote('n1', mac.root);
    await mac.sync();
    expect(foldersOf(mac), ['Ideas']);
    // The phone's Ideas, emptied by that pass, goes.
    await phone.sync();
    expect(foldersOf(phone), isEmpty);
  }, skip: skip);

  test('the engine’s hook hands the channel the folders, and files by path through them', () async {
    final phone = device(), mac = device();
    final clients = phone.workspaces!.addWorkspace('Clients', 'ink', phone.root)!;
    phone.put('n1', '# Plan', into: clients.id);
    await phone.sync();
    Object? kept;
    final pass = TeamPass(
      token: service.signedIn(),
      accountId: fakeAccountId,
      org: OrgRow.fromJson({'id': orgId, 'name': 'Ghost', 'role': 'owner', 'state': 'member', 'members': 1, 'createdAt': 0})!,
      key: orgKey,
      generation: 0,
      olderKey: null,
      notes: mac.local,
      files: mac.files,
      api: apiOf(service),
      crypto: service.crypto,
      loadState: () => kept,
      saveState: (s) => kept = s,
      isTeamNote: mac.isTeamNote,
      file: mac.file,
      folders: mac.folders,
      pulled: () {},
    );
    expect((await teamNotesPass(mac.docs)(pass)).changed, 1);
    expect(foldersOf(mac), ['Clients']);
    expect(filedIn(mac, 'n1'), 'Ghost › Clients');
  }, skip: skip);
}
