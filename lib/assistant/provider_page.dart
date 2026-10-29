/// What one AI provider's plugin says about itself and how its key is checked (docs/AI_PROVIDERS.md, "Its page and its
/// setup"): one description for the page every provider shares (provider_pane.dart) and the setup every provider
/// shares (provider_setup.dart), each plugin's own words and addresses held in its folder (lib/plugins/openai/,
/// lib/plugins/gemini/, lib/plugins/custom_ai/, lib/plugins/aster/).
///
/// **What it says of privacy** is said plainly on its page, in its setup and in the Market ([sends]): what is asked,
/// the notes read to answer it, and, with meetings on, a meeting's transcript, go from this device to the provider
/// under the person's own key, billed to it, and nowhere else: not through Ghost.md's server.
library;

import 'package:flutter/foundation.dart';

import '../art/app_icon.dart' show LucideIcon;
import 'provider.dart';
import 'provider_settings.dart';

/// A page to open from the setup, or from the page's foot.
@immutable
class AiProviderLink {
  const AiProviderLink(this.label, this.url);
  final String label;
  final String url;
}

/// One provider's words and ways (see the header).
@immutable
class AiProviderPage {
  const AiProviderPage({
    required this.id,
    required this.name,
    required this.icon,
    required this.hue,
    required this.settings,
    required this.client,
    required this.keyLabel,
    required this.keyPlaceholder,
    this.keyShape,
    required this.company,
    this.account,
    this.keys,
    this.billing,
    this.about = '',
    this.custom = false,
    this.typedModel = false,
  });

  /// The plugin's id: `openai`.
  final String id;

  /// Its name, as the app says it: "OpenAI", "Gemini", "Custom AI model".
  final String name;
  final LucideIcon icon;

  /// Its colour, by `marketHues`' names (lib/market/market_items.dart).
  final String hue;
  final AiProviderSettings settings;

  /// Its client for a key (the one kept, or one being checked before it is kept).
  final AiProvider Function(AiProviderSettings settings, {String? key}) client;

  /// The key's field: "OpenAI API key", `sk-…`.
  final String keyLabel;
  final String keyPlaceholder;

  /// What is wrong with the shape of a pasted key, or null where it looks like one; none, and any shape is taken.
  final String? Function(String text)? keyShape;

  /// Who the words go to, as the privacy line says it: "OpenAI", "Google", "the endpoint you set".
  final String company;

  /// Where an account is made, where its keys are, where credit is added; none for the custom endpoint.
  final AiProviderLink? account;
  final AiProviderLink? keys;
  final AiProviderLink? billing;

  /// A line on what it is, for the page's head.
  final String about;

  /// Whether this is the OpenAI-compatible endpoint: an address and a model typed, the key optional.
  final bool custom;

  /// Whether a model's id may be typed as well as picked from the list, for a provider at a fixed address whose list
  /// may not name every model or may not be there at all (Aster's). The custom endpoint's always may ([typesModel]).
  final bool typedModel;

  /// Whether the page and the setup offer a field for the model's id.
  bool get typesModel => custom || typedModel;

  /// The same page over other settings and another client: a test's, whose provider is its own.
  AiProviderPage copyWith({AiProviderSettings? settings, AiProvider Function(AiProviderSettings settings, {String? key})? client}) => AiProviderPage(
        id: id,
        name: name,
        icon: icon,
        hue: hue,
        settings: settings ?? this.settings,
        client: client ?? this.client,
        keyLabel: keyLabel,
        keyPlaceholder: keyPlaceholder,
        keyShape: keyShape,
        company: company,
        account: account,
        keys: keys,
        billing: billing,
        about: about,
        custom: custom,
        typedModel: typedModel,
      );

  /// The privacy line (see the header).
  String get sends =>
      'What you ask, and the notes it reads to answer, go from this device to $company under your own key${custom ? '' : ', and $company bills the key'}. With meeting summaries on, a meeting’s transcript goes there too. Nothing goes through Ghost.md’s server.';

  /// A typed key checked: null when it works.
  Future<AiError?> check(String? key) => client(settings, key: key).check();

  /// The models, as the provider lists them now.
  Future<List<AiModelInfo>> models() => client(settings).models();
}
