import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaDeviceInfo;
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../kit/settings_kit.dart';
import '../voice/channels.dart';
import '../voice/rtc.dart';
import '../voice/voice_settings.dart';
import 'common.dart';

/// Settings › Voice and video (Matt, 2026-11-15: "voice settings to change all kinds of things like bitrates and sound
/// input devices etc etc"): the microphone and the speaker, the sound's bit rate and stereo, what is done to the
/// microphone's sound, and the picture's quality. A device chosen is used in the call there is at once; the rest from
/// the next call joined.
class VoicePane extends StatefulWidget {
  const VoicePane({super.key});

  @override
  State<VoicePane> createState() => _VoicePaneState();
}

class _VoicePaneState extends State<VoicePane> {
  List<MediaDeviceInfo> _inputs = const [], _outputs = const [];

  @override
  void initState() {
    super.initState();
    _devices();
  }

  Future<void> _devices() async {
    final inputs = await RtcMedia.devices('audioinput'), outputs = await RtcMedia.devices('audiooutput');
    if (!mounted) return;
    setState(() {
      _inputs = inputs;
      _outputs = outputs;
    });
  }

  static String _name(List<MediaDeviceInfo> list, String id) {
    if (id.isEmpty) return 'The system\'s own';
    for (final d in list) {
      if (d.deviceId == id) return d.label.isEmpty ? 'A device' : d.label;
    }
    return 'Not connected now';
  }

  void _pick(String title, List<MediaDeviceInfo> list, String current, Future<void> Function(String id) use) {
    showChoices(context, title: title, choices: [
      Choice(current.isEmpty ? '✓  The system\'s own' : 'The system\'s own', Lucide.laptop, () => use('').then((_) => setState(() {}))),
      for (final d in list)
        Choice('${d.deviceId == current ? '✓  ' : ''}${d.label.isEmpty ? 'A device' : d.label}', Lucide.mic, () => use(d.deviceId).then((_) => setState(() {}))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.of(context);
    final v = VoiceSettings.of(app);
    final voice = Voice.instance;
    Widget icon(LucideIcon i) => AppIcon(i, size: 18);
    final gap = SizedBox(height: context.tokens.space(6));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PaneSection(
        title: 'Devices',
        description: const Text('Used in a call at once. The system\'s own follows whatever the device uses.'),
        children: [
          SettingRow(icon: icon(Lucide.mic), label: 'Microphone', value: Text(_name(_inputs, v.input)), onPress: () => _pick('Microphone', _inputs, v.input, voice.useInput)),
          SettingRow(icon: icon(LucideMore.headphones), label: 'Speaker or headset', value: Text(_name(_outputs, v.output)), onPress: () => _pick('Speaker or headset', _outputs, v.output, voice.useOutput)),
        ],
      ),
      gap,
      PaneSection(
        title: 'Sound',
        description: const Text('Opus, the codec calls use. 510 kb/s stereo is the most it carries, and as close to the microphone as a live call gets.'),
        children: [
          SettingRow(
            icon: icon(Lucide.audioLines),
            label: 'Bit rate',
            value: Text('${v.audioKbps} kb/s'),
            onPress: () => showChoices(context, title: 'Bit rate', choices: [
              for (final k in VoiceSettings.kbpsChoices) Choice('${k == v.audioKbps ? '✓  ' : ''}${VoiceSettings.kbpsLabel(k)}', Lucide.audioLines, () => app.set('voice_kbps', '$k')),
            ]),
          ),
          SettingRow(icon: icon(LucideMore.headphones), label: 'Stereo', hint: const Text('Two channels; off sends one.'), control: GlacierSwitch(checked: v.stereo, onCheckedChange: (on) => app.setFlag('voice_stereo', on), ariaLabel: 'Stereo')),
          SettingRow(icon: icon(Lucide.volume2), label: 'Echo cancellation', hint: const Text('Keeps your speaker out of your microphone. Off for headphones only.'), control: GlacierSwitch(checked: v.echo, onCheckedChange: (on) => app.setFlag('voice_echo', on), ariaLabel: 'Echo cancellation')),
          SettingRow(icon: icon(Lucide.waves), label: 'Noise suppression', hint: const Text('Quiets steady noise: fans, traffic. Off sends the room as it is.'), control: GlacierSwitch(checked: v.noise, onCheckedChange: (on) => app.setFlag('voice_noise', on), ariaLabel: 'Noise suppression')),
          SettingRow(icon: icon(Lucide.slidersHorizontal), label: 'Automatic gain', hint: const Text('Evens out how loud you are. Off keeps your own level.'), control: GlacierSwitch(checked: v.gain, onCheckedChange: (on) => app.setFlag('voice_gain', on), ariaLabel: 'Automatic gain')),
        ],
      ),
      gap,
      PaneSection(
        title: 'Video',
        description: const Text('The most a picture is sent at. With more people in a call each copy is smaller, so it keeps moving.'),
        children: [
          SettingRow(
            icon: icon(Lucide.video),
            label: 'Quality',
            value: Text('${v.video}p'),
            onPress: () => showChoices(context, title: 'Video quality', choices: [
              for (final q in VoiceSettings.videoChoices)
                Choice('${q == v.video ? '✓  ' : ''}${q}p · up to ${switch (q) { 480 => '1.5', 720 => '4', _ => '12' }} Mb/s', Lucide.video, () => app.set('voice_video', '$q')),
            ]),
          ),
        ],
      ),
      if (voice.session != null) ...[gap, SettingsCallout(child: const Text('Sound and video changes apply from the next call you join. Devices change now.'))],
    ]);
  }
}
