/// The web build's [SecureStore] (docs/WEB.md): this site's `localStorage`, where the phone has its Keystore and the
/// Mac its Keychain. Only in the web build; page_secure_stub.dart stands in elsewhere.
///
/// A page has nothing closer to a keychain that it can write: what is kept here (the session, the account's keys as
/// the core writes them down, a plugin's token) is this site's alone, read by no other, and gone when the person
/// signs out or clears the site's data. It is the same storage the old web app kept its session in. Synchronous,
/// so a plugin's secrets are read before the first screen as they are on the phone.
library;

import 'package:web/web.dart' as web;

import '../account/device_keys.dart' show SecureStore;

/// Every name is kept under this, beside the preferences' own `flutter.` keys and the old page's `glyph-` ones.
const String _prefix = 'ghost-secure:';

class PageSecureStore implements SecureStore {
  const PageSecureStore();

  @override
  Future<String?> read(String name) async {
    try {
      return web.window.localStorage.getItem('$_prefix$name');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String name, String? value) async {
    try {
      if (value == null) {
        web.window.localStorage.removeItem('$_prefix$name');
      } else {
        web.window.localStorage.setItem('$_prefix$name', value);
      }
    } catch (_) {
      // Storage refused (a private window, or full): kept for nobody, as a phone whose Keystore refused.
    }
  }
}

SecureStore pageSecureStore() => const PageSecureStore();
