/// The Custom AI model plugin: any model behind an OpenAI-compatible endpoint, with its address, its key (if it has
/// one) and its model's name (docs/AI_PROVIDERS.md, "Custom AI model"; Matt, 2026-10-29: "Add support for aster 6 and
/// other Ai models as plugins in addition to claude like openAI google gemini etc"). Most providers offer one: OpenRouter
/// (`https://openrouter.ai/api/v1`), Mistral, Groq, DeepSeek, Together; and LM Studio (`http://localhost:1234/v1`) and
/// Ollama (`http://localhost:11434/v1`) on the person's own computer, with no key. A model named to us whose provider
/// is not known yet ("Aster 6") is reached here until it is.
///
/// - **Its client** is OpenAI's (lib/plugins/openai/chat_api.dart) at the address given, as a compatible endpoint
///   (`max_tokens`, every model listed as it is, OpenRouter's prices read where it lists them). Its check and its list
///   are `GET {address}/models`; an endpoint with no list is asked all the same, by the model typed.
/// - **Tools**: offered unless turned off; a model that refuses them is asked without them, and the chat says so once.
/// - **Its settings** (lib/assistant/provider_settings.dart, prefix `custom-ai`): the address, the key and the model,
///   kept and synced as OpenAI's are.
///
/// It declares `notes` and `network`. The host is the person's: the Market says "the address you give".
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
import '../openai/chat_api.dart';
import '../registry.dart' show pluginOn;
import '../types.dart';

const PluginManifest customAiManifest = PluginManifest(
  id: 'custom-ai',
  name: 'Custom AI model',
  description:
      'Any model behind an OpenAI-compatible endpoint, which most providers offer: OpenRouter, Mistral, Groq or DeepSeek, or LM Studio and Ollama on your own computer. Give its address, its key and the model’s name, and it answers in the dock and writes meetings up where you let it.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.ai,
  tagline: 'Any OpenAI-compatible endpoint, by its address',
  adds: [
    'Your own endpoint’s model in the dock’s chat, where Settings › AI chooses it or no other AI is set up',
    'Ghost.md’s tools, for a model that takes them',
    'Meeting summaries written by it, where you let it',
    'A monthly spending limit, at the prices you set',
  ],
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Asked here, it reads, makes and changes your notes on this device as you watch.'),
    PluginPermission(Permission.network, 'What you ask, the notes it reads to answer, and with meeting summaries on a meeting’s transcript, go from this device to the address you give, under your key, and nowhere else.'),
  ],
  storage: [],
);

/// What is wrong with the shape of a pasted key, or null: any key without spaces.
String? customAiKeyShape(String text) => RegExp(r'\s').hasMatch(text) ? 'Paste the key alone: it has no spaces in it.' : null;

/// This device's custom endpoint.
final AiProviderSettings customAiSettings = AiProviderSettings(deviceSecureStore(), prefix: 'custom-ai', name: 'Custom AI model', keyOptional: true, needsBase: true);

/// Whether the plugin may be asked now (Local only holds it off).
bool customAiOn() => pluginOn(customAiManifest);

/// The client at [settings]' address, over its key or [key].
AiProvider customAiClient(AiProviderSettings settings, {String? key}) =>
    OpenAiChatApi(key: key ?? settings.key, base: settings.baseUrl ?? '', official: false, who: 'The endpoint', place: 'Settings › Custom AI model', settings: settings);

final AiProviderPage customAiPage = AiProviderPage(
  id: customAiManifest.id,
  name: 'Custom AI model',
  icon: Lucide.network,
  hue: 'indigo',
  settings: customAiSettings,
  client: customAiClient,
  keyLabel: 'API key',
  keyPlaceholder: 'Its key, or nothing',
  keyShape: customAiKeyShape,
  company: 'the endpoint you set',
  custom: true,
  about: 'Any model behind an OpenAI-compatible endpoint: most providers offer one, and LM Studio and Ollama run one on your own computer.',
);

/// The custom endpoint's setup (lib/assistant/provider_setup.dart).
PluginSetup customAiSetup() => providerSetup(customAiPage);

final GlyphPlugin customAiPlugin = GlyphPlugin(
  manifest: customAiManifest,
  icon: 'network',
  setup: customAiSetup,
  settings: PluginSettings(
    pane: (BuildContext context) => ProviderPane(page: customAiPage, setup: PluginSetupCard(setup: customAiSetup())),
    summary: () => providerSummary(customAiPage),
    hue: 'indigo',
    settings: providerFindable('Custom AI model', custom: true),
  ),
);
