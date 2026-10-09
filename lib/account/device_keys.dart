/// The key store a device ships with (keystore.dart's ask, "THE DEVICE'S OWN"): the session and the three keys in
/// the platform's secure storage, each key written down by the real crypto ([CoreCrypto.keep]) and raised again at
/// launch ([CoreCrypto.restore]).
///
/// Two halves:
///
/// - **[SecureStore]** is a few small strings kept where only this app on this phone can read them. On Android it is
///   [ChannelSecureStore], over `SecureStore.kt`: each value encrypted with AES-256-GCM under a key that lives in
///   the Android Keystore and never leaves it, written to a file in the app's no-backup folder. Not
///   SharedPreferences in the clear, and not the library folder, which the backup copies. Anywhere else (the Mac's
///   tests, a desktop run) it is [MemorySecureStore]: signed in until the app closes.
/// - **[DeviceKeyStore]** is the [KeyStore] over one: the session as the JSON of [Session.toJson] under
///   `glyph-account-session`, and the keys under `account`, `device` and `encryption`, each as the one string `keep`
///   gave. A key is restored once a launch and held by its handle after that.
///
/// The rules keystore.dart sets, kept: a key set to null is forgotten; one this device does not hold, or cannot
/// read (the Keystore's key was lost with a restore to a new phone, the file was cut short), is null and never a
/// throw: a device that cannot remember is signed out, not broken. A value that could not be WRITTEN is still held
/// for as long as the app is open.
///
/// An organization's keys are never here: they are read from their wraps each launch (docs/STAGE7.md, "org keys in
/// memory only").
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/mac_app.dart';
import 'crypto.dart';
import 'crypto_api.dart';
import 'keystore.dart';
import 'session.dart';

/// A few small strings, kept where only this app on this device can read them.
abstract interface class SecureStore {
  /// The value kept under [name], or null: none, or one that can no longer be read.
  Future<String?> read(String name);

  /// Keeps [value] under [name]; null forgets it.
  Future<void> write(String name, String? value);
}

/// [SecureStore] in memory: off Android, and in tests. Nothing outlives the app.
class MemorySecureStore implements SecureStore {
  /// By name.
  final Map<String, String> held = {};

  @override
  Future<String?> read(String name) async => held[name];

  @override
  Future<void> write(String name, String? value) async {
    if (value == null) {
      held.remove(name);
    } else {
      held[name] = value;
    }
  }
}

/// [SecureStore] over the phone's (android/…/SecureStore.kt): `read {name}`, `write {name, value}`, `delete {name}`.
class ChannelSecureStore implements SecureStore {
  const ChannelSecureStore();

  static const MethodChannel channel = MethodChannel('ghost_md/secure_store');

  @override
  Future<String?> read(String name) => channel.invokeMethod<String>('read', {'name': name});

  @override
  Future<void> write(String name, String? value) async {
    if (value == null) {
      await channel.invokeMethod<void>('delete', {'name': name});
    } else {
      await channel.invokeMethod<void>('write', {'name': name, 'value': value});
    }
  }
}

/// This device's secure storage: the phone's Keystore on Android, the Keychain in the Mac app
/// (macos/Runner/GhostChannels.swift `Keychain`, under a service of this app's own), memory anywhere else.
SecureStore deviceSecureStore() => Platform.isAndroid || runsAsMacApp ? const ChannelSecureStore() : MemorySecureStore();

/// One of the three keys, as it is held and kept.
class _Slot<K extends KeyHandle> {
  _Slot(this.name, this.kind);

  /// The name it is kept under, and what the core calls it.
  final String name;
  final String kind;
  K? key;
  bool read = false;
}

/// The [KeyStore] a device ships with. See the header.
class DeviceKeyStore implements KeyStore {
  DeviceKeyStore({required CoreCrypto crypto, required SecureStore store})
      : _crypto = crypto,
        _store = store;

  final CoreCrypto _crypto;
  final SecureStore _store;

  final _Slot<SealKey> _account = _Slot('account', 'account');
  final _Slot<DeviceKey> _device = _Slot('device', 'device');
  final _Slot<EncryptionKey> _encryption = _Slot('encryption', 'pair');

  Session? _session;
  bool _sessionRead = false;

  Future<String?> _read(String name) async {
    try {
      return await _store.read(name);
    } catch (_) {
      // No store, or one that will not answer: nothing kept.
      return null;
    }
  }

  Future<void> _write(String name, String? value) async {
    try {
      await _store.write(name, value);
    } catch (_) {
      // Not kept: held until the app closes, and signed out after that.
    }
  }

  @override
  Future<Session?> session() async {
    if (_sessionRead) return _session;
    final text = await _read(sessionKey);
    Session? found;
    if (text != null) {
      try {
        found = Session.fromJson(jsonDecode(text));
      } on FormatException {
        found = null;
      }
    }
    // Set while this was being read: what was set stands.
    if (_sessionRead) return _session;
    _sessionRead = true;
    return _session = found;
  }

  @override
  Future<void> setSession(Session? session) async {
    _session = session;
    _sessionRead = true;
    await _write(sessionKey, session == null ? null : jsonEncode(session.toJson()));
  }

  Future<K?> _get<K extends KeyHandle>(_Slot<K> slot) async {
    if (slot.read) return slot.key;
    final raw = await _read(slot.name);
    K? found;
    if (raw != null) {
      try {
        found = await _crypto.restore(KeptKey(kind: slot.kind, raw: raw)) as K;
      } catch (_) {
        // Not a key the core takes: none kept.
        found = null;
      }
    }
    if (slot.read) return slot.key;
    slot.read = true;
    return slot.key = found;
  }

  Future<void> _set<K extends KeyHandle>(_Slot<K> slot, K? key) async {
    slot.key = key;
    slot.read = true;
    if (key == null) {
      await _write(slot.name, null);
      return;
    }
    final String raw;
    try {
      raw = (await _crypto.keep(key)).raw;
    } catch (_) {
      // Not one of the core's, or not one it writes down: held, not kept.
      return;
    }
    await _write(slot.name, raw);
  }

  @override
  Future<SealKey?> accountKey() => _get(_account);

  @override
  Future<void> setAccountKey(SealKey? key) => _set(_account, key);

  @override
  Future<DeviceKey?> deviceKey() => _get(_device);

  @override
  Future<void> setDeviceKey(DeviceKey? pair) => _set(_device, pair);

  @override
  Future<EncryptionKey?> encryptionKey() => _get(_encryption);

  @override
  Future<void> setEncryptionKey(EncryptionKey? pair) => _set(_encryption, pair);
}
