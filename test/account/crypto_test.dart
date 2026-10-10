// lib/account/crypto.dart over the Rust core's real C functions, on the Mac (tool/build-native.sh host): the typed
// API, the interface the account's flows are written against (crypto_api.dart), and the wire, held here too to
// what the WEB code sealed (native/tests/fixtures/crypto_web.json, tool/crypto_vectors.mjs). What each command
// does is Rust's to test (native/src/crypto.rs); this holds the crossing: handles, bytes either way, errors, and
// that a long derivation does not keep the notes waiting.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/bytes.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/native/ghost_core.dart';

const _library = 'native/target/debug/libghost_core.dylib';
const _fast = 1000;
const _notOpened = 'That could not be opened: it was sealed with another key, or for something else, or it has been changed.';

Future<Object> _refused(Future<Object?> asked) async {
  try {
    await asked;
  } on Object catch (e) {
    return e;
  }
  fail('the core answered where it should have refused');
}

void main() {
  final built = File(_library).existsSync();
  final skip = built ? null : 'the Mac\'s core is not built: run tool/build-native.sh host (wanted $_library)';
  final web = (jsonDecode(File('native/tests/fixtures/crypto_web.json').readAsStringSync()) as Map).cast<String, Object?>();

  late Directory root;
  late GhostCore core;
  late CoreCrypto crypto;

  setUpAll(() async {
    if (!built) return;
    root = Directory(Directory.systemTemp.createTempSync('ghost-crypto-test-').resolveSymbolicLinksSync());
    final path = File(_library).absolute.path;
    core = await GhostCore.open(libraryPath: path);
    // The crypto asks nothing of the library, so it is tried before `init`; the notes are opened for the test of
    // the two lanes.
    crypto = await CoreCrypto.withLane(core, libraryPath: path);
  });

  tearDownAll(() async {
    if (!built) return;
    await crypto.close();
    await core.close();
    root.deleteSync(recursive: true);
  });

  test('a secret is two halves, the account key wraps under one and comes back only under the same', () async {
    final right = await crypto.derive('correct horse', passwordSalt('Matt'), iterations: _fast);
    final same = await crypto.derive('correct horse', passwordSalt('matt'), iterations: _fast);
    final wrong = await crypto.derive('wrong horse', passwordSalt('matt'), iterations: _fast);
    expect(right.login, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(same.login, right.login);
    expect(wrong.login, isNot(right.login));
    expect(right.wrapKey.extractable, isFalse);

    final key = await crypto.newAccountKey();
    expect(key.extractable, isTrue);
    final wrapped = await crypto.wrap(key, right.wrapKey);
    expect(wrapped, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    final back = await crypto.unwrap(wrapped, right.wrapKey);
    expect(back.extractable, isFalse);
    final sealed = await crypto.seal(key, {'words': 'hello'}, 'note:a');
    expect(await crypto.open(back, sealed, 'note:a'), {'words': 'hello'});
    final refused = await _refused(crypto.unwrap(wrapped, wrong.wrapKey));
    expect(refused, isA<CoreError>().having((e) => e.message, 'message', 'That password or recovery code does not open this account\'s key.'));
  }, skip: skip);

  test('a kept key seals and opens and is not wrapped; one unwrapped to be wrapped again is', () async {
    final key = await crypto.newAccountKey();
    final kept = await crypto.settle(key);
    expect(kept.extractable, isFalse);
    expect(identical(await crypto.settle(kept), kept), isTrue);
    expect(await crypto.open(kept, await crypto.seal(key, [1, 2, 3], 'prefs'), 'prefs'), [1, 2, 3]);
    final derived = await crypto.derive('x', passwordSalt('m'), iterations: _fast);
    expect(await _refused(crypto.wrap(kept, derived.wrapKey)), isA<CoreError>());
    final again = await crypto.unwrap(await crypto.wrap(key, derived.wrapKey), derived.wrapKey, extractable: true);
    expect(again.extractable, isTrue);
    expect(await crypto.wrap(again, derived.wrapKey), isNotEmpty);
    // A key of another kind is refused here, before the core is asked.
    expect(() => crypto.seal(derived.wrapKey as SealKey, 1, 'prefs'), throwsArgumentError);
  }, skip: skip);

  test('a sealed blob opens only under its own key and context, is never the same twice, and is refused when changed', () async {
    final key = await crypto.newAccountKey(), other = await crypto.newAccountKey();
    final blob = await crypto.seal(key, {'body': '# Weekend trip', 'at': 1759000000000, 'scale': 1.25, 'none': null}, 'note:one');
    expect(await crypto.open(key, blob, 'note:one'), {'body': '# Weekend trip', 'at': 1759000000000, 'scale': 1.25, 'none': null});
    expect(await _refused(crypto.open(other, blob, 'note:one')), isA<CoreError>().having((e) => e.message, 'message', _notOpened));
    expect(await _refused(crypto.open(key, blob, 'note:two')), isA<CoreError>());
    expect(await crypto.seal(key, 'the deposit is four hundred', 'note:a'), isNot(await crypto.seal(key, 'the deposit is four hundred', 'note:a')));

    final audio = Uint8List.fromList([for (var i = 0; i < 60000; i += 1) (i * 37 + (i >> 8)) & 0xff]);
    final sealed = await crypto.sealBytes(key, audio, 'recording:a');
    expect(sealed.length, 1 + 12 + audio.length + 16);
    expect(sealed[0], 1);
    expect(await crypto.openBytes(key, sealed, 'recording:a'), audio);
    sealed[sealed.length - 1] ^= 1;
    expect(await _refused(crypto.openBytes(key, sealed, 'recording:a')), isA<CoreError>());
    sealed[sealed.length - 1] ^= 1;
    sealed[0] = 9;
    final newer = await _refused(crypto.openBytes(key, sealed, 'recording:a'));
    expect(newer, isA<CoreError>().having((e) => e.message, 'message', 'This was sealed by a newer Ghost.md. Update the app to read it.'));
  }, skip: skip);

  test('a recovery sheet\'s every code unwraps the account key, typed however it is typed', () async {
    for (var i = 0; i < 20; i += 1) {
      expect(crypto.newRecoveryCode(), matches(RegExp(r'^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$')));
    }
    final key = await crypto.newAccountKey();
    final sheet = await crypto.newSheet('Matt', key, iterations: _fast);
    expect(sheet.codes, hasLength(recoveryCodes));
    expect(sheet.codes.toSet(), hasLength(recoveryCodes));
    final typed = sheet.codes[3].toLowerCase().replaceAll('-', ' ');
    final derived = await crypto.derive(normaliseCode(typed), recoverySalt('matt'), iterations: _fast);
    expect(derived.login, sheet.entries[3].login);
    final back = await crypto.unwrap(sheet.entries[3].wrapped, derived.wrapKey);
    expect(await crypto.open(back, await crypto.seal(key, 'ok', 'prefs'), 'prefs'), 'ok');
  }, skip: skip);

  test('the device key signs, and is the same key back from the keystore', () async {
    final device = await crypto.newDeviceKey();
    final public = await crypto.publicKeyOf(device);
    expect(fromBase64Url(public), hasLength(32));
    final signature = await crypto.signNonce(device, 'nonce-1');
    expect(fromBase64Url(signature), hasLength(64));
    final kept = await crypto.keep(device);
    expect(kept.kind, 'device');
    final again = await crypto.restoreDeviceKey(KeptKey.fromJson(jsonDecode(jsonEncode(kept.toJson())))!.raw);
    expect(await crypto.publicKeyOf(again), public);
    expect(await crypto.signNonce(again, 'nonce-1'), signature, reason: 'Ed25519 signs the same nonce the same way');
  }, skip: skip);

  test('the pair travels as its private half, wraps an organization\'s key, and what a device keeps is not exported', () async {
    final account = await crypto.newAccountKey();
    final made = await crypto.newEncryptionKey();
    final pub = await crypto.encryptionPublicKeyOf(made);
    expect(fromBase64Url(pub), hasLength(65));
    // enc_key.dart's own lines: the private half as a JWK, sealed for the account's other devices.
    final sealed = await crypto.seal(account, await crypto.exportPrivateKey(made), 'encryption-key');
    final jwk = (await crypto.open(account, sealed, 'encryption-key') as Map).cast<String, Object?>();
    expect(jwk['kty'], 'EC');
    final elsewhere = await crypto.importEncryptionKey(jwk);
    expect(elsewhere.extractable, isFalse);
    expect(await crypto.encryptionPublicKeyOf(elsewhere), pub);
    final settled = await crypto.settleEncryptionKey(made);
    expect(settled.extractable, isFalse);
    expect(identical(await crypto.settleEncryptionKey(settled), settled), isTrue);
    expect(await _refused(crypto.exportPrivateKey(settled)), isA<CoreError>());

    final orgKey = crypto.randomBytes(32);
    final wrapped = await crypto.wrapFor(pub, orgKey, wrapContext('org-1', 1));
    expect(await crypto.unwrapWith(elsewhere, wrapped, wrapContext('org-1', 1)), orgKey);
    expect(await crypto.wrapFor(pub, orgKey, wrapContext('org-1', 1)), isNot(wrapped));
    final lee = await crypto.newEncryptionKey();
    expect(await _refused(crypto.unwrapWith(lee, wrapped, wrapContext('org-1', 1))), isA<CoreError>());
    expect(await _refused(crypto.unwrapWith(settled, wrapped, wrapContext('org-2', 1))), isA<CoreError>());
    expect(await _refused(crypto.unwrapWith(settled, wrapped, wrapContext('org-1', 2))), isA<CoreError>());
    final short = await _refused(crypto.unwrapWith(settled, 'AAAA', wrapContext('org-1', 1)));
    expect(short, isA<CoreError>().having((e) => e.message, 'message', 'That wrap could not be read.'));

    // The same key by either road: bytes taken up, or never leaving the core.
    final byBytes = await crypto.importSealKey(orgKey);
    final byHandle = await crypto.unwrapOrgKey(settled, wrapped, wrapContext('org-1', 1));
    expect(await crypto.open(byHandle, await crypto.seal(byBytes, {'v': 1}, 'org:org-1:note:n'), 'org:org-1:note:n'), {'v': 1});
    final team = await crypto.newOrgKey();
    final forSam = await crypto.wrapOrgKey(team, pub, wrapContext('org-1', 2));
    final sams = await crypto.unwrapOrgKey(elsewhere, forSam, wrapContext('org-1', 2));
    expect(await crypto.open(sams, await crypto.seal(team, 'ours', 'live:org:org-1:presence'), 'live:org:org-1:presence'), 'ours');
    expect(await _refused(crypto.keep(team)), isA<ArgumentError>(), reason: 'an organization key lives in memory only');
    // And in one step, the JWK never reaching Dart.
    final other = await crypto.openEncryptionKey(await crypto.sealEncryptionKey(lee, account), account);
    expect(await crypto.encryptionPublicKeyOf(other), await crypto.encryptionPublicKeyOf(lee));
    // The keystore's three.
    expect((await crypto.keep(settled)).kind, 'pair');
    expect(await crypto.encryptionPublicKeyOf(await crypto.restoreEncryptionKey((await crypto.keep(settled)).raw)), pub);
    final keptAccount = await crypto.restoreAccountKey((await crypto.keep(account)).raw);
    expect(await crypto.open(keptAccount, sealed, 'encryption-key'), jwk);
  }, skip: skip);

  test('random words, ids and digests', () async {
    expect(crypto.randomBytes(32), hasLength(32));
    expect(crypto.randomBytes(32), isNot(crypto.randomBytes(32)));
    expect(crypto.shortId(), matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
    expect(crypto.newShareKey(), matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    final abc = Uint8List.fromList(utf8.encode('abc'));
    expect(toHex(await crypto.sha256(abc)), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(await crypto.sha16(abc), 'ba7816bf8f01cfea414140de5dae2223');
  }, skip: skip);

  test('a file is sealed and opened where it lies, and never crosses', () async {
    final key = await crypto.newAccountKey();
    final wav = Uint8List.fromList([...utf8.encode('RIFF'), for (var i = 0; i < 2 * 1024 * 1024; i += 1) (i * 31) & 0xff]);
    File('${root.path}/n1.wav').writeAsBytesSync(wav);
    final sealed = await crypto.sealFile(key, 'file:r-n1', path: '${root.path}/n1.wav', out: '${root.path}/up/n1.sealed');
    expect(sealed, wav.length + 29);
    expect(File('${root.path}/up/n1.sealed').lengthSync(), sealed);
    expect(await crypto.openFile(key, 'file:r-n1', path: '${root.path}/up/n1.sealed', out: '${root.path}/n1.back'), wav.length);
    expect(File('${root.path}/n1.back').readAsBytesSync(), wav);
    expect(await crypto.digestFile('${root.path}/n1.back'), await crypto.sha16(wav));
    expect(await crypto.digestFile('${root.path}/nothing'), isNull);
    // The same bytes `sealBytes` makes: either opens the other's.
    expect(await crypto.openBytes(key, File('${root.path}/up/n1.sealed').readAsBytesSync().sublist(0), 'file:r-n1'), wav);
    final refused = await _refused(crypto.openFile(key, 'file:r-n2', path: '${root.path}/up/n1.sealed', out: '${root.path}/never'));
    expect(refused, isA<CoreError>().having((e) => e.message, 'message', _notOpened));
    expect(File('${root.path}/never').existsSync(), isFalse);
  }, skip: skip);

  test('a share is sealed under its link\'s key, with its pictures', () async {
    final key = crypto.newShareKey();
    final shared = {
      'v': 1,
      'kind': 'note',
      'title': 'Trip',
      'pages': [
        {'title': 'Trip', 'body': '![](image/a.png)'},
      ],
      'at': 1759000000000,
    };
    final plain = await crypto.openShare(key, await crypto.sealShare(key, shared));
    expect(plain.shared, shared);
    expect(plain.pictures, isEmpty);
    final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
    File('${root.path}/b.jpg').writeAsBytesSync([0xff, 0xd8, 0xff, 9]);
    final blob = await crypto.sealShare(key, shared, pictures: {'a.png': png}, pictureFiles: {'b.jpg': '${root.path}/b.jpg'});
    final opened = await crypto.openShare(key, blob);
    expect(opened.shared, shared);
    expect(opened.pictures.keys, ['a.png', 'b.jpg']);
    expect(opened.pictures['a.png'], png);
    expect(opened.pictures['b.jpg'], [0xff, 0xd8, 0xff, 9]);
    expect(await _refused(crypto.openShare(crypto.newShareKey(), blob)), isA<CoreError>());
  }, skip: skip);

  group('what the web code sealed (native/tests/fixtures/crypto_web.json)', () {
    late SealKey account;
    setUpAll(() async {
      if (!built) return;
      account = await crypto.restoreAccountKey(web['accountKey'] as String);
    });

    test('the salts and codes of crypto_api.dart are the web\'s', () {
      for (final one in (web['salts'] as List).cast<Map>()) {
        final salt = one['kind'] == 'recovery' ? recoverySalt(one['handle'] as String) : passwordSalt(one['handle'] as String);
        expect(salt, one['salt'], reason: '${one['handle']}');
      }
      for (final one in (web['codes'] as List).cast<Map>()) {
        expect(normaliseCode(one['typed'] as String), one['normalised']);
      }
    });

    test('a password derives to the web\'s login half and unwraps its account key, at the real 600,000 rounds', () async {
      final note = (web['sealed'] as List).first as Map;
      for (final one in (web['derive'] as List).cast<Map>().take(2)) {
        final timed = Stopwatch()..start();
        final derived = await crypto.derive(one['secret'] as String, one['salt'] as String);
        // ignore: avoid_print
        print('derive at $rounds rounds through the debug library: ${timed.elapsedMilliseconds} ms');
        expect(derived.login, one['login']);
        final key = await crypto.unwrap(one['wrapped'] as String, derived.wrapKey);
        expect(await crypto.open(key, note['blob'] as String, note['context'] as String), note['value']);
      }
      // Two derivations through the Mac's debug library: 1.9 s each on a quiet Mac, 5.2 s with its load at 25 (the
      // loop is the crate's own, unoptimised; only the hashing under it is built optimised, native/Cargo.toml), and
      // past the default thirty seconds between them at a load of 200, where this timed out. So it has the time a
      // debug build needs on a busy Mac; a quiet one is done in its four seconds all the same.
    }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));

    test('every blob opens in its context, by the key the web sealed it with', () async {
      final pair = (web['pair'] as Map).cast<String, Object?>(), org = (web['org'] as Map).cast<String, Object?>();
      final ours = await crypto.importEncryptionKey((await crypto.open(account, pair['sealed'] as String, 'encryption-key') as Map).cast<String, Object?>());
      expect(await crypto.encryptionPublicKeyOf(ours), pair['public']);
      final orgKey = await crypto.importSealKey(await crypto.unwrapWith(ours, org['wrapped'] as String, org['context'] as String));
      var opened = 0;
      for (final one in (web['sealed'] as List).cast<Map>()) {
        final key = one['key'] == 'org' ? orgKey : account;
        final context = one['context'] as String;
        if (one['as'] == 'value') {
          expect(await crypto.open(key, one['blob'] as String, context), one['value'], reason: context);
        } else {
          expect(toBase64Url(await crypto.openBytes(key, fromBase64Url(one['blob'] as String), context)), one['data'], reason: context);
        }
        expect(await _refused(crypto.openBytes(key, fromBase64Url(one['blob'] as String), '${context}x')), isA<CoreError>());
        opened += 1;
      }
      expect(opened, greaterThanOrEqualTo(15));
    }, skip: skip);

    test('the device key signs as the web\'s does, and its shares open', () async {
      final device = (web['device'] as Map).cast<String, Object?>();
      final key = await crypto.restoreDeviceKey(device['seed'] as String);
      expect(await crypto.publicKeyOf(key), device['public']);
      for (final one in (device['signed'] as List).cast<Map>()) {
        expect(await crypto.signNonce(key, one['nonce'] as String), one['signature']);
      }
      final share = (web['share'] as Map).cast<String, Object?>();
      final opened = await crypto.openShare(share['key'] as String, share['pictured'] as String);
      expect(opened.shared, share['words']);
      expect([for (final MapEntry(:key, :value) in opened.pictures.entries) [key, toBase64Url(value)]], share['pictures']);
      for (final one in (web['sha'] as List).cast<Map>()) {
        expect(await crypto.sha16(fromBase64Url(one['data'] as String)), one['sha']);
      }
    }, skip: skip);
  });

  test('a derivation at the real rounds does not keep the notes waiting', () async {
    await core.init(dataDir: '${root.path}/data', cacheDir: '${root.path}/cache');
    await core.invoke('create_note', {'id': await core.newId(), 'body': '# Still here\n', 'source': 'editor'});
    var derived = false;
    // Four at once on the long lane: seconds of work, in a debug build.
    final deriving = Future.wait([for (var i = 0; i < 4; i += 1) crypto.derive('correct horse $i', passwordSalt('matt'))]).then((_) => derived = true);
    final answered = <int>[];
    final timed = Stopwatch()..start();
    for (var i = 0; i < 20; i += 1) {
      final asked = timed.elapsedMicroseconds;
      expect(await core.invoke('list_notes'), hasLength(1));
      expect(await crypto.seal(await crypto.newAccountKey(), 'quick', 'prefs'), isNotEmpty);
      answered.add(timed.elapsedMicroseconds - asked);
    }
    expect(derived, isFalse, reason: 'twenty reads and seals were answered while the derivations still ran');
    answered.sort();
    // ignore: avoid_print
    print('list_notes and a seal while four derivations run: median ${answered[10] / 1000} ms, slowest ${answered.last / 1000} ms');
    expect(answered.last, lessThan(500 * 1000));
    await deriving;

    // Asked on the one lane, a derivation is in the queue like anything else: the read waits for it.
    final oneLane = CoreCrypto(core.invoke);
    final order = <String>[];
    final slow = oneLane.derive('correct horse', passwordSalt('matt')).then((_) => order.add('derive'));
    final read = core.invoke('list_notes').then((_) => order.add('list'));
    await Future.wait([slow, read]);
    expect(order, ['derive', 'list']);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
