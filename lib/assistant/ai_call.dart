/// One request to a cloud model, whichever provider answers it (docs/AI_PROVIDERS.md, "The seam"; Matt, 2026-10-29:
/// "Add support for aster 6 and other Ai models as plugins in addition to claude like openAI google gemini etc"): the
/// stream of its events, the way to stop it, and what went wrong, in words a person reads.
///
/// These were the Claude client's own (lib/claude/messages_api.dart `ClaudeCall`, `ClaudeError`, `ClaudeCancelled`),
/// and are still its, by those names, as type aliases: nothing of Claude's changed but where the classes are written.
/// Every provider's client hands back the same three, so the run (lib/claude/claude_run.dart), the spending meter
/// (lib/claude/claude_spend.dart `meterClaude`) and the meetings' write-ups (lib/ai/summary_claude.dart) read one
/// shape whoever answered.
library;

import 'dart:async';

import 'sse.dart';

export 'sse.dart' show SseEvent;

/// Something a provider answered with instead of a stream, or the network's failure, in words a person reads.
class AiError implements Exception {
  const AiError(this.message, {this.status, this.type});

  final String message;

  /// The HTTP status, or null for no answer at all.
  final int? status;

  /// The provider's error type, in the Messages API's names where the client maps one (`authentication_error`,
  /// `rate_limit_error`, `billing_error`, `overloaded_error`, ...), else the provider's own.
  final String? type;

  /// Whether the key was refused.
  bool get badKey => status == 401 || type == 'authentication_error';

  @override
  String toString() => message;
}

/// A request stopped by [AiCall.cancel].
class AiCancelled implements Exception {
  const AiCancelled();

  @override
  String toString() => 'Stopped.';
}

/// One streamed request: its events, and the way to stop it.
///
/// The events are the Messages API's, whoever answered (docs/AI_PROVIDERS.md, "One shape of event"): `message_start`
/// (the model that answered, and the input's count in `usage`), `content_block_start` / `_delta` / `_stop` for each
/// block of text, thinking or tool call, `message_delta` (the `stop_reason`, and the output's count), `message_stop`,
/// and `error`. A client of another provider translates its own stream into these as it reads it
/// (lib/plugins/openai/chat_api.dart, lib/plugins/gemini/gemini_api.dart). One more is the app's own: `ghost_notice`,
/// whose data is `{"words": "..."}`, something the person should be told once (a model that cannot use tools).
class AiCall {
  AiCall(this.events, this._cancel);

  /// The events in order, ending with the stream or with an error ([AiError], [AiCancelled]).
  final Stream<SseEvent> events;
  final void Function() _cancel;

  void cancel() => _cancel();
}

/// The event a client sends for something to be said once in the chat (see [AiCall]).
const String aiNoticeEvent = 'ghost_notice';
