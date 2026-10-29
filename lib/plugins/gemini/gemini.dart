/// The Gemini plugin: Google's Gemini models in the app, with the person's own Gemini API key (docs/AI_PROVIDERS.md,
/// "Gemini"; Matt, 2026-10-29: "Add support for aster 6 and other Ai models as plugins in addition to claude like
/// openAI google gemini etc"). A Market plugin of its own, off until added, beside Claude's and OpenAI's:
///
/// - **What it does**: answers the dock's chat and Ask, with Ghost.md's tools (Gemini's function calling), typing into
///   the note as Claude does, where Settings › AI › Assistant says it answers; and writes meetings up, where it is
///   chosen for them and its Write meeting summaries with Gemini is on.
/// - **Its client** is gemini_api.dart: `streamGenerateContent` as server-sent events, with function declarations; the
///   key (an AI Studio key, in the `x-goog-api-key` header) checked and the models read from `GET /v1beta/models`, the
///   default the newest stable Pro there, else Flash ([geminiDefault]), kept as the choice until the person picks
///   another. [geminiFallbackModels] stand in where the list cannot be read, said to be possibly out of date.
/// - **Its settings** (lib/assistant/provider_settings.dart, prefix `gemini`): kept and synced as OpenAI's are.
///
/// It declares `notes` and `network`: the notes here, and `generativelanguage.googleapis.com`.
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
import 'gemini_api.dart';

export 'gemini_api.dart';

const PluginManifest geminiManifest = PluginManifest(
  id: 'gemini',
  name: 'Gemini',
  description: 'Ask Google’s Gemini models in the app with your own Gemini API key: from the dock on any page, writing into your notes as you watch, and writing your meetings up where you let it.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.ai,
  tagline: 'Google’s Gemini, with your own key',
  adds: [
    'Gemini in the dock’s chat, where Settings › AI chooses it or no other AI is set up',
    'The same tools Claude has: read, make and change your notes as you watch',
    'Meeting summaries written by Gemini, where you let it',
    'A monthly spending limit of its own',
  ],
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Asked here, it reads, makes and changes your notes on this device as you watch.'),
    PluginPermission(Permission.network, 'What you ask, the notes it reads to answer, and with meeting summaries on a meeting’s transcript, go from this device to Google with your key, and nowhere else.'),
  ],
  hosts: ['generativelanguage.googleapis.com'],
  storage: [],
);

/// The models offered where Google's own list cannot be read: ids Google has offered, which **may be out of date**
/// (the page says so).
const List<AiModelInfo> geminiFallbackModels = [
  AiModelInfo('gemini-2.5-pro', name: 'Gemini 2.5 Pro'),
  AiModelInfo('gemini-2.5-flash', name: 'Gemini 2.5 Flash'),
];

/// What is wrong with the shape of a pasted key, or null. AI Studio's keys start `AIza` today; another shape is let
/// through to the check rather than refused here.
String? geminiKeyShape(String text) {
  if (RegExp(r'\s').hasMatch(text)) return 'Paste the key alone: it has no spaces in it.';
  if (text.length < 30) return 'That key looks cut short. Copy all of it from AI Studio.';
  return null;
}

/// This device's Gemini settings.
final AiProviderSettings geminiSettings = AiProviderSettings(deviceSecureStore(), prefix: 'gemini', name: 'Gemini', fallbackModels: geminiFallbackModels);

/// Whether the plugin may be asked now (Local only holds it off).
bool geminiOn() => pluginOn(geminiManifest);

/// The client over [settings]' key, or [key].
AiProvider geminiClient(AiProviderSettings settings, {String? key}) => GeminiApi(key: key ?? settings.key ?? '', settings: settings);

final AiProviderPage geminiPage = AiProviderPage(
  id: geminiManifest.id,
  name: 'Gemini',
  icon: Lucide.wandSparkles,
  hue: 'blue',
  settings: geminiSettings,
  client: geminiClient,
  keyLabel: 'Gemini API key',
  keyPlaceholder: 'AIza…',
  keyShape: geminiKeyShape,
  company: 'Google',
  account: const AiProviderLink('Open Google AI Studio', 'https://aistudio.google.com/'),
  keys: const AiProviderLink('Open API keys', 'https://aistudio.google.com/apikey'),
  about: 'Google’s Gemini models answer here with your own API key from Google AI Studio, and write into your notes as you watch.',
);

/// Gemini's setup (lib/assistant/provider_setup.dart).
PluginSetup geminiSetup() => providerSetup(geminiPage);

final GlyphPlugin geminiPlugin = GlyphPlugin(
  manifest: geminiManifest,
  icon: 'wand-sparkles',
  setup: geminiSetup,
  settings: PluginSettings(
    pane: (BuildContext context) => ProviderPane(page: geminiPage, setup: PluginSetupCard(setup: geminiSetup())),
    summary: () => providerSummary(geminiPage),
    hue: 'blue',
    settings: providerFindable('Gemini'),
  ),
);
