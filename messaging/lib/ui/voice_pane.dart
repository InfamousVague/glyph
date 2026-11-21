import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaDeviceInfo;
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../kit/settings_kit.dart';
import '../kit/semantic_colors.dart';
import '../kit/settings_type.dart';
import '../voice/channels.dart';
import '../voice/rtc.dart';
import '../voice/voice_fx.dart';
import '../voice/ducking.dart';
import '../voice/voice_settings.dart';
import 'voice_screen.dart' show VolumeSlider;
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
    await VoiceFx.modes();
    _asked = true;
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

  /// DeepFilterNet is offered where this device runs it; RNNoise always (WebRTC's own stands in where it cannot run).
  bool _offered(NoiseMode m) => m != NoiseMode.deepfilter || VoiceFx.available.contains(m);

  String _noiseName(VoiceSettings v) {
    final used = v.noiseOn(VoiceFx.available);
    return used == v.noise || !_asked ? v.noise.label : '${v.noise.label} (Standard here)';
  }

  bool _asked = false;

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
    // Each change is kept, and what can change in a call there is changes now (Voice.settingsChanged).
    void set(String key, String value) {
      app.set(key, value);
      unawaited(voice.settingsChanged());
    }

    void flag(String key, bool on) {
      app.setFlag(key, on);
      unawaited(voice.settingsChanged());
    }

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
      const AudioTest(),
      gap,
      PaneSection(
        title: 'Volume',
        description: const Text('Over 100% is boosted: your microphone louder than it picks up, or everyone louder than the device plays.'),
        children: [
          _Level(icon: icon(Lucide.mic), label: 'Microphone', value: v.inputVolume, onChanged: (p) => set('voice_in_volume', '$p')),
          _Level(icon: icon(Lucide.volume2), label: 'Output', value: v.outputVolume, onChanged: (p) => set('voice_out_volume', '$p')),
        ],
      ),
      gap,
      PaneSection(
        title: 'Sound',
        description: const Text('Opus, the codec calls use. 510 kb/s stereo is the most it carries: past what an ear can tell from the microphone itself. FLAC is not something a live call can carry.'),
        children: [
          SettingRow(
            icon: icon(LucideMore.music),
            label: 'Music mode',
            hint: const Text('The microphone as it is, for music: no echo cancellation, noise suppression or gain, 510 kb/s stereo at a constant rate. Use headphones.'),
            control: GlacierSwitch(checked: v.music, onCheckedChange: (on) => flag('voice_music', on), ariaLabel: 'Music mode'),
          ),
          SettingRow(
            icon: icon(Lucide.waves),
            label: 'Noise suppression',
            value: Text(v.music ? 'Off in Music mode' : _noiseName(v)),
            disabled: v.music,
            onPress: () => showChoices(context, title: 'Noise suppression', choices: [
              for (final m in NoiseMode.values)
                if (_offered(m))
                  Choice('${m == v.noise ? '✓  ' : ''}${m.label} · ${m.hint}', Lucide.waves, () => set('voice_noise_mode', m.name)),
            ]),
          ),
          SettingRow(
            icon: icon(Lucide.audioLines),
            label: 'Bit rate',
            value: Text(v.music ? '510 kb/s in Music mode' : '${v.audioKbps} kb/s'),
            disabled: v.music,
            onPress: () => showChoices(context, title: 'Bit rate', choices: [
              for (final k in VoiceSettings.kbpsChoices) Choice('${k == v.audioKbps ? '✓  ' : ''}${VoiceSettings.kbpsLabel(k)}', Lucide.audioLines, () => set('voice_kbps', '$k')),
            ]),
          ),
          SettingRow(icon: icon(LucideMore.headphones), label: 'Stereo', hint: const Text('Two channels; off sends one.'), disabled: v.music, control: GlacierSwitch(checked: v.sendStereo, disabled: v.music, onCheckedChange: (on) => flag('voice_stereo', on), ariaLabel: 'Stereo')),
          SettingRow(icon: icon(Lucide.volume2), label: 'Echo cancellation', hint: const Text('Keeps your speaker out of your microphone. Off for headphones only.'), disabled: v.music, control: GlacierSwitch(checked: v.useEcho, disabled: v.music, onCheckedChange: (on) => flag('voice_echo', on), ariaLabel: 'Echo cancellation')),
          SettingRow(icon: icon(Lucide.slidersHorizontal), label: 'Automatic gain', hint: const Text('Evens out how loud you are. Off keeps your own level.'), disabled: v.music, control: GlacierSwitch(checked: v.useGain, disabled: v.music, onCheckedChange: (on) => flag('voice_gain', on), ariaLabel: 'Automatic gain')),
          if (!kIsWeb && Platform.isWindows)
            SettingRow(
              icon: icon(LucideMore.volumeX),
              label: 'Lower other sounds in calls',
              hint: const Text('Windows turns everything else on the computer down while you talk. Off keeps music, games and videos as loud as they were.'),
              control: GlacierSwitch(
                checked: v.duckOthers,
                onCheckedChange: (on) {
                  flag('voice_duck_others', on);
                  unawaited(Ducking.apply(duckOthers: on));
                },
                ariaLabel: 'Lower other sounds in calls',
              ),
            ),
        ],
      ),
      gap,
      PaneSection(
        title: 'Video',
        description: const Text('The most a picture is sent at. With more people in a call each copy is smaller, so it keeps moving. 4K needs a camera that films it, and a fast connection.'),
        children: [
          SettingRow(
            icon: icon(Lucide.video),
            label: 'Quality',
            value: Text(VoiceSettings.videoLabel(v.video)),
            onPress: () => showChoices(context, title: 'Video quality', choices: [
              for (final q in VoiceSettings.videoChoices)
                Choice('${q == v.video ? '✓  ' : ''}${VoiceSettings.videoLabel(q)} · up to ${switch (q) { 480 => '1.5', 720 => '4', 1080 => '12', _ => '25' }} Mb/s', Lucide.video, () => set('voice_video', '$q')),
            ]),
          ),
        ],
      ),
      if (voice.session != null) ...[gap, SettingsCallout(child: const Text('Volume, noise suppression and devices change now; the rest from the next call you join.'))],
    ]);
  }
}

/// A volume, 0 to 200%, with its number: over 100 is boosted.
class _Level extends StatelessWidget {
  const _Level({required this.icon, required this.label, required this.value, required this.onChanged});
  final Widget icon;
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SettingRowBox(
      child: Row(children: [
        // The same chip as every other row's (SettingRow).
        Container(
          width: t.lenOf('1.85rem'),
          height: t.lenOf('1.85rem'),
          decoration: BoxDecoration(color: settingsHueWash(t), borderRadius: BorderRadius.circular(t.lenOf('0.55rem'))),
          alignment: Alignment.center,
          child: SizedBox.square(dimension: t.lenOf('1.05rem'), child: FittedBox(child: IconTheme.merge(data: IconThemeData(color: settingsHue(t)), child: icon))),
        ),
        SizedBox(width: t.space(3)),
        SizedBox(width: t.lenOf('6.5rem'), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'medium', color: t.color('app-ink')))),
        Expanded(child: VolumeSlider(value: value / 100, max: VoiceSettings.maxVolume / 100, label: label, onChanged: (x) => onChanged((x * 100).round()))),
        SizedBox(width: t.space(3)),
        SizedBox(
          width: t.lenOf('3.5rem'),
          child: Text('$value%', textAlign: TextAlign.right, style: pageText(t, t.fontSize('sm'), weight: value > 100 ? 'bold' : 'regular', color: value > 100 ? t.colorOf('#e08a1e') : t.color('app-ink-3'))),
        ),
      ]),
    );
  }
}


/// Settings' audio test (GMFB-2, @kevin: "When testing voice calls it is difficult to diagnose issues without an in app
/// audio device test"): the microphone chosen, opened as a call opens it, with how loud it hears you; and, with
/// headphones, yourself played back through the speaker chosen. Not while in a call: the call has the microphone.
class AudioTest extends StatefulWidget {
  const AudioTest({super.key});

  /// What the test is run with: the call's own media, alone ([RtcMedia] measures its microphone through its meter when
  /// nobody else is connected). A test gives its own.
  @visibleForTesting
  static RtcMedia Function(VoiceSettings settings)? make;

  @override
  State<AudioTest> createState() => _AudioTestState();
}

class _AudioTestState extends State<AudioTest> {
  RtcMedia? _media;
  bool _starting = false, _hear = false;
  String? _problem;

  Future<void> _start() async {
    if (_media != null || _starting) return;
    setState(() {
      _starting = true;
      _problem = null;
    });
    final settings = VoiceSettings.of(AppState.of(context));
    final media = (AudioTest.make ?? (s) => RtcMedia(settings: s))(settings);
    try {
      await media.start();
      media.hearMyself = _hear;
      if (!mounted) return unawaited(media.stop());
      setState(() => _media = media);
    } catch (e) {
      unawaited(media.stop());
      if (mounted) setState(() => _problem = 'The microphone couldn\'t be opened: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    final media = _media;
    _media = null;
    if (mounted) setState(() {});
    await media?.stop();
  }

  @override
  void dispose() {
    unawaited(_media?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final inCall = Voice.instance.session != null;
    final media = _media;
    Widget icon(LucideIcon i) => AppIcon(i, size: 18);
    return PaneSection(
      title: 'Test',
      description: Text(inCall
          ? 'Leave the call to test your microphone and speaker here.'
          : 'Talk, and the bar moves with your voice as a call hears it. With headphones on, hear yourself through the speaker chosen.'),
      footer: _problem == null ? null : Text(_problem!, style: TextStyle(color: t.danger)),
      children: [
        SettingRow(
          key: const ValueKey('audio-test'),
          icon: icon(Lucide.mic),
          label: media == null ? 'Test your microphone' : 'Stop the test',
          disabled: inCall || _starting,
          onPress: media == null ? _start : _stop,
        ),
        if (media != null) ...[
          SettingRowBox(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(3)),
              child: ValueListenableBuilder<Map<String, double>>(
                valueListenable: media.levels,
                builder: (context, loud, _) => _Meter(level: (loud['me'] ?? 0).clamp(0.0, 1.0)),
              ),
            ),
          ),
          SettingRow(
            icon: icon(LucideMore.headphones),
            label: 'Hear yourself',
            hint: const Text('Your microphone through the speaker chosen. Use headphones, or the speaker feeds back into the microphone.'),
            control: GlacierSwitch(
              checked: _hear,
              ariaLabel: 'Hear yourself',
              onCheckedChange: (on) {
                setState(() => _hear = on);
                media.hearMyself = on;
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// How loud the microphone is, as a bar: green while it hears you speak, red near the top.
class _Meter extends StatelessWidget {
  const _Meter({required this.level});
  final double level;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colour = level > 0.85 ? t.danger : (level > 0.04 ? t.colorOf('#2fb35a') : t.color('app-ink-4'));
    return Semantics(
      label: 'Microphone level',
      value: '${(level * 100).round()}%',
      child: LayoutBuilder(
        builder: (context, box) => Stack(children: [
          Container(height: 10, decoration: BoxDecoration(color: t.color('app-paper-3'), borderRadius: BorderRadius.circular(5))),
          AnimatedContainer(
            key: const ValueKey('audio-test-level'),
            duration: const Duration(milliseconds: 120),
            width: box.maxWidth * level,
            height: 10,
            decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(5)),
          ),
        ]),
      ),
    );
  }
}
