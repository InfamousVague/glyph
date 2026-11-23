import 'dart:convert';
import 'dart:io';

import 'package:ghost_relay/feedback.dart';
import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/market.dart';
import 'package:ghost_relay/relay.dart';
import 'package:test/test.dart';

/// The app in a browser at an address of its own (app.gogho.st; `GHOST_APP_ORIGIN`): its page sends a report to the
/// Marketplace's review and feedback to the relay at another address (gogho.st), and a browser lets the page read
/// those answers only where they say so (CORS). Only those two say so, and only to that address (second review of the
/// web client: "Report and feedback don't work in a browser").
void main() {
  const app = 'https://app.example';
  late Directory dir;
  late Relay relay;
  late int port;
  late HttpClient http;

  Future<void> boot({String? appOrigin = app}) async {
    final market = Market(
      dir: Directory('${dir.path}/market'),
      config: const MarketConfig(),
      ownsName: (_, _) => false,
      whoOf: (_) => null,
      adminSignedIn: (_, {Duration within = const Duration(hours: 8)}) => false,
      claimedOn: (_) => null,
    );
    // Feedback with no board to file in: it says so, which is answer enough here.
    final feedback = Feedback(config: const FeedbackConfig(), ownsName: (_, _) => false);
    relay = Relay(hub: Hub(), market: market, feedback: feedback, appOrigin: appOrigin);
    port = await relay.start(port: 0);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ghost-app-origin-test');
    http = HttpClient();
  });
  tearDown(() async {
    http.close(force: true);
    await relay.stop();
    await dir.delete(recursive: true);
  });

  Future<HttpClientResponse> ask(String method, String path, {String? origin, Map<String, String> headers = const {}, List<int>? body}) async {
    final req = await http.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    if (origin != null) req.headers.set('origin', origin);
    headers.forEach(req.headers.set);
    if (body != null) {
      req.contentLength = body.length;
      req.add(body);
    }
    final res = await req.close();
    await res.drain<void>();
    return res;
  }

  // What a browser asks before a POST carrying the app's signature headers.
  Future<HttpClientResponse> preflight(String path, {String origin = app}) =>
      ask('OPTIONS', path, origin: origin, headers: {'access-control-request-method': 'POST', 'access-control-request-headers': 'content-type,x-ghost-key,x-ghost-sig,x-ghost-time,x-ghost-body-sha256,x-ghost-body-length'});

  test('the app\'s page may send a report and feedback, and read the answers', () async {
    await boot();
    for (final path in ['/market/abuse', '/feedback']) {
      final first = await preflight(path);
      expect(first.statusCode, HttpStatus.noContent, reason: path);
      expect(first.headers.value('access-control-allow-origin'), app, reason: path);
      expect(first.headers.value('access-control-allow-methods'), 'POST', reason: path);
      final allowed = first.headers.value('access-control-allow-headers')!.split(',').map((h) => h.trim()).toSet();
      expect(allowed, containsAll(['content-type', 'x-ghost-key', 'x-ghost-time', 'x-ghost-sig', 'x-ghost-body-sha256', 'x-ghost-body-length']), reason: path);
      expect(first.headers['vary']?.join(','), contains('Origin'), reason: path);
    }
    // The POST itself: the relay's own answer (here, that the board isn't set up, and that it isn't signed), readable.
    final feedback = await ask('POST', '/feedback', origin: app, headers: {'content-type': 'application/json'}, body: utf8.encode('{}'));
    expect(feedback.statusCode, HttpStatus.serviceUnavailable);
    expect(feedback.headers.value('access-control-allow-origin'), app);
    final report = await ask('POST', '/market/abuse', origin: app, headers: {'content-type': 'application/json'}, body: utf8.encode('{"sealed":"x"}'));
    expect(report.statusCode, isNot(HttpStatus.notFound));
    expect(report.headers.value('access-control-allow-origin'), app);
  });

  test('another address is told nothing, and the relay\'s other answers say nothing to anyone', () async {
    await boot();
    for (final path in ['/market/abuse', '/feedback']) {
      final other = await preflight(path, origin: 'https://evil.example');
      expect(other.headers.value('access-control-allow-origin'), isNull, reason: path);
      expect(other.statusCode, isNot(HttpStatus.noContent), reason: path);
      // gogho.st's own pages, and the app's address with something after it, are other addresses too.
      for (final near in ['https://example', 'https://app.example.evil', 'http://app.example', 'https://app.example:444']) {
        expect((await preflight(path, origin: near)).headers.value('access-control-allow-origin'), isNull, reason: '$path from $near');
      }
    }
    for (final path in ['/market', '/market/catalog', '/market/abuse/0123456789abcdef', '/files/x', '/feedback/x', '/']) {
      final res = await ask('GET', path, origin: app);
      expect(res.headers.value('access-control-allow-origin'), isNull, reason: path);
      final first = await preflight(path);
      expect(first.headers.value('access-control-allow-origin'), isNull, reason: path);
    }
  });

  test('a relay with no app address set answers as it did: no CORS anywhere, OPTIONS not taken', () async {
    await boot(appOrigin: null);
    for (final path in ['/market/abuse', '/feedback']) {
      final first = await preflight(path);
      expect(first.headers.value('access-control-allow-origin'), isNull, reason: path);
      expect(first.statusCode, isNot(HttpStatus.noContent), reason: path);
      expect(first.headers['vary'], isNull, reason: path);
    }
    final feedback = await ask('POST', '/feedback', origin: app, body: utf8.encode('{}'));
    expect(feedback.statusCode, HttpStatus.serviceUnavailable);
    expect(feedback.headers.value('access-control-allow-origin'), isNull);
  });

  test('GHOST_APP_ORIGIN is read as a browser names an address, or left off', () {
    expect(Relay.appOriginFrom(const {}), isNull);
    expect(Relay.appOriginFrom(const {'GHOST_APP_ORIGIN': ''}), isNull);
    expect(Relay.appOriginFrom(const {'GHOST_APP_ORIGIN': 'https://app.gogho.st'}), 'https://app.gogho.st');
    expect(Relay.appOriginFrom(const {'GHOST_APP_ORIGIN': ' https://App.Gogho.st/ '}), 'https://app.gogho.st');
    expect(Relay.appOriginFrom(const {'GHOST_APP_ORIGIN': 'https://app.gogho.st:8443'}), 'https://app.gogho.st:8443');
    expect(Relay.appOriginFrom(const {'GHOST_APP_ORIGIN': 'http://127.0.0.1:18980'}), 'http://127.0.0.1:18980');
    for (final bad in ['http://app.gogho.st', 'https://app.gogho.st/app', '*', 'null', 'app.gogho.st', 'https://app.gogho.st, https://x.example']) {
      expect(Relay.appOriginFrom({'GHOST_APP_ORIGIN': bad}), isNull, reason: bad);
    }
  });
}
