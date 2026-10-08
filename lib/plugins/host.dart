/// A plugin's one way onto the phone, cut to its manifest. A port of `src/app/plugins/host.ts`.
///
/// Each call checks the manifest before doing anything: a storage key it does not own, a secret it did not name, a
/// host it did not list, or a permission it did not ask for throws, naming the plugin, the moment the code runs. A
/// built-in plugin that reaches past its manifest fails its first test rather than quietly doing something
/// Settings > Plugins never said it does.
///
/// What differs:
/// - The page's globals (localStorage, Tauri's `invoke`, the opener) are [PluginGround], one value the app's root
///   puts in place with [usePluginGround] before the first frame and a test replaces with its own. A host made at
///   the top of a plugin's file reads the ground when it is used, never when it is made. The ground it starts with
///   keeps secrets for this run only, answers no request and opens nothing.
/// - `invoke` refuses every command (types.dart): the commands were Rust's, and their work is the plugin's own
///   now, through [PluginHost.fetch] and [PluginHost.secrets].
/// - [PluginHost.fetch] holds a request to the manifest's hosts: the name itself or a name under it. A plugin that
///   asked `api.github.com` cannot be made to ask anywhere else by an address in a note.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../account/api.dart' show FetchRequest, FetchResponse, Fetcher;
import '../account/device_keys.dart' show MemorySecureStore, SecureStore;
import '../core/stored.dart';
import 'types.dart';

/// What the hosts stand on: the device's memory, its secure store, the network, the browser.
class PluginGround {
  PluginGround({Stored Function()? stored, SecureStore? secrets, Fetcher? fetch, Future<void> Function(String url)? open, Future<bool> Function(int wanted)? hasNativeGeneration})
      : _stored = stored,
        secrets = secrets ?? MemorySecureStore(),
        fetch = fetch ?? _noNetwork,
        open = open ?? _opensNothing,
        hasNativeGeneration = hasNativeGeneration ?? _everyGeneration;

  final Stored Function()? _stored;

  /// The app's memory (lib/core/stored.dart [stored]) unless the ground was given its own.
  Stored get kept => _stored?.call() ?? stored;

  /// Tokens and webhooks: `deviceSecureStore()` on a phone (lib/account/device_keys.dart).
  final SecureStore secrets;

  /// `ioFetcher()` on a phone (lib/account/api.dart); a test's recorded answers.
  final Fetcher fetch;

  /// Hands an address to the phone (lib/core/open_link.dart `openLink`).
  final Future<void> Function(String url) open;

  /// `core/nativeGeneration.ts` `hasNativeGeneration`. Everything a plugin needed of the binary is Dart here, so
  /// the ground a build starts with says yes to any generation.
  final Future<bool> Function(int wanted) hasNativeGeneration;

  static Future<FetchResponse> _noNetwork(FetchRequest request) => throw StateError('No network was given to the plugins (usePluginGround).');
  static Future<void> _opensNothing(String url) async {}
  static Future<bool> _everyGeneration(int wanted) async => true;
}

PluginGround _ground = PluginGround();

/// What every host stands on now.
PluginGround get pluginGround => _ground;

/// Puts [ground] under every host: the root, once, before the first frame; a test, with its own.
void usePluginGround(PluginGround ground) {
  _ground = ground;
  _held.clear();
  _storageChanged();
}

/// What the secrets doors have read or written, by name, across hosts: one store, one memory of it.
final Map<String, String?> _held = {};

final Set<VoidCallback> _storageListeners = {};

void _storageChanged() {
  for (final listener in _storageListeners.toList()) {
    listener();
  }
}

/// A plugin wrote to its storage or its secrets: whatever draws from it (a note's link marks, the cog sheet's
/// hints) reads again. Answers the way to stop (`onPluginStorage`).
VoidCallback onPluginStorage(VoidCallback listener) {
  _storageListeners.add(listener);
  return () => _storageListeners.remove(listener);
}

/// A plugin reached for something its manifest did not declare (`PluginPermissionError`).
class PluginPermissionError extends Error {
  PluginPermissionError(PluginManifest manifest, String what) : message = 'The ${manifest.name} plugin didn\'t declare $what.';
  final String message;

  @override
  String toString() => message;
}

/// Whether [host] is [listed] or a name under it.
bool _under(String host, String listed) => host == listed || host.endsWith('.$listed');

/// The host for [manifest] (`createHost`). [ground] is for a test that wants one of its own; otherwise the app's.
PluginHost createHost(PluginManifest manifest, {PluginGround? ground}) => _Host(manifest, ground);

class _Host implements PluginHost, PluginStorage, PluginSecrets {
  _Host(this.manifest, this._own);

  @override
  final PluginManifest manifest;
  final PluginGround? _own;

  PluginGround get _on => _own ?? _ground;

  @override
  void need(Permission permission) {
    if (!manifest.declares(permission)) throw PluginPermissionError(manifest, 'the “${permission.name}” permission');
  }

  void _owns(String key) {
    if (!manifest.storage.contains(key)) throw PluginPermissionError(manifest, 'the storage key “$key”');
  }

  void _keeps(String name) {
    final listed = manifest.secrets.any((s) => s.endsWith(':') ? name.startsWith(s) && name.length > s.length : s == name);
    if (!listed) throw PluginPermissionError(manifest, 'the secret “$name”');
  }

  @override
  Future<bool> nativeReady() async {
    final native = manifest.native;
    if (native == null) return false;
    return _on.hasNativeGeneration(native.generation);
  }

  @override
  Future<T> invoke<T>(String command, [Map<String, Object?>? args]) {
    if (!manifest.declares(Permission.native)) return Future.error(PluginPermissionError(manifest, 'the “native” permission'));
    if (!(manifest.native?.commands.contains(command) ?? false)) return Future.error(PluginPermissionError(manifest, 'the native command “$command”'));
    return Future.error(UnsupportedError('“$command” was the web app’s Rust; here ${manifest.name} does that work itself.'));
  }

  @override
  PluginStorage get storage => this;

  @override
  PluginSecrets get secrets => this;

  // ---- storage ----

  @override
  T get<T>(String key, T fallback) {
    _owns(key);
    try {
      return _on.kept.readShared<T>(key, fallback);
    } catch (_) {
      // Kept as some other shape: the same as nothing kept.
      return fallback;
    }
  }

  @override
  void set(String key, Object? value) {
    _owns(key);
    // As JSON whatever it is, null included; with no storage it lasts as long as the app.
    _on.kept.writeText(key, _json(value));
    _storageChanged();
  }

  @override
  void remove(String key) {
    _owns(key);
    // Gone before anything is told, as a write is: a listener reads what the change left.
    _on.kept.writeText(key, null);
    _storageChanged();
  }

  // ---- secrets ----

  @override
  Future<String?> read(String name) async {
    _keeps(name);
    final ground = _on;
    String? value;
    try {
      value = await ground.secrets.read(name);
    } catch (_) {
      // A store that will not answer keeps nothing.
      value = null;
    }
    if (identical(ground, _on)) _held[name] = value;
    return value;
  }

  @override
  Future<void> write(String name, String? value) async {
    _keeps(name);
    _held[name] = value;
    try {
      await _on.secrets.write(name, value);
    } catch (_) {
      // Not kept: held until the app closes.
    }
    _storageChanged();
  }

  @override
  String? held(String name) {
    _keeps(name);
    return _held[name];
  }

  @override
  Future<void> warm() async {
    var any = false;
    for (final name in manifest.secrets) {
      if (name.endsWith(':')) continue;
      final before = _held[name];
      if (await read(name) != before) any = true;
    }
    if (any) _storageChanged();
  }

  // ---- out of the phone ----

  @override
  Future<FetchResponse> fetch(FetchRequest request) async {
    // Refused as a request that failed, never as a throw where it was asked: a caller waits on one thing.
    need(Permission.network);
    final host = request.url.host.toLowerCase();
    if (!manifest.hosts.any((listed) => _under(host, listed.toLowerCase()))) throw PluginPermissionError(manifest, 'the host “$host”');
    return _on.fetch(request);
  }

  @override
  Future<void> openUrl(String url) async {
    need(Permission.network);
    await _on.open(url);
  }
}

String _json(Object? value) => jsonEncode(value);
