/// What the app's own Claude is set up with on this device (docs/CLAUDE_APP.md, "The key"): the person's Anthropic
/// API key, which model to ask, and whether the "Ask Claude" inbox note is worked through as requests are added.
///
/// The key is kept in the device's secure storage (lib/account/device_keys.dart [SecureStore]: the Android Keystore,
/// the Keychain on a Mac and an iPhone), never in the preferences, never synced, never in the library folder a backup
/// copies. Each device is given its key by hand. The model and the inbox switch sit beside it there, small strings,
/// so the three are read together and a device with no key keeps nothing else.
library;

import 'package:flutter/foundation.dart';

import '../account/device_keys.dart' show SecureStore, deviceSecureStore;

/// The names in the secure store.
const String claudeKeyName = 'anthropic-api-key';
const String claudeModelName = 'anthropic-model';
const String claudeInboxName = 'anthropic-inbox';

/// A model the app offers.
@immutable
class ClaudeModel {
  const ClaudeModel(this.id, this.name, this.about);

  final String id;
  final String name;
  final String about;
}

/// In the order Settings shows them; the API's own ids (platform.claude.com/docs/en/models/overview).
const List<ClaudeModel> claudeModels = [
  ClaudeModel('claude-sonnet-5-5', 'Sonnet 5.5', 'Quick and able. The one to start with.'),
  ClaudeModel('claude-opus-5-5', 'Opus 5.5', 'The most careful, for long or tangled work. Slower, and costs more.'),
  ClaudeModel('claude-haiku-5-5', 'Haiku 5.5', 'The fastest and cheapest, for small asks.'),
];

const String defaultClaudeModel = 'claude-sonnet-5-5';

/// The model's name as a person reads it.
String claudeModelLabel(String id) {
  for (final model in claudeModels) {
    if (model.id == id) return model.name;
  }
  return id;
}

/// A key shown without showing it: its start and its last four.
String maskKey(String key) {
  final k = key.trim();
  if (k.length <= 12) return '••••';
  return '${k.substring(0, 7)}…${k.substring(k.length - 4)}';
}

/// The settings, read once from the store and kept as they change.
class ClaudeSettings extends ChangeNotifier {
  ClaudeSettings(this._store);

  final SecureStore _store;

  String? _key;
  String _model = defaultClaudeModel;
  bool _inbox = true;
  bool _loaded = false;
  Future<void>? _loading;

  bool get loaded => _loaded;

  /// The key, or null for none.
  String? get key => _key;
  bool get hasKey => (_key ?? '').trim().isNotEmpty;
  String get model => _model;

  /// Whether requests added to the "Ask Claude" note are done as they are added.
  bool get inbox => _inbox;

  /// Reads what this device keeps. Once; later calls wait for the same read.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final key = await _store.read(claudeKeyName);
      final model = await _store.read(claudeModelName);
      final inbox = await _store.read(claudeInboxName);
      _key = (key ?? '').trim().isEmpty ? null : key!.trim();
      if (model != null && model.isNotEmpty) _model = model;
      _inbox = inbox != 'off';
    } catch (_) {
      // A store that cannot be read is a device with no key.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Keeps [key] (trimmed), or forgets it for null or blank.
  Future<void> setKey(String? key) async {
    final k = (key ?? '').trim();
    _key = k.isEmpty ? null : k;
    notifyListeners();
    await _store.write(claudeKeyName, _key);
  }

  Future<void> setModel(String id) async {
    if (id == _model) return;
    _model = id;
    notifyListeners();
    await _store.write(claudeModelName, id);
  }

  Future<void> setInbox(bool on) async {
    if (on == _inbox) return;
    _inbox = on;
    notifyListeners();
    await _store.write(claudeInboxName, on ? 'on' : 'off');
  }
}

/// This device's, as the app reads and writes them: Settings › Ask Claude and the root's runner share it, as the app
/// shares `preferences`. Read on first use.
final ClaudeSettings claudeSettings = ClaudeSettings(deviceSecureStore());
