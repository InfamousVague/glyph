/// Which model does what (docs/AI_PROVIDERS.md, "The assistant"; Matt, 2026-10-29: "Add support for aster 6 and other
/// Ai models as plugins in addition to claude like openAI google gemini etc"): the provider that answers the dock's
/// chat and Ask (with the talk to it and the "Ask Claude" note's runner), and the one that writes meetings up. Settings
/// › AI › Assistant chooses each; Automatic, the default, is:
///
/// - **Claude, where it can answer**: its plugin on and an Anthropic key kept (for meetings, Write meeting summaries
///   with Claude on as well), exactly as before there were others, so nothing changes for a person with Claude set up;
/// - **else the first other provider that can**, in the Market's order (OpenAI, Gemini, Custom AI model): its plugin
///   on, its key (and for the custom endpoint its address and model) kept, and for meetings its own Write meeting
///   summaries with (its name) on;
/// - **else the device**: the chat is not offered, as with no key today, and meetings are the on-device model's.
///
/// A provider chosen by name answers while it can, and Automatic's rule stands in while it cannot (its key forgotten,
/// its plugin off), so a choice never leaves the dock dead while another could answer. "On this device" for meetings
/// keeps them on the device's own model whatever keys are kept.
///
/// The two choices are kept in the device's secure store beside the keys ([assistantChatName],
/// [assistantMeetingsName]) and follow the account with them (lib/sync/connections.dart), as Claude's Write meeting
/// summaries with Claude does.
library;

import 'package:flutter/foundation.dart';

import '../account/device_keys.dart' show SecureStore;
import '../claude/claude_settings.dart' show ClaudeSettings;
import '../claude/claude_spend.dart' show ClaudeSpend;
import 'provider.dart';
import 'provider_settings.dart';

/// The names in the secure store.
const String assistantChatName = 'glyph-assistant-chat';
const String assistantMeetingsName = 'glyph-assistant-meetings';

/// The choices' own words: Automatic (see the header), Claude's id, and the device for meetings.
const String assistantAuto = 'auto';
const String claudeAssistantId = 'claude';
const String assistantDevice = 'device';

/// One provider other than Claude, as the app has it: its plugin's switch, its settings, and its client.
class AiPlugged {
  const AiPlugged({required this.id, required this.name, required this.settings, required this.switchedOn, bool Function()? allowed, required this.client}) : _allowed = allowed;

  /// Its plugin's id: `openai`.
  final String id;
  final String name;
  final AiProviderSettings settings;

  /// Whether its plugin is switched on, whatever Local only says (lib/plugins/registry.dart `switchedOn`): what a
  /// meeting's write-up is chosen by, which Local only then holds (lib/ai/summary_claude.dart).
  final bool Function() switchedOn;

  /// Whether it may be asked now: switched on and not held by Local only (`pluginOn`); [switchedOn] where not given.
  final bool Function()? _allowed;
  bool allowed() => (_allowed ?? switchedOn)();

  /// Its client, over [settings]' key and address.
  final AiProvider Function(AiProviderSettings settings) client;

  /// Whether it can answer the chat now: allowed, and set up.
  bool get ready => allowed() && settings.ready;

  /// Whether it may write meetings up: switched on, set up, and its Write meeting summaries with (its name) on.
  bool get writesMeetings => switchedOn() && settings.ready && settings.meetings;
}

/// What a chat or a write-up is sent with when it is not Claude's (Claude's own path is the one it always was).
class AiRoute {
  const AiRoute(this.by);

  final AiPlugged by;

  String get id => by.id;
  String get name => by.name;
  AiProvider api() => by.client(by.settings);
  String get model => by.settings.model;
  ClaudeSpend get spend => by.settings.spend;

  /// Whether the run offers it the tools: its settings' switch, and its model not found to refuse them.
  bool get tools => by.settings.tools && !by.settings.toolsRefused(model);
}

/// The two choices, and what they come to now (see the header).
class AssistantChoice extends ChangeNotifier {
  AssistantChoice({required SecureStore store, required this.claude, required this.claudeOn, bool Function()? claudeSwitchedOn, required this.others, Listenable? switches})
      : _store = store,
        claudeSwitchedOn = claudeSwitchedOn ?? claudeOn {
    _heard = Listenable.merge([claude, for (final other in others) other.settings, ?switches])..addListener(notifyListeners);
  }

  final SecureStore _store;

  /// Claude's settings, whether its plugin is on (Local only holding it off, `claudeInApp`), and whether it is switched
  /// on whatever Local only says (what meetings are chosen by, as lib/ai/summary_claude.dart has always read it).
  final ClaudeSettings claude;
  final bool Function() claudeOn;
  final bool Function() claudeSwitchedOn;

  /// The others, in the order Automatic tries them.
  final List<AiPlugged> others;

  late final Listenable _heard;

  String _chat = assistantAuto;
  String _meetings = assistantAuto;
  Future<void>? _loading;

  /// The chat's choice: [assistantAuto], [claudeAssistantId] or another's id.
  String get chat => _chat;

  /// The meetings' choice: as [chat]'s, or [assistantDevice].
  String get meetings => _meetings;

  /// Reads the choices, and every provider's settings. Once; later calls wait for the same read, or, once it is done,
  /// for nothing: a finished read is answered with a new future, never the first one again, which belongs to the zone
  /// it was made in (a test's, over by then).
  Future<void> load() => _loaded ? Future<void>.value() : (_loading ??= _load());
  bool _loaded = false;

  Future<void> _load() async {
    await Future.wait([if (!claude.loaded) claude.load(), for (final other in others) other.settings.load()]);
    await _read();
    _loaded = true;
    notifyListeners();
  }

  /// Reads the choices again, once another device's were written into the store (lib/sync/sealed_keys.dart).
  Future<void> reload() async {
    await load();
    await _read();
    notifyListeners();
  }

  Future<void> _read() async {
    try {
      _chat = await _store.read(assistantChatName) ?? assistantAuto;
      _meetings = await _store.read(assistantMeetingsName) ?? assistantAuto;
    } catch (_) {
      // A store that cannot be read is Automatic.
    }
  }

  Future<void> setChat(String choice) async {
    if (choice == _chat) return;
    _chat = choice;
    notifyListeners();
    await _store.write(assistantChatName, choice == assistantAuto ? null : choice);
  }

  Future<void> setMeetings(String choice) async {
    if (choice == _meetings) return;
    _meetings = choice;
    notifyListeners();
    await _store.write(assistantMeetingsName, choice == assistantAuto ? null : choice);
  }

  /// The names that follow the account (lib/sync/connections.dart).
  static const List<String> syncedNames = [assistantChatName, assistantMeetingsName];

  /// Where they are kept.
  SecureStore get store => _store;

  /// What is held of [name] now, for the synced keys to notice a change made here.
  Object? peek(String name) => switch (name) {
        assistantChatName => _chat,
        assistantMeetingsName => _meetings,
        _ => null,
      };

  /// The other provider by [id], or null.
  AiPlugged? other(String? id) => others.where((o) => o.id == id).firstOrNull;

  /// The provider's name as the app says it.
  String nameOf(String id) => id == claudeAssistantId ? 'Claude' : (other(id)?.name ?? id);

  /// Whether any provider's plugin is on: the chat's parts are drawn for it.
  bool get anyOn => claudeOn() || others.any((o) => o.allowed());

  bool get _claudeChats => claudeOn() && claude.hasKey;
  bool get _claudeWrites => claudeSwitchedOn() && claude.hasKey && claude.meetings;

  /// Who answers the chat now: [claudeAssistantId], another's id, or null for nobody (see the header).
  String? get chatBy {
    if (_chat == claudeAssistantId && _claudeChats) return claudeAssistantId;
    final chosen = other(_chat);
    if (chosen != null && chosen.ready) return chosen.id;
    if (_claudeChats) return claudeAssistantId;
    return others.where((o) => o.ready).firstOrNull?.id;
  }

  /// Who writes meetings up now: as [chatBy], each by whether it may write them; null for the device's model.
  String? get meetingsBy {
    if (_meetings == assistantDevice) return null;
    if (_meetings == claudeAssistantId && _claudeWrites) return claudeAssistantId;
    final chosen = other(_meetings);
    if (chosen != null && chosen.writesMeetings) return chosen.id;
    if (_claudeWrites) return claudeAssistantId;
    return others.where((o) => o.writesMeetings).firstOrNull?.id;
  }

  /// Who Automatic would have answer the chat, whatever is chosen.
  String? get autoChatBy => _claudeChats ? claudeAssistantId : others.where((o) => o.ready).firstOrNull?.id;

  /// Who Automatic would have write meetings up, whatever is chosen.
  String? get autoMeetingsBy => _claudeWrites ? claudeAssistantId : others.where((o) => o.writesMeetings).firstOrNull?.id;

  /// The chat's route where another provider answers it; null for Claude's, or for nobody.
  AiRoute? get chatRoute => _routeOf(chatBy);

  /// The meetings' route where another provider writes them; null for Claude's, or the device's.
  AiRoute? get meetingsRoute => _routeOf(meetingsBy);

  AiRoute? _routeOf(String? by) {
    final plugged = by == null || by == claudeAssistantId ? null : other(by);
    return plugged == null ? null : AiRoute(plugged);
  }

  /// The chat's choices as Settings offers them: Automatic, Claude, then the others, each with its name.
  List<(String, String)> get chatChoices => [(assistantAuto, 'Automatic'), (claudeAssistantId, 'Claude'), for (final o in others) (o.id, o.name)];

  /// The meetings', with the device's last.
  List<(String, String)> get meetingsChoices => [...chatChoices, (assistantDevice, 'On this device')];

  @override
  void dispose() {
    _heard.removeListener(notifyListeners);
    super.dispose();
  }
}
