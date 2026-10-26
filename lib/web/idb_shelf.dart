/// [Shelf] over the browser's IndexedDB: the web build's files (docs/WEB.md). One database, `ghost-md`, one object
/// store a shelf, text kept as text and bytes as bytes. Only in the web build: it is the page's own storage.
///
/// The page asks the browser once to keep it (`navigator.storage.persist`), so a browser short of space does not
/// clear a person's notes as it would a cache; a browser that says no still keeps them as long as it keeps any
/// site's data, and sync has them besides.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'shelf.dart';

class IdbShelf implements Shelf {
  IdbShelf._(this._db);

  final web.IDBDatabase _db;

  /// The database's name, and its version: a version for every change of its shelves.
  static const String name = 'ghost-md';
  static const int version = 1;

  /// Opens the page's database, making its shelves the first time. Throws where the browser will not open one.
  static Future<IdbShelf> open() async {
    final factory = web.window.indexedDB;
    final request = factory.open(name, version);
    request.onupgradeneeded = ((web.Event _) {
      final db = request.result as web.IDBDatabase;
      for (final shelf in Shelves.all) {
        if (!db.objectStoreNames.contains(shelf)) db.createObjectStore(shelf);
      }
    }).toJS;
    final opened = await _answer(request).timeout(const Duration(seconds: 10));
    unawaited(_keepForGood());
    return IdbShelf._(opened as web.IDBDatabase);
  }

  static Future<void> _keepForGood() async {
    try {
      await web.window.navigator.storage.persist().toDart;
    } catch (_) {
      // A browser that will not say: the notes are kept as long as its site data is.
    }
  }

  static Future<JSAny?> _answer(web.IDBRequest request) {
    final done = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      if (!done.isCompleted) done.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('The browser\'s storage refused: ${request.error?.message ?? 'no reason given'}'));
    }).toJS;
    return done.future;
  }

  static Future<void> _kept(web.IDBTransaction transaction) {
    final done = Completer<void>();
    transaction.oncomplete = ((web.Event _) {
      if (!done.isCompleted) done.complete();
    }).toJS;
    void failed(web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('The browser\'s storage did not keep that: ${transaction.error?.message ?? 'no reason given'}'));
    }

    transaction.onerror = failed.toJS;
    transaction.onabort = failed.toJS;
    return done.future;
  }

  web.IDBObjectStore _store(String shelf, {bool write = false}) => _db.transaction(shelf.toJS, write ? 'readwrite' : 'readonly').objectStore(shelf);

  Future<void> _write(String shelf, void Function(web.IDBObjectStore store) change) {
    final transaction = _db.transaction(shelf.toJS, 'readwrite');
    change(transaction.objectStore(shelf));
    return _kept(transaction);
  }

  @override
  Future<Map<String, String>> texts(String shelf) async {
    final store = _store(shelf);
    final keys = _answer(store.getAllKeys());
    final values = _answer(store.getAll());
    final (k, v) = await (keys, values).wait;
    final names = (k as JSArray<JSAny?>).toDart;
    final texts = (v as JSArray<JSAny?>).toDart;
    return {
      for (var i = 0; i < names.length && i < texts.length; i += 1)
        if (names[i].isA<JSString>() && texts[i].isA<JSString>()) (names[i] as JSString).toDart: (texts[i] as JSString).toDart,
    };
  }

  @override
  Future<String?> text(String shelf, String key) async {
    final value = await _answer(_store(shelf).get(key.toJS));
    return value.isA<JSString>() ? (value as JSString).toDart : null;
  }

  @override
  Future<void> putText(String shelf, String key, String? value) => _write(shelf, (store) {
    if (value == null) {
      store.delete(key.toJS);
    } else {
      store.put(value.toJS, key.toJS);
    }
  });

  @override
  Future<Uint8List?> bytes(String shelf, String key) async {
    final value = await _answer(_store(shelf).get(key.toJS));
    return value.isA<JSUint8Array>() ? (value as JSUint8Array).toDart : null;
  }

  @override
  Future<void> putBytes(String shelf, String key, Uint8List? value) => _write(shelf, (store) {
    if (value == null) {
      store.delete(key.toJS);
    } else {
      store.put(value.toJS, key.toJS);
    }
  });

  @override
  Future<List<String>> keys(String shelf) async {
    final keys = await _answer(_store(shelf).getAllKeys());
    return [
      for (final key in (keys as JSArray<JSAny?>).toDart)
        if (key.isA<JSString>()) (key as JSString).toDart,
    ];
  }

  @override
  Future<void> clear(String shelf) => _write(shelf, (store) => store.clear());
}
