/// The account's cryptography, as the Rust core does it (native/src/crypto.rs, docs/STAGE7.md "Crypto"): the answer
/// to crypto_api.dart's ask. [CoreCrypto] is an [AccountCrypto] over a [CoreInvoke], so everything written against
/// the interface (account.dart, enc_key.dart, lib/sync/feed.dart) takes it where a test takes the fake.
///
/// What is the core's and what is this file's:
///
/// - **The core holds every key.** A [KeyHandle] here is a number naming a key in the core's table, with whether it
///   is extractable. The bytes stay there, except an organization's key where the interface (as the web) passes one
///   as bytes: [wrapFor], [unwrapWith], [importSealKey]. [newOrgKey], [wrapOrgKey] and [unwrapOrgKey] do the same
///   without the bytes ever reaching Dart, for a caller that needs no more.
/// - **The wire is the web's**, held to it by fixtures the web code wrote and opens (tool/crypto_vectors.mjs,
///   native/tests/crypto_vectors.rs): what this seals the Mac opens, and the reverse.
/// - **JSON is written and read here** ([seal], [open]): `jsonEncode` then the core seals the text, as the page's
///   `seal` is `JSON.stringify` then `sealBytes`.
/// - **Random words that need no key are Dart's** ([randomBytes], [shortId], [newRecoveryCode]): the interface has
///   them answer at once, and `Random.secure` is the system's generator, as the core's is.
///
/// **A long call does not hold up the notes.** The app asks its core through one worker isolate, one command at a
/// time (ghost_worker.dart), so 600,000 rounds of PBKDF2 asked there would keep `list_notes` waiting behind it.
/// The crypto commands take no lock of the library's, so they are safe from any thread: [CoreCrypto.withLane] starts a
/// SECOND worker isolate on the same loaded library and sends the long ones there ([derive], [newSheet],
/// [sealFile], [openFile], [digestFile]); a key made on one lane is the same key on the other, since the table is
/// the process's. Given only one [CoreInvoke] (a test's fake, or `CoreCrypto(core.invoke)`), everything goes down
/// it.
///
/// **What a device keeps.** [keep] writes a key down for the phone's secure storage and [restore] raises it again
/// at launch (keystore.dart's ask): the account key, the device key and the pair. Nothing else is ever written
/// down. A handle let go by Dart is forgotten by the core too.
///
/// ```dart
/// final crypto = await CoreCrypto.withLane(core);        // the app: a lane of its own for long calls
/// final derived = await crypto.derive(password, passwordSalt(handle));
/// final key = await crypto.unwrap(wrapped, derived.wrapKey);
/// final note = await crypto.open(key, blob, 'note:$id');
/// ```
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../core/bytes.dart';
import '../core/native/core.dart';
import '../core/native/ghost_core.dart';
import 'crypto_api.dart';

/// A key the core holds: its number there, what it is (`wrap`, `account`, `org`, `device`, `pair`), and whether it
/// may be wrapped or exported.
class CoreKey implements KeyHandle, WrapKey, SealKey, DeviceKey, EncryptionKey {
  CoreKey._(this.handle, this.kind, this.extractable, {this.publicKey});

  /// The key's number in the core's table. Never used twice in a process.
  final int handle;

  /// What the key is for; the core checks it wherever the key is used.
  final String kind;

  @override
  final bool extractable;

  /// A device key's or a pair's public half, base64url, as the core said it when the key was made.
  final String? publicKey;

  @override
  String toString() => 'CoreKey($kind #$handle${extractable ? ', extractable' : ''})';
}

/// A key written down for the phone's secure storage ([CoreCrypto.keep]): which key, and its bytes as base64url.
/// The two strings are all a keystore needs to hold.
class KeptKey {
  const KeptKey({required this.kind, required this.raw});

  /// `account`, `device` or `pair`.
  final String kind;
  final String raw;

  Map<String, Object?> toJson() => {'kind': kind, 'raw': raw};

  /// What [toJson] wrote, or null for anything else.
  static KeptKey? fromJson(Object? value) {
    if (value is! Map) return null;
    final kind = value['kind'], raw = value['raw'];
    return kind is String && raw is String ? KeptKey(kind: kind, raw: raw) : null;
  }
}

/// What a share holds (`Shared`, share/share.ts): its words as the JSON the web writes, and its pictures by name.
class OpenedShare {
  const OpenedShare({required this.shared, required this.pictures});

  /// `{v, kind, title, pages, at}`.
  final Map<String, Object?> shared;

  /// The pictures its pages show, in the order the share carried them.
  final Map<String, Uint8List> pictures;
}

/// [AccountCrypto] by the Rust core. See the header.
class CoreCrypto implements AccountCrypto, UnwrapsBytes {
  /// Over [quick], with the long calls sent down [slow] when there is one.
  CoreCrypto(CoreInvoke quick, {CoreInvoke? slow, Random? random})
    : _quick = quick,
      _slow = slow ?? quick,
      _random = random ?? Random.secure(),
      _lane = null {
    _forgetting = Finalizer<int>(_forget);
  }

  CoreCrypto._lane(this._quick, GhostCore lane) : _slow = lane.invoke, _random = Random.secure(), _lane = lane {
    _forgetting = Finalizer<int>(_forget);
  }

  /// The app's: [core] for everything quick, and a second worker isolate on the same library for the long calls.
  /// [libraryPath] is a test's (`native/target/debug/libghost_core.dylib`). [close] ends the second worker.
  ///
  /// The lane is opened deaf (`hears: false`): the core has one listener for its events, and a lane that took it
  /// left [core] hearing nothing, so no job the app started ever ended in a build with an account.
  static Future<CoreCrypto> withLane(GhostCore core, {String? libraryPath}) async {
    return CoreCrypto._lane(core.invoke, await GhostCore.open(libraryPath: libraryPath, hears: false));
  }

  final CoreInvoke _quick;
  final CoreInvoke _slow;
  final Random _random;
  final GhostCore? _lane;
  late final Finalizer<int> _forgetting;

  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Ends the lane [withLane] started. The keys stay in the core: another [CoreCrypto] may be given their handles.
  Future<void> close() async => _lane?.close();

  void _forget(int handle) {
    _quick('key_forget', {'key': handle}).then((_) {}, onError: (Object _) {});
  }

  CoreKey _key(Object? answer, String kind, {bool extractable = false}) {
    final said = answer as Map;
    final key = CoreKey._(said['key'] as int, kind, extractable, publicKey: said['public'] as String?);
    _forgetting.attach(key, key.handle, detach: key);
    return key;
  }

  /// [key] as one of the core's, of one of [kinds]; anything else was made by another crypto, or for another use.
  int _own(KeyHandle key, [List<String> kinds = const []]) {
    if (key is! CoreKey) throw ArgumentError('That key was not made by the core.');
    if (kinds.isNotEmpty && !kinds.contains(key.kind)) throw ArgumentError('A ${key.kind} key is not ${kinds.join(' or ')}.');
    return key.handle;
  }

  // --- secrets --------------------------------------------------------------------------------------------------

  @override
  Future<Derived> derive(String secret, String salt, {int iterations = rounds}) async {
    final said = await _slow('derive', {'secret': secret, 'salt': salt, 'rounds': iterations}) as Map;
    return Derived(login: said['login'] as String, wrapKey: _key({'key': said['wrapKey']}, 'wrap'));
  }

  // --- the account key ------------------------------------------------------------------------------------------

  @override
  Future<SealKey> newAccountKey() async => _key(await _quick('account_key_new'), 'account', extractable: true);

  @override
  Future<String> wrap(SealKey accountKey, WrapKey wrapKey) async {
    return await _quick('account_key_wrap', {'key': _own(accountKey, const ['account']), 'wrapKey': _own(wrapKey, const ['wrap'])}) as String;
  }

  @override
  Future<SealKey> unwrap(String wrapped, WrapKey wrapKey, {bool extractable = false}) async {
    final said = await _quick('account_key_unwrap', {'wrapped': wrapped, 'wrapKey': _own(wrapKey, const ['wrap']), 'extractable': extractable});
    return _key(said, 'account', extractable: extractable);
  }

  @override
  Future<SealKey> settle(SealKey accountKey) async {
    if (!accountKey.extractable) return accountKey;
    return _key(await _quick('key_settle', {'key': _own(accountKey, const ['account'])}), 'account');
  }

  @override
  Future<SealKey> importSealKey(Uint8List raw) async => _key(await _quick('seal_key_import', {'raw': toBase64Url(raw)}), 'org');

  // --- sealed blobs ---------------------------------------------------------------------------------------------

  @override
  Future<Uint8List> sealBytes(SealKey key, Uint8List bytes, String context) async {
    return fromBase64Url(await _quick('seal', {'key': _own(key, const ['account', 'org']), 'context': context, 'data': toBase64Url(bytes)}) as String);
  }

  @override
  Future<Uint8List> openBytes(SealKey key, Uint8List sealed, String context) async {
    final said = await _quick('open', {'key': _own(key, const ['account', 'org']), 'context': context, 'blob': toBase64Url(sealed), 'as': 'data'});
    return fromBase64Url(said as String);
  }

  @override
  Future<String> seal(SealKey key, Object? value, String context) async {
    return await _quick('seal', {'key': _own(key, const ['account', 'org']), 'context': context, 'text': jsonEncode(value)}) as String;
  }

  @override
  Future<Object?> open(SealKey key, String blob, String context) async {
    final text = await _quick('open', {'key': _own(key, const ['account', 'org']), 'context': context, 'blob': blob, 'as': 'text'});
    return jsonDecode(text as String);
  }

  // --- recovery codes -------------------------------------------------------------------------------------------

  @override
  String newRecoveryCode() {
    final picks = String.fromCharCodes([for (var i = 0; i < 12; i += 1) _alphabet.codeUnitAt(_random.nextInt(256) & 31)]);
    return '${picks.substring(0, 4)}-${picks.substring(4, 8)}-${picks.substring(8, 12)}';
  }

  @override
  Future<RecoverySheet> newSheet(String handle, SealKey accountKey, {int iterations = rounds}) async {
    final said = await _slow('recovery_sheet', {'handle': handle, 'key': _own(accountKey, const ['account']), 'rounds': iterations}) as Map;
    return RecoverySheet(
      codes: [for (final code in said['codes'] as List) code as String],
      entries: [for (final entry in said['entries'] as List) SheetEntry(login: (entry as Map)['login'] as String, wrapped: entry['wrapped'] as String)],
    );
  }

  // --- the device key -------------------------------------------------------------------------------------------

  @override
  Future<DeviceKey> newDeviceKey() async => _key(await _quick('device_key_new'), 'device');

  @override
  Future<String> publicKeyOf(DeviceKey pair) async {
    _own(pair, const ['device']);
    return (pair as CoreKey).publicKey ?? await _quick('key_public', {'key': pair.handle}) as String;
  }

  @override
  Future<String> signNonce(DeviceKey pair, String nonce) async {
    return await _quick('device_key_sign', {'key': _own(pair, const ['device']), 'nonce': nonce}) as String;
  }

  // --- the encryption pair --------------------------------------------------------------------------------------

  @override
  Future<EncryptionKey> newEncryptionKey() async => _key(await _quick('pair_new'), 'pair', extractable: true);

  @override
  Future<String> encryptionPublicKeyOf(EncryptionKey pair) async {
    _own(pair, const ['pair']);
    return (pair as CoreKey).publicKey ?? await _quick('key_public', {'key': pair.handle}) as String;
  }

  @override
  Future<Map<String, Object?>> exportPrivateKey(EncryptionKey pair) async {
    return (await _quick('pair_export_jwk', {'key': _own(pair, const ['pair'])}) as Map).cast<String, Object?>();
  }

  @override
  Future<EncryptionKey> importEncryptionKey(Map<String, Object?> jwk) async => _key(await _quick('pair_import_jwk', {'jwk': jwk}), 'pair');

  @override
  Future<EncryptionKey> settleEncryptionKey(EncryptionKey pair) async {
    if (!pair.extractable) return pair;
    final said = await _quick('key_settle', {'key': _own(pair, const ['pair'])}) as Map;
    return _key({'key': said['key'], 'public': (pair as CoreKey).publicKey}, 'pair');
  }

  @override
  Future<String> wrapFor(String pub, Uint8List orgKey, String context) async {
    return await _quick('wrap_for', {'public': pub, 'raw': toBase64Url(orgKey), 'context': context}) as String;
  }

  @override
  Future<Uint8List> unwrapWith(EncryptionKey pair, String wrapped, String context) async {
    return fromBase64Url(await _quick('unwrap_with', {'pair': _own(pair, const ['pair']), 'wrapped': wrapped, 'context': context}) as String);
  }

  @override
  Future<Uint8List> unwrapBytesWith(EncryptionKey pair, String wrapped, String context) async {
    return fromBase64Url(await _quick('unwrap_bytes_with', {'pair': _own(pair, const ['pair']), 'wrapped': wrapped, 'context': context}) as String);
  }

  // --- randomness and digests -----------------------------------------------------------------------------------

  @override
  Uint8List randomBytes(int count) => Uint8List.fromList([for (var i = 0; i < count; i += 1) _random.nextInt(256)]);

  @override
  String shortId() => toBase64Url(randomBytes(16));

  @override
  Future<Uint8List> sha256(Uint8List bytes) async => fromBase64Url(await _quick('sha256', {'data': toBase64Url(bytes)}) as String);

  // --- beyond the interface: what only a device with files and a keystore asks ---------------------------------

  /// The first sixteen bytes of [bytes]' SHA-256 as hex: what sync remembers a file by (core/sync/notes.ts `sha`).
  Future<String> sha16(Uint8List bytes) async => await _quick('sha256_16', {'data': toBase64Url(bytes)}) as String;

  /// [sha16] of the file at [path], read by the core where it lies; null where there is none.
  Future<String?> digestFile(String path) async => await _slow('digest_file', {'path': path}) as String?;

  /// The file at [path] sealed into the file at [out], in the wire's own bytes (what a `PUT` of a file carries),
  /// without either crossing to Dart: an hour's recording is read, sealed and written by the core. Answers the
  /// sealed file's length.
  Future<int> sealFile(SealKey key, String context, {required String path, required String out}) async {
    final said = await _slow('seal_file', {'key': _own(key, const ['account', 'org']), 'context': context, 'path': path, 'out': out}) as Map;
    return said['bytes'] as int;
  }

  /// The sealed file at [path] (a `GET`'s body, as it arrived) opened into the file at [out]. Nothing is written
  /// unless the whole of it is what was sealed. Answers the opened file's length.
  Future<int> openFile(SealKey key, String context, {required String path, required String out}) async {
    final said = await _slow('open_file', {'key': _own(key, const ['account', 'org']), 'context': context, 'path': path, 'out': out}) as Map;
    return said['bytes'] as int;
  }

  /// [key] written down for the phone's secure storage: the account key, the device key or the pair, and no
  /// other. What it answers is the key itself: it goes into Keystore-backed storage and nowhere else.
  Future<KeptKey> keep(KeyHandle key) async {
    final said = await _quick('key_keep', {'key': _own(key, const ['account', 'device', 'pair'])}) as Map;
    return KeptKey(kind: said['kind'] as String, raw: said['raw'] as String);
  }

  /// A key raised again from what [keep] wrote, at launch: not extractable, as a device keeps one.
  Future<CoreKey> restore(KeptKey kept) async => _key(await _quick('key_restore', kept.toJson()), kept.kind);

  /// [restore] for each of the three, by the names keystore.dart keeps them under.
  Future<SealKey> restoreAccountKey(String raw) => restore(KeptKey(kind: 'account', raw: raw));
  Future<DeviceKey> restoreDeviceKey(String raw) => restore(KeptKey(kind: 'device', raw: raw));
  Future<EncryptionKey> restoreEncryptionKey(String raw) => restore(KeptKey(kind: 'pair', raw: raw));

  /// Lets [key] go now, where waiting for Dart to notice would leave it in the core's table.
  Future<void> forget(KeyHandle key) async {
    final handle = _own(key);
    _forgetting.detach(key);
    await _quick('key_forget', {'key': handle});
  }

  /// Signing out: every key the core holds, whoever holds its handle.
  Future<void> forgetAll() async {
    await _quick('keys_forget');
  }

  /// The pair's private half sealed under the account key in one step (encKey.ts's `seal(accountKey,
  /// exportPrivateKey(made), 'encryption-key')`), the JWK never reaching Dart.
  Future<String> sealEncryptionKey(EncryptionKey pair, SealKey accountKey) async {
    return await _quick('pair_seal', {'key': _own(pair, const ['pair']), 'accountKey': _own(accountKey, const ['account'])}) as String;
  }

  /// The pair another device registered, out of what the service holds, in one step.
  Future<EncryptionKey> openEncryptionKey(String sealed, SealKey accountKey) async {
    return _key(await _quick('pair_open', {'sealed': sealed, 'accountKey': _own(accountKey, const ['account'])}), 'pair');
  }

  /// A new organization key, held by the core.
  Future<SealKey> newOrgKey() async => _key(await _quick('org_key_new'), 'org');

  /// [orgKey] wrapped for the member whose public key is [pub], its bytes never reaching Dart.
  Future<String> wrapOrgKey(SealKey orgKey, String pub, String context) async {
    return await _quick('org_key_wrap', {'key': _own(orgKey, const ['org']), 'public': pub, 'context': context}) as String;
  }

  /// The organization key out of [wrapped], straight to a key that seals.
  Future<SealKey> unwrapOrgKey(EncryptionKey pair, String wrapped, String context) async {
    return _key(await _quick('org_key_unwrap', {'pair': _own(pair, const ['pair']), 'wrapped': wrapped, 'context': context}), 'org');
  }

  /// A share's key: 32 random bytes as base64url, carried in the link and nowhere else (`newShareKey`).
  String newShareKey() => toBase64Url(randomBytes(32));

  /// [shared] sealed under a share's own [key] (`sealShare`): its JSON alone, or with [pictures] the `GSP1`
  /// layout. [pictureFiles] are pictures read by the core from where they are kept, by name.
  Future<String> sealShare(String key, Map<String, Object?> shared, {Map<String, Uint8List> pictures = const {}, Map<String, String> pictureFiles = const {}}) async {
    return await _quick('share_seal', {
          'key': key,
          'shared': shared,
          'pictures': [for (final MapEntry(key: name, value: bytes) in pictures.entries) [name, toBase64Url(bytes)]],
          'pictureFiles': [for (final MapEntry(key: name, value: path) in pictureFiles.entries) [name, path]],
        })
        as String;
  }

  /// A share opened with the key from its link (`openShare`).
  Future<OpenedShare> openShare(String key, String blob) async {
    final said = await _quick('share_open', {'key': key, 'blob': blob}) as Map;
    return OpenedShare(
      shared: (said['shared'] as Map).cast<String, Object?>(),
      pictures: {for (final picture in said['pictures'] as List) (picture as List)[0] as String: fromBase64Url(picture[1] as String)},
    );
  }
}
