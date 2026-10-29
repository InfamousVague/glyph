/// What one AI provider's plugin is set up with on this device (docs/AI_PROVIDERS.md, "The key"): the person's key for
/// it, the model, the address for an OpenAI-compatible endpoint, whether it may write meetings up, whether its model
/// takes tools, the prices its spending limit counts at, and the limit itself. Claude's own are
/// lib/claude/claude_settings.dart, as they were; these are the other providers', one class for all of them, each
/// under its own [prefix] (`openai`, `gemini`, `custom-ai`, `aster`).
///
/// **Kept as Claude's are**: in the device's secure storage (lib/account/device_keys.dart [SecureStore]), never in the
/// preferences in the clear, never in the library folder a backup copies; and **they follow the account** as Claude's
/// do (lib/sync/connections.dart, sealed by lib/sync/sealed_keys.dart): every name in [syncedNames] is sealed under the
/// account key into the synced settings and written back into another device's store under the same name, then
/// [reload] reads them again. What this month has cost ([spendName]) stays each device's, as Claude's count does.
///
/// The names, for a prefix `p`: `p-api-key`, `p-model`, `p-base-url`, `p-meetings` (`off` or anything else), `p-tools`
/// (`off` or anything else), `p-rates` (`{input, output, cached}`, US dollars a million tokens), `p-spend` and
/// `p-limit` (lib/claude/claude_spend.dart's two).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../account/device_keys.dart' show SecureStore;
import '../claude/claude_spend.dart';
import 'provider.dart';

/// The rates a provider's limit counts at until the person sets their model's (see [AiProviderSettings.rates]):
/// high on purpose, so a limit is reached early rather than late. Not any model's price.
const AiRates aiCautiousRates = AiRates(input: 10, output: 40);

/// A provider's settings (see the header).
class AiProviderSettings extends ChangeNotifier {
  AiProviderSettings(
    this._store, {
    required this.prefix,
    required this.name,
    this.keyOptional = false,
    this.needsBase = false,
    this.fallbackModels = const [],
    this.defaultRates = aiCautiousRates,
    this.ratesFor,
    DateTime Function()? now,
  }) {
    spend = ClaudeSpend(_store, now: now, spendName: spendName, limitName: limitName, price: (model, usage) => aiCost(rates, input: usage.input + usage.cacheWrite5m + usage.cacheWrite1h, cached: usage.cacheRead, output: usage.output), who: name, place: 'Settings › $name');
    // Heard through the settings: the page, the runner and the write-ups' queue look again as the count changes.
    spend.addListener(notifyListeners);
  }

  final SecureStore _store;

  /// The names' start in the store: `openai`.
  final String prefix;

  /// The provider's name as the app says it: "OpenAI".
  final String name;

  /// Whether it can be asked with no key (an endpoint on the person's own computer, LM Studio's or Ollama's).
  final bool keyOptional;

  /// Whether it needs an address ([baseUrl]) before it can be asked: the OpenAI-compatible endpoint's.
  final bool needsBase;

  /// The models to offer when the provider's own list cannot be read, first the default; said on the page to be
  /// possibly out of date.
  final List<AiModelInfo> fallbackModels;

  /// The rates counted at until others are set (see [rates]).
  final AiRates defaultRates;

  /// The provider's published prices for a model, by its id, where the plugin knows them (Aster's three); null for a
  /// model it doesn't, which is counted at [defaultRates].
  final AiRates? Function(String model)? ratesFor;

  /// What this provider has spent this month on this device, and the limit on it.
  late final ClaudeSpend spend;

  /// Where they are kept: the synced keys read and write it by [syncedNames], then [reload].
  SecureStore get store => _store;

  String get keyName => '$prefix-api-key';
  String get modelName => '$prefix-model';
  String get baseName => '$prefix-base-url';
  String get meetingsName => '$prefix-meetings';
  String get toolsName => '$prefix-tools';
  String get ratesName => '$prefix-rates';
  String get spendName => '$prefix-spend';
  String get limitName => '$prefix-limit';

  /// The names that follow the account (see the header): all but this month's count.
  List<String> get syncedNames => [keyName, modelName, if (needsBase) baseName, meetingsName, toolsName, ratesName, limitName];

  String? _key;
  String? _model;
  String? _base;
  bool _meetings = true;
  bool _tools = true;
  AiRates? _rates;
  bool _loaded = false;
  Future<void>? _loading;

  /// The models the provider listed last ([setModels]), in memory: the page's and the setup's picker.
  List<AiModelInfo> _listed = const [];

  /// The models that refused tools this run of the app ([toolsRefused]): asked without them from then on, and said
  /// so once.
  final Set<String> _noTools = {};

  bool get loaded => _loaded;

  String? get key => _key;
  bool get hasKey => (_key ?? '').trim().isNotEmpty;

  /// The address an OpenAI-compatible endpoint is at, with no slash at its end: `https://openrouter.ai/api/v1`.
  String? get baseUrl => _base;
  bool get hasBase => (_base ?? '').isNotEmpty;

  /// The model chosen, or none.
  String? get chosenModel => _model;

  /// The model asked: the one chosen, else the first the provider listed, else the first of [fallbackModels]; '' for
  /// none at all (an endpoint whose model must be typed).
  String get model => _model ?? (_listed.isNotEmpty ? _listed.first.id : (fallbackModels.isNotEmpty ? fallbackModels.first.id : ''));

  /// Whether it can be asked: a key (where one is needed), an address (where one is), and a model.
  bool get ready => (keyOptional || hasKey) && (!needsBase || hasBase) && model.isNotEmpty;

  /// Whether a meeting's summary may be this provider's to write: Write meeting summaries with (its name), on unless turned
  /// off, as Claude's is. Which provider writes them, of those that may, is the AI page's choice
  /// (lib/assistant/assistant.dart).
  bool get meetings => _meetings;

  /// Whether the model is offered the app's tools: on unless turned off, for a model the person knows has none. One
  /// that refuses them is asked without them anyway ([toolsRefused]).
  bool get tools => _tools;

  /// The rates the limit counts at: the person's, else the listing's for the model where it says (OpenRouter's), else
  /// the plugin's published prices for it ([ratesFor]), else [defaultRates].
  AiRates get rates => _rates ?? _knownRates ?? defaultRates;

  AiRates? get _knownRates => _listed.where((m) => m.id == model).firstOrNull?.rates ?? ratesFor?.call(model);

  /// Whether the person set the rates.
  bool get ratesChosen => _rates != null;

  /// Whether the rates counted at are the model's own, as the listing or the plugin has them, rather than the person's
  /// or the high guess.
  bool get ratesKnown => _rates == null && _knownRates != null;

  /// The models listed last, or the fallback's where none were.
  List<AiModelInfo> get listed => _listed;

  /// What is held of [name] now, with no wait, for the synced keys to notice a change made here (lib/sync/connections.dart):
  /// compared, never kept or said.
  Object? peek(String name) {
    if (name == keyName) return _key;
    if (name == modelName) return _model;
    if (name == baseName) return _base;
    if (name == meetingsName) return _meetings;
    if (name == toolsName) return _tools;
    if (name == ratesName) return _rates?.toJson().toString();
    if (name == limitName) return spend.limitText;
    return null;
  }

  /// Whether [model] refused tools in this run of the app.
  bool toolsRefused(String model) => _noTools.contains(model);

  /// [model] refused tools: it is asked without them from now on. Answers whether that is news.
  bool refuseTools(String model) => _noTools.add(model);

  /// Reads what this device keeps. Once; later calls wait for the same read, or for nothing once it is done (see
  /// lib/assistant/assistant.dart `AssistantChoice.load`).
  Future<void> load() => _loaded ? Future<void>.value() : (_loading ??= _load());

  Future<void> _load() async {
    await _read();
    await spend.load();
    _loaded = true;
    notifyListeners();
  }

  /// Reads the store again, once another device's settings were written into it (lib/sync/sealed_keys.dart).
  Future<void> reload() async {
    await load();
    await _read();
    await spend.reloadLimit();
    notifyListeners();
  }

  Future<void> _read() async {
    try {
      final key = await _store.read(keyName);
      final model = await _store.read(modelName);
      final base = needsBase ? await _store.read(baseName) : null;
      final meetings = await _store.read(meetingsName);
      final tools = await _store.read(toolsName);
      final rates = await _store.read(ratesName);
      _key = (key ?? '').trim().isEmpty ? null : key!.trim();
      _model = (model ?? '').trim().isEmpty ? null : model!.trim();
      _base = needsBase ? aiBaseUrl(base ?? '') : null;
      _meetings = meetings != 'off';
      _tools = tools != 'off';
      _rates = rates == null ? null : AiRates.fromJson(_decode(rates));
    } catch (_) {
      // A store that cannot be read is a device with nothing set.
    }
  }

  static Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  /// Keeps [key] (trimmed), or forgets it for null or blank.
  Future<void> setKey(String? key) async {
    final k = (key ?? '').trim();
    _key = k.isEmpty ? null : k;
    notifyListeners();
    await _store.write(keyName, _key);
  }

  /// Keeps the model, or goes back to the default with null or blank.
  Future<void> setModel(String? id) async {
    final m = (id ?? '').trim();
    final next = m.isEmpty ? null : m;
    if (next == _model) return;
    _model = next;
    notifyListeners();
    await _store.write(modelName, next);
  }

  /// Keeps the endpoint's address, made plain ([aiBaseUrl]); null or blank forgets it.
  Future<void> setBaseUrl(String? url) async {
    final b = aiBaseUrl(url ?? '');
    _base = b;
    _listed = const [];
    notifyListeners();
    await _store.write(baseName, b);
  }

  Future<void> setMeetings(bool on) async {
    if (on == _meetings) return;
    _meetings = on;
    notifyListeners();
    await _store.write(meetingsName, on ? 'on' : 'off');
  }

  Future<void> setTools(bool on) async {
    if (on == _tools) return;
    _tools = on;
    notifyListeners();
    await _store.write(toolsName, on ? 'on' : 'off');
  }

  /// Sets the rates the limit counts at, or goes back to the default with null.
  Future<void> setRates(AiRates? rates) async {
    if (rates == _rates) return;
    _rates = rates;
    notifyListeners();
    await _store.write(ratesName, rates == null ? null : jsonEncode(rates.toJson()));
  }

  /// The models the provider listed, as read now: kept in memory for the pickers. Where no model is chosen yet, the
  /// first listed (the provider's flagship, as its client sorts them) is kept as the choice, so the default is the
  /// provider's own list's and stays the same after the app starts again, until the person chooses another.
  void setModels(List<AiModelInfo> models) {
    _listed = List.unmodifiable(models);
    notifyListeners();
    if (_model == null && models.isNotEmpty) unawaited(setModel(models.first.id));
  }
}

/// An endpoint's address made plain: trimmed, `https://` put in front of one with no scheme (but `http://` for the
/// person's own computer), and no slash at its end. Null for blank.
String? aiBaseUrl(String text) {
  var url = text.trim();
  if (url.isEmpty) return null;
  if (!url.contains('://')) {
    final local = RegExp(r'^(localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0|192\.168\.|10\.)').hasMatch(url);
    url = '${local ? 'http' : 'https'}://$url';
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}
