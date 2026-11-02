/// Which AI the contradiction finder asks (docs/CONTRADICTIONS.md, "Which AI"; Matt, 2026-11-02, asking for "whatever AI
/// is connected"): the provider layer every other AI feature uses, with Local only kept.
///
/// [pickContradictionAi] is the rule, pure: Local only on, the on-device model and nothing else (none on the device, and
/// the run waits); otherwise whoever answers the chat (lib/assistant/assistant.dart `AssistantChoice.chatBy`: Claude
/// with the person's key, or OpenAI, Gemini, a custom endpoint or Aster); with none set up, the on-device model.
/// [appContradictionAi] is the rule over the app's own choice, settings and model.
///
/// A cloud request is counted by its provider's spending meter (lib/claude/claude_spend.dart `meterClaude`) and refused
/// once the month's limit is reached, as a meeting's write-up is.
library;

import 'dart:async';

import '../../assistant/app_assistant.dart' show appAssistant;
import '../../assistant/assistant.dart' show AiRoute, claudeAssistantId;
import '../../assistant/provider.dart' show aiText;
import '../../claude/claude_settings.dart' show claudeSettings;
import '../../claude/claude_spend.dart' show claudeLimitError, meterClaude;
import '../../claude/messages_api.dart' show ClaudeApi;
import '../../core/preferences.dart' show preferences;
import '../available.dart' show modelNow;
import '../backend.dart' show RunOptions, aiBackend, generate, listModels;
import 'compare.dart' show compareMaxTokens;

/// One question asked: its answer, and how to stop it.
class ContradictionAsk {
  const ContradictionAsk(this.answer, this.cancel);
  final Future<String> answer;
  final void Function() cancel;
}

/// The AI a run asks.
abstract interface class ContradictionAi {
  /// Its name as the page says it: "Claude", "OpenAI", "this device".
  String get name;

  /// Whether it runs on the device, so nothing of a note leaves it.
  bool get onDevice;

  /// How long a request of six pairs takes, roughly: for the cost question.
  Duration get perRequest;

  ContradictionAsk ask({required String system, required String prompt});
}

/// Who the finder asks now (see the header): [localOnly], whether [device] has a model ([deviceReady]), and who answers
/// the chat ([chatBy], null for nobody). Null with nobody to ask.
ContradictionAi? pickContradictionAi({
  required bool localOnly,
  required String? chatBy,
  required bool deviceReady,
  required ContradictionAi Function() device,
  required ContradictionAi Function(String by) cloud,
}) {
  if (localOnly) return deviceReady ? device() : null;
  if (chatBy != null) return cloud(chatBy);
  return deviceReady ? device() : null;
}

/// What the page says when [pickContradictionAi] has nobody: Local only with no model, or nothing set up.
String noAiWords({required bool localOnly}) =>
    localOnly ? 'Needs a model on this device (Settings › AI), since Local only is on.' : 'Needs an AI: add Claude or another AI plugin, or a model on this device (Settings › AI).';

/// The app's own AI for the finder now: [pickContradictionAi] over the preferences, the assistant's choice and the
/// device's models.
Future<ContradictionAi?> appContradictionAi() async {
  await appAssistant.load();
  String? model;
  if (aiBackend.available) {
    try {
      model = modelNow(await listModels());
    } catch (_) {
      model = null;
    }
  }
  return pickContradictionAi(
    localOnly: preferences.value.localOnly,
    chatBy: appAssistant.chatBy,
    deviceReady: model != null,
    device: () => _DeviceAi(model!),
    cloud: (by) => by == claudeAssistantId ? const _ClaudeAi() : _RouteAi(appAssistant.chatRoute!),
  );
}

/// The name of who would answer now, without asking anything: for the page's line.
String appContradictionAiName() {
  if (preferences.value.localOnly) return 'this device';
  final by = appAssistant.chatBy;
  return by == null ? 'this device' : appAssistant.nameOf(by);
}

Map<String, Object?> _body(String model, String system, String prompt) => {
      'model': model,
      'max_tokens': compareMaxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    };

class _ClaudeAi implements ContradictionAi {
  const _ClaudeAi();

  @override
  String get name => 'Claude';

  @override
  bool get onDevice => false;

  @override
  Duration get perRequest => const Duration(seconds: 12);

  @override
  ContradictionAsk ask({required String system, required String prompt}) {
    final key = claudeSettings.key;
    if (key == null) return ContradictionAsk(Future.error(StateError('Add your Anthropic API key in Settings › Claude.')), () {});
    if (claudeSettings.spend.reached) return ContradictionAsk(Future.error(claudeLimitError(claudeSettings.spend)), () {});
    final model = claudeSettings.model;
    final call = meterClaude(ClaudeApi(key: key).stream(_body(model, system, prompt)), model: model, spend: claudeSettings.spend);
    return ContradictionAsk(aiText(call, who: 'Claude'), call.cancel);
  }
}

class _RouteAi implements ContradictionAi {
  const _RouteAi(this.route);
  final AiRoute route;

  @override
  String get name => route.name;

  @override
  bool get onDevice => false;

  @override
  Duration get perRequest => const Duration(seconds: 12);

  @override
  ContradictionAsk ask({required String system, required String prompt}) {
    if (route.spend.reached) return ContradictionAsk(Future.error(claudeLimitError(route.spend)), () {});
    final call = meterClaude(route.api().stream(_body(route.model, system, prompt)), model: route.model, spend: route.spend);
    return ContradictionAsk(aiText(call, who: route.name), call.cancel);
  }
}

class _DeviceAi implements ContradictionAi {
  const _DeviceAi(this.model);
  final String model;

  @override
  String get name => 'this device';

  @override
  bool get onDevice => true;

  @override
  Duration get perRequest => const Duration(seconds: 45);

  @override
  ContradictionAsk ask({required String system, required String prompt}) {
    final run = generate(RunOptions(model: model, system: system, prompt: prompt, maxTokens: compareMaxTokens, temperature: 0.1, onProgress: (_) {}));
    return ContradictionAsk(run.done.then((output) => output.text), run.cancel);
  }
}
