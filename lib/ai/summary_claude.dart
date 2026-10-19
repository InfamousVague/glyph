/// A meeting's write-up through the app's own Claude (docs/CLAUDE_APP.md, "Meetings"). Matt, 2026-10-19: "when
/// claude is enabled the meeting summary should go through claude instead of gemma".
///
/// Claude is **chosen** for meetings when the Claude plugin's switch is on and an API key is kept on this device; it
/// is **enabled** (asked now) when, besides, Local only is off, since Local only holds the plugin off with every
/// plugin that reaches the internet. Chosen but held by Local only, a meeting's write-up waits for Claude rather than
/// going to the phone's own model: summaries are never remade on their own, so a local write-up made in the meantime
/// would stand for good where the person had chosen Claude's, and Local only is the switch a person turns on for a
/// while. Not chosen (the plugin off, or no key), meetings are the on-device model's as they always were.
///
/// What goes to Anthropic, with the person's own key and nowhere else (no Ghost.md server between): the meeting's
/// transcript as the summary queue reads it, in the same pieces and with the same prompts as the on-device model is
/// given (format/prompt.dart, ai/summary_text.dart `transcriptPieces`), so the answer is placed and shaped by the
/// same rules. Only meetings: a long voice note's summary stays on the phone.
///
/// One request a generation, streamed (lib/claude/messages_api.dart [ClaudeApi.streamWith]) and read whole: the text
/// of every text block joined, thinking left alone (the models run adaptive thinking when none is asked for), the
/// effort the person chose sent where one was chosen. `max_tokens` is room for the thinking as well as the words, not
/// the on-device model's budget: the prompt says how long the summary is. Opus 5.5 and Sonnet 5.5 are asked with the
/// server-side fallback (`fallbacks: "default"`), so a request a safety classifier declines is answered by the
/// model Anthropic routes it to rather than refused; what still ends `refusal`, `max_tokens` or with no words is a
/// [ClaudeError] in the queue's words.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../claude/claude_settings.dart' show ClaudeSettings;
import '../claude/messages_api.dart';

/// The room a write-up's request is given: its thinking and its words.
const int claudeSummaryMaxTokens = 16000;

/// The beta the server-side fallback is asked for under (`fallbacks: "default"`).
const String claudeFallbackBeta = 'server-side-fallback-2026-07-01';

/// The models the server-side fallback is asked for (Haiku 5.5 has none).
const Set<String> claudeFallbackModels = {'claude-opus-5-5', 'claude-sonnet-5-5'};

/// Whether [error] is one asking again will not mend: the key refused, the request refused, or Claude declining it.
/// The queue fails such a job at once, for Try again once the person has put it right, rather than three times.
bool claudeLasting(Object error) {
  if (error is! ClaudeError) return false;
  if (error.badKey || error.type == 'refusal' || error.type == 'permission_error' || error.type == 'invalid_request_error') return true;
  final status = error.status;
  return status != null && status >= 400 && status < 500 && status != 408 && status != 409 && status != 429;
}

/// One generation asked of Claude: its text once whole, and the way to stop it.
class ClaudeWriting {
  ClaudeWriting(this.done, this._cancel);

  /// The answer's text, or a [ClaudeError] ([ClaudeCancelled] once stopped).
  final Future<String> done;
  final VoidCallback _cancel;

  void cancel() => _cancel();
}

/// Claude, as the summary queue asks it for a meeting's write-up.
class MeetingClaude {
  MeetingClaude({required this.settings, required this.switchedOn, required this.localOnly, ClaudeApi Function(String key)? api, this.changes})
      : _api = api ?? ((key) => ClaudeApi(key: key));

  /// The key, the model and the effort (lib/claude/claude_settings.dart).
  final ClaudeSettings settings;

  /// Whether the Claude plugin's switch is on, whatever Local only says (lib/plugins/registry.dart `switchedOn`).
  final bool Function() switchedOn;

  /// Whether Local only is on (lib/core/preferences.dart).
  final bool Function() localOnly;

  /// Hears each change of what [chosen] and [enabled] are read from, where the app gives it: the queue looks again,
  /// and the phone's write-up is sent its config again (ai/job_config.dart).
  final Listenable? changes;

  final ClaudeApi Function(String key) _api;

  /// Reads the settings, once.
  Future<void> load() => settings.load();

  /// Meetings are Claude's: the plugin switched on and a key kept (see the header).
  bool get chosen => switchedOn() && settings.hasKey;

  /// Chosen, and held off by Local only: the write-up waits.
  bool get held => chosen && localOnly();

  /// Claude may be asked now.
  bool get enabled => chosen && !localOnly();

  /// The model the person chose, which a write-up is kept as having been made by.
  String get model => settings.model;

  /// The request for one generation: [system] and [prompt] as the on-device model would be given them.
  Map<String, Object?> requestFor({required String system, required String prompt}) {
    final model = settings.model;
    return {
      'model': model,
      'max_tokens': claudeSummaryMaxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      if (settings.effortChosen) 'output_config': {'effort': settings.effort},
      if (claudeFallbackModels.contains(model)) 'fallbacks': 'default',
    };
  }

  /// One generation: [system] and [prompt], answered with the text Claude wrote.
  ClaudeWriting write({required String system, required String prompt}) {
    final key = settings.key;
    if (key == null) return ClaudeWriting(Future<String>.error(const ClaudeError('Add your Anthropic API key in Settings › Claude.')), () {});
    final body = requestFor(system: system, prompt: prompt);
    final call = _api(key).streamWith(body, betas: body.containsKey('fallbacks') ? const [claudeFallbackBeta] : const []);
    return ClaudeWriting(_read(call), call.cancel);
  }

  static Future<String> _read(ClaudeCall call) async {
    final text = StringBuffer();
    String? stop;
    Object? failure;
    await for (final event in call.events.handleError((Object error) => failure ??= error)) {
      final data = _json(event.data);
      switch (event.event) {
        case 'content_block_delta':
          final delta = data['delta'];
          if (delta is Map && delta['type'] == 'text_delta') text.write(delta['text'] as String? ?? '');
        case 'message_delta':
          final delta = data['delta'];
          if (delta is Map && delta['stop_reason'] is String) stop = delta['stop_reason'] as String;
        case 'error':
          final error = data['error'];
          failure ??= ClaudeError(error is Map ? (error['message'] as String? ?? 'Claude stopped with an error.') : 'Claude stopped with an error.', type: error is Map ? error['type'] as String? : null);
      }
    }
    if (failure != null) throw failure!;
    // A decline is checked before the words: what streamed before it is not the answer.
    if (stop == 'refusal') throw const ClaudeError('Claude declined to write this one up.', type: 'refusal');
    if (stop == 'max_tokens') throw const ClaudeError('Claude’s write-up ran out of room and was cut off.');
    final said = text.toString().trim();
    if (said.isEmpty) throw const ClaudeError('Claude answered with nothing.');
    return said;
  }

  static Map<String, Object?> _json(String data) {
    try {
      final parsed = jsonDecode(data);
      return parsed is Map ? parsed.cast<String, Object?>() : const {};
    } catch (_) {
      return const {};
    }
  }
}
