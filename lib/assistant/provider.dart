/// What the app asks of a cloud model, whoever's it is (docs/AI_PROVIDERS.md; Matt, 2026-10-29: "Add support for aster
/// 6 and other Ai models as plugins in addition to claude like openAI google gemini etc"). One interface, [AiProvider],
/// with Claude's client (lib/claude/messages_api.dart `ClaudeApi`) one of its kinds and each other provider's client
/// in its own plugin's folder: OpenAI's and any OpenAI-compatible endpoint's (lib/plugins/openai/chat_api.dart, used by
/// lib/plugins/custom_ai/), Google's Gemini (lib/plugins/gemini/gemini_api.dart).
///
/// **The conversation has one shape: the Messages API's.** Claude's run (lib/claude/claude_run.dart) was written round
/// it, with its blocks of text, thinking and tool calls, its tool results and its stream of events; rather than write a
/// second run, every other client takes a request in that shape and answers in it ([AiStreamer.stream]). A request is
/// `{model, max_tokens, system, tools: [{name, description, input_schema}], messages: [{role, content}]}`, `content`
/// being a string or the API's blocks (`text`, `tool_use`, `tool_result`, `thinking`); the events are the Messages
/// API's ([AiCall]). Each client translates both ways as it goes, and drops what its provider has no word for
/// (Claude's thinking blocks and their signatures, `output_config`, `thinking`). So the tools, the live typing into a
/// note, the follow-up asks and the spending limit are the same code for every provider, and Claude's own path is the
/// one it always was.
///
/// What a provider is asked:
/// - **A streamed chat with tools** ([AiStreamer.stream]): the run's every turn.
/// - **One completion** ([aiText]): a meeting's write-up, read whole from the same stream.
/// - **Its models** ([AiProvider.models]): read from the provider at setup and on its page, never written here, with a
///   small list of the plugin's own as the fallback, said to be possibly out of date.
/// - **Whether a key works** ([AiProvider.check]): one small read, the models list, which no provider bills.
/// - **What it used** (the `usage` of `message_start` and `message_delta`), priced by the plugin's [AiRates] for the
///   spending meter (lib/claude/claude_spend.dart).
/// - **Its errors in plain words** ([AiError]): each client maps its provider's (a refused key, no credit, too many
///   requests, no connection) to a sentence and to the Messages API's error types, so the setup and the meetings'
///   queue read them alike.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ai_call.dart';

export 'ai_call.dart';

/// What streams one request in the conversation's shape (see the header).
abstract interface class AiStreamer {
  /// Streams one request ([body] in the Messages API's shape; `stream` is set by the client).
  AiCall stream(Map<String, Object?> body);
}

/// One provider's client, with one key.
abstract interface class AiProvider implements AiStreamer {
  /// Whether the key works: null when it does, else what is wrong. One small read of the models the key may use.
  Future<AiError?> check();

  /// The models the key may ask, as the provider lists them now. Throws [AiError] where it cannot be read.
  Future<List<AiModelInfo>> models();
}

/// One model a provider lists.
@immutable
class AiModelInfo {
  const AiModelInfo(this.id, {String? name, this.about = '', this.rates}) : name = name ?? id;

  /// The provider's own id: what a request names.
  final String id;

  /// What a person reads: the provider's display name where it gives one, else the id.
  final String name;
  final String about;

  /// What the provider says the model costs, where its listing says (OpenRouter's does); null for most.
  final AiRates? rates;

  @override
  bool operator ==(Object other) => other is AiModelInfo && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AiModelInfo($id)';
}

/// What a provider charges, in US dollars per million tokens: the spending meter's prices for a provider whose API
/// does not say them (docs/AI_PROVIDERS.md, "Spending limit").
@immutable
class AiRates {
  const AiRates({required this.input, required this.output, double? cachedInput}) : cachedInput = cachedInput ?? input;

  /// Input not read from a cache.
  final double input;
  final double output;

  /// Input read from the provider's cache, where it reports any; the input's rate where not said.
  final double cachedInput;

  Map<String, Object?> toJson() => {'input': input, 'output': output, 'cached': cachedInput};

  /// Reads [toJson]'s; null for anything else.
  static AiRates? fromJson(Object? json) {
    if (json is! Map) return null;
    final input = json['input'], output = json['output'], cached = json['cached'];
    if (input is! num || output is! num || input < 0 || output < 0) return null;
    return AiRates(input: input.toDouble(), output: output.toDouble(), cachedInput: cached is num && cached >= 0 ? cached.toDouble() : null);
  }

  @override
  bool operator ==(Object other) => other is AiRates && other.input == input && other.output == output && other.cachedInput == cachedInput;

  @override
  int get hashCode => Object.hash(input, output, cachedInput);
}

/// What [input], [cached] and [output] tokens cost at [rates], in US dollars.
double aiCost(AiRates rates, {required int input, required int output, int cached = 0}) => (input * rates.input + cached * rates.cachedInput + output * rates.output) / 1000000;

/// One completion read whole from [call]: the text of every text block joined, thinking left alone. [who] names the
/// model in what is said when it did not answer ("Claude declined to write this one up."). Throws the stream's
/// [AiError], or one for a stream that ended in a refusal, out of room, or with no words. [onText] is told the words so
/// far as each piece of them arrives, for what draws them as they come (a meeting's summary being written, in its note:
/// lib/editor/ai/summary_writing.dart).
Future<String> aiText(AiCall call, {String who = 'Claude', void Function(String sofar)? onText}) async {
  final text = StringBuffer();
  String? stop;
  Object? failure;
  await for (final event in call.events.handleError((Object error) => failure ??= error)) {
    final data = aiJson(event.data);
    switch (event.event) {
      case 'content_block_delta':
        final delta = data['delta'];
        if (delta is Map && delta['type'] == 'text_delta') {
          text.write(delta['text'] as String? ?? '');
          onText?.call(text.toString());
        }
      case 'message_delta':
        final delta = data['delta'];
        if (delta is Map && delta['stop_reason'] is String) stop = delta['stop_reason'] as String;
      case 'error':
        final error = data['error'];
        failure ??= AiError(error is Map ? (error['message'] as String? ?? '$who stopped with an error.') : '$who stopped with an error.', type: error is Map ? error['type'] as String? : null);
    }
  }
  if (failure != null) throw failure!;
  // A decline is checked before the words: what streamed before it is not the answer.
  if (stop == 'refusal') throw AiError('$who declined to write this one up.', type: 'refusal');
  if (stop == 'max_tokens') throw AiError('$who’s write-up ran out of room and was cut off.');
  final said = text.toString().trim();
  if (said.isEmpty) throw AiError('$who answered with nothing.');
  return said;
}

/// An event's data as a map: `{}` for anything that is not one.
Map<String, Object?> aiJson(String data) {
  try {
    final parsed = jsonDecode(data);
    return parsed is Map ? parsed.cast<String, Object?>() : const {};
  } catch (_) {
    return const {};
  }
}

/// The text of a message's `content`, a string or the API's blocks: the text blocks joined.
String aiContentText(Object? content) {
  if (content is String) return content;
  if (content is! List) return '';
  return [
    for (final block in content)
      if (block is Map && block['type'] == 'text' && block['text'] is String) block['text'] as String,
  ].join('\n\n');
}

/// The words a `tool_result` block carries, a string or the API's blocks, as one string.
String aiToolResultText(Object? content) => content is String ? content : aiContentText(content);
