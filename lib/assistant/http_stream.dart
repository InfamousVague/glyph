/// The network as every provider's client but Claude's uses it (docs/AI_PROVIDERS.md, "The network"): `dart:io`'s
/// [HttpClient], as lib/claude/messages_api.dart's own does, so no provider brings an SDK of its own and a test hands
/// in a fake client for all of them alike. Two calls: [aiPostStream], one request streamed as server-sent events and
/// translated as it reads into the Messages API's events ([AiTranslator]), stoppable at any point; and [aiGetJson], one
/// small read (a provider's models, a key's check).
///
/// The stop is the Claude client's, line for line: the connection closed, and the stream ended with [AiCancelled].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_call.dart';
import 'sse.dart';

/// Turns one provider's stream into the Messages API's events (see [AiCall]), a raw event at a time.
abstract class AiTranslator {
  /// The events [raw] makes, in order: none, one or several.
  Iterable<SseEvent> take(SseEvent raw);

  /// The events the stream's end makes: blocks left open closed, the stop reason and the last count.
  Iterable<SseEvent> end();
}

/// A request a client makes, and how its answer is read.
class AiRequest {
  const AiRequest({required this.url, required this.headers, required this.body, required this.translator});

  final Uri url;
  final Map<String, String> headers;
  final Map<String, Object?> body;

  /// Made for each attempt, fresh.
  final AiTranslator Function() translator;
}

/// Streams [first]. Where it is refused before it streams, [retry] may answer another request (the same without its
/// tools, for a model that has none) with a notice to say before its events, or none; twice at most. Else the refusal
/// is the stream's error, in [errorOf]'s words. [unreachable] is what no answer at all is called.
AiCall aiPostStream({
  required HttpClient Function() client,
  required AiRequest first,
  required AiError Function(int status, String body) errorOf,
  required String unreachable,
  ({AiRequest request, String? notice})? Function(AiError refused)? retry,
}) {
  final http = client();
  HttpClientRequest? sent;
  var cancelled = false;
  late final StreamController<SseEvent> out;
  StreamSubscription<SseEvent>? reading;
  Completer<void>? readingDone;

  Future<void> attempt(AiRequest request, {int tries = 0}) async {
    final made = sent = await http.postUrl(request.url);
    request.headers.forEach(made.headers.set);
    made.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    made.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    made.add(utf8.encode(jsonEncode(request.body)));
    final answer = await made.close();
    if (answer.statusCode != 200) {
      final text = await utf8.decodeStream(answer);
      final refused = errorOf(answer.statusCode, text);
      final next = tries >= 2 || cancelled ? null : retry?.call(refused);
      if (next == null) throw refused;
      final notice = next.notice;
      if (notice != null && !out.isClosed) out.add(SseEvent(aiNoticeEvent, jsonEncode({'words': notice})));
      return attempt(next.request, tries: tries + 1);
    }
    final translator = request.translator();
    final done = readingDone = Completer<void>();
    reading = sseEvents(answer).listen(
      (event) {
        for (final made in translator.take(event)) {
          if (!out.isClosed) out.add(made);
        }
      },
      onError: (Object error) {
        if (!done.isCompleted) done.completeError(error);
      },
      onDone: () {
        if (!cancelled) {
          for (final made in translator.end()) {
            if (!out.isClosed) out.add(made);
          }
        }
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    await done.future;
  }

  Future<void> run() async {
    try {
      await attempt(first);
    } catch (error) {
      if (out.isClosed) {
        // Stopped: the stream has ended already.
      } else if (cancelled) {
        out.addError(const AiCancelled());
      } else if (error is AiError) {
        out.addError(error);
      } else if (error is SocketException || error is HttpException || error is HandshakeException) {
        out.addError(AiError(unreachable));
      } else {
        out.addError(AiError('$error'));
      }
    } finally {
      http.close(force: true);
      if (!out.isClosed) await out.close();
    }
  }

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    reading?.cancel();
    final waiting = readingDone;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
    sent?.abort(const AiCancelled());
    http.close(force: true);
    if (!out.isClosed) {
      out.addError(const AiCancelled());
      out.close();
    }
  }

  out = StreamController<SseEvent>(onListen: run);
  return AiCall(out.stream, cancel);
}

/// One small read: [url] with [headers], answered with its status and body, or [AiError] in [unreachable]'s words
/// (or [slow]'s past fifteen seconds) where there was no answer.
Future<({int status, String body})> aiGetJson({required HttpClient Function() client, required Uri url, required Map<String, String> headers, required String unreachable, required String slow}) async {
  final http = client();
  try {
    final request = await http.getUrl(url).timeout(const Duration(seconds: 15));
    headers.forEach(request.headers.set);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final answer = await request.close().timeout(const Duration(seconds: 15));
    final text = await utf8.decodeStream(answer).timeout(const Duration(seconds: 15));
    return (status: answer.statusCode, body: text);
  } on TimeoutException {
    throw AiError(slow);
  } on AiError {
    rethrow;
  } catch (_) {
    throw AiError(unreachable);
  } finally {
    http.close(force: true);
  }
}

/// A Messages API event, its data made JSON.
SseEvent aiEvent(String name, Map<String, Object?> data) => SseEvent(name, jsonEncode({'type': name, ...data}));

/// Whether a refusal says the model cannot take tools (function calling), in the words providers use: a model
/// without them is asked again without them (docs/AI_PROVIDERS.md, "A model without tools").
bool aiRefusedTools(AiError error) {
  final status = error.status;
  if (status == null || status < 400 || status >= 500 || status == 401 || status == 403 || status == 429) return false;
  final words = error.message.toLowerCase();
  return RegExp(r'\btools?\b|function[ _-]?call|function declaration|tool[ _-]?choice|tool[ _-]?use').hasMatch(words) &&
      RegExp(r'not support|unsupported|does not|doesn.t|not available|not enabled|invalid|unknown|unrecognized|not allowed|not permitted').hasMatch(words);
}
