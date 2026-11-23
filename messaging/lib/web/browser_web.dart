import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'browser.dart';

/// The browser this page is in (browser.dart): the one file of the app in a web page that speaks to JavaScript for
/// what it keeps and for being the only tab. Nothing here is fetched from anywhere: it is all the browser's own.
Browser browser() => _PageBrowser();

class _PageBrowser implements Browser {
  @override
  Uri get address => Uri.parse(web.window.location.href);

  @override
  String get name => browserNameOf(web.window.navigator.userAgent);

  @override
  String? get unfit {
    // Sealing what is kept (crypto.subtle) and the one-tab lock are given only to a page from a secure address:
    // https, or this computer itself.
    if (!web.window.isSecureContext) return 'Ghost Messaging needs a secure address to run in a browser: one that starts with https.';
    return null;
  }

  @override
  Future<BrowserStore> openStore() => _PageStore.open();

  // --- one tab at a time ---------------------------------------------------------------------------------------------

  /// What the tabs of one browser are all asking for, and where they speak to each other.
  static const _name = 'ghost-messaging-tab';

  static web.LockManager? get _locks {
    final n = web.window.navigator as JSObject;
    return n.has('locks') ? web.window.navigator.locks : null;
  }

  static web.BroadcastChannel? _makeChannel() => (web.window as JSObject).has('BroadcastChannel') ? web.BroadcastChannel(_name) : null;

  web.BroadcastChannel? _channel;
  bool _mine = false;

  /// Hears the other tabs from now on: one asking who is here is answered, and one asking for the tab is given it
  /// once [onAsked] is done.
  void _hear(Future<void> Function() onAsked) {
    final channel = _channel ??= _makeChannel();
    if (channel == null) return;
    var going = false;
    channel.onmessage = ((web.MessageEvent e) {
      final said = e.data.dartify();
      if (!_mine) return;
      if (said == 'who') {
        channel.postMessage('here'.toJS);
      } else if (said == 'yield' && !going) {
        going = true;
        // What is being written is finished first, then it is theirs: this page starts again, as the tab that isn't it.
        onAsked().catchError((_) {}).whenComplete(() {
          _mine = false;
          channel.postMessage('yielded'.toJS);
          reload();
        });
      }
    }).toJS;
  }

  /// Waits [wait] for another tab to say [word].
  Future<bool> _heard(String word, Duration wait, {String? after}) {
    final channel = _channel ??= _makeChannel();
    if (channel == null) return Future.value(false);
    final heard = Completer<bool>();
    void listener(web.Event e) {
      if ((e as web.MessageEvent).data.dartify() == word && !heard.isCompleted) heard.complete(true);
    }

    final js = listener.toJS;
    channel.addEventListener('message', js);
    if (after != null) channel.postMessage(after.toJS);
    return heard.future.timeout(wait, onTimeout: () => false).whenComplete(() => channel.removeEventListener('message', js));
  }

  /// Asks the browser for the lock: only when it is free, or ([steal]) from whichever tab has it. True where this
  /// tab has it now; it is kept until the page goes.
  Future<bool> _lock({bool steal = false}) {
    final locks = _locks!;
    final got = Completer<bool>();
    final never = Completer<JSAny?>();
    final asked = locks.request(
      _name,
      steal ? web.LockOptions(steal: true) : web.LockOptions(ifAvailable: true),
      ((web.Lock? lock) {
        if (!got.isCompleted) got.complete(lock != null);
        // Held for as long as this is not done: until the page goes.
        return lock == null ? null : never.future.toJS;
      }).toJS,
    );
    // Taken from this tab by another that did not wait to be answered: this page starts again, as the one that isn't it.
    asked.toDart.then((_) {}, onError: (Object _) {
      if (!got.isCompleted) {
        got.complete(false);
      } else if (_mine) {
        _mine = false;
        reload();
      }
    });
    return got.future;
  }

  @override
  Future<TabHold?> holdTab({required Future<void> Function() onAsked}) async {
    if (_locks != null) {
      if (!await _lock()) return null;
    } else if (await _heard('here', const Duration(milliseconds: 400), after: 'who')) {
      // A browser without the lock: the tabs ask each other, and one that is the app answers.
      return null;
    }
    _mine = true;
    _hear(onAsked);
    return _Held();
  }

  @override
  Future<TabHold> takeTab({required Future<void> Function() onAsked}) async {
    // Asked first, so the tab that is it finishes what it is writing; taken all the same where it doesn't answer.
    await _heard('yielded', const Duration(seconds: 2), after: 'yield');
    if (_locks != null) await _lock(steal: true);
    _mine = true;
    _hear(onAsked);
    return _Held();
  }

  @override
  void reload() => web.window.location.reload();

  @override
  bool openTab(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || url != url.trim() || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return false;
    // No way back to this page from the one opened, and it is not told where it was opened from.
    web.window.open(uri.toString(), '_blank', 'noopener,noreferrer');
    return true;
  }
}

class _Held implements TabHold {}

/// The page's own IndexedDB: one database, one store of named records. A plain value is its text; a sealed one is
/// twelve random bytes and then AES-256-GCM's output under the key kept as [_keyName], its name bound in.
class _PageStore implements BrowserStore {
  _PageStore(this._db, this._key);

  static const _dbName = 'ghost-messaging', _records = 'kept', _keyName = 'seal-key';

  final web.IDBDatabase _db;

  /// Made by the browser as not extractable: `encrypt` and `decrypt` take it, and nothing gives its bytes.
  final web.CryptoKey _key;

  static Future<_PageStore> open() async {
    final opening = web.window.indexedDB.open(_dbName, 1);
    opening.onupgradeneeded = ((web.Event _) {
      final db = opening.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_records)) db.createObjectStore(_records);
    }).toJS;
    final db = (await _asked(opening)) as web.IDBDatabase;
    var key = await _get(db, _keyName);
    if (key == null || !key.isA<web.CryptoKey>()) {
      key = await web.window.crypto.subtle
          .generateKey(_object({'name': 'AES-GCM'.toJS, 'length': 256.toJS}), false, ['encrypt'.toJS, 'decrypt'.toJS].toJS)
          .toDart;
      await _put(db, _keyName, key);
    }
    return _PageStore(db, key as web.CryptoKey);
  }

  static Future<JSAny?> _asked(web.IDBRequest request) {
    final done = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => done.complete(request.result)).toJS;
    request.onerror = ((web.Event _) => done.completeError(StateError('the browser\'s store: ${request.error?.message ?? 'refused'}'))).toJS;
    return done.future;
  }

  static Future<JSAny?> _get(web.IDBDatabase db, String name) => _asked(db.transaction(_records.toJS).objectStore(_records).get(name.toJS));

  /// Done when the browser says the write is kept, not when it was asked for.
  static Future<void> _write(web.IDBDatabase db, void Function(web.IDBObjectStore store) change) {
    final done = Completer<void>();
    final tx = db.transaction(_records.toJS, 'readwrite');
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    void failed(web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('the browser\'s store: ${tx.error?.message ?? 'the write was not kept'}'));
    }

    tx.onerror = failed.toJS;
    tx.onabort = failed.toJS;
    change(tx.objectStore(_records));
    return done.future;
  }

  static Future<void> _put(web.IDBDatabase db, String name, JSAny? value) => _write(db, (s) => s.put(value, name.toJS));

  @override
  Future<String?> read(String name) async {
    final got = await _get(_db, name);
    return got != null && got.isA<JSString>() ? (got as JSString).toDart : null;
  }

  @override
  Future<void> write(String name, String value) => _put(_db, name, value.toJS);

  @override
  Future<void> delete(String name) => _write(_db, (s) => s.delete(name.toJS));

  /// AES-GCM under [nonce], with the record's own name bound in: one record's bytes put under another name don't open.
  static JSObject _params(Uint8List nonce, String name) =>
      _object({'name': 'AES-GCM'.toJS, 'iv': nonce.toJS, 'additionalData': Uint8List.fromList(utf8.encode('ghost-messaging kept v1|$name')).toJS});

  /// A plain JavaScript object of [fields], as the browser's sealing takes its settings.
  static JSObject _object(Map<String, JSAny?> fields) {
    final o = JSObject();
    fields.forEach((name, value) => o[name] = value);
    return o;
  }

  @override
  Future<void> writeSealed(String name, String value) async {
    final filled = _random(12);
    final sealed = (await web.window.crypto.subtle.encrypt(_params(filled, name), _key, Uint8List.fromList(utf8.encode(value)).toJS).toDart) as JSArrayBuffer;
    final out = Uint8List(12 + sealed.toDart.lengthInBytes)
      ..setRange(0, 12, filled)
      ..setRange(12, 12 + sealed.toDart.lengthInBytes, sealed.toDart.asUint8List());
    await _put(_db, name, out.toJS);
  }

  /// [n] bytes from the browser's own random. Read back from what JavaScript filled: a list handed over may be a
  /// copy there.
  static Uint8List _random(int n) {
    final js = Uint8List(n).toJS;
    web.window.crypto.getRandomValues(js);
    return js.toDart;
  }

  @override
  Future<String?> readSealed(String name) async {
    final got = await _get(_db, name);
    if (got == null || !got.isA<JSUint8Array>()) return null;
    final bytes = (got as JSUint8Array).toDart;
    if (bytes.length < 12 + 16) return null;
    try {
      final clear = (await web.window.crypto.subtle.decrypt(_params(Uint8List.sublistView(bytes, 0, 12), name), _key, Uint8List.sublistView(bytes, 12).toJS).toDart) as JSArrayBuffer;
      return utf8.decode(clear.toDart.asUint8List());
    } catch (_) {
      // Sealed with another key (the browser's store cleared in part), or changed: nothing is kept there.
      return null;
    }
  }
}
