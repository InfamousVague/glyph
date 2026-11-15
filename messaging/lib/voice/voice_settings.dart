import 'package:flutter/foundation.dart';

import '../app_state.dart';

/// How calls sound and look on this device (Matt, 2026-11-15: "voice settings to change all kinds of things like
/// bitrates and sound input devices etc etc"): the microphone and speaker, Opus's bit rate and stereo, the
/// microphone's processing, and the picture's quality. Kept with the device's choices (`voice_*`); each is what the
/// app did before where it has not been changed: 510 kb/s stereo, echo cancellation on, noise suppression and gain
/// control off, 1080p.
@immutable
class VoiceSettings {
  const VoiceSettings({
    this.input = '',
    this.output = '',
    this.audioKbps = 510,
    this.stereo = true,
    this.echo = true,
    this.noise = false,
    this.gain = false,
    this.video = 1080,
  });

  /// The microphone's and the speaker's device ids; empty for the system's own.
  final String input;
  final String output;
  final int audioKbps;
  final bool stereo;
  final bool echo;
  final bool noise;
  final bool gain;

  /// The tallest picture sent: 1080, 720 or 480.
  final int video;

  static const kbpsChoices = [510, 256, 128, 64, 32];
  static const videoChoices = [1080, 720, 480];

  factory VoiceSettings.of(AppState app) => VoiceSettings(
        input: app.choice('voice_input', ''),
        output: app.choice('voice_output', ''),
        audioKbps: int.tryParse(app.choice('voice_kbps', '510')) ?? 510,
        stereo: app.flag('voice_stereo', fallback: true),
        echo: app.flag('voice_echo', fallback: true),
        noise: app.flag('voice_noise', fallback: false),
        gain: app.flag('voice_gain', fallback: false),
        video: int.tryParse(app.choice('voice_video', '1080')) ?? 1080,
      );

  /// The most a copy of the picture is sent at, by the quality chosen.
  int get videoCap => switch (video) { <= 480 => 1500000, <= 720 => 4000000, _ => 12000000 };

  /// The camera asked for: [video] tall at 16:9.
  ({int width, int height}) get videoSize => switch (video) { <= 480 => (width: 854, height: 480), <= 720 => (width: 1280, height: 720), _ => (width: 1920, height: 1080) };

  static String kbpsLabel(int k) => k >= 510 ? '510 kb/s · the most Opus carries' : '$k kb/s';
}
