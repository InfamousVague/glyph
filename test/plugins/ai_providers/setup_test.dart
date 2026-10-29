// The other AI providers' plugins: their setups, their pages and their Market cards (lib/assistant/provider_setup.dart,
// provider_pane.dart; lib/plugins/openai/, gemini/, custom_ai/; docs/AI_PROVIDERS.md; Matt, 2026-10-29: "Add support
// for aster 6 and other Ai models as plugins in addition to claude like openAI google gemini etc"). The steps and their
// words, said aloud as every plugin's are (Matt, 2026-10-29: "add the voiceover onboarding for the rest of the
// plugins"; the clips are setup_voice_test.dart's), the key's shape, the key kept where the page keeps it, the check in plain words and the
// models it reads, the custom endpoint's address and its optional key, the settings at the end; the page's key, model,
// tools, meetings and limit; and each plugin's privacy words. Every provider is the test's own: nothing is asked of a
// network.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;
import 'package:ghost_md/assistant/provider.dart';
import 'package:ghost_md/assistant/provider_page.dart';
import 'package:ghost_md/assistant/provider_pane.dart';
import 'package:ghost_md/assistant/provider_settings.dart';
import 'package:ghost_md/assistant/provider_setup.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/aster/aster.dart';
import 'package:ghost_md/plugins/custom_ai/custom_ai.dart';
import 'package:ghost_md/plugins/gemini/gemini.dart';
import 'package:ghost_md/plugins/onboarding/setup_card.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';
import 'package:ghost_md/plugins/onboarding/setup_sheet.dart';
import 'package:ghost_md/plugins/onboarding/setup_voice.dart';
import 'package:ghost_md/plugins/openai/openai.dart';
import 'package:ghost_md/plugins/reach.dart' show usesLine;
import 'package:ghost_md/settings/kit/settings_kit.dart' show Pick;

import '../../settings/support.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  group('the steps', () {
    test('OpenAI and Gemini: an account, a key, the check and the settings; the custom endpoint: its address and the rest', () {
      List<String> ids(PluginSetup setup) => [for (final step in setup.steps) step.id];
      expect(ids(openAiSetup()), ['intro', 'account', 'key', 'paste', 'check', 'done']);
      expect(ids(geminiSetup()), ['intro', 'account', 'key', 'paste', 'check', 'done']);
      expect(ids(customAiSetup()), ['intro', 'paste', 'check', 'done']);
      final links = [for (final step in openAiSetup().steps.whereType<SetupOpen>()) for (final link in step.links) (link.label, link.url, link.verified)];
      expect(links, [
        ('Open the OpenAI platform', 'https://platform.openai.com/', false),
        ('Billing', 'https://platform.openai.com/settings/organization/billing/overview', false),
        ('Open API keys', 'https://platform.openai.com/api-keys', false),
      ]);
      expect([for (final step in geminiSetup().steps.whereType<SetupOpen>()) for (final link in step.links) link.url], ['https://aistudio.google.com/', 'https://aistudio.google.com/apikey']);
      for (final plugin in [openAiPlugin, geminiPlugin, customAiPlugin]) {
        expect(plugin.setup, isNotNull, reason: plugin.manifest.id);
      }
    });

    test('every step has its words, and they are said: each is a clip of the voice', () {
      for (final setup in [openAiSetup(), geminiSetup(), customAiSetup()]) {
        for (final step in setup.steps) {
          for (final simple in [false, true]) {
            expect(setup.wordsOf(step, simple: simple), isNotEmpty, reason: '${setup.id}-${step.id}');
          }
          expect(setupVoice.containsKey('${setup.id}-${step.id}'), isTrue, reason: '${setup.id}-${step.id}');
        }
      }
    });

    test('checks a key’s shape before it is kept', () {
      expect(openAiKeyShape('sk-proj-abcdefghijklmnopqrstuvwxyz'), isNull);
      expect(openAiKeyShape('sk-ant-api03-abcdefghijklmnopqrstuvwxyz'), isNull, reason: 'sk-, as OpenAI’s are; the check says the rest');
      expect(openAiKeyShape('AIzaSyabcdefghijklmnopqrstuvwxyz'), 'That doesn’t look like an OpenAI API key. Those start with sk-.');
      expect(openAiKeyShape('sk-abc'), 'That key looks cut short. Copy all of it.');
      expect(geminiKeyShape('AIzaSyA-abcdefghijklmnopqrstuvwxyz012'), isNull);
      expect(geminiKeyShape('AIza short'), 'Paste the key alone: it has no spaces in it.');
      expect(customAiKeyShape(''), isNull);
      expect(endpointShape('openrouter.ai/api/v1'), isNull);
      expect(endpointShape('not an address'), isNotNull);
      expect(aiBaseUrl('localhost:11434/v1/'), 'http://localhost:11434/v1');
      expect(aiBaseUrl(' https://api.mistral.ai/v1 '), 'https://api.mistral.ai/v1');
    });

    test('keeps the key where the page keeps it, and is needed until it is; the custom endpoint with its address and no key', () async {
      final openAi = ProviderTest(openAiPage);
      final made = openAi.setup();
      expect(made.ready(), isFalse);
      expect(await made.steps.whereType<SetupPaste>().single.save({'key': 'sk-proj-abcdefghijklmnopqrstuvwxyz'}), isNull);
      expect(await openAi.settings.store.read('openai-api-key'), 'sk-proj-abcdefghijklmnopqrstuvwxyz');
      expect(made.ready(), isTrue, reason: 'the fallback model stands in until the list is read');

      final custom = ProviderTest(customAiPage);
      final paste = custom.setup().steps.whereType<SetupPaste>().single;
      expect([for (final f in paste.fields) (f.id, f.optional)], [('base', false), ('key', true)]);
      await paste.save({'base': 'localhost:1234/v1', 'key': ''});
      expect((custom.settings.baseUrl, custom.settings.hasKey, custom.settings.ready), ('http://localhost:1234/v1', false, false));
      custom.settings.setModels(const [AiModelInfo('qwen-local')]);
      await Future<void>.delayed(Duration.zero);
      expect(custom.settings.ready, isTrue);
      expect(await custom.settings.store.read('custom-ai-model'), 'qwen-local', reason: 'the listed default kept, so it holds once the app starts again');
    });
  });

  group('the check', () {
    Future<(ProviderTest, SetupResult)> check(AiProviderPage page, {AiError? answer}) async {
      final test = ProviderTest(page)..answer = answer;
      await test.settings.setKey(page.custom ? null : 'sk-proj-abcdefghijklmnopqrstuvwxyz');
      if (page.custom) await test.settings.setBaseUrl('https://openrouter.ai/api/v1');
      return (test, await test.setup().steps.whereType<SetupCheck>().single.run());
    }

    test('a key that works reads the models for the last step, the provider’s first the default', () async {
      final (test, result) = await check(openAiPage);
      expect((result.kind, result.words), (SetupCheckKind.ok, 'Your key works. OpenAI is ready.'));
      expect(test.settings.listed.map((m) => m.id), ['model-one', 'model-two']);
      await Future<void>.delayed(Duration.zero);
      expect(test.settings.chosenModel, 'model-one');
    });

    test('a refused key is let go of; no credit warns with Billing; a quota warns; no connection is the connection', () async {
      final (refused, said) = await check(openAiPage, answer: openAiErrorOf(401, '{}'));
      expect((said.kind, said.pasteAgain), (SetupCheckKind.failed, true));
      expect(said.words, 'That key isn’t right. Copy it again from Open API keys: all of it.');
      expect(refused.settings.hasKey, isFalse);
      final (_, credit) = await check(openAiPage, answer: openAiErrorOf(429, '{"error":{"code":"insufficient_quota","message":"You exceeded your current quota"}}'));
      expect((credit.kind, credit.link?.url), (SetupCheckKind.warn, 'https://platform.openai.com/settings/organization/billing/overview'));
      final (_, google) = await check(geminiPage, answer: geminiErrorOf(400, '{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}'));
      expect(google.pasteAgain, isTrue);
      final (_, quota) = await check(geminiPage, answer: geminiErrorOf(429, '{"error":{"code":429,"message":"Quota exceeded","status":"RESOURCE_EXHAUSTED"}}'));
      expect(quota.kind, SetupCheckKind.warn);
      final (_, away) = await check(geminiPage, answer: const AiError('Gemini could not be reached. Check the connection.'));
      expect(away.words, 'Gemini couldn’t be reached. Check the connection, then check again.');
    });

    test('the custom endpoint: answered, or with no list of models, which is fine', () async {
      final (_, ok) = await check(customAiPage);
      expect(ok.words, 'The endpoint answers. model-one is ready.');
      final (_, none) = await check(customAiPage, answer: openAiErrorOf(404, 'Not Found', who: 'The endpoint'));
      expect(none.kind, SetupCheckKind.warn);
      expect(none.words, contains('type the model’s name next'));
    });
  });

  group('drawn', () {
    Finder field(String id) => find.descendant(of: find.byKey(ValueKey('setup-field-$id')), matching: find.byType(EditableText));

    testWidgets('OpenAI’s key is pasted, checked and set up, and its two settings are at the end', (tester) async {
      final test = ProviderTest(openAiPage);
      final memory = SetupMemory(MemoryStored())..at('openai', 'paste');
      await pumpSettings(tester, PluginSetupSheet(setup: test.setup(), memory: memory, onClose: () {}));
      expect(find.text('Paste your key'), findsOneWidget);
      await tester.enterText(field('key'), 'AIza-not-openai-abcdefghijklmnop');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('setup-next')));
      await settleSettings(tester);
      expect(find.text('That doesn’t look like an OpenAI API key. Those start with sk-.'), findsOneWidget);
      await tester.enterText(field('key'), 'sk-proj-abcdefghijklmnopqrstuvwxyz');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('setup-next')));
      await settleSettings(tester);
      expect(test.settings.key, 'sk-proj-abcdefghijklmnopqrstuvwxyz');
      expect(find.text('Your key works. OpenAI is ready.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('setup-next')));
      await settleSettings(tester);
      expect(find.text('Your settings'), findsOneWidget);
      expect(find.text('Model One unless you choose another: the first OpenAI lists for your key.'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('openai-setup-meetings')), matching: find.byType(GlacierSwitch)));
      await settleSettings(tester);
      expect(test.settings.meetings, isFalse);
      await tester.ensureVisible(find.byKey(const ValueKey('openai-setup-model:model-two')));
      await settleSettings(tester);
      await tester.tap(find.byKey(const ValueKey('openai-setup-model:model-two')));
      await settleSettings(tester);
      expect(test.settings.model, 'model-two');
      await endSettings(tester);
    });

    testWidgets('the custom endpoint takes its address with no key, and its model typed', (tester) async {
      final test = ProviderTest(customAiPage)..listed = const [];
      final memory = SetupMemory(MemoryStored())..at('custom-ai', 'paste');
      await pumpSettings(tester, PluginSetupSheet(setup: test.setup(), memory: memory, onClose: () {}));
      await tester.enterText(field('base'), 'localhost:11434/v1');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('setup-next')));
      await settleSettings(tester);
      expect(test.settings.baseUrl, 'http://localhost:11434/v1');
      expect(test.keys, everyElement(isNull), reason: 'asked with no key');
      expect(find.text('The endpoint answers. Choose its model next.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('setup-next')));
      await settleSettings(tester);
      expect(find.text('Type the model’s name as the endpoint knows it.'), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byType(ProviderSetupChoices), matching: find.byType(EditableText)), 'llama3.1');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('custom-ai-setup-model-typed')));
      await settleSettings(tester);
      expect((test.settings.model, test.settings.ready), ('llama3.1', true));
      await endSettings(tester);
    });

    testWidgets('a provider’s page: Set up while it needs one, the key checked before it is kept, the models read, the switches', (tester) async {
      final test = ProviderTest(geminiPage);
      await pumpSettings(tester, SingleChildScrollView(child: ProviderPane(page: test.page, setup: PluginSetupCard(setup: test.setup()))), size: const Size(390, 4000));
      expect(find.text('Set up Gemini'), findsOneWidget);
      expect(find.text(test.page.sends), findsOneWidget, reason: 'what goes where, said plainly');
      expect(find.textContaining('may be out of date'), findsOneWidget);
      // A refused key is not kept.
      test.answer = geminiErrorOf(400, '{"error":{"message":"API key not valid."}}');
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('provider-key-new')), matching: find.byType(EditableText)), 'AIzaSy-wrong-abcdefghijklmnopqrstu');
      await tester.pump();
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('provider-key-new')), matching: find.text('Keep it')));
      await settleSettings(tester);
      expect(find.text('Google refused that key. Copy it again, all of it.'), findsOneWidget);
      expect(test.settings.hasKey, isFalse);
      // A right one is, and the list is read.
      test.answer = null;
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('provider-key-new')), matching: find.byType(EditableText)), 'AIzaSy-right-abcdefghijklmnopqrstu');
      await tester.pump();
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('provider-key-new')), matching: find.text('Keep it')));
      await settleSettings(tester);
      expect(test.settings.key, 'AIzaSy-right-abcdefghijklmnopqrstu');
      expect(find.byKey(const ValueKey('provider-key-kept')), findsOneWidget);
      expect(find.byKey(const ValueKey('provider-model:model-two')), findsOneWidget);
      expect(find.text('Set up Gemini'), findsNothing);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('provider-model:model-two')), matching: find.byType(Pick)));
      await settleSettings(tester);
      expect(test.settings.model, 'model-two');
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('provider-tools')), matching: find.byType(GlacierSwitch)));
      await settleSettings(tester);
      expect(test.settings.tools, isFalse);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('provider-meetings')), matching: find.byType(GlacierSwitch)));
      await settleSettings(tester);
      expect(test.settings.meetings, isFalse);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('provider-spend-on')), matching: find.byType(GlacierSwitch)));
      await settleSettings(tester);
      expect(test.settings.spend.on, isTrue);
      await endSettings(tester);
    });

    testWidgets('the app’s page builders put Set up on each page', (tester) async {
      for (final plugin in [openAiPlugin, geminiPlugin, customAiPlugin, asterPlugin]) {
        await pumpSettings(tester, SingleChildScrollView(key: UniqueKey(), child: Builder(builder: plugin.settings!.pane)), size: const Size(390, 4000));
        expect(find.byType(PluginSetupCard), findsOneWidget, reason: plugin.manifest.id);
        await endSettings(tester);
      }
    });
  });

  test('each plugin says plainly where the words go, under whose key, and is off until added', () {
    for (final (plugin, page, to) in [(openAiPlugin, openAiPage, 'OpenAI'), (geminiPlugin, geminiPage, 'Google'), (customAiPlugin, customAiPage, 'the address you give'), (asterPlugin, asterPage, 'Aster')]) {
      final manifest = plugin.manifest;
      expect(manifest.standard, isFalse, reason: manifest.id);
      expect(manifest.permissions.last.why, contains('go from this device to $to'), reason: manifest.id);
      expect(usesLine(manifest), 'Uses your notes and the internet');
      expect(page.sends, contains('Nothing goes through Ghost.md’s server.'));
      expect(manifest.description.toLowerCase(), isNot(contains('claude')), reason: 'its own words');
    }
    expect(openAiManifest.hosts, ['api.openai.com']);
    expect(geminiManifest.hosts, ['generativelanguage.googleapis.com']);
    expect(customAiManifest.hosts, isEmpty);
    expect(asterManifest.hosts, ['api.asterlab.ai']);
  });
}
