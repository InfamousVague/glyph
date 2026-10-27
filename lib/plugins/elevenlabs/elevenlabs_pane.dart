/// The ElevenLabs plugin's page in Settings: the person's key, checked before it is kept (`GET /v1/user`, which
/// spends nothing), Check and Forget once kept, and the month's characters; the voice a voice-over is read in, each
/// to hear first; the model; and a word on what goes to ElevenLabs. Shaped as Lovart's page
/// (lib/plugins/lovart/lovart_pane.dart): Forget asks twice.
///
/// The key is kept in the device's secure store (manifest.dart) and follows the account sealed, with the voice and
/// the model (lib/sync/connections.dart); the page draws again when the plugin's storage or secrets change, so a key
/// that arrives from another device shows as soon as it is read.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../claude/claude_settings.dart' show maskKey;
import '../../settings/kit/settings_kit.dart';
import '../../settings/panes/pane_parts.dart' show armedFor;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../github/plain_field.dart';
import '../host.dart' show onPluginStorage;
import 'client.dart';
import 'elevenlabs_mark.dart';
import 'manifest.dart';
import 'previews.dart';
import 'voice_over.dart' show grouped;
import 'voices.dart';

/// What Settings' search finds on the page.
const List<SettingsFindable> elevenLabsFindable = [
  SettingsFindable('ElevenLabs key', 'api key xi elevenlabs credits characters'),
  SettingsFindable('Voice', 'voice voices narrator read aloud preview listen voice-over'),
  SettingsFindable('Model', 'model eleven v4 multilingual flash quality'),
];

class ElevenLabsPane extends StatefulWidget {
  const ElevenLabsPane({super.key});

  @override
  State<ElevenLabsPane> createState() => _ElevenLabsPaneState();
}

class _ElevenLabsPaneState extends State<ElevenLabsPane> {
  final TextEditingController _key = TextEditingController();
  late final VoidCallback _stop;
  bool _checking = false;
  String? _problem;
  String? _said;
  bool _armed = false;
  Timer? _timer;
  ElevenAccount? _account;

  /// The key the account and voices were last asked with, so a key arriving from another device is asked once.
  String? _askedWith;

  @override
  void initState() {
    super.initState();
    _key.addListener(_redraw);
    _stop = onPluginStorage(_storageMoved);
    elevenLabsPlayer?.addListener(_redraw);
    previewMaking.addListener(_redraw);
    unawaited(host.secrets.warm().then((_) => _askAccount()));
  }

  @override
  void dispose() {
    _stop();
    elevenLabsPlayer?.removeListener(_redraw);
    previewMaking.removeListener(_redraw);
    _key.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _storageMoved() {
    _redraw();
    if (elevenKey() != _askedWith) unawaited(_askAccount());
  }

  /// The month's characters and the person's own voices, for the key kept: asked as the page opens and as a key
  /// is kept. Quiet where either cannot be read: the page says what it has.
  Future<void> _askAccount() async {
    final key = elevenKey();
    _askedWith = key;
    if (key == null) {
      if (mounted && _account != null) setState(() => _account = null);
      return;
    }
    final client = elevenLabsClient();
    if (client == null) return;
    try {
      final account = await client.account();
      if (mounted && _askedWith == key) setState(() => _account = account);
    } on ElevenFailure {
      // A key that may not read its account still reads aloud.
    }
  }

  Future<void> _keep() async {
    final key = _key.text.trim();
    if (key.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _problem = null;
      _said = null;
    });
    final wrong = await ElevenLabsClient(apiKey: key).check();
    if (!mounted) return;
    if (wrong != null && wrong.badKey) {
      setState(() {
        _checking = false;
        _problem = 'ElevenLabs refused that key. Copy it again from your ElevenLabs profile, under API Keys.';
      });
      return;
    }
    await host.secrets.write(apiKeySecret, key);
    if (!mounted) return;
    _key.clear();
    setState(() {
      _checking = false;
      // Kept even when it could not be checked (no connection, or a key that may not read its account): the first
      // voice-over says if it is wrong.
      _said = wrong == null ? 'The key works.' : (wrong.missingPermission ? 'Kept. This key may not read your account, so what is left of the month isn’t shown; voice-overs still work if it may read aloud.' : 'Kept. It could not be checked just now: ${wrong.message}');
    });
    unawaited(_askAccount());
  }

  Future<void> _check() async {
    final client = ElevenLabsClient.kept();
    if (client == null || _checking) return;
    setState(() {
      _checking = true;
      _problem = null;
      _said = null;
    });
    final wrong = await client.check();
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (wrong == null) {
        _said = 'The key works.';
      } else {
        _problem = wrong.message;
      }
    });
    if (wrong == null) unawaited(_askAccount());
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
      _account = null;
    });
    unawaited(host.secrets.write(apiKeySecret, null));
    host.storage.remove(ownVoicesKey);
  }

  Future<void> _preview(VoiceChoice voice) async {
    final player = elevenLabsPlayer;
    final model = chosenModel();
    if (player != null && previewPlaying(voice.id, model.id)) return player.stop();
    final wrong = await playPreview(voiceId: voice.id, name: voice.name, modelId: model.id);
    if (mounted && wrong != null) setState(() => _problem = wrong);
  }

  String _usage(ElevenAccount account) {
    final used = account.used, limit = account.limit;
    if (used == null || limit == null) return 'Your plan: ${account.tier ?? 'unknown'}.';
    final resets = account.resets;
    final when = resets == null ? '' : ' They begin again on ${_day(resets.toLocal())}.';
    return '${grouped(used)} of ${grouped(limit)} credits used this month.$when';
  }

  static const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  static String _day(DateTime day) => '${day.day} ${_months[day.month - 1]}';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final key = elevenKey();
    final model = chosenModel();
    final chosen = chosenVoice();
    final making = previewMaking.value;
    return PaneBody(
      children: [
        if (_problem != null) SettingsCallout(child: Text(_problem!)),
        if (_said != null) SettingsCallout(child: Text(_said!)),
        PaneSection(
          title: 'ElevenLabs key',
          description: const Text('ElevenLabs reads your notes aloud with your own ElevenLabs account: in ElevenLabs, open your profile › API Keys and make one that may use Text to Speech and read Voices. Each voice-over is read with your ElevenLabs credits, a credit a character.'),
          footer: const Text('The key is kept in this device’s secure storage and follows your account, sealed, to your other devices.'),
          children: [
            if (key == null)
              SettingRow(
                key: const ValueKey('elevenlabs-key-new'),
                icon: const ElevenLabsMark(size: 18),
                label: 'API key',
                layout: SettingRowLayout.stacked,
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: t.space(2),
                  children: [
                    PlainField(key: const ValueKey('elevenlabs-key'), label: 'ElevenLabs API key', controller: _key, placeholder: 'sk_…', secret: true, onSubmitted: _keep),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: RowAction(onPress: _keep, disabled: _checking || _key.text.trim().isEmpty, child: Text(_checking ? 'Checking…' : 'Keep it')),
                    ),
                  ],
                ),
              )
            else ...[
              SettingRow(
                key: const ValueKey('elevenlabs-key-kept'),
                icon: const ElevenLabsMark(size: 18),
                label: 'Key kept',
                hint: Text(maskKey(key)),
                value: RowAction(onPress: _check, disabled: _checking, child: Text(_checking ? 'Checking…' : 'Check')),
              ),
              if (_account != null) SettingRow(key: const ValueKey('elevenlabs-usage'), label: 'This month', hint: Text(_usage(_account!))),
              SettingRow(
                key: const ValueKey('elevenlabs-key-forget'),
                label: 'Forget the key',
                hint: const Text('ElevenLabs can no longer be asked from this device until it is added again.'),
                value: RowAction(onPress: _forget, child: Text(_armed ? 'Tap again' : 'Forget')),
              ),
            ],
          ],
        ),
        PaneSection(
          title: 'Voice',
          description: Text('The voice a voice-over is read in; pick another on the note’s menu any time. Play reads a short line in it, made once with your credits (about ${previewLine('Elara').length} characters) and kept on this device.'),
          children: [
            for (final voice in voiceChoices())
              SettingRow(
                key: ValueKey('elevenlabs-voice-${voice.id}'),
                label: voice.name,
                hint: Text(voice.own ? '${voice.line} · Your own voice' : voice.line),
                value: RowAction(
                  onPress: () => unawaited(_preview(voice)),
                  disabled: key == null || (making != null && making != voice.id),
                  child: Text(making == voice.id ? 'Making…' : (previewPlaying(voice.id, model.id) ? 'Stop' : 'Play')),
                ),
                control: Pick(checked: voice.id == chosen.id, label: 'Read voice-overs in ${voice.name}', onPress: () => setVoice(voice.id)),
              ),
          ],
        ),
        PaneSection(
          title: 'Model',
          children: [
            SettingRow(
              key: const ValueKey('elevenlabs-model'),
              label: model.name,
              hint: Text('${model.line}. ${model.creditsPerCharacter < 1 ? 'Half a credit a character.' : 'A credit a character.'}'),
              layout: SettingRowLayout.stacked,
              control: GlacierSegmentedControl(
                ariaLabel: 'Model',
                fullWidth: true,
                size: GlacierSegmentedSize.sm,
                options: [for (final each in elevenModels) GlacierSegmentedOption(value: each.id, label: Text(each.name))],
                value: model.id,
                onValueChange: setModel,
              ),
            ),
          ],
        ),
        const SettingsFootnote(
          child: Text('Only the words of a note you ask a voice-over for go to ElevenLabs, as you read them: not its pictures, files, code or front matter. The sound comes back to this device and is kept in the note, which takes it to your other devices. ElevenLabs keeps what it is sent as its own privacy policy says.'),
        ),
      ],
    );
  }
}
