/// What the app's own Claude is set up with on this device (docs/CLAUDE_APP.md, "The key"): the person's Anthropic
/// API key, which model to ask, and whether the "Ask Claude" inbox note is worked through as requests are added.
///
/// The key is kept in the device's secure storage (lib/account/device_keys.dart [SecureStore]: the Android Keystore,
/// the Keychain on a Mac and an iPhone), never in the preferences in the clear, never in the library folder a backup
/// copies. The model and the inbox switch sit beside it there, small strings, so they are read together and a device
/// with no key keeps nothing else.
///
/// **They follow the account** (Matt, 2026-10-26: "make it so things like the Claude tokens and other stuff is kept
/// in sync across all instances of ghost logged in to my account"). Until then each device was given its key by
/// hand, and a meeting's summary stuck on the Mac, which had none, while the Fold did. Now the key, the model, the
/// effort, the inbox and watch switches and the spending limit are each sealed under the account key into the synced
/// settings (lib/sync/sealed_keys.dart, the items in lib/sync/connections.dart), and on another device written back
/// into its secure store under the same names; [reload] then reads them again, so the next request, and the
/// summaries' handoff, see the key. Settings › Account › Keep keys and connections in sync turns that off for a
/// device.
library;

import 'package:flutter/foundation.dart';

import '../account/device_keys.dart' show SecureStore, deviceSecureStore;
import 'claude_spend.dart';

/// The names in the secure store.
const String claudeKeyName = 'anthropic-api-key';
const String claudeModelName = 'anthropic-model';
const String claudeInboxName = 'anthropic-inbox';
const String claudeEffortName = 'anthropic-effort';
const String claudeWatchName = 'anthropic-watch';

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

/// How hard Claude thinks before it answers: the API's `output_config.effort`. Lower is quicker and cheaper, higher
/// more thorough. In the order the chat shows them, each with the word it shows.
const List<(String, String)> claudeEfforts = [
  ('low', 'Low'),
  ('medium', 'Medium'),
  ('high', 'High'),
  ('xhigh', 'Extra high'),
  ('max', 'Max'),
];

/// The effort a model takes when none is said: Opus 5.5's and Haiku 5.5's is medium, Sonnet 5.5's high
/// (platform.claude.com/docs). The chat shows it chosen until another is.
String defaultClaudeEffort(String model) => model == 'claude-sonnet-5-5' ? 'high' : 'medium';

/// The effort's word as a person reads it.
String claudeEffortLabel(String effort) {
  for (final (id, words) in claudeEfforts) {
    if (id == effort) return words;
  }
  return effort;
}

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
  ClaudeSettings(this._store) : spend = ClaudeSpend(_store) {
    // Heard through the settings: the page, the runner and the write-ups' queue look again as the count changes.
    spend.addListener(notifyListeners);
  }

  final SecureStore _store;

  /// Where the key and its choices are kept: the synced keys read and write it by the names above
  /// (lib/sync/connections.dart), then [reload].
  SecureStore get store => _store;

  /// What Claude has spent this month on this device, and the limit on it (lib/claude/claude_spend.dart), kept in
  /// the same store.
  final ClaudeSpend spend;

  String? _key;
  String _model = defaultClaudeModel;
  String? _effort;
  bool _inbox = true;
  bool _watch = true;
  bool _loaded = false;
  Future<void>? _loading;

  bool get loaded => _loaded;

  /// The key, or null for none.
  String? get key => _key;
  bool get hasKey => (_key ?? '').trim().isNotEmpty;
  String get model => _model;

  /// The effort asked for: the one chosen, or the model's own when none is.
  String get effort => _effort ?? defaultClaudeEffort(_model);

  /// Whether an effort was chosen (sent with every request) rather than left to the model.
  bool get effortChosen => _effort != null;

  /// Whether requests added to the "Ask Claude" note are done as they are added.
  bool get inbox => _inbox;

  /// Whether a short recording from the watch goes to Claude, as one said to the dock's microphone does
  /// (lib/watch/watch_notes.dart, "To Claude"); off, it is a voice note. Settings › Recording › Watch.
  bool get watch => _watch;

  /// Reads what this device keeps. Once; later calls wait for the same read.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    await _read();
    await spend.load();
    _loaded = true;
    notifyListeners();
  }

  /// Reads the store again, once what is kept there was written by another device (lib/sync/sealed_keys.dart), and
  /// tells whoever listens: the chat, the runner, the write-ups' queue and the summaries' handoff look again.
  Future<void> reload() async {
    await load();
    await _read();
    await spend.reloadLimit();
    notifyListeners();
  }

  Future<void> _read() async {
    try {
      final key = await _store.read(claudeKeyName);
      final model = await _store.read(claudeModelName);
      final inbox = await _store.read(claudeInboxName);
      final effort = await _store.read(claudeEffortName);
      final watch = await _store.read(claudeWatchName);
      _effort = effort != null && claudeEfforts.any((e) => e.$1 == effort) ? effort : null;
      _key = (key ?? '').trim().isEmpty ? null : key!.trim();
      _model = model != null && model.isNotEmpty ? model : defaultClaudeModel;
      _inbox = inbox != 'off';
      _watch = watch != 'off';
    } catch (_) {
      // A store that cannot be read is a device with no key.
    }
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

  /// Chooses an effort, or goes back to the model's own with null.
  Future<void> setEffort(String? effort) async {
    if (effort == _effort) return;
    _effort = effort;
    notifyListeners();
    await _store.write(claudeEffortName, effort);
  }

  Future<void> setInbox(bool on) async {
    if (on == _inbox) return;
    _inbox = on;
    notifyListeners();
    await _store.write(claudeInboxName, on ? 'on' : 'off');
  }

  Future<void> setWatch(bool on) async {
    if (on == _watch) return;
    _watch = on;
    notifyListeners();
    await _store.write(claudeWatchName, on ? 'on' : 'off');
  }
}

/// This device's, as the app reads and writes them: the Claude plugin's page and the root's runner share it, as the app
/// shares `preferences`. Read on first use.
final ClaudeSettings claudeSettings = ClaudeSettings(deviceSecureStore());
