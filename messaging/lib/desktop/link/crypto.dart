import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// The sealing between the Mac and the phone it is paired with (docs/desktop.md): the Dart half of the phone's
/// `DeskCrypto.kt`, held to the same examples (test/desk_vectors.json, made by tool/desk_vectors.mjs).
///
/// P-256 ECDH into HKDF-SHA256 into AES-256-GCM, as the phone-to-phone encryption is (`E2eCrypto.kt`), with the QR
/// code's secret in the pairing's key, a key for each connection in each direction, and a counter on every frame.
class DeskCrypto {
  DeskCrypto._();

  static const offerTag = 'GHOSTPAIR1:';
  static const int hello = 1;
  static const int sealed = 2;

  /// The largest frame either side sends or takes.
  static const int maxFrame = 1 << 20;

  static final ECDomainParameters _curve = ECCurve_secp256r1();
  static final Uint8List _aad = _utf8('ghost-desk-v1');

  static Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

  static final SecureRandom _random = () {
    final seed = Random.secure();
    return FortunaRandom()..seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => seed.nextInt(256)))));
  }();

  static Uint8List randomBytes(int n) => _random.nextBytes(n);

  static String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List unhex(String text) => Uint8List.fromList([for (var i = 0; i + 1 < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)]);

  static Uint8List concat(List<List<int>> parts) => Uint8List.fromList([for (final p in parts) ...p]);

  static Uint8List hmac(List<int> key, List<int> data) {
    final h = HMac(SHA256Digest(), 64)..init(KeyParameter(Uint8List.fromList(key)));
    return h.process(Uint8List.fromList(data));
  }

  /// HKDF-SHA256 with one block of output.
  static Uint8List hkdf(List<int> salt, List<int> ikm, String info) => hmac(hmac(salt, ikm), concat([utf8.encode(info), [1]]));

  /// A value made from the pairing's key: its id, its relay channel, its code.
  static Uint8List derive(List<int> key, String label) => hmac(key, concat([utf8.encode('ghost-desk $label'), [1]]));

  static Uint8List _ordered(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] < b[i] ? concat([a, b]) : concat([b, a]);
    }
    return concat([a, b]);
  }

  // --- keys ----------------------------------------------------------------------------------------------------------

  static DeskKeyPair newKeyPair() {
    final gen = ECKeyGenerator()..init(ParametersWithRandom(ECKeyGeneratorParameters(_curve), _random));
    final pair = gen.generateKeyPair();
    return DeskKeyPair._(pair.privateKey, pair.publicKey.Q!.getEncoded(true));
  }

  /// A key pair from its private half's 32 bytes: the examples' fixed keys, and a pairing waiting to be finished.
  static DeskKeyPair keyPairFrom(List<int> scalar) {
    final d = BigInt.parse(hex(scalar), radix: 16);
    return DeskKeyPair._(ECPrivateKey(d, _curve), (_curve.G * d)!.getEncoded(true));
  }

  /// The secret the holder of [mine] and the holder of [theirs] (33 bytes) agree on, or null when those are no key.
  static Uint8List? _agree(DeskKeyPair mine, List<int> theirs) {
    if (theirs.length != 33 || (theirs[0] != 2 && theirs[0] != 3)) return null;
    try {
      final point = _curve.curve.decodePoint(theirs);
      if (point == null || point.isInfinity) return null;
      final s = (ECDHBasicAgreement()..init(mine._private)).calculateAgreement(ECPublicKey(point, _curve));
      return unhex(s.toRadixString(16).padLeft(64, '0'));
    } catch (_) {
      return null;
    }
  }

  static bool isKey(List<int> bytes) {
    if (bytes.length != 33 || (bytes[0] != 2 && bytes[0] != 3)) return false;
    try {
      final point = _curve.curve.decodePoint(bytes);
      return point != null && !point.isInfinity;
    } catch (_) {
      return false;
    }
  }

  // --- what the QR code's secret alone makes --------------------------------------------------------------------------

  static Uint8List fromSecret(List<int> secret, String label) => hkdf(utf8.encode('ghost-desk pairing'), secret, label);
  static String pairingId(List<int> secret) => hex(fromSecret(secret, 'id').sublist(0, 8));
  static String pairingChannel(List<int> secret) => hex(fromSecret(secret, 'relay channel').sublist(0, 16));
  static String pairingToken(List<int> secret) => hex(fromSecret(secret, 'relay token'));

  // --- the pairing's key -----------------------------------------------------------------------------------------------

  /// The key the Mac and the phone keep: the same on both, and nobody's who lacks the QR code's [secret].
  static Uint8List? pairKey(DeskKeyPair mine, List<int> theirs, List<int> secret) {
    final shared = _agree(mine, theirs);
    if (shared == null) return null;
    return hkdf(_ordered(mine.public, Uint8List.fromList(theirs)), concat([shared, secret]), 'ghost-messaging desktop v1');
  }

  static String id(List<int> pairKey) => hex(derive(pairKey, 'id').sublist(0, 8));
  static String relayChannel(List<int> pairKey) => hex(derive(pairKey, 'relay channel').sublist(0, 16));
  static String relayToken(List<int> pairKey) => hex(derive(pairKey, 'relay token'));

  /// Six digits, the same on both when they hold the same key: what is compared by eye as they pair.
  static String code(List<int> pairKey) {
    final d = derive(pairKey, 'code');
    final n = (d[0] << 24) | (d[1] << 16) | (d[2] << 8) | d[3];
    return (n % 1000000).toString().padLeft(6, '0');
  }

  // --- one connection --------------------------------------------------------------------------------------------------

  /// The two keys of one connection, the Mac's (what it seals with) and the phone's.
  static ({Uint8List desk, Uint8List phone})? sessionKeys(List<int> pairKey, List<int> deskNonce, List<int> phoneNonce, DeskKeyPair mine, List<int> theirs) {
    final shared = _agree(mine, theirs);
    if (shared == null) return null;
    final prk = hmac(concat([deskNonce, phoneNonce]), concat([pairKey, shared]));
    return (desk: hmac(prk, concat([utf8.encode('d2p'), [1]])), phone: hmac(prk, concat([utf8.encode('p2d'), [1]])));
  }

  static Uint8List _nonce(int counter) {
    final n = Uint8List(12);
    ByteData.sublistView(n).setUint64(4, counter);
    return n;
  }

  static Uint8List _gcm(bool seal, List<int> key, int counter, List<int> input) {
    final c = GCMBlockCipher(AESEngine())..init(seal, AEADParameters(KeyParameter(Uint8List.fromList(key)), 128, _nonce(counter), _aad));
    return c.process(Uint8List.fromList(input));
  }
}

/// A P-256 key pair: the private half stays in here, the public half is its 33 bytes (the point, compressed).
class DeskKeyPair {
  DeskKeyPair._(this._private, this.public);
  final ECPrivateKey _private;
  final Uint8List public;

  /// The private half's 32 bytes, to keep a pairing that is waiting for the phone across a restart of the wizard.
  Uint8List get scalar => DeskCrypto.unhex(_private.d!.toRadixString(16).padLeft(64, '0'));
}

/// One side of a connection: what it seals goes out under [sendKey], what arrives is opened under [receiveKey].
/// A frame's counter is its nonce and is never sent, so a frame repeated, dropped, reordered or changed does not open.
class DeskChannel {
  DeskChannel({required this.sendKey, required this.receiveKey});
  final Uint8List sendKey;
  final Uint8List receiveKey;
  int _sent = 0;
  int _received = 0;

  Uint8List seal(String text) => DeskCrypto._gcm(true, sendKey, _sent++, utf8.encode(text));

  String? open(List<int> sealed) {
    try {
      final text = utf8.decode(DeskCrypto._gcm(false, receiveKey, _received, sealed));
      _received++;
      return text;
    } catch (_) {
      return null;
    }
  }
}

/// What the Mac's QR code says: its public key for this pairing, sixteen random bytes that cross no network, its
/// name, how it would connect (both, local, relay) and the relay's address.
class DeskOffer {
  const DeskOffer({required this.key, required this.secret, required this.name, required this.mode, required this.relay});
  final Uint8List key;
  final Uint8List secret;
  final String name;
  final String mode;
  final String relay;

  static const modes = {'both', 'local', 'relay'};

  String get text => DeskCrypto.offerTag + base64Url.encode(utf8.encode(jsonEncode({'k': base64.encode(key), 's': base64.encode(secret), 'n': name, 'm': mode, 'r': relay}))).replaceAll('=', '');

  static DeskOffer? parse(String text) {
    final body = text.trim();
    if (!body.startsWith(DeskCrypto.offerTag)) return null;
    try {
      final o = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(body.substring(DeskCrypto.offerTag.length).trim())))) as Map;
      final key = base64.decode(o['k'] as String);
      final secret = base64.decode(o['s'] as String);
      final mode = (o['m'] as String?) ?? 'both';
      if (!DeskCrypto.isKey(key) || secret.length != 16 || !modes.contains(mode)) return null;
      return DeskOffer(key: key, secret: secret, name: (o['n'] as String?) ?? 'A computer', mode: mode, relay: ((o['r'] as String?) ?? '').trim());
    } catch (_) {
      return null;
    }
  }
}
