import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'voice_settings.dart';

/// The microphone's own processing, done natively inside WebRTC's capture path (Matt, 2026-11-15: "build in like krisp
/// noise supression or other fancy noise suppression tools, add a volume slider for input ... with overboosting";
/// RNNoise + DeepFilterNet chosen): the sound sent is boosted or lowered and, where chosen, cleaned by RNNoise or
/// DeepFilterNet before Opus.
///
/// The native halves (channel `ghost/voicefx`) sit in flutter_webrtc's capture post-processing hook: android
/// VoiceFx.kt, macos VoiceFx.swift, and on Windows the patched flutter_webrtc (third_party/flutter_webrtc). Each runs
/// native/voicefx, the same C for all three.
class VoiceFx {
  VoiceFx._();
  static const _channel = MethodChannel('ghost/voicefx');

  /// What this device can run, once asked; empty where there is no native half (tests, an old build).
  static Set<NoiseMode> available = const {};
  static bool _asked = false;

  /// Asks the native half what it runs.
  static Future<Set<NoiseMode>> modes() async {
    if (_asked) return available;
    try {
      final said = await _channel.invokeListMethod<String>('modes') ?? const [];
      available = {for (final s in said) ?NoiseMode.named(s)};
    } on MissingPluginException {
      available = const {};
    } on PlatformException {
      available = const {};
    }
    _asked = true;
    return available;
  }

  /// For a test: what the device can run set to [to], as if asked; with none, asked afresh next time.
  @visibleForTesting
  static void reset([Set<NoiseMode> to = const {}]) {
    available = to;
    _asked = to.isNotEmpty;
  }

  /// Sets what is done to the microphone: [mode] (only RNNoise and DeepFilterNet are native; others are none here)
  /// and [gain], 1 for as it is, up to 2 for boosted.
  static Future<void> configure({required NoiseMode mode, required double gain}) async {
    final native = mode == NoiseMode.rnnoise || mode == NoiseMode.deepfilter ? mode.name : 'off';
    try {
      await _channel.invokeMethod<void>('configure', {'mode': native, 'gain': gain});
    } on MissingPluginException {
      // No native half: the sound goes as it is.
    } on PlatformException {
      // Refused: likewise.
    }
  }

  /// Applies [s] as it stands.
  static Future<void> apply(VoiceSettings s) async {
    final modes = await VoiceFx.modes();
    await configure(mode: s.noiseOn(modes), gain: s.inputVolume / 100);
  }
}
