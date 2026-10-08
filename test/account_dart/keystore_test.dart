import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/keystore.dart';
import 'package:ghost_md/account/session.dart';
import 'package:ghost_md/core/stored.dart';

import '../support/fake_crypto.dart';

/// What makes a device a signed-in one (lib/account/keystore.dart): the session, read back only when it is whole,
/// and the keys. The web's `src/app/core/account/keystore.test.ts`, case for case, on the memory store - the one a
/// browser without IndexedDB gets, and the only one this stage builds.
///
/// What differs: the page's last case is `deviceKeys()` falling back to one memory store for the whole page; there
/// is no device default here to fall back from (whoever wires the app gives the store), so the last case is the
/// memory store keeping the session itself when it is given nowhere else to.
void main() {
  late MemoryStored kept;
  late MemoryKeyStore keys;
  setUp(() {
    kept = MemoryStored();
    keys = MemoryKeyStore(kept: kept);
  });

  group('the session', () {
    test('is read back as it was written, and gone once signed out', () async {
      await keys.setSession(const Session(token: 't1', handle: 'matt', accountId: 7));
      expect(await keys.session(), const Session(token: 't1', handle: 'matt', accountId: 7));
      expect(jsonDecode(kept.getItem('glyph-account-session')!), {'token': 't1', 'handle': 'matt', 'accountId': 7});
      await keys.setSession(null);
      expect(await keys.session(), isNull);
      expect(kept.getItem('glyph-account-session'), isNull);
    });

    test('is no session at all when any part is missing or the wrong kind, and keeps nothing extra', () async {
      Future<Session?> stored(Object? value) {
        kept.setItem('glyph-account-session', jsonEncode(value));
        return keys.session();
      }

      expect(await stored({'handle': 'matt', 'accountId': 7}), isNull);
      expect(await stored({'token': 't1', 'accountId': 7}), isNull);
      expect(await stored({'token': 't1', 'handle': 'matt', 'accountId': '7'}), isNull);
      expect(await stored(null), isNull);
      final whole = await stored({'token': 't1', 'handle': 'matt', 'accountId': 7, 'password': 'never'});
      expect(whole, const Session(token: 't1', handle: 'matt', accountId: 7));
      expect(whole!.toJson().keys, ['token', 'handle', 'accountId']);
      kept.setItem('glyph-account-session', '{half');
      expect(await keys.session(), isNull);
    });
  });

  group('the keys', () {
    test('are held and forgotten by a memory store, each store its own', () async {
      final crypto = FakeCrypto();
      final one = MemoryKeyStore();
      final two = MemoryKeyStore();
      final key = await crypto.settle(await crypto.newAccountKey());
      final pair = await crypto.newDeviceKey();
      final encryption = await crypto.newEncryptionKey();
      await one.setAccountKey(key);
      await one.setDeviceKey(pair);
      await one.setEncryptionKey(encryption);
      expect(await one.accountKey(), same(key));
      expect(await one.deviceKey(), same(pair));
      expect(await one.encryptionKey(), same(encryption));
      expect(await two.accountKey(), isNull);
      await one.setAccountKey(null);
      expect(await one.accountKey(), isNull);
    });

    test('keep the session beside them when the store is given nowhere else to', () async {
      final alone = MemoryKeyStore();
      await alone.setSession(const Session(token: 't1', handle: 'matt', accountId: 7));
      expect(await alone.session(), const Session(token: 't1', handle: 'matt', accountId: 7));
      expect(await MemoryKeyStore().session(), isNull);
      await alone.setSession(null);
      expect(await alone.session(), isNull);
    });
  });
}
