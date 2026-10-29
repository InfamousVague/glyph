/// The Aster plugin: Aster's models in the app, with the person's own Aster API key (docs/AI_PROVIDERS.md, "Aster";
/// Matt, 2026-10-29: "aster 6 is OpenAI-compatible, add it as a plugin"). Custom AI model's shape (lib/plugins/custom_ai/),
/// preset: the address is Aster's, and only the key is pasted.
///
/// What Aster's own site says (asterlab.ai/inference and /pricing, read 2026-10-29): its API is OpenAI-compatible, at
/// `https://api.asterlab.ai/v1`; "pass your Aster key" (the header isn't named, so it is OpenAI's `Authorization:
/// Bearer`); keys are made in the console, where credits are added; nothing is kept by default (zero data retention).
/// Nothing there names "Aster 6", which is what Matt calls it.
///
/// - **Its client** is OpenAI's (lib/plugins/openai/chat_api.dart) at [asterBase], as a compatible endpoint
///   (`max_tokens`, every model listed as it is), in [AsterApi], which only changes the check (below). No HTTP of its
///   own.
/// - **Its models** are read from `GET /v1/models` at setup and on its page; [asterFallbackModels] stand in where the
///   list can't be read, said to be possibly out of date, and a model's id may be typed as the custom endpoint's is
///   ([AiProviderPage.typedModel]): the site shows display names ("Kimi K3", "GLM 5.2"), not their ids.
/// - **Its prices** for the spending meter are the three the site shows ([asterRatesFor]), else the seam's high guess.
/// - **Tools**: the site doesn't say whether its models take them; one that refuses them is asked without them, and the
///   chat says so once (lib/assistant/http_stream.dart `aiRefusedTools`).
/// - **Its settings** (lib/assistant/provider_settings.dart, prefix `aster`): the key, the model, the switches, the
///   prices and the limit, kept and synced as OpenAI's are.
///
/// It declares `notes` and `network`, which is what it reaches: the notes here, and `api.asterlab.ai`.
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

/// Aster's API, as its site gives it.
const String asterBase = 'https://api.asterlab.ai/v1';

/// Where an Aster key is made and credits are added (not opened while this was written: marked unverified).
const String asterConsole = 'https://www.asterlab.ai/inference/console';

const PluginManifest asterManifest = PluginManifest(
  id: 'aster',
  name: 'Aster',
  description:
      'Ask Aster (Aster 6) in the app with your own Aster API key: from the dock on any page, writing into your notes as you watch, and writing your meetings up where you let it. What you ask and the text of the notes it reads go to Aster under your key, and nowhere else.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.ai,
  tagline: 'Aster’s models, with your own key',
  adds: [
    'Aster in the dock’s chat, where Settings › AI chooses it or no other AI is set up',
    'Ghost.md’s tools, for a model that takes them',
    'Meeting summaries written by Aster, where you let it',
    'A monthly spending limit, at Aster’s prices',
  ],
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Asked here, it reads, makes and changes your notes on this device as you watch.'),
    PluginPermission(Permission.network, 'What you ask, the notes it reads to answer, and with meeting summaries on a meeting’s transcript, go from this device to Aster with your key, and nowhere else.'),
  ],
  hosts: ['api.asterlab.ai'],
  storage: [],
);

/// The model offered where Aster's own list can't be read: the one id its site shows, which **may be out of date**
/// (the page says so). The default is never this where the list could be read.
const List<AiModelInfo> asterFallbackModels = [AiModelInfo('gpt-oss-120b-fast')];

/// The prices Aster's site showed on 2026-10-29, US dollars a million tokens, input and output.
const AiRates asterGptOssRates = AiRates(input: 0.30, output: 1.20);
const AiRates asterKimiRates = AiRates(input: 2.50, output: 12.50);
const AiRates asterGlmRates = AiRates(input: 1.00, output: 4.00);

/// The spending meter's prices for [model] ([AiProviderSettings.ratesFor]): `gpt-oss-120b-fast` by its id; the site
/// gives the other two by their names alone, so any id with "kimi" in it is Kimi K3's and any with "glm" GLM 5.2's;
/// null for any other, which is counted at the seam's high guess.
AiRates? asterRatesFor(String model) {
  final id = model.trim().toLowerCase();
  if (id == 'gpt-oss-120b-fast') return asterGptOssRates;
  if (id.contains('kimi')) return asterKimiRates;
  if (id.contains('glm')) return asterGlmRates;
  return null;
}

/// What is wrong with the shape of a pasted key, or null. Aster's site doesn't say what its keys look like, so only
/// spaces are refused; the check says the rest.
String? asterKeyShape(String text) => RegExp(r'\s').hasMatch(text) ? 'Paste the key alone: it has no spaces in it.' : null;

/// This device's Aster settings.
final AiProviderSettings asterSettings = AiProviderSettings(deviceSecureStore(), prefix: 'aster', name: 'Aster', fallbackModels: asterFallbackModels, ratesFor: asterRatesFor);

/// Whether the plugin may be asked now (Local only holds it off).
bool asterOn() => pluginOn(asterManifest);

/// Aster's client: OpenAI's at [asterBase], whose check falls back to one token of a chat where there is no list of
/// models (see [check]).
class AsterApi implements AiProvider {
  AsterApi(this.chat, {required this.model});

  /// OpenAI's client at Aster's address.
  final OpenAiChatApi chat;

  /// The model the fallback check asks: the one chosen, else the first listed, else the fallback's.
  final String model;

  @override
  AiCall stream(Map<String, Object?> body) => chat.stream(body);

  @override
  Future<List<AiModelInfo>> models() => chat.models();

  /// The models list, as OpenAI's check. The site doesn't say Aster has `GET /v1/models`; where it has none (a 404 or
  /// a 405), the key is checked by the smallest chat there is instead: one token from [model], through the same
  /// client. Unlike the list, Aster bills that, a few tokens, a fraction of a cent.
  @override
  Future<AiError?> check() async {
    final wrong = await chat.check();
    if (wrong == null || (wrong.status != 404 && wrong.status != 405) || model.isEmpty) return wrong;
    try {
      final call = chat.stream({
        'model': model,
        'max_tokens': 1,
        'messages': const [
          {'role': 'user', 'content': 'Hi'},
        ],
      });
      await for (final event in call.events) {
        if (event.event != 'error') continue;
        final error = aiJson(event.data)['error'];
        return AiError(error is Map ? (error['message'] as String? ?? 'Aster stopped with an error.') : 'Aster stopped with an error.', type: error is Map ? error['type'] as String? : null);
      }
      return null;
    } on AiError catch (error) {
      return error;
    }
  }
}

/// The client over [settings]' key, or [key].
AiProvider asterClient(AiProviderSettings settings, {String? key}) =>
    AsterApi(OpenAiChatApi(key: key ?? settings.key, base: asterBase, official: false, who: 'Aster', place: 'Settings › Aster', settings: settings), model: settings.model);

/// The page's and the setup's words and ways.
final AiProviderPage asterPage = AiProviderPage(
  id: asterManifest.id,
  name: 'Aster',
  icon: Lucide.asterisk,
  hue: 'yellow',
  settings: asterSettings,
  client: asterClient,
  keyLabel: 'Aster API key',
  keyPlaceholder: 'Your Aster key',
  keyShape: asterKeyShape,
  company: 'Aster',
  account: const AiProviderLink('Open the Aster console', asterConsole),
  keys: const AiProviderLink('Open the Aster console', asterConsole),
  billing: const AiProviderLink('Plans and pricing', 'https://www.asterlab.ai/pricing'),
  typedModel: true,
  about: 'Aster’s models answer here with your own Aster API key, through its OpenAI-compatible API, and write into your notes as you watch. Aster bills the key; it says it keeps nothing it is sent by default.',
);

/// Aster's setup (lib/assistant/provider_setup.dart): intro, account, key, paste, check, settings.
PluginSetup asterSetup() => providerSetup(asterPage);

final GlyphPlugin asterPlugin = GlyphPlugin(
  manifest: asterManifest,
  icon: 'asterisk',
  setup: asterSetup,
  settings: PluginSettings(
    pane: (BuildContext context) => ProviderPane(page: asterPage, setup: PluginSetupCard(setup: asterSetup())),
    summary: () => providerSummary(asterPage),
    hue: 'yellow',
    settings: providerFindable('Aster'),
  ),
);
