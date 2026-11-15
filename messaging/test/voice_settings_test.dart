import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/voice/voice.dart';
import 'package:ghost_messaging/voice/voice_settings.dart';

/// Settings › Voice and video as calls use it (lib/voice/voice_settings.dart; Matt, 2026-11-15: "can we support 4k?
/// and flac audio? also build in like krisp noise supression or other fancy noise suppression tools, add a volume
/// slider for input and output volume with overboosting", then "RNNoise + DeepFilterNet").
void main() {
  // AppState writes its choices down the app's channel; with no phone there it goes nowhere.
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unchanged, a call is 510 kb/s stereo with echo cancellation and RNNoise, at 100% both ways', () {
    final s = VoiceSettings.of(AppState());
    expect(s.sendKbps, 510);
    expect(s.sendStereo, isTrue);
    expect(s.useEcho, isTrue);
    expect(s.noise, NoiseMode.rnnoise);
    expect(s.inputVolume, 100);
    expect(s.outputVolume, 100);
    expect(s.video, 1080);
  });

  test('noise suppression the device cannot run falls back to WebRTC\'s own; Music mode and Off use none', () {
    const rn = VoiceSettings(noise: NoiseMode.rnnoise), df = VoiceSettings(noise: NoiseMode.deepfilter);
    expect(rn.noiseOn(const {NoiseMode.rnnoise}), NoiseMode.rnnoise);
    expect(rn.noiseOn(const {}), NoiseMode.webrtc, reason: 'no native half (an old build, tests)');
    expect(df.noiseOn(const {NoiseMode.rnnoise}), NoiseMode.webrtc, reason: 'a phone has no DeepFilterNet');
    expect(df.noiseOn(const {NoiseMode.rnnoise, NoiseMode.deepfilter}), NoiseMode.deepfilter);
    expect(const VoiceSettings(noise: NoiseMode.webrtc).noiseOn(const {}), NoiseMode.webrtc);
    expect(const VoiceSettings(noise: NoiseMode.off).noiseOn(const {NoiseMode.rnnoise}), NoiseMode.off);
    expect(const VoiceSettings(music: true).noiseOn(const {NoiseMode.rnnoise}), NoiseMode.off);
  });

  test('Music mode sends the microphone as it is: 510 kb/s stereo, no echo cancellation or gain control', () {
    const s = VoiceSettings(music: true, audioKbps: 64, stereo: false, echo: true, gain: true);
    expect(s.sendKbps, 510);
    expect(s.sendStereo, isTrue);
    expect(s.useEcho, isFalse);
    expect(s.useGain, isFalse);
    expect(highestOpus('m=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=rtpmap:111 opus/48000/2\r\na=fmtp:111 minptime=10\r\n', kbps: s.sendKbps, stereo: s.sendStereo), contains('maxaveragebitrate=510000'));
  });

  test('4K asks the camera for 3840x2160 and sends it whole to one other at up to 25 Mb/s; to more, scaled as 1080p is', () {
    const k = VoiceSettings(video: 2160), hd = VoiceSettings(video: 1080);
    expect(k.videoSize, (width: 3840, height: 2160));
    expect(k.sendTo(1, videoFor(1)), (scale: 1.0, bitrate: 25000000));
    expect(hd.sendTo(1, videoFor(1)), (scale: 1.0, bitrate: 12000000));
    // Two others: 1080p goes at 1.5x smaller, 4K at 3x, so each copy is the same size and bit rate.
    expect(hd.sendTo(2, videoFor(2)).scale, 1.5);
    expect(k.sendTo(2, videoFor(2)).scale, 3.0);
    expect(k.sendTo(2, videoFor(2)).bitrate, hd.sendTo(2, videoFor(2)).bitrate);
    expect(const VoiceSettings(video: 480).sendTo(1, videoFor(1)).bitrate, 1500000, reason: 'never past the quality chosen');
    expect(VoiceSettings.videoLabel(2160), '4K');
  });

  test('volumes are kept from 0 to 200%; the old noise switch reads as WebRTC\'s own', () {
    final app = AppState()
      ..set('voice_in_volume', '350')
      ..set('voice_out_volume', '-20')
      ..setFlag('voice_noise', true);
    final s = VoiceSettings.of(app);
    expect(s.inputVolume, 200);
    expect(s.outputVolume, 0);
    expect(s.noise, NoiseMode.webrtc);
    app.set('voice_noise_mode', 'deepfilter');
    expect(VoiceSettings.of(app).noise, NoiseMode.deepfilter);
    expect(s.copyWith(outputVolume: 150).outputVolume, 150);
    expect(s.copyWith(outputVolume: 150).noise, NoiseMode.webrtc, reason: 'the rest kept');
  });
}
