// A fake of dart:io's HttpClient for the AI providers' clients (docs/AI_PROVIDERS.md, "Tests"): every request is
// recorded and answered by the test, its body in the chunks the test cuts it into, so a line, a letter or a tool
// call's arguments can be split across reads as a real network splits them. Nothing reaches the network.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

/// One request as the client made it.
class FakeRequest {
  FakeRequest(this.method, this.url);

  final String method;
  final Uri url;
  final Map<String, String> headers = {};
  final BytesBuilder _body = BytesBuilder();

  String get body => utf8.decode(_body.toBytes());
  Map<String, Object?> get json => jsonDecode(body) as Map<String, Object?>;
}

/// What a request is answered with: a status, and the body in chunks.
class FakeAnswer {
  FakeAnswer(this.status, this.chunks);

  /// An event stream: each piece of [events] a chunk of its own.
  factory FakeAnswer.sse(List<String> chunks) => FakeAnswer(200, chunks);

  factory FakeAnswer.json(int status, Object body) => FakeAnswer(status, [jsonEncode(body)]);

  final int status;
  final List<String> chunks;
}

/// The client: [answer] says what each request gets.
class FakeHttp {
  FakeHttp(this.answer);

  final FutureOr<FakeAnswer> Function(FakeRequest request) answer;
  final List<FakeRequest> requests = [];

  /// A fresh client each time, as the providers ask for one.
  HttpClient call() => _FakeClient(this);
}

class _FakeClient implements HttpClient {
  _FakeClient(this.http);
  final FakeHttp http;

  Future<HttpClientRequest> _open(String method, Uri url) async {
    final request = FakeRequest(method, url);
    http.requests.add(request);
    return _FakeClientRequest(this, request);
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _open('POST', url);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _open('GET', url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  _FakeHeaders(this.into);
  final Map<String, String> into;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) => into[name.toLowerCase()] = '$value';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClientRequest implements HttpClientRequest {
  _FakeClientRequest(this.client, this.request) : headers = _FakeHeaders(request.headers);
  final _FakeClient client;
  final FakeRequest request;

  @override
  final HttpHeaders headers;

  @override
  void add(List<int> data) => request._body.add(data);

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() async {
    final answer = await client.http.answer(request);
    return _FakeResponse(answer.status, Stream<List<int>>.fromIterable([for (final chunk in answer.chunks) utf8.encode(chunk)]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends StreamView<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode, super.stream);

  @override
  final int statusCode;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [text] cut into pieces of [size], as a network might deliver it.
List<String> cutInto(String text, int size) => [for (var i = 0; i < text.length; i += size) text.substring(i, i + size > text.length ? text.length : i + size)];

/// One server-sent event with no name, as OpenAI and Gemini send them.
String sseData(Object json) => 'data: ${json is String ? json : jsonEncode(json)}\n\n';
