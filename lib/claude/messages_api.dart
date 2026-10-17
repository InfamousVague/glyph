/// The Messages API, asked from the app with the person's own key (docs/CLAUDE_APP.md, "The stream"). One request
/// streamed as server-sent events ([ClaudeApi.stream]) and one small read that says whether a key works
/// ([ClaudeApi.check]). Nothing else leaves the app: no Ghost.md server stands between, and the key goes only to
/// `api.anthropic.com`, in its `x-api-key` header.
///
/// A request can be stopped ([ClaudeCall.cancel]): the connection is closed, and the stream ends with
/// [ClaudeCancelled].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sse.dart';

/// Where the API is.
const String claudeApiBase = 'https://api.anthropic.com/v1';

/// The API's version header.
const String claudeApiVersion = '2023-06-01';

/// Something the API answered with instead of a stream, or the network's failure, in words a person reads.
class ClaudeError implements Exception {
  const ClaudeError(this.message, {this.status, this.type});

  final String message;

  /// The HTTP status, or null for no answer at all.
  final int? status;

  /// The API's error type (`authentication_error`, `overloaded_error`, ...), when it said one.
  final String? type;

  /// Whether the key was refused.
  bool get badKey => status == 401 || type == 'authentication_error';

  @override
  String toString() => message;
}

/// A request stopped by [ClaudeCall.cancel].
class ClaudeCancelled implements Exception {
  const ClaudeCancelled();

  @override
  String toString() => 'Stopped.';
}

/// One streamed request: its events, and the way to stop it.
class ClaudeCall {
  ClaudeCall(this.events, this._cancel);

  /// The server's events in order, ending with the stream or with an error ([ClaudeError], [ClaudeCancelled]).
  final Stream<SseEvent> events;
  final void Function() _cancel;

  void cancel() => _cancel();
}

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
    401 => 'The API key was refused. Check it in Settings › Ask Claude.',
    403 => 'This key may not use that. ${message ?? ''}'.trim(),
    429 => 'Too many requests for this key just now. Try again in a moment.',
    529 => 'Claude is overloaded just now. Try again in a moment.',
    _ => message ?? 'Claude answered $status.',
  };
  return ClaudeError(said, status: status, type: type);
}

/// The API, with one key.
class ClaudeApi {
  ClaudeApi({required this.key, HttpClient Function()? client}) : _client = client ?? HttpClient.new;

  final String key;
  final HttpClient Function() _client;

  void _headers(HttpClientRequest request) {
    request.headers.set('x-api-key', key);
    request.headers.set('anthropic-version', claudeApiVersion);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
  }

  /// Streams one Messages request ([body] is the request as the API takes it; `stream` is set here).
  ClaudeCall stream(Map<String, Object?> body) {
    final client = _client();
    HttpClientRequest? sent;
    var cancelled = false;
    late final StreamController<SseEvent> out;
    StreamSubscription<SseEvent>? reading;
    Completer<void>? readingDone;

    Future<void> run() async {
      try {
        final request = sent = await client.postUrl(Uri.parse('$claudeApiBase/messages'));
        _headers(request);
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
}
