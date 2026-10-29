/// One AI provider's page in Settings (docs/AI_PROVIDERS.md, "Its page and its setup"): the same cards for OpenAI,
/// Gemini and the custom endpoint, each in its plugin's words ([AiProviderPage]), shaped as Claude's In the app cards
/// (lib/plugins/claude/claude_in_app.dart) so the four read alike:
///
/// - **Your key** (the custom endpoint's: **The endpoint**, its address first): pasted, checked with the provider before
///   it is kept (its models list, which no provider bills), then shown by its start and end with Check, and Forget,
///   asked twice. Under it, plainly, what goes where ([AiProviderPage.sends]).
/// - **Model**: the provider's own list, read from it as the key is kept and again on Read the list again, never a list
///   of ids written here; the plugin's few in its place where the list cannot be read, said to be possibly out of
///   date. The custom endpoint's model may be typed, as some list none, and Aster's ([AiProviderPage.typedModel]).
/// - **Tools**: whether the model is offered Ghost.md's tools (on), for a model the person knows has none. One that
///   refuses them is asked without them anyway, and the chat says so once.
/// - **Meeting summaries**: Write meeting summaries with (its name), on unless turned off, as Claude's; which provider writes
///   them, of those that may, is Settings › AI › Assistant.
/// - **Spending limit**: Claude's card, for this provider's own limit (lib/claude/claude_spend.dart), and the prices it
///   counts at, since no provider's API says them: high until the person sets their model's, so the limit is reached
///   early rather than late; OpenRouter's listed prices where it lists them, and Aster's published ones for its models.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart' show AppIcon, Lucide;
import '../claude/claude_settings.dart' show maskKey;
import '../claude/claude_spend.dart';
import '../plugins/github/plain_field.dart';
import '../settings/kit/settings_kit.dart';
import '../settings/panes/pane_parts.dart' show armedFor;
import '../settings/settings_search.dart' show SettingsFindable;
import 'provider.dart';
import 'provider_page.dart';
import 'provider_settings.dart';

/// What Settings' search finds on a provider's page.
List<SettingsFindable> providerFindable(String name, {bool custom = false}) => [
      if (custom) SettingsFindable('The endpoint', '${name.toLowerCase()} address url base endpoint openrouter mistral groq deepseek lm studio ollama api key token') else SettingsFindable('Your key', '${name.toLowerCase()} api key token secret connections'),
      SettingsFindable('Model', '${name.toLowerCase()} model models choose'),
      const SettingsFindable('Tools', 'tools function calling notes read write'),
      SettingsFindable('Meeting summaries', 'meeting meetings summary summaries write up transcript ${name.toLowerCase()} privacy'),
      const SettingsFindable('Spending limit', 'spending limit budget cost money dollars monthly price usage spend cap warn rates'),
    ];

/// The models a page shows before Show all.
const int providerModelsShown = 12;

/// A provider's page (see the header).
class ProviderPane extends StatefulWidget {
  const ProviderPane({super.key, required this.page, this.setup});

  final AiProviderPage page;

  /// Set up, or Run setup again (lib/plugins/onboarding/setup_card.dart), under the page's head.
  final Widget? setup;

  @override
  State<ProviderPane> createState() => _ProviderPaneState();
}

class _ProviderPaneState extends State<ProviderPane> {
  final TextEditingController _key = TextEditingController();
  final TextEditingController _base = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _custom = TextEditingController();
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  bool _checking = false;
  bool _reading = false;
  bool _all = false;
  String? _problem;
  String? _said;
  String? _modelsProblem;
  bool _armed = false;
  Timer? _timer;

  AiProviderPage get _page => widget.page;
  AiProviderSettings get _settings => _page.settings;

  @override
  void initState() {
    super.initState();
    unawaited(_settings.load().then((_) {
      if (mounted && _settings.ready && _settings.listed.isEmpty) unawaited(_readModels());
    }));
  }

  @override
  void dispose() {
    for (final controller in [_key, _base, _model, _custom, _input, _output]) {
      controller.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  void _say({String? problem, String? said}) => setState(() {
        _problem = problem;
        _said = said;
      });

  Future<void> _readModels() async {
    if (_reading) return;
    setState(() {
      _reading = true;
      _modelsProblem = null;
    });
    try {
      final models = await _page.models();
      _settings.setModels(models);
      if (models.isEmpty) _modelsProblem = '${_page.name} listed no models.';
    } on AiError catch (error) {
      _modelsProblem = error.message;
    } catch (error) {
      _modelsProblem = '$error';
    }
    if (mounted) setState(() => _reading = false);
  }

  Future<void> _keepKey() async {
    final key = _key.text.trim();
    if (key.isEmpty || _checking) return;
    final shape = _page.keyShape?.call(key);
    if (shape != null) return _say(problem: shape);
    setState(() {
      _checking = true;
      _problem = _said = null;
    });
    final wrong = await _page.check(key);
    if (!mounted) return;
    if (wrong != null && wrong.badKey) {
      setState(() => _checking = false);
      return _say(problem: '${_page.company} refused that key. Copy it again, all of it.');
    }
    await _settings.setKey(key);
    if (!mounted) return;
    _key.clear();
    setState(() => _checking = false);
    // Kept even when it could not be checked (no connection): it is checked again at the first ask.
    _say(said: wrong == null ? 'The key works.' : 'Kept. It could not be checked just now: ${wrong.message}');
    if (wrong == null) unawaited(_readModels());
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _problem = _said = null;
    });
    final wrong = await _page.check(_settings.key);
    if (!mounted) return;
    setState(() => _checking = false);
    if (wrong == null) {
      _say(said: _page.custom ? 'The endpoint answers.' : 'The key works.');
      unawaited(_readModels());
    } else {
      _say(problem: wrong.message);
    }
  }

  Future<void> _keepBase() async {
    final url = aiBaseUrl(_base.text);
    if (url == null) return;
    if (Uri.tryParse(url)?.host.isEmpty ?? true) return _say(problem: 'That doesn’t look like an address. It is like https://openrouter.ai/api/v1.');
    await _settings.setBaseUrl(url);
    if (!mounted) return;
    _base.clear();
    _say();
    unawaited(_check());
  }

  Future<void> _keepModel() async {
    final typed = _model.text.trim();
    if (typed.isEmpty) return;
    await _settings.setModel(typed);
    _model.clear();
    if (mounted) _say();
  }

  void _forget() {
    _timer?.cancel();
    if (!_armed) {
      setState(() => _armed = true);
      HapticsProvider.of(context)(HapticKind.warning);
      _timer = Timer(armedFor, () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    setState(() {
      _armed = false;
      _said = _problem = null;
    });
    unawaited(_settings.setKey(null));
  }

  void _setCustomLimit(ClaudeSpend spend) {
    final typed = double.tryParse(_custom.text.replaceAll(RegExp(r'[\s$,]'), ''));
    if (typed == null || !typed.isFinite || typed < 0.01) return _say(problem: 'Type the monthly limit in US dollars, such as 15 or 12.50.');
    _custom.clear();
    _say();
    unawaited(spend.setLimit((typed * 100).round() / 100));
  }

  void _setRates() {
    double? read(TextEditingController field) => double.tryParse(field.text.replaceAll(RegExp(r'[\s$,]'), ''));
    final now = _settings.rates;
    final input = _input.text.trim().isEmpty ? now.input : read(_input), output = _output.text.trim().isEmpty ? now.output : read(_output);
    if (input == null || output == null || input < 0 || output < 0) return _say(problem: 'Type each price in US dollars for a million tokens, such as 2.50.');
    _input.clear();
    _output.clear();
    _say();
    unawaited(_settings.setRates(AiRates(input: input, output: output)));
  }

  Widget _field(String label, TextEditingController controller, String placeholder, VoidCallback keep, {bool secret = false, String action = 'Keep it'}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PlainField(label: label, controller: controller, placeholder: placeholder, secret: secret, onSubmitted: keep),
          SizedBox(height: context.tokens.space(2)),
          Align(
            alignment: Alignment.centerLeft,
            child: RowAction(onPress: keep, disabled: _checking, child: Text(_checking ? 'Checking…' : action)),
          ),
        ],
      );

  Widget _keyCard() {
    final page = _page, settings = _settings, key = settings.key, base = settings.baseUrl;
    return PaneSection(
      title: page.custom ? 'The endpoint' : 'Your key',
      description: Text(page.sends),
      footer: Text(
        [
          if (page.custom) 'Most providers offer an OpenAI-compatible endpoint: OpenRouter, Mistral, Groq and DeepSeek among them, and LM Studio or Ollama on your own computer (http://localhost:1234/v1, http://localhost:11434/v1).',
          'The key is kept in this device’s secure storage, and sealed to your other devices while Keep keys and connections in sync is on (Settings › Account).',
          if (page.keys != null) 'Make one at ${Uri.parse(page.keys!.url).host}.',
        ].join(' '),
      ),
      children: [
        if (page.custom)
          base == null
              ? SettingRow(key: const ValueKey('provider-base-new'), label: 'Address', layout: SettingRowLayout.stacked, control: _field('Endpoint address', _base, 'https://openrouter.ai/api/v1', () => unawaited(_keepBase())))
              : SettingRow(
                  key: const ValueKey('provider-base-kept'),
                  label: 'Address',
                  hint: Text(base, softWrap: false, overflow: TextOverflow.fade),
                  value: RowAction(onPress: () => unawaited(settings.setBaseUrl(null)), child: const Text('Change')),
                ),
        if (key == null)
          SettingRow(
            key: const ValueKey('provider-key-new'),
            label: page.custom ? 'API key, if it needs one' : 'API key',
            layout: SettingRowLayout.stacked,
            control: _field(page.keyLabel, _key, page.keyPlaceholder, () => unawaited(_keepKey()), secret: true),
          )
        else ...[
          SettingRow(
            key: const ValueKey('provider-key-kept'),
            label: 'API key',
            hint: Text('A key is kept: ${maskKey(key)}'),
            value: RowAction(onPress: () => unawaited(_check()), disabled: _checking, child: Text(_checking ? 'Checking…' : 'Check')),
          ),
          SettingRow(
            key: const ValueKey('provider-key-forget'),
            label: 'Forget the key',
            hint: Text('${page.name} can no longer be asked on this device until a key is added again.'),
            value: RowAction(onPress: _forget, child: Text(_armed ? 'Tap again' : 'Forget')),
          ),
        ],
        if (page.custom && key == null && base != null)
          SettingRow(
            key: const ValueKey('provider-check'),
            label: 'Check the endpoint',
            hint: const Text('One look at its list of models.'),
            value: RowAction(onPress: () => unawaited(_check()), disabled: _checking, child: Text(_checking ? 'Checking…' : 'Check')),
          ),
      ],
    );
  }

  Widget _modelCard() {
    final settings = _settings, listed = settings.listed;
    final fallback = listed.isEmpty;
    final models = fallback ? settings.fallbackModels : listed;
    final shown = _all || models.length <= providerModelsShown + 2 ? models : models.take(providerModelsShown).toList();
    final chosen = settings.model;
    final String description;
    if (_reading) {
      description = 'Reading ${_page.name}’s list of models…';
    } else if (!fallback) {
      description = 'From ${_page.name}’s own list, as your key sees it. ${listed.first.id == chosen && settings.chosenModel == null ? 'The first is the one used unless you choose another.' : ''}'.trim();
    } else if (models.isEmpty) {
      description = 'Type the model’s name as the endpoint knows it, such as mistral-small-latest or llama3.1.';
    } else {
      description = 'These may be out of date: ${_page.name}’s own list couldn’t be read${_modelsProblem == null ? ' yet' : ''}. Read the list again once a key is kept.';
    }
    return PaneSection(
      title: 'Model',
      description: Text(description),
      footer: _modelsProblem == null ? null : Text(_modelsProblem!),
      children: [
        for (final model in shown)
          SettingRow(
            key: ValueKey('provider-model:${model.id}'),
            label: model.name,
            hint: model.name != model.id ? Text(model.id) : null,
            control: Pick(checked: chosen == model.id, label: 'Use ${model.name}', onPress: () => unawaited(settings.setModel(model.id))),
          ),
        if (shown.length < models.length)
          SettingRow(key: const ValueKey('provider-models-all'), label: 'Show all ${models.length}', onPress: () => setState(() => _all = true)),
        if (_page.typesModel || (chosen.isNotEmpty && !models.any((m) => m.id == chosen)))
          SettingRow(
            key: const ValueKey('provider-model-typed'),
            label: chosen.isEmpty ? 'Model name' : 'Model: $chosen',
            layout: SettingRowLayout.stacked,
            control: _field('Model name', _model, 'The model’s id', () => unawaited(_keepModel()), action: 'Use it'),
          ),
        SettingRow(
          key: const ValueKey('provider-models-read'),
          label: 'Read the list again',
          hint: Text(settings.ready || (_page.custom && settings.hasBase) ? 'Ask ${_page.name} which models your key may use.' : 'Once a key is kept.'),
          value: RowAction(onPress: () => unawaited(_readModels()), disabled: _reading || !(settings.hasKey || (_page.custom && settings.hasBase)), child: Text(_reading ? 'Reading…' : 'Read')),
        ),
      ],
    );
  }

  Widget _spendCard(ClaudeSpend spend) {
    final spent = spend.spent, requests = spend.requests;
    final asked = '$requests request${requests == 1 ? '' : 's'}';
    final month = spend.on ? 'This month: ${claudeDollars(spent)} of ${claudeLimitWords(spend.limit)} · $asked' : 'This month: ${claudeDollars(spent)} · $asked';
    final rates = _settings.rates;
    final ratesSaid = 'Counted at ${claudeDollars(rates.input)} in and ${claudeDollars(rates.output)} out for a million tokens';
    return PaneSection(
      title: 'Spending limit',
      description: Text('A monthly limit on what ${_page.name} in the app spends with your key, in US dollars. Once it is reached, it isn’t asked until the 1st of next month or until you raise it; meeting write-ups wait for then.'),
      footer: Text('Counted on this device from what ${_page.name} reports for each request, at the prices below: ${_page.name}’s API doesn’t say them. Other apps or devices using the same key aren’t included.'),
      children: [
        SettingRow(
          key: const ValueKey('provider-spend-on'),
          label: 'Spending limit',
          hint: Text(spend.on ? 'On: ${claudeLimitWords(spend.limit)} a month, from the 1st.' : 'Off: ${_page.name} is asked whatever it costs.'),
          control: GlacierSwitch(ariaLabel: 'Spending limit', checked: spend.on, onCheckedChange: (on) => unawaited(spend.setOn(on))),
        ),
        if (spend.on) ...[
          for (final amount in claudeLimitPresets)
            SettingRow(
              key: ValueKey('provider-spend-limit:${amount.toStringAsFixed(0)}'),
              label: '${claudeLimitWords(amount)} a month',
              control: Pick(checked: spend.limit == amount, label: 'Limit to ${claudeLimitWords(amount)} a month', onPress: () => unawaited(spend.setLimit(amount))),
            ),
          SettingRow(
            key: const ValueKey('provider-spend-custom'),
            label: 'Another amount',
            hint: Text(!claudeLimitPresets.contains(spend.limit) ? 'Now ${claudeLimitWords(spend.limit)} a month.' : 'In US dollars.'),
            layout: SettingRowLayout.stacked,
            control: Row(
              children: [
                Expanded(child: PlainField(label: 'Monthly limit in US dollars', controller: _custom, placeholder: '\$15', onSubmitted: () => _setCustomLimit(spend))),
                SizedBox(width: context.tokens.space(2)),
                RowAction(onPress: () => _setCustomLimit(spend), child: const Text('Set')),
              ],
            ),
          ),
          SettingRow(
            key: const ValueKey('provider-spend-warn'),
            label: 'Warn me at 80%',
            hint: const Text('Once a month, the chat says when this month’s spending passes 80% of the limit.'),
            control: GlacierSwitch(ariaLabel: 'Warn me at 80%', checked: spend.warn, onCheckedChange: (on) => unawaited(spend.setWarn(on))),
          ),
        ],
        SettingRow(
          key: const ValueKey('provider-spend-rates'),
          label: 'Prices',
          hint: Text(
            _settings.ratesChosen
                ? '$ratesSaid, as you set them.'
                : _settings.ratesKnown
                    ? '$ratesSaid: ${_page.name}’s published prices for ${_settings.model} when this was written. Set your own if they’ve changed.'
                    : '$ratesSaid: a high guess until you set your model’s, so the limit is reached early rather than late.',
          ),
          layout: SettingRowLayout.stacked,
          control: Row(
            spacing: context.tokens.space(2),
            children: [
              Expanded(child: PlainField(label: 'Input, US dollars a million tokens', controller: _input, placeholder: 'In \$${rates.input}', onSubmitted: _setRates)),
              Expanded(child: PlainField(label: 'Output, US dollars a million tokens', controller: _output, placeholder: 'Out \$${rates.output}', onSubmitted: _setRates)),
              RowAction(onPress: _setRates, child: const Text('Set')),
            ],
          ),
        ),
        SettingRow(
          key: const ValueKey('provider-spend-month'),
          label: month,
          hint: Text(spend.reached ? 'The limit is reached: ${_page.name} isn’t asked until the 1st, or until you raise it.' : 'Counted again from the 1st of each month.'),
          value: RowAction(onPress: () => unawaited(spend.resetCount()), child: const Text('Reset count')),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        final page = _page, settings = _settings;
        return PaneBody(
          children: [
            PaneSection(
              children: [
                PaneHero(
                  glyph: AppIcon(page.icon, size: 22),
                  title: page.custom ? 'Any OpenAI-compatible model' : '${page.name}, with your own key',
                  meta: Text(page.about),
                  status: PaneHeroStatus(settings.ready ? 'Ready: ${settings.model}' : (page.custom ? 'Needs an address and a model' : 'Needs a key')),
                ),
              ],
            ),
            ?widget.setup,
            if (_problem != null) SettingsCallout(child: Text(_problem!)),
            if (_said != null) SettingsCallout(child: Text(_said!)),
            _keyCard(),
            _modelCard(),
            PaneSection(
              title: 'Tools',
              children: [
                SettingRow(
                  key: const ValueKey('provider-tools'),
                  label: 'Let it read and write your notes',
                  hint: Text(
                    settings.toolsRefused(settings.model)
                        ? '${settings.model} said it can’t use tools, so it answers without them.'
                        : 'Ghost.md’s tools, as Claude has them: list, search and read notes, make and change them as you watch, notebooks, tickets and folders. Turn off for a model that has no tools.',
                  ),
                  control: GlacierSwitch(ariaLabel: 'Let it read and write your notes', checked: settings.tools, onCheckedChange: (on) => unawaited(settings.setTools(on))),
                ),
              ],
            ),
            PaneSection(
              title: 'Meeting summaries',
              description: const Text('Each meeting’s summary: what was said, what was decided, and who does what next. Which AI writes them, of those allowed to, is chosen in Settings › AI › Assistant.'),
              footer: Text('On, a meeting’s transcript is sent from this device to ${page.company} under your own key. It goes nowhere else: not through Ghost.md’s server. Off, nothing of a meeting goes to ${page.company}.'),
              children: [
                SettingRow(
                  key: const ValueKey('provider-meetings'),
                  label: 'Write meeting summaries with ${page.name}',
                  hint: Text(settings.meetings ? 'On: ${page.name} may write them up.' : 'Off: ${page.name} never writes them.'),
                  control: GlacierSwitch(ariaLabel: 'Write meeting summaries with ${page.name}', checked: settings.meetings, onCheckedChange: (on) => unawaited(settings.setMeetings(on))),
                ),
              ],
            ),
            _spendCard(settings.spend),
            SettingsFootnote(child: Text('${page.sends} Switched off, this plugin takes ${page.name} off the dock and away from meetings; its key stays until you forget it.')),
          ],
        );
      },
    );
  }
}

/// The row to a provider's page on its card: the model it answers with, or what it still needs.
String providerSummary(AiProviderPage page) {
  final settings = page.settings;
  if (!settings.loaded) unawaited(settings.load());
  if (settings.ready) return settings.model;
  return page.custom ? 'Add the endpoint' : 'Add your API key';
}

/// The icon a page may use where its plugin draws none.
const defaultProviderIcon = Lucide.sparkles;
