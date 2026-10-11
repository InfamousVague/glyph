/// **NOT CRYPTOGRAPHY. FOR TESTS ONLY. NOTHING THIS FILE SEALS IS SECRET, AND NOTHING IT SIGNS IS PROOF.**
///
/// A stand-in for the Rust core's crypto (lib/account/crypto_api.dart, [AccountCrypto]) so the account's flows, the
/// service in memory and the notifications feed can be tried in plain Dart before the real one exists, and without
/// its build afterwards. It is SELF-CONSISTENT and REVERSIBLE and nothing more:
///
/// - what it wraps, it unwraps; what it seals, it opens; what it signs, [FakeCrypto.verifyNonce] verifies;
/// - it fails where the real one fails, so the refusals a client lives by are tried: a wrong password at `unwrap`, a
///   blob under another key, tampered with, or moved to another context at `open`, another member's wrap or another
///   context at `unwrapWith`, a key that is not extractable at `wrap` and `exportPrivateKey`;
/// - its outputs have the real ones' SHAPES AND LENGTHS (docs/STAGE7.md, "Crypto"): 64 hex characters of login
///   half, `iv12 ‖ box` for a wrap, `0x01 ‖ iv12 ‖ box` for a seal with the box 16 bytes longer than what went in,
///   a 32-byte device public key and a 64-byte signature, a 65-byte point starting `0x04`, `point65 ‖ iv12 ‖ box`
///   for an organization key's wrap, `XXXX-XXXX-XXXX` codes, 22-character short ids.
///
/// What it is NOT, so nobody mistakes a green test for a wire that works:
/// - **Not the wire.** Nothing here interoperates with the web app, the service or the real core: there is no
///   PBKDF2, no AES-GCM, no Ed25519, no P-256, no HKDF. A blob this sealed opens only here.
/// - **Not secret.** The "cipher" is a hash's output XORed over the bytes; the "signature" is a hash of the PUBLIC
///   key and the nonce, which anyone can make; the "agreement" behind an organization key's wrap is a hash of the
///   member's PUBLIC key and the wrap's own first bytes, so anyone holding the wrap can open it. `derive` does one
///   hash however many rounds it is asked for.
/// - **Not for a device.** It lives under `test/`, which no build of the app can import, and its constructor throws
///   outside `flutter test` besides.
///
/// The one honest function is [FakeCrypto.sha256], which is SHA-256 (FIPS 180-4), because a fingerprint that is not
/// the real one would make the tests of what compares fingerprints lie.
library;

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/bytes.dart';

/// PBKDF2 rounds for a test (`FAST`, src/test/fakeService.ts): the real 600 000 are for a person's password, not for
/// a test that makes ten accounts. The fake does one hash either way; the number still salts what it derives, so a
/// device and a service that disagree about it disagree about the key.
const int fastRounds = 1000;

class _Key {
  _Key(this.bytes, this.extractable);
  final Uint8List bytes;
  final bool extractable;
}

class _Wrap extends _Key implements WrapKey {
  _Wrap(Uint8List bytes) : super(bytes, false);
}

class _Seal extends _Key implements SealKey {
  _Seal(super.bytes, super.extractable);
}

class _Device extends _Key implements DeviceKey {
  _Device(Uint8List bytes) : super(bytes, false);
}

class _Pair extends _Key implements EncryptionKey {
  _Pair(super.bytes, super.extractable);
}

/// See the header: **not cryptography**. An [AccountCrypto] that only a test may make.
class FakeCrypto implements AccountCrypto {
  /// Throws [StateError] anywhere but under `flutter test`. [random] makes a test's keys and codes repeatable.
  FakeCrypto({Random? random}) : _random = random ?? Random.secure() {
    if (Platform.environment['FLUTTER_TEST'] != 'true') {
      throw StateError('FakeCrypto is not cryptography: it exists for tests, and will not be made outside `flutter test`.');
    }
  }

  final Random _random;

  static const int _iv = 12;
  static const int _tag = 16;
  static const int _point = 65;
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  // --- the pretend primitives -----------------------------------------------------------------------------------

  /// One hash over parts, each behind its length so two splits of the same bytes do not collide.
  static Uint8List _mix(List<Object> parts) {
    final out = BytesBuilder();
    for (final part in parts) {
      final bytes = part is String ? utf8.encode(part) : part as List<int>;
      out.add([bytes.length >> 24 & 0xff, bytes.length >> 16 & 0xff, bytes.length >> 8 & 0xff, bytes.length & 0xff]);
      out.add(bytes);
    }
    return sha256Of(out.takeBytes());
  }

  static Uint8List _xor(Uint8List key, Uint8List iv, Uint8List bytes) {
    final out = Uint8List(bytes.length);
    for (var block = 0; block * 32 < bytes.length; block += 1) {
      final pad = _mix(['stream', key, iv, '$block']);
      for (var i = block * 32; i < bytes.length && i < block * 32 + 32; i += 1) {
        out[i] = bytes[i] ^ pad[i - block * 32];
      }
    }
    return out;
  }

  /// [plain] "sealed": its bytes XORed, then 16 bytes that only the same key, iv and words give.
  static Uint8List _box(Uint8List key, Uint8List iv, String aad, Uint8List plain) {
    final hidden = _xor(key, iv, plain);
    return Uint8List.fromList([...hidden, ..._mix(['tag', key, iv, aad, hidden]).sublist(0, _tag)]);
  }

  static Uint8List _unbox(Uint8List key, Uint8List iv, String aad, Uint8List boxed) {
    if (boxed.length < _tag) throw const FormatException('That could not be opened.');
    final hidden = boxed.sublist(0, boxed.length - _tag);
    final tag = _mix(['tag', key, iv, aad, hidden]);
    for (var i = 0; i < _tag; i += 1) {
      if (tag[i] != boxed[hidden.length + i]) throw const FormatException('That could not be opened.');
    }
    return _xor(key, iv, hidden);
  }

  _Key _own(KeyHandle handle) {
    final Object held = handle;
    return held is _Key ? held : throw ArgumentError('That key was not made by a FakeCrypto.');
  }

  // --- secrets ----------------------------------------------------------------------------------------------------

  @override
  Future<Derived> derive(String secret, String salt, {int iterations = rounds}) async {
    final bits = _mix(['derive', secret, salt, '$iterations']);
    return Derived(login: toHex(_mix(['login', bits])), wrapKey: _Wrap(_mix(['wrap', bits])));
  }

  // --- the account key --------------------------------------------------------------------------------------------

  @override
  Future<SealKey> newAccountKey() async => _Seal(randomBytes(32), true);

  @override
  Future<String> wrap(SealKey accountKey, WrapKey wrapKey) async {
    final key = _own(accountKey);
    if (!key.extractable) throw StateError('That key is not extractable, and cannot be wrapped.');
    final iv = randomBytes(_iv);
    return toBase64Url([...iv, ..._box(_own(wrapKey).bytes, iv, 'account-key', key.bytes)]);
  }

  @override
  Future<SealKey> unwrap(String wrapped, WrapKey wrapKey, {bool extractable = false}) async {
    final bytes = fromBase64Url(wrapped);
    if (bytes.length < _iv) throw const FormatException('That could not be opened.');
    return _Seal(_unbox(_own(wrapKey).bytes, bytes.sublist(0, _iv), 'account-key', bytes.sublist(_iv)), extractable);
  }

  @override
  Future<SealKey> settle(SealKey accountKey) async => accountKey.extractable ? _Seal(_own(accountKey).bytes, false) : accountKey;

  @override
  Future<SealKey> importSealKey(Uint8List raw) async {
    if (raw.length != 32) throw ArgumentError('A key that seals is 32 bytes.');
    return _Seal(Uint8List.fromList(raw), false);
  }

  // --- sealed blobs -----------------------------------------------------------------------------------------------

  @override
  Future<Uint8List> sealBytes(SealKey key, Uint8List bytes, String context) async {
    final iv = randomBytes(_iv);
    return Uint8List.fromList([1, ...iv, ..._box(_own(key).bytes, iv, context, bytes)]);
  }

  @override
  Future<Uint8List> openBytes(SealKey key, Uint8List sealed, String context) async {
    if (sealed.isEmpty || sealed[0] != 1) throw const FormatException('This was sealed by a newer Ghost.md. Update the app to read it.');
    if (sealed.length < 1 + _iv) throw const FormatException('That could not be opened.');
    return _unbox(_own(key).bytes, sealed.sublist(1, 1 + _iv), context, sealed.sublist(1 + _iv));
  }

  @override
  Future<String> seal(SealKey key, Object? value, String context) async => toBase64Url(await sealBytes(key, utf8.encode(jsonEncode(value)), context));

  @override
  Future<Object?> open(SealKey key, String blob, String context) async => jsonDecode(utf8.decode(await openBytes(key, fromBase64Url(blob), context)));

  // --- recovery codes ---------------------------------------------------------------------------------------------

  @override
  String newRecoveryCode() {
    final picks = [for (final byte in randomBytes(12)) _alphabet[byte & 31]].join();
    return '${picks.substring(0, 4)}-${picks.substring(4, 8)}-${picks.substring(8, 12)}';
  }

  @override
  Future<RecoverySheet> newSheet(String handle, SealKey accountKey, {int iterations = rounds}) async {
    final codes = [for (var i = 0; i < recoveryCodes; i += 1) newRecoveryCode()];
    final entries = <SheetEntry>[];
    for (final code in codes) {
      final derived = await derive(normaliseCode(code), recoverySalt(handle), iterations: iterations);
      entries.add(SheetEntry(login: derived.login, wrapped: await wrap(accountKey, derived.wrapKey)));
    }
    return RecoverySheet(codes: codes, entries: entries);
  }

  // --- the device key ---------------------------------------------------------------------------------------------

  @override
  Future<DeviceKey> newDeviceKey() async => _Device(randomBytes(32));

  static Uint8List _devicePublic(Uint8List private) => _mix(['device-public', private]);

  static Uint8List _signature(Uint8List public, String nonce) => Uint8List.fromList([..._mix(['signature', public, nonce]), ..._mix(['signature-tail', public, nonce])]);

  @override
  Future<String> publicKeyOf(DeviceKey pair) async => toBase64Url(_devicePublic(_own(pair).bytes));

  @override
  Future<String> signNonce(DeviceKey pair, String nonce) async => toBase64Url(_signature(_devicePublic(_own(pair).bytes), nonce));

  /// Whether [signature] is what [signNonce] gives for [nonce] under the device key whose public half is
  /// [publicKey]: the service's side of password-free sign-in, which the web's fake does with WebCrypto's `verify`.
  /// Not in [AccountCrypto]: a client never verifies.
  Future<bool> verifyNonce(String publicKey, String nonce, String signature) async {
    try {
      final given = fromBase64Url(signature);
      final wanted = _signature(fromBase64Url(publicKey), nonce);
      if (given.length != wanted.length) return false;
      var same = true;
      for (var i = 0; i < wanted.length; i += 1) {
        if (given[i] != wanted[i]) same = false;
      }
      return same;
    } on FormatException {
      return false;
    }
  }

  // --- the encryption pair ----------------------------------------------------------------------------------------

  @override
  Future<EncryptionKey> newEncryptionKey() async => _Pair(randomBytes(32), true);

  static Uint8List _pointOf(Uint8List private) => Uint8List.fromList([4, ..._mix(['point-x', private]), ..._mix(['point-y', private])]);

  @override
  Future<String> encryptionPublicKeyOf(EncryptionKey pair) async => toBase64Url(_pointOf(_own(pair).bytes));

  @override
  Future<Map<String, Object?>> exportPrivateKey(EncryptionKey pair) async {
    final key = _own(pair);
    if (!key.extractable) throw StateError('That key pair is not extractable.');
    final point = _pointOf(key.bytes);
    return {
      'kty': 'EC',
      'crv': 'P-256',
      'd': toBase64Url(key.bytes),
      'x': toBase64Url(point.sublist(1, 33)),
      'y': toBase64Url(point.sublist(33)),
      'ext': true,
      'key_ops': ['deriveBits'],
    };
  }

  @override
  Future<EncryptionKey> importEncryptionKey(Map<String, Object?> jwk) async {
    final d = jwk['d'];
    if (jwk['kty'] != 'EC' || d is! String) throw const FormatException('That is not a key pair’s private half.');
    final private = fromBase64Url(d);
    if (private.length != 32) throw const FormatException('That is not a key pair’s private half.');
    return _Pair(private, false);
  }

  @override
  Future<EncryptionKey> settleEncryptionKey(EncryptionKey pair) async => pair.extractable ? _Pair(_own(pair).bytes, false) : pair;

  /// The "agreed" key: a hash of the member's public point and the wrap's own, which is no agreement at all.
  static Uint8List _agreed(Uint8List theirs, Uint8List ephemeral, String context) => _mix(['agreed', theirs, ephemeral, 'glyph/v1/org-key:$context']);

  @override
  Future<String> wrapFor(String pub, Uint8List orgKey, String context) async {
    final theirs = fromBase64Url(pub);
    if (theirs.length != _point || theirs[0] != 4) throw const FormatException('That is not a public key.');
    final ephemeral = Uint8List.fromList([4, ...randomBytes(_point - 1)]);
    final iv = randomBytes(_iv);
    return toBase64Url([...ephemeral, ...iv, ..._box(_agreed(theirs, ephemeral, context), iv, context, orgKey)]);
  }

  @override
  Future<Uint8List> unwrapWith(EncryptionKey pair, String wrapped, String context) async {
    final bytes = fromBase64Url(wrapped);
    if (bytes.length < _point + _iv + 17) throw const FormatException('That wrap could not be read.');
    final mine = _pointOf(_own(pair).bytes);
    final key = _agreed(mine, bytes.sublist(0, _point), context);
    return _unbox(key, bytes.sublist(_point, _point + _iv), context, bytes.sublist(_point + _iv));
  }

  // --- randomness and digests -------------------------------------------------------------------------------------

  @override
  Uint8List randomBytes(int count) {
    final out = Uint8List(count);
    for (var i = 0; i < count; i += 1) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  @override
  String shortId() => toBase64Url(randomBytes(16));

  @override
  Future<Uint8List> sha256(Uint8List bytes) async => sha256Of(bytes);
}

// --- SHA-256, the one real thing here (FIPS 180-4) ----------------------------------------------------------------

const List<int> _k = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, //
  0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, //
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, //
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, //
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

/// SHA-256 of [message], as 32 bytes.
Uint8List sha256Of(List<int> message) {
  final length = message.length;
  final padded = Uint8List(((length + 9 + 63) ~/ 64) * 64);
  padded.setRange(0, length, message);
  padded[length] = 0x80;
  final bits = length * 8;
  for (var i = 0; i < 8; i += 1) {
    padded[padded.length - 1 - i] = (bits >> (8 * i)) & 0xff;
  }
  final h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  final w = Uint32List(64);
  for (var at = 0; at < padded.length; at += 64) {
    for (var i = 0; i < 16; i += 1) {
      w[i] = (padded[at + 4 * i] << 24) | (padded[at + 4 * i + 1] << 16) | (padded[at + 4 * i + 2] << 8) | padded[at + 4 * i + 3];
    }
    for (var i = 16; i < 64; i += 1) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var i = 0; i < 64; i += 1) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & 0xffffffff & g);
      final t1 = (hh + s1 + ch + _k[i] + w[i]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    h[0] = (h[0] + a) & 0xffffffff;
    h[1] = (h[1] + b) & 0xffffffff;
    h[2] = (h[2] + c) & 0xffffffff;
    h[3] = (h[3] + d) & 0xffffffff;
    h[4] = (h[4] + e) & 0xffffffff;
    h[5] = (h[5] + f) & 0xffffffff;
    h[6] = (h[6] + g) & 0xffffffff;
    h[7] = (h[7] + hh) & 0xffffffff;
  }
  final out = Uint8List(32);
  for (var i = 0; i < 8; i += 1) {
    out[4 * i] = h[i] >> 24 & 0xff;
    out[4 * i + 1] = h[i] >> 16 & 0xff;
    out[4 * i + 2] = h[i] >> 8 & 0xff;
    out[4 * i + 3] = h[i] & 0xff;
  }
  return out;
}
