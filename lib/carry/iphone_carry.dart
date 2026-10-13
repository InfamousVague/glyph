/// The carry from the Tauri app on an iPhone (docs/CUTOVER.md §8): the Mac's carry (lib/carry/mac_carry.dart),
/// over the same ground one level in.
///
/// The build that replaces the Tauri iPhone app is that app's next version in the App Store, under its bundle id,
/// so an update leaves it in that app's own container with everything 1.10.0 kept still there. Tauri names its
/// folders on an iPhone as it does on a Mac, and the web view is the same WebKit, so inside the container the
/// layout is the Mac's `~/Library` file for file (seen in a simulator's container of the Tauri app, 2026-10-13):
///
/// | The Tauri app kept | where, under `<container>/Library` |
/// | --- | --- |
/// | the notes, their `.versions` files, the sidecars, the core's index | `Application Support/com.mattssoftware.glyph/Library/` |
/// | pictures | `Application Support/com.mattssoftware.glyph/images/` |
/// | `localStorage` (settings, workspaces, the session, the sync's cursors) | `WebKit/com.mattssoftware.glyph/WebsiteData/Default/<hash>/<hash>/LocalStorage/localstorage.sqlite3`, the origin `tauri://localhost` |
/// | the three keys, the team notes' documents | `…/<hash>/<hash>/IndexedDB/<hash>/IndexedDB.sqlite3`, each key wrapped under WebKit's master key |
/// | WebKit's master key | the Keychain: account `com.apple.WebKit.WebCrypto.master+com.mattssoftware.glyph`, the app's own access group |
///
/// An iPhone's Tauri app records nothing, runs no model and keeps no `slack.json` or `notion.json` (those commands
/// are not built for iOS, tauri/src-tauri/src/unsupported.rs), so `recordings/`, `video/` and `models/` are not
/// there to carry; if one ever is, it is carried as on a Mac. `Library/Preferences` is empty and `Documents` is
/// empty: the Tauri app keeps nothing in either.
///
/// **This app's own folder is beside the Tauri app's, never it**: `Application Support/com.mattssoftware.glyph.v2`
/// (ios/Runner/GhostChannels.swift `cutoverFolder`), for the Mac's reasons. So everything is COPIED, once, by the
/// Mac's three halves and under the Mac's rules: files first and whole (a clone on the phone's APFS, so a library
/// takes no second helping of the disk), then the settings read from copies of WebKit's SQLite files, then the
/// secrets, each key proven before it is believed. Nothing of the Tauri app's is written, moved or removed. The
/// same marker and log, in this app's folder: `carry/tauri-carry.json`, `carry/tauri-carry.log`.
library;

import '../account/device_keys.dart' show SecureStore;
import 'mac_carry.dart';
import 'tauri_carry.dart';

/// The whole carry for an iPhone. [ownDataDir] is this app's own folder in the container
/// (`<container>/Library/Application Support/com.mattssoftware.glyph.v2`), which must not be the Tauri app's or
/// inside it; the Tauri app's are found beside it, under the same `Library`. [standIn] is another folder to take
/// for that `Library`, for a test.
TauriCarry iPhoneCarry({required String ownDataDir, required CarryPrefs prefs, required SecureStore secure, MacCarryDevice device = const ChannelMacCarryDevice(), String? standIn, DateTime Function()? now}) =>
    macCarry(ownDataDir: ownDataDir, prefs: prefs, secure: secure, device: device, standIn: standIn, now: now, host: 'an iPhone');
