// A fresh web library signing in to an account whose organization keeps notes in folders under its workspace
// deletes nothing on the team (2026-10-26, 19:02 UTC: the old Tauri page at attack.fm/glyph read every organization
// sub-folder note as personal and deleted 108 team notes for every member; the web build replaces that page).
//
// The web device's notes are the web build's own library (lib/web/web_store.dart, through the commands
// lib/sync/local.dart `LibraryNotes` asks), over a shelf in memory as IndexedDB is behind it; its organization's
// folders are a store of its own, empty until the team's pass files what arrives (test/team_sync/support.dart
// `TeamDevice(folders: true)`). The CRDT is the REAL one, the Rust core's through the Mac's library
// (tool/build-native.sh host), which the browser's core is compiled from; without it every case is skipped, out
// loud, as test/team_sync's are. The service is the one in memory: every DELETE it is sent is counted.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/sync/local.dart';
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/sync.dart';
import 'package:ghost_md/web/shelf.dart';
import 'package:ghost_md/web/web_core.dart';
import 'package:ghost_md/web/web_store.dart';

import '../feed/signed.dart' show apiOf, testAccount;
import '../support/fake_service.dart';
import '../team_sync/support.dart';
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

  /// The web build's library over [shelf], as the page opens it, and the notes the sync pass is handed from it.
  Future<(WebStore, LibraryNotes)> webLibrary(Shelf shelf) async {
    final ask = browserCoreStandIn(rest: core.invoke);
    final store = await WebStore.open(shelf, ask);
    return (store, LibraryNotes(WebCore(store, ask).invoke));
  }

  List<String> deletesSince(int at) => [for (final call in service.calls.sublist(at)) if (call.startsWith('DELETE')) call];

  test('a fresh web library takes in the organization\'s folder notes at their paths, and deletes nothing on the team', () async {
    // A member's phone files three notes: one in the organization's workspace, two in folders under it.
    final phone = device();
    final clients = phone.workspaces!.addWorkspace('Clients', 'moss', phone.root)!;
    final acme = phone.workspaces!.addWorkspace('Acme', 'ink', clients.id)!;
    phone.put('n1', '# Plan', into: clients.id);
    phone.put('n2', '# Brief', into: acme.id);
    phone.put('n3', '# Minutes');
    await phone.sync();
    expect(service.teamNotes(orgId).length, 3);

    // The browser signs in: an empty library, no folders known, the team's state empty.
    final before = service.calls.length;
    final shelf = MemoryShelf();
    final (store, notes) = await webLibrary(shelf);
    final web = device();
    expect((await syncTeamNotes(web.context(notes: notes))).changed, 3);
    final kept = {for (final note in await notes.list()) note.id: note.path};
    expect(kept, {'n1': 'orgs/Ghost/Clients/n1.md', 'n2': 'orgs/Ghost/Clients/Acme/n2.md', 'n3': 'orgs/Ghost/n3.md'});
    expect(store.count, 3);
    // A second pass, quiet: nothing sent, nothing deleted.
    final quiet = await syncTeamNotes(web.context(notes: notes));
    expect([quiet.sent, quiet.unsent], [0, 0]);
    expect(deletesSince(before), isEmpty);
    expect([for (final row in service.teamNotes(orgId).values) row.deleted], everyElement(isFalse));
  }, skip: skip);

  test('a web page reloaded with the team\'s state but none of the organization\'s folders known keeps every team row', () async {
    final phone = device();
    final clients = phone.workspaces!.addWorkspace('Clients', 'moss', phone.root)!;
    phone.put('n1', '# Plan', into: clients.id);
    phone.put('n2', '# Notes', into: clients.id);
    await phone.sync();

    final shelf = MemoryShelf();
    final (_, notes) = await webLibrary(shelf);
    final web = device();
    await syncTeamNotes(web.context(notes: notes));
    final state = web.state;

    // The page is loaded again: the library read back off its shelf, the team's state kept, and a workspace store
    // that has not learned the folders (the incident's device, which read the folder notes as no team's).
    final before = service.calls.length;
    final (again, notesAgain) = await webLibrary(shelf);
    expect(again.count, 2);
    final reloaded = TeamDevice(crdt: crdt, api: apiOf(service), crypto: service.crypto, token: service.signedIn, orgId: orgId, orgKey: orgKey);
    made.add(reloaded);
    reloaded.state = state;
    expect(reloaded.isTeamNote('n1'), isFalse, reason: 'this device places neither note in the team');
    await syncTeamNotes(reloaded.context(notes: notesAgain));
    expect(deletesSince(before), isEmpty);
    expect([for (final row in service.teamNotes(orgId).values) row.deleted], everyElement(isFalse));

    // And a library that reads as empty (a browser whose storage was cleared) deletes nothing either.
    final (_, empty) = await webLibrary(MemoryShelf());
    await syncTeamNotes(reloaded.context(notes: empty));
    expect(deletesSince(before), isEmpty);
    expect([for (final row in service.teamNotes(orgId).values) row.deleted], everyElement(isFalse));
  }, skip: skip);
}
