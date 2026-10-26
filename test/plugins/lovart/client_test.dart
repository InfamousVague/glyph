// Lovart's API as the plugin asks it (lib/plugins/lovart/client.dart): the signature, the headers, the envelope and its
// failures, a generation polled to its images, a refusal, a costly step never confirmed, the time limit, and the project
// kept. No request leaves: the ground answers as Lovart would, on a clock the test moves.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/lovart/lovart.dart';
import 'package:ghost_md/plugins/lovart/manifest.dart' as lovart;

import '../support.dart';

final Uint8List png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4]);
final Uint8List jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2]);

FetchResponse ok(Object? data) => FetchResponse.json(200, {'code': 0, 'message': 'ok', 'data': data});

/// Lovart, as the skill's source says it answers: a thread that runs [runs] polls, then is done.
class FakeLovart {
  FakeLovart({this.runs = 2, this.result, this.validProject = true});

  int runs;
  Map<String, Object?>? result;
  bool validProject;
  final List<String> paths = [];
  int made = 0;

  Map<String, Object?> get images => {
        'items': [
          {'type': 'assistant', 'text': 'Here are your images.'},
          {
            'type': 'generator',
            'artifacts': [
              {'type': 'image', 'content': 'https://assets-persist.lovart.ai/a/one.png'},
              {'type': 'image', 'content': 'https://assets-persist.lovart.ai/a/two.jpg'},
            ],
          },
        ],
        'failures': <Object?>[],
      };

  Future<FetchResponse> answer(FetchRequest request) async {
    final path = request.url.path;
    paths.add('${request.method} $path');
    if (request.url.host == 'assets-persist.lovart.ai') return FetchResponse(200, bytes: path.endsWith('.png') ? png : jpeg);
    switch (path) {
      case '/v1/openapi/mode/query':
        return ok({'unlimited': false});
      case '/v1/openapi/project/save':
        made += 1;
        return ok({'project_id': 'proj-$made'});
      case '/v1/openapi/project/validate':
        return ok({'valid': validProject, 'project_name': 'Ghost'});
      case '/v1/openapi/chat':
        return ok({'thread_id': 'thread-1'});
      case '/v1/openapi/chat/status':
        if (runs > 0) {
          runs -= 1;
          return ok({'status': 'running'});
        }
        return ok({'status': 'done'});
      case '/v1/openapi/chat/result':
        return ok(result ?? images);
    }
    return FetchResponse.json(404, {'message': 'no route'});
  }
}

void main() {
  late TestGround ground;
  late FakeLovart server;
  late DateTime clock;
  late List<Duration> waited;

  LovartClient client() => LovartClient(
        accessKey: 'ak-test',
        secretKey: 'sk-test-secret',
        now: () => clock,
        sleep: (wait) async {
          waited.add(wait);
          clock = clock.add(wait);
        },
        idempotency: () => 'idem-1',
      );

  setUp(() {
    server = FakeLovart();
    ground = TestGround(answer: (request) => server.answer(request));
    usePluginGround(ground.ground);
    clock = DateTime.fromMillisecondsSinceEpoch(1761480000 * 1000, isUtc: true);
    waited = [];
  });

  tearDown(() => usePluginGround(PluginGround()));

  test('signs METHOD, path and seconds with HMAC-SHA256, as Python’s hmac does', () {
    // python3 -c "import hmac,hashlib; print(hmac.new(b'sk-test-secret', b'POST\n/v1/openapi/chat\n1761480000', hashlib.sha256).hexdigest())"
    expect(lovartSignature('sk-test-secret', 'POST', '/v1/openapi/chat', 1761480000), '1c4814180b7afba54cd2097c5a47b2e6a5c5aad0bd52a6a68ed87743f52b5a48');
    expect(lovartSignature('sk-test-secret', 'GET', '/v1/openapi/chat/status', 1761480000), '3025d146b917d7c9e5a0ab2e8ed6837d62f82661c77fe62be5c4059c3c0be691');
  });

  test('sends the keys, the signature over the path without its query, a browser’s agent, and an idempotency key on a POST', () async {
    await client().start('a red chair', project: 'proj-9');
    final chat = ground.asked.single;
    expect(chat.url.toString(), 'https://lgw.lovart.ai/v1/openapi/chat');
    expect(chat.headers, {
      'X-Access-Key': 'ak-test',
      'X-Timestamp': '1761480000',
      'X-Signature': '1c4814180b7afba54cd2097c5a47b2e6a5c5aad0bd52a6a68ed87743f52b5a48',
      'X-Signed-Method': 'POST',
      'X-Signed-Path': '/v1/openapi/chat',
      'Content-Type': 'application/json',
      'User-Agent': lovartAgent,
      'Idempotency-Key': 'idem-1',
    });
    expect(jsonDecode(chat.text), {'prompt': 'a red chair', 'project_id': 'proj-9', 'mode': 'fast'});

    ground.asked.clear();
    await client().finish('thread-1');
    final status = ground.asked.first;
    expect(status.url.query, 'thread_id=thread-1');
    expect(status.headers['X-Signed-Path'], '/v1/openapi/chat/status');
    expect(status.headers.containsKey('Idempotency-Key'), isFalse);
  });

  test('the keys are checked with /mode/query, and a 401 is said as keys refused', () async {
    expect(await client().check(), isNull);
    expect(server.paths, ['POST /v1/openapi/mode/query']);

    ground = TestGround(answer: (_) async => FetchResponse.json(401, {'message': 'invalid signature'}));
    usePluginGround(ground.ground);
    final wrong = await client().check();
    expect(wrong?.badKeys, isTrue);
    expect(wrong?.message, contains('didn’t accept these keys'));
  });

  test('Lovart’s own message is said for a 402 and for a code that is not 0', () async {
    ground = TestGround(answer: (_) async => FetchResponse.json(402, {'code': 2012, 'message': 'Insufficient credits. Upgrade your plan to continue.'}));
    usePluginGround(ground.ground);
    final credits = await client().check();
    expect((credits?.status, credits?.code, credits?.message), (402, 2012, 'Insufficient credits. Upgrade your plan to continue.'));

    ground = TestGround(answer: (_) async => FetchResponse.json(200, {'code': 2011, 'message': 'A task is still running on this thread.'}));
    usePluginGround(ground.ground);
    final busy = await client().check();
    expect((busy?.code, busy?.message), (2011, 'A task is still running on this thread.'));
  });

  test('a 429 waits as long as Retry-After says, signed again, then goes on', () async {
    var first = true;
    ground = TestGround(answer: (request) async {
      if (first) {
        first = false;
        return FetchResponse(429, headers: const {'Retry-After': '7'}, bytes: utf8.encode('{"message":""}'));
      }
      return ok({'unlimited': false});
    });
    usePluginGround(ground.ground);
    expect(await client().check(), isNull);
    expect(waited, [const Duration(seconds: 7)]);
    expect(ground.asked.map((r) => r.headers['X-Timestamp']), ['1761480000', '1761480007']);
    expect(ground.asked.map((r) => r.headers['Idempotency-Key']).toSet(), {'idem-1'});
  });

  test('a generation: a project, the chat, polled every 3 s, done looked at again 5 s on, then its images fetched with Lovart’s Referer', () async {
    final images = await client().generate('a calm reading nook');
    expect(images, [png, jpeg]);
    expect(server.paths, [
      'POST /v1/openapi/project/save',
      'POST /v1/openapi/chat',
      'GET /v1/openapi/chat/status',
      'GET /v1/openapi/chat/status',
      'GET /v1/openapi/chat/status',
      'GET /v1/openapi/chat/status',
      'GET /v1/openapi/chat/result',
      'GET /a/one.png',
      'GET /a/two.jpg',
    ]);
    expect(waited, [lovartPollEvery, lovartPollEvery, lovartDoneSettle]);
    final download = ground.asked[7];
    expect((download.headers['Referer'], download.headers['User-Agent']), ('https://www.lovart.ai/', lovartAgent));
    expect(download.headers.containsKey('X-Access-Key'), isFalse, reason: 'the keys go to the API alone');
  });

  test('done with no image is the agent’s refusal, in its words', () async {
    server.result = {
      'items': [
        {'type': 'assistant', 'text': 'I can’t make that image.'},
      ],
    };
    await expectLater(client().generate('something refused'), throwsA(isA<LovartRefused>().having((r) => r.text, 'text', 'I can’t make that image.').having((r) => r.message, 'message', 'Lovart made no image: I can’t make that image.')));
  });

  test('a step waiting for the person’s yes is said with its cost, and never confirmed', () async {
    server.result = {
      'items': <Object?>[],
      'pending_confirmation': {'estimated_cost': 40, 'tool': 'generate_video'},
    };
    await expectLater(client().generate('a video'), throwsA(isA<LovartNeedsConfirmation>().having((c) => c.cost, 'cost', 40).having((c) => c.said, 'said', contains('about 40 credits'))));
    expect(server.paths.where((p) => p.contains('confirm')), isEmpty);
  });

  test('a step waiting while the chat still runs is found twenty seconds in', () async {
    server.runs = 1000;
    server.result = {'pending_confirmation': {'estimated_cost': 12}};
    await expectLater(client().generate('premium'), throwsA(isA<LovartNeedsConfirmation>()));
    expect(server.paths.where((p) => p.endsWith('/chat/result')), hasLength(1));
    expect(server.paths.where((p) => p.endsWith('/chat/status')), hasLength(9));
    expect(server.paths.where((p) => p.contains('confirm')), isEmpty);
  });

  test('gives up after the time allowed', () async {
    server.runs = 1000;
    server.result = {'items': <Object?>[]};
    await expectLater(client().generate('slow', timeout: const Duration(minutes: 1)), throwsA(isA<LovartFailure>().having((f) => f.message, 'message', contains('more than a minute'))));
    expect(clock.difference(DateTime.fromMillisecondsSinceEpoch(1761480000 * 1000, isUtc: true)), greaterThanOrEqualTo(const Duration(minutes: 1)));
  });

  test('keeps the project, checks it before each use, and makes another where Lovart no longer has it', () async {
    expect(await client().ensureProject(), 'proj-1');
    expect(ground.kept.getItem(lovart.projectKey), '"proj-1"');
    expect(await client().ensureProject(), 'proj-1');
    expect(server.paths, ['POST /v1/openapi/project/save', 'GET /v1/openapi/project/validate']);
    server.validProject = false;
    expect(await client().ensureProject(), 'proj-2');
    expect(ground.kept.getItem(lovart.projectKey), '"proj-2"');
  });

  test('knows a picture by its first bytes', () {
    expect(pictureExtension(png), 'png');
    expect(pictureExtension(jpeg), 'jpg');
    expect(pictureExtension(Uint8List.fromList(utf8.encode('RIFF\x00\x00\x00\x00WEBPVP8 '))), 'webp');
    expect(pictureExtension(Uint8List.fromList(utf8.encode('<html>'))), isNull);
  });
}
