/// The AIs a cleanup can be asked by: whatever the person has connected (Matt, 2026-11-02: "use whatever AI we choose
/// that's connected"), through the app's own provider layer (docs/AI_PROVIDERS.md, lib/assistant/), and the model on
/// the device (lib/ai/backend.dart). docs/CLEANUP.md, "The page" and "Privacy".
///
/// Listed only when it can answer now ([connectedAis]): Claude with its plugin on and a key kept; OpenAI, Gemini, the
/// custom endpoint and Aster each with its plugin on and set up (`AiPlugged.ready`); the device's model where the
/// engine is here and a model is downloaded. Local only lists the device's alone: the cloud providers' plugins are held
/// off by the registry, and this asks again for itself.
///
/// Every ask goes through the provider's own client with the person's own key, counted against its spending limit
/// (lib/claude/claude_spend.dart `meterClaude`), and is read whole ([aiText]); a limit reached is an error before
/// anything is sent.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../ai/available.dart' show modelNow;
import '../../ai/backend.dart' show RunOptions, aiBackend, generate, listModels, modelName;
import '../../assistant/assistant.dart' show AiPlugged, AssistantChoice, claudeAssistantId;
import '../../assistant/provider.dart' show AiError, aiText;
import '../../claude/claude_spend.dart' show claudeLimitError, meterClaude;
import '../../claude/messages_api.dart' show ClaudeApi;
import 'prompts.dart' show CleanupSizes;

/// The device's own model's id among the choices.
const String deviceAiId = 'device';

/// One ask in flight: its answer, and the way to stop it.
class CleanupAsking {
  CleanupAsking(this.done, this.cancel);

  final Future<String> done;
  final VoidCallback cancel;
}

/// Asks [system] and [prompt], with room for [maxTokens] of answer.
typedef CleanupAsk = CleanupAsking Function(String system, String prompt, {required int maxTokens});

/// One AI a run can ask.
@immutable
class CleanupAi {
  const CleanupAi({required this.id, required this.name, required this.ask, this.local = false, this.plugin, this.model});

  /// `claude`, another provider's plugin id, or [deviceAiId].
  final String id;

  /// What the page calls it: "Claude", "OpenAI", "On this device".
  final String name;
  final CleanupAsk ask;

  /// The device's own model: nothing leaves the device.
  final bool local;

  /// The plugin whose mark the job wears (`claude`, `openai`); null for the device's model.
  final String? plugin;

  /// The model it asks, for the page's line.
  final String? model;

  CleanupSizes get sizes => local ? CleanupSizes.device : CleanupSizes.cloud;
}

/// A cloud provider's request in the Messages API's shape.
Map<String, Object?> _body(String model, String system, String prompt, int maxTokens) => {
      'model': model,
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    };

/// Claude, with [choice]'s settings: its key, its model, its limit.
CleanupAi claudeCleanupAi(AssistantChoice choice, {ClaudeApi Function(String key)? api}) {
  final settings = choice.claude;
  return CleanupAi(
    id: claudeAssistantId,
    name: 'Claude',
    plugin: claudeAssistantId,
    model: settings.model,
    ask: (system, prompt, {required maxTokens}) {
      final key = settings.key;
      if (key == null || key.trim().isEmpty) return CleanupAsking(Future<String>.error(const AiError('Add your Anthropic API key in Settings › Claude.')), () {});
      if (settings.spend.reached) return CleanupAsking(Future<String>.error(claudeLimitError(settings.spend)), () {});
      final call = meterClaude((api ?? (k) => ClaudeApi(key: k))(key).stream(_body(settings.model, system, prompt, maxTokens)), model: settings.model, spend: settings.spend);
      return CleanupAsking(aiText(call, who: 'Claude'), call.cancel);
    },
  );
}

/// Another provider ([plugged]): its client over its settings, counted by its own meter.
CleanupAi otherCleanupAi(AiPlugged plugged) => CleanupAi(
      id: plugged.id,
      name: plugged.name,
      plugin: plugged.id,
      model: plugged.settings.model,
      ask: (system, prompt, {required maxTokens}) {
        final settings = plugged.settings;
        if (!settings.ready) return CleanupAsking(Future<String>.error(AiError('Set up ${plugged.name} in Settings › ${plugged.name}.')), () {});
        if (settings.spend.reached) return CleanupAsking(Future<String>.error(claudeLimitError(settings.spend)), () {});
        final call = meterClaude(plugged.client(settings).stream(_body(settings.model, system, prompt, maxTokens)), model: settings.model, spend: settings.spend);
        return CleanupAsking(aiText(call, who: plugged.name), call.cancel);
      },
    );

/// The device's own [model] (lib/ai/backend.dart `generate`).
CleanupAi deviceCleanupAi(String model) => CleanupAi(
      id: deviceAiId,
      name: 'On this device',
      local: true,
      model: modelName(model),
      ask: (system, prompt, {required maxTokens}) {
        final run = generate(RunOptions(model: model, system: system, prompt: prompt, maxTokens: maxTokens, temperature: 0.1, onProgress: (_) {}));
        return CleanupAsking(run.done.then((output) => output.text), run.cancel);
      },
    );

/// The device's model that would run now, or null: no engine here, or no model on it.
Future<String?> deviceModelNow() async {
  if (!aiBackend.available) return null;
  try {
    return modelNow(await listModels());
  } catch (_) {
    return null;
  }
}

/// The AIs that can be asked now (see the library doc): Claude, then the others in Automatic's order, then the
/// device's model; with [localOnly], the device's alone. [deviceModel] says which model the device would run.
Future<List<CleanupAi>> connectedAis({AssistantChoice? choice, required bool localOnly, Future<String?> Function()? deviceModel, ClaudeApi Function(String key)? claudeApi}) async {
  final device = await (deviceModel ?? deviceModelNow)();
  final found = <CleanupAi>[];
  if (!localOnly && choice != null) {
    await choice.load();
    if (choice.claudeOn() && choice.claude.hasKey) found.add(claudeCleanupAi(choice, api: claudeApi));
    for (final other in choice.others) {
      if (other.ready) found.add(otherCleanupAi(other));
    }
  }
  if (device != null) found.add(deviceCleanupAi(device));
  return found;
}

/// The one chosen to begin with: [chosen] where it is among [ais]; under Local only the device's; else the app's own
/// choice for the assistant ([AssistantChoice.chatBy]); else the first.
String? defaultAiId(List<CleanupAi> ais, {AssistantChoice? choice, String? chosen, required bool localOnly}) {
  if (ais.isEmpty) return null;
  bool has(String? id) => id != null && ais.any((ai) => ai.id == id);
  if (has(chosen)) return chosen;
  if (localOnly) return has(deviceAiId) ? deviceAiId : null;
  final app = choice?.chatBy;
  if (has(app)) return app;
  return ais.first.id;
}
