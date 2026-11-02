/// Who answers a question (docs/ASK_THE_ORG.md, "The AI"; Matt, 2026-11-02, "'Ask the org' with receipts"):
/// whatever is connected, as the chat chooses (lib/assistant/assistant.dart `chatBy`), through the provider layer and
/// its spending limit; or, with Local only on or no cloud model set up, the device's own model, sent fewer passages.
library;

import 'dart:async';

import '../ai/backend.dart' as device;
import '../ai/runs.dart' show splitThinking;
import '../assistant/assistant.dart';
import '../assistant/provider.dart';
import '../claude/claude_settings.dart' show ClaudeSettings;
import '../claude/claude_spend.dart' show ClaudeSpend, claudeLimitError, meterClaude;
import '../claude/messages_api.dart' show ClaudeApi;
import 'ask_retrieve.dart' show AskBudget;

/// One answer being written: the model's words when done, and the way to stop it.
typedef AskCall = ({Future<String> done, void Function() cancel});

/// What answers (see the library's doc).
abstract interface class AskModel {
  /// "Claude", "Gemini", "Gemma 3 1B".
  String get name;

  /// Whether it runs on this device: fewer passages are sent, and the sheet says retrieval may be poorer.
  bool get onDevice;

  /// How much it is sent.
  AskBudget get budget;

  AskCall complete({required String system, required String prompt});
}

/// The most an answer may run to.
const int askMaxTokens = 1600;

/// A cloud model through the provider layer, metered on its spending limit.
class CloudAskModel implements AskModel {
  CloudAskModel({required this.name, required this.api, required this.model, this.spend});

  @override
  final String name;
  final AiStreamer api;
  final String model;
  final ClaudeSpend? spend;

  @override
  bool get onDevice => false;

  @override
  AskBudget get budget => AskBudget.cloud;

  @override
  AskCall complete({required String system, required String prompt}) {
    final spend = this.spend;
    if (spend != null && spend.reached) return (done: Future<String>.error(claudeLimitError(spend)), cancel: () {});
    final body = {
      'model': model,
      'max_tokens': askMaxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    };
    final asked = api.stream(body);
    final call = spend == null ? asked : meterClaude(asked, model: model, spend: spend);
    return (done: aiText(call, who: name), cancel: call.cancel);
  }
}

/// The device's formatting model (lib/ai/backend.dart `generate`).
class DeviceAskModel implements AskModel {
  DeviceAskModel(this.model, {String? name}) : name = name ?? device.modelSpec(model)?.name ?? 'the model on this device';

  final String model;

  @override
  final String name;

  @override
  bool get onDevice => true;

  @override
  AskBudget get budget => AskBudget.device;

  @override
  AskCall complete({required String system, required String prompt}) {
    final run = device.generate(device.RunOptions(model: model, system: system, prompt: prompt, maxTokens: askMaxTokens, temperature: 0.1, onProgress: (_) {}));
    return (done: run.done.then((output) => splitThinking(output.text, output.thinking ?? false).answer), cancel: run.cancel);
  }
}

/// Who answers now: with [localOnly], the device's model or nobody; else the chat's choice (Claude with its key, or
/// another provider set up), else the device's model where the device runs one, else nobody (null).
AskModel? askModelFor({required AssistantChoice choice, required ClaudeSettings claude, required bool localOnly, required String deviceModel, bool deviceRuns = true}) {
  final onDevice = deviceRuns && deviceModel.isNotEmpty ? DeviceAskModel(deviceModel) : null;
  if (localOnly) return onDevice;
  final by = choice.chatBy;
  if (by == claudeAssistantId && claude.hasKey) return CloudAskModel(name: 'Claude', api: ClaudeApi(key: claude.key!), model: claude.model, spend: claude.spend);
  final route = choice.chatRoute;
  if (route != null) return CloudAskModel(name: route.name, api: route.api(), model: route.model, spend: route.spend);
  return onDevice;
}
