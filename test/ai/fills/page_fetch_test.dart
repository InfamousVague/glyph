import 'dart:convert';
import 'dart:io';

import 'package:ghost_md/ai/fills/web.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app's own fetch for a live blank's lookup (lib/ai/fills/web.dart `pageFetcher`; docs/PARITY.md, Differs 27),
/// asked of a server of this file's. No widgets' binding here: under one every request is answered 400.
void main() {
  // The page's `fetch` follows a redirect (its default); the app's own fetch answered the 3xx as it came, which
  // the lookups read as nothing found. Ten seconds at most is the page's own (ai/fills/web.ts `pageFetch`).
  test('a lookup follows a redirect to where the source moved, as the page\'s fetch does', () async {
    final paths = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      paths.add(request.uri.path);
      if (request.uri.path == '/moved') {
        request.response.statusCode = 301;
        request.response.headers.set('location', '/here');
      } else if (request.uri.path == '/loop') {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/loop');
      } else {
        request.response.headers.set('content-type', 'application/json');
        request.response.write(jsonEncode({'found': true}));
      }
      await request.response.close();
    });
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final fetch = pageFetcher(client: client, userAgent: 'GhostMd/test');
    final answer = await fetch('http://127.0.0.1:${server.port}/moved');
    expect(answer.status, 200);
    expect(answer.json, {'found': true});
    expect(paths, ['/moved', '/here']);
    // One that never arrives is the network's failure, as a fetch that redirects for ever rejects.
    await expectLater(fetch('http://127.0.0.1:${server.port}/loop'), throwsA(isA<StateError>().having((e) => e.message, 'message', 'offline')));
  });
}
