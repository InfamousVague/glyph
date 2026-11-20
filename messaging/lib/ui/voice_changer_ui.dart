import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/semantic_colors.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../voice/soundboard.dart' show Soundboard;
import '../voice/voice_changer.dart';
import 'common.dart';

/// The Voice changer plugin's rows in its section of Settings, and the pages they open (Matt, 2026-11-20: "build it as
/// a plugin"; lib/voice/voice_changer.dart): the ElevenLabs key, the voice, whether the next messages are changed,
/// background noise, and forgetting the key.

Widget _icon(LucideIcon icon) => AppIcon(icon, size: 18);

/// One row drawn again whenever the voice changer's choices change.
abstract class _Row extends StatelessWidget implements PaneRow {
  const _Row({super.key});
  Widget row(BuildContext context, VoiceChanger c);

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: VoiceChanger.instance, builder: (context, _) => row(context, VoiceChanger.instance));
}

class VoiceChangerKeyRow extends _Row {
  const VoiceChangerKeyRow({super.key});

  @override
  Widget row(BuildContext context, VoiceChanger c) => SettingRow(
        key: const ValueKey('changer-key'),
        icon: _icon(Lucide.keyRound),
        label: 'ElevenLabs key',
        hint: Text(c.hasKey ? 'Kept on this device, in a file only you can read.' : 'Your own, from elevenlabs.io › Developers › API keys. Using it costs what your plan charges.'),
        value: Text(c.hasKey ? 'Ends in ${c.keyEnd}' : 'Add'),
        onPress: () => push<void>(context, (_) => const VoiceChangerKeyScreen()),
      );
}

class VoiceChangerVoiceRow extends _Row {
  const VoiceChangerVoiceRow({super.key});

  @override
  Widget row(BuildContext context, VoiceChanger c) => SettingRow(
        key: const ValueKey('changer-voice'),
        icon: _icon(Lucide.audioLines),
        label: 'Voice',
        hint: Text(c.voice == null ? 'Whose voice your voice messages go out in.' : (c.voice!.about.isEmpty ? 'Your voice messages go out in this voice.' : c.voice!.about)),
        value: Text(c.voice?.name ?? 'Choose'),
        disabledReason: c.hasKey ? null : 'Add your ElevenLabs key first',
        onPress: () => push<void>(context, (_) => const VoiceChangerVoicesScreen()),
      );
}

class VoiceChangerOnRow extends _Row {
  const VoiceChangerOnRow({super.key});

  @override
  Widget row(BuildContext context, VoiceChanger c) => SettingRow(
        key: const ValueKey('changer-on'),
        icon: _icon(Lucide.mic),
        label: 'Change my voice messages',
        hint: Text(!c.ready
            ? 'Once there is a key and a voice.'
            : c.paused
                ? 'Off: they go out in your own voice, and nothing is sent to ElevenLabs.'
                : 'Each one goes to ElevenLabs to be changed before it is sent. If it can\'t be changed it isn\'t sent.'),
        control: GlacierSwitch(checked: c.ready && !c.paused, disabled: !c.ready, ariaLabel: 'Change my voice messages', onCheckedChange: (v) => c.setPaused(!v)),
      );
}

class VoiceChangerCleanRow extends _Row {
  const VoiceChangerCleanRow({super.key});

  @override
  Widget row(BuildContext context, VoiceChanger c) => SettingRow(
        key: const ValueKey('changer-clean'),
        icon: _icon(Lucide.ear),
        label: 'Take out background noise',
        hint: const Text('The room behind you is removed before the voice is changed.'),
        control: GlacierSwitch(checked: c.clean, ariaLabel: 'Take out background noise', onCheckedChange: c.setClean),
      );
}

class VoiceChangerForgetRow extends _Row {
  const VoiceChangerForgetRow({super.key});

  @override
  Widget row(BuildContext context, VoiceChanger c) => SettingRow(
        key: const ValueKey('changer-forget'),
        icon: _icon(Lucide.trash2),
        label: 'Forget the key',
        labelColor: c.hasKey ? context.tokens.danger : null,
        hint: const Text('Takes the key, the voice and the list of voices off this device. The key itself stays in your ElevenLabs account until you delete it there.'),
        disabled: !c.hasKey,
        onPress: () => showChoices(context, title: 'Forget your ElevenLabs key on this device?', choices: [
          Choice('Forget it', Lucide.trash2, () {
            c.forget();
            toast(context, 'Forgotten. Voice messages go out in your own voice.');
          }, danger: true),
        ]),
      );
}

/// Pasting the key. It is tried against ElevenLabs before it is kept, and never shown again.
class VoiceChangerKeyScreen extends StatefulWidget {
  const VoiceChangerKeyScreen({super.key});

  @override
  State<VoiceChangerKeyScreen> createState() => _VoiceChangerKeyScreenState();
}

class _VoiceChangerKeyScreenState extends State<VoiceChangerKeyScreen> {
  final _key = TextEditingController();
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || _key.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    final why = await VoiceChanger.instance.setKey(_key.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = why;
    });
    if (why != null) return;
    _key.clear();
    final n = VoiceChanger.instance.voices.length;
    toast(context, 'Key kept. $n ${n == 1 ? 'voice' : 'voices'} to choose from.');
    // Straight on to choosing a voice, where none is chosen yet.
    final nav = Navigator.of(context);
    if (VoiceChanger.instance.voice == null) {
      nav.pushReplacement(PageRouteBuilder<void>(pageBuilder: (c, _, _) => const VoiceChangerVoicesScreen()));
    } else {
      nav.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final had = VoiceChanger.instance.hasKey;
    final pad = EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom);
    return GhostPage(
      title: 'ElevenLabs key',
      body: SettingsPaneScope(
        finder: SettingsFinder(),
        child: ListView(padding: pad, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
          SettingsCallout(
            icon: AppIcon(Lucide.info, size: 18),
            child: const Text('With this key, each voice message you send while Voice changer is on goes from this device to ElevenLabs to be changed, and counts against your ElevenLabs plan. Ghost\'s servers never see the key or the recording.'),
          ),
          SizedBox(height: t.space(4)),
          PaneSection(
            title: had ? 'A new key' : 'Your key',
            description: const Text('At elevenlabs.io, open Developers › API keys and create one. If you restrict it, let it use Voice Changer and read Voices.'),
            children: [
              SettingRowBox(
                child: GlacierInput(
                  key: const ValueKey('changer-key-field'),
                  controller: _key,
                  type: GlacierInputType.password,
                  placeholder: 'sk_…',
                  ariaLabel: 'ElevenLabs API key',
                  autoCorrect: false,
                  autoCapitalize: TextCapitalization.none,
                  size: GlacierFieldSize.md,
                  onChange: (_) => setState(() {}),
                  onSubmitted: (_) => _save(),
                ),
              ),
              SettingRow(key: const ValueKey('changer-key-save'), icon: _icon(Lucide.check), label: _busy ? 'Asking ElevenLabs…' : (had ? 'Use this key instead' : 'Keep this key'), disabled: _busy || _key.text.trim().isEmpty, onPress: _save),
            ],
          ),
          if (_problem != null)
            Padding(
              padding: EdgeInsets.only(top: t.space(3)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: EdgeInsets.only(right: t.space(2), top: 2), child: AppIcon(Lucide.triangleAlert, size: 16, color: t.danger)),
                Expanded(child: Text(_problem!, key: const ValueKey('changer-key-problem'), style: pageText(t, t.fontSize('sm'), color: t.danger, height: 1.4))),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// The account's voices: one chosen with a tap, a sample of each to hear first.
class VoiceChangerVoicesScreen extends StatelessWidget {
  const VoiceChangerVoicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VoiceChanger.instance,
      builder: (context, _) {
        final t = context.tokens;
        final c = VoiceChanger.instance;
        final pad = EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom);
        return GhostPage(
          title: 'Voice',
          actions: [
            IconTap(
              icon: Lucide.refreshCw,
              label: 'Read my voices again',
              onPressed: c.busy
                  ? null
                  : () async {
                      final why = await c.refresh();
                      if (context.mounted) toast(context, why ?? '${c.voices.length} voices', tone: why == null ? GlacierToastTone.neutral : GlacierToastTone.danger);
                    },
            ),
          ],
          body: SettingsPaneScope(
            finder: SettingsFinder(),
            child: ListView(padding: pad, children: [
              PaneSection(
                title: 'Your ElevenLabs voices',
                description: const Text('ElevenLabs\' own and any you made or saved there. Your voice messages keep how you said them, in the voice you choose.'),
                children: [
                  if (c.voices.isEmpty) const SettingRowBox(child: Text('No voices yet. Add your key, or read them again.')),
                  for (final v in c.voices)
                    SettingRow(
                      key: ValueKey('changer-voice-${v.id}'),
                      icon: _icon(v == c.voice ? Lucide.check : Lucide.audioLines),
                      label: v.name,
                      hint: v.about.isEmpty ? null : Text(v.about),
                      control: v.preview == null ? null : IconTap(icon: Lucide.play, label: 'Hear ${v.name}', onPressed: () => Soundboard.playClip(v.preview!, 1)),
                      onPress: () {
                        c.choose(v);
                        toast(context, 'Your voice messages go out as ${v.name}');
                        Navigator.of(context).maybePop();
                      },
                    ),
                ],
              ),
            ]),
          ),
        );
      },
    );
  }
}
