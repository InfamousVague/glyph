// OpenAI's Chat Completions, as the app's AI assistant asks it (lib/plugins/openai/chat_api.dart; docs/AI_PROVIDERS.md;
// Matt, 2026-10-29: "Add support for aster 6 and other Ai models as plugins in addition to claude like openAI google
// gemini etc"). Over a fake HttpClient only: the request translated from the Messages API's shape, the stream read back
// into its events (a tool call's arguments cut across chunks and lines), the run's tools driven by it, the errors in
// plain words, the key's check and the models' list. Nothing reaches the network.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/assistant/provider.dart';
import 'package:ghost_md/assistant/provider_settings.dart';
import 'package:ghost_md/claude/claude_run.dart';
import 'package:ghost_md/claude/claude_spend.dart';
import 'package:ghost_md/claude/claude_tools.dart';
import 'package:ghost_md/plugins/openai/chat_api.dart';

import '../../assistant/fake_http.dart';
import '../../assistant/support.dart';

/// One chunk of Chat Completions' stream.
Map<String, Object?> _chunk({String? content, List<Map<String, Object?>>? calls, String? finish, String? reasoning}) => {
      'id': 'chatcmpl-1',
      'object': 'chat.completion.chunk',
      'model': 'gpt-test',
      'choices': [
        {
          'index': 0,
          'delta': {'content': ?content, 'tool_calls': ?calls, 'reasoning_content': ?reasoning},
          'finish_reason': finish,
        },
      ],
    };

Map<String, Object?> _usage(int prompt, int completion, {int cached = 0}) => {
      'choices': <Object?>[],
      'usage': {
        'prompt_tokens': prompt,
        'completion_tokens': completion,
        'prompt_tokens_details': {'cached_tokens': cached},
      },
    };

/// A stream of [chunks], each an event, the whole cut into pieces of [cut] characters (lines and letters split).
FakeAnswer _stream(List<Object> chunks, {int cut = 7}) => FakeAnswer.sse(cutInto([for (final c in chunks) sseData(c), 'data: [DONE]\n\n'].join(), cut));

Future<List<(String, Map<String, Object?>)>> _events(AiCall call) async => [for (final e in await call.events.toList()) (e.event, aiJson(e.data))];

void main() {
  group('the request', () {
    test('is the conversation in Chat Completions’ shape: system, tool calls, tool results, the tools', () {
      final body = openAiBody({
        'model': 'gpt-test',
        'max_tokens': 900,
        'system': 'Be brief.',
        'thinking': {'type': 'adaptive'},
        'output_config': {'effort': 'high'},
        'tools': [
          {
            'name': 'read_note',
            'description': 'A note in full.',
            'input_schema': {
              'type': 'object',
              'properties': {
                'id': {'type': 'string'},
              },
              'required': <String>[],
            },
          },
        ],
        'messages': [
          {'role': 'user', 'content': 'What is in my list?'},
          {
            'role': 'assistant',
            'content': [
              {'type': 'thinking', 'thinking': 'Claude’s own', 'signature': 'sig'},
              {'type': 'text', 'text': 'Looking.'},
              {
                'type': 'tool_use',
                'id': 'call_1',
                'name': 'read_note',
                'input': {'id': 'n1'},
              },
            ],
          },
          {
            'role': 'user',
            'content': [
              {'type': 'tool_result', 'tool_use_id': 'call_1', 'content': '{"body":"milk"}'},
              {'type': 'tool_result', 'tool_use_id': 'call_2', 'content': 'No such note.', 'is_error': true},
              {'type': 'text', 'text': 'And the other one?'},
            ],
          },
        ],
      });
      expect(body['model'], 'gpt-test');
      expect(body['stream'], isTrue);
      expect(body['stream_options'], {'include_usage': true});
      expect(body['max_completion_tokens'], 900);
      expect(body.containsKey('max_tokens'), isFalse);
      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('output_config'), isFalse);
      expect(body['messages'], [
        {'role': 'system', 'content': 'Be brief.'},
        {'role': 'user', 'content': 'What is in my list?'},
        {
          'role': 'assistant',
          'content': 'Looking.',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {'name': 'read_note', 'arguments': '{"id":"n1"}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'call_1', 'content': '{"body":"milk"}'},
        {'role': 'tool', 'tool_call_id': 'call_2', 'content': 'Error: No such note.'},
        {'role': 'user', 'content': 'And the other one?'},
      ]);
      expect(body['tools'], [
        {
          'type': 'function',
          'function': {
            'name': 'read_note',
            'description': 'A note in full.',
            'parameters': {
              'type': 'object',
              'properties': {
                'id': {'type': 'string'},
              },
              'required': <String>[],
            },
          },
        },
      ]);
      // A compatible endpoint is sent `max_tokens`, and a run without tools sends none.
      final compatible = openAiBody({'model': 'm', 'max_tokens': 10, 'messages': const []}, completionTokens: false, tools: false);
      expect(compatible['max_tokens'], 10);
      expect(compatible.containsKey('tools'), isFalse);
    });
  });

  group('the stream', () {
    test('is read back as the Messages API’s events: words, a tool call cut across chunks, the stop and the counts', () async {
      final args = jsonEncode({'id': 'n1', 'text': '- bread “brown”'});
      final http = FakeHttp((_) => _stream([
            _chunk(content: 'Adding '),
            _chunk(content: 'it.'),
            _chunk(calls: [
              {
                'index': 0,
                'id': 'call_9',
                'type': 'function',
                'function': {'name': 'append_to_note', 'arguments': ''},
              },
            ]),
            for (final piece in cutInto(args, 5))
              _chunk(calls: [
                {
                  'index': 0,
                  'function': {'arguments': piece},
                },
              ]),
            _chunk(finish: 'tool_calls'),
            _usage(120, 30, cached: 20),
          ]));
      final api = OpenAiChatApi(key: 'sk-test-0123456789abcdef', client: http.call);
      final events = await _events(api.stream({
        'model': 'gpt-test',
        'max_tokens': 100,
        'messages': [
          {'role': 'user', 'content': 'add bread'},
        ],
      }));
      expect(http.requests.single.url.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(http.requests.single.headers['authorization'], 'Bearer sk-test-0123456789abcdef');
      expect([for (final e in events) e.$1], [
        'message_start',
        'content_block_start',
        'content_block_delta',
        'content_block_delta',
        'content_block_stop',
        'content_block_start',
        for (final _ in cutInto(args, 5)) 'content_block_delta',
        'content_block_stop',
        'message_delta',
        'message_stop',
      ]);
      expect((events.first.$2['message'] as Map)['model'], 'gpt-test');
      final tool = events.firstWhere((e) => e.$1 == 'content_block_start' && (e.$2['content_block'] as Map)['type'] == 'tool_use').$2;
      expect(tool['content_block'], {'type': 'tool_use', 'id': 'call_9', 'name': 'append_to_note', 'input': <String, Object?>{}});
      final json = [
        for (final e in events)
          if (e.$1 == 'content_block_delta' && (e.$2['delta'] as Map)['type'] == 'input_json_delta') (e.$2['delta'] as Map)['partial_json'] as String,
      ].join();
      expect(jsonDecode(json), {'id': 'n1', 'text': '- bread “brown”'});
      final last = events.firstWhere((e) => e.$1 == 'message_delta').$2;
      expect(last['delta'], {'stop_reason': 'tool_use'});
      expect(last['usage'], {'input_tokens': 100, 'output_tokens': 30, 'cache_read_input_tokens': 20});
    });

    test('drives the run’s tools as Claude’s stream does, and the meter counts it at the provider’s rates', () async {
      final notes = MemoryNotes()..bodies['n1'] = '# Groceries\n\n- milk';
      final desk = BlindDesk(notes);
      final args = jsonEncode({'id': 'n1', 'text': '- bread'});
      var turn = 0;
      final http = FakeHttp((request) {
        turn += 1;
        if (turn == 1) {
          return _stream([
            _chunk(calls: [
              {
                'index': 0,
                'id': 'call_1',
                'function': {'name': ClaudeTool.append, 'arguments': args.substring(0, 6)},
              },
            ]),
            _chunk(calls: [
              {
                'index': 0,
                'function': {'arguments': args.substring(6)},
              },
            ]),
            // A local server's way: `stop` though a tool was called.
            _chunk(finish: 'stop'),
            _usage(1000000, 0),
          ], cut: 11);
        }
        return _stream([_chunk(content: 'Added bread to Groceries.'), _chunk(finish: 'stop'), _usage(0, 1000000)]);
      });
      final settings = AiProviderSettings(MemorySecureStore(), prefix: 'openai', name: 'OpenAI', defaultRates: const AiRates(input: 2, output: 8));
      await settings.load();
      final run = ClaudeRun(api: OpenAiChatApi(key: 'sk-test-0123456789abcdef', client: http.call, settings: settings), model: 'gpt-test', notes: notes, desk: desk, prompt: 'add bread', spend: settings.spend);
      await run.run();
      expect(run.state, ClaudeState.done, reason: run.problem);
      expect(notes.bodies['n1'], '# Groceries\n\n- milk\n- bread');
      expect(run.answer, 'Added bread to Groceries.');
      // The second request carried the call and its answer back, in OpenAI's shape.
      final second = http.requests[1].json['messages'] as List;
      expect((second[1] as Map)['tool_calls'], isNotEmpty);
      expect((second[2] as Map)['role'], 'tool');
      expect((second[2] as Map)['tool_call_id'], 'call_1');
      // A million in at $2, a million out at $8.
      expect(settings.spend.spent, closeTo(10, 1e-9));
      expect(settings.spend.requests, 2);
    });

    test('a model that refuses the tools is asked again without them, and the chat is told once', () async {
      final http = FakeHttp((request) {
        if (request.json.containsKey('tools')) return FakeAnswer.json(400, {'error': {'message': 'This model does not support tools.', 'type': 'invalid_request_error'}});
        return _stream([_chunk(content: 'Hello.'), _chunk(finish: 'stop')]);
      });
      final settings = AiProviderSettings(MemorySecureStore(), prefix: 'custom-ai', name: 'Custom AI model', needsBase: true, keyOptional: true);
      final notes = MemoryNotes();
      final api = OpenAiChatApi(key: null, base: 'http://localhost:11434/v1', official: false, client: http.call, settings: settings);
      final run = ClaudeRun(api: api, model: 'llama-test', notes: notes, desk: BlindDesk(notes), prompt: 'hi');
      await run.run();
      expect(run.state, ClaudeState.done, reason: run.problem);
      expect(run.answer, 'Hello.');
      expect([for (final s in run.steps) if (s.kind == 'notice') s.words], [noToolsNotice('llama-test')]);
      expect(http.requests.length, 2);
      expect(http.requests.first.headers.containsKey('authorization'), isFalse);
      expect(http.requests.first.json['max_tokens'], 16000);
      // Asked again: straight without them, and nothing said.
      final again = ClaudeRun(api: api, model: 'llama-test', notes: notes, desk: BlindDesk(notes), prompt: 'hi', tools: !settings.toolsRefused('llama-test'));
      await again.run();
      expect(again.steps.where((s) => s.kind == 'notice'), isEmpty);
      expect(http.requests.last.json.containsKey('tools'), isFalse);
      expect(http.requests.length, 3);
    });

    test('an older server that knows no stream_options is asked again without it', () async {
      final http = FakeHttp((request) {
        if (request.json.containsKey('stream_options')) return FakeAnswer.json(400, {'error': {'message': 'Unrecognized request argument supplied: stream_options'}});
        return _stream([_chunk(content: 'ok'), _chunk(finish: 'stop')]);
      });
      final api = OpenAiChatApi(key: 'k', base: 'https://example.test/v1', official: false, client: http.call);
      expect(await aiText(api.stream({'model': 'm', 'messages': const []}), who: 'It'), 'ok');
      expect(http.requests.length, 2);
    });

    test('says a refusal, an answer cut off for room, and a stream that broke, in words', () async {
      Future<Object?> fails(List<Object> chunks) async {
        final api = OpenAiChatApi(key: 'k', client: FakeHttp((_) => _stream(chunks)).call);
        try {
          await aiText(api.stream({'model': 'm', 'messages': const []}), who: 'OpenAI');
          return null;
        } catch (error) {
          return error;
        }
      }

      expect('${await fails([_chunk(content: 'partial'), _chunk(finish: 'length')])}', 'OpenAI’s write-up ran out of room and was cut off.');
      final refused = await fails([_chunk(finish: 'content_filter')]);
      expect((refused as AiError).type, 'refusal');
      final broke = await fails([
        {
          'error': {'message': 'The server had an error.', 'type': 'server_error'},
        },
      ]);
      expect('$broke', 'The server had an error.');
    });

    test('shows a model’s reasoning as thinking, and leaves it out of the answer', () async {
      final api = OpenAiChatApi(key: 'k', base: 'https://example.test/v1', official: false, client: FakeHttp((_) => _stream([_chunk(reasoning: 'Weighing it.'), _chunk(content: 'Yes.'), _chunk(finish: 'stop')])).call);
      final events = await _events(api.stream({'model': 'm', 'messages': const []}));
      final starts = [for (final e in events) if (e.$1 == 'content_block_start') (e.$2['content_block'] as Map)['type']];
      expect(starts, ['thinking', 'text']);
      final api2 = OpenAiChatApi(key: 'k', base: 'https://example.test/v1', official: false, client: FakeHttp((_) => _stream([_chunk(reasoning: 'Weighing it.'), _chunk(content: 'Yes.'), _chunk(finish: 'stop')])).call);
      expect(await aiText(api2.stream({'model': 'm', 'messages': const []})), 'Yes.');
    });
  });

  group('the errors', () {
    test('a refused key, no credit, too many requests, no such model and the provider’s trouble, each in words', () {
      final refused = openAiErrorOf(401, jsonEncode({'error': {'message': 'Incorrect API key provided', 'type': 'invalid_request_error', 'code': 'invalid_api_key'}}));
      expect(refused.badKey, isTrue);
      expect(refused.message, 'The API key was refused. Check it in Settings › OpenAI.');
      final quota = openAiErrorOf(429, jsonEncode({'error': {'message': 'You exceeded your current quota, please check your plan and billing details.', 'type': 'insufficient_quota', 'code': 'insufficient_quota'}}));
      expect((quota.type, quota.badKey), ('billing_error', false));
      expect(quota.message, contains('no credit'));
      final busy = openAiErrorOf(429, jsonEncode({'error': {'message': 'Rate limit reached', 'type': 'requests', 'code': 'rate_limit_exceeded'}}));
      expect(busy.type, 'rate_limit_error');
      expect(openAiErrorOf(404, jsonEncode({'error': {'message': 'The model `gpt-x` does not exist'}})).message, 'The model `gpt-x` does not exist');
      expect(openAiErrorOf(503, 'upstream').type, 'overloaded_error');
      expect(openAiErrorOf(500, '<html>').message, 'OpenAI is having trouble just now. Try again in a moment.');
      expect(openAiErrorOf(401, '{}', who: 'The endpoint', place: 'Settings › Custom AI model').message, 'The API key was refused. Check it in Settings › Custom AI model.');
    });

    test('no answer at all is the connection', () async {
      final api = OpenAiChatApi(key: 'k', client: FakeHttp((_) => throw const SocketException('no route')).call);
      await expectLater(api.stream({'model': 'm', 'messages': const []}).events.drain<void>(), throwsA(isA<AiError>().having((e) => e.message, 'message', 'OpenAI could not be reached. Check the connection.')));
      final wrong = await api.check();
      expect(wrong?.status, isNull);
      expect(wrong?.message, 'OpenAI could not be reached. Check the connection.');
    });
  });

  group('the key and the models', () {
    test('a key is checked by the models list, which is read for the chat models, the flagship first', () async {
      final http = FakeHttp((request) => FakeAnswer.json(200, {
            'object': 'list',
            'data': [
              for (final id in ['whisper-1', 'gpt-4.1', 'gpt-5-mini', 'text-embedding-3-large', 'gpt-5.5', 'gpt-5.5-2026-08-01', 'o3', 'dall-e-3', 'gpt-4o-realtime-preview', 'gpt-5']) {'id': id, 'object': 'model'},
            ],
          }));
      final api = OpenAiChatApi(key: 'sk-test-0123456789abcdef', client: http.call);
      expect(await api.check(), isNull);
      expect(http.requests.single.method, 'GET');
      expect(http.requests.single.url.toString(), 'https://api.openai.com/v1/models');
      final models = [for (final m in await api.models()) m.id];
      expect(models.first, 'gpt-5.5');
      expect(models.toSet(), {'gpt-5.5', 'gpt-5.5-2026-08-01', 'gpt-5', 'gpt-5-mini', 'gpt-4.1', 'o3'});
      final refused = await OpenAiChatApi(key: 'sk-wrong-0123456789', client: FakeHttp((_) => FakeAnswer.json(401, {'error': {'message': 'Incorrect API key'}})).call).check();
      expect(refused?.badKey, isTrue);
    });

    test('the flagship is the newest plain gpt-N, read from the list and never written here', () {
      expect(openAiFlagship(['gpt-4o', 'gpt-4.1', 'gpt-4.1-mini']), 'gpt-4.1');
      expect(openAiFlagship(['gpt-5-mini', 'gpt-5', 'gpt-6-nano']), 'gpt-5');
      expect(openAiFlagship(['gpt-5-mini']), 'gpt-5-mini');
      expect(openAiFlagship(['o3']), isNull);
    });

    test('a compatible endpoint lists every model, with OpenRouter’s prices where it gives them', () {
      final models = openAiModelsOf(
        jsonEncode({
          'data': [
            {
              'id': 'mistralai/mistral-small',
              'name': 'Mistral Small',
              'pricing': {'prompt': '0.0000002', 'completion': '0.0000006'},
            },
            {'id': 'local-model'},
          ],
        }),
        official: false,
      );
      expect([for (final m in models) (m.id, m.name)], [('mistralai/mistral-small', 'Mistral Small'), ('local-model', 'local-model')]);
      expect(models.first.rates!.input, closeTo(0.2, 1e-9));
      expect(models.first.rates!.output, closeTo(0.6, 1e-9));
      expect(models.last.rates, isNull);
    });

    test('a list kept as the settings’ choice: the first listed is the default until another is chosen', () async {
      final settings = AiProviderSettings(MemorySecureStore(), prefix: 'openai', name: 'OpenAI', fallbackModels: const [AiModelInfo('gpt-old')]);
      await settings.load();
      expect(settings.model, 'gpt-old');
      settings.setModels(const [AiModelInfo('gpt-new'), AiModelInfo('gpt-new-mini')]);
      await Future<void>.delayed(Duration.zero);
      expect(settings.chosenModel, 'gpt-new');
      await settings.setModel('gpt-new-mini');
      settings.setModels(const [AiModelInfo('gpt-newer')]);
      await Future<void>.delayed(Duration.zero);
      expect(settings.model, 'gpt-new-mini');
    });
  });

  test('the limit names the provider and its page', () async {
    final settings = AiProviderSettings(MemorySecureStore(), prefix: 'openai', name: 'OpenAI');
    await settings.load();
    await settings.spend.setOn(true);
    await settings.spend.setLimit(5);
    settings.spend.record('gpt-test', ClaudeUsage(input: 1000000, output: 1000000));
    expect(settings.spend.reached, isTrue);
    expect(settings.spend.limitMessage, 'Monthly spending limit reached (\$5). Change it in Settings › OpenAI.');
    expect(claudeLimitError(settings.spend).type, claudeLimitType);
  });
}
