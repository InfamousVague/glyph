// A team's notes between two members' devices (lib/team/sync.dart; docs/SHARED.md, S1, S4, S5, S11): a note filed
// in the organization's workspace published, adopted on another device with its words kept, edited on both and
// merged by the CRDT, snapshotted, taken out of the team, its versions file and pictures carried, and the key
// turning under it. A port of `src/app/core/team/sync.test.ts`, case for case.
//
// The CRDT is the REAL one, the Rust core's through the Mac's library (tool/build-native.sh host); without it every
// case is skipped, out loud. The service is the one in memory and the crypto its fake: the wire's own proof is
// test/e2e. Two devices here share the service's one account, which stands for both members: the channel keys
// nothing by account, and the rows and logs are the organization's. Each device has its own notes, files,
// documents and state (where the web's two share a module's documents and forget them between passes, each here
// has its own `TeamDocs`; `reopened` is the app closed and opened, which reads them back from the store).
//
// The last group is this port's own: the hook the engine is given, and what the port does differently.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/bytes.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_json.dart';
import 'package:ghost_md/orgs/types.dart';
import 'package:ghost_md/sync/engine.dart' show TeamPass;
import 'package:ghost_md/sync/notes.dart' show FileKind;
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/docs.dart';
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

  Future<SealKey> freshKey() => service.crypto.importSealKey(service.crypto.randomBytes(32));

  setUp(() async {
    if (!coreBuilt) return;
    service = await FakeService.start(seed: testAccount);
    final answer = await apiOf(service).callMap('POST', 'orgs', token: service.signedIn(), body: {'name': 'Ghost', 'hue': 'sea'});
    orgId = (answer['org'] as Map)['id'] as String;
    orgKey = await freshKey();
  });

  tearDown(() async {
    for (final device in made) {
      await device.docs.forget();
    }
    made.clear();
  });

  TeamDevice device({TeamDocStore? store}) {
    final one = TeamDevice(crdt: crdt, api: apiOf(service), crypto: service.crypto, token: service.signedIn, orgId: orgId, orgKey: orgKey, store: store);
    made.add(one);
    return one;
  }

  Future<Map<String, Object?>> opened(SealKey key, String id) async => (await service.crypto.open(key, service.teamNotes(orgId)[id]!.blob!, 'org:$orgId:note:$id') as Map).cast<String, Object?>();
  String bodyOf(Map<String, Object?> payload) => (payload['note'] as Map)['body'] as String;

  group('a team note between two devices', () {
    test('is published by the first device as a row the service cannot read, and adopted by the second with its words and particulars', () async {
      final phone = device();
      phone.put('n1', '# Roadmap\n- ship', starred: true);
      final outcome = await phone.sync();
      expect(saidOutcome(outcome), 'changed 0, sent 1, unsent 0, reason null');
      final rows = service.teamNotes(orgId);
      expect(rows, hasLength(1));
      final row = rows['n1']!;
      expect(row.blob, isNot(contains('Roadmap')));
      final payload = await opened(orgKey, 'n1');
      expect(payload['seq'], 0);
      expect(payload['v'], 1);
      final written = noteFromJson(payload['note'])!;
      expect(written.body, '# Roadmap\n- ship');
      expect(written.starred, isTrue);
      expect(phone.state.notes['n1'], TeamMark(rev: row.rev, mark: particulars(written)));
      expect(service.teamUpdates(orgId, 'n1'), isEmpty);
      // The other device: the note arrives, filed, with its words and its pin, and a document of its own.
      final mac = device();
      final arrived = await mac.sync();
      expect(arrived.changed, 1);
      expect(mac.notes['n1']!.body, '# Roadmap\n- ship');
      expect(mac.notes['n1']!.starred, isTrue);
      expect(mac.filed, contains('n1'));
      expect((await mac.docs.store.read('n1'))?.seq, 0);
      // Nothing more on a quiet pass, either side: the feed and the heads are read, and no note's log is.
      final before = service.calls.length;
      expect((await mac.sync()).changed, 0);
      expect(service.calls.sublist(before), ['GET orgs/$orgId/notes', 'GET orgs/$orgId/heads']);
    }, skip: skip);

    test('carries edits made apart to both sides and merges them by the CRDT, with no copy', () async {
      final phone = device();
      phone.put('n1', 'one\ntwo\nthree');
      await phone.sync();
      final mac = device();
      await mac.sync();
      // Edited on both, apart: the phone at the top, the mac at the foot. Each pass reconciles its note's words.
      phone.write('n1', 'ONE\ntwo\nthree');
      mac.write('n1', 'one\ntwo\nTHREE');
      await phone.reopened();
      await phone.sync();
      expect(service.teamUpdates(orgId, 'n1'), hasLength(1));
      await mac.reopened();
      await mac.sync();
      expect(mac.notes['n1']!.body, 'ONE\ntwo\nTHREE');
      await phone.sync();
      expect(phone.notes['n1']!.body, 'ONE\ntwo\nTHREE');
      expect(phone.notes.keys, ['n1']);
      expect(mac.notes.keys, ['n1']);
      // The updates on the log are sealed, and open under the organization key alone.
      final update = service.teamUpdates(orgId, 'n1').first;
      expect(await service.crypto.openBytes(orgKey, fromBase64Url(update.blob), 'org:$orgId:note:n1:update'), isA<Uint8List>());
      await expectLater(service.crypto.openBytes(orgKey, fromBase64Url(update.blob), 'org:$orgId:note:n2:update'), throwsA(anything));
    }, skip: skip);

    test('keeps the words a device had of its own before the team did, as a change for the team', () async {
      final phone = device();
      phone.put('n1', '# Plan\n- a');
      await phone.sync();
      // The mac had the same note of its own, with a line more, before the team's row reached it.
      final mac = device();
      mac.put('n1', '# Plan\n- a\n- b (mine)');
      await mac.sync();
      expect(mac.notes['n1']!.body, '# Plan\n- a\n- b (mine)');
      await phone.sync();
      expect(phone.notes['n1']!.body, '# Plan\n- a\n- b (mine)');
    }, skip: skip);

    test('puts the row again for a changed pin or archive, and after enough updates, cutting the log', () async {
      final phone = device();
      phone.put('n1', 'words');
      await phone.sync();
      final first = service.teamNotes(orgId)['n1']!.rev;
      phone.notes['n1'] = phone.notes['n1']!.copyWith(archivedAt: () => 5);
      await phone.sync();
      expect(service.teamNotes(orgId)['n1']!.rev, greaterThan(first));
      // Many small edits: each pass posts one update; past the snapshot count the row goes again and the log is cut.
      for (var i = 0; i < snapshotEvery + 1; i += 1) {
        phone.write('n1', 'words $i');
        await phone.sync();
      }
      // The snapshot went at the two-hundredth update and cut the log to there; the one edit since is on it alone.
      expect([for (final u in service.teamUpdates(orgId, 'n1')) u.seq], [snapshotEvery + 1]);
      final doc = (await phone.docs.doc('n1'))!;
      expect([doc.snapshotSeq, doc.seq], [snapshotEvery, snapshotEvery + 1]);
    }, skip: skip);

    test('takes a note from the team when a device deletes it or takes it out of the workspace', () async {
      final phone = device();
      phone.put('n1', 'going');
      phone.put('n2', 'leaving the team');
      await phone.sync();
      final mac = device();
      await mac.sync();
      expect(mac.notes.keys.toList()..sort(), ['n1', 'n2']);
      phone.notes.remove('n1');
      phone.filed.remove('n2');
      await phone.sync();
      expect(service.teamNotes(orgId)['n1']!.deleted, isTrue);
      expect(service.teamNotes(orgId)['n2']!.deleted, isTrue);
      expect(phone.notes.containsKey('n2'), isTrue);
      expect(await phone.docs.store.read('n2'), isNull);
      expect(phone.docs.held(), isEmpty);
      await mac.sync();
      expect(mac.notes.keys, isEmpty);
    }, skip: skip);

    test('carries a note\'s versions file, merged, and its pictures, under the organization', () async {
      final phone = device();
      phone.put('n1', 'See ![](image/photo.png)');
      phone.pictures['photo.png'] = Uint8List.fromList([1, 2, 3]);
      phone.versions['n1'] = '# Ghost.md versions 1\n# note n1\n\nv1 2026-10-05T00:00:00.000Z matt 00000000 full\n  +See\n';
      phone.owed.add('n1');
      await phone.sync();
      expect(service.teamFiles(orgId).keys.toList()..sort(), ['i-png-photo', 'v-n1']);
      expect(phone.owed, isNot(contains('n1')));
      final mac = device();
      await mac.sync();
      expect(mac.pictures['photo.png'], [1, 2, 3]);
      expect(mac.versions['n1'], contains('v1 2026-10-05'));
    }, skip: skip);

    test('counts a send that fails and goes on, and ends on a lapsed session', () async {
      final phone = device();
      phone.put('n1', 'words');
      phone.put('n2', 'more words');
      Future<FetchResponse> failing(FetchRequest request) async {
        if (request.url.path.endsWith('/notes/n1') && request.method == 'PUT') return FetchResponse.json(500, {'error': 'The service is down.'});
        return service.fetcher(request);
      }

      final outcome = await phone.sync(through: apiOf(service, failing));
      expect(saidOutcome(outcome), 'changed 0, sent 1, unsent 1, reason The service is down.');
      expect(service.teamNotes(orgId).keys, ['n2']);
      // The next pass sends what the last could not.
      expect(saidOutcome(await phone.sync()), 'changed 0, sent 1, unsent 0, reason null');
      // A lapsed session is not counted: it ends the pass, for the engine to renew.
      final held = phone.context();
      service.expireAllTokens();
      await expectLater(syncTeamNotes(held), throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)));
    }, skip: skip);
  });

  group('the key turning under the team (docs/SHARED.md, S11)', () {
    // The organization with its key at generation `at`, as the service keeps it: what a device's writes are checked
    // against.
    void inForce(int at) => service.orgs[orgId]!.generation = at;

    test('puts every note, its log cut, and its files again under the new key, so a member who reads with it finds everything', () async {
      inForce(1);
      final phone = device();
      phone.put('n1', 'words ![](image/photo.png)');
      phone.pictures['photo.png'] = Uint8List.fromList([1, 2, 3]);
      phone.versions['n1'] = 'v1\n';
      phone.owed.add('n1');
      await phone.sync(generation: 1);
      for (var i = 0; i < 3; i += 1) {
        phone.write('n1', 'words $i ![](image/photo.png)');
        await phone.sync(generation: 1);
      }
      expect(service.teamUpdates(orgId, 'n1'), isNotEmpty);
      final before = service.teamNotes(orgId)['n1']!;
      // The turn: the service names generation 2, and the phone, holding it, puts everything again under it.
      final turned = await freshKey();
      inForce(2);
      final resealed = await resealTeamNotes(phone.context(key: turned, generation: 2));
      expect(resealed.unsent, 0);
      final row = service.teamNotes(orgId)['n1']!;
      expect(row.rev, greaterThan(before.rev));
      expect(service.teamUpdates(orgId, 'n1'), isEmpty);
      await expectLater(opened(orgKey, 'n1'), throwsA(anything));
      expect(bodyOf(await opened(turned, 'n1')), 'words 2 ![](image/photo.png)');
      // A member reading with the new key alone has the row, the log, the picture and the versions.
      final laptop = device();
      await laptop.sync(key: turned, generation: 2);
      expect(laptop.notes['n1']?.body, 'words 2 ![](image/photo.png)');
      expect(laptop.pictures['photo.png'], [1, 2, 3]);
      expect(laptop.versions['n1'], 'v1\n');
    }, skip: skip);

    test('refuses a write under a generation no longer in force, and the channel stops with the turn rather than counting it unsent', () async {
      inForce(1);
      final phone = device();
      phone.put('n1', 'words');
      await phone.sync(generation: 1);
      final before = service.teamNotes(orgId)['n1']!;
      inForce(2);
      phone.write('n1', 'words typed after the turn');
      await expectLater(phone.sync(generation: 1), throwsA(isA<KeyTurned>().having((e) => e.generation, 'generation', 2)));
      // Nothing of it reached the service under the old key; the next pass, under the new one, carries it.
      expect(service.teamUpdates(orgId, 'n1'), isEmpty);
      final turned = await freshKey();
      // The row still under the old key opens for a device that can read the older generation, and is put again by it.
      final laptop = device();
      final outcome = await laptop.sync(key: turned, generation: 2, olderKey: (generation) async => generation == 1 ? orgKey : null);
      expect(outcome.unsent, 0);
      expect(laptop.notes['n1']?.body, 'words');
      expect(bodyOf(await opened(turned, 'n1')), 'words');
      // A device with no way to the older generation cannot read it, and the pass says so without losing the note
      // elsewhere.
      service.teamNotes(orgId)['n1'] = before;
      final tablet = device();
      final unread = await tablet.sync(key: await freshKey(), generation: 2);
      expect(unread.unsent, 1);
      expect(tablet.notes.containsKey('n1'), isFalse);
    }, skip: skip);

    test('snapshots when the service says the log is as long as it keeps one, and posts on', () async {
      inForce(1);
      final phone = device();
      phone.put('n1', 'words');
      await phone.sync(generation: 1);
      // The log filled by another device, with updates this one has read: its next update is told to snapshot first.
      final have = service.teamUpdates(orgId, 'n1').length;
      await apiOf(service).call('POST', 'orgs/$orgId/notes/n1/updates', token: service.signedIn(), body: {
        'blobs': [for (var i = 0; i < updatesKept - have; i += 1) 'x$i'],
        'generation': 1,
      });
      final doc = (await phone.docs.doc('n1'))!;
      doc.seq = updatesKept;
      phone.write('n1', 'words and one more');
      final outcome = await phone.sync(generation: 1);
      expect(outcome.unsent, 0);
      // The snapshot carried the edit and cut the log to it: nothing is left to post after it.
      expect(service.teamUpdates(orgId, 'n1'), isEmpty);
      expect(doc.snapshotSeq, updatesKept);
      expect(bodyOf(await opened(orgKey, 'n1')), 'words and one more');
    }, skip: skip);
  });

  group('this port\'s own', () {
    test('the engine\'s hook runs a pass from what it is handed, keeps the channel\'s state where the engine keeps it, and re-seals when told', () async {
      service.orgs[orgId]!.generation = 1;
      final phone = device(), mac = device();
      Object? phoneKept, macKept;
      var drawn = 0;
      TeamPass pass(TeamDevice d, {required Object? Function() load, required void Function(Object?) save, SealKey? key, int generation = 1, bool reseal = false}) => TeamPass(
            token: service.signedIn(),
            accountId: fakeAccountId,
            org: OrgRow.fromJson({'id': orgId, 'name': 'Ghost', 'role': 'owner', 'state': 'member', 'members': 1, 'createdAt': 0})!,
            key: key ?? orgKey,
            generation: generation,
            olderKey: null,
            notes: d.local,
            files: d.files,
            api: apiOf(service),
            crypto: service.crypto,
            loadState: load,
            saveState: save,
            isTeamNote: d.filed.contains,
            file: d.filed.add,
            pulled: () => drawn += 1,
            reseal: reseal,
          );
      phone.put('n1', 'from the phone');
      final sent = await teamNotesPass(phone.docs)(pass(phone, load: () => phoneKept, save: (s) => phoneKept = s));
      expect(saidOutcome(sent), 'changed 0, sent 1, unsent 0, reason null');
      // What was kept is JSON a `Stored` writes, and reads back as the channel's state.
      final kept = TeamSyncState.fromJson(phoneKept);
      // The cursor is the pull's: this device's own row is passed over by its revision on the next one.
      expect(kept.cursor, 0);
      expect(kept.notes['n1']?.rev, 1);
      final arrived = await teamNotesPass(mac.docs)(pass(mac, load: () => macKept, save: (s) => macKept = s));
      expect(arrived.changed, 1);
      expect(drawn, 1);
      expect(mac.notes['n1']!.body, 'from the phone');
      // The turn, then the hook asked to re-seal: the row opens under the new key alone.
      final turned = await freshKey();
      service.orgs[orgId]!.generation = 2;
      final resealed = await teamNotesPass(phone.docs)(pass(phone, load: () => phoneKept, save: (s) => phoneKept = s, key: turned, generation: 2, reseal: true));
      expect(saidOutcome(resealed), 'changed 0, sent 1, unsent 0, reason null');
      expect(bodyOf(await opened(turned, 'n1')), 'from the phone');
      await expectLater(opened(orgKey, 'n1'), throwsA(anything));
    }, skip: skip);

    test('a canvas is passed over both ways: not published from here, not taken, and never taken for gone', () async {
      const canvas = '{"nodes":[{"id":"a","type":"text","x":0,"y":0,"width":200,"height":80,"text":"card"}],"edges":[]}';
      final phone = device();
      phone.put('c1', canvas);
      phone.put('n1', 'words');
      expect(saidOutcome(await phone.sync()), 'changed 0, sent 1, unsent 0, reason null');
      expect(service.teamNotes(orgId).keys, ['n1']);
      // A canvas the web published: its row is in the feed, and this device leaves it be.
      final web = device();
      final row = await service.crypto.seal(orgKey, {'v': 1, 'note': noteToJson(Note(id: 'c2', body: canvas, createdAt: 1, updatedAt: 1, path: 'Board.canvas')), 'state': toBase64Url(Uint8List.fromList([0, 0])), 'seq': 0}, 'org:$orgId:note:c2');
      await apiOf(service).call('PUT', 'orgs/$orgId/notes/c2', token: service.signedIn(), body: {'base': 0, 'blob': row});
      expect(saidOutcome(await phone.sync()), 'changed 0, sent 0, unsent 0, reason null');
      expect(phone.notes.keys.toList()..sort(), ['c1', 'n1']);
      expect(service.teamNotes(orgId)['c2']!.deleted, isFalse);
      expect(web.notes, isEmpty);
    }, skip: skip);

    test('a row is put with the note whole, and a row that says no phrases leaves the ones this device has', () async {
      final phone = device();
      const phrases = [Segment(text: 'hello', startMs: 0, endMs: 400)];
      phone.notes['n1'] = Note(id: 'n1', body: 'hello', createdAt: 1, updatedAt: 1, recordingMs: 400, segments: phrases, formatted: 'Hello.', formattedFor: 1);
      phone.filed.add('n1');
      await phone.sync();
      final written = noteFromJson((await opened(orgKey, 'n1'))['note'])!;
      expect(written.segments, hasLength(1));
      expect(written.formatted, 'Hello.');
      // The web's row carries the note as its list had it: no phrases. The words change; the phrases stay.
      final mac = device();
      await mac.sync();
      mac.notes['n1'] = Note(id: 'n1', body: 'hello there', createdAt: 1, updatedAt: 2, recordingMs: 400, formattedFor: 1);
      final doc = (await mac.docs.doc('n1'))!;
      await doc.reconcile('hello there');
      final bare = await service.crypto.seal(orgKey, {'v': 1, 'note': noteToJson(mac.notes['n1']!), 'state': toBase64Url(await doc.snapshot()), 'seq': 0}, 'org:$orgId:note:n1');
      await apiOf(service).call('PUT', 'orgs/$orgId/notes/n1', token: service.signedIn(), body: {'base': service.teamNotes(orgId)['n1']!.rev, 'blob': bare});
      await phone.sync();
      expect(phone.notes['n1']!.body, 'hello there');
      expect(phone.notes['n1']!.segments, hasLength(1));
      expect(phone.notes['n1']!.formatted, 'Hello.');
      expect(await phone.files.read(FileKind.image, 'none.png'), isNull);
    }, skip: skip);
  });
}
