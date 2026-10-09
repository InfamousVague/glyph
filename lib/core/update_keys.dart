/// The Ed25519 public keys this app accepts an update from: what `../glyph/src-tauri/ota-trusted-keys.txt` is to
/// the Tauri app, compiled in the same way (this file is in the APK, and the APK is signed).
///
/// One raw 32-byte key to a line, base64, as that file holds them. A release is accepted if ANY key here signed
/// its `apk.json` (native/src/kept/updates.rs), which is how a key is rotated: ship a build that lists the old key
/// and the new one, move signing to the new key, and drop the old line in a later build. Removing a key from here
/// does not revoke it for builds already installed.
///
/// **It is empty, and an empty list means no update check at all** (lib/core/updates.dart `UpdatesConfig`): which
/// key signs this app's releases is the owner's to decide, and none has been made for it. tool/release.md says
/// what the choice is and where the Tauri app keeps its own.
library;

const List<String> trustedUpdateKeys = <String>[];
