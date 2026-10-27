// ElevenLabs' API as the plugin asks it (lib/plugins/elevenlabs/client.dart): the key in its header, the account read,
// a key checked, the person's own voices, a read asked with its model and format, and each failure as a sentence. No
// request leaves: the ground answers as ElevenLabs would.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/plugins/elevenlabs/elevenlabs.dart';
import 'package:ghost_md/plugins/elevenlabs/manifest.dart' as eleven;
import 'package:ghost_md/plugins/host.dart';

import '../github/support.dart';

final Uint8List mp3 = Uint8List.fromList([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 0, 0xff, 0xfb, 0x90, 0x64]);

FetchResponse failing(int status, Object? detail) => FetchResponse.json(status, {'detail': detail});

void main() {
  late TestGround ground;
  late List<Duration> waited;
  late Future<FetchResponse> Function(FetchRequest request) answer;

  ElevenLabsClient client() => ElevenLabsClient(apiKey: 'sk_test_key', sleep: (wait) async => waited.add(wait));

  setUp(() {
    waited = [];
    answer = (request) async => FetchResponse.json(200, const {});
    ground = useGround((request) => answer(request));
  });

  tearDown(() => usePluginGround(PluginGround()));

  test('reads the account with the key in xi-api-key: the plan and the month’s characters', () async {
    answer = (request) async => FetchResponse.json(200, {
          'subscription': {'tier': 'creator', 'character_count': 1234, 'character_limit': 100000, 'next_character_count_reset_unix': 1764547200},
        });
    final account = await client().account();
    final asked = ground.asked.single;
    expect(asked.method, 'GET');
    expect(asked.url.toString(), 'https://api.elevenlabs.io/v1/user');
    expect(header(asked, 'xi-api-key'), 'sk_test_key');
    expect((account.tier, account.used, account.limit, account.left), ('creator', 1234, 100000, 98766));
    expect(account.resets, DateTime.utc(2025, 12, 1));
  });

  test('a key checked: null when it works, refused when ElevenLabs does not know it, still a key when it only lacks a permission', () async {
    expect(await client().check(), isNull);
    answer = (request) async => failing(401, {'type': 'authentication_error', 'code': 'invalid_api_key', 'message': 'Invalid API key'});
    final refused = await client().check();
    expect(refused!.badKey, isTrue);
    expect(refused.message, contains('didn’t accept this key'));
    answer = (request) async => failing(401, {'status': 'missing_permissions', 'message': 'The API key you used is missing the permission user_read'});
    final limited = await client().check();
    expect((limited!.badKey, limited.missingPermission), (false, true));
    answer = (request) async => failing(401, {'type': 'authorization_error', 'code': 'unauthorized', 'message': 'This API key lacks the user_read permission'});
    final worded = await client().check();
    expect((worded!.badKey, worded.missingPermission), (false, true));
    expect(worded.message, contains('Give it Text to Speech'));
  });

  test('lists the person’s own voices, leaving out the ones ElevenLabs ships, each with a few words', () async {
    answer = (request) async => FetchResponse.json(200, {
          'voices': [
            {'voice_id': 'premade1', 'name': 'Roger', 'category': 'premade'},
            {'voice_id': 'mine1', 'name': ' Matt ', 'category': 'cloned', 'description': 'My own voice, read slowly'},
            {'voice_id': 'lib1', 'name': 'Narrator', 'category': 'professional', 'labels': {'accent': 'british', 'use_case': 'narration'}},
            {'voice_id': '', 'name': 'Broken'},
          ],
        });
    final voices = await client().voices();
    expect(ground.asked.single.url.path, '/v1/voices');
    expect([for (final v in voices) (v.id, v.name, v.line)], [('mine1', 'Matt', 'My own voice, read slowly'), ('lib1', 'Narrator', 'british, narration')]);
  });

  test('reads words aloud: POST to the voice, the model and the settings in JSON, MP3 at 44.1 kHz asked for', () async {
    answer = (request) async => FetchResponse(200, headers: const {'content-type': 'audio/mpeg'}, bytes: mp3);
    final bytes = await client().speak('Hello there.', voiceId: 'WQP7cQUF5aAS6Axh5yaa', modelId: 'eleven_v4');
    expect(bytes, mp3);
    final asked = ground.asked.single;
    expect(asked.method, 'POST');
    expect(asked.url.toString(), 'https://api.elevenlabs.io/v1/text-to-speech/WQP7cQUF5aAS6Axh5yaa?output_format=mp3_44100_128');
    expect(header(asked, 'Content-Type'), 'application/json');
    expect(header(asked, 'xi-api-key'), 'sk_test_key');
    expect(jsonDecode(asked.text), {
      'text': 'Hello there.',
      'model_id': 'eleven_v4',
      'voice_settings': {'stability': 0.5, 'similarity_boost': 0.75},
    });
    expect(asked.timeout, elevenSpeakTimeout);
  });

  test('never asks with a voice id that could reach another path', () async {
    await expectLater(client().speak('Hi', voiceId: '../v1/user', modelId: 'eleven_v4'), throwsA(isA<ElevenFailure>()));
    expect(ground.asked, isEmpty);
  });

  test('an answer that is not a sound is refused', () async {
    answer = (request) async => FetchResponse.json(200, {'ok': true});
    await expectLater(client().speak('Hi', voiceId: 'abc', modelId: 'eleven_v4'), throwsA(isA<ElevenFailure>().having((f) => f.message, 'message', contains('isn’t a sound'))));
  });

  group('failures, said as the person can act on them', () {
    Future<ElevenFailure> failureOf(FetchResponse response) async {
      answer = (request) async => response;
      try {
        await client().speak('Hi', voiceId: 'abc', modelId: 'eleven_v4');
      } on ElevenFailure catch (failure) {
        return failure;
      }
      fail('no failure');
    }

    test('credits spent, in either shape', () async {
      final now = await failureOf(failing(402, {'type': 'payment_required', 'code': 'insufficient_credits', 'message': 'not enough'}));
      expect(now.spent, isTrue);
      expect(now.message, contains('credits are used up'));
      final legacy = await failureOf(failing(401, {'status': 'quota_exceeded', 'message': 'This request exceeds your quota.'}));
      expect((legacy.spent, legacy.badKey), (true, false));
      expect(legacy.message, contains('credits are used up'));
      expect(elevenTrouble(failing(400, {'status': 'quota_exceeded', 'message': 'quota'})).message, contains('credits are used up'));
    });

    test('too long, a voice not the key’s, a model refused', () async {
      expect((await failureOf(failing(400, {'code': 'text_too_long', 'message': 'too long'}))).tooLong, isTrue);
      expect((await failureOf(failing(400, {'status': 'max_character_limit_exceeded'}))).tooLong, isTrue);
      final voice = await failureOf(failing(404, {'code': 'voice_not_found', 'message': 'nope'}));
      expect(voice.voiceRefused, isTrue);
      expect(voice.message, contains('doesn’t have that voice'));
      expect((await failureOf(failing(403, {'code': 'model_access_denied'}))).modelRefused, isTrue);
      expect((await failureOf(failing(400, {'code': 'unsupported_model'}))).modelRefused, isTrue);
    });

    test('a 422’s list, and words of ElevenLabs’ own otherwise', () async {
      expect((await failureOf(failing(422, [
        {'loc': ['body', 'text'], 'msg': 'field required', 'type': 'value_error'},
      ]))).message, 'ElevenLabs said: field required');
      expect((await failureOf(FetchResponse(418, bytes: utf8.encode('teapot')))).message, 'ElevenLabs answered 418.');
    });

    test('busy is asked again after Retry-After, twice, then said', () async {
      var asks = 0;
      answer = (request) async {
        asks += 1;
        if (asks < 3) return FetchResponse(429, headers: const {'retry-after': '7'}, bytes: utf8.encode(jsonEncode({'detail': {'code': 'concurrent_limit_exceeded'}})));
        return FetchResponse(200, bytes: mp3);
      };
      expect(await client().speak('Hi', voiceId: 'abc', modelId: 'eleven_v4'), mp3);
      expect(waited, [const Duration(seconds: 7), const Duration(seconds: 7)]);
      waited.clear();
      final failure = await failureOf(failing(429, {'code': 'system_busy'}));
      expect(failure.busy, isTrue);
      expect(failure.message, contains('busy'));
      expect(waited, hasLength(2));
    });

    test('no connection, and no answer in time, which is never asked again: it may have been billed', () async {
      answer = (request) async => throw const SocketLike();
      await expectLater(client().account(), throwsA(isA<ElevenFailure>().having((f) => f.message, 'message', elevenUnreachable)));
      ground.asked.clear();
      answer = (request) async => throw TimeoutException('slow');
      await expectLater(client().speak('Hi', voiceId: 'abc', modelId: 'eleven_v4'), throwsA(isA<ElevenFailure>().having((f) => f.message, 'message', elevenNoAnswer)));
      expect(ground.asked, hasLength(1));
    });
  });

  test('the key is read from the plugin’s secrets, trimmed; none is no client', () async {
    expect(ElevenLabsClient.kept(), isNull);
    await eleven.host.secrets.write(apiKeySecret, '  sk_kept  ');
    expect(ElevenLabsClient.kept()!.apiKey, 'sk_kept');
    expect(hasElevenKey(), isTrue);
  });
}

/// What a socket refused throws: an exception, not an error.
class SocketLike implements Exception {
  const SocketLike();
}
