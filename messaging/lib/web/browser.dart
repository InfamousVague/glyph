/// What the app in a web page asks of the browser it is in (lib/web/main.dart; Matt: "the full web client"):
/// somewhere to keep things, being the only tab of itself, a link opened beside it, and starting again. The browser's
/// own answers are in browser_web.dart, the one file here that speaks to JavaScript; anywhere else there is no
/// browser to ask (browser_none.dart), and a test stands [MemoryBrowser] in.
library;

import 'dart:async';

import 'browser_none.dart' if (dart.library.js_interop) 'browser_web.dart' as platform;

/// What a page is called in the account's list of devices, from the browser's own description of itself
/// ([userAgent]): "Browser", then which one and on what where it says ("Browser · Safari · Mac"). A page is none of the
/// five platforms and can't learn the computer's name, so two browsers are told apart by this. Only a few well-known
/// names are looked for; anything else is "Browser" alone.
String browserNameOf(String userAgent) {
  final ua = userAgent;
  // Each of these says it is the ones after it too, so the order is the test.
  final which = ua.contains('Firefox/') || ua.contains('FxiOS/')
      ? 'Firefox'
      : ua.contains('Edg/') || ua.contains('EdgA/') || ua.contains('EdgiOS/')
          ? 'Edge'
          : ua.contains('OPR/')
              ? 'Opera'
              : ua.contains('Chrome/') || ua.contains('CriOS/')
                  ? 'Chrome'
                  : ua.contains('Safari/')
                      ? 'Safari'
                      : null;
  final on = ua.contains('Android')
      ? 'Android'
      : ua.contains('iPhone') || ua.contains('iPad')
          ? 'iOS'
          : ua.contains('Windows')
              ? 'Windows'
              : ua.contains('CrOS')
                  ? 'ChromeOS'
                  : ua.contains('Mac OS X') || ua.contains('Macintosh')
                      ? 'Mac'
                      : ua.contains('Linux')
                          ? 'Linux'
                          : null;
  return ['Browser', ?which, ?on].join(' · ');
}

abstract class Browser {
  /// The browser this page is in. A test puts its own here.
  static Browser instance = platform.browser();

  /// The page's address.
  Uri get address;

  /// What this browser is called in the account's list of devices ([browserNameOf]): "Browser · Chrome · Mac".
  String get name;

  /// Why the app can't run in this browser at all, in words for the person; null where it can. (No secure address:
  /// a browser gives a page neither the sealing nor the one-tab lock without one.)
  String? get unfit;

  /// The page's own store. Throws where the browser will keep nothing for this page.
  Future<BrowserStore> openStore();

  /// Asks to be the one tab of the app in this browser. [onAsked]: another tab wants to be it instead; finish what is
  /// being written, then answer, and it is theirs. Null where another tab is it already.
  Future<TabHold?> holdTab({required Future<void> Function() onAsked});

  /// Becomes the one tab, asking whichever tab is it to let go (and taking it where that one doesn't answer).
  Future<TabHold> takeTab({required Future<void> Function() onAsked});

  /// The page, loaded again from the start.
  void reload();

  /// [url] opened in a tab beside this one, with no way back to this page from it; whether the browser did.
  bool openTab(String url);
}

/// Being the one tab of the app. Held until the page goes.
abstract class TabHold {}

/// Named values that outlast the page, and a second kind the page can seal and open but never read the key of.
abstract class BrowserStore {
  Future<String?> read(String name);

  /// Keeps [value] as [name], whole or not at all.
  Future<void> write(String name, String value);
  Future<void> delete(String name);

  /// [read] of what [writeSealed] kept: opened with the store's key. Null where nothing is kept, or it won't open.
  Future<String?> readSealed(String name);

  /// [write], sealed first with a key the browser holds for this page and hands out to no one, the page included.
  Future<void> writeSealed(String name, String value);
}

/// A [Browser] in memory, for a test: one store per browser, and tabs that ask each other as real ones do.
class MemoryBrowser implements Browser {
  MemoryBrowser({Uri? address, this.unfit, MemoryBrowserProfile? profile, this.name = 'Browser'})
      : address = address ?? Uri.parse('https://relay.example/app/'),
        profile = profile ?? MemoryBrowserProfile();

  @override
  final Uri address;
  @override
  final String? unfit;
  @override
  final String name;

  /// What tabs of one browser share: the store, and which of them is the one.
  final MemoryBrowserProfile profile;

  int reloads = 0;
  final List<String> opened = [];

  /// Set to have [openStore] fail, as a browser that keeps nothing for a page does.
  bool noStore = false;

  @override
  Future<BrowserStore> openStore() async {
    if (noStore) throw StateError('no store here');
    return profile.store;
  }

  @override
  Future<TabHold?> holdTab({required Future<void> Function() onAsked}) async {
    if (profile._holder != null) return null;
    return profile._holder = _MemoryHold(onAsked);
  }

  @override
  Future<TabHold> takeTab({required Future<void> Function() onAsked}) async {
    final had = profile._holder;
    profile._holder = null;
    await had?.onAsked();
    return profile._holder = _MemoryHold(onAsked);
  }

  @override
  void reload() => reloads++;

  @override
  bool openTab(String url) {
    opened.add(url);
    return true;
  }
}

class MemoryBrowserProfile {
  final MemoryBrowserStore store = MemoryBrowserStore();
  _MemoryHold? _holder;

  /// The tab that was the one has gone (closed, or loaded again).
  void tabGone() => _holder = null;
}

class _MemoryHold implements TabHold {
  _MemoryHold(this.onAsked);
  final Future<void> Function() onAsked;
}

class MemoryBrowserStore implements BrowserStore {
  final Map<String, String> plain = {};

  /// What was sealed, as the store holds it: never the value itself.
  final Map<String, String> sealed = {};

  static String _seal(String value) => 'sealed:${String.fromCharCodes(value.codeUnits.reversed)}';

  @override
  Future<String?> read(String name) async => plain[name];
  @override
  Future<void> write(String name, String value) async => plain[name] = value;
  @override
  Future<void> delete(String name) async {
    plain.remove(name);
    sealed.remove(name);
  }

  @override
  Future<String?> readSealed(String name) async {
    final kept = sealed[name];
    if (kept == null || !kept.startsWith('sealed:')) return null;
    return String.fromCharCodes(kept.substring(7).codeUnits.reversed);
  }

  @override
  Future<void> writeSealed(String name, String value) async => sealed[name] = _seal(value);
}
