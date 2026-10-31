// A member's trash and the team (lib/team/sync.dart with library/trash.rs, 2026-10-31): the trash is the person's,
// not the organization's. A member's trashed copy is put to the team at the path it had, so no other member's file
// moves into `.trash/`; a row landing over a trashed copy leaves it in the trash; and a member's deletion still
// removes the note outright, trashed or not, as an organization's deletes have always skipped the Trash.
//
// The CRDT is the REAL one, the Rust core's through the Mac's library (tool/build-native.sh host); without it every
// case is skipped, out loud.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_folders.dart' show orgFolderNames;
import 'package:ghost_md/core/note_json.dart';
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

  /// A member's device with the organization's folders, so its notes have paths as the app's do.
  TeamDevice device() {
    final one = TeamDevice(crdt: crdt, api: apiOf(service), crypto: service.crypto, token: service.signedIn, orgId: orgId, orgKey: orgKey, folders: true);
    made.add(one);
    return one;
  }

  Future<Note> rowNote(String id) async {
    final payload = (await service.crypto.open(orgKey, service.teamNotes(orgId)[id]!.blob!, 'org:$orgId:note:$id') as Map).cast<String, Object?>();
    return noteFromJson(payload['note'])!;
  }

  test('a member’s trashed copy is put at the path it had, lands in nobody else’s trash, and stays in the member’s through a pull', () async {
    final phone = device(), mac = device();
    phone.put('n1', '# Roadmap\n- ship');
    await phone.sync();
    await mac.sync();
    expect(mac.notes['n1']!.path, 'orgs/Ghost/n1.md');

    // Trashed on the phone: its file moves under `.trash/`, which is no change to the team.
    phone.notes['n1'] = phone.notes['n1']!.copyWith(path: () => trashedPathOf('orgs/Ghost/n1.md'));
    expect(saidOutcome(await phone.sync()), 'changed 0, sent 0, unsent 0, reason null', reason: 'the particulars read the path it had');
    // Its words changed in the trash (a tag renamed across every note, say): the row goes with its live path.
    phone.write('n1', '# Roadmap\n- ship\n- #done');
    expect((await phone.sync()).sent, 1);
    expect((await rowNote('n1')).path, 'orgs/Ghost/n1.md');
    await mac.sync();
    expect(mac.notes['n1']!.body, '# Roadmap\n- ship\n- #done');
    expect(mac.notes['n1']!.path, 'orgs/Ghost/n1.md', reason: 'the Mac’s copy is where it was, not in its trash');

    // The Mac's edit lands on the phone: the words move, the file stays in the phone's trash.
    mac.write('n1', '# Roadmap\n- ship\n- #done\n- celebrate');
    await mac.sync();
    expect((await phone.sync()).changed, 1);
    expect(phone.notes['n1']!.body, '# Roadmap\n- ship\n- #done\n- celebrate');
    expect(phone.notes['n1']!.path, '.trash/orgs/Ghost/n1.md');
    expect(phone.notes['n1']!.inTrash, isTrue);
  }, skip: skip);

  test('a member’s deletion removes the note outright on a device that had it in the trash, as an organization’s deletes always skipped the Trash', () async {
    final phone = device(), mac = device();
    phone.put('n1', '# Roadmap');
    await phone.sync();
    // The Mac has a note of its own too, so its library never reads as empty (which deletes nothing, by design).
    mac.put('n2', '# Minutes');
    await mac.sync();
    phone.notes['n1'] = phone.notes['n1']!.copyWith(path: () => trashedPathOf('orgs/Ghost/n1.md'));
    await phone.sync();
    // Deleted for good on the Mac.
    mac.notes.remove('n1');
    await mac.sync();
    expect(service.teamNotes(orgId)['n1']!.deleted, isTrue);
    expect((await phone.sync()).changed, 1);
    expect(phone.notes['n1'], isNull, reason: 'gone, not left in the trash');
  }, skip: skip);

  test('a row whose path somehow carries .trash/ is filed under the path beneath it', () {
    expect(orgFolderNames('.trash/orgs/Ghost/Clients/Acme/Plan.md'), ['Clients', 'Acme']);
    expect(particulars(Note(id: 'a', body: '', createdAt: 1, updatedAt: 1, path: '.trash/orgs/Ghost/Plan.md')), particulars(Note(id: 'a', body: '', createdAt: 1, updatedAt: 1, path: 'orgs/Ghost/Plan.md')));
  });
}
