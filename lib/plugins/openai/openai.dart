/// The OpenAI plugin: OpenAI's models in the app, with the person's own API key (docs/AI_PROVIDERS.md, "OpenAI"; Matt,
/// 2026-10-29: "Add support for aster 6 and other Ai models as plugins in addition to claude like openAI google gemini
/// etc"). A Market plugin of its own, off until added, beside Claude's:
///
/// - **What it does**: answers the dock's chat and Ask, with Ghost.md's tools, typing into the note as Claude does, where
///   Settings › AI › Assistant says it answers (Automatic: where Claude cannot); and writes meetings up, where it is
///   chosen for them and its Write meeting summaries with OpenAI is on.
/// - **Its client** is chat_api.dart: Chat Completions, streamed, with function calling; the key checked and the models
///   read from `GET /v1/models`, the default the newest flagship there ([openAiFlagship]), kept as the choice until the
///   person picks another. [openAiFallbackModels] stand in where the list cannot be read, said to be possibly out of
///   date.
/// - **Its settings** (lib/assistant/provider_settings.dart, prefix `openai`): the key in the device's secure store,
///   sealed to the account's other devices with the model, the switches, the prices and the limit
///   (lib/sync/connections.dart). Its page and its setup are every provider's (lib/assistant/provider_pane.dart,
///   provider_setup.dart) in its words.
///
/// It declares `notes` and `network`, which is what it reaches: the notes here, and `api.openai.com`.
library;

import 'package:flutter/widgets.dart';

import '../../account/device_keys.dart' show deviceSecureStore;
import '../../art/lucide.g.dart';
import '../../assistant/provider.dart';
import '../../assistant/provider_page.dart';
import '../../assistant/provider_pane.dart';
import '../../assistant/provider_settings.dart';
import '../../assistant/provider_setup.dart';
import '../onboarding/setup_card.dart';
import '../onboarding/setup_flow.dart';
import '../registry.dart' show pluginOn;
import '../types.dart';
import 'chat_api.dart';

export 'chat_api.dart';

const PluginManifest openAiManifest = PluginManifest(
  id: 'openai',
  name: 'OpenAI',
  description: 'Ask OpenAI’s models in the app with your own OpenAI API key: from the dock on any page, writing into your notes as you watch, and writing your meetings up where you let it.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.ai,
  tagline: 'OpenAI’s models, with your own key',
  adds: [
    'OpenAI in the dock’s chat, where Settings › AI chooses it or no other AI is set up',
    'The same tools Claude has: read, make and change your notes as you watch',
    'Meeting summaries written by OpenAI, where you let it',
    'A monthly spending limit of its own',
  ],
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Asked here, it reads, makes and changes your notes on this device as you watch.'),
    PluginPermission(Permission.network, 'What you ask, the notes it reads to answer, and with meeting summaries on a meeting’s transcript, go from this device to OpenAI with your key, and nowhere else.'),
  ],
  hosts: ['api.openai.com'],
  storage: [],
);

/// The models offered where OpenAI's own list cannot be read: ids OpenAI has offered, which **may be out of date**
/// (the page says so). The default is never one of these where the list could be read.
const List<AiModelInfo> openAiFallbackModels = [
  AiModelInfo('gpt-5', name: 'GPT-5'),
  AiModelInfo('gpt-5-mini', name: 'GPT-5 mini'),
  AiModelInfo('gpt-4.1', name: 'GPT-4.1'),
];

/// What is wrong with the shape of a pasted key, or null.
String? openAiKeyShape(String text) {
  if (RegExp(r'\s').hasMatch(text)) return 'Paste the key alone: it has no spaces in it.';
  if (!text.startsWith('sk-')) return 'That doesn’t look like an OpenAI API key. Those start with sk-.';
  if (text.length < 20) return 'That key looks cut short. Copy all of it.';
  return null;
}

/// This device's OpenAI settings, as the app reads and writes them.
final AiProviderSettings openAiSettings = AiProviderSettings(deviceSecureStore(), prefix: 'openai', name: 'OpenAI', fallbackModels: openAiFallbackModels);

/// Whether the plugin may be asked now (Local only holds it off).
bool openAiOn() => pluginOn(openAiManifest);

/// The client over [settings]' key, or [key].
AiProvider openAiClient(AiProviderSettings settings, {String? key}) => OpenAiChatApi(key: key ?? settings.key, settings: settings);

/// The page's and the setup's words and ways.
final AiProviderPage openAiPage = AiProviderPage(
  id: openAiManifest.id,
  name: 'OpenAI',
  icon: Lucide.brain,
  hue: 'green',
  settings: openAiSettings,
  client: openAiClient,
  keyLabel: 'OpenAI API key',
  keyPlaceholder: 'sk-…',
  keyShape: openAiKeyShape,
  company: 'OpenAI',
  account: const AiProviderLink('Open the OpenAI platform', 'https://platform.openai.com/'),
  keys: const AiProviderLink('Open API keys', 'https://platform.openai.com/api-keys'),
  billing: const AiProviderLink('Billing', 'https://platform.openai.com/settings/organization/billing/overview'),
  about: 'OpenAI’s models answer here with your own API key, and write into your notes as you watch. OpenAI bills the key, apart from any ChatGPT plan.',
);

/// OpenAI's setup (lib/assistant/provider_setup.dart).
PluginSetup openAiSetup() => providerSetup(openAiPage);

final GlyphPlugin openAiPlugin = GlyphPlugin(
  manifest: openAiManifest,
  icon: 'brain',
  setup: openAiSetup,
  settings: PluginSettings(
    pane: (BuildContext context) => ProviderPane(page: openAiPage, setup: PluginSetupCard(setup: openAiSetup())),
    summary: () => providerSummary(openAiPage),
    hue: 'green',
    settings: providerFindable('OpenAI'),
  ),
);
