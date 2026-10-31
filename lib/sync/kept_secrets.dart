/// A few secrets kept in the device's secure store and read into memory once, so the code that draws a page or reads
/// the settings can ask for one without waiting ([KeptSecrets.peek]), as Claude's settings do with their key
/// (lib/claude/claude_settings.dart). Made for the calendars' and the webhooks' secrets (docs/MARKDOWN_FIRST.md §11
/// decision 22; Matt, 2026-10-31): Google's refresh token, each iCal address and each outgoing webhook's secret sat in
/// the clear in the device's settings blob (`glyph-preferences`), which the export's settings.json dumped whole; now
/// each is here, by name, and travels to the account's other devices as a sealed key (lib/sync/sealed_keys.dart,
/// listed in lib/sync/connections.dart), while the settings keep only what names it (an address's id, a hook's id).
///
/// The migration is read-both: a value still in the settings blob (written by an older build, here or on another
/// device) is read as it was, written here, and taken out of the blob once it is ([CalendarService], [WebhookSender]
/// do that for theirs). What is written here is written to the cache first and the store after, so a page reads a
/// secret the moment it is set.
library;

import 'package:flutter/foundation.dart';

import '../account/device_keys.dart' show SecureStore, deviceSecureStore;

/// What answers a secret by its secure-store name, with no wait: [KeptSecrets.peek], or a test's map.
typedef SecretPeek = String? Function(String name);

class KeptSecrets extends ChangeNotifier {
  /// Over [store], the device's own when left out (asked for lazily: the device's is known only after launch).
  KeptSecrets([SecureStore? store]) : _store = store;

  SecureStore? _store;
  SecureStore get store => _store ??= deviceSecureStore();

  final Map<String, String?> _held = {};
  final Set<String> _loaded = {};
  final Map<String, Future<void>> _loading = {};

  /// Reads every name in [names] not read yet, so [peek] answers for each. A name that will not read is held as none.
  Future<void> load(Iterable<String> names) async {
    final waits = <Future<void>>[];
    for (final name in names) {
      if (_loaded.contains(name)) continue;
      waits.add(_loading.putIfAbsent(name, () => _read(name)));
    }
    if (waits.isNotEmpty) await Future.wait(waits);
  }

  Future<void> _read(String name) async {
    String? value;
    try {
      value = await store.read(name);
    } catch (_) {
      value = null;
    }
    // Written meanwhile: what was written stands.
    if (!_held.containsKey(name)) _held[name] = value;
    _loaded.add(name);
    _loading.remove(name);
  }

  /// Whether [name] has been read from the store (or written) since launch: before that [peek] says nothing of it.
  bool loaded(String name) => _loaded.contains(name);

  /// The value held under [name], with no wait: null for none, and for one not [load]ed yet.
  String? peek(String name) => _held[name];

  /// The value kept under [name], read from the store where it has not been yet.
  Future<String?> read(String name) async {
    await load([name]);
    return _held[name];
  }

  /// Keeps [value] under [name], null taking it away: in memory at once, in the store after. Tells the listeners.
  Future<void> write(String name, String? value) async {
    final was = _held[name];
    _held[name] = value;
    _loaded.add(name);
    if (was != value) notifyListeners();
    try {
      await store.write(name, value);
    } catch (failure) {
      // Held until the app closes; what it was is not said.
      debugPrint('[secrets] “$name” was not kept: ${failure.runtimeType}');
    }
  }

  /// Every name held with a value, among those loaded or written.
  Iterable<String> get names => [for (final MapEntry(:key, :value) in _held.entries) if (value != null) key];
}

/// The app's: the calendars' and the webhooks' secrets, over the device's secure store.
final KeptSecrets integrationSecrets = KeptSecrets();
