import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/account/enc_key.dart';
import 'package:ghost_md/account/keystore.dart';

import '../support/fake_service.dart';

/// The account's encryption key pair (lib/account/enc_key.dart; docs/SHARED.md, S3): kept on the device, else read
/// from the service and unsealed with the account key, else made here and registered - and when two devices race,
/// the service's choice stands on both. The web's `src/app/core/account/encKey.test.ts`, case for case, over the
/// fake crypto.
void main() {
  late FakeService service;
  late SealKey accountKey;

  setUp(() async {
    service = await FakeService.start(seed: (handle: 'matt', password: 'correct horse'));
    accountKey = service.accountKey;
  });

  EncryptionKeyContext ctx(KeyStore keys, [Fetcher? fetcher]) =>
      EncryptionKeyContext(token: service.signedIn(), accountKey: accountKey, keys: keys, api: Api(base: 'http://service.test/api', fetcher: fetcher ?? service.fetcher), crypto: service.crypto);

  group('the encryption key pair', () {
    test('is made once, registered with the private half sealed, kept non-extractable, and read back by another device', () async {
      final crypto = service.crypto;
      final phone = MemoryKeyStore();
      final made = await ensureEncryptionKey(ctx(phone));
      expect(made.pair.extractable, isFalse);
      expect(await phone.encryptionKey(), same(made.pair));
      expect(service.encryption?.pub, made.pub);
      // The private half travels sealed under the account key: the service holds ciphertext it cannot read.
      final jwk = await crypto.open(accountKey, service.encryption!.sealed, 'encryption-key') as Map;
      expect(jwk['kty'], 'EC');
      expect(service.encryption!.sealed, isNot(contains(jwk['d'] as String)));
      // The same device again: the kept pair, and no call.
      final before = service.calls.length;
      expect((await ensureEncryptionKey(ctx(phone))).pair, same(made.pair));
      expect(service.calls.length, before);
      // Another device of the account: the pair from the service, able to open what was wrapped for the first.
      final mac = MemoryKeyStore();
      final read = await ensureEncryptionKey(ctx(mac));
      expect(read.pub, made.pub);
      expect(read.pair.extractable, isFalse);
      final orgKey = crypto.randomBytes(32);
      final wrapped = await crypto.wrapFor(made.pub, orgKey, wrapContext('org-1', 1));
      expect(await crypto.unwrapWith(read.pair, wrapped, wrapContext('org-1', 1)), orgKey);
    });

    test('adopts the pair the service kept when another device registered first', () async {
      // The other device's pair stands on the service before this one asks; this one made its own in between.
      final other = MemoryKeyStore();
      final theirs = await ensureEncryptionKey(ctx(other));
      final racing = MemoryKeyStore();
      var adopted = false;
      // A fetch that answers the first GET with 404 (as it was when this device looked) and lets the PUT meet the 409.
      Future<FetchResponse> raced(FetchRequest request) async {
        if (!adopted && request.url.path.endsWith('/account/key') && request.method == 'GET') {
          adopted = true;
          return FetchResponse.json(404, {'error': 'No key pair yet.'});
        }
        return service.fetcher(request);
      }

      final mine = await ensureEncryptionKey(ctx(racing, raced));
      expect(adopted, isTrue);
      expect(mine.pub, theirs.pub);
      expect(await service.crypto.encryptionPublicKeyOf((await racing.encryptionKey())!), theirs.pub);
      expect(service.calls.where((call) => call == 'PUT account/key'), hasLength(2));
    });

    test('is not made against a service without the route yet: the refusal is the service’s, and nothing is kept', () async {
      // Not a case of the web's: `no such route` is a 404 too, and must not read as "none registered, make one".
      final old = await FakeService.start(seed: (handle: 'matt', password: 'correct horse'), teams: false);
      final keys = MemoryKeyStore();
      final context = EncryptionKeyContext(token: old.signedIn(), accountKey: old.accountKey, keys: keys, api: Api(base: 'http://service.test/api', fetcher: old.fetcher), crypto: old.crypto);
      await expectLater(ensureEncryptionKey(context), throwsA(isA<ApiError>().having((e) => notYet(e), 'not yet', isTrue)));
      expect(await keys.encryptionKey(), isNull);
    });
  });
}
