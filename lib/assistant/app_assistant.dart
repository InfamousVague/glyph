/// The app's own assistant choice and its providers (docs/AI_PROVIDERS.md, "The assistant"): Claude's settings and
/// plugin, then OpenAI's, Gemini's and the custom endpoint's, in the order Automatic tries them. The root's runner
/// (lib/root/ghost_root.dart), the meetings' write-ups (lib/root/voice_wiring.dart), the AI page
/// (lib/settings/panes/ai_pane.dart) and the synced keys (lib/sync/connections.dart) share it, as they share
/// `claudeSettings`. Read on first use.
///
/// The switches are read from the app's registry ([plugins]) as each question is asked; what is heard for a change is
/// the registry the app had when this was first used, which is the one the app keeps (lib/plugins/built_in.dart puts it
/// in place before the first screen).
library;

import '../account/device_keys.dart' show deviceSecureStore;
import '../claude/claude_settings.dart' show claudeSettings;
import '../plugins/claude/claude.dart' show claudeInApp, claudeManifest;
import '../plugins/custom_ai/custom_ai.dart';
import '../plugins/gemini/gemini.dart';
import '../plugins/openai/openai.dart';
import '../plugins/registry.dart' show plugins;
import '../plugins/types.dart' show PluginManifest;
import 'assistant.dart';

bool _switchedOn(PluginManifest manifest) => plugins.all().isEmpty ? manifest.standard : plugins.switchedOn(manifest.id);

/// The providers other than Claude, in the order Automatic tries them.
final List<AiPlugged> aiProviders = [
  AiPlugged(id: openAiManifest.id, name: 'OpenAI', settings: openAiSettings, switchedOn: () => _switchedOn(openAiManifest), allowed: openAiOn, client: openAiClient),
  AiPlugged(id: geminiManifest.id, name: 'Gemini', settings: geminiSettings, switchedOn: () => _switchedOn(geminiManifest), allowed: geminiOn, client: geminiClient),
  AiPlugged(id: customAiManifest.id, name: 'Custom AI model', settings: customAiSettings, switchedOn: () => _switchedOn(customAiManifest), allowed: customAiOn, client: customAiClient),
];

/// The app's choice (see the header).
final AssistantChoice appAssistant = AssistantChoice(
  store: deviceSecureStore(),
  claude: claudeSettings,
  claudeOn: claudeInApp,
  claudeSwitchedOn: () => _switchedOn(claudeManifest),
  others: aiProviders,
  switches: plugins,
);
