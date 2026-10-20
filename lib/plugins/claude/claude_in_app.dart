/// The Claude plugin's "In the app" half (docs/CLAUDE_APP.md, "The key"): the person's Anthropic API key, kept on
/// this device only, the model, and the "Ask Claude" note's switch. Its cards stand on the plugin's page
/// (claude_pane.dart) above the connector's. They were Settings › Ask Claude, a page of their own, until the app's
/// Claude became the plugin's (Matt, 2026-10-17: "Ask Claude and other integrations should be shipped as plugins").
/// The app's own; the web app has none of it.
///
/// A key is checked before it is kept (one small read of the API, lib/claude/messages_api.dart [ClaudeApi.check]),
/// so a key mistyped is said at once rather than at the first ask. Forget asks twice.
///
/// On a phone, a fourth card: **Phone assistant** (Matt, 2026-10-17: "add the setting back in to be able to bind
/// ghost as the agent on the phone"). Its switch is the one Settings › Developer has had (lib/core/wip.dart
/// [switchVoiceAssistant]): on, Ghost.md is offered to Android as a digital assistant, and Android's Default digital
/// assistant app screen is opened at once, since the app cannot pick itself; a person picks it there. Its second row
/// opens that screen again and says whether Ghost.md is the one chosen, read again each time the app comes back.
///
/// **Spending limit** (Matt, 2026-10-20: "Also enable setting spending limits in claude settings in the app";
/// lib/claude/claude_spend.dart): off by default; on, a monthly amount in US dollars ($5, $10, $25, $50 or one typed),
/// counted again from the 1st, and "Warn me at 80%". The month so far is shown under it with Reset count. The count
/// is this device's, from what Claude reports for each request, and the card says so.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart' show AppIcon, Lucide;
import '../../claude/claude_settings.dart';
import '../../claude/claude_spend.dart';
import '../../claude/messages_api.dart';
import '../../core/wip.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/panes/pane_parts.dart' show armedFor;
import '../../settings/settings_search.dart';
import '../github/plain_field.dart';

/// What Settings' search finds of the app's Claude on the plugin's page: its cards, and the key's row.
const List<SettingsFindable> claudeInAppFindable = [
  SettingsFindable('Ask Claude', 'anthropic claude ask chat dock in the app'),
  SettingsFindable('API key', 'anthropic api key claude sk-ant console token'),
  SettingsFindable('Model', 'claude sonnet opus haiku model'),
  SettingsFindable('Spending limit', 'spending limit budget cost money dollars monthly price usage spend cap warn'),
  SettingsFindable('Ask Claude note', 'inbox ask claude requests to-do automatic'),
  SettingsFindable('Phone assistant', 'assistant digital default side key gesture voice talk microphone bind gemini bixby'),
];

/// What the Phone assistant card reaches (lib/core/wip.dart): the phone's own unless a test gives others.
@immutable
class PhoneAssistantSeam {
  const PhoneAssistantSeam({this.on, this.set, this.choose, this.chosen});

  /// Whether this device's switch is on.
  final ValueListenable<bool>? on;
  final Future<void> Function(bool on)? set;

  /// Opens Android's Default digital assistant app screen.
  final Future<bool> Function()? choose;

  /// Whether Ghost.md is the phone's assistant now.
  final Future<bool> Function()? chosen;

  ValueListenable<bool> get _on => on ?? wipAssistant;
  Future<void> _set(bool next) => (set ?? switchVoiceAssistant)(next);
  Future<bool> _choose() => (choose ?? openAssistantChooser)();
  Future<bool> _chosen() => (chosen ?? isPhoneAssistant)();
}

/// The row to the plugin's page on its card: the model Claude answers with, or that a key is wanted.
String claudeSummary([ClaudeSettings? settings]) {
  final claude = settings ?? claudeSettings;
  if (!claude.loaded) unawaited(claude.load());
  return claude.hasKey ? claudeModelLabel(claude.model) : 'Add your API key';
}

/// The three cards, Ask Claude (the key), Model and Ask Claude note, a page's gap apart.
class ClaudeInApp extends StatefulWidget {
  const ClaudeInApp({super.key, this.settings, this.assistant = const PhoneAssistantSeam(), this.phone});

  /// The settings to read and write; the app's own when null.
  final ClaudeSettings? settings;

  /// What the Phone assistant card reaches.
  final PhoneAssistantSeam assistant;

  /// Whether the Phone assistant card is drawn: on Android, where there is an assistant to be, unless told.
  final bool? phone;

  @override
  State<ClaudeInApp> createState() => _ClaudeInAppState();
}

class _ClaudeInAppState extends State<ClaudeInApp> {
  final TextEditingController _typed = TextEditingController();

  /// A limit of the person's own, typed.
  final TextEditingController _custom = TextEditingController();
  bool _checking = false;
  String? _problem;
  String? _said;
  bool _armed = false;
  Timer? _timer;

  /// Whether Ghost.md is the phone's assistant, as last asked; null before the first answer.
  bool? _chosen;
  AppLifecycleListener? _life;

  ClaudeSettings get _settings => widget.settings ?? claudeSettings;
  bool get _phone => widget.phone ?? defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    unawaited(_settings.load());
    if (_phone) {
      unawaited(_readChosen());
      // Back from Android's screen: whether it was picked there is read again.
      _life = AppLifecycleListener(onResume: () => unawaited(_readChosen()));
    }
  }

  @override
  void dispose() {
    _typed.dispose();
    _custom.dispose();
    _timer?.cancel();
    _life?.dispose();
    super.dispose();
  }

  Future<void> _readChosen() async {
    final chosen = await widget.assistant._chosen();
    if (mounted && chosen != _chosen) setState(() => _chosen = chosen);
  }

  /// The switch: on, Ghost.md is offered as an assistant and Android's screen is opened to pick it.
  Future<void> _switchAssistant(bool on) async {
    await widget.assistant._set(on);
    if (on && !(_chosen ?? false)) await widget.assistant._choose();
  }

  Future<void> _keep() async {
    final key = _typed.text.trim();
    if (key.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _problem = null;
      _said = null;
    });
    final wrong = await ClaudeApi(key: key).check();
    if (!mounted) return;
    if (wrong != null && wrong.badKey) {
      setState(() {
        _checking = false;
        _problem = 'Anthropic refused that key. Copy it again from the Claude Console.';
      });
      return;
    }
    await _settings.setKey(key);
    if (!mounted) return;
    _typed.clear();
    setState(() {
      _checking = false;
      // Kept even when it could not be checked (no connection): it is checked again at the first ask.
      _said = wrong == null ? 'The key works.' : 'Kept. It could not be checked just now: ${wrong.message}';
    });
  }

  Future<void> _check() async {
    final key = _settings.key;
    if (key == null || _checking) return;
    setState(() {
      _checking = true;
      _problem = null;
      _said = null;
    });
    final wrong = await ClaudeApi(key: key).check();
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (wrong == null) {
        _said = 'The key works.';
      } else {
        _problem = wrong.message;
      }
    });
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
      _said = null;
      _problem = null;
    });
    unawaited(_settings.setKey(null));
  }

  /// The limit typed: dollars, a `\$` and commas allowed.
  void _setCustom() {
    final typed = double.tryParse(_custom.text.replaceAll(RegExp(r'[\s$,]'), ''));
    if (typed == null || !typed.isFinite || typed < 0.01) {
      setState(() {
        _said = null;
        _problem = 'Type the monthly limit in US dollars, such as 15 or 12.50.';
      });
      return;
    }
    final cents = (typed * 100).round() / 100;
    _custom.clear();
    setState(() => _problem = null);
    unawaited(_settings.spend.setLimit(cents));
  }

  Widget _spendCard(BuildContext context, ClaudeSpend spend) {
    final spent = spend.spent, requests = spend.requests;
    final asked = '$requests request${requests == 1 ? '' : 's'}';
    final month = spend.on ? 'This month: ${claudeDollars(spent)} of ${claudeLimitWords(spend.limit)} · $asked' : 'This month: ${claudeDollars(spent)} · $asked';
    final custom = !claudeLimitPresets.contains(spend.limit);
    return PaneSection(
      title: 'Spending limit',
      description: const Text('A monthly limit on what Claude in the app spends with your key, in US dollars. Once it is reached, Claude isn’t asked until the 1st of next month or until you raise it; meeting write-ups wait for then.'),
      footer: const Text('Counted on this device from what Claude reports for each request; other apps or devices using the same key aren’t included.'),
      children: [
        SettingRow(
          key: const ValueKey('claude-spend-on'),
          label: 'Spending limit',
          hint: Text(spend.on ? 'On: ${claudeLimitWords(spend.limit)} a month, from the 1st.' : 'Off: Claude is asked whatever it costs.'),
          control: GlacierSwitch(ariaLabel: 'Spending limit', checked: spend.on, onCheckedChange: (on) => unawaited(spend.setOn(on))),
        ),
        if (spend.on) ...[
          for (final amount in claudeLimitPresets)
            SettingRow(
              key: ValueKey('claude-spend-limit:${amount.toStringAsFixed(0)}'),
              label: '${claudeLimitWords(amount)} a month',
              control: Pick(checked: spend.limit == amount, label: 'Limit to ${claudeLimitWords(amount)} a month', onPress: () => unawaited(spend.setLimit(amount))),
            ),
          SettingRow(
            key: const ValueKey('claude-spend-custom'),
            label: 'Another amount',
            hint: Text(custom ? 'Now ${claudeLimitWords(spend.limit)} a month.' : 'In US dollars.'),
            layout: SettingRowLayout.stacked,
            control: Row(
              children: [
                Expanded(child: PlainField(label: 'Monthly limit in US dollars', controller: _custom, placeholder: '\$15', onSubmitted: _setCustom)),
                SizedBox(width: context.tokens.space(2)),
                RowAction(onPress: _setCustom, child: const Text('Set')),
              ],
            ),
          ),
          SettingRow(
            key: const ValueKey('claude-spend-warn'),
            label: 'Warn me at 80%',
            hint: const Text('Once a month, the chat says when this month’s spending passes 80% of the limit.'),
            control: GlacierSwitch(ariaLabel: 'Warn me at 80%', checked: spend.warn, onCheckedChange: (on) => unawaited(spend.setWarn(on))),
          ),
        ],
        SettingRow(
          key: const ValueKey('claude-spend-month'),
          label: month,
          hint: Text(spend.reached ? 'The limit is reached: Claude isn’t asked until the 1st, or until you raise it.' : 'Counted again from the 1st of each month.'),
          value: RowAction(onPress: () => unawaited(spend.resetCount()), child: const Text('Reset count')),
        ),
      ],
    );
  }

  Widget _assistantCard(BuildContext context) {
    final chosen = _chosen;
    return ValueListenableBuilder<bool>(
      valueListenable: widget.assistant._on,
      builder: (context, on, _) => PaneSection(
        title: 'Phone assistant',
        description: const Text(
          'Talk to Claude from anywhere: hold the side key, or use your phone’s assistant gesture, and Ghost.md listens, shows Claude thinking, then opens the note Claude writes in. Without an API key on this device, it records a voice note instead.',
        ),
        footer: const Text('Ghost.md cannot make itself the assistant: Android asks you to pick it. The microphone is only open while you talk, never waiting for a word.'),
        children: [
          SettingRow(
            key: const ValueKey('claude-assistant'),
            icon: const AppIcon(Lucide.mic, size: 20),
            label: 'Ghost.md as the phone’s assistant',
            hint: const Text('Switched on, the screen to choose it opens: pick Ghost.md under Default digital assistant app. Open Ghost.md again after switching it.'),
            control: GlacierSwitch(ariaLabel: 'Ghost.md as the phone’s assistant', checked: on, onCheckedChange: (next) => unawaited(_switchAssistant(next))),
          ),
          if (on)
            SettingRow(
              key: const ValueKey('claude-assistant-choose'),
              label: 'Default digital assistant app',
              hint: Text(chosen == true ? 'Ghost.md is your phone’s assistant.' : 'Not chosen yet. Pick Ghost.md on Android’s screen.'),
              value: RowAction(onPress: () => unawaited(widget.assistant._choose()), child: Text(chosen == true ? 'Change' : 'Choose')),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        final settings = _settings;
        final key = settings.key;
        // Cards among the page's own, as far apart as PaneBody sets them.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: context.tokens.space(4),
          children: [
            if (_problem != null) SettingsCallout(child: Text(_problem!)),
            if (_said != null) SettingsCallout(child: Text(_said!)),
            PaneSection(
              title: 'Ask Claude',
              description: const Text(
                'Ask Claude from the dock on any page or the command bar, and it reads, makes and changes your notes, typing into the note as you watch. It uses your own Anthropic API key: what you ask, and the notes Claude reads to answer, go from this device to Anthropic, and Anthropic bills the key.',
              ),
              footer: const Text('The key is kept on this device alone, in its secure storage. It is never synced; give each device its own. Make one at console.anthropic.com.'),
              children: [
                if (key == null)
                  SettingRow(
                    key: const ValueKey('claude-key-new'),
                    label: 'API key',
                    layout: SettingRowLayout.stacked,
                    control: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PlainField(label: 'Anthropic API key', controller: _typed, placeholder: 'sk-ant-…', secret: true, onSubmitted: _keep),
                        SizedBox(height: context.tokens.space(2)),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: RowAction(onPress: _keep, disabled: _checking, child: Text(_checking ? 'Checking…' : 'Keep it')),
                        ),
                      ],
                    ),
                  )
                else ...[
                  SettingRow(
                    key: const ValueKey('claude-key-kept'),
                    label: 'API key',
                    hint: Text('A key is kept: ${maskKey(key)}'),
                    value: RowAction(onPress: _check, disabled: _checking, child: Text(_checking ? 'Checking…' : 'Check')),
                  ),
                  SettingRow(
                    key: const ValueKey('claude-key-forget'),
                    label: 'Forget the key',
                    hint: const Text('Claude can no longer be asked on this device until a key is added again.'),
                    value: RowAction(onPress: _forget, child: Text(_armed ? 'Tap again' : 'Forget')),
                  ),
                ],
              ],
            ),
            PaneSection(
              title: 'Model',
              description: const Text('Which Claude answers. Each is billed to the key at its own price.'),
              children: [
                for (final model in claudeModels)
                  SettingRow(
                    key: ValueKey('claude-model:${model.id}'),
                    label: model.name,
                    hint: Text(model.about),
                    control: Pick(checked: settings.model == model.id, label: 'Use ${model.name}', onPress: () => unawaited(settings.setModel(model.id))),
                  ),
              ],
            ),
            _spendCard(context, settings.spend),
            PaneSection(
              title: 'Ask Claude note',
              children: [
                SettingRow(
                  key: const ValueKey('claude-inbox'),
                  label: 'Do requests as they are written',
                  hint: const Text('A to-do written in your “Ask Claude” note is done a few seconds after you stop typing it: Claude does it while you watch, writes what it did under it, and ticks it.'),
                  control: GlacierSwitch(ariaLabel: 'Do requests as they are written', checked: settings.inbox, onCheckedChange: (on) => unawaited(settings.setInbox(on))),
                ),
              ],
            ),
            if (_phone) _assistantCard(context),
          ],
        );
      },
    );
  }
}
