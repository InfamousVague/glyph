// Which AIs a cleanup can ask (lib/plugins/cleanup/ai.dart; Matt, 2026-11-02: "use whatever AI we choose that's
// connected"): the connected ones only, Claude then the others then the device's model, Local only leaving the
// device's alone, the app's own choice first, and each ask through the provider's own client in the Messages API's
// shape, counted against its limit. The providers are the test's own: nothing is sent anywhere.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/assistant/assistant.dart';
import 'package:ghost_md/assistant/provider.dart';
import 'package:ghost_md/assistant/provider_settings.dart';
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/claude/claude_spend.dart' show ClaudeUsage;
import 'package:ghost_md/claude/messages_api.dart';
import 'package:ghost_md/plugins/cleanup/cleanup.dart';

SseEvent _e(String name, Map<String, Object?> data) => SseEvent(name, jsonEncode(data));

List<SseEvent> _said(String words) => [
      _e('message_start', {
        'message': {
          'model': 'm',
          'usage': {'input_tokens': 10},
        },
      }),
      _e('content_block_start', {
        'index': 0,
        'content_block': {'type': 'text', 'text': ''},
      }),
      _e('content_block_delta', {
        'index': 0,
        'delta': {'type': 'text_delta', 'text': words},
      }),
      _e('content_block_stop', {'index': 0}),
      _e('message_delta', {
        'delta': {'stop_reason': 'end_turn'},
        'usage': {'output_tokens': 5},
      }),
      _e('message_stop', {}),
    ];

class _Provider implements AiProvider {
  _Provider(this.words);
  final String words;
  final List<Map<String, Object?>> asked = [];

  @override
  AiCall stream(Map<String, Object?> body) {
    asked.add(body);
    return AiCall(Stream<SseEvent>.fromIterable(_said(words)), () {});
  }

  @override
  Future<AiError?> check() async => null;

  @override
  Future<List<AiModelInfo>> models() async => const [AiModelInfo('gpt-test')];
}

class _Claude extends ClaudeApi {
  _Claude() : super(key: 'sk-ant-test');
  final List<Map<String, Object?>> asked = [];

  @override
  ClaudeCall stream(Map<String, Object?> body) => streamWith(body);

  @override
  ClaudeCall streamWith(Map<String, Object?> body, {List<String> betas = const []}) {
    asked.add(body);
    return ClaudeCall(Stream<SseEvent>.fromIterable(_said('{"titles": []}')), () {});
  }
}

void main() {
  late ClaudeSettings claude;
  late AiProviderSettings openAi;
  late AssistantChoice choice;
  late _Provider provider;
  var claudeOn = true, openAiOn = true, localOnly = false;

  setUp(() async {
    claudeOn = true;
    openAiOn = true;
    localOnly = false;
    provider = _Provider('{"stale": []}');
    claude = ClaudeSettings(MemorySecureStore());
    openAi = AiProviderSettings(MemorySecureStore(), prefix: 'openai', name: 'OpenAI', fallbackModels: const [AiModelInfo('gpt-test')]);
    choice = AssistantChoice(
      store: MemorySecureStore(),
      claude: claude,
      claudeOn: () => claudeOn && !localOnly,
      claudeSwitchedOn: () => claudeOn,
      others: [AiPlugged(id: 'openai', name: 'OpenAI', settings: openAi, switchedOn: () => openAiOn, allowed: () => openAiOn && !localOnly, client: (settings) => provider)],
    );
    await choice.load();
  });

  test('only the AIs that can answer now: none without keys, then Claude and OpenAI, then the device’s model', () async {
    expect(await connectedAis(choice: choice, localOnly: false, deviceModel: () async => null), isEmpty);
    await claude.setKey('sk-ant-test-0123456789abcdef');
    await openAi.setKey('sk-test-0123456789abcdef');
    final all = await connectedAis(choice: choice, localOnly: false, deviceModel: () async => 'qwen3.5-4b');
    expect([for (final ai in all) (ai.id, ai.name, ai.local)], [('claude', 'Claude', false), ('openai', 'OpenAI', false), ('device', 'On this device', true)]);
    expect(all.last.model, 'Qwen3.5 4B');
    openAiOn = false;
    expect((await connectedAis(choice: choice, localOnly: false, deviceModel: () async => null)).map((ai) => ai.id), ['claude']);
  });

  test('Local only leaves the device’s model alone, or nothing at all', () async {
    await claude.setKey('sk-ant-test-0123456789abcdef');
    await openAi.setKey('sk-test-0123456789abcdef');
    localOnly = true;
    expect((await connectedAis(choice: choice, localOnly: true, deviceModel: () async => 'qwen3.5-2b')).map((ai) => ai.id), ['device']);
    expect(await connectedAis(choice: choice, localOnly: true, deviceModel: () async => null), isEmpty);
    // Even with a choice that says otherwise.
    final ais = await connectedAis(choice: choice, localOnly: true, deviceModel: () async => 'qwen3.5-2b');
    expect(defaultAiId(ais, choice: choice, chosen: 'claude', localOnly: true), 'device');
  });

  test('the first choice is the one chosen before, else the app’s own assistant, else the first', () async {
    await claude.setKey('sk-ant-test-0123456789abcdef');
    await openAi.setKey('sk-test-0123456789abcdef');
    final ais = await connectedAis(choice: choice, localOnly: false, deviceModel: () async => 'qwen3.5-2b');
    expect(defaultAiId(ais, choice: choice, localOnly: false), 'claude');
    await choice.setChat('openai');
    expect(defaultAiId(ais, choice: choice, localOnly: false), 'openai');
    expect(defaultAiId(ais, choice: choice, chosen: 'device', localOnly: false), 'device');
    expect(defaultAiId(ais, choice: choice, chosen: 'gone', localOnly: false), 'openai');
    expect(defaultAiId(const [], localOnly: false), isNull);
  });

  test('each ask goes through the provider’s own client in the Messages API’s shape, read whole', () async {
    await claude.setKey('sk-ant-test-0123456789abcdef');
    await openAi.setKey('sk-test-0123456789abcdef');
    final api = _Claude();
    final ais = await connectedAis(choice: choice, localOnly: false, deviceModel: () async => null, claudeApi: (_) => api);
    expect(await ais.first.ask('system words', 'the notes', maxTokens: 4000).done, '{"titles": []}');
    expect(api.asked.single['system'], 'system words');
    expect(api.asked.single['max_tokens'], 4000);
    expect((api.asked.single['messages']! as List).single, {'role': 'user', 'content': 'the notes'});
    expect(await ais.last.ask('s', 'p', maxTokens: 10).done, '{"stale": []}');
    expect(provider.asked.single['model'], 'gpt-test');
  });

  test('a spending limit reached is an error before anything is sent', () async {
    await openAi.setKey('sk-test-0123456789abcdef');
    await openAi.spend.setOn(true);
    await openAi.spend.setLimit(0.01);
    openAi.spend.record('gpt-test', ClaudeUsage(input: 1000000, output: 1000000));
    expect(openAi.spend.reached, isTrue);
    final ais = await connectedAis(choice: choice, localOnly: false, deviceModel: () async => null);
    await expectLater(ais.single.ask('s', 'p', maxTokens: 10).done, throwsA(isA<Exception>()));
    expect(provider.asked, isEmpty);
  });
}
