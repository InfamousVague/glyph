/// The Messages API, asked from the app with the person's own key (docs/CLAUDE_APP.md, "The stream"). One request
/// streamed as server-sent events ([ClaudeApi.stream]) and one small read that says whether a key works
/// ([ClaudeApi.check]). Nothing else leaves the app: no Ghost.md server stands between, and the key goes only to
/// `api.anthropic.com`, in its `x-api-key` header.
///
/// A request can be stopped ([ClaudeCall.cancel]): the connection is closed, and the stream ends with
/// [ClaudeCancelled].
///
/// **One provider of several** (docs/AI_PROVIDERS.md; Matt, 2026-10-29: "Add support for aster 6 and other Ai models
/// as plugins in addition to claude like openAI google gemini etc"): [ClaudeApi] is the seam's [AiProvider], the one
/// whose shape the others translate into, so it streams, checks and lists exactly as it did. [ClaudeApi.models] is
/// the one thing added: the models the key may ask, read for the seam, which Claude's own page does not use (it
/// offers its three, lib/claude/claude_settings.dart `claudeModels`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../assistant/provider.dart';
import 'sse.dart';

export '../assistant/ai_call.dart' show AiCall, AiCancelled, AiError;

/// Where the API is.
const String claudeApiBase = 'https://api.anthropic.com/v1';

/// The API's version header.
const String claudeApiVersion = '2023-06-01';

/// Something the API answered with instead of a stream, or the network's failure, in words a person reads: the
/// seam's own error (lib/assistant/ai_call.dart [AiError]), by the name Claude's code has always used.
typedef ClaudeError = AiError;

/// A request stopped by [ClaudeCall.cancel] ([AiCancelled]).
typedef ClaudeCancelled = AiCancelled;

/// One streamed request: its events, and the way to stop it ([AiCall]).
typedef ClaudeCall = AiCall;

/// The words of a failed answer: the API's own `error.message` where its body has one.
ClaudeError errorOf(int status, String body) {
  String? message, type;
  try {
    final json = jsonDecode(body);
    if (json is Map && json['error'] is Map) {
      message = (json['error'] as Map)['message'] as String?;
      type = (json['error'] as Map)['type'] as String?;
    }
  } catch (_) {
    // Not JSON: the status says it.
  }
  final said = switch (status) {
    401 => 'The API key was refused. Check it in Settings › Claude.',
    403 => 'This key may not use that. ${message ?? ''}'.trim(),
    429 => 'Too many requests for this key just now. Try again in a moment.',
    529 => 'Claude is overloaded just now. Try again in a moment.',
    _ => message ?? 'Claude answered $status.',
  };
  return ClaudeError(said, status: status, type: type);
}

/// The API, with one key.
class ClaudeApi implements AiProvider {
  ClaudeApi({required this.key, HttpClient Function()? client}) : _client = client ?? HttpClient.new;

  final String key;
  final HttpClient Function() _client;

  void _headers(HttpClientRequest request, [List<String> betas = const []]) {
    request.headers.set('x-api-key', key);
    if (betas.isNotEmpty) request.headers.set('anthropic-beta', betas.join(','));
    request.headers.set('anthropic-version', claudeApiVersion);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
  }

  /// Streams one Messages request ([body] is the request as the API takes it; `stream` is set here).
  @override
  ClaudeCall stream(Map<String, Object?> body) => streamWith(body);

  /// [stream], with the betas the request opts into in its `anthropic-beta` header (a meeting's write-up asks for
  /// the server-side fallback, lib/ai/summary_claude.dart).
  ClaudeCall streamWith(Map<String, Object?> body, {List<String> betas = const []}) {
    final client = _client();
    HttpClientRequest? sent;
    var cancelled = false;
    late final StreamController<SseEvent> out;
    StreamSubscription<SseEvent>? reading;
    Completer<void>? readingDone;

    Future<void> run() async {
      try {
        final request = sent = await client.postUrl(Uri.parse('$claudeApiBase/messages'));
        _headers(request, betas);
        request.add(utf8.encode(jsonEncode({...body, 'stream': true})));
        final answer = await request.close();
        if (answer.statusCode != 200) {
          final text = await utf8.decodeStream(answer);
          throw errorOf(answer.statusCode, text);
        }
        final done = readingDone = Completer<void>();
        reading = sseEvents(answer).listen(
          (event) {
            if (!out.isClosed) out.add(event);
          },
          onError: (Object error) {
            if (!done.isCompleted) done.completeError(error);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
        await done.future;
      } catch (error) {
        if (out.isClosed) {
          // Stopped: the stream has ended already.
        } else if (cancelled) {
          out.addError(const ClaudeCancelled());
        } else if (error is ClaudeError) {
          out.addError(error);
        } else if (error is SocketException || error is HttpException || error is HandshakeException) {
          out.addError(const ClaudeError('Claude could not be reached. Check the connection.'));
        } else {
          out.addError(ClaudeError('$error'));
        }
      } finally {
        client.close(force: true);
        if (!out.isClosed) await out.close();
      }
    }

    void cancel() {
      if (cancelled) return;
      cancelled = true;
      reading?.cancel();
      final waiting = readingDone;
      if (waiting != null && !waiting.isCompleted) waiting.complete();
      sent?.abort(const ClaudeCancelled());
      client.close(force: true);
      if (!out.isClosed) {
        out.addError(const ClaudeCancelled());
        out.close();
      }
    }

    out = StreamController<SseEvent>(onListen: run);
    return ClaudeCall(out.stream, cancel);
  }

  /// Whether the key works: null when it does, else what is wrong. One small read of the models the key may use.
  @override
  Future<ClaudeError?> check() async {
    final client = _client();
    try {
      final request = await client.getUrl(Uri.parse('$claudeApiBase/models?limit=1')).timeout(const Duration(seconds: 15));
      _headers(request);
      final answer = await request.close().timeout(const Duration(seconds: 15));
      final text = await utf8.decodeStream(answer);
      return answer.statusCode == 200 ? null : errorOf(answer.statusCode, text);
    } on TimeoutException {
      return const ClaudeError('Claude took too long to answer.');
    } catch (_) {
      return const ClaudeError('Claude could not be reached. Check the connection.');
    } finally {
      client.close(force: true);
    }
  }

  /// The models the key may ask (`GET /v1/models`), newest first as the API lists them, by their display names.
  @override
  Future<List<AiModelInfo>> models() async {
    final client = _client();
    try {
      final request = await client.getUrl(Uri.parse('$claudeApiBase/models?limit=100')).timeout(const Duration(seconds: 15));
      _headers(request);
      final answer = await request.close().timeout(const Duration(seconds: 15));
      final text = await utf8.decodeStream(answer);
      if (answer.statusCode != 200) throw errorOf(answer.statusCode, text);
      final json = jsonDecode(text);
      final data = json is Map ? json['data'] : null;
      return [
        if (data is List)
          for (final model in data)
            if (model is Map && model['id'] is String) AiModelInfo(model['id'] as String, name: model['display_name'] as String?),
      ];
    } on TimeoutException {
      throw const ClaudeError('Claude took too long to answer.');
    } on ClaudeError {
      rethrow;
    } catch (_) {
      throw const ClaudeError('Claude could not be reached. Check the connection.');
    } finally {
      client.close(force: true);
    }
  }
}
