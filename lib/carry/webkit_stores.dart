/// What the Tauri Mac app's web view left on disk, read without a web view: the page's `localStorage`, the
/// account's three keys and the team notes' documents out of IndexedDB. The Mac's twin of web_stores.dart, which
/// reads what a phone's Chromium left; the Mac's web view is WebKit, and nothing is laid out the same.
///
/// **Where.** Not in the app's folder: `~/Library/WebKit/com.mattssoftware.glyph/WebsiteData/Default/<a>/<b>/`,
/// one folder to an origin (`<a>` and `<b>` are salted hashes of the page's origin and the frame's, the same for a
/// page that is its own top), with a file `origin` in it saying which. The Tauri app's page is `tauri://localhost`
/// ([tauriMacOrigin]). In it:
///
/// - `LocalStorage/localstorage.sqlite3`: a table `ItemTable(key TEXT, value BLOB)`, a value its UTF-16 text, low
///   byte first.
/// - `IndexedDB/<hash of the database's name>/IndexedDB.sqlite3`, one to a database: its name in
///   `IDBDatabaseInfo`, its stores in `ObjectStoreInfo`, and `Records(objectStoreID, key, value)`. A key is
///   WebKit's `IDBKeyData` (for a string: `00 60`, how many UTF-16 units, the units); a value is WebKit's
///   `SerializedScriptValue` ([_Ssv]).
///
/// **They are read from a copy.** SQLite opens a file to read it and, in write-ahead mode, may write its `-shm`
/// and fold its `-wal`; the Tauri app's files are the way back to that app and are never opened by anything but a
/// plain read of their bytes. So each file is copied with its `-wal` and `-shm` to a folder made for the moment
/// ([WebKitStores.read]), read there, and the folder removed: it held the session.
///
/// **The keys are wrapped**, which is where the Mac differs most from a phone. Chromium writes a `CryptoKey`'s
/// bytes to disk in the clear; WebKit wraps each one (`WebCore/crypto/mac/SerializedCryptoKeyWrapMac.mm`): a
/// binary property list of `wrappedKEK` (a fresh 16-byte key, wrapped by RFC 3394 under the app's "WebCrypto
/// Master Key"), `encryptedKey` (the key's serialisation, AES-128-GCM under that fresh key with an empty IV),
/// `tag` and `version` 1. The master key is a generic password in the login Keychain, account
/// `com.apple.WebKit.WebCrypto.master+com.mattssoftware.glyph`, readable without a prompt only by an app the
/// Keychain takes for the one that made it: the same bundle id signed by the same team
/// (macos/Runner/GhostChannels.swift `webCryptoMasterKey`). With it, [WrappedKey.open] gives the serialisation ([_keyOf]):
///
/// ```text
/// <u32 15> <u32 1> <extractable> <u32 how many usages> <a byte each>
/// 1 (AES)  <algorithm 9: AES-GCM>                              <u32 length> <the key>
/// 3 (EC)   <algorithm 5: ECDH> <"P-256"> <0 public, 1 private>  <u32 length> <the raw point | PKCS#8>
/// 5 (OKP)  <algorithm 22: Ed25519> <curve 1>                    <u32 length> <32 bytes: the seed, or the public key>
/// ```
///
/// GCM's tag is checked, so a key that opens is byte for byte what WebKit wrapped, and a wrong master key opens
/// nothing. Without the master key the keys stay wrapped, the person is asked for their password once, and nothing
/// is lost (the service holds the account key wrapped).
///
/// All of it was worked out against a real WebKit's storage, made by tool/webkit_fixture.swift, and is held to it
/// by test/carry/webkit_stores_test.dart. Nothing here throws for bytes it does not understand: a record that
/// will not parse is counted in [WebKitRead.damaged] and left.
library;

import 'dart:convert';
import 'dart:io' hide Platform;
import 'dart:typed_data';

import 'aes_unwrap.dart';
import 'sqlite_read.dart' if (dart.library.js_interop) 'sqlite_read_web.dart';
import 'web_stores.dart' show DiskKey, DiskKeys, p256ScalarOfPkcs8;
import '../core/host_platform.dart';

/// The origin the Tauri app's page has on a Mac: wry's own scheme, with no `useHttpsScheme`
/// (tauri/src-tauri/tauri.conf.json).
const ({String scheme, String host}) tauriMacOrigin = (scheme: 'tauri', host: 'localhost');

/// The Keychain account WebKit keeps an app's master key under (`masterKeyAccountNameForCurrentApplication`).
String webCryptoMasterKeyAccount(String bundleId) => 'com.apple.WebKit.WebCrypto.master+$bundleId';

/// The master key out of what the Keychain holds for it: WebKit stores its 16 bytes as base64 text.
Uint8List? webCryptoMasterKey(Uint8List kept) {
  if (kept.length == 16) return kept;
  try {
    final decoded = base64.decode(ascii.decode(kept).trim());
    return decoded.length == 16 ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// A `CryptoKey` as WebKit stored it: still wrapped.
class WrappedKey {
  const WrappedKey(this.bytes);

  /// The binary property list.
  final Uint8List bytes;

  /// The key's serialisation, opened under [masterKey], or null: not WebKit's wrap, another version of it, or
  /// not wrapped under that key.
  Uint8List? open(Uint8List masterKey) {
    try {
      final plist = _Bplist.dictionary(bytes);
      final kek = plist?['wrappedKEK'], sealed = plist?['encryptedKey'], tag = plist?['tag'];
      if (plist == null || plist['version'] != 1 || kek is! Uint8List || sealed is! Uint8List || tag is! Uint8List) return null;
      final fresh = aesKeyUnwrap(masterKey, kek);
      if (fresh == null) return null;
      return aesGcmOpen(fresh, Uint8List(0), sealed, tag);
    } catch (_) {
      return null;
    }
  }
}

/// What a WebKit web view kept for one origin.
class WebKitRead {
  const WebKitRead({required this.found, this.local = const {}, this.wrapped = const {}, this.keysFound = false, this.team = const [], this.damaged = 0, this.failure});

  /// Whether the origin's folder was there at all.
  final bool found;

  /// Every key and value of `localStorage`.
  final Map<String, String> local;

  /// `glyph-account`'s records, by name (`account`, `device`, `encryption`): each the wrapped keys in it, by the
  /// property they were under (`privateKey`, `publicKey`), or `''` for a record that is one key.
  final Map<String, Map<String, WrappedKey>> wrapped;

  /// Whether the database `glyph-account` was there.
  final bool keysFound;

  /// `glyph-team`'s documents, as the carry takes them (lib/carry/tauri_carry.dart `_carryDocument`): `id`,
  /// `state` and each of `pending` as base64url without padding, `seq`, `snapshotSeq`.
  final List<Map<String, Object?>> team;

  /// How many records or files could not be read.
  final int damaged;

  /// Why nothing could be read, when nothing could.
  final String? failure;

  /// The three keys, opened under [masterKey]. A key that will not open, or is not the kind its name says, is
  /// null; with no master key every one is. [deviceRecord] is the record the device's key is read from: the
  /// page's own name for it, but in a test that keeps a second one beside it.
  DiskKeys keys(Uint8List? masterKey, {String deviceRecord = 'device'}) {
    if (!keysFound) return const DiskKeys();
    if (masterKey == null) return const DiskKeys(found: true);
    _Key? open(String record, String property, String kind, {required bool private}) {
      final plain = wrapped[record]?[property]?.open(masterKey);
      final key = plain == null ? null : _keyOf(plain);
      if (key == null || key.kind != kind) return null;
      // An Ed25519 key does not say which half it is: the property it was under does, and what it may be used for.
      if (key.isPublic != null && key.isPublic == private) return null;
      return key;
    }

    DiskKey? pair(String record, String kind) {
      final private = open(record, 'privateKey', kind, private: true), public = open(record, 'publicKey', kind, private: false);
      final secret = private == null ? null : (kind == 'ec' ? p256ScalarOfPkcs8(private.data) : (private.data.length == 32 ? private.data : null));
      if (private == null || secret == null) return null;
      return DiskKey(kind: kind, secret: secret, public: public?.data, extractable: private.extractable);
    }

    final account = open('account', '', 'aes', private: true);
    return DiskKeys(
      account: account == null || account.data.length != 32 ? null : DiskKey(kind: 'aes', secret: account.data, extractable: account.extractable),
      device: pair(deviceRecord, 'ed25519'),
      encryption: pair('encryption', 'ec'),
      found: true,
    );
  }

  /// How many wrapped keys were found, for the log.
  int get wrappedCount => wrapped.values.fold(0, (sum, record) => sum + record.length);
}

class WebKitStores {
  WebKitStores._();

  /// The folder of [origin] under a web view's `WebsiteData` (or a store made by identifier, whose origins are
  /// under `Origins`), or null when that origin kept nothing.
  static Future<Directory?> originFolder(Directory websiteData, {({String scheme, String host}) origin = tauriMacOrigin}) async {
    for (final name in const ['Default', 'Origins']) {
      final root = Directory('${websiteData.path}${Platform.pathSeparator}$name');
      if (!await root.exists()) continue;
      await for (final top in root.list(followLinks: false)) {
        if (top is! Directory) continue;
        await for (final frame in top.list(followLinks: false)) {
          if (frame is! Directory) continue;
          final said = File('${frame.path}${Platform.pathSeparator}origin');
          try {
            if (await said.exists() && _isOrigin(await said.readAsBytes(), origin)) return frame;
          } catch (_) {
            // A folder that cannot be read is not the one.
          }
        }
      }
    }
    return null;
  }

  /// Reads what [origin]'s page kept under [websiteData], from copies of its files made in a folder of the
  /// system's temporary directory and removed before this returns. It never throws.
  static Future<WebKitRead> read(Directory websiteData, {({String scheme, String host}) origin = tauriMacOrigin}) async {
    Directory? copy;
    try {
      final folder = await originFolder(websiteData, origin: origin);
      if (folder == null) return const WebKitRead(found: false);
      copy = await Directory.systemTemp.createTemp('ghost-carry-');
      var damaged = 0;

      var local = <String, String>{};
      final storage = await _copied(File('${folder.path}/LocalStorage/localstorage.sqlite3'), copy, 'local');
      if (storage != null) {
        try {
          local = {
            for (final row in SqliteRead.rows(storage, 'SELECT key, value FROM ItemTable', ownCopy: true))
              if (row[0] is String && row[1] is Uint8List) row[0] as String: _utf16(row[1] as Uint8List),
          };
        } catch (_) {
          damaged += 1;
        }
      }

      final wrapped = <String, Map<String, WrappedKey>>{};
      final team = <Map<String, Object?>>[];
      var keysFound = false;
      final databases = Directory('${folder.path}/IndexedDB');
      if (await databases.exists()) {
        var count = 0;
        await for (final each in databases.list(followLinks: false)) {
          if (each is! Directory) continue;
          final file = await _copied(File('${each.path}/IndexedDB.sqlite3'), copy, 'idb${count += 1}');
          if (file == null) continue;
          try {
            final name = _databaseName(file);
            if (name != 'glyph-account' && name != 'glyph-team') continue;
            final store = name == 'glyph-account' ? 'keys' : 'docs';
            final stores = SqliteRead.rows(file, 'SELECT id, name FROM ObjectStoreInfo', ownCopy: true);
            final id = stores.where((row) => row[1] == store).map((row) => row[0]).firstOrNull;
            if (name == 'glyph-account') keysFound = true;
            if (id == null) continue;
            // The whole table, and the store chosen here: `key` has WebKit's own collation, which SQLite cannot
            // compare by without WebKit.
            for (final row in SqliteRead.rows(file, 'SELECT objectStoreID, CAST(key AS BLOB), value FROM Records', ownCopy: true)) {
              if (row[0] != id) continue;
              final key = row[1] is Uint8List ? _idbString(row[1] as Uint8List) : null;
              final value = row[2];
              if (key == null || value is! Uint8List) {
                damaged += 1;
                continue;
              }
              try {
                final read = _Ssv(value).value();
                if (name == 'glyph-account') {
                  final keys = _wrappedIn(read);
                  if (keys.isEmpty) {
                    damaged += 1;
                  } else {
                    wrapped[key] = keys;
                  }
                } else {
                  final document = _document(key, read);
                  if (document == null) {
                    damaged += 1;
                  } else {
                    team.add(document);
                  }
                }
              } catch (_) {
                damaged += 1;
              }
            }
          } catch (_) {
            damaged += 1;
          }
        }
      }
      return WebKitRead(found: true, local: local, wrapped: wrapped, keysFound: keysFound, team: team, damaged: damaged);
    } catch (failure) {
      return WebKitRead(found: true, failure: '$failure', damaged: 1);
    } finally {
      try {
        await copy?.delete(recursive: true);
      } catch (_) {
        // The system clears its temporary directory itself.
      }
    }
  }

  /// [file] with its `-wal` and `-shm`, copied into a folder of its own under [into]: the copy's path, or null
  /// when there is no such file. The originals are only ever read.
  static Future<String?> _copied(File file, Directory into, String name) async {
    if (!await file.exists()) return null;
    final folder = await Directory('${into.path}${Platform.pathSeparator}$name').create();
    final copy = '${folder.path}${Platform.pathSeparator}db.sqlite3';
    await file.copy(copy);
    for (final suffix in const ['-wal', '-shm']) {
      final beside = File('${file.path}$suffix');
      if (await beside.exists()) await beside.copy('$copy$suffix');
    }
    return copy;
  }

  /// A database's name. WebKit writes it as UTF-16 into a text column.
  static String? _databaseName(String file) {
    final rows = SqliteRead.rows(file, "SELECT CAST(value AS BLOB) FROM IDBDatabaseInfo WHERE key = 'DatabaseName'", ownCopy: true);
    final bytes = rows.isEmpty ? null : rows.first[0];
    if (bytes is! Uint8List) return null;
    var wide = bytes.length.isEven && bytes.isNotEmpty;
    for (var i = 1; i < bytes.length && wide; i += 2) {
      wide = bytes[i] == 0;
    }
    return wide ? _utf16(bytes) : utf8.decode(bytes, allowMalformed: true);
  }
}

String _utf16(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return String.fromCharCodes([for (var i = 0; i + 1 < bytes.length; i += 2) data.getUint16(i, Endian.little)]);
}

String _b64(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// Whether an `origin` file names [origin] as both the page's origin and the frame's. The file is WebKit's
/// `ClientOrigin`: two origins, each a scheme and a host (a length, a byte saying one byte to a character, the
/// characters) and then a byte for whether a port follows.
bool _isOrigin(Uint8List bytes, ({String scheme, String host}) origin) {
  var at = 0;
  String? text() {
    if (at + 5 > bytes.length) return null;
    final length = ByteData.sublistView(bytes).getUint32(at, Endian.little);
    final narrow = bytes[at + 4] == 1;
    at += 5;
    final size = narrow ? length : length * 2;
    if (length > 4096 || at + size > bytes.length) return null;
    final body = Uint8List.sublistView(bytes, at, at + size);
    at += size;
    return narrow ? latin1.decode(body) : _utf16(body);
  }

  for (var i = 0; i < 2; i += 1) {
    if (text() != origin.scheme || text() != origin.host) return false;
    if (at >= bytes.length || bytes[at] != 0) return false; // a port: not the Tauri app's page
    at += 1;
  }
  return true;
}

/// A record's key when it is a string (`IDBKeyData`: a version, the type, the length, UTF-16).
String? _idbString(Uint8List key) {
  if (key.length < 6 || key[0] != 0 || key[1] != 0x60) return null;
  final length = ByteData.sublistView(key).getUint32(2, Endian.little);
  if (key.length != 6 + length * 2) return null;
  return _utf16(Uint8List.sublistView(key, 6));
}

/// The wrapped keys in a record's value: the value itself, or the properties of the object it is.
Map<String, WrappedKey> _wrappedIn(Object? value) {
  if (value is WrappedKey) return {'': value};
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.key is String && entry.value is WrappedKey) entry.key as String: entry.value as WrappedKey,
  };
}

/// A team note's document (tauri/src/app/core/team/docs.ts `TeamDocRecord`), as the carry takes one.
Map<String, Object?>? _document(String id, Object? value) {
  if (value is! Map) return null;
  final state = value['state'], seq = value['seq'], snapshotSeq = value['snapshotSeq'], pending = value['pending'];
  if (state is! Uint8List || seq is! num || snapshotSeq is! num || pending is! List || pending.any((each) => each is! Uint8List)) return null;
  return {'id': id, 'state': _b64(state), 'seq': seq.toInt(), 'snapshotSeq': snapshotSeq.toInt(), 'pending': [for (final each in pending) _b64(each as Uint8List)]};
}

/// WebKit's `SerializedScriptValue`, as much of it as the page's records use (WebCore
/// `bindings/js/SerializedScriptValue.cpp`): a version, then a value by its tag. Numbers are low byte first.
/// Anything else (a date, a map, a blob, a second reference to one object) is a [FormatException], and the record
/// is left.
class _Ssv {
  _Ssv(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _at = 0;

  /// Every string written so far: a later one that is the same is written as its place in this list.
  final List<String> _strings = [];

  static const int _terminator = 0xffffffff, _pooled = 0xfffffffe;

  Object? value() {
    final version = _u32();
    if (version < 9 || version > 64) throw const FormatException('not a serialised value');
    return _value(0);
  }

  int _u8() {
    if (_at + 1 > _bytes.length) throw const FormatException('cut short');
    return _bytes[_at++];
  }

  int _u32() {
    if (_at + 4 > _bytes.length) throw const FormatException('cut short');
    final value = _data.getUint32(_at, Endian.little);
    _at += 4;
    return value;
  }

  int _u64() {
    if (_at + 8 > _bytes.length) throw const FormatException('cut short');
    final value = _data.getUint64(_at, Endian.little);
    _at += 8;
    if (value < 0 || value > _bytes.length) throw const FormatException('a length past the end');
    return value;
  }

  Uint8List _take(int length) {
    if (length < 0 || _at + length > _bytes.length) throw const FormatException('cut short');
    final out = Uint8List.fromList(Uint8List.sublistView(_bytes, _at, _at + length));
    _at += length;
    return out;
  }

  /// A string after its length word [said] (already read): the characters, or a place in the pool.
  String _string(int said) {
    if (said == _pooled) {
      final index = _strings.length <= 0xff ? _u8() : (_strings.length <= 0xffff ? (_u8() | (_u8() << 8)) : _u32());
      if (index >= _strings.length) throw const FormatException('a string that was never written');
      return _strings[index];
    }
    final narrow = said & 0x80000000 != 0;
    final length = said & 0x7fffffff;
    final text = narrow ? latin1.decode(_take(length)) : _utf16(_take(length * 2));
    _strings.add(text);
    return text;
  }

  Object? _value(int depth) {
    if (depth > 16) throw const FormatException('too deep');
    final tag = _u8();
    switch (tag) {
      case 1: // an array: its length, then a place and a value for each, then its other properties
        final length = _u32();
        if (length > _bytes.length) throw const FormatException('an array longer than its bytes');
        final out = List<Object?>.filled(length, null);
        while (true) {
          final index = _u32();
          if (index == _terminator) break;
          if (index >= length) throw const FormatException('past the array');
          out[index] = _value(depth + 1);
        }
        while (true) {
          final said = _u32();
          if (said == _terminator) break;
          _string(said);
          _value(depth + 1);
        }
        return out;
      case 2: // an object: a name and a value for each property
        final out = <String, Object?>{};
        while (true) {
          final said = _u32();
          if (said == _terminator) break;
          final name = _string(said);
          out[name] = _value(depth + 1);
        }
        return out;
      case 3 || 4:
        return null;
      case 5:
        return _u32().toSigned(32);
      case 6:
        return 0;
      case 7:
        return 1;
      case 8:
        return false;
      case 9:
        return true;
      case 10:
        final bytes = _take(8);
        return ByteData.sublistView(bytes).getFloat64(0, Endian.little);
      case 16:
        return _string(_u32());
      case 17:
        return '';
      case 21: // an ArrayBuffer
        return _take(_u64());
      case 22: // a view of one: which kind, where it starts, how long, then the buffer
        final kind = _u8();
        final from = _u64(), length = _u64();
        final buffer = _value(depth + 1);
        // 2 is a Uint8Array, 3 a clamped one: the only views that are plain bytes.
        if ((kind != 2 && kind != 3) || buffer is! Uint8List || from + length > buffer.length) throw const FormatException('not a view of bytes');
        return Uint8List.sublistView(buffer, from, from + length);
      case 33: // a CryptoKey, wrapped
        return WrappedKey(_take(_u32()));
      default:
        throw FormatException('a value this does not read ($tag)');
    }
  }
}

/// A key out of its wrap: what it is and its bytes.
class _Key {
  const _Key({required this.kind, required this.isPublic, required this.extractable, required this.data});

  /// `aes`, `ec` or `ed25519`.
  final String kind;

  /// Which half, where the serialisation says (an EC key) or its uses do (an Ed25519 key: one that may sign is
  /// the private half, one that may verify the public); null where neither does.
  final bool? isPublic;
  final bool extractable;

  /// Raw for AES, an Ed25519 key and a public point; PKCS#8 for a private EC key.
  final Uint8List data;
}

/// WebKit's numbers for the algorithms the page's three keys use (`CryptoAlgorithmIdentifierTag`), its classes
/// of key, and the uses that tell an Ed25519 key's halves apart (`CryptoKeyUsageTag`).
const int _aesGcm = 9, _ecdh = 5, _ed25519 = 22;
const int _classAes = 1, _classEc = 3, _classOkp = 5;
const int _usageSign = 2, _usageVerify = 3;

/// The key in the serialisation a wrap opens to (the header's table), or null for one that is not the page's.
_Key? _keyOf(Uint8List plain) {
  try {
    final data = ByteData.sublistView(plain);
    var at = 0;
    int u8() => plain[at++];
    int u32() {
      final value = data.getUint32(at, Endian.little);
      at += 4;
      return value;
    }

    Uint8List take(int length) {
      if (length < 0 || at + length > plain.length) throw const FormatException('cut short');
      final out = Uint8List.fromList(Uint8List.sublistView(plain, at, at + length));
      at += length;
      return out;
    }

    u32(); // the serialisation's version
    if (u32() != 1) return null; // the key's
    final extractable = u8() != 0;
    final count = u32();
    if (count > 16) return null;
    final usages = [for (var i = 0; i < count; i += 1) u8()];
    switch (u8()) {
      case _classAes:
        if (u8() != _aesGcm) return null;
        return _Key(kind: 'aes', isPublic: null, extractable: extractable, data: take(u32()));
      case _classEc:
        if (u8() != _ecdh) return null;
        final said = u32();
        final curve = said & 0x80000000 != 0 ? latin1.decode(take(said & 0x7fffffff)) : _utf16(take((said & 0x7fffffff) * 2));
        if (curve != 'P-256') return null;
        final type = u8();
        if (type != 0 && type != 1) return null;
        return _Key(kind: 'ec', isPublic: type == 0, extractable: extractable, data: take(u32()));
      case _classOkp:
        if (u8() != _ed25519 || u8() != 1) return null;
        final signs = usages.contains(_usageSign), verifies = usages.contains(_usageVerify);
        return _Key(kind: 'ed25519', isPublic: signs == verifies ? null : verifies, extractable: extractable, data: take(u32()));
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}

/// A binary property list, as much as WebKit's wrap is: one dictionary of names to bytes and whole numbers.
class _Bplist {
  static Map<String, Object?>? dictionary(Uint8List bytes) {
    if (bytes.length < 40 || ascii.decode(bytes.sublist(0, 8), allowInvalid: true) != 'bplist00') return null;
    final data = ByteData.sublistView(bytes);
    final trailer = bytes.length - 32;
    final offsetSize = bytes[trailer + 6], refSize = bytes[trailer + 7];
    final count = data.getUint64(trailer + 8), top = data.getUint64(trailer + 16), table = data.getUint64(trailer + 24);
    if (offsetSize < 1 || offsetSize > 8 || refSize < 1 || refSize > 8 || count < 1 || count > 4096 || top >= count || table + count * offsetSize > trailer) return null;

    int number(int at, int size) {
      if (at < 0 || at + size > bytes.length) throw const FormatException('cut short');
      var value = 0;
      for (var i = 0; i < size; i += 1) {
        value = (value << 8) | bytes[at + i];
      }
      return value;
    }

    int offsetOf(int index) {
      if (index >= count) throw const FormatException('no such object');
      return number(table + index * offsetSize, offsetSize);
    }

    /// The count in an object's first byte, or the whole number after it when that byte says fifteen.
    (int, int) sized(int at) {
      final low = bytes[at] & 0x0f;
      if (low != 0x0f) return (low, at + 1);
      final size = 1 << (bytes[at + 1] & 0x0f);
      return (number(at + 2, size), at + 2 + size);
    }

    Object? object(int index) {
      final at = offsetOf(index);
      if (at >= trailer) throw const FormatException('past the end');
      switch (bytes[at] >> 4) {
        case 0x1:
          return number(at + 1, 1 << (bytes[at] & 0x0f));
        case 0x4:
          final (length, from) = sized(at);
          if (from + length > trailer) throw const FormatException('cut short');
          return Uint8List.fromList(Uint8List.sublistView(bytes, from, from + length));
        case 0x5:
          final (length, from) = sized(at);
          return ascii.decode(Uint8List.sublistView(bytes, from, from + length));
        case 0x6:
          final (length, from) = sized(at);
          return String.fromCharCodes([for (var i = 0; i < length; i += 1) number(from + i * 2, 2)]);
        default:
          return null;
      }
    }

    final at = offsetOf(top);
    if (bytes[at] >> 4 != 0xd) return null;
    final (pairs, from) = sized(at);
    final out = <String, Object?>{};
    for (var i = 0; i < pairs; i += 1) {
      final name = object(number(from + i * refSize, refSize));
      if (name is String) out[name] = object(number(from + (pairs + i) * refSize, refSize));
    }
    return out;
  }
}
