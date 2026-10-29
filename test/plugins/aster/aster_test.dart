// The Aster plugin (lib/plugins/aster/aster.dart; docs/AI_PROVIDERS.md, "Aster"; Matt, 2026-10-29: "aster 6 is
// OpenAI-compatible, add it as a plugin"): OpenAI's client at Aster's address with the key as a Bearer header, the
// check by the models list and, where Aster has none, by one token of a chat; the spending meter at Aster's published
// prices, matched by the model's id; the setup's steps, words and links; a model's id typed at the end; and what it
// says of where the words go. Over a fake HttpClient and the test's own settings: nothing reaches the network.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/assistant/provider.dart';
import 'package:ghost_md/assistant/provider_pane.dart';
import 'package:ghost_md/assistant/provider_settings.dart';
import 'package:ghost_md/assistant/provider_setup.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/aster/aster.dart';
import 'package:ghost_md/plugins/onboarding/setup_card.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';
import 'package:ghost_md/plugins/onboarding/setup_sheet.dart';
import 'package:ghost_md/plugins/onboarding/setup_voice.dart';
import 'package:ghost_md/plugins/openai/chat_api.dart';
import 'package:ghost_md/plugins/reach.dart' show usesLine;

import '../../assistant/fake_http.dart';
import '../../settings/support.dart';
import '../ai_providers/support.dart';

/// One token of a chat, as Chat Completions streams it.
FakeAnswer _oneToken() => FakeAnswer.sse([
      sseData({
        'model': 'gpt-oss-120b-fast',
        'choices': [
          {
            'index': 0,
            'delta': {'content': 'Hi'},
            'finish_reason': 'length',
          },
        ],
      }),
      'data: [DONE]\n\n',
    ]);

/// Aster's client over [http], with [model] chosen.
AiProvider _client(FakeHttp http, {String model = 'gpt-oss-120b-fast'}) {
  final settings = AiProviderSettings(MemorySecureStore(), prefix: 'aster', name: 'Aster', fallbackModels: asterFallbackModels, ratesFor: asterRatesFor);
  return AsterApi(OpenAiChatApi(key: 'aster-key-0123', base: asterBase, official: false, who: 'Aster', place: 'Settings › Aster', settings: settings, client: http.call), model: model);
}

void main() {
  setUpAll(loadAppFonts);

  group('the client', () {
    test('is OpenAI’s at api.asterlab.ai/v1, the key a Bearer header, with max_tokens and every model as listed', () async {
      final http = FakeHttp((request) => request.method == 'GET'
          ? FakeAnswer.json(200, {
              'data': [
                {'id': 'gpt-oss-120b-fast'},
                {'id': 'moonshotai/kimi-k3', 'name': 'Kimi K3'},
              ],
            })
          : _oneToken());
      final api = _client(http);
      expect(await api.check(), isNull);
      expect(http.requests.single.url.toString(), 'https://api.asterlab.ai/v1/models');
      expect(http.requests.single.headers['authorization'], 'Bearer aster-key-0123');
      expect([for (final m in await api.models()) (m.id, m.name)], [('gpt-oss-120b-fast', 'gpt-oss-120b-fast'), ('moonshotai/kimi-k3', 'Kimi K3')]);
      await api.stream({
        'model': 'gpt-oss-120b-fast',
        'max_tokens': 64,
        'messages': const [
          {'role': 'user', 'content': 'Hello'},
        ],
      }).events.drain<void>();
      final chat = http.requests.last;
      expect(chat.url.toString(), 'https://api.asterlab.ai/v1/chat/completions');
      expect((chat.json['max_tokens'], chat.json.containsKey('max_completion_tokens')), (64, false));
    });

    test('with no list of models, the key is checked by one token of a chat with the chosen model', () async {
      final http = FakeHttp((request) => request.method == 'GET' ? FakeAnswer(404, ['Not Found']) : _oneToken());
      expect(await _client(http, model: 'glm-5.2').check(), isNull);
      expect([for (final r in http.requests) '${r.method} ${r.url.path}'], ['GET /v1/models', 'POST /v1/chat/completions']);
      final asked = http.requests.last.json;
      expect((asked['model'], asked['max_tokens'], asked.containsKey('tools')), ('glm-5.2', 1, false));
      expect(http.requests.last.headers['authorization'], 'Bearer aster-key-0123');
    });

    test('a key refused by the list is refused, with no chat; one refused by the fallback’s chat is refused too', () async {
      final listed = FakeHttp((_) => FakeAnswer.json(401, {'error': {'message': 'Invalid key'}}));
      final refused = await _client(listed).check();
      expect((refused?.badKey, refused?.message), (true, 'The API key was refused. Check it in Settings › Aster.'));
      expect(listed.requests, hasLength(1));
      final chatted = FakeHttp((request) => request.method == 'GET' ? FakeAnswer(404, ['Not Found']) : FakeAnswer.json(401, {'error': {'message': 'Invalid key'}}));
      expect((await _client(chatted).check())?.badKey, isTrue);
      final noModel = FakeHttp((request) => request.method == 'GET' ? FakeAnswer(404, ['Not Found']) : FakeAnswer.json(404, {'error': {'message': 'The model nope does not exist'}}));
      expect((await _client(noModel, model: 'nope').check())?.message, 'The model nope does not exist');
    });
  });

  group('the prices', () {
    test('are Aster’s three, matched by id: gpt-oss-120b-fast exactly, any kimi as Kimi K3, any glm as GLM 5.2', () {
      expect(asterRatesFor('gpt-oss-120b-fast'), const AiRates(input: 0.30, output: 1.20));
      expect(asterRatesFor('moonshotai/Kimi-K3'), const AiRates(input: 2.50, output: 12.50));
      expect(asterRatesFor('zai-org/glm-5.2-fp8'), const AiRates(input: 1.00, output: 4.00));
      expect(asterRatesFor('gpt-oss-120b'), isNull, reason: 'exact for the one id the site shows');
      expect(asterRatesFor('llama-4'), isNull);
    });

    test('the meter counts at the model’s, then the person’s; a model it doesn’t know at the high guess', () async {
      final settings = AiProviderSettings(MemorySecureStore(), prefix: 'aster', name: 'Aster', fallbackModels: asterFallbackModels, ratesFor: asterRatesFor);
      await settings.load();
      expect((settings.model, settings.rates, settings.ratesKnown), ('gpt-oss-120b-fast', asterGptOssRates, true));
      await settings.setModel('kimi-k3');
      expect(settings.rates, asterKimiRates);
      await settings.setModel('someone-else-7b');
      expect((settings.rates, settings.ratesKnown), (aiCautiousRates, false));
      await settings.setRates(const AiRates(input: 1, output: 2));
      expect((settings.rates, settings.ratesChosen, settings.ratesKnown), (const AiRates(input: 1, output: 2), true, false));
      // A million in and a million out of GLM 5.2, at its own prices.
      await settings.setRates(null);
      await settings.setModel('glm-5.2');
      expect(aiCost(settings.rates, input: 1000000, output: 1000000), closeTo(5.0, 1e-9));
    });
  });

  group('the setup', () {
    test('intro, account, key, paste, check and settings, the console’s links unverified, every step’s words a clip', () {
      final setup = asterSetup();
      expect([for (final step in setup.steps) step.id], ['intro', 'account', 'key', 'paste', 'check', 'done']);
      expect([for (final step in setup.steps.whereType<SetupOpen>()) for (final link in step.links) (link.url, link.verified)], [
        ('https://www.asterlab.ai/inference/console', false),
        ('https://www.asterlab.ai/pricing', false),
        ('https://www.asterlab.ai/inference/console', false),
      ]);
      expect([for (final f in setup.steps.whereType<SetupPaste>().single.fields) (f.id, f.optional)], [('key', false)], reason: 'Aster’s address is set');
      for (final step in setup.steps) {
        expect(setupVoice.containsKey('aster-${step.id}'), isTrue, reason: step.id);
        for (final simple in [false, true]) {
          expect(setup.wordsOf(step, simple: simple), isNotEmpty, reason: step.id);
        }
      }
      expect(asterKeyShape('ak_live_0123456789'), isNull);
      expect(asterKeyShape('two words'), 'Paste the key alone: it has no spaces in it.');
    });

    test('a key that works: Aster is ready, its list read for the last step', () async {
      final test = ProviderTest(asterPage);
      await test.settings.setKey('aster-key-0123');
      final result = await test.setup().steps.whereType<SetupCheck>().single.run();
      expect((result.kind, result.words), (SetupCheckKind.ok, 'Your key works. Aster is ready.'));
      expect(test.settings.listed.map((m) => m.id), ['model-one', 'model-two']);
    });

    testWidgets('its settings at the end: the fallback said to be possibly out of date, and a model’s id typed', (tester) async {
      final test = ProviderTest(asterPage)..listed = const [];
      await test.settings.setKey('aster-key-0123');
      final memory = SetupMemory(MemoryStored())..at('aster', 'done');
      await pumpSettings(tester, PluginSetupSheet(setup: test.setup(), memory: memory, onClose: () {}));
      await settleSettings(tester);
      expect(find.text('gpt-oss-120b-fast unless you choose another. This list may be out of date: Aster’s own couldn’t be read.'), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byType(ProviderSetupChoices), matching: find.byType(EditableText)), 'kimi-k3');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('aster-setup-model-typed')));
      await tester.tap(find.byKey(const ValueKey('aster-setup-model-typed')));
      await settleSettings(tester);
      expect((test.settings.model, test.settings.ready), ('kimi-k3', true));
      await endSettings(tester);
    });
  });

  testWidgets('its page: Set up at its head, where the words go, a model’s id typed, and Aster’s prices said as its', (tester) async {
    final test = ProviderTest(asterPage);
    await test.settings.load();
    await pumpSettings(tester, SingleChildScrollView(child: ProviderPane(page: test.page, setup: PluginSetupCard(setup: test.setup()))), size: const Size(390, 4000));
    expect(find.text('Set up Aster'), findsOneWidget);
    expect(find.text(test.page.sends), findsOneWidget);
    expect(find.byKey(const ValueKey('provider-model-typed')), findsOneWidget);
    expect(find.textContaining('Aster’s published prices for gpt-oss-120b-fast'), findsOneWidget);
    await endSettings(tester);
  });

  test('says plainly that what you ask and your notes go to Aster under your key, and is off until added', () {
    final manifest = asterPlugin.manifest;
    expect((manifest.id, manifest.name, manifest.standard), ('aster', 'Aster', false));
    expect(manifest.description, contains('the text of the notes it reads go to Aster under your key, and nowhere else'));
    expect(manifest.permissions.last.why, contains('go from this device to Aster with your key'));
    expect(manifest.hosts, ['api.asterlab.ai']);
    expect(usesLine(manifest), 'Uses your notes and the internet');
    expect(asterPage.sends, 'What you ask, and the notes it reads to answer, go from this device to Aster under your own key, and Aster bills the key. With meeting summaries on, a meeting’s transcript goes there too. Nothing goes through Ghost.md’s server.');
  });
}
