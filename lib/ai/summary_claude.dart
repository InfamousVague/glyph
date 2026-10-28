/// A meeting's write-up through the app's own Claude (docs/CLAUDE_APP.md, "Meetings"). Matt, 2026-10-19: "when
/// claude is enabled the meeting summary should go through claude instead of gemma".
///
/// Claude is **chosen** for meetings when the Claude plugin's switch is on, an API key is kept on this device (typed
/// here, or sealed from another of the account's devices, lib/sync/sealed_keys.dart), and Write meeting summaries with
/// Claude is on (Settings › Plugins › Claude, [ClaudeSettings.meetings], on unless turned off; Matt, 2026-10-28: "We
/// should be using Claude to generate the meeting summaries not the local processor on the Mac when the anthropic API
/// key is set"). It
/// is **enabled** (asked now) when, besides, Local only is off, since Local only holds the plugin off with every
/// plugin that reaches the internet. Chosen but held by Local only, a meeting's write-up waits for Claude rather than
/// going to the phone's own model: summaries are never remade on their own, so a local write-up made in the meantime
/// would stand for good where the person had chosen Claude's, and Local only is the switch a person turns on for a
/// while. Not chosen (the plugin off, or no key), meetings are the on-device model's as they always were.
///
/// What goes to Anthropic, with the person's own key and nowhere else (no Ghost.md server between): the meeting's
/// transcript as the summary queue reads it, in the same pieces and with the same prompts as the on-device model is
/// given (format/prompt.dart), so the answer is placed and shaped by the same rules. Only meetings: a long voice
/// note's summary stays on the phone.
///
/// **One pass where it fits** (2026-10-28). The on-device model reads twenty thousand characters at a time, so a long
/// meeting goes to it in pieces, each boiled down to notes and the notes summarized. Claude's models read a million
/// tokens, so a meeting goes to Claude whole up to [claudeOnePassChars] (about 200,000 tokens at four characters a
/// token: the 69-minute standup of that morning was 362,000 characters, some 90,000 tokens, and goes in one request),
/// and only past that in pieces of [claudePieceChars], the same notes-then-summary map and reduce with the same
/// prompts (ai/summary_text.dart `transcriptPieces`). [onePassChars] and [pieceChars] are those two unless a test
/// says.
///
/// **Falling back** (2026-10-28). A request Claude did not answer (no connection, the key refused, too many requests,
/// Anthropic out of credit, overloaded, declined, cut off) is not the end of the summary: where the device has a
/// summary model, the job is written by it instead, at once, and the strip says why ("Claude couldn't write it: … It
/// is being written on this device."; ai/summaries.dart `fellBack`). Only where there is no model does the job count
/// a try, or fail in Claude's words, as before. Local only and the spending limit are choices, not failures: they
/// hold the job for Claude as they did.
///
/// One request a generation, streamed (lib/claude/messages_api.dart [ClaudeApi.streamWith]) and read whole: the text
/// of every text block joined, thinking left alone (the models run adaptive thinking when none is asked for), the
/// effort the person chose sent where one was chosen. `max_tokens` is room for the thinking as well as the words, not
/// the on-device model's budget: the prompt says how long the summary is. Opus 5.5 and Sonnet 5.5 are asked with the
/// server-side fallback (`fallbacks: "default"`), so a request a safety classifier declines is answered by the
/// model Anthropic routes it to rather than refused; what still ends `refusal`, `max_tokens` or with no words is a
/// [ClaudeError] in the queue's words.
///
/// **The spending limit** (lib/claude/claude_spend.dart): each request is counted as it ends. Once the month's limit
/// is reached a write-up is [limited]: the queue holds its job, saying [limitMessage], and asks again next month or
/// once the limit is raised or the count reset; it is never failed for it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../claude/claude_settings.dart' show ClaudeSettings;
import '../core/background_jobs.dart';
import '../claude/claude_spend.dart' show claudeLimitError, claudeLimitType, meterClaude;
import '../claude/messages_api.dart';

/// The device's name for a write-up being asked of Claude (lib/core/background_jobs.dart).
const String claudeWriteUpJobId = 'claude-write-up';

/// The room a write-up's request is given: its thinking and its words.
const int claudeSummaryMaxTokens = 16000;

/// The most of a meeting's words sent to Claude in one request (see the header): about 200,000 tokens.
const int claudeOnePassChars = 800000;

/// About how many characters a piece of a meeting longer than [claudeOnePassChars] holds.
const int claudePieceChars = 400000;

/// The beta the server-side fallback is asked for under (`fallbacks: "default"`).
const String claudeFallbackBeta = 'server-side-fallback-2026-07-01';

/// The models the server-side fallback is asked for (Haiku 5.5 has none).
const Set<String> claudeFallbackModels = {'claude-opus-5-5', 'claude-sonnet-5-5'};

/// Whether [error] is one asking again will not mend: the key refused, the request refused, or Claude declining it.
/// The queue fails such a job at once, for Try again once the person has put it right, rather than three times.
bool claudeLasting(Object error) {
  if (error is! ClaudeError) return false;
  // The limit is waited out, never failed for.
  if (error.type == claudeLimitType) return false;
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
  MeetingClaude({required this.settings, required this.switchedOn, required this.localOnly, ClaudeApi Function(String key)? api, this.changes, BackgroundJobs? background, this.onePassChars = claudeOnePassChars, this.pieceChars = claudePieceChars})
      : _api = api ?? ((key) => ClaudeApi(key: key)),
        background = background ?? const NoBackgroundJobs();

  /// The device, told while a write-up is being asked of Claude, so it goes on with the app behind another (Matt,
  /// 2026-10-27: "Claude times out when the app loses focus please background the activity"): Android's foreground
  /// service and the Mac out of App Nap, as Lovart's pictures are held (lib/core/background_jobs.dart). The phone's
  /// own model writes up natively, held by its own work; Claude's answer is read here, in the app, which a phone
  /// freezes behind another app within seconds.
  final BackgroundJobs background;
  int _asking = 0;

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

  /// The most of a meeting sent in one request, and the size of a piece past it (see the header).
  final int onePassChars;
  final int pieceChars;

  /// Reads the settings, once.
  Future<void> load() => settings.load();

  /// Meetings are Claude's: the plugin switched on, a key kept, and Write meeting summaries with Claude on (see the
  /// header).
  bool get chosen => switchedOn() && settings.hasKey && settings.meetings;

  /// Chosen, and held off by Local only: the write-up waits.
  bool get held => chosen && localOnly();

  /// Claude may be asked now.
  bool get enabled => chosen && !localOnly();

  /// Chosen, and this month's spending limit reached: the write-up waits, as it does for Local only.
  bool get limited => chosen && settings.spend.reached;

  /// What a write-up held by the limit says.
  String get limitMessage => settings.spend.limitMessage;

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
    if (settings.spend.reached) return ClaudeWriting(Future<String>.error(claudeLimitError(settings.spend)), () {});
    final body = requestFor(system: system, prompt: prompt);
    final asked = _api(key).streamWith(body, betas: body.containsKey('fallbacks') ? const [claudeFallbackBeta] : const []);
    final call = meterClaude(asked, model: body['model']! as String, spend: settings.spend);
    _asking += 1;
    if (_asking == 1) unawaited(background.running(claudeWriteUpJobId, title: 'Writing up with Claude', text: 'A meeting’s summary'));
    final read = _read(call).whenComplete(() {
      _asking -= 1;
      if (_asking == 0) unawaited(background.ended(claudeWriteUpJobId, title: 'Written up', quiet: true));
    });
    return ClaudeWriting(read, call.cancel);
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
