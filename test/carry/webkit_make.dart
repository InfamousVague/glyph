// Storage as a Mac's WebKit lays it out, made here so the Mac carry's tests need nothing that is not in git: the
// origin's folder, `localStorage`'s SQLite file, an IndexedDB file to a database, values in WebKit's serialisation
// and keys wrapped as WebKit wraps them (lib/carry/webkit_stores.dart says each form). It is held to the real
// thing by webkit_stores_test.dart, which reads a real WebKit's storage wherever tool/webkit_fixture.swift has
// been run, with the same reader.
//
// The SQLite files are written by the `sqlite3` every Mac has; the app itself only ever reads one.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ghost_md/carry/aes_unwrap.dart';

/// Whether this machine can make them.
bool get canMakeWebKit => Platform.isMacOS && File('/usr/bin/sqlite3').existsSync();
String? get webKitSkip => canMakeWebKit ? null : 'no /usr/bin/sqlite3 to make WebKit\'s files with';

Uint8List fromBase64Url(String text) => base64Url.decode(text.padRight((text.length + 3) & ~3, '='));
String toBase64Url(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');
String _hex(List<int> bytes) => bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
List<int> _u32(int value) => [value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff, (value >> 24) & 0xff];
List<int> _u64(int value) => [..._u32(value & 0xffffffff), ..._u32(value >> 32)];
List<int> _utf16(String text) => [for (final unit in text.codeUnits) ...[unit & 0xff, unit >> 8]];
List<int> _narrow(String text) => [..._u32(text.length | 0x80000000), ...latin1.encode(text)];

/// A value in WebKit's serialisation, without the version in front.
abstract final class Ssv {
  static List<int> object(Map<String, List<int>> properties) => [2, for (final entry in properties.entries) ...[..._narrow(entry.key), ...entry.value], 0xff, 0xff, 0xff, 0xff];
  static List<int> array(List<List<int>> values) => [1, ..._u32(values.length), for (var i = 0; i < values.length; i += 1) ...[..._u32(i), ...values[i]], ...List.filled(8, 0xff)];
  static List<int> number(int value) => value == 0 ? [6] : (value == 1 ? [7] : [5, ..._u32(value)]);
  static List<int> bytes(List<int> value) => [22, 2, ..._u64(0), ..._u64(value.length), 21, ..._u64(value.length), ...value];
  static List<int> cryptoKey(Uint8List wrapped) => [33, ..._u32(wrapped.length), ...wrapped];
  static Uint8List whole(List<int> value) => Uint8List.fromList([..._u32(15), ...value]);
}

/// A key's serialisation, as WebKit writes one before wrapping it.
abstract final class KeyBytes {
  static List<int> _head(bool extractable, List<int> usages) => [..._u32(15), ..._u32(1), extractable ? 1 : 0, ..._u32(usages.length), ...usages];

  /// AES-GCM, to encrypt and decrypt.
  static Uint8List aes(Uint8List raw, {bool extractable = false}) => Uint8List.fromList([..._head(extractable, [0, 1]), 1, 9, ..._u32(raw.length), ...raw]);

  /// ECDH on P-256: the private half as PKCS#8 with its public point inside, to derive bits.
  static Uint8List ecPrivate(Uint8List scalar, Uint8List point) {
    final pkcs8 = [
      0x30, 0x81, 0x87, 0x02, 0x01, 0x00, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, //
      0x04, 0x6d, 0x30, 0x6b, 0x02, 0x01, 0x01, 0x04, 0x20, ...scalar, 0xa1, 0x44, 0x03, 0x42, 0x00, ...point,
    ];
    return Uint8List.fromList([..._head(false, [5]), 3, 5, ..._narrow('P-256'), 1, ..._u32(pkcs8.length), ...pkcs8]);
  }

  static Uint8List ecPublic(Uint8List point) => Uint8List.fromList([..._head(true, []), 3, 5, ..._narrow('P-256'), 0, ..._u32(point.length), ...point]);

  /// Ed25519: the seed to sign with, or the public key to verify with.
  static Uint8List okp(Uint8List bytes, {required bool private}) => Uint8List.fromList([..._head(!private, [private ? 2 : 3]), 5, 22, 1, ..._u32(bytes.length), ...bytes]);
}

final Random _random = Random.secure();
Uint8List randomBytes(int length) => Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

/// [plain] wrapped as WebKit wraps a stored key under [masterKey]: a binary property list of four things.
Uint8List webKitWrap(Uint8List masterKey, Uint8List plain, {int version = 1}) {
  final kek = randomBytes(16);
  final made = aesGcmSeal(kek, Uint8List(0), plain);
  return _bplist({'encryptedKey': made.sealed, 'wrappedKEK': aesKeyWrap(masterKey, kek), 'tag': made.tag, 'version': version});
}

Uint8List _bplist(Map<String, Object> dictionary) {
  final objects = <List<int>>[];
  List<int> sized(int kind, int length) => length < 15 ? [kind | length] : [kind | 0x0f, 0x11, length >> 8, length & 0xff];
  final names = dictionary.keys.toList();
  objects.add([...sized(0xd0, names.length), for (var i = 0; i < names.length; i += 1) i + 1, for (var i = 0; i < names.length; i += 1) names.length + i + 1]);
  for (final name in names) {
    objects.add([...sized(0x50, name.length), ...ascii.encode(name)]);
  }
  for (final value in dictionary.values) {
    objects.add(value is int ? [0x10, value] : [...sized(0x40, (value as Uint8List).length), ...value]);
  }
  final out = BytesBuilder()..add(ascii.encode('bplist00'));
  final offsets = <int>[];
  for (final object in objects) {
    offsets.add(out.length);
    out.add(object);
  }
  final table = out.length;
  for (final offset in offsets) {
    out.add([offset >> 8, offset & 0xff]);
  }
  out.add([0, 0, 0, 0, 0, 0, 2, 1, ...List.filled(7, 0), objects.length, ...List.filled(8, 0), ...List.filled(6, 0), table >> 8, table & 0xff]);
  return out.toBytes();
}

/// The file WebKit leaves in an origin's folder to say whose it is.
Uint8List originFile(String scheme, String host) {
  final one = [..._u32(scheme.length), 1, ...latin1.encode(scheme), ..._u32(host.length), 1, ...latin1.encode(host), 0];
  return Uint8List.fromList([...one, ...one]);
}

void _sqlite(String file, List<String> statements) {
  final script = File('$file.sql')..writeAsStringSync('${statements.join(';\n')};\n');
  final ran = Process.runSync('/usr/bin/sqlite3', [file, '.read ${script.path}']);
  script.deleteSync();
  if (ran.exitCode != 0 || (ran.stderr as String).trim().isNotEmpty) throw StateError('sqlite3: ${ran.stderr}');
}

/// The names WebKit gives a database's folder do not matter to a reader, which goes by the name inside.
int _made = 0;

/// One origin's storage under [websiteData] (`…/WebsiteData`), as a Mac's WebKit keeps it: [local] in
/// `localStorage`, and each of [databases] (a name, its one store, and its records by their string keys, each a
/// whole serialised value).
Directory makeWebKit(Directory websiteData, {String scheme = 'tauri', String host = 'localhost', Map<String, String> local = const {}, List<({String name, String store, Map<String, Uint8List> records})> databases = const []}) {
  final hash = 'made${_made += 1}-${toBase64Url(randomBytes(12))}';
  final folder = Directory('${websiteData.path}/Default/$hash/$hash')..createSync(recursive: true);
  File('${websiteData.path}/Default/salt').writeAsBytesSync(randomBytes(8));
  File('${folder.path}/origin').writeAsBytesSync(originFile(scheme, host));
  Directory('${folder.path}/LocalStorage').createSync();
  _sqlite('${folder.path}/LocalStorage/localstorage.sqlite3', [
    'CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB NOT NULL ON CONFLICT FAIL)',
    for (final entry in local.entries) "INSERT INTO ItemTable VALUES ('${entry.key.replaceAll("'", "''")}', X'${_hex(_utf16(entry.value))}')",
  ]);
  for (final database in databases) {
    final at = Directory('${folder.path}/IndexedDB/${_hex(randomBytes(32)).toUpperCase()}')..createSync(recursive: true);
    _sqlite('${at.path}/IndexedDB.sqlite3', [
      // WebKit's own table has `key TEXT COLLATE IDBKEY` and an index over it; the collation is WebKit's, so
      // neither can be made here, and a reader may not lean on either.
      'CREATE TABLE Records (objectStoreID INTEGER NOT NULL ON CONFLICT FAIL, key TEXT NOT NULL ON CONFLICT FAIL, value NOT NULL ON CONFLICT FAIL, recordID INTEGER PRIMARY KEY)',
      'CREATE TABLE IDBDatabaseInfo (key TEXT NOT NULL ON CONFLICT FAIL UNIQUE ON CONFLICT REPLACE, value TEXT NOT NULL ON CONFLICT FAIL)',
      'CREATE TABLE ObjectStoreInfo (id INTEGER PRIMARY KEY NOT NULL ON CONFLICT FAIL UNIQUE ON CONFLICT FAIL, name TEXT NOT NULL ON CONFLICT FAIL UNIQUE ON CONFLICT FAIL, keyPath BLOB NOT NULL ON CONFLICT FAIL, autoInc INTEGER NOT NULL ON CONFLICT FAIL)',
      "INSERT INTO IDBDatabaseInfo VALUES ('MetadataVersion', '2')",
      // The name is UTF-16 in a text column, as WebKit leaves it.
      "INSERT INTO IDBDatabaseInfo VALUES ('DatabaseName', CAST(X'${_hex(_utf16(database.name))}' AS TEXT))",
      "INSERT INTO IDBDatabaseInfo VALUES ('DatabaseVersion', '1')",
      "INSERT INTO ObjectStoreInfo VALUES (41, 'another', X'00', 0)",
      "INSERT INTO ObjectStoreInfo VALUES (867, '${database.store}', X'00', 0)",
      "INSERT INTO Records (objectStoreID, key, value) VALUES (41, CAST(X'${_hex([0, 0x60, ..._u32(7), ..._utf16('account')])}' AS TEXT), X'${_hex(Ssv.whole(Ssv.number(3)))}')",
      for (final record in database.records.entries)
        "INSERT INTO Records (objectStoreID, key, value) VALUES (867, CAST(X'${_hex([0, 0x60, ..._u32(record.key.length), ..._utf16(record.key)])}' AS TEXT), X'${_hex(record.value)}')",
    ]);
  }
  return folder;
}

/// `glyph-account` as the page keeps it (tauri/src/app/core/account/keystore.ts), every key wrapped under
/// [masterKey]. A half left null is left out.
({String name, String store, Map<String, Uint8List> records}) accountDatabase(Uint8List masterKey, {Uint8List? account, ({Uint8List scalar, Uint8List point})? encryption, ({Uint8List seed, Uint8List public})? device}) => (
      name: 'glyph-account',
      store: 'keys',
      records: {
        if (account != null) 'account': Ssv.whole(Ssv.cryptoKey(webKitWrap(masterKey, KeyBytes.aes(account)))),
        if (encryption != null)
          'encryption': Ssv.whole(Ssv.object({
            'privateKey': Ssv.cryptoKey(webKitWrap(masterKey, KeyBytes.ecPrivate(encryption.scalar, encryption.point))),
            'publicKey': Ssv.cryptoKey(webKitWrap(masterKey, KeyBytes.ecPublic(encryption.point))),
          })),
        if (device != null)
          'device': Ssv.whole(Ssv.object({
            'privateKey': Ssv.cryptoKey(webKitWrap(masterKey, KeyBytes.okp(device.seed, private: true))),
            'publicKey': Ssv.cryptoKey(webKitWrap(masterKey, KeyBytes.okp(device.public, private: false))),
          })),
      },
    );

/// `glyph-team` (tauri/src/app/core/team/docs.ts): a document to a note.
({String name, String store, Map<String, Uint8List> records}) teamDatabase(Map<String, ({List<int> state, int seq, int snapshotSeq, List<List<int>> pending})> documents) => (
      name: 'glyph-team',
      store: 'docs',
      records: {
        for (final entry in documents.entries)
          entry.key: Ssv.whole(Ssv.object({
            'state': Ssv.bytes(entry.value.state),
            'seq': Ssv.number(entry.value.seq),
            'snapshotSeq': Ssv.number(entry.value.snapshotSeq),
            'pending': Ssv.array([for (final each in entry.value.pending) Ssv.bytes(each)]),
          })),
      },
    );

/// Every file under [folder], by its path from it: how long it is, when it was written, and its bytes' hash. Two
/// of these are equal exactly when nothing under the folder was written, added, removed or renamed between them.
Map<String, String> treeState(Directory folder) {
  final out = <String, String>{};
  if (!folder.existsSync()) return out;
  for (final entry in folder.listSync(recursive: true, followLinks: false)) {
    final name = entry.path.substring(folder.path.length);
    if (entry is File) {
      final bytes = entry.readAsBytesSync();
      var hash = 0xcbf29ce484222325;
      for (final byte in bytes) {
        hash = ((hash ^ byte) * 0x100000001b3) & 0x7fffffffffffffff;
      }
      out[name] = '${bytes.length} ${entry.lastModifiedSync().millisecondsSinceEpoch} $hash';
    } else {
      out[name] = entry is Directory ? 'folder' : 'link';
    }
  }
  return out;
}
