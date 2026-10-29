// Google's Gemini API, as the app's AI assistant asks it (lib/plugins/gemini/gemini_api.dart; docs/AI_PROVIDERS.md;
// Matt, 2026-10-29: "Add support for aster 6 and other Ai models as plugins in addition to claude like openAI google
// gemini etc"). Over a fake HttpClient only: the request translated from the Messages API's shape (a function call's
// thought signature carried back), the stream read back into its events (cut across chunks), the run's tools driven by
// it, the errors in plain words (a wrong key is Google's 400), the key's check and the models' list.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/assistant/provider.dart';
import 'package:ghost_md/assistant/provider_settings.dart';
import 'package:ghost_md/claude/claude_run.dart';
import 'package:ghost_md/claude/claude_tools.dart';
import 'package:ghost_md/plugins/gemini/gemini_api.dart';

import '../../assistant/fake_http.dart';
import '../../assistant/support.dart';

Map<String, Object?> _chunk(List<Map<String, Object?>> parts, {String? finish, Map<String, Object?>? usage}) => {
      'candidates': [
        {
          'content': {'role': 'model', 'parts': parts},
          'finishReason': ?finish,
          'index': 0,
        },
      ],
      'usageMetadata': ?usage,
      'modelVersion': 'gemini-test-pro',
    };

FakeAnswer _stream(List<Object> chunks, {int cut = 9}) => FakeAnswer.sse(cutInto([for (final c in chunks) sseData(c)].join(), cut));

void main() {
  group('the request', () {
    test('is the conversation as Gemini’s contents: a call named back in its response, its signature carried', () {
      final body = geminiBody({
        'model': 'gemini-test-pro',
        'max_tokens': 800,
        'system': 'Be brief.',
        'thinking': {'type': 'adaptive'},
        'tools': [
          {
            'name': 'read_note',
            'description': 'A note in full.',
            'eager_input_streaming': true,
            'input_schema': {
              'type': 'object',
              'additionalProperties': false,
              'properties': {
                'id': {'type': 'string', 'description': 'Its id.', 'default': 'x'},
                'tags': {
                  'type': 'array',
                  'items': {'type': 'string', r'$comment': 'dropped'},
                },
              },
              'required': ['id'],
            },
          },
          {
            'name': 'list_folders',
            'description': 'The folders.',
            'input_schema': {'type': 'object', 'properties': <String, Object?>{}, 'required': <String>[]},
          },
        ],
        'messages': [
          {'role': 'user', 'content': 'What is in n1?'},
          {
            'role': 'assistant',
            'content': [
              {'type': 'thinking', 'thinking': '', 'signature': 'claude-only'},
              {'type': 'text', 'text': 'Reading.'},
              {
                'type': 'tool_use',
                'id': geminiToolId(1, 'c2lnbmF0dXJl'),
                'name': 'read_note',
                'input': {'id': 'n1'},
              },
            ],
          },
          {
            'role': 'user',
            'content': [
              {'type': 'tool_result', 'tool_use_id': geminiToolId(1, 'c2lnbmF0dXJl'), 'content': '{"body":"milk"}'},
            ],
          },
        ],
      });
      expect(body['systemInstruction'], {
        'parts': [
          {'text': 'Be brief.'},
        ],
      });
      expect(body['generationConfig'], {'maxOutputTokens': 800});
      expect(body.containsKey('thinking'), isFalse);
      expect(body['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'What is in n1?'},
          ],
        },
        {
          'role': 'model',
          'parts': [
            {'text': 'Reading.'},
            {
              'functionCall': {
                'name': 'read_note',
                'args': {'id': 'n1'},
              },
              'thoughtSignature': 'c2lnbmF0dXJl',
            },
          ],
        },
        {
          'role': 'user',
          'parts': [
            {
              'functionResponse': {
                'name': 'read_note',
                'response': {'result': '{"body":"milk"}'},
              },
            },
          ],
        },
      ]);
      expect(body['tools'], [
        {
          'functionDeclarations': [
            {
              'name': 'read_note',
              'description': 'A note in full.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'id': {'type': 'string', 'description': 'Its id.'},
                  'tags': {
                    'type': 'array',
                    'items': {'type': 'string'},
                  },
                },
                'required': ['id'],
              },
            },
            // No properties: no parameters, which Gemini would refuse empty.
            {'name': 'list_folders', 'description': 'The folders.'},
          ],
        },
      ]);
      expect(geminiSignatureOf(geminiToolId(3, null)), isNull);
    });
  });

  group('the stream', () {
    test('drives the run’s tools: a whole call in one part, the signature in its id, the counts at the end', () async {
      final notes = MemoryNotes()..bodies['n1'] = '# Groceries\n\n- milk';
      var turn = 0;
      final http = FakeHttp((request) {
        turn += 1;
        if (turn == 1) {
          return _stream([
            _chunk([
              {'text': 'Adding it.'},
            ]),
            _chunk([
              {
                'functionCall': {
                  'name': ClaudeTool.append,
                  'args': {'id': 'n1', 'text': '- bread'},
                },
                'thoughtSignature': 'U0lH',
              },
            ], finish: 'STOP', usage: {'promptTokenCount': 1000, 'candidatesTokenCount': 40, 'thoughtsTokenCount': 10, 'cachedContentTokenCount': 200}),
          ]);
        }
        return _stream([
          _chunk([
            {'text': 'Added bread.'},
          ], finish: 'STOP', usage: {'promptTokenCount': 0, 'candidatesTokenCount': 0}),
        ]);
      });
      final settings = AiProviderSettings(MemorySecureStore(), prefix: 'gemini', name: 'Gemini', defaultRates: const AiRates(input: 1000, output: 1000));
      await settings.load();
      final run = ClaudeRun(api: GeminiApi(key: 'AIzaTest-0123456789abcdefghijklmnop', client: http.call, settings: settings), model: 'gemini-test-pro', notes: notes, desk: BlindDesk(notes), prompt: 'add bread', spend: settings.spend);
      await run.run();
      expect(run.state, ClaudeState.done, reason: run.problem);
      expect(notes.bodies['n1'], '# Groceries\n\n- milk\n- bread');
      expect(run.answer, 'Added bread.');
      final first = http.requests.first;
      expect(first.url.toString(), 'https://generativelanguage.googleapis.com/v1beta/models/gemini-test-pro:streamGenerateContent?alt=sse');
      expect(first.headers['x-goog-api-key'], 'AIzaTest-0123456789abcdefghijklmnop');
      expect(first.url.queryParameters.containsKey('key'), isFalse, reason: 'the key never rides in the address');
      // The call went back with its signature, and its answer named by it.
      final contents = http.requests[1].json['contents'] as List;
      final call = ((contents[1] as Map)['parts'] as List).last as Map;
      expect(call['thoughtSignature'], 'U0lH');
      final answer = ((contents[2] as Map)['parts'] as List).single as Map;
      expect((answer['functionResponse'] as Map)['name'], ClaudeTool.append);
      // 800 in and 200 from the cache at $1000 a million each, 50 out at $1000 a million: one dollar and five cents.
      expect(settings.spend.spent, closeTo(1.05, 1e-9));
    });

    test('a block, a cut for room and a thought part, each as the Messages API says them', () async {
      Future<List<(String, Map<String, Object?>)>> read(List<Object> chunks) async {
        final api = GeminiApi(key: 'k', client: FakeHttp((_) => _stream(chunks)).call);
        return [for (final e in await api.stream({'model': 'models/gemini-x', 'messages': const []}).events.toList()) (e.event, aiJson(e.data))];
      }

      String? stop(List<(String, Map<String, Object?>)> events) => ((events.firstWhere((e) => e.$1 == 'message_delta').$2['delta']) as Map)['stop_reason'] as String?;
      expect(stop(await read([_chunk(const [], finish: 'SAFETY')])), 'refusal');
      expect(stop(await read([
        {
          'promptFeedback': {'blockReason': 'OTHER'},
        },
      ])), 'refusal');
      expect(stop(await read([
        _chunk([
          {'text': 'Half'},
        ], finish: 'MAX_TOKENS'),
      ])), 'max_tokens');
      final thought = await read([
        _chunk([
          {'text': 'Considering.', 'thought': true},
          {'text': 'Done.'},
        ], finish: 'STOP'),
      ]);
      expect([for (final e in thought) if (e.$1 == 'content_block_start') (e.$2['content_block'] as Map)['type']], ['thinking', 'text']);
    });

    test('a refusal of the tools asks again without them, said once', () async {
      final settings = AiProviderSettings(MemorySecureStore(), prefix: 'gemini', name: 'Gemini');
      final http = FakeHttp((request) {
        if (request.json.containsKey('tools')) return FakeAnswer.json(400, {'error': {'code': 400, 'message': 'Function calling is not enabled for models/gemma-x', 'status': 'INVALID_ARGUMENT'}});
        return _stream([
          _chunk([
            {'text': 'Hi.'},
          ], finish: 'STOP'),
        ]);
      });
      final notes = MemoryNotes();
      final run = ClaudeRun(api: GeminiApi(key: 'k', client: http.call, settings: settings), model: 'gemma-x', notes: notes, desk: BlindDesk(notes), prompt: 'hi');
      await run.run();
      expect(run.answer, 'Hi.');
      expect(run.steps.where((s) => s.kind == 'notice'), hasLength(1));
      expect(settings.toolsRefused('gemma-x'), isTrue);
    });
  });

  group('the errors', () {
    test('a wrong key is Google’s 400, read as refused; the quota, the project and the trouble each in words', () {
      final wrong = geminiErrorOf(
        400,
        jsonEncode({
          'error': {
            'code': 400,
            'message': 'API key not valid. Please pass a valid API key.',
            'status': 'INVALID_ARGUMENT',
            'details': [
              {'@type': 'type.googleapis.com/google.rpc.ErrorInfo', 'reason': 'API_KEY_INVALID'},
            ],
          },
        }),
      );
      expect(wrong.badKey, isTrue);
      expect(wrong.message, 'The API key was refused. Check it in Settings › Gemini.');
      final quota = geminiErrorOf(429, jsonEncode({'error': {'code': 429, 'message': 'You exceeded your current quota.', 'status': 'RESOURCE_EXHAUSTED'}}));
      expect(quota.type, 'rate_limit_error');
      expect(quota.message, contains('quota'));
      expect(geminiErrorOf(403, jsonEncode({'error': {'code': 403, 'message': 'Generative Language API has not been used in project 1.', 'status': 'PERMISSION_DENIED'}})).type, 'permission_error');
      expect(geminiErrorOf(404, jsonEncode({'error': {'code': 404, 'message': 'models/x is not found', 'status': 'NOT_FOUND'}})).message, 'models/x is not found');
      expect(geminiErrorOf(503, jsonEncode({'error': {'code': 503, 'message': 'The model is overloaded.', 'status': 'UNAVAILABLE'}})).type, 'overloaded_error');
    });

    test('an error inside the stream ends it in words', () async {
      final api = GeminiApi(key: 'k', client: FakeHttp((_) => _stream([
            {
              'error': {'code': 500, 'message': 'Internal error', 'status': 'INTERNAL'},
            },
          ])).call);
      await expectLater(aiText(api.stream({'model': 'gemini-x', 'messages': const []}), who: 'Gemini'), throwsA(isA<AiError>().having((e) => e.message, 'message', 'Gemini is having trouble just now. Try again in a moment.')));
    });
  });

  group('the key and the models', () {
    test('a key is checked by the models list; the list is the ones that write text, the newest stable Pro first, over pages', () async {
      final http = FakeHttp((request) {
        if (request.url.queryParameters['pageSize'] == '1') return FakeAnswer.json(200, {'models': const []});
        final second = request.url.queryParameters['pageToken'] == 'next';
        return FakeAnswer.json(200, {
          'models': second
              ? [
                  {
                    'name': 'models/gemini-3.0-pro',
                    'displayName': 'Gemini 3 Pro',
                    'supportedGenerationMethods': ['generateContent', 'countTokens'],
                  },
                ]
              : [
                  {
                    'name': 'models/gemini-2.5-flash',
                    'displayName': 'Gemini 2.5 Flash',
                    'supportedGenerationMethods': ['generateContent'],
                  },
                  {
                    'name': 'models/gemini-3.5-pro-preview-09-2026',
                    'supportedGenerationMethods': ['generateContent'],
                  },
                  {
                    'name': 'models/text-embedding-004',
                    'supportedGenerationMethods': ['embedContent'],
                  },
                  {
                    'name': 'models/gemini-2.5-flash-image',
                    'supportedGenerationMethods': ['generateContent'],
                  },
                ],
          if (!second) 'nextPageToken': 'next',
        });
      });
      final api = GeminiApi(key: 'AIzaTest', client: http.call);
      expect(await api.check(), isNull);
      expect(http.requests.single.headers['x-goog-api-key'], 'AIzaTest');
      final models = await api.models();
      expect([for (final m in models) m.id], ['gemini-3.0-pro', 'gemini-2.5-flash', 'gemini-3.5-pro-preview-09-2026']);
      expect(models.first.name, 'Gemini 3 Pro');
      expect(http.requests.where((r) => r.url.queryParameters['pageToken'] == 'next'), hasLength(1));
    });

    test('the default is the newest stable Pro, else Flash, read from the list', () {
      expect(geminiDefault(['gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-3.0-pro-preview']), 'gemini-2.5-pro');
      expect(geminiDefault(['gemini-2.5-flash', 'gemini-3.0-flash']), 'gemini-3.0-flash');
      expect(geminiDefault(['gemini-3.0-pro-preview']), 'gemini-3.0-pro-preview');
      expect(geminiDefault(const []), isNull);
    });
  });
}
