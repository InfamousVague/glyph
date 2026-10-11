/// This device's own memory, asked the one way the whole app asks it. A port of `src/app/core/stored.ts`.
///
/// The rule is the web's: storage that REFUSES is a device that cannot remember, not an error. A read that cannot be
/// answered is the caller's fallback, and a write that cannot be kept is silence; every caller has already said what
/// it does without a memory. Keys are `glyph-<thing>`, the web app's own, so a reset finds all of them. Values are
/// JSON ([Stored.read], [Stored.write]) or plain text for the keys that have always held a bare word or number
/// ([Stored.readText], [Stored.writeText]); a key keeps the form it was first written in.
///
/// What differs: the page has one `localStorage`; here [Stored] is a small synchronous interface with the web's
/// functions as its methods, [MemoryStored] is the one implementation in this file, and the app's is [stored], which
/// whoever wires the app replaces with one kept on the device ([useStored]). A backend that throws is one that
/// refuses.
library;

import 'dart:convert';

/// A value read from storage and checked: null for a shape the caller will not have.
typedef StoredParse<T> = T? Function(Object? raw);

/// The device's key/value memory (`localStorage`), synchronous, with the web module's functions over it.
///
/// An implementation gives the three primitives and [allKeys]; any of them may throw, which is storage refusing.
abstract class Stored {
  /// What is kept under [key], or null when nothing is (`localStorage.getItem`).
  String? getItem(String key);

  /// Keeps [text] under [key] (`localStorage.setItem`).
  void setItem(String key, String text);

  /// Forgets [key] (`localStorage.removeItem`).
  void removeItem(String key);

  /// Every key kept, this app's and anybody else's.
  Iterable<String> get allKeys;

  final Map<String, ({String text, Object? value})> _parsed = {};

  /// What is kept under [key]: `(true, text)`, with a null text when nothing is; `(false, null)` when storage would
  /// not answer at all (`held`).
  (bool, String?) _held(String key) {
    try {
      return (true, getItem(key));
    } catch (_) {
      // Refused (see the header): the caller decides what an unanswerable read means.
      return (false, null);
    }
  }

  /// The text kept under [key], or null when there is none or storage will not say (`readStoredText`).
  String? readText(String key) => _held(key).$2;

  /// Keeps [text] under [key]; null removes it. Refused, it is silence (`writeStoredText`).
  void writeText(String key, String? text) {
    try {
      if (text == null) {
        removeItem(key);
      } else {
        setItem(key, text);
      }
    } catch (_) {
      // Refused (see the header): the caller holds the value for this run, or does without it.
    }
  }

  /// The value kept under [key] as JSON, or [fallback] when there is none, it is not JSON, or storage will not say
  /// (`readStored`). [parse] checks what was read and answers null for a value it will not have, which reads as
  /// [fallback] too, as does an exception inside it; without it the value is taken as it is. [fallback] is answered
  /// as it was passed, so a caller that changes what it reads passes a fresh one each time.
  T read<T>(String key, T fallback, [StoredParse<T>? parse]) {
    final text = _held(key).$2;
    if (text == null) return fallback;
    try {
      final Object? value = jsonDecode(text);
      return parse != null ? (parse(value) ?? fallback) : value as T;
    } catch (_) {
      // Not JSON, or not a shape `parse` would have: the same as nothing kept.
      return fallback;
    }
  }

  /// Keeps [value] under [key] as JSON; null removes it. Refused, it is silence (`writeStored`).
  void write(String key, Object? value) {
    String? text;
    if (value != null) {
      try {
        text = jsonEncode(value);
      } catch (_) {
        // Nothing JSON can say: the same as a write that was refused.
        return;
      }
    }
    writeText(key, text);
  }

  /// [read], parsing only when the text has changed since the last read of the key (`readStoredShared`). The text is
  /// still asked of storage on every read. What it answers is SHARED between readers, so a caller that changes it
  /// copies it first.
  T readShared<T>(String key, T fallback, [StoredParse<T>? parse]) {
    final text = _held(key).$2;
    if (text == null) return fallback;
    final last = _parsed[key];
    if (last != null && last.text == text) return last.value as T;
    try {
      final Object? raw = jsonDecode(text);
      final Object? value = parse != null ? parse(raw) : raw;
      // A shape `parse` will not have is not kept, so the next read looks again; without `parse` a JSON null is a value.
      if (parse != null && value == null) return fallback;
      _parsed[key] = (text: text, value: value);
      return value as T;
    } catch (_) {
      return fallback;
    }
  }

  /// Every key kept on this device: for a reset. Nothing, when storage will not say (`storedKeys`).
  List<String> keys() {
    try {
      return allKeys.toList();
    } catch (_) {
      // Refused (see the header): there is nothing this app can see to clear.
      return const [];
    }
  }

  /// Something that happens once on a device, remembered by a key that holds anything at all once it has
  /// (`storedFlag`). [value] is what marking writes and what `isMarked` then looks for: without one, the moment it
  /// was marked (ISO), and any value at all reads as marked. [unreadable] is what `isMarked` answers when storage
  /// cannot be read at all, which is each flag's own judgement of which mistake is cheaper.
  StoredFlag flag(String key, {String? value, bool unreadable = false}) => StoredFlag._(this, key, value, unreadable);
}

/// A once-flag on a [Stored] (`StoredFlag`): `is()`, `mark()` and `clear()` on the web.
class StoredFlag {
  const StoredFlag._(this._stored, this.key, this._value, this._unreadable);

  final Stored _stored;
  final String key;
  final String? _value;
  final bool _unreadable;

  /// Whether it has been marked (`is`, a word Dart keeps for itself).
  bool get isMarked {
    final (answered, text) = _stored._held(key);
    if (!answered) return _unreadable;
    return _value == null ? text != null : text == _value;
  }

  /// Marks it, from now on.
  void mark() => _stored.writeText(key, _value ?? DateTime.now().toUtc().toIso8601String());

  /// Takes the mark away.
  void clear() => _stored.writeText(key, null);
}

/// Kept for this run only: a test's storage, and the app's until a kept one is put in its place.
class MemoryStored extends Stored {
  MemoryStored([Map<String, String>? held]) : _held2 = {...?held};

  final Map<String, String> _held2;

  @override
  String? getItem(String key) => _held2[key];

  @override
  void setItem(String key, String text) => _held2[key] = text;

  @override
  void removeItem(String key) => _held2.remove(key);

  @override
  Iterable<String> get allKeys => _held2.keys;

  /// Forgets everything (`localStorage.clear()`).
  void clear() => _held2.clear();
}

Stored _stored = MemoryStored();

/// The app's memory on this device: in memory until [useStored] puts a kept one in its place.
Stored get stored => _stored;

/// Makes [next] the app's memory. Called once as the app starts, by whoever holds the device's storage; a test calls
/// it with a fresh [MemoryStored].
void useStored(Stored next) => _stored = next;
