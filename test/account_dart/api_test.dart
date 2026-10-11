import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/not_yet.dart';

import '../support/fake_service.dart';

/// The app's one way to the service (lib/account/api.dart). The first group is the web's
/// `src/app/core/account/api.test.ts`, case for case; the rest is what this port adds to the module and the web has
/// no test of: the base that must be given and may not be the real service, and the `dart:io` fetcher, tried over a
/// socket on 127.0.0.1 against the service in memory.
class _Other implements Exception, Refusal {
  const _Other(this.status, this.body);
  @override
  final int status;
  @override
  final Object? body;
}

void main() {
  group('a 404 that means "not yet"', () {
    test('is the service’s own "no such route", or a 404 with no service body', () {
      expect(notYet(const ApiError(404, 'no such route', {'error': 'no such route'})), isTrue);
      expect(notYet(const ApiError(404, 'The sync service answered 404.')), isTrue);
      expect(notYet(const ApiError(404, 'The sync service answered 404.', '<html>not found</html>')), isTrue);
    });

    test('is never a 404 in the service’s words, which is an answer, nor any other status', () {
      expect(notYet(const ApiError(404, 'No one has that handle.', {'error': 'No one has that handle.'})), isFalse);
      expect(notYet(const ApiError(404, 'You were not invited.', {'error': 'You were not invited.'})), isFalse);
      expect(notYet(const ApiError(500, 'no such route', {'error': 'no such route'})), isFalse);
      expect(notYet(const ApiError(0, 'The sync service could not be reached.')), isFalse);
      expect(notYet(Exception('not a refusal')), isFalse);
      expect(notYet('404'), isFalse);
    });

    test('reads another error class that carries a status and a body, as the MCP server’s does', () {
      expect(notYet(const _Other(404, {'error': 'no such route'})), isTrue);
      expect(notYet(const _Other(404, {'error': 'No such organization.'})), isFalse);
    });
  });

  group('the base', () {
    Future<FetchResponse> never(FetchRequest request) async => fail('Nothing should have been asked.');

    test('must be given, and a development build refuses the real service outright', () {
      for (final real in ['https://ghostmarkdown.com/api', 'https://GhostMarkdown.com/api/', 'https://www.ghostmarkdown.com/glyph/api', 'https://attack.fm/glyph/api']) {
        expect(() => Api(base: real, fetcher: never), throwsA(isA<AssertionError>()), reason: real);
      }
      expect(Api(base: 'http://127.0.0.1:8787/api/', fetcher: never).base, 'http://127.0.0.1:8787/api');
      expect(isProductionHost('ghostmarkdown.com.evil.test'), isFalse);
      expect(isProductionHost('notghostmarkdown.com'), isFalse);
    });

    test('is refused by the socket fetcher too, for a request made round the Api', () async {
      final fetch = ioFetcher();
      await expectLater(fetch(FetchRequest(method: 'GET', url: Uri.parse('https://ghostmarkdown.com/api/v1/notes'))), throwsA(isA<AssertionError>()));
      // And through an Api the assert is not swallowed into "could not be reached".
      final api = Api(base: 'http://127.0.0.1:1/api', fetcher: (request) => fetch(FetchRequest(method: 'GET', url: Uri.parse('https://attack.fm/glyph/api/v1/notes'))));
      await expectLater(api.call('GET', 'notes'), throwsA(isA<AssertionError>()));
    });
  });

  group('a call', () {
    test('sends the token, JSON or bytes, to /v1 under the base, and reads the answer', () async {
      final seen = <FetchRequest>[];
      final api = Api(
        base: 'http://service.test/api',
        fetcher: (request) async {
          seen.add(request);
          return request.method == 'GET' ? FetchResponse(200) : FetchResponse.json(200, {'rev': 4});
        },
      );
      expect(await api.call('PUT', 'notes/n%201', token: 't1', body: {'blob': 'b', 'base': 0}), {'rev': 4});
      expect(seen.single.url.toString(), 'http://service.test/api/v1/notes/n%201');
      expect(seen.single.headers, {'Authorization': 'Bearer t1', 'Content-Type': 'application/json'});
      expect(seen.single.text, '{"blob":"b","base":0}');
      expect(seen.single.bearer, 't1');
      expect(seen.single.timeout, const Duration(seconds: 30));
      await api.call('PUT', 'recordings/r-1?base=0', bytes: Uint8List.fromList([1, 2, 3]), timeout: const Duration(minutes: 5));
      expect(seen.last.headers, {'Content-Type': 'application/octet-stream'});
      expect(seen.last.body, [1, 2, 3]);
      expect(seen.last.url.queryParameters, {'base': '0'});
      expect(seen.last.timeout, const Duration(minutes: 5));
      // An empty answer is null, and an object asked for as a map is an empty one.
      expect(await api.call('GET', 'notes'), isNull);
      expect(await api.callMap('GET', 'notes'), isEmpty);
      expect(seen.last.headers, isEmpty);
      expect(seen.last.body, isNull);
    });

    test('throws a refusal in the service’s words with its body, and words of its own where the service gave none', () async {
      FetchResponse answer = FetchResponse.json(409, {'error': 'That handle is taken.', 'rev': 3});
      final api = Api(base: 'http://service.test/api', fetcher: (request) async => answer);
      await expectLater(
        api.call('POST', 'signup'),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 409).having((e) => e.message, 'message', 'That handle is taken.').having((e) => e.body, 'body', {'error': 'That handle is taken.', 'rev': 3})),
      );
      answer = FetchResponse(404);
      await expectLater(api.call('GET', 'orgs'), throwsA(isA<ApiError>().having((e) => e.message, 'message', 'The sync service answered 404.').having((e) => e.body, 'body', isNull).having(notYet, 'not yet', isTrue)));
      // A proxy's page is no service body: still a refusal, and still "not yet".
      answer = FetchResponse(404, bytes: Uint8List.fromList('<html>not found</html>'.codeUnits));
      await expectLater(api.callBytes('GET', 'recordings/r-1'), throwsA(isA<ApiError>().having((e) => e.status, 'status', 404).having(notYet, 'not yet', isTrue)));
      answer = FetchResponse(200, bytes: Uint8List.fromList('<html>hello</html>'.codeUnits));
      await expectLater(api.call('GET', 'notes'), throwsA(isA<ApiError>().having((e) => e.status, 'status', 200)));
    });

    test('is no answer at all, status 0, when the fetch fails or takes too long', () async {
      final down = Api(base: 'http://service.test/api', fetcher: (request) async => throw const SocketException('Failed to fetch'));
      await expectLater(down.call('GET', 'notes'), throwsA(isA<ApiError>().having((e) => e.status, 'status', 0).having((e) => e.message, 'message', 'The sync service could not be reached.')));
      final slow = Api(base: 'http://service.test/api', fetcher: (request) => Future.delayed(const Duration(seconds: 5), () => FetchResponse(200)));
      await expectLater(
        slow.call('GET', 'notes', timeout: const Duration(milliseconds: 20)),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 0).having((e) => e.message, 'message', 'The sync service took too long to answer.')),
      );
    });
  });

  group('over a socket, on 127.0.0.1', () {
    late FakeService service;
    late FakeServer server;
    late Api api;

    setUp(() async {
      // `flutter test` may hand out an HttpClient that answers 400 to everything; this group wants the real one.
      HttpOverrides.global = null;
      service = await FakeService.start(seed: (handle: 'matt', password: 'correct horse'));
      server = await service.listen(handle: (request) async {
        if (request.url.path.endsWith('/v1/slow')) return Future.delayed(const Duration(seconds: 3), () => FetchResponse(200));
        return null;
      });
      api = Api(base: server.base, fetcher: ioFetcher());
    });
    tearDown(() => server.close());

    test('asks the service, with the token and the body as the page sends them', () async {
      final token = service.signedIn();
      expect(await api.call('GET', 'keys', token: token), {'wrapped': isA<String>()});
      expect(await api.call('PUT', 'notes/n1', token: token, body: {'blob': 'sealed', 'base': 0}), {'rev': 1});
      expect(service.notes['n1']?.blob, 'sealed');
      expect(await api.callMap('GET', 'notes?since=0', token: token), containsPair('rev', 1));
      expect(service.calls, ['GET keys', 'PUT notes/n1', 'GET notes']);
    });

    test('reads a refusal’s `{error}`, and a file’s bytes with its revision from x-glyph-rev', () async {
      await expectLater(api.call('GET', 'keys'), throwsA(isA<ApiError>().having((e) => e.status, 'status', 401).having((e) => e.message, 'message', 'Sign in first.')));
      final token = service.signedIn();
      final sent = Uint8List.fromList(List.generate(70000, (i) => i % 251));
      expect(await api.call('PUT', 'recordings/r-1?base=0', token: token, bytes: sent), {'rev': 1});
      final got = await api.callBytes('GET', 'recordings/r-1', token: token);
      expect(got.rev, 1);
      expect(got.bytes, sent);
      expect((await api.callBytes('HEAD', 'recordings/r-1', token: token)).rev, 1);
      await expectLater(api.callBytes('HEAD', 'recordings/r-2', token: token), throwsA(isA<ApiError>().having((e) => e.status, 'status', 404)));
      await expectLater(
        api.call('PUT', 'recordings/r-1?base=9', token: token, bytes: sent),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 409).having((e) => e.body, 'body', {'rev': 1})),
      );
    });

    test('gives up on a request that takes too long, and says so when nothing is listening', () async {
      final token = service.signedIn();
      await expectLater(
        api.call('GET', 'slow', token: token, timeout: const Duration(milliseconds: 150)),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 0).having((e) => e.message, 'message', 'The sync service took too long to answer.')),
      );
      final closed = await service.listen();
      final nowhere = Api(base: closed.base, fetcher: ioFetcher());
      await closed.close();
      await expectLater(nowhere.call('GET', 'keys', token: token), throwsA(isA<ApiError>().having((e) => e.status, 'status', 0).having((e) => e.message, 'message', 'The sync service could not be reached.')));
    });
  });
}
