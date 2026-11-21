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
    // DeepFilterNet, where this build has it (native/voicefx/deepfilter): its model is built in, made ready once, off
    // the main thread. A build without it answers 0 and offers RNNoise alone.
    DispatchQueue.global(qos: .utility).async { [fx] in _ = voicefx_deepfilter_model(fx, "") }
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
        modes.append("live")
        modes.append("effects")
        result(modes)
      // A voice effect made here as it is said (lib/voice/live_changer.dart, native/voicefx voicefx_effect).
      case "effect":
        let args = call.arguments as? [String: Any] ?? [:]
        voicefx_effect(self.fx, voicefx_effect_id(args["name"] as? String ?? "none"))
        result(self.attach())
      // Live voice changing (lib/voice/live_changer.dart): what was said, taken; the changed voice, fed.
      case "live":
        let args = call.arguments as? [String: Any] ?? [:]
        voicefx_live(self.fx, (args["on"] as? Bool ?? false) ? 1 : 0)
        result(self.attach())
      case "take":
        let args = call.arguments as? [String: Any] ?? [:]
        let most = max(1, args["most"] as? Int ?? 32000)
        var buf = [Int16](repeating: 0, count: most)
        let n = Int(buf.withUnsafeMutableBufferPointer { voicefx_take(self.fx, $0.baseAddress, Int32(most)) })
        result(FlutterStandardTypedData(bytes: buf.prefix(n).withUnsafeBufferPointer { Data(buffer: $0) }))
      case "feed":
        let args = call.arguments as? [String: Any] ?? [:]
        if let pcm = (args["pcm"] as? FlutterStandardTypedData)?.data, pcm.count >= 2 {
          let rate = Int32(args["rate"] as? Int ?? 24000)
          pcm.withUnsafeBytes { raw in
            if let p = raw.bindMemory(to: Int16.self).baseAddress { voicefx_feed(self.fx, p, Int32(pcm.count / 2), rate) }
          }
        }
        result(Int(voicefx_queued_ms(self.fx)))
      case "queued":
        result(Int(voicefx_queued_ms(self.fx)))
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
    // The voice as it is sent, for a recording of the call being made here (CallRecorder.swift).
    CallRecorder.shared.mic(first, frames: frames, rate: frames * 100)
    // And for the call's captions, where they are on (LiveCaptions.swift).
    LiveCaptions.shared.feed(first, frames: frames, rate: frames * 100)
    for c in 1..<max(1, audioBuffer.channels) {
      audioBuffer.rawBuffer(forChannel: c).update(from: first, count: frames)
    }
  }

  func audioProcessingRelease() {}
}
