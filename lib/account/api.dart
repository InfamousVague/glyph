/// The one way the app talks to the account and sync service (server/src/accounts.rs, server/src/sync.rs). A port of
/// `src/app/core/account/api.ts`.
///
/// Errors come back as the service words them, `{ error }`, so what the person reads is what the service meant.
///
/// What differs:
/// - **There is no default base.** The page falls back to `https://ghostmarkdown.com/api`; an [Api] must be GIVEN
///   its base, and a debug build refuses the real service's hosts outright ([isProductionHost]; docs/STAGE7.md,
///   "A development build never talks to ghostmarkdown.com"). [ioFetcher] refuses them a second time, under the
///   same assert, so a request made round the [Api] is stopped too.
/// - `fetch` is [Fetcher], the one typed function every client takes: a [FetchRequest] in, a [FetchResponse] out.
///   The service in memory (test/support/fake_service.dart) is one; [ioFetcher] is the one over `dart:io`.
/// - The page gives up a request with an `AbortController`; here the wait is [FetchRequest.timeout], which
///   [ioFetcher] keeps by aborting, and [Api] keeps again for a fetcher that does not.
/// - A refusal whose body is not JSON (a proxy's HTML 404) is an [ApiError] with that text as its body, where the
///   page's `JSON.parse` throws a `SyntaxError` of its own; an answer that should be JSON and is not is an
///   [ApiError] too, with the status it came with.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'not_yet.dart';

export 'not_yet.dart' show noSuchRoute, notYet;

/// A request as a [Fetcher] is handed it.
class FetchRequest {
  const FetchRequest({required this.method, required this.url, this.headers = const {}, this.body, this.timeout = Api.timeout});

  final String method;
  final Uri url;

  /// By the names the page sends: `Authorization`, `Content-Type`.
  final Map<String, String> headers;

  /// The body as it goes: JSON as UTF-8, or a recording's bytes; null for none.
  final Uint8List? body;

  /// How long the request may take before it is given up on.
  final Duration timeout;

  /// The body as text: what a JSON call sent. Empty for none.
  String get text => body == null ? '' : utf8.decode(body!);

  /// The bearer token, or null for a request with none.
  String? get bearer {
    for (final MapEntry(:key, :value) in headers.entries) {
      if (key.toLowerCase() == 'authorization') return value.replaceFirst(RegExp('^Bearer '), '');
    }
    return null;
  }
}

/// What a [Fetcher] answers.
class FetchResponse {
  FetchResponse(this.status, {Map<String, String> headers = const {}, Uint8List? bytes})
      : headers = {for (final MapEntry(:key, :value) in headers.entries) key.toLowerCase(): value},
        bytes = bytes ?? Uint8List(0);

  /// A JSON answer, as the service writes one.
  factory FetchResponse.json(int status, Object? body) => FetchResponse(status, headers: const {'content-type': 'application/json'}, bytes: utf8.encode(jsonEncode(body)));

  final int status;

  /// By lower-cased name.
  final Map<String, String> headers;
  final Uint8List bytes;

  /// `Response.ok`.
  bool get ok => status >= 200 && status < 300;

  /// The body as text; malformed UTF-8 reads as replacement characters, as `Response.text()` reads it.
  String get text => utf8.decode(bytes, allowMalformed: true);
}

/// The one typed HTTP function every client takes (`typeof fetch`). It answers whatever status the service did, and
/// throws only when there was no answer at all.
typedef Fetcher = Future<FetchResponse> Function(FetchRequest request);

/// The hosts of the real service: ghostmarkdown.com, and attack.fm, kept as a working alias of it.
const List<String> productionHosts = ['ghostmarkdown.com', 'attack.fm'];

/// Whether [host] is the real service, or a name under it.
bool isProductionHost(String host) {
  final name = host.toLowerCase();
  return productionHosts.any((real) => name == real || name.endsWith('.$real'));
}

const String _refused = 'A development build never talks to ghostmarkdown.com (docs/STAGE7.md): work against the fake service or a local server.';

/// A [Fetcher] over `dart:io`'s [HttpClient]. [client] is the one to use, or one made here and kept.
Fetcher ioFetcher({HttpClient? client}) {
  final http = client ?? HttpClient();
  return (request) async {
    assert(!isProductionHost(request.url.host), _refused);
    HttpClientRequest? sent;
    Future<FetchResponse> ask() async {
      final asked = sent = await http.openUrl(request.method, request.url);
      request.headers.forEach(asked.headers.set);
      final body = request.body;
      if (body != null) {
        asked.contentLength = body.length;
        asked.add(body);
      }
      final answer = await asked.close();
      final bytes = BytesBuilder(copy: false);
      await answer.forEach(bytes.add);
      final headers = <String, String>{};
      answer.headers.forEach((name, values) => headers[name] = values.join(', '));
      return FetchResponse(answer.statusCode, headers: headers, bytes: bytes.takeBytes());
    }

    return ask().timeout(request.timeout, onTimeout: () {
      sent?.abort();
      throw TimeoutException('The request took too long.', request.timeout);
    });
  };
}

/// A request the service refused, with its status and its own words (`ApiError`). A status of 0 is no answer at
/// all: unreachable, or too slow.
class ApiError implements Exception, Refusal {
  const ApiError(this.status, this.message, [this.body]);

  @override
  final int status;
  final String message;

  /// The body a refusal carried, for the ones that are data rather than words (a 409 says what won).
  @override
  final Object? body;

  @override
  String toString() => message;
}

ApiError _refusal(int status, Object? body) => ApiError(status, wordsOf(body) ?? 'The sync service answered $status.', body);

/// A refusal's body: JSON where it is JSON, its text where it is not, null where there is none.
Object? _refusalBody(String text) {
  if (text.isEmpty) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}

/// The service at one base, asked through one [Fetcher] (`call`, `callBytes`).
class Api {
  /// [base] is where the service is, up to and not including `/v1`: `http://127.0.0.1:8787/api`. There is no
  /// default, and in a debug build the real service's hosts are refused.
  Api({required String base, required this.fetcher})
      : assert(!isProductionHost(Uri.parse(base).host), _refused),
        base = base.replaceFirst(RegExp(r'/+$'), '');

  /// How long a request may take before it is given up on (`TIMEOUT_MS`). A recording is allowed a good deal
  /// longer, by its caller.
  static const Duration timeout = Duration(seconds: 30);

  final String base;
  final Fetcher fetcher;

  /// A JSON call to `/v1/<path>` (`call`): the decoded answer, null for an empty one. [body] is sent as JSON when it
  /// is not null; [bytes] instead, raw, for a recording. Throws [ApiError] for a refusal, or for no answer.
  Future<Object?> call(String method, String path, {String? token, Object? body, Uint8List? bytes, Duration? timeout}) async {
    final response = await _send(method, path, token: token, body: body, bytes: bytes, timeout: timeout);
    final text = response.text;
    if (!response.ok) throw _refusal(response.status, _refusalBody(text));
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      throw ApiError(response.status, 'The sync service answered something that could not be read.', text);
    }
  }

  /// [call], for the routes that answer an object: the answer as a map, empty for anything else.
  Future<Map<String, Object?>> callMap(String method, String path, {String? token, Object? body, Uint8List? bytes, Duration? timeout}) async {
    final answer = await call(method, path, token: token, body: body, bytes: bytes, timeout: timeout);
    return answer is Map ? answer.cast<String, Object?>() : <String, Object?>{};
  }

  /// A call that answers bytes (`callBytes`): a recording, with its revision from `x-glyph-rev`, 0 where the header
  /// is not there.
  Future<({Uint8List bytes, int rev})> callBytes(String method, String path, {String? token, Object? body, Uint8List? bytes, Duration? timeout}) async {
    final response = await _send(method, path, token: token, body: body, bytes: bytes, timeout: timeout);
    if (!response.ok) throw _refusal(response.status, _refusalBody(response.text));
    return (bytes: response.bytes, rev: int.tryParse(response.headers['x-glyph-rev'] ?? '') ?? 0);
  }

  Future<FetchResponse> _send(String method, String path, {String? token, Object? body, Uint8List? bytes, Duration? timeout}) async {
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    Uint8List? sent;
    if (bytes != null) {
      headers['Content-Type'] = 'application/octet-stream';
      sent = bytes;
    } else if (body != null) {
      headers['Content-Type'] = 'application/json';
      sent = utf8.encode(jsonEncode(body));
    }
    final wait = timeout ?? Api.timeout;
    final request = FetchRequest(method: method, url: Uri.parse('$base/v1/$path'), headers: headers, body: sent, timeout: wait);
    try {
      return await fetcher(request).timeout(wait);
    } on TimeoutException {
      throw const ApiError(0, 'The sync service took too long to answer.');
    } on Exception {
      // No answer at all. An Error (the assert above, a test's own complaint) is a mistake, and is left to be seen.
      throw const ApiError(0, 'The sync service could not be reached.');
    }
  }
}
