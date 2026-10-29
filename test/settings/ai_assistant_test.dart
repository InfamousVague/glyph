// Settings › AI › Assistant (lib/settings/panes/ai_pane.dart `AssistantSection`; docs/AI_PROVIDERS.md; Matt,
// 2026-10-29: "Add support for aster 6 and other Ai models as plugins in addition to claude like openAI google gemini
// etc"): which AI answers the chat and which writes meetings up, Automatic saying who that is now, each provider saying
// whether it can, and a pick kept.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/assistant/assistant.dart';
import 'package:ghost_md/assistant/provider_settings.dart';
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart' show Pick;
import 'package:ghost_md/settings/panes/ai_pane.dart';

import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('says who answers now, whether each can, and keeps a pick for the chat and for meetings', (tester) async {
    final claude = ClaudeSettings(MemorySecureStore());
    final openAi = AiProviderSettings(MemorySecureStore(), prefix: 'openai', name: 'OpenAI');
    final store = MemorySecureStore();
    final choice = AssistantChoice(
      store: store,
      claude: claude,
      claudeOn: () => true,
      others: [AiPlugged(id: 'openai', name: 'OpenAI', settings: openAi, switchedOn: () => true, client: (settings, {key}) => throw UnimplementedError())],
    );
    await tester.runAsync(() async {
      await choice.load();
      await openAi.setKey('sk-test-0123456789abcdef');
      await openAi.setModel('gpt-test');
    });
    await pumpSettings(tester, SingleChildScrollView(child: AiPane(assistant: choice)), size: const Size(390, 3000));
    expect(find.text('Which AI answers the dock’s chat and Ask. Automatic is Claude where it can answer, else the first other AI you have set up.'), findsOneWidget);
    Finder hint(String key, String words) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(words));
    expect(hint('assistant-chat:auto', 'Now: OpenAI.'), findsOneWidget);
    expect(hint('assistant-chat:claude', 'Needs its key: Settings › Claude.'), findsOneWidget);
    expect(hint('assistant-chat:openai', 'Ready: gpt-test.'), findsOneWidget);
    expect(hint('assistant-meetings:device', 'The summary model on your device, and nothing of a meeting leaves it.'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('assistant-meetings:device')), matching: find.byType(Pick)));
    await settleSettings(tester);
    expect(choice.meetings, assistantDevice);
    expect(await tester.runAsync(() => store.read(assistantMeetingsName)), assistantDevice);
    expect(hint('assistant-meetings:auto', 'Would be: OpenAI.'), findsOneWidget, reason: 'Automatic is not what is chosen, and says who it would be');
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('assistant-chat:openai')), matching: find.byType(Pick)));
    await settleSettings(tester);
    expect((choice.chat, choice.chatBy), ('openai', 'openai'));
    await endSettings(tester);
  });
}
