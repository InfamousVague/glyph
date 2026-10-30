// The seam and the assistant choice (lib/assistant/; docs/AI_PROVIDERS.md; Matt, 2026-10-29: "Add support for aster 6
// and other Ai models as plugins in addition to claude like openAI google gemini etc"). Claude's client is the seam's
// provider by its old names, and is asked exactly as before where Claude answers; Settings › AI › Assistant routes the
// chat and the meetings' write-ups to another provider where it says, or where Claude cannot answer, and to the device
// for meetings; a conversation is one provider's. Every provider here is the test's own: nothing reaches a network.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/ai/summary_claude.dart';
import 'package:ghost_md/assistant/assistant.dart';
import 'package:ghost_md/assistant/provider.dart';
import 'package:ghost_md/assistant/provider_settings.dart';
import 'package:ghost_md/claude/claude_run.dart';
import 'package:ghost_md/claude/claude_runner.dart';
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/claude/claude_spend.dart' show ClaudeUsage;
import 'package:ghost_md/claude/messages_api.dart';

import 'fake_http.dart';
import 'support.dart';

SseEvent _e(String name, Map<String, Object?> data) => SseEvent(name, jsonEncode(data));

/// A reply of [words], in the Messages API's events.
List<SseEvent> _said(String words, {String model = 'other-model', int input = 10, int output = 5}) => [
      _e('message_start', {
        'message': {
          'model': model,
          'usage': {'input_tokens': input},
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
        'usage': {'output_tokens': output},
      }),
      _e('message_stop', {}),
    ];

/// Another provider, the test's own: what it was asked, and [words] for each answer.
class _Provider implements AiProvider {
  _Provider(this.words);
  final String words;
  final List<Map<String, Object?>> asked = [];

  @override
  AiCall stream(Map<String, Object?> body) {
    asked.add(jsonDecode(jsonEncode(body)) as Map<String, Object?>);
    return AiCall(Stream<SseEvent>.fromIterable(_said(words)), () {});
  }

  @override
  Future<AiError?> check() async => null;

  @override
  Future<List<AiModelInfo>> models() async => const [AiModelInfo('other-model')];
}

/// Claude, the test's own, as claude_run_test's is.
class _Claude extends ClaudeApi {
  _Claude() : super(key: 'sk-ant-test');
  final List<Map<String, Object?>> asked = [];

  @override
  ClaudeCall stream(Map<String, Object?> body) => streamWith(body);

  @override
  ClaudeCall streamWith(Map<String, Object?> body, {List<String> betas = const []}) {
    asked.add(jsonDecode(jsonEncode(body)) as Map<String, Object?>);
    return ClaudeCall(Stream<SseEvent>.fromIterable(_said('Claude here.', model: body['model'] as String)), () {});
  }
}

class _World {
  _World() {
    claude = ClaudeSettings(MemorySecureStore());
    openAi = AiProviderSettings(MemorySecureStore(), prefix: 'openai', name: 'OpenAI', fallbackModels: const [AiModelInfo('gpt-fallback')]);
    custom = AiProviderSettings(MemorySecureStore(), prefix: 'custom-ai', name: 'Custom AI model', needsBase: true, keyOptional: true);
    choice = AssistantChoice(
      store: MemorySecureStore(),
      claude: claude,
      claudeOn: () => claudeOn && !localOnly,
      claudeSwitchedOn: () => claudeOn,
      others: [
        AiPlugged(id: 'openai', name: 'OpenAI', settings: openAi, switchedOn: () => openAiOn, allowed: () => openAiOn && !localOnly, client: (settings, {key}) => openAiProvider),
        AiPlugged(id: 'custom-ai', name: 'Custom AI model', settings: custom, switchedOn: () => customOn, allowed: () => customOn && !localOnly, client: (settings, {key}) => customProvider),
      ],
    );
  }

  late final ClaudeSettings claude;
  late final AiProviderSettings openAi;
  late final AiProviderSettings custom;
  late final AssistantChoice choice;
  bool claudeOn = true;
  bool openAiOn = true;
  bool customOn = true;
  bool localOnly = false;
  final _Provider openAiProvider = _Provider('OpenAI here.');
  final _Provider customProvider = _Provider('Custom here.');
  final _Claude claudeApi = _Claude();

  Future<void> load() => choice.load();
}

void main() {
  group('the seam', () {
    test('Claude’s client is the seam’s provider, by the names Claude’s code has always used', () async {
      final api = ClaudeApi(key: 'sk-ant-test');
      expect(api, isA<AiProvider>());
      const refused = ClaudeError('No.', status: 401);
      expect(refused, isA<AiError>());
      expect(refused.badKey, isTrue);
      expect(const ClaudeCancelled(), isA<AiCancelled>());
      // Its models, read for the seam, with their display names.
      final http = FakeHttp((_) => FakeAnswer.json(200, {
            'data': [
              {'id': 'claude-sonnet-5-5', 'display_name': 'Claude Sonnet 5.5'},
            ],
          }));
      final models = await ClaudeApi(key: 'sk-ant-test', client: http.call).models();
      expect([for (final m in models) (m.id, m.name)], [('claude-sonnet-5-5', 'Claude Sonnet 5.5')]);
      expect(http.requests.single.headers['x-api-key'], 'sk-ant-test');
    });

    test('one completion is read whole from any provider, in its name’s words', () async {
      expect(await aiText(_Provider('Summary.').stream(const {})), 'Summary.');
      final empty = AiCall(Stream<SseEvent>.fromIterable([_e('message_delta', {'delta': {'stop_reason': 'end_turn'}})]), () {});
      await expectLater(aiText(empty, who: 'Gemini'), throwsA(isA<AiError>().having((e) => e.message, 'message', 'Gemini answered with nothing.')));
    });

    test('the run sends no tools where it is told the model has none, and says a provider’s notice as a step', () async {
      final notes = MemoryNotes();
      final provider = _Provider('Hi.');
      await ClaudeRun(api: provider, model: 'm', notes: notes, desk: BlindDesk(notes), prompt: 'x', tools: false).run();
      expect(provider.asked.single.containsKey('tools'), isFalse);
      final told = AiCall(Stream<SseEvent>.fromIterable([SseEvent(aiNoticeEvent, jsonEncode({'words': 'No tools here.'})), ..._said('Hi.')]), () {});
      final run = ClaudeRun(api: _Once(told), model: 'm', notes: notes, desk: BlindDesk(notes), prompt: 'x');
      await run.run();
      expect([for (final s in run.steps) (s.kind, s.words)], [('asked', 'x'), ('notice', 'No tools here.'), ('said', 'Hi.')]);
    });
  });

  group('who answers the chat', () {
    test('Automatic is Claude where it can answer, else the first other provider set up, else nobody', () async {
      final world = _World();
      await world.load();
      expect(world.choice.chatBy, isNull);
      await world.custom.setBaseUrl('http://localhost:1234/v1');
      await world.custom.setModel('local-model');
      expect(world.choice.chatBy, 'custom-ai');
      await world.openAi.setKey('sk-test-0123456789abcdef');
      expect(world.choice.chatBy, 'openai', reason: 'in the Market’s order');
      expect(world.choice.chatRoute?.model, 'gpt-fallback');
      await world.claude.setKey('sk-ant-test-0123456789abcdef');
      expect(world.choice.chatBy, claudeAssistantId);
      expect(world.choice.chatRoute, isNull, reason: 'Claude’s own path');
      // Chosen by name, and standing aside while it cannot answer.
      await world.choice.setChat('custom-ai');
      expect(world.choice.chatBy, 'custom-ai');
      world.customOn = false;
      expect(world.choice.chatBy, claudeAssistantId);
      // Local only holds every one off.
      world.localOnly = true;
      expect(world.choice.chatBy, isNull);
    });

    test('meetings: Claude where it may write them, else another allowed to, else the device; Local only does not unchoose them', () async {
      final world = _World();
      await world.load();
      await world.openAi.setKey('sk-test-0123456789abcdef');
      expect(world.choice.meetingsBy, 'openai');
      await world.openAi.setMeetings(false);
      expect(world.choice.meetingsBy, isNull);
      await world.openAi.setMeetings(true);
      await world.claude.setKey('sk-ant-test-0123456789abcdef');
      expect(world.choice.meetingsBy, claudeAssistantId);
      await world.claude.setMeetings(false);
      expect(world.choice.meetingsBy, 'openai');
      await world.choice.setMeetings(assistantDevice);
      expect(world.choice.meetingsBy, isNull);
      await world.choice.setMeetings('openai');
      world.localOnly = true;
      expect(world.choice.meetingsBy, 'openai', reason: 'held by Local only, never moved to the device for it');
    });

    test('the runner asks the provider the choice names, with its model, its limit and a prompt that does not call it Claude', () async {
      final world = _World();
      await world.load();
      await world.openAi.setKey('sk-test-0123456789abcdef');
      await world.openAi.setModel('gpt-chosen');
      final notes = MemoryNotes();
      final runner = ClaudeRunner(settings: world.claude, notes: notes, desk: BlindDesk(notes), api: (_) => world.claudeApi, route: () => world.choice.chatRoute, routeChanges: world.choice, loadRoute: world.choice.load);
      expect((runner.ready, runner.speaker, runner.claudeAnswers, runner.model), (true, 'OpenAI', false, 'gpt-chosen'));
      final run = await runner.ask('hello');
      await ClaudeRunner.over(run);
      expect(run.answer, 'OpenAI here.');
      final asked = world.openAiProvider.asked.single;
      expect(asked['model'], 'gpt-chosen');
      expect(asked['system'] as String, startsWith('You are an AI assistant, working inside Ghost.md'));
      expect(asked.containsKey('thinking'), isFalse, reason: 'only Claude’s models are asked for their thinking');
      expect(world.openAi.spend.requests, 1);
      expect(world.claude.spend.requests, 0);
      expect(world.claudeApi.asked, isEmpty);

      // A follow-up is the same conversation; Claude set up and chosen, the next ask is Claude's, afresh.
      await ClaudeRunner.over(await runner.ask('and again'));
      expect((world.openAiProvider.asked.last['messages'] as List).length, 3);
      await world.claude.setKey('sk-ant-test-0123456789abcdef');
      await world.choice.setChat(claudeAssistantId);
      expect((runner.speaker, runner.claudeAnswers), ('Claude', true));
      final claudeRun = await runner.ask('now you');
      await ClaudeRunner.over(claudeRun);
      expect(claudeRun.answer, 'Claude here.');
      final claudeAsked = world.claudeApi.asked.single;
      expect((claudeAsked['messages'] as List).length, 1, reason: 'OpenAI’s turns are not Claude’s');
      expect(claudeAsked['system'] as String, startsWith('You are Claude, working inside Ghost.md'));
      expect(claudeAsked['model'], defaultClaudeModel);
    });

    test('with no route given, every ask is Claude’s, as it always was', () async {
      final world = _World();
      await world.load();
      await world.openAi.setKey('sk-test-0123456789abcdef');
      final notes = MemoryNotes();
      final runner = ClaudeRunner(settings: world.claude, notes: notes, desk: BlindDesk(notes), api: (_) => world.claudeApi);
      expect(runner.ready, isFalse);
      await expectLater(runner.ask('x'), throwsA(isA<ClaudeError>().having((e) => e.message, 'message', 'Add your Anthropic API key in Settings › Claude.')));
      expect(world.openAiProvider.asked, isEmpty);
    });

    test('a provider whose plugin is off, or whose limit is reached, is not asked', () async {
      final world = _World();
      await world.load();
      await world.openAi.setKey('sk-test-0123456789abcdef');
      await world.choice.setChat('openai');
      final notes = MemoryNotes();
      final route = world.choice.chatRoute!;
      final runner = ClaudeRunner(settings: world.claude, notes: notes, desk: BlindDesk(notes), route: () => route);
      world.openAiOn = false;
      await expectLater(runner.ask('x'), throwsA(isA<ClaudeError>().having((e) => e.message, 'message', 'OpenAI is switched off on this device. Add it in the Market.')));
      world.openAiOn = true;
      await world.openAi.spend.setOn(true);
      await world.openAi.spend.setLimit(1);
      world.openAi.spend.record('gpt', ClaudeUsage(input: 100000000, output: 100000000));
      await expectLater(runner.ask('x'), throwsA(isA<ClaudeError>().having((e) => e.message, 'message', contains('Settings › OpenAI'))));
      expect(world.openAiProvider.asked, isEmpty);
    });
  });

  group('who writes meetings up', () {
    MeetingClaude meetings(_World world) => MeetingClaude(settings: world.claude, switchedOn: () => world.claudeOn, localOnly: () => world.localOnly, api: (_) => world.claudeApi, choice: world.choice);

    test('another provider writes them where the choice says, through its own client and meter', () async {
      final world = _World();
      await world.load();
      await world.openAi.setKey('sk-test-0123456789abcdef');
      await world.openAi.setModel('gpt-writer');
      final writer = meetings(world);
      await writer.load();
      expect((writer.chosen, writer.enabled, writer.name, writer.model), (true, true, 'OpenAI', 'gpt-writer'));
      // The summary's job wears the provider's mark (lib/activity/job_mark.dart).
      expect(writer.pluginId, 'openai');
      expect(writer.onePassChars, otherOnePassChars);
      final text = await writer.write(system: 'Summarize.', prompt: 'The transcript').done;
      expect(text, 'OpenAI here.');
      final asked = world.openAiProvider.asked.single;
      expect(asked['system'], 'Summarize.');
      expect(asked['messages'], [
        {'role': 'user', 'content': 'The transcript'},
      ]);
      expect(world.openAi.spend.requests, 1);
      // Local only holds it, as it holds Claude.
      world.localOnly = true;
      expect((writer.chosen, writer.held, writer.enabled), (true, true, false));
    });

    test('Claude writes them as before where it may, and the device where the choice says so', () async {
      final world = _World();
      await world.load();
      await world.claude.setKey('sk-ant-test-0123456789abcdef');
      await world.openAi.setKey('sk-test-0123456789abcdef');
      final writer = meetings(world);
      expect((writer.chosen, writer.name, writer.model, writer.pluginId), (true, 'Claude', defaultClaudeModel, 'claude'));
      expect(writer.onePassChars, claudeOnePassChars);
      expect(await writer.write(system: 's', prompt: 'p').done, 'Claude here.');
      expect(world.claudeApi.asked.single['model'], defaultClaudeModel);
      expect(world.openAiProvider.asked, isEmpty);
      await world.choice.setMeetings(assistantDevice);
      expect(writer.chosen, isFalse);
    });

    test('with no choice given, meetings are Claude’s or the device’s, as they were', () async {
      final world = _World();
      await world.load();
      await world.openAi.setKey('sk-test-0123456789abcdef');
      final writer = MeetingClaude(settings: world.claude, switchedOn: () => true, localOnly: () => false, api: (_) => world.claudeApi);
      expect(writer.chosen, isFalse);
      await world.claude.setKey('sk-ant-test-0123456789abcdef');
      expect(writer.chosen, isTrue);
    });
  });
}

/// A provider that answers once with [call].
class _Once implements AiStreamer {
  _Once(this.call);
  final AiCall call;

  @override
  AiCall stream(Map<String, Object?> body) => call;
}
