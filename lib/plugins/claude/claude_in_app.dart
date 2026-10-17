/// The Claude plugin's "In the app" half (docs/CLAUDE_APP.md, "The key"): the person's Anthropic API key, kept on
/// this device only, the model, and the "Ask Claude" note's switch. Its cards stand on the plugin's page
/// (claude_pane.dart) above the connector's. They were Settings › Ask Claude, a page of their own, until the app's
/// Claude became the plugin's (Matt, 2026-10-17: "Ask Claude and other integrations should be shipped as plugins").
/// The app's own; the web app has none of it.
///
/// A key is checked before it is kept (one small read of the API, lib/claude/messages_api.dart [ClaudeApi.check]),
/// so a key mistyped is said at once rather than at the first ask. Forget asks twice.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../claude/claude_settings.dart';
import '../../claude/messages_api.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/panes/pane_parts.dart' show armedFor;
import '../../settings/settings_search.dart';
import '../github/plain_field.dart';

/// What Settings' search finds of the app's Claude on the plugin's page: its cards, and the key's row.
const List<SettingsFindable> claudeInAppFindable = [
  SettingsFindable('Ask Claude', 'anthropic claude ask chat dock in the app'),
  SettingsFindable('API key', 'anthropic api key claude sk-ant console token'),
  SettingsFindable('Model', 'claude sonnet opus haiku model'),
  SettingsFindable('Ask Claude note', 'inbox ask claude requests to-do automatic'),
];

/// The row to the plugin's page on its card: the model Claude answers with, or that a key is wanted.
String claudeSummary([ClaudeSettings? settings]) {
  final claude = settings ?? claudeSettings;
  if (!claude.loaded) unawaited(claude.load());
  return claude.hasKey ? claudeModelLabel(claude.model) : 'Add your API key';
}

/// The three cards, Ask Claude (the key), Model and Ask Claude note, a page's gap apart.
class ClaudeInApp extends StatefulWidget {
  const ClaudeInApp({super.key, this.settings});

  /// The settings to read and write; the app's own when null.
  final ClaudeSettings? settings;

  @override
  State<ClaudeInApp> createState() => _ClaudeInAppState();
}

class _ClaudeInAppState extends State<ClaudeInApp> {
  final TextEditingController _typed = TextEditingController();
  bool _checking = false;
  String? _problem;
  String? _said;
  bool _armed = false;
  Timer? _timer;

  ClaudeSettings get _settings => widget.settings ?? claudeSettings;

  @override
  void initState() {
    super.initState();
    unawaited(_settings.load());
  }

  @override
  void dispose() {
    _typed.dispose();
    _timer?.cancel();
    super.dispose();
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
          ],
        );
      },
    );
  }
}
