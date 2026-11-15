import FlutterMacOS
import Foundation
import VoiceFxC
import WebRTC
import flutter_webrtc

/// What is done to the microphone before Opus, on the Mac (lib/voice/voice_fx.dart; Matt, 2026-11-15: "build in like
/// krisp noise supression or other fancy noise suppression tools, add a volume slider for input ... with
/// overboosting"): RNNoise, DeepFilterNet where its model is in the app, and the gain, from native/voicefx, run in
/// flutter_webrtc's capture post-processing hook on WebRTC's audio thread.
final class VoiceFx: NSObject, ExternalAudioProcessingDelegate {
  static let shared = VoiceFx()
  private let fx = voicefx_create()
  private var attached = false
  private var channel: FlutterMethodChannel?

  private override init() {
    super.init()
    // DeepFilterNet's model, where this build carries it (tool/build-deepfilter.sh): loaded once, off the main thread.
    if let model = Bundle.main.path(forResource: "DeepFilterNet3_onnx", ofType: "tar.gz") {
      DispatchQueue.global(qos: .utility).async { [fx] in _ = voicefx_deepfilter_model(fx, model) }
    }
  }

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "ghost/voicefx", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "modes":
        let bits = voicefx_modes(self.fx)
        var modes: [String] = []
        if bits & (1 << 1) != 0 { modes.append("rnnoise") }
        if bits & (1 << 2) != 0 { modes.append("deepfilter") }
        result(modes)
      case "configure":
        let args = call.arguments as? [String: Any] ?? [:]
        let mode: Int32 = switch args["mode"] as? String { case "rnnoise": 1; case "deepfilter": 2; default: 0 }
        voicefx_configure(self.fx, mode, Float(args["gain"] as? Double ?? 1))
        result(self.attach())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  /// Into flutter_webrtc's capture hook, once.
  private func attach() -> Bool {
    if attached { return true }
    AudioManager.sharedInstance().capturePostProcessingAdapter.addProcessing(self)
    attached = true
    return true
  }

  func audioProcessingInitialize(withSampleRate sampleRateHz: Int, channels: Int) {}

  func audioProcessingProcess(_ audioBuffer: RTCAudioBuffer) {
    let frames = audioBuffer.frames
    guard frames > 0, audioBuffer.channels > 0 else { return }
    // The first channel is cleaned; any other is given the same, so a stereo microphone stays one voice.
    let first = audioBuffer.rawBuffer(forChannel: 0)
    voicefx_process(fx, first, Int32(frames), Int32(frames * 100))
    for c in 1..<max(1, audioBuffer.channels) {
      audioBuffer.rawBuffer(forChannel: c).update(from: first, count: frames)
    }
  }

  func audioProcessingRelease() {}
}
