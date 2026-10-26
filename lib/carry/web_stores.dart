/// What the Tauri app's web view left on disk, read without a web view: the page's `localStorage`, and the
/// account's three keys out of IndexedDB. Over lib/carry/leveldb.dart.
///
/// **`localStorage`** is the plain one. Chromium keeps every origin's in one LevelDB
/// (`app_webview/Default/Local Storage/leveldb`): a key is `_<origin>\0` and then the page's key, a value is the
/// page's value, and each of the two starts with a byte saying how it is written (0: UTF-16, low byte first;
/// 1: one byte a character). The carry asks a web view first, which is Chromium reading its own files
/// (TauriCarry.kt); this is what it falls back on when no web view will answer.
///
/// **The keys** are the reason any of this is read from disk. `src/app/core/account/keystore.ts` keeps them as
/// `CryptoKey` objects in the database `glyph-account`, store `keys`, under `account`, `device` and
/// `encryption`, each made NOT extractable: a page can use one and can never read it out, so neither can a web
/// view asked on first launch. Chromium serialises a `CryptoKey` with its bytes all the same (Blink's
/// `V8ScriptValueSerializerForModules::WriteCryptoKey`):
///
/// ```text
/// \ K            a host object, a CryptoKey
/// 1 <algorithm> <bytes>            AES            | 5 <algorithm> <public 1, private 2> <curve>   an EC key
/// 7 <algorithm> <public 1, private 2>   Ed25519
/// <usages>   <length> <the key>    raw for AES, PKCS#8 for a private key, SPKI for a public one
/// ```
///
/// and a record's place in the LevelDB is `<database id> <store 1> <index 1> <the key's name>`, with the
/// database's id kept under its name. A pair is an object of two such keys, so each private key is read with its
/// public half beside it, which is how the carry checks what it read (the core raises the private key again and
/// must answer the same public one).
///
/// Nothing here throws for bytes it does not understand: a key that cannot be read is null, the person is asked
/// for their password once, and nothing is lost (the service holds the account key wrapped).
library;

import 'dart:convert';
import 'dart:io' hide Platform;
import 'dart:typed_data';

import 'leveldb.dart';
import '../core/host_platform.dart';

/// The origin the Tauri app's page was served from on Android (`http://tauri.localhost`, wry's default with no
/// `useHttpsScheme`): what its storage is kept under.
const String tauriOrigin = 'http://tauri.localhost';

/// Where a web view keeps things, under the app's data directory.
String webViewFolder(String dataDir) => '$dataDir${Platform.pathSeparator}app_webview${Platform.pathSeparator}Default';

/// The `localStorage` LevelDB under [dataDir].
Directory localStorageFolder(String dataDir) => Directory('${webViewFolder(dataDir)}${Platform.pathSeparator}Local Storage${Platform.pathSeparator}leveldb');

/// The IndexedDB LevelDB of [origin] under [dataDir]: `http_tauri.localhost_0.indexeddb.leveldb`.
Directory indexedDbFolder(String dataDir, {String origin = tauriOrigin}) {
  final uri = Uri.parse(origin);
  final port = uri.hasPort ? uri.port : 0;
  return Directory('${webViewFolder(dataDir)}${Platform.pathSeparator}IndexedDB${Platform.pathSeparator}${uri.scheme}_${uri.host}_$port.indexeddb.leveldb');
}

/// Every key and value [origin]'s page kept in `localStorage`, from the LevelDB [db].
Map<String, String> localStorageOf(LevelDb db, {String origin = tauriOrigin}) {
  final prefix = [0x5f, ...utf8.encode(origin), 0];
  final out = <String, String>{};
  for (final entry in db.entries) {
    if (!_startsWith(entry.key, prefix)) continue;
    final key = _storageText(Uint8List.sublistView(entry.key, prefix.length));
    final value = _storageText(entry.value);
    if (key != null && value != null) out[key] = value;
  }
  return out;
}

/// A `localStorage` string as Chromium writes it: a byte for the form, then the text.
String? _storageText(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  final body = Uint8List.sublistView(bytes, 1);
  switch (bytes[0]) {
    case 1:
      return latin1.decode(body);
    case 0:
      if (body.length.isOdd) return null;
      final data = ByteData.sublistView(body);
      return String.fromCharCodes([for (var i = 0; i < body.length; i += 2) data.getUint16(i, Endian.little)]);
    default:
      return null;
  }
}

/// A key read out of IndexedDB: what it is and its bytes.
class DiskKey {
  const DiskKey({required this.kind, required this.secret, this.public, required this.extractable});

  /// `aes`, `ec` or `ed25519`.
  final String kind;

  /// The key itself: an AES key's 32 bytes, a P-256 key's scalar, an Ed25519 key's seed.
  final Uint8List secret;

  /// The public half kept beside a private key, as the page exports it raw (a P-256 point's 65 bytes, an
  /// Ed25519 key's 32), or null when none was kept or read.
  final Uint8List? public;

  /// Whether the page could have exported it. The three a device keeps are not.
  final bool extractable;
}

/// The account's keys as the Tauri app left them in IndexedDB.
class DiskKeys {
  const DiskKeys({this.account, this.device, this.encryption, this.found = false});

  /// `keys/account`: AES-256-GCM.
  final DiskKey? account;

  /// `keys/device`: Ed25519, where the web view had it (Chromium 137 and later).
  final DiskKey? device;

  /// `keys/encryption`: ECDH on P-256.
  final DiskKey? encryption;

  /// Whether the database `glyph-account` was there at all.
  final bool found;

  /// Reads them from the IndexedDB LevelDB [db].
  factory DiskKeys.of(LevelDb db, {String database = 'glyph-account'}) {
    final id = _databaseId(db, database);
    if (id == null) return const DiskKeys();
    DiskKey? read(String name, String kind) {
      final value = db.get(_recordKey(id, name));
      if (value == null) return null;
      try {
        final keys = _cryptoKeys(value);
        final private = keys.where((key) => key.kind == kind && !key.isPublic).toList();
        if (private.length != 1) return null;
        final public = keys.where((key) => key.kind == kind && key.isPublic).toList();
        final secret = private.single.secret();
        if (secret == null) return null;
        return DiskKey(kind: kind, secret: secret, public: public.length == 1 ? public.single.publicRaw() : null, extractable: private.single.extractable);
      } catch (_) {
        // Bytes this does not understand: no key.
        return null;
      }
    }

    return DiskKeys(account: read('account', 'aes'), device: read('device', 'ed25519'), encryption: read('encryption', 'ec'), found: true);
  }
}

/// The scalar of a P-256 private key written as PKCS#8, as the core keeps one (32 bytes), or null for bytes that
/// are not one. WebKit keeps a private key in the same form (lib/carry/webkit_stores.dart).
Uint8List? p256ScalarOfPkcs8(Uint8List pkcs8) => _SerialKey(kind: 'ec', isPublic: false, extractable: false, data: pkcs8).secret();

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i += 1) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

/// IndexedDB's own string: how many UTF-16 units, then each with its high byte first.
List<int> _idbString(String text) => [..._varint(text.length), for (final unit in text.codeUnits) ...[unit >> 8, unit & 0xff]];

List<int> _varint(int value) {
  final out = <int>[];
  var rest = value;
  do {
    final low = rest & 0x7f;
    rest >>= 7;
    out.add(rest == 0 ? low : low | 0x80);
  } while (rest != 0);
  return out;
}

/// The id of the database named [name]: kept under `0 0 0 0 201 <origin> <name>`, for whichever origin (the
/// folder is one origin's).
int? _databaseId(LevelDb db, String name) {
  final tail = _idbString(name);
  int? found;
  var newest = -1;
  for (final entry in db.entries) {
    final key = entry.key;
    if (key.length < 5 + tail.length || key[0] != 0 || key[1] != 0 || key[2] != 0 || key[3] != 0 || key[4] != 201) continue;
    var same = true;
    for (var i = 0; i < tail.length && same; i += 1) {
      same = key[key.length - tail.length + i] == tail[i];
    }
    if (!same) continue;
    // What comes before the name must be exactly the origin's string, or a longer name's end would pass.
    final origin = _skipIdbString(key, 5);
    if (origin != key.length - tail.length) continue;
    final id = _readVarint(entry.value, 0)?.$1;
    if (id != null && entry.sequence > newest) {
      found = id;
      newest = entry.sequence;
    }
  }
  return found;
}

int? _skipIdbString(Uint8List bytes, int at) {
  final length = _readVarint(bytes, at);
  if (length == null) return null;
  final end = length.$2 + length.$1 * 2;
  return end <= bytes.length ? end : null;
}

(int, int)? _readVarint(Uint8List bytes, int at) {
  var value = 0, shift = 0, i = at;
  while (i < bytes.length && shift <= 56) {
    final next = bytes[i++];
    value |= (next & 0x7f) << shift;
    if (next & 0x80 == 0) return (value, i);
    shift += 7;
  }
  return null;
}

/// A record's place: the database, its first store (the only one each of the page's databases has), the
/// store's own data (index 1), then the key, a string.
List<int> _recordKey(int database, String name) {
  final id = _minimalBytes(database);
  return [(id.length - 1) << 5, ...id, 1, 1, 1, ..._idbString(name)];
}

List<int> _minimalBytes(int value) {
  final out = <int>[];
  var rest = value;
  do {
    out.add(rest & 0xff);
    rest >>= 8;
  } while (rest != 0);
  return out;
}

class _SerialKey {
  _SerialKey({required this.kind, required this.isPublic, required this.extractable, required this.data});

  final String kind;
  final bool isPublic;
  final bool extractable;

  /// Raw for AES, PKCS#8 for a private key, SubjectPublicKeyInfo for a public one.
  final Uint8List data;

  /// The 32 bytes the core keeps (native/src/crypto.rs `key_keep`).
  Uint8List? secret() {
    switch (kind) {
      case 'aes':
        return data.length == 32 ? data : null;
      case 'ed25519':
        // PrivateKeyInfo { 0, { Ed25519 }, OCTET STRING { OCTET STRING seed } }
        final info = _Der.sequence(data);
        final inner = info == null || info.length < 3 ? null : _Der.read(info[2].body, 0);
        return inner != null && inner.tag == 0x04 && inner.body.length == 32 ? inner.body : null;
      case 'ec':
        // PrivateKeyInfo { 0, { ecPublicKey, prime256v1 }, OCTET STRING { ECPrivateKey { 1, OCTET STRING d, … } } }
        final info = _Der.sequence(data);
        final key = info == null || info.length < 3 ? null : _Der.sequence(info[2].body);
        if (key == null || key.length < 2 || key[1].tag != 0x04) return null;
        final d = key[1].body;
        if (d.length > 32) return null;
        // A scalar may be written short of its leading zeros.
        return Uint8List(32)..setRange(32 - d.length, 32, d);
      default:
        return null;
    }
  }

  /// A public key as the page exports it raw: the BIT STRING of its SubjectPublicKeyInfo.
  Uint8List? publicRaw() {
    final info = _Der.sequence(data);
    if (info == null || info.length < 2 || info[1].tag != 0x03 || info[1].body.isEmpty) return null;
    return Uint8List.sublistView(info[1].body, 1);
  }
}

/// Every `CryptoKey` in a record's value. The value is the record's version, Blink's envelope, then V8's
/// serialisation, in which a key is a host object: found by its two tags and read from there, so the object a
/// pair is wrapped in never has to be walked.
List<_SerialKey> _cryptoKeys(Uint8List value) {
  final out = <_SerialKey>[];
  for (var i = 0; i + 2 < value.length; i += 1) {
    if (value[i] != 0x5c || value[i + 1] != 0x4b) continue;
    final key = _cryptoKeyAt(value, i + 2);
    if (key != null) {
      out.add(key.$1);
      i = key.$2 - 1;
    }
  }
  return out;
}

/// Blink's numbers for the algorithms (`CryptoKeyAlgorithmTag`) that the page's three keys use.
const int _aesGcm = 9, _ecdh = 15, _ed25519 = 18;

(_SerialKey, int)? _cryptoKeyAt(Uint8List bytes, int from) {
  var at = from;
  int? next() {
    final read = _readVarint(bytes, at);
    if (read == null) return null;
    at = read.$2;
    return read.$1;
  }

  final tag = next();
  String kind;
  var isPublic = false;
  switch (tag) {
    case 1:
      final algorithm = next(), length = next();
      if (algorithm != _aesGcm || length != 32) return null;
      kind = 'aes';
    case 5:
      final algorithm = next(), type = next(), curve = next();
      // Curve 1 is P-256.
      if (algorithm != _ecdh || curve != 1 || (type != 1 && type != 2)) return null;
      kind = 'ec';
      isPublic = type == 1;
    case 7:
      final algorithm = next(), type = next();
      if (algorithm != _ed25519 || (type != 1 && type != 2)) return null;
      kind = 'ed25519';
      isPublic = type == 1;
    default:
      return null;
  }
  final usages = next(), length = next();
  if (usages == null || length == null || length <= 0 || at + length > bytes.length) return null;
  final data = Uint8List.fromList(Uint8List.sublistView(bytes, at, at + length));
  return (_SerialKey(kind: kind, isPublic: isPublic, extractable: usages & 1 == 1, data: data), at + length);
}

/// As much of DER as two key formats need: a tag, a length, a body.
class _Der {
  const _Der(this.tag, this.body, this.end);

  final int tag;
  final Uint8List body;
  final int end;

  static _Der? read(Uint8List bytes, int at) {
    if (at + 2 > bytes.length) return null;
    final tag = bytes[at];
    var length = bytes[at + 1], from = at + 2;
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 3 || from + count > bytes.length) return null;
      length = 0;
      for (var i = 0; i < count; i += 1) {
        length = (length << 8) | bytes[from + i];
      }
      from += count;
    }
    if (from + length > bytes.length) return null;
    return _Der(tag, Uint8List.sublistView(bytes, from, from + length), from + length);
  }

  /// The members of the SEQUENCE that [bytes] is, or null when it is not one.
  static List<_Der>? sequence(Uint8List bytes) {
    final outer = read(bytes, 0);
    if (outer == null || outer.tag != 0x30) return null;
    final out = <_Der>[];
    var at = 0;
    while (at < outer.body.length) {
      final member = read(outer.body, at);
      if (member == null) return null;
      out.add(member);
      at = member.end;
    }
    return out;
  }
}
