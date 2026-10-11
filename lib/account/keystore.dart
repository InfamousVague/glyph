/// Where a device keeps what makes it a signed-in device (docs/SYNC.md): the session token, and three keys - the
/// account key that opens every synced note, this device's own signing key for password-free sign-in, and the
/// account's encryption key pair. A port of `src/app/core/account/keystore.ts`.
///
/// What differs:
/// - The page keeps the session in `localStorage` (`readSession`, `writeSession`) and the keys in IndexedDB; here
///   all four are one [KeyStore], since on a phone all four belong in the same place (docs/STAGE7.md: "keys and the
///   session token in Keystore-backed secure storage"). So the session is read with a wait, and [Account]
///   (account.dart) holds what it read.
/// - The keys are the crypto's handles (crypto_api.dart), not `CryptoKey` objects.
/// - [MemoryKeyStore] is the web's `memoryKeys()`. Given a [Stored] it keeps the session there under the web's own
///   key, `glyph-account-session`, as the page does: that is the browser's arrangement, for tests and for a build
///   with no secure storage yet, and NOT what a phone should ship.
///
/// THE DEVICE'S OWN (not built here: it needs a dependency this stage's Dart may not add). A `KeyStore` over the
/// platform's secure storage - on Android, values encrypted under a key held in the Android Keystore
/// (EncryptedSharedPreferences, or the `flutter_secure_storage` plugin over it), never plain SharedPreferences and
/// never a file in the library folder, which the backup copies. It must:
/// - keep the session as the JSON of [Session.toJson] under `glyph-account-session`, and read it back only whole
///   ([Session.fromJson]);
/// - keep each key in whatever form the real crypto can give and take back across launches. The page's IndexedDB
///   stores the non-extractable `CryptoKey` itself; the Rust core has no such thing, so its `lib/account/crypto.dart`
///   must offer a way to write a handle down for the keystore and to raise a handle from what was written (the raw
///   key, guarded by the Keystore-held key, is the plain way), under the names `account`, `device`, `encryption`;
/// - forget a key when it is set to null, and answer null, never throw, for one it does not hold or cannot read: a
///   device that cannot remember is signed out, not broken (lib/core/stored.dart has the same rule).
library;

import '../core/stored.dart';
import 'crypto_api.dart';
import 'session.dart';

/// The key the page keeps its session under (`SESSION_KEY`).
const String sessionKey = 'glyph-account-session';

/// What makes this device a signed-in one (`KeyStore`, with the session beside the keys).
abstract interface class KeyStore {
  /// The session kept, or null: signed out, or kept in a shape that is not whole (`readSession`).
  Future<Session?> session();

  /// Keeps the session; null forgets it (`writeSession`).
  Future<void> setSession(Session? session);

  Future<SealKey?> accountKey();
  Future<void> setAccountKey(SealKey? key);

  Future<DeviceKey?> deviceKey();
  Future<void> setDeviceKey(DeviceKey? pair);

  /// The account's encryption key pair (docs/SHARED.md, S3), kept as the account key is; null until this device has
  /// it.
  Future<EncryptionKey?> encryptionKey();
  Future<void> setEncryptionKey(EncryptionKey? pair);
}

/// The session as the page's `localStorage` holds it, read from a [Stored] (`readSession`).
Session? readSession(Stored kept) => kept.read<Session?>(sessionKey, null, Session.fromJson);

/// Keeps the session in a [Stored]; null removes it (`writeSession`). No storage: signed in for as long as the app
/// is open.
void writeSession(Stored kept, Session? session) => kept.write(sessionKey, session?.toJson());

/// Everything held in memory (`memoryKeys`): for tests, and for a device with nowhere safe to keep a key, which is
/// then signed in until the app closes. With [kept], the session alone is kept there, as the page keeps it.
class MemoryKeyStore implements KeyStore {
  MemoryKeyStore({Stored? kept}) : _kept = kept;

  final Stored? _kept;
  Session? _session;
  SealKey? _account;
  DeviceKey? _device;
  EncryptionKey? _encryption;

  @override
  Future<Session?> session() async => _kept != null ? readSession(_kept) : _session;

  @override
  Future<void> setSession(Session? session) async {
    if (_kept != null) {
      writeSession(_kept, session);
    } else {
      _session = session;
    }
  }

  @override
  Future<SealKey?> accountKey() async => _account;

  @override
  Future<void> setAccountKey(SealKey? key) async => _account = key;

  @override
  Future<DeviceKey?> deviceKey() async => _device;

  @override
  Future<void> setDeviceKey(DeviceKey? pair) async => _device = pair;

  @override
  Future<EncryptionKey?> encryptionKey() async => _encryption;

  @override
  Future<void> setEncryptionKey(EncryptionKey? pair) async => _encryption = pair;
}
