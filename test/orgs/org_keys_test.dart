// The organization key on a device (lib/orgs/org_keys.dart; docs/SHARED.md, S2). A port of
// `src/app/core/orgs/orgKeys.test.ts`, case for case: made by the first member device to find none, wrapped for
// everyone who can be wrapped for, read by the others, filled for whoever joins, and settled by the service when
// two devices make one at once.
//
// The crypto is the tests' (test/support/fake_crypto.dart): what is proved is who is wrapped for, at which
// generation, under which context, and what a device holds - not the wire, which is the Rust core's own vectors.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/account/enc_key.dart';
import 'package:ghost_md/account/keystore.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/orgs/org_keys.dart';
import 'package:ghost_md/orgs/orgs.dart';

import '../feed/signed.dart';
import '../support/fake_service.dart';

late FakeService service;
late Orgs orgs;
late OrgKeys keys;
late AccountCrypto crypto;

CallContext call() => CallContext(token: service.signedIn());
Uint8List filled(int byte) => Uint8List(32)..fillRange(0, 32, byte);

Future<EncryptionKey> pairOf() async =>
    (await ensureEncryptionKey(EncryptionKeyContext(token: service.signedIn(), accountKey: service.accountKey, keys: MemoryKeyStore(), api: apiOf(service), crypto: crypto))).pair;

Future<List<OrgRow>> rows() async => (await orgs.listOrgs(ctx: call())).rows;

OrgKeysContext ctx(EncryptionKey pair, {List<OrgRow> list = const [], Uint8List Function()? randomKey, Api? api}) =>
    OrgKeysContext(token: service.signedIn(), pair: pair, list: list, randomKey: randomKey, api: api);

OrgRowKept member(String handle, [String role = 'member']) => OrgRowKept(handle: handle, role: role, state: 'member', since: 1, invitedBy: 'matt');

void main() {
  setUp(() async {
    service = await FakeService.start(seed: testAccount, peers: ['sam', 'lee']);
    crypto = service.crypto;
    final prefs = PreferencesStore()..startWithoutStorage();
    orgs = Orgs(account: SignedAccount(session: testSession), api: apiOf(service), workspaces: WorkspaceStore());
    keys = OrgKeys(crypto: crypto, api: apiOf(service));
    addTearDown(prefs.dispose);
  });

  group('the organization key', () {
    test('is made by the first member device, wrapped for itself, held, and skipped once the list says it is in hand', () async {
      final pair = await pairOf();
      final org = await orgs.createOrg('Ghost', hue: 'sea', ctx: call());
      expect(keys.orgKeyOf(org.id), isNull);
      final raw = filled(7);
      var list = await rows();
      await keys.syncOrgKeys(ctx(pair, list: list, randomKey: () => raw));
      expect(keys.orgKeyGeneration(org.id), 1);
      expect(keys.orgKeyOf(org.id), isNotNull);
      final stored = service.keysOf(org.id);
      expect(stored.generation, 1);
      expect(await crypto.unwrapWith(pair, stored.wraps['matt']![1]!, wrapContext(org.id, 1)), raw);
      // The list now says it is in hand: the next pass asks nothing.
      list = await rows();
      expect(list[0].keys, const KeyNeeds(generation: 1, mine: true));
      final before = service.calls.length;
      await keys.syncOrgKeys(ctx(pair, list: list));
      expect(service.calls.length, before);
    });

    test('wraps for a member who joins with a public key, and reads its own wrap on another device', () async {
      final pair = await pairOf();
      final org = await orgs.createOrg('Ghost', ctx: call());
      final raw = filled(9);
      await keys.syncOrgKeys(ctx(pair, list: await rows(), randomKey: () => raw));
      // sam joins (through the service's own rows) with a key pair of their own: missing, then wrapped for.
      final sam = await crypto.newEncryptionKey();
      service.peerKey('sam', await crypto.encryptionPublicKeyOf(sam));
      service.orgs[org.id]!.rows['sam'] = member('sam');
      final list = await rows();
      expect(list[0].keys, const KeyNeeds(generation: 1, mine: true, missing: 1));
      await keys.syncOrgKeys(ctx(pair, list: list));
      final stored = service.keysOf(org.id);
      expect(await crypto.unwrapWith(sam, stored.wraps['sam']![1]!, wrapContext(org.id, 1)), raw);
      // Another device of matt's, with the pair but no key held: reads the wrap rather than making a new generation.
      keys.forgetOrgKeys();
      await keys.syncOrgKeys(ctx(pair, list: await rows(), randomKey: () => filled(1)));
      expect(keys.orgKeyGeneration(org.id), 1);
      expect(service.keysOf(org.id).generation, 1);
    });

    test('adopts the generation another device made first, and waits when it has no wrap yet', () async {
      final pair = await pairOf();
      final org = await orgs.createOrg('Ghost', ctx: call());
      // sam's device made the first generation before this one posted: this one's post meets the generation in
      // force.
      final sam = await crypto.newEncryptionKey();
      service.peerKey('sam', await crypto.encryptionPublicKeyOf(sam));
      service.orgs[org.id]!.rows['sam'] = member('sam', 'admin');
      var raced = false;
      Future<FetchResponse> racing(FetchRequest request) async {
        if (!raced && request.url.path.endsWith('/keys') && request.method == 'POST') {
          // sam's post lands first, wrapping for sam alone.
          raced = true;
          final stored = service.orgs[org.id]!;
          stored.generation = 1;
          stored.wraps
            ..clear()
            ..['sam'] = {1: 'w-sam'};
        }
        return service.fetcher(request);
      }

      await keys.syncOrgKeys(ctx(pair, list: await rows(), api: apiOf(service, racing)));
      // No wrap for matt yet: nothing held, nothing made; sam's generation stands untouched.
      expect(keys.orgKeyOf(org.id), isNull);
      final stood = service.keysOf(org.id);
      expect(stood.generation, 1);
      expect(stood.wraps, {
        'sam': {1: 'w-sam'},
      });
      expect(keys.orgKeyGeneration(org.id), 0);
      // sam's device wraps for matt; the next pass reads it.
      final raw = filled(3);
      service.orgs[org.id]!.wraps['matt'] = {1: await crypto.wrapFor(await crypto.encryptionPublicKeyOf(pair), raw, wrapContext(org.id, 1))};
      await keys.syncOrgKeys(ctx(pair, list: await rows()));
      expect(keys.orgKeyGeneration(org.id), 1);
    });

    test('turns when a member goes: the next generation wrapped for those who remain, the one before kept for what is not re-sealed', () async {
      final pair = await pairOf();
      final org = await orgs.createOrg('Ghost', ctx: call());
      final sam = await crypto.newEncryptionKey();
      final lee = await crypto.newEncryptionKey();
      service.peerKey('sam', await crypto.encryptionPublicKeyOf(sam));
      service.peerKey('lee', await crypto.encryptionPublicKeyOf(lee));
      for (final handle in ['sam', 'lee']) {
        service.orgs[org.id]!.rows[handle] = member(handle);
      }
      await keys.syncOrgKeys(ctx(pair, list: await rows(), randomKey: () => filled(1)));
      final before = keys.orgKeyOf(org.id)!;
      expect(keys.turnDue((await rows())[0]), isFalse);
      // lee leaves: the list says the key owes a turn, which this device, holding the generation in force, makes.
      await apiOf(service).call('DELETE', 'orgs/${org.id}/members/lee', token: service.signedIn());
      final list = await rows();
      expect(list[0].keys, const KeyNeeds(generation: 1, mine: true, stale: true));
      expect(keys.turnDue(list[0]), isTrue);
      final second = filled(2);
      final members = (await orgs.fetchOrg(org.id, ctx: call())).members;
      expect(await keys.turnOrgKey(org.id, members, token: service.signedIn(), randomKey: () => second), 2);
      expect(keys.orgKeyGeneration(org.id), 2);
      expect(identical(keys.orgKeyOf(org.id), before), isFalse);
      final stored = service.keysOf(org.id);
      expect(stored.generation, 2);
      expect(await crypto.unwrapWith(pair, stored.wraps['matt']![2]!, wrapContext(org.id, 2)), second);
      expect(await crypto.unwrapWith(sam, stored.wraps['sam']![2]!, wrapContext(org.id, 2)), second);
      expect(stored.wraps['lee']?[2], isNull);
      expect((await rows())[0].keys, const KeyNeeds(generation: 2, mine: true));
      // The generation before is still in hand, and read back from this account's wrap on a device that lacks it.
      expect(await keys.orgKeyAt(ctx(pair), org.id, 1), same(before));
      expect(await keys.orgKeyAt(ctx(pair), org.id, 2), same(keys.orgKeyOf(org.id)));
      expect(await keys.orgKeyAt(ctx(pair), org.id, 3), isNull);
      keys.forgetOrgKeys();
      await keys.syncOrgKeys(ctx(pair, list: await rows()));
      expect(keys.orgKeyGeneration(org.id), 2);
      final older = await keys.orgKeyAt(ctx(pair), org.id, 1);
      expect(older, isNotNull);
      expect(await keys.orgKeyAt(ctx(pair), org.id, 1), same(older));
      // A turn another device made first: this one's goes nowhere, and the next pass reads the new wrap.
      service.orgs[org.id]!.turns = 1;
      service.orgs[org.id]!.generation = 3;
      expect(await keys.turnOrgKey(org.id, members, token: service.signedIn(), randomKey: () => filled(3)), isNull);
      expect(keys.orgKeyGeneration(org.id), 2);
    });

    test('knows from the list alone when there is key work for this device, so a joiner is wrapped for at once', () {
      OrgRow row(KeyNeeds needs, [String state = 'member']) => OrgRow(id: 'o', name: 'Ghost', role: 'member', state: state, members: 2, createdAt: 1, keys: needs);
      // None made: someone makes it. A wrap waiting and not read: read it. Held, with a member lacking one: wrap for
      // them.
      expect(keyWork(row(const KeyNeeds(missing: 1)), held: false), isTrue);
      expect(keyWork(row(const KeyNeeds(generation: 1, mine: true)), held: false), isTrue);
      expect(keyWork(row(const KeyNeeds(generation: 1, mine: true, missing: 1)), held: true), isTrue);
      // Not in hand and no wrap yet: still work, since this account's key pair must be registered before anyone can
      // wrap for it.
      expect(keyWork(row(const KeyNeeds(generation: 1, missing: 1)), held: false), isTrue);
      // Nothing to do: in hand with nobody missing; an invitation.
      expect(keyWork(row(const KeyNeeds(generation: 1, mine: true)), held: true), isFalse);
      expect(keyWork(row(const KeyNeeds(missing: 1), 'invited'), held: false), isFalse);
    });

    test('drops the key of an organization the account has left', () async {
      final pair = await pairOf();
      final org = await orgs.createOrg('Ghost', ctx: call());
      await keys.syncOrgKeys(ctx(pair, list: await rows()));
      expect(keys.orgKeyOf(org.id), isNotNull);
      await keys.syncOrgKeys(ctx(pair));
      expect(keys.orgKeyOf(org.id), isNull);
    });

    test('is quiet against a service without the routes yet, and tells whoever waits when a key is held or forgotten', () async {
      final pair = await pairOf();
      final org = await orgs.createOrg('Ghost', ctx: call());
      final older = await FakeService.start(seed: testAccount, teams: false);
      await keys.syncOrgKeys(OrgKeysContext(token: older.signedIn(), pair: pair, list: await rows(), api: apiOf(older)));
      expect(keys.orgKeyOf(org.id), isNull);
      var told = 0;
      keys.addListener(() => told += 1);
      await keys.syncOrgKeys(ctx(pair, list: await rows()));
      expect(told, 1);
      keys.forgetOrgKeys();
      expect(told, 2);
      expect(keys.orgKeyOf(org.id), isNull);
    });
  });
}
