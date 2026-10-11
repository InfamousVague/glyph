/// The Ed25519 public keys this app accepts an update from: what `tauri/src-tauri/ota-trusted-keys.txt` is to
/// the Tauri app, compiled in the same way (this file is in the APK, and the APK is signed).
///
/// One raw 32-byte key to a line, base64, as that file holds them. A release is accepted if ANY key here signed
/// its `apk.json` (native/src/kept/updates.rs), which is how a key is rotated: ship a build that lists the old key
/// and the new one, move signing to the new key, and drop the old line in a later build. Removing a key from here
/// does not revoke it for builds already installed.
///
/// **It holds Ghost.md's own key**, the one line of that file (added there 2026-09-12): the owner's choice,
/// 2026-10-11, since this app is to replace the Tauri app as its next version ("updates use the original's update
/// signing key and release address"; docs/CUTOVER.md). Its private half is outside every repository
/// (`~/.config/glyph/ota-signing-key.pem`, tauri/scripts/ota-sign.mjs). A key alone turns nothing on: a build
/// still looks only where it was told to (lib/core/updates.dart `UpdatesConfig`), and what this app accepts is a
/// description signed for THIS app (`apk.json.flutter.sig`), which the Tauri app's own signature is not.
library;

const List<String> trustedUpdateKeys = <String>[
  '+lGP9TU8jcvUCrDjPwD5W33HsJn/Bhxm3gH4TK5CvkM=', // Ghost.md's, tauri/src-tauri/ota-trusted-keys.txt
];
