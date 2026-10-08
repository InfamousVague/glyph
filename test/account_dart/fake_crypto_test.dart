import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/bytes.dart';
import 'package:ghost_md/core/ids.dart';

import '../support/fake_crypto.dart';

/// The tests' crypto (test/support/fake_crypto.dart) held to what its header promises: self-consistent, reversible,
/// failing where the real one fails, and shaped like the wire. It is NOT cryptography, and nothing here says it is;
/// the real one (the Rust core's) is held to the web's own vectors by its own tests. With it, the spelling the wire
/// is written in (lib/core/bytes.dart) and the ids (lib/core/ids.dart).
void main() {
  final crypto = FakeCrypto();

  group('bytes as text', () {
    test('are base64, hex and URL-safe base64 as the page writes them', () {
      final bytes = Uint8List.fromList([0, 1, 250, 251, 252, 253, 254, 255]);
      expect(toBase64(bytes), 'AAH6+/z9/v8=');
      expect(toHex(bytes), '0001fafbfcfdfeff');
      expect(toBase64Url(bytes), 'AAH6-_z9_v8');
      expect(fromBase64Url('AAH6-_z9_v8'), bytes);
      expect(fromBase64Url('AAH6+/z9/v8='), bytes);
      expect(fromBase64Url(''), isEmpty);
      for (var length = 0; length < 40; length += 1) {
        final some = crypto.randomBytes(length);
        expect(fromBase64Url(toBase64Url(some)), some);
        expect(toBase64Url(some), isNot(contains('=')));
      }
      expect(() => fromBase64Url('not base64!'), throwsFormatException);
      expect(() => fromBase64Url('A'), throwsFormatException);
    });
  });

  group('ids', () {
    test('are a version 4 UUID, and a short id of 22 base64url characters', () {
      final id = randomId();
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(randomId('i'), isNot(id));
      final short = shortId();
      expect(short, hasLength(shortIdLength));
      expect(isShortId(short), isTrue);
      expect(isShortId(crypto.shortId()), isTrue);
      expect(isShortId('too-short'), isFalse);
      expect(isShortId('${short.substring(1)}='), isFalse);
      expect({for (var i = 0; i < 50; i += 1) shortId()}, hasLength(50));
    });
  });

  group('the words both implementations salt with', () {
    test('are the web’s', () {
      expect(passwordSalt('  Matt '), 'glyph/v1/matt');
      expect(recoverySalt('Matt'), 'glyph/v1/recovery/matt');
      expect(normaliseCode('abcd-efgh 2345'), 'ABCDEFGH2345');
      expect(wrapContext('o1', 3), 'org-key:o1:3');
      expect(rounds, 600000);
    });
  });

  group('a secret', () {
    test('splits the same way every time, and differently for another secret, salt or round count', () async {
      final a = await crypto.derive('correct horse', passwordSalt('matt'), iterations: fastRounds);
      final again = await FakeCrypto().derive('correct horse', passwordSalt('Matt'), iterations: fastRounds);
      expect(a.login, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(again.login, a.login);
      for (final other in [
        await crypto.derive('wrong horse', passwordSalt('matt'), iterations: fastRounds),
        await crypto.derive('correct horse', passwordSalt('sam'), iterations: fastRounds),
        await crypto.derive('correct horse', passwordSalt('matt'), iterations: fastRounds + 1),
        await crypto.derive('correct horse', recoverySalt('matt'), iterations: fastRounds),
      ]) {
        expect(other.login, isNot(a.login));
      }
      // The same secret's wrap key opens what it wrapped, from either derivation.
      final key = await crypto.newAccountKey();
      final sealed = await crypto.seal(key, 'x', 'c');
      expect(await crypto.open(await crypto.unwrap(await crypto.wrap(key, a.wrapKey), again.wrapKey), sealed, 'c'), 'x');
    });
  });

  group('the account key', () {
    test('is wrapped and unwrapped, refused under another secret, and only wrapped while extractable', () async {
      final key = await crypto.newAccountKey();
      expect(key.extractable, isTrue);
      final right = (await crypto.derive('correct horse', 's', iterations: fastRounds)).wrapKey;
      final wrong = (await crypto.derive('wrong horse', 's', iterations: fastRounds)).wrapKey;
      final wrapped = await crypto.wrap(key, right);
      // iv(12) ‖ the 32-byte key ‖ a 16-byte tag, as the real wrap is.
      expect(fromBase64Url(wrapped), hasLength(60));
      expect(await crypto.wrap(key, right), isNot(wrapped));
      final back = await crypto.unwrap(wrapped, right);
      expect(back.extractable, isFalse);
      expect((await crypto.unwrap(wrapped, right, extractable: true)).extractable, isTrue);
      await expectLater(crypto.unwrap(wrapped, wrong), throwsA(anything));
      await expectLater(crypto.wrap(back, right), throwsA(anything));
      final settled = await crypto.settle(key);
      expect(settled.extractable, isFalse);
      expect(await crypto.settle(settled), same(settled));
      // What one sealed, the others open: they are the same key.
      final blob = await crypto.seal(key, {'a': 1}, 'prefs');
      expect(await crypto.open(back, blob, 'prefs'), {'a': 1});
      expect(await crypto.open(settled, blob, 'prefs'), {'a': 1});
    });
  });

  group('a sealed blob', () {
    test('opens under its key and context, and under nothing else', () async {
      final key = await crypto.importSealKey(crypto.randomBytes(32));
      final other = await crypto.importSealKey(crypto.randomBytes(32));
      final value = {'v': 1, 'note': {'id': 'n1', 'body': '# Groceries\n- “milk” 🥛'}};
      final blob = await crypto.seal(key, value, 'note:n1');
      expect(blob, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(await crypto.open(key, blob, 'note:n1'), value);
      expect(await crypto.seal(key, value, 'note:n1'), isNot(blob));
      await expectLater(crypto.open(key, blob, 'note:n2'), throwsA(anything));
      await expectLater(crypto.open(other, blob, 'note:n1'), throwsA(anything));
      await expectLater(crypto.open(key, 'not-a-seal', 'note:n1'), throwsA(anything));
      await expectLater(crypto.open(key, '', 'note:n1'), throwsA(anything));
      // The service's own check: 1 ‖ iv(12) ‖ the bytes ‖ a 16-byte tag.
      final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final sealed = await crypto.sealBytes(key, bytes, 'file:r-1');
      expect(sealed, hasLength(1 + 12 + 1000 + 16));
      expect(sealed[0], 1);
      expect(await crypto.openBytes(key, sealed, 'file:r-1'), bytes);
      expect(await crypto.openBytes(key, await crypto.sealBytes(key, Uint8List(0), 'file:r-1'), 'file:r-1'), isEmpty);
      for (final at in [1, 13, 500, sealed.length - 1]) {
        final tampered = Uint8List.fromList(sealed)..[at] ^= 1;
        await expectLater(crypto.openBytes(key, tampered, 'file:r-1'), throwsA(anything), reason: 'byte $at');
      }
      final newer = Uint8List.fromList(sealed)..[0] = 2;
      await expectLater(crypto.openBytes(key, newer, 'file:r-1'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('newer Ghost.md'))));
      await expectLater(crypto.importSealKey(Uint8List(16)), throwsA(anything));
    });
  });

  group('recovery codes', () {
    test('are XXXX-XXXX-XXXX in the alphabet with no 0, O, 1 or I, eight to a sheet, each opening the key', () async {
      final key = await crypto.newAccountKey();
      final sheet = await crypto.newSheet('Matt', key, iterations: fastRounds);
      expect(sheet.codes, hasLength(recoveryCodes));
      expect(sheet.entries, hasLength(recoveryCodes));
      expect(sheet.codes.toSet(), hasLength(8));
      final blob = await crypto.seal(key, 'kept', 'prefs');
      for (final (i, code) in sheet.codes.indexed) {
        expect(code, matches(RegExp(r'^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$')));
        // As a person types it off the sheet.
        final derived = await crypto.derive(normaliseCode(code.toLowerCase().replaceAll('-', ' ')), recoverySalt('matt'), iterations: fastRounds);
        expect(derived.login, sheet.entries[i].login);
        expect(await crypto.open(await crypto.unwrap(sheet.entries[i].wrapped, derived.wrapKey), blob, 'prefs'), 'kept');
      }
      expect(sheet.entries.first.toJson().keys, ['login', 'wrapped']);
    });
  });

  group('the device key', () {
    test('signs a nonce its own public key verifies, and no other nonce or key does', () async {
      final device = await crypto.newDeviceKey();
      final other = await crypto.newDeviceKey();
      expect(device.extractable, isFalse);
      final public = await crypto.publicKeyOf(device);
      expect(fromBase64Url(public), hasLength(32));
      final signature = await crypto.signNonce(device, 'nonce-1');
      expect(fromBase64Url(signature), hasLength(64));
      expect(await crypto.verifyNonce(public, 'nonce-1', signature), isTrue);
      expect(await crypto.verifyNonce(public, 'nonce-2', signature), isFalse);
      expect(await crypto.verifyNonce(await crypto.publicKeyOf(other), 'nonce-1', signature), isFalse);
      expect(await crypto.verifyNonce(public, 'nonce-1', 'rubbish!'), isFalse);
      expect(await crypto.verifyNonce(public, 'nonce-1', ''), isFalse);
    });
  });

  group('the encryption pair', () {
    test('travels as a JSON Web Key, settles non-extractable, and opens only what was wrapped for it there', () async {
      final made = await crypto.newEncryptionKey();
      expect(made.extractable, isTrue);
      final pub = await crypto.encryptionPublicKeyOf(made);
      final point = fromBase64Url(pub);
      expect(point, hasLength(65));
      expect(point[0], 4);
      final jwk = await crypto.exportPrivateKey(made);
      expect(jwk, containsPair('kty', 'EC'));
      expect(jwk, containsPair('crv', 'P-256'));
      // It goes through JSON on its way to the other device.
      final elsewhere = await crypto.importEncryptionKey((jsonDecode(jsonEncode(jwk)) as Map).cast<String, Object?>());
      expect(elsewhere.extractable, isFalse);
      expect(await crypto.encryptionPublicKeyOf(elsewhere), pub);
      await expectLater(crypto.exportPrivateKey(elsewhere), throwsA(anything));
      final settled = await crypto.settleEncryptionKey(made);
      expect(settled.extractable, isFalse);
      expect(await crypto.settleEncryptionKey(settled), same(settled));

      final orgKey = crypto.randomBytes(32);
      final wrapped = await crypto.wrapFor(pub, orgKey, wrapContext('o1', 1));
      // point(65) ‖ iv(12) ‖ the 32-byte key ‖ a 16-byte tag.
      expect(fromBase64Url(wrapped), hasLength(65 + 12 + 32 + 16));
      expect(await crypto.unwrapWith(elsewhere, wrapped, wrapContext('o1', 1)), orgKey);
      await expectLater(crypto.unwrapWith(elsewhere, wrapped, wrapContext('o1', 2)), throwsA(anything));
      await expectLater(crypto.unwrapWith(elsewhere, wrapped, wrapContext('o2', 1)), throwsA(anything));
      await expectLater(crypto.unwrapWith(await crypto.newEncryptionKey(), wrapped, wrapContext('o1', 1)), throwsA(anything));
      await expectLater(crypto.unwrapWith(elsewhere, 'c2hvcnQ', wrapContext('o1', 1)), throwsA(anything));
      await expectLater(crypto.wrapFor('c2hvcnQ', orgKey, wrapContext('o1', 1)), throwsA(anything));
    });
  });

  group('the one real thing', () {
    test('is SHA-256, by the standard’s own vectors', () async {
      Future<String> hex(String text) async => toHex(await crypto.sha256(Uint8List.fromList(utf8.encode(text))));
      expect(await hex(''), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(await hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(await hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'), '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
      expect(await hex('a' * 1000000), 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
    });
  });
}
