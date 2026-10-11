import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/bytes.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/notion/notion.dart';
import 'package:ghost_md/plugins/notion/sha256.dart';

import 'support.dart';

/// Notion from the app (lib/plugins/notion/client.dart), on a phone that is stood in for (support.dart): the secure
/// store that keeps the sign-in, the browser that opens Notion's consent page, and a network that answers what
/// each test recorded for glyph-api's `claim` and `refresh` and for Notion itself. The cases are the web app's
/// `client.test.ts`, by their names, and the Rust's own (`src-tauri/src/notion.rs`), since the Rust's work is this
/// file's now; what the page's tests asserted of `invoke`'s arguments is asserted here of the request that goes.
const String api = 'https://ghostmarkdown.com/api/notion';
const String signInKey = 'glyph-notion-signin';
const String linksKey = 'glyph-notion-links';

String hex(List<int> bytes) => [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

void main() {
  late Phone phone;

  setUp(() => phone = Phone()..use());
  tearDown(() {
    resetNotionClient();
    usePluginGround(PluginGround());
  });

  group('the digest the challenge is made with', () {
    test('is SHA-256, by its published vectors', () {
      expect(hex(sha256(const [])), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(hex(sha256(utf8.encode('abc'))), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(hex(sha256(utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'))), '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
      // A message that fills its last block to the byte, and one a byte over, where the padding takes a block more.
      expect(hex(sha256(List.filled(55, 0x61))), '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318');
      expect(hex(sha256(List.filled(56, 0x61))), 'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a');
      expect(hex(sha256(List.filled(1000, 0x61))), '41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3');
      // RFC 7636, appendix B: the verifier and the challenge it must make.
      expect(challengeOf('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'), 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });
  });

  group('signing in with Notion', () {
    test('keeps a fresh state and verifier, and opens the consent page with the verifier hashed', () async {
      await startNotionSignIn();
      final kept = phone.storedJson(signInKey)! as Map;
      expect(kept['state'], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(kept['verifier'], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(kept['verifier'], isNot(kept['state']));
      expect(kept['at'], isA<int>());
      expect(phone.opened, ['$api/start?state=${kept['state']}&challenge=${toBase64Url(sha256(utf8.encode(kept['verifier'] as String)))}']);
      // Opening the page asked the network nothing.
      expect(phone.requests, isEmpty);
    });

    test('refuses on a binary too old to hold the sign-in, before anything is kept or opened', () async {
      phone.generation = 11;
      await expectLater(startNotionSignIn(), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', 'Notion needs the newest Ghost.md. Install it from Settings > Updates.')));
      expect(phone.kept.getItem(signInKey), isNull);
      expect(phone.opened, isEmpty);
    });

    test('has nothing to collect when no sign-in was started', () async {
      expect(await collectNotionSignIn(), isNull);
      expect(phone.requests, isEmpty);
    });

    test('says pending while the person is still on Notion’s page, and asks again next time', () async {
      await startNotionSignIn();
      final kept = phone.storedJson(signInKey)! as Map;
      phone.answer = (request) async => json(202, {'pending': true});
      expect(await collectNotionSignIn(), isA<NotionPending>());
      expect(await collectNotionSignIn(), isA<NotionPending>());
      expect(phone.requests, hasLength(2));
      final sent = phone.requests.first;
      expect(sent.url.toString(), '$api/claim');
      expect(sent.method, 'POST');
      expect(sent.headers, {'Content-Type': 'application/json'});
      expect(jsonDecode(sent.text), {'state': kept['state'], 'verifier': kept['verifier']});
    });

    test('hands a finished sign-in to the binary to keep, and forgets it', () async {
      await startNotionSignIn();
      phone.answer = (request) async => json(200, {'accessToken': 'secret', 'refreshToken': 'r1', 'botId': 'bot', 'workspaceId': 'ws', 'workspaceName': 'Studio', 'workspaceIcon': null});
      final collected = await collectNotionSignIn();
      expect((collected! as NotionSignedIn).account, const NotionAccount(connected: true, workspaceName: 'Studio'));
      // The tokens went to the secure store, whole, as the claim spelled them; nothing else keeps anything of them,
      // nor the flight.
      expect(jsonDecode(phone.secrets.held[accountSecret]!), {'accessToken': 'secret', 'refreshToken': 'r1', 'botId': 'bot', 'workspaceId': 'ws', 'workspaceName': 'Studio', 'workspaceIcon': null});
      expect(phone.kept.getItem(signInKey), isNull);
      expect(phone.kept.allKeys.where((key) => (phone.kept.getItem(key) ?? '').contains('secret')), isEmpty);
      expect(await collectNotionSignIn(), isNull);
      expect(await notionAccount(), const NotionAccount(connected: true, workspaceName: 'Studio'));
    });

    test('says why a sign-in was refused, in the service’s words or its own, and forgets it', () async {
      await startNotionSignIn();
      phone.answer = (request) async => json(400, {'error': 'The sign-in was cancelled on Notion.'});
      await expectLater(collectNotionSignIn(), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', 'The sign-in was cancelled on Notion.')));
      expect(await collectNotionSignIn(), isNull);

      resetNotionClient();
      await startNotionSignIn();
      phone.answer = (request) async => FetchResponse(502, bytes: utf8.encode('Bad gateway'));
      await expectLater(collectNotionSignIn(), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', 'Notion sign-in did not finish.')));
    });

    test('collects a sign-in the page kept across a reload for ten minutes, and not after', () async {
      final now = DateTime.utc(2026, 9, 25, 12).millisecondsSinceEpoch;
      phone.answer = (request) async => json(202);

      phone.kept.setItem(signInKey, jsonEncode({'state': 's', 'verifier': 'v', 'at': now - 9 * 60000}));
      resetNotionClient();
      notionNow = () => now;
      expect(await collectNotionSignIn(), isA<NotionPending>());

      phone.kept.setItem(signInKey, jsonEncode({'state': 's', 'verifier': 'v', 'at': now - 11 * 60000}));
      resetNotionClient();
      notionNow = () => now;
      expect(await collectNotionSignIn(), isNull);
      expect(phone.requests, hasLength(1));
    });

    test('forgets a sign-in in flight when Notion is disconnected, and tells the binary', () async {
      phone.secrets.held[accountSecret] = accountJson();
      await startNotionSignIn();
      await disconnectNotion();
      expect(phone.secrets.held.containsKey(accountSecret), isFalse);
      expect(await collectNotionSignIn(), isNull);
      expect(await notionAccount(), NotionAccount.signedOut);
    });

    test('knows the binary can talk to Notion once it has answered, for code that cannot wait', () async {
      expect(await notionAvailable(), isTrue);
      expect(notionReadyNow(), isTrue);
    });

    test('asks by itself the first time code that cannot wait asks, and knows by the next', () async {
      expect(notionReadyNow(), isFalse);
      await pumpEventQueue();
      expect(notionReadyNow(), isTrue);
    });
  });

  // src-tauri/src/notion.rs's own tests, and its refusals.
  group('the account, kept', () {
    test('a claim reads as an account', () async {
      final info = await saveNotionAccount(jsonDecode('{"accessToken":"secret_x","refreshToken":null,"botId":"b","workspaceId":"w","workspaceName":"AttackFM","workspaceIcon":null}'));
      expect(info, const NotionAccount(connected: true, workspaceName: 'AttackFM'));
      expect((await notionAccount()).workspaceName, 'AttackFM');
      await disconnectNotion();
      expect((await notionAccount()).connected, isFalse);
    });

    test('a claim with no token is refused, and nothing is kept', () async {
      for (final claim in [<String, Object?>{}, {'accessToken': ''}, {'access_token': 'snake'}, null, 'words']) {
        await expectLater(saveNotionAccount(claim), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', "Notion didn't give Glyph an access token.")));
      }
      expect(phone.secrets.held, isEmpty);
    });

    test('signed in means a token to call with', () async {
      expect(await notionAccount(), NotionAccount.signedOut, reason: 'nothing kept is signed out');
      phone.secrets.held[accountSecret] = '{"accessToken":"","workspaceName":"AttackFM"}';
      expect(await notionAccount(), NotionAccount.signedOut, reason: 'an empty token is signed out, whatever else is kept');
      phone.secrets.held[accountSecret] = '{ half a file';
      expect(await notionAccount(), NotionAccount.signedOut);
      phone.secrets.held[accountSecret] = '{"accessToken":"secret_x"}';
      expect(await notionAccount(), const NotionAccount(connected: true), reason: 'the rest may be missing');
    });

    test('is in the secure store alone, under the name the manifest lists, and answers with no wait once warmed', () async {
      expect(notionManifest.secrets, [accountSecret]);
      expect(notionManifest.storage, isNot(contains(accountSecret)));
      phone.secrets.held[accountSecret] = accountJson(workspace: 'Glyph HQ');
      expect(notionAccountNow(), NotionAccount.signedOut, reason: 'not read yet');
      await notionHost.secrets.warm();
      expect(notionAccountNow(), const NotionAccount(connected: true, workspaceName: 'Glyph HQ'));
      await disconnectNotion();
      expect(notionAccountNow(), NotionAccount.signedOut);
    });

    test('is signed out on a binary that cannot reach Notion, whatever is kept', () async {
      phone.secrets.held[accountSecret] = accountJson();
      phone.generation = 11;
      expect(await notionAccount(), NotionAccount.signedOut);
      expect(phone.secrets.reads, 0);
    });
  });

  group('asking Notion', () {
    setUp(() => phone.secrets.held[accountSecret] = accountJson(token: 'secret_x'));

    test('only the routes glyph uses', () {
      expect(allowedPath('search'), isTrue);
      expect(allowedPath('databases/abc123/query'), isTrue);
      expect(allowedPath('pages'), isTrue);
      expect(allowedPath('pages/abc123'), isTrue);
      expect(allowedPath('blocks/abc/children'), isTrue);
      expect(allowedPath('users/me'), isTrue);
      expect(allowedPath('data_sources/abc'), isTrue);
      expect(allowedPath('/pages/abc123'), isTrue);
      expect(allowedPath('oauth/token'), isFalse);
      expect(allowedPath('databases/../oauth/token'), isFalse);
      expect(allowedPath('https://evil.example/'), isFalse);
      expect(allowedPath('//evil.example'), isFalse);
    });

    test('refuses a route, a method or a call with no sign-in, in the binary’s words, before anything is sent', () async {
      await expectLater(notionRequest('POST', 'oauth/token'), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', "Glyph doesn't call Notion's oauth/token route.")));
      await expectLater(notionRequest('DELETE', 'pages/abc'), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', "Glyph doesn't send DELETE to Notion.")));
      phone.secrets.held.clear();
      await expectLater(notionRequest('GET', 'users/me'), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', "Glyph isn't signed in to Notion.")));
      expect(phone.requests, isEmpty);
    });

    test('sends the token and Notion’s version to api.notion.com, a body as JSON with its type, and none without', () async {
      phone.answer = (request) async => json(200, {'ok': 1});
      await notionRequest('get', '/users/me');
      final read = phone.requests.single;
      expect(read.method, 'GET');
      expect(read.url.toString(), 'https://api.notion.com/v1/users/me');
      expect(read.headers, {'Authorization': 'Bearer secret_x', 'Notion-Version': '2022-06-28'});
      expect(read.body, isNull);
      expect(read.timeout, const Duration(seconds: 30));

      await notionRequest('PATCH', 'pages/abc', {
        'properties': {'Done': {'checkbox': true}},
      });
      final wrote = phone.requests.last;
      expect(wrote.method, 'PATCH');
      expect(wrote.url.toString(), 'https://api.notion.com/v1/pages/abc');
      expect(wrote.headers, {'Authorization': 'Bearer secret_x', 'Notion-Version': '2022-06-28', 'Content-Type': 'application/json'});
      expect(jsonDecode(wrote.text), {
        'properties': {'Done': {'checkbox': true}},
      });
    });

    test('answers the body, and says each refusal as a sentence', () async {
      phone.answer = (request) async => json(200, {'ok': 1});
      expect(await notionRequest('GET', 'users/me'), {'ok': 1});
      phone.answer = (request) async => json(401, {'message': 'API token is invalid.'});
      await expectLater(notionRequest('GET', 'users/me'), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', 'Notion signed Ghost.md out. Sign in again in Settings › Plugins › Notion.')));
      phone.answer = (request) async => json(404);
      await expectLater(notionRequest('PATCH', 'pages/abc'), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', 'Notion can’t see that task. Share its board with Ghost.md in Notion.')));
      await expectLater(notionRequest('POST', 'databases/abc/query'), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', 'Notion can’t see that board. Share it with Ghost.md in Notion.')));
      phone.answer = (request) async => json(409, {'message': 'Conflict occurred while saving.'});
      await expectLater(notionRequest('POST', 'pages'), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', 'Conflict occurred while saving.')));
      phone.answer = (request) async => json(503);
      await expectLater(notionRequest('POST', 'pages'), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', 'Notion answered 503.')));
    });

    test('says a rate limit in Notion’s words, or by its number, and does not ask again by itself', () async {
      phone.answer = (request) async => FetchResponse.json(429, {'object': 'error', 'status': 429, 'code': 'rate_limited', 'message': 'You have been rate limited. Please try again in a few minutes.'});
      await expectLater(notionRequest('GET', 'pages/abc'), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', 'You have been rate limited. Please try again in a few minutes.')));
      expect(phone.requests, hasLength(1));
      phone.answer = (request) async => FetchResponse(429, headers: const {'Retry-After': '2'});
      await expectLater(notionRequest('GET', 'pages/abc'), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', 'Notion answered 429.')));
      expect(phone.requests, hasLength(2));
    });

    test('says so when Notion cannot be reached', () async {
      phone.answer = (request) => throw const FormatException('no route to host');
      await expectLater(notionRequest('GET', 'users/me'), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', "Notion couldn't be reached. Check the connection.")));
    });

    test('answers a 401 by refreshing through glyph-api once, keeps the fresh tokens, and asks again', () async {
      phone.secrets.held[accountSecret] = accountJson(token: 'old', refresh: 'r1', workspace: 'Studio');
      phone.answer = (request) async {
        if (request.url.host == 'ghostmarkdown.com') return json(200, {'accessToken': 'fresh', 'refreshToken': null});
        return request.bearer == 'fresh' ? json(200, {'ok': 1}) : json(401, {'message': 'API token is invalid.'});
      };
      expect(await notionRequest('POST', 'search', {'page_size': 1}), {'ok': 1});
      expect([for (final r in phone.requests) '${r.method} ${r.url} ${r.bearer}'], ['POST https://api.notion.com/v1/search old', 'POST $api/refresh null', 'POST https://api.notion.com/v1/search fresh']);
      final refresh = phone.requests[1];
      expect(refresh.headers, {'Content-Type': 'application/json'});
      expect(jsonDecode(refresh.text), {'refreshToken': 'r1'});
      // The body went again as it was.
      expect(jsonDecode(phone.requests[2].text), {'page_size': 1});
      // Fresh tokens over the old; a refresh token the service did not renew is kept, and the workspace stays.
      expect(jsonDecode(phone.secrets.held[accountSecret]!), {'accessToken': 'fresh', 'refreshToken': 'r1', 'botId': 'b', 'workspaceId': 'w', 'workspaceName': 'Studio', 'workspaceIcon': null});
    });

    test('leaves a 401 a 401 when there is nothing to refresh with, or the refresh is refused', () async {
      phone.answer = (request) async => json(401);
      await expectLater(notionRequest('GET', 'users/me'), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', startsWith('Notion signed Ghost.md out.'))));
      expect(phone.requests, hasLength(1), reason: 'no refresh token, no refresh');

      phone.requests.clear();
      phone.secrets.held[accountSecret] = accountJson(token: 'old', refresh: 'spent');
      phone.answer = (request) async => request.url.host == 'ghostmarkdown.com' ? json(502, {'error': 'Notion said no: The token is spent.'}) : json(401);
      await expectLater(notionRequest('GET', 'users/me'), throwsA(isA<NotionFailure>().having((f) => f.message, 'message', startsWith('Notion signed Ghost.md out.'))));
      expect(phone.requests, hasLength(2), reason: 'asked once, refreshed once, and not asked again');
      expect(jsonDecode(phone.secrets.held[accountSecret]!)['accessToken'], 'old');
    });

    test('lists the boards shared with it, each with its title property and what marks a task done', () async {
      phone.answer = (request) async => json(200, {
            'results': [
              {
                'id': 'b1',
                'url': 'https://notion.so/b1',
                'title': [
                  {'plain_text': 'Road'},
                  {'plain_text': 'map'},
                ],
                'properties': {
                  'Task': {'type': 'title'},
                  'Done': {'type': 'checkbox'},
                  'Stage': {'type': 'status'},
                },
              },
              {
                'id': 'b2',
                'url': 'https://notion.so/b2',
                'title': <Object?>[],
                'properties': {
                  'Name': {'type': 'title'},
                  'Shipped': {'type': 'checkbox'},
                },
              },
              {'id': 'b3', 'url': 'https://notion.so/b3'},
            ],
            // More than a page of them: the page asks for fifty and no more, and so does this.
            'has_more': true,
            'next_cursor': 'cursor-2',
          });
      expect(await listBoards(), const [
        // A status is preferred to a checkbox for done: it is what a board's columns are.
        Board(id: 'b1', url: 'https://notion.so/b1', title: 'Roadmap', titleProperty: 'Task', doneProperty: DoneProperty('Stage', 'status')),
        Board(id: 'b2', url: 'https://notion.so/b2', title: 'Untitled board', titleProperty: 'Name', doneProperty: DoneProperty('Shipped', 'checkbox')),
        Board(id: 'b3', url: 'https://notion.so/b3', title: 'Untitled board', titleProperty: 'Name'),
      ]);
      expect(phone.asked, [
        {
          'method': 'POST',
          'path': 'search',
          'body': {
            'filter': {'property': 'object', 'value': 'database'},
            'sort': {'direction': 'descending', 'timestamp': 'last_edited_time'},
            'page_size': 50,
          },
        },
      ]);
    });

    const board = Board(id: 'b1', url: 'https://notion.so/b1', title: 'Roadmap', titleProperty: 'Task');

    test('makes a task on the board under its title property, cut to what Notion takes', () async {
      phone.answer = (request) async => json(200, {'id': 'p1', 'url': 'https://notion.so/p1'});
      final task = await createTask(board, 'x' * 2500);
      expect((task.id, task.title, task.url), ('p1', 'x' * 2500, 'https://notion.so/p1'));
      expect(phone.asked, [
        {
          'method': 'POST',
          'path': 'pages',
          'body': {
            'parent': {'database_id': 'b1'},
            'properties': {
              'Task': {
                'title': [
                  {
                    'type': 'text',
                    'text': {'content': 'x' * 2000},
                  },
                ],
              },
            },
          },
        },
      ]);
    });
  });

  group('which board a note sends to', () {
    const road = Board(id: 'b1', url: 'u', title: 'Roadmap', titleProperty: 'Task');

    test('is kept on this phone per note, and unlinked by a null', () {
      expect(boardFor('n1'), isNull);
      linkBoard('n1', road);
      linkBoard('n2', road);
      expect(boardFor('n1'), road);
      linkBoard('n1', null);
      expect(boardFor('n1'), isNull);
      expect(boardLinks().keys, ['n2']);
      expect(phone.storedJson(linksKey), {
        'n2': {'id': 'b1', 'title': 'Roadmap', 'url': 'u', 'titleProperty': 'Task', 'doneProperty': null},
      });
    });

    test('never changes the links another reader already holds', () {
      linkBoard('n1', road);
      final held = boardLinks();
      linkBoard('n2', road);
      expect(held.keys, ['n1']);
      expect(() => held['n3'] = road, throwsUnsupportedError);
    });

    test('reads back what the web app kept, and leaves out what is not a board', () {
      phone.kept.setItem(linksKey, jsonEncode({
        'n1': {'id': 'b1', 'url': 'https://notion.so/b1', 'title': 'Roadmap', 'titleProperty': 'Task', 'doneProperty': {'name': 'Stage', 'kind': 'status'}},
        'n2': 'not a board',
        'n3': {'id': 'b3'},
      }));
      expect(boardLinks(), {'n1': const Board(id: 'b1', url: 'https://notion.so/b1', title: 'Roadmap', titleProperty: 'Task', doneProperty: DoneProperty('Stage', 'status'))});
    });
  });

  group('the manifest', () {
    test('holds the plugin to its two hosts, whatever an address in a note says', () async {
      await expectLater(notionHost.fetch(FetchRequest(method: 'GET', url: Uri.parse('https://evil.example/v1/pages'))), throwsA(isA<PluginPermissionError>()));
      await expectLater(notionHost.fetch(FetchRequest(method: 'GET', url: Uri.parse('https://attack.fm/glyph/api/notion/refresh'))), throwsA(isA<PluginPermissionError>()));
      expect(phone.requests, isEmpty);
    });
  });
}
