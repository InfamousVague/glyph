import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto_api.dart';

import '../core/make_note.dart';
import '../support/fake_service.dart';
import '../support/sync_device.dart';

/// The service in memory (test/support/fake_service.dart), asked the way its clients will ask it. The account's
/// routes are tried by account_test.dart and the notifications' by test/feed; these are the routes whose clients
/// are not ported yet - notes, settings, files, organizations, their keys, team notes and invite links - so the
/// sync engine and the organizations start from a service that has already answered once, in the web fake's own
/// words (`src/test/fakeService.ts`). Not a port of a web file: the web tries these through its clients' tests.
void main() {
  late FakeService service;
  late Api api;
  late String token;

  setUp(() async {
    service = await FakeService.start(seed: (handle: 'matt', password: 'correct horse'), peers: ['sam', 'Priya']);
    api = Api(base: 'http://service.test/api', fetcher: service.fetcher);
    token = service.signedIn();
  });

  Future<Object> refused(Future<Object?> attempt) async {
    try {
      await attempt;
      return 'no refusal';
    } on ApiError catch (failure) {
      return (failure.status, failure.message);
    }
  }

  Future<Map<String, Object?>> ask(String method, String path, [Object? body]) => api.callMap(method, path, token: token, body: body);
  Map<String, Object?> orgOf(Map<String, Object?> answer) => (answer['org'] as Map).cast<String, Object?>();

  group('a session', () {
    test('is asked for by every route but the ways in, in the service’s words', () async {
      expect(await refused(api.call('GET', 'notes')), (401, 'Sign in first.'));
      expect(await refused(api.call('GET', 'notes', token: 'tok-nope')), (401, 'Your session has ended. Sign in again.'));
      expect(await refused(ask('GET', 'nowhere')), (404, 'No route GET nowhere'));
      service.expireAllTokens();
      expect(await refused(ask('GET', 'notes')), (401, 'Your session has ended. Sign in again.'));
      expect(() => FakeService.start().then((empty) => empty.accountKey), throwsStateError);
    });
  });

  group('notes', () {
    test('are fed by revision, written against a base, and a refused write answers what won', () async {
      expect(await ask('GET', 'notes?since=0'), {'rev': 0, 'items': <Object?>[], 'more': false});
      expect(await ask('PUT', 'notes/n1', {'blob': 'one', 'base': 0}), {'rev': 1});
      final rev = await service.deviceWrites(makeNote('n2', body: '# Groceries'), extra: {'images': ['i-1']});
      expect(rev, 2);
      expect(await ask('PUT', 'notes/n1', {'blob': 'two', 'base': 1}), {'rev': 3});
      final fed = await ask('GET', 'notes?since=1');
      expect(fed['rev'], 3);
      expect([for (final item in fed['items'] as List) ((item as Map)['id'], item['rev'], item['deleted'])], [('n2', 2, false), ('n1', 3, false)]);
      // A write against a revision that has moved on: 409, with the row that stands.
      try {
        await ask('PUT', 'notes/n1', {'blob': 'stale', 'base': 1});
        fail('The stale write was taken.');
      } on ApiError catch (failure) {
        expect(failure.status, 409);
        expect(failure.body, {'id': 'n1', 'rev': 3, 'deleted': false, 'blob': 'two'});
      }
      expect(await ask('DELETE', 'notes/n1', {'base': 3}), {'rev': 4});
      expect((service.notes['n1']!.deleted, service.notes['n1']!.blob), (true, null));
      // What another device sealed opens as the payload the app seals, and a tombstone as nothing.
      final stored = (await service.stored('n2'))!;
      expect([stored['v'], (stored['note'] as Map)['body'], stored['images']], [1, '# Groceries', ['i-1']]);
      expect(await service.stored('n1'), isNull);
      expect(await service.stored('never'), isNull);
      // An id with a space in it is one note.
      await ask('PUT', 'notes/${Uri.encodeComponent('my note')}', {'blob': 'x', 'base': 0});
      expect(service.notes.containsKey('my note'), isTrue);
    });
  });

  group('settings', () {
    test('are one blob at a revision, written against the one before', () async {
      expect(await ask('GET', 'prefs'), {'rev': 0, 'blob': null});
      expect(await refused(ask('PUT', 'prefs', {'blob': 'x', 'base': 3})), (500, 'Those settings could not be stored.'));
      expect(await ask('PUT', 'prefs', {'blob': 'one', 'base': 0}), {'rev': 1});
      try {
        await ask('PUT', 'prefs', {'blob': 'two', 'base': 0});
        fail('The stale write was taken.');
      } on ApiError catch (failure) {
        expect([failure.status, failure.body], [409, {'rev': 1, 'blob': 'one'}]);
      }
      expect(await ask('PUT', 'prefs', {'blob': 'two', 'base': 1}), {'rev': 2});
      expect(service.prefs, (rev: 2, blob: 'two'));
    });
  });

  group('recordings and pictures', () {
    test('are bytes at a revision, asked for by their head, and share the account’s counter', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 250]);
      expect(await refused(api.callBytes('HEAD', 'recordings/r-1', token: token)), (404, 'The sync service answered 404.'));
      expect(await refused(api.callBytes('GET', 'recordings/r-1', token: token)), (404, 'No recording by that id.'));
      expect(await api.call('PUT', 'recordings/r-1?base=0', token: token, bytes: bytes), {'rev': 1});
      await ask('PUT', 'notes/n1', {'blob': 'one', 'base': 0});
      expect(await api.call('PUT', 'recordings/i-1', token: token, bytes: bytes), {'rev': 3});
      expect((await api.callBytes('HEAD', 'recordings/r-1', token: token)).rev, 1);
      final got = await api.callBytes('GET', 'recordings/r-1', token: token);
      expect([got.rev, got.bytes], [1, bytes]);
      expect(service.files['i-1']!.bytes, bytes);
      try {
        await api.call('PUT', 'recordings/r-1?base=0', token: token, bytes: bytes);
        fail('The stale write was taken.');
      } on ApiError catch (failure) {
        expect([failure.status, failure.body], [409, {'rev': 1}]);
      }
      // A service whose HEAD never arrives: no answer at all, which the pass reads as "send and find out".
      final deaf = await FakeService.start(seed: (handle: 'matt', password: 'correct horse'), head: false);
      final deafApi = Api(base: 'http://service.test/api', fetcher: deaf.fetcher);
      expect(await refused(deafApi.callBytes('HEAD', 'recordings/r-1', token: deaf.signedIn())), (0, 'The sync service could not be reached.'));
    });
  });

  group('an organization', () {
    test('is made, renamed, coloured and deleted by its owner, and lists as the account sees it', () async {
      expect(await refused(ask('POST', 'orgs', {'name': '   '})), (400, 'An organization’s name is 1 to 60 characters.'));
      expect(await refused(ask('POST', 'orgs', {'name': 'Ghost', 'hue': 'tartan'})), (400, 'That is not one of the hues.'));
      final org = orgOf(await ask('POST', 'orgs', {'name': ' Ghost ', 'hue': 'sea'}));
      final id = org['id'] as String;
      expect([org['name'], org['hue'], org['role'], org['state'], org['keys']], ['Ghost', 'sea', 'owner', 'member', {'generation': 0, 'mine': false, 'missing': 0, 'stale': false}]);
      expect([for (final m in org['members'] as List) ((m as Map)['handle'], m['role'], m['state'])], [('matt', 'owner', 'member')]);
      final listed = await ask('GET', 'orgs');
      expect(listed['colour'], isNull);
      expect([for (final row in listed['orgs'] as List) ((row as Map)['id'], row['members'])], [(id, 1)]);
      expect(orgOf(await ask('PUT', 'orgs/$id', {'name': 'Ghosts', 'hue': null}))['name'], 'Ghosts');
      expect(service.orgs[id]!.hue, isNull);
      // Colours: the account's own everywhere, and an override in one organization.
      expect(await ask('PUT', 'account/colour', {'hue': 'moss'}), {'colour': 'moss'});
      expect(orgOf(await ask('GET', 'orgs/$id'))['colour'], 'moss');
      expect(orgOf(await ask('PUT', 'orgs/$id/colour', {'hue': 'rose'}))['colour'], 'rose');
      expect(orgOf(await ask('PUT', 'orgs/$id/colour', {'hue': 'ink'}))['colour'], 'moss');
      expect(await refused(ask('PUT', 'account/colour', {'hue': 'tartan'})), (400, 'That hue is not one of the workspace hues.'));
      expect(await refused(ask('GET', 'orgs/nope')), (404, 'No such organization.'));
      expect(await ask('DELETE', 'orgs/$id'), {'deleted': true});
      expect(service.orgs, isEmpty);
    });

    test('invites by handle, refreshes a pending invitation, changes roles, and removes', () async {
      final id = orgOf(await ask('POST', 'orgs', {'name': 'Ghost'}))['id'] as String;
      expect(await refused(ask('POST', 'orgs/$id/members', {'handle': 'nobody'})), (404, 'No one has that handle.'));
      final invited = ((await ask('POST', 'orgs/$id/members', {'handle': 'SAM'}))['member'] as Map);
      expect((invited['handle'], invited['role'], invited['state'], invited['invitedBy']), ('sam', 'member', 'invited', 'matt'));
      await ask('POST', 'orgs/$id/members', {'handle': 'sam'});
      expect(service.orgs[id]!.rows, hasLength(2));
      expect(await refused(ask('PUT', 'orgs/$id/members/sam', {'role': 'admin'})), (409, 'They have not joined yet.'));
      // Sam joins (their own device's doing, which the fake has none of).
      service.orgs[id]!.rows['sam']!.state = 'member';
      expect(await refused(ask('POST', 'orgs/$id/members', {'handle': 'sam'})), (409, 'They are already a member.'));
      expect(await refused(ask('PUT', 'orgs/$id/members/sam', {'role': 'boss'})), (400, 'A role is owner, admin or member.'));
      expect(((await ask('PUT', 'orgs/$id/members/sam', {'role': 'admin'}))['member'] as Map)['role'], 'admin');
      expect(await refused(ask('DELETE', 'orgs/$id/members/matt')), (403, 'Hand the organization over first.'));
      expect(await refused(ask('PUT', 'orgs/$id/members/matt', {'role': 'member'})), (403, 'Hand the organization over first.'));
      expect(await ask('DELETE', 'orgs/$id/members/sam'), {'removed': true});
      expect(service.orgs[id]!.turns, 1);
      expect(await refused(ask('DELETE', 'orgs/$id/members/sam')), (404, 'No one by that handle is in this organization.'));
      // Handing it over: the owner becomes an admin, and can no longer delete it.
      await ask('POST', 'orgs/$id/members', {'handle': 'Priya'});
      service.orgs[id]!.rows['priya']!.state = 'member';
      await ask('PUT', 'orgs/$id/members/priya', {'role': 'owner'});
      expect(service.rowIn(id), (role: 'admin', state: 'member'));
      expect(await refused(ask('DELETE', 'orgs/$id')), (403, 'Only the owner can delete the organization.'));
      expect(await ask('DELETE', 'orgs/$id/members/matt'), {'removed': true});
      expect(service.rowIn(id), isNull);
    });

    test('a peer’s is joined by invitation or by link, and its invite links are the owner’s and admins’', () async {
      final theirs = service.invited('Barn', 'sam');
      expect(service.rowIn(theirs), (role: 'member', state: 'invited'));
      expect(await refused(ask('GET', 'orgs/$theirs')), (404, 'No such organization.'));
      expect(orgOf(await ask('POST', 'orgs/$theirs/invite', {'accept': true}))['state'], 'member');
      expect(await refused(ask('POST', 'orgs/$theirs/invite', {'accept': true})), (404, 'You were not invited.'));
      expect(await refused(ask('GET', 'orgs/$theirs/links')), (403, 'Only the owner or an admin can do that.'));
      expect(service.feed.values.single.state, 'accepted');

      final code = service.peerLink('Hall', by: 'Priya', maxUses: 1);
      final seen = await ask('GET', 'joins/$code');
      expect(((seen['org'] as Map)['name'], seen['by'], seen['member']), ('Hall', 'Priya', false));
      final joined = orgOf(await ask('POST', 'joins/$code'));
      expect((joined['role'], joined['state'], joined['invitedBy']), ('member', 'member', 'Priya'));
      // Used up.
      expect(await refused(ask('GET', 'joins/$code')), (404, 'That invite link has expired or was turned off.'));

      final mine = orgOf(await ask('POST', 'orgs', {'name': 'Ghost'}))['id'] as String;
      expect(await refused(ask('POST', 'orgs/$mine/links', {'expiresIn': 60})), (400, 'A link lasts an hour to thirty days, or until it is turned off.'));
      service.clock = () => 1000;
      final link = ((await ask('POST', 'orgs/$mine/links', {'expiresIn': 3600, 'maxUses': 5}))['link'] as Map);
      expect((link['expiresAt'], link['maxUses'], link['uses'], link['by']), (1000 + 3600000, 5, 0, 'matt'));
      expect((await ask('GET', 'orgs/$mine/links'))['links'], hasLength(1));
      service.clock = () => 1000 + 3600001;
      expect((await ask('GET', 'orgs/$mine/links'))['links'], isEmpty);
      service.clock = () => 2000;
      expect(await ask('DELETE', 'orgs/$mine/links/${link['id']}'), {'dropped': true});
      expect(await refused(ask('DELETE', 'orgs/$mine/links/${link['id']}')), (404, 'That invite link has expired or was turned off.'));
    });
  });

  group('an organization’s key', () {
    test('is made a generation at a time, wrapped per member, first wrap wins, and owes a turn when a member goes', () async {
      final crypto = service.crypto;
      final id = orgOf(await ask('POST', 'orgs', {'name': 'Ghost'}))['id'] as String;
      final mine = await crypto.newEncryptionKey();
      final pub = await crypto.encryptionPublicKeyOf(mine);
      expect(await refused(ask('GET', 'account/key')), (404, 'No key pair yet.'));
      await ask('PUT', 'account/key', {'pub': pub, 'sealed': 'sealed-private-half'});
      final sams = await crypto.newEncryptionKey();
      service.peerKey('sam', await crypto.encryptionPublicKeyOf(sams));
      await ask('POST', 'orgs/$id/members', {'handle': 'sam'});

      var keys = await ask('GET', 'orgs/$id/keys');
      expect((keys['generation'], keys['mine'], keys['stale']), (0, null, false));
      expect([for (final m in keys['missing'] as List) (m as Map)['handle']], ['matt', 'sam']);

      final orgKey = crypto.randomBytes(32);
      final wrapped = await crypto.wrapFor(pub, orgKey, wrapContext(id, 1));
      expect(await refused(ask('POST', 'orgs/$id/keys', {'generation': 2, 'make': true, 'wraps': <Object?>[]})), (409, 'That is not the generation in force.'));
      keys = await ask('POST', 'orgs/$id/keys', {
        'generation': 1,
        'make': true,
        'wraps': [
          {'handle': 'matt', 'wrapped': wrapped},
          {'handle': 'nobody', 'wrapped': 'ignored'},
        ],
      });
      expect((keys['generation'], keys['mine']), (1, wrapped));
      expect([for (final m in keys['missing'] as List) (m as Map)['handle']], ['sam']);
      expect(await crypto.unwrapWith(mine, keys['mine'] as String, wrapContext(id, 1)), orgKey);
      // A second wrap for the same member at the same generation does not replace the first.
      await ask('POST', 'orgs/$id/keys', {
        'generation': 1,
        'wraps': [
          {'handle': 'matt', 'wrapped': 'later'},
          {'handle': 'sam', 'wrapped': 'for-sam'},
        ],
      });
      expect(service.keysOf(id).generation, 1);
      expect(service.keysOf(id).wraps, {'matt': {1: wrapped}, 'sam': {1: 'for-sam'}});
      expect(((await ask('GET', 'orgs'))['orgs'] as List).single['keys'], {'generation': 1, 'mine': true, 'missing': 0, 'stale': false});
      expect(await refused(ask('GET', 'orgs/$id/keys?generation=0')), (400, 'That generation could not be read.'));
      expect((await ask('GET', 'orgs/$id/keys?generation=1'))['mine'], wrapped);
      // Sam joins and leaves: the key is stale until the next generation is made.
      service.orgs[id]!.rows['sam']!.state = 'member';
      await ask('DELETE', 'orgs/$id/members/sam');
      expect((await ask('GET', 'orgs/$id/keys'))['stale'], isTrue);
      await ask('POST', 'orgs/$id/keys', {'generation': 2, 'make': true, 'wraps': <Object?>[]});
      keys = await ask('GET', 'orgs/$id/keys');
      expect((keys['generation'], keys['mine'], keys['stale']), (2, null, false));
    });
  });

  group('team notes', () {
    test('are rows on the organization’s own counter with a log of updates each, cut by a snapshot', () async {
      final id = orgOf(await ask('POST', 'orgs', {'name': 'Ghost'}))['id'] as String;
      expect(await ask('GET', 'orgs/$id/notes?since=0'), {'rev': 0, 'items': <Object?>[], 'more': false});
      expect(await refused(ask('PUT', 'orgs/$id/notes/t1', {'blob': '', 'base': 0})), (400, 'That note is empty or too large to sync.'));
      expect(await refused(ask('POST', 'orgs/$id/notes/t1/updates', {'blobs': ['u1']})), (404, 'No such note.'));
      expect(await ask('PUT', 'orgs/$id/notes/t1', {'blob': 'snapshot-1', 'base': 0, 'generation': 0}), {'rev': 1});
      // The account's own counter did not move.
      expect((await ask('GET', 'notes?since=0'))['rev'], 0);
      expect(await ask('POST', 'orgs/$id/notes/t1/updates', {'blobs': ['u1', 'u2']}), {'seq': 2});
      expect(await ask('POST', 'orgs/$id/notes/t1/updates', {'blobs': ['u3'], 'generation': 0}), {'seq': 3});
      expect(await refused(ask('POST', 'orgs/$id/notes/t1/updates', {'blobs': <Object?>[]})), (400, 'Those updates could not be read.'));
      final log = await ask('GET', 'orgs/$id/notes/t1/updates?since=1');
      expect(log['seq'], 3);
      expect([for (final u in log['items'] as List) [(u as Map)['seq'], u['blob'], u['by']]], [[2, 'u2', 'matt'], [3, 'u3', 'matt']]);
      expect(await ask('GET', 'orgs/$id/heads'), {'heads': {'t1': 3}});
      // Another generation's write is refused with the one in force.
      try {
        await ask('PUT', 'orgs/$id/notes/t1', {'blob': 'x', 'base': 1, 'generation': 4});
        fail('A write under another generation was taken.');
      } on ApiError catch (failure) {
        expect([failure.status, failure.body], [409, {'error': 'That is not the generation in force.', 'generation': 0}]);
      }
      // A snapshot up to seq 2 cuts the log to what came after, and the head stays.
      expect(await ask('PUT', 'orgs/$id/notes/t1', {'blob': 'snapshot-2', 'base': 1, 'upTo': 2}), {'rev': 2});
      expect([for (final u in service.teamUpdates(id, 't1')) u.seq], [3]);
      expect((service.teamNotes(id)['t1']!.blob, service.teamNotes(id)['t1']!.by), ('snapshot-2', 'matt'));
      expect((await ask('GET', 'orgs/$id/notes/t1/updates?since=3'))['seq'], 3);
      // A log past what the service keeps asks for a snapshot first.
      try {
        await ask('POST', 'orgs/$id/notes/t1/updates', {'blobs': List.filled(updatesKept, 'u')});
        fail('A log past its length was taken.');
      } on ApiError catch (failure) {
        expect([failure.status, failure.body], [409, {'error': 'snapshot', 'seq': 3}]);
      }
      // Its files, on the same counter; and a deletion, which takes the log with it.
      expect(await api.call('PUT', 'orgs/$id/files/i-1?base=0&generation=0', token: token, bytes: Uint8List.fromList([9])), {'rev': 3});
      expect((await api.callBytes('GET', 'orgs/$id/files/i-1', token: token)).rev, 3);
      expect(service.teamFiles(id)['i-1']!.bytes, [9]);
      expect(await refused(api.call('PUT', 'orgs/$id/files/i-1?base=0&generation=7', token: token, bytes: Uint8List(1))), (409, 'That is not the generation in force.'));
      expect(await ask('DELETE', 'orgs/$id/notes/t1', {'base': 2}), {'rev': 4});
      expect(service.teamUpdates(id, 't1'), isEmpty);
      expect(await ask('GET', 'orgs/$id/heads'), {'heads': <String, Object?>{}});
    });
  });

  group('a service from before organizations', () {
    test('answers every one of their routes "no such route", and the rest as ever', () async {
      final old = await FakeService.start(seed: (handle: 'matt', password: 'correct horse'), teams: false);
      final oldApi = Api(base: 'http://service.test/api', fetcher: old.fetcher);
      final oldToken = old.signedIn();
      for (final (method, path) in [('GET', 'orgs'), ('POST', 'orgs'), ('GET', 'notifications?since=0'), ('GET', 'joins/abc'), ('GET', 'account/key'), ('PUT', 'account/colour')]) {
        await expectLater(oldApi.call(method, path, token: oldToken, body: method == 'GET' ? null : <String, Object?>{}), throwsA(isA<ApiError>().having(notYet, 'not yet', isTrue)), reason: '$method $path');
      }
      expect(await oldApi.callMap('GET', 'notes?since=0', token: oldToken), containsPair('rev', 0));
    });
  });

  group('a device in a test', () {
    test('holds what the pass is given, behind the stores’ own names, and stands between itself and the service', () async {
      final asked = <String>[];
      final device = SyncDevice<Map<String, Object?>>(
        service,
        state: const {'cursor': 0},
        pictures: {'i-1': Uint8List.fromList([1])},
        fetcher: (request) {
          asked.add(request.method);
          return service.fetcher(request);
        },
      );
      await device.local.apply(makeNote('n1'));
      expect([for (final note in await device.local.list()) note.id], ['n1']);
      expect((await device.local.get('n1'))?.body, '# n1');
      await device.local.remove('n1');
      expect(device.notes, isEmpty);
      expect(await device.files.read(FileKind.image, 'i-1'), [1]);
      await device.files.write(FileKind.recording, 'n1', Uint8List.fromList([2]));
      expect(device.tapes['n1'], [2]);
      device.keepVersions('n1', 'a versions file ✓');
      expect(device.files.owed(), ['n1']);
      // A versions file crosses to the pass as bytes, UTF-8.
      expect(utf8.decode((await device.files.read(FileKind.versions, 'n1'))!), 'a versions file ✓');
      expect(await device.files.read(FileKind.versions, 'never'), isNull);
      await device.files.write(FileKind.versions, 'n2', (await device.files.read(FileKind.versions, 'n1'))!);
      expect(device.versions['n2'], 'a versions file ✓');
      device.files.settled('n1');
      expect(device.owed, isEmpty);
      expect(device.files.digest, isNull);
      // One pass, as an engine would run it: with the device's token, key, clock and state.
      device.clock = 5000;
      final rev = await device.sync((d) async {
        final blob = await d.crypto.seal(d.key, {'v': 1, 'note': {'id': 'n9', 'body': 'x'}}, 'note:n9');
        final answer = await d.api.callMap('PUT', 'notes/n9', token: d.token, body: {'blob': blob, 'base': 0});
        d.save({'cursor': answer['rev'], 'at': d.now()});
        return answer['rev'];
      });
      expect(rev, 1);
      expect(device.state, {'cursor': 1, 'at': 5000});
      expect(asked, ['PUT']);
      expect(((await service.stored('n9'))!['note'] as Map)['body'], 'x');
    });
  });
}
