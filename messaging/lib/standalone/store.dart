/// Where a device of its own keeps what it keeps (lib/standalone/standalone.dart, [StandaloneCalls]): one text of
/// JSON (the choices, the friends by username, the conversations), the key that is who this device is, and the
/// secrets kept by name beside it (the account's words, forward secrecy's prekeys, circles' keys).
///
/// On a computer and an iPhone it is a folder and the Keychain (store_files.dart, exactly as before there was this).
/// A browser has neither: there it is the page's own IndexedDB, the secrets sealed with a key the page can use and
/// not read out (lib/web/store_web.dart; Matt: "the full web client").
abstract class StandaloneStore {
  /// Made ready, before anything is read.
  Future<void> open();

  /// The JSON as it was last kept, or null where there is none yet.
  Future<String?> readState();

  /// Keeps [text] as the JSON, whole or not at all. Never two at once: whoever calls waits for one before the next.
  Future<void> writeState(String text);

  /// The key that is who this device is (64 hex digits), or null where there is none yet.
  Future<String?> readIdentity();

  /// Keeps [hex] as that key: one made here for a device that had none, or ([imported]) another put in its place as
  /// the device signs in to an account.
  Future<void> writeIdentity(String hex, {bool imported = false});

  /// The secret kept as [name], or null.
  Future<String?> readSecret(String name);

  /// Keeps [value] as [name].
  Future<void> writeSecret(String name, String value);

  /// Forgets what is kept as [name].
  Future<void> deleteSecret(String name);
}
