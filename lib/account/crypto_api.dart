/// The keys and the ciphertext of end-to-end encrypted sync (docs/SYNC.md, "Keys"; docs/STAGE7.md, "Crypto"), as the
/// Dart side asks for them. The function list of `src/app/core/sync/crypto.ts` and of `src/app/core/orgs/wrap.ts`,
/// one method each, by the web's names.
///
/// This file is the ASK, not the answer. The answer is the Rust core's (PBKDF2-HMAC-SHA-256, AES-256-GCM, Ed25519,
/// ECDH P-256 with HKDF), behind the FFI with keys held by handle, in `lib/account/crypto.dart`; that file adapts
/// itself to [AccountCrypto]. Everything else in the account's stage - the flows (account.dart), the encryption pair
/// (enc_key.dart), the notifications feed (lib/sync/feed.dart) - takes an [AccountCrypto] and never names an
/// algorithm. The tests' one is `test/support/fake_crypto.dart`, which is NOT cryptography.
///
/// What differs from the web:
/// - A key is an opaque handle ([WrapKey], [SealKey], [DeviceKey], [EncryptionKey]), not a `CryptoKey`: the bytes
///   stay on the far side of the FFI, as WebCrypto keeps a non-extractable key's on the far side of its own. A handle
///   says only whether it is [KeyHandle.extractable], which is what the page's code reads off a `CryptoKey` too.
/// - WebCrypto's `importKey('raw', …, 'AES-GCM')`, written out where an organization's key or a share's is taken up
///   (core/orgs/orgKeys.ts, share/share.ts), is [AccountCrypto.importSealKey]; `crypto.getRandomValues` is
///   [AccountCrypto.randomBytes]; `crypto.subtle.digest('SHA-256')` (core/sync/notes.ts `sha`) is
///   [AccountCrypto.sha256].
/// - `publicKeyOf` is two functions on the web, one in each module, told apart by the import; here they are
///   [AccountCrypto.publicKeyOf] (the device's signing key) and [AccountCrypto.encryptionPublicKeyOf].
/// - The salts, the code's normal form and the round count are plain words and are in this file as functions
///   ([passwordSalt], [recoverySalt], [normaliseCode], [rounds]), so both implementations salt alike.
library;

import 'dart:typed_data';

/// OWASP's floor for PBKDF2-SHA-256 as of 2023 (`ROUNDS`). The real number, except in tests.
const int rounds = 600000;

/// How many codes a recovery sheet holds (`CODES`).
const int recoveryCodes = 8;

/// What a password is salted with: the handle, the way the person types it, lower-cased (`passwordSalt`).
String passwordSalt(String handle) => 'glyph/v1/${handle.trim().toLowerCase()}';

/// What a recovery code is salted with (`recoverySalt`).
String recoverySalt(String handle) => 'glyph/v1/recovery/${handle.trim().toLowerCase()}';

/// A recovery code as it is compared: letters and digits only, upper case, so dashes and case do not matter
/// (`normaliseCode`).
String normaliseCode(String code) => code.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toUpperCase();

/// The context a member's wrap of an organization key is bound to (`wrapContext`, core/orgs/wrap.ts).
String wrapContext(String orgId, int generation) => 'org-key:$orgId:$generation';

/// A key held for this app by whoever does its cryptography: opaque, compared by identity, never read.
abstract interface class KeyHandle {
  /// Whether the key's bytes may be read out to be wrapped or sealed (`CryptoKey.extractable`). A device keeps only
  /// keys that are not.
  bool get extractable;
}

/// The half of a password or a recovery code that wraps and unwraps the account key. Never leaves the device.
abstract interface class WrapKey implements KeyHandle {}

/// A key that seals and opens: the account key, an organization's key at one generation, a share's key.
abstract interface class SealKey implements KeyHandle {}

/// This device's signing key for password-free sign-in: Ed25519, never extractable.
abstract interface class DeviceKey implements KeyHandle {}

/// The account's encryption key pair (docs/SHARED.md, S3): ECDH on P-256. [extractable] is its private half's.
abstract interface class EncryptionKey implements KeyHandle {}

/// The two halves of a secret (`Derived`).
class Derived {
  const Derived({required this.login, required this.wrapKey});

  /// Sent to the service in place of the secret: 64 hex characters.
  final String login;

  /// Wraps and unwraps the account key.
  final WrapKey wrapKey;
}

/// What the service keeps for one recovery code (`SheetEntry`): its login half, and the account key wrapped under it.
class SheetEntry {
  const SheetEntry({required this.login, required this.wrapped});
  final String login;
  final String wrapped;

  Map<String, Object?> toJson() => {'login': login, 'wrapped': wrapped};
}

/// A recovery sheet (`newSheet`'s answer): the codes, shown to the person once and never sent, and what the service
/// keeps for each.
class RecoverySheet {
  const RecoverySheet({required this.codes, required this.entries});
  final List<String> codes;
  final List<SheetEntry> entries;
}

/// Every piece of cryptography the account's stage asks for. Each method names the web function it stands for; an
/// implementation answers exactly what that function answers, on the same wire (docs/STAGE7.md has the bytes).
///
/// Everything that can fail fails by throwing: a wrong password at [unwrap], a blob under another key, tampered
/// with, or moved from another context at [open] and [openBytes], another member's wrap at [unwrapWith]. What is
/// thrown is the implementation's own; callers catch anything.
abstract interface class AccountCrypto {
  // --- secrets --------------------------------------------------------------------------------------------------

  /// The two halves of a secret (`derive`): PBKDF2 over [secret] salted with [salt] ([passwordSalt] or
  /// [recoverySalt]), [iterations] rounds ([rounds] outside tests).
  Future<Derived> derive(String secret, String salt, {int iterations = rounds});

  // --- the account key ------------------------------------------------------------------------------------------

  /// A new account key, extractable so it can be wrapped (`newAccountKey`); kept on the device as [settle] leaves it.
  Future<SealKey> newAccountKey();

  /// The account key wrapped under [wrapKey], base64url (`wrap`). The key must be extractable.
  Future<String> wrap(SealKey accountKey, WrapKey wrapKey);

  /// The account key back out of [wrapped] (`unwrap`). Throws on the wrong password or code.
  Future<SealKey> unwrap(String wrapped, WrapKey wrapKey, {bool extractable = false});

  /// A non-extractable copy of an extractable account key, the form a device keeps (`settle`); the key itself when
  /// it already is one.
  Future<SealKey> settle(SealKey accountKey);

  /// A key that seals, from its 32 raw bytes, not extractable: an organization's key out of its wrap, a share's out
  /// of its link (WebCrypto's `importKey('raw', …, 'AES-GCM')`).
  Future<SealKey> importSealKey(Uint8List raw);

  // --- sealed blobs ---------------------------------------------------------------------------------------------

  /// [bytes] sealed under [key], bound to [context] (`sealBytes`): a recording, a picture, a versions file.
  Future<Uint8List> sealBytes(SealKey key, Uint8List bytes, String context);

  /// The bytes back out of a sealed blob (`openBytes`). Throws on the wrong key, a tampered blob, a blob moved from
  /// another context, or one sealed by a newer build.
  Future<Uint8List> openBytes(SealKey key, Uint8List sealed, String context);

  /// A JSON value sealed as base64url text (`seal`): what a note, the settings or a notification go to the service
  /// as. [value] is anything `jsonEncode` writes.
  Future<String> seal(SealKey key, Object? value, String context);

  /// The JSON value back out of [blob] (`open`), as `jsonDecode` reads it. Throws as [openBytes] does, and for text
  /// that is not base64url or bytes that are not JSON.
  Future<Object?> open(SealKey key, String blob, String context);

  // --- recovery codes -------------------------------------------------------------------------------------------

  /// One code, `XXXX-XXXX-XXXX`: sixty random bits in AttackFM's alphabet, with no 0/O or 1/I (`newRecoveryCode`).
  String newRecoveryCode();

  /// A recovery sheet for [handle] (`newSheet`): [recoveryCodes] new codes, and for each its login half and
  /// [accountKey], which must be extractable, wrapped under its wrap key.
  Future<RecoverySheet> newSheet(String handle, SealKey accountKey, {int iterations = rounds});

  // --- the device key -------------------------------------------------------------------------------------------

  /// This device's signing key (`newDeviceKey`).
  Future<DeviceKey> newDeviceKey();

  /// A device key's public half as the service keeps it: the raw 32 bytes, base64url (crypto.ts `publicKeyOf`).
  Future<String> publicKeyOf(DeviceKey pair);

  /// The service's challenge signed with this device's key, base64url (`signNonce`).
  Future<String> signNonce(DeviceKey pair, String nonce);

  // --- the encryption pair (core/orgs/wrap.ts) ------------------------------------------------------------------

  /// A fresh encryption key pair, extractable: its private half is exported once, to travel sealed to the account's
  /// other devices (`newEncryptionKey`).
  Future<EncryptionKey> newEncryptionKey();

  /// A pair's public key as the service keeps it: the raw 65-byte point, base64url (wrap.ts `publicKeyOf`).
  Future<String> encryptionPublicKeyOf(EncryptionKey pair);

  /// The private half as a JSON Web Key, to seal for the account's other devices (`exportPrivateKey`). The pair must
  /// be extractable.
  Future<Map<String, Object?>> exportPrivateKey(EncryptionKey pair);

  /// A pair back from its private half, as another device of the account keeps it: not extractable
  /// (`importEncryptionKey`).
  Future<EncryptionKey> importEncryptionKey(Map<String, Object?> jwk);

  /// The same pair, its private half no longer extractable: the form a device keeps (`settleEncryptionKey`).
  Future<EncryptionKey> settleEncryptionKey(EncryptionKey pair);

  /// [orgKey] wrapped for the member whose public key is [pub], bound to [context] ([wrapContext]): base64url
  /// (`wrapFor`).
  Future<String> wrapFor(String pub, Uint8List orgKey, String context);

  /// The organization key out of [wrapped], with this account's pair (`unwrapWith`). Throws on another's wrap, or
  /// another context.
  Future<Uint8List> unwrapWith(EncryptionKey pair, String wrapped, String context);

  // --- randomness and digests -----------------------------------------------------------------------------------

  /// [count] random bytes from the system's source (`crypto.getRandomValues`): a new organization key is 32.
  Uint8List randomBytes(int count);

  /// A short id: 16 random bytes as base64url, 22 characters (core/ids.ts `shortId`).
  String shortId();

  /// SHA-256 of [bytes], as 32 bytes (`crypto.subtle.digest`): a recording's fingerprint, a versions file's.
  Future<Uint8List> sha256(Uint8List bytes);
}
