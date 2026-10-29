// Pictures of the other AI providers' plugins (docs/AI_PROVIDERS.md; Matt, 2026-10-29: "Add support for aster 6 and
// other Ai models as plugins in addition to claude like openAI google gemini etc"), for the eye: written only by
// `flutter test --update-goldens test/plugins/ai_providers/shots_test.dart`, into build/feature-shots/ai-providers/
// (not committed). Each plugin's page, unset and set up; every step of each setup; a check that fails; and Settings ›
// AI's Assistant; on a phone and the Mac's window, light and dark. Every provider is the test's own: nothing is asked
// of a network.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/assistant/assistant.dart';
import 'package:ghost_md/assistant/provider.dart';
import 'package:ghost_md/assistant/provider_pane.dart';
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/custom_ai/custom_ai.dart';
import 'package:ghost_md/plugins/gemini/gemini.dart';
import 'package:ghost_md/plugins/onboarding/setup_card.dart';
import 'package:ghost_md/plugins/onboarding/setup_flow.dart';
import 'package:ghost_md/plugins/onboarding/setup_sheet.dart';
import 'package:ghost_md/plugins/openai/openai.dart';
import 'package:ghost_md/settings/panes/ai_pane.dart';

import '../../settings/support.dart';
import 'support.dart';

const String _out = '../../../build/feature-shots/ai-providers';

void main() {
  setUpAll(loadAppFonts);

  const places = [('phone', Size(390, 844), false), ('mac', Size(1280, 800), true)];

  Future<void> picture(WidgetTester tester, Widget shown, {required String name, required Size size, required bool mac, required String theme}) async {
    if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpSettings(tester, shown, size: size, prefs: Preferences(theme: theme, experience: 'advanced', experienceChosen: true));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await expectLater(find.byType(GhostApp), matchesGoldenFile('$_out/$name.png'));
    await endSettings(tester);
    debugDefaultTargetPlatformOverride = null;
  }

  const listed = [AiModelInfo('model-pro', name: 'Flagship Pro'), AiModelInfo('model-mini', name: 'Flagship Mini'), AiModelInfo('model-nano', name: 'Flagship Nano')];

  for (final (where, size, mac) in places) {
    for (final (id, page) in [('openai', openAiPage), ('gemini', geminiPage), ('custom-ai', customAiPage)]) {
      testWidgets('$id’s page and its setup on the $where, light and dark', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        for (final theme in ['light', 'dark']) {
          // The page, before anything is kept, then set up.
          final fresh = ProviderTest(page);
          await picture(tester, SingleChildScrollView(key: UniqueKey(), child: ProviderPane(page: fresh.page, setup: PluginSetupCard(setup: fresh.setup(), memory: SetupMemory(MemoryStored())))), name: '$id-page-new-$where-$theme', size: Size(size.width, 2800), mac: mac, theme: theme);
          final set = ProviderTest(page)..listed = listed;
          await tester.runAsync(() async {
            if (page.custom) await set.settings.setBaseUrl('https://openrouter.ai/api/v1');
            await set.settings.setKey(page.custom ? 'sk-or-v1-0123456789abcdef' : 'sk-proj-0123456789abcdefghijkl');
            set.settings.setModels(listed);
            await Future<void>.delayed(Duration.zero);
          });
          await picture(tester, SingleChildScrollView(key: UniqueKey(), child: ProviderPane(page: set.page, setup: PluginSetupCard(setup: set.setup(), memory: SetupMemory(MemoryStored())))), name: '$id-page-set-$where-$theme', size: Size(size.width, 3400), mac: mac, theme: theme);
          // Every step, and a check that fails.
          for (final step in ProviderTest(page).setup().steps) {
            final test = ProviderTest(page)..listed = listed;
            if (step is SetupCheck || step is SetupDone) {
              await tester.runAsync(() async {
                if (page.custom) await test.settings.setBaseUrl('http://localhost:1234/v1');
                await test.settings.setKey(page.custom ? null : 'sk-proj-0123456789abcdefghijkl');
                if (step is SetupDone) test.settings.setModels(listed);
                await Future<void>.delayed(Duration.zero);
              });
            }
            final memory = SetupMemory(MemoryStored())..at(id, step.id);
            await picture(tester, PluginSetupSheet(key: UniqueKey(), setup: test.setup(), memory: memory, onClose: () {}), name: '$id-setup-${step.id}-$where-$theme', size: size, mac: mac, theme: theme);
          }
          final refused = ProviderTest(page)..answer = page.custom ? openAiErrorOf(404, 'Not Found', who: 'The endpoint') : (id == 'gemini' ? geminiErrorOf(429, '{"error":{"code":429,"message":"Quota exceeded","status":"RESOURCE_EXHAUSTED"}}') : openAiErrorOf(429, '{"error":{"code":"insufficient_quota","message":"quota"}}'));
          await tester.runAsync(() async {
            if (page.custom) await refused.settings.setBaseUrl('http://localhost:1234/v1');
            await refused.settings.setKey(page.custom ? null : 'sk-proj-0123456789abcdefghijkl');
          });
          await picture(tester, PluginSetupSheet(key: UniqueKey(), setup: refused.setup(), memory: SetupMemory(MemoryStored())..at(id, 'check'), onClose: () {}), name: '$id-setup-check-warn-$where-$theme', size: size, mac: mac, theme: theme);
        }
      });
    }

    testWidgets('Settings › AI › Assistant on the $where, light and dark', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      for (final theme in ['light', 'dark']) {
        final claude = ClaudeSettings(MemorySecureStore());
        final openAi = ProviderTest(openAiPage);
        final gemini = ProviderTest(geminiPage);
        final choice = AssistantChoice(store: MemorySecureStore(), claude: claude, claudeOn: () => true, others: [
          AiPlugged(id: 'openai', name: 'OpenAI', settings: openAi.settings, switchedOn: () => true, client: openAi.page.client),
          AiPlugged(id: 'gemini', name: 'Gemini', settings: gemini.settings, switchedOn: () => true, client: gemini.page.client),
        ]);
        await tester.runAsync(() async {
          await choice.load();
          await openAi.settings.setKey('sk-proj-0123456789abcdefghijkl');
          await openAi.settings.setModel('model-pro');
          await choice.setMeetings('openai');
        });
        await picture(tester, SingleChildScrollView(key: UniqueKey(), child: AiPane(assistant: choice)), name: 'ai-assistant-$where-$theme', size: Size(size.width, 1800), mac: mac, theme: theme);
      }
    });
  }
}
