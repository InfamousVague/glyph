import AVFoundation
import Foundation
import Speech
#if canImport(FlutterMacOS)
import FlutterMacOS
#else
import Flutter
#endif

/// Words from a recorded call, on the Mac and the iPhone (the same file in macos/Runner and ios/Runner;
/// lib/voice/scribe.dart; Matt, 2026-11-19: "Start with the recording plugin, then scribe"): one track of a
/// recording's MP4 (one person's voice) read, cut where they pause, and each stretch heard by Apple's speech recognition
/// on the device. As android Scribe.kt: each line has its time from the cut, and the track says whose voice it is.
final class Scribe: NSObject {
  static let shared = Scribe()
  static let rate = 16000
  private var channel: FlutterMethodChannel?

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "ghost/scribe", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "available":
        let r = SFSpeechRecognizer()
        result(r?.supportsOnDeviceRecognition ?? false)
      case "transcribe":
        let path = args["path"] as? String ?? ""
        let track = args["track"] as? Int ?? 0
        let language = args["language"] as? String
        SFSpeechRecognizer.requestAuthorization { status in
          guard status == .authorized else {
            DispatchQueue.main.async { result(FlutterError(code: "denied", message: "Speech recognition isn't allowed for Ghost Messaging", details: nil)) }
            return
          }
          DispatchQueue.global(qos: .userInitiated).async {
            do {
              let lines = try Scribe.transcribe(path: path, track: track, language: language)
              DispatchQueue.main.async { result(lines) }
            } catch {
              DispatchQueue.main.async { result(FlutterError(code: "scribe", message: "\(error)", details: nil)) }
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  struct Failure: Error, CustomStringConvertible { let description: String }

  static func transcribe(path: String, track: Int, language: String?) throws -> [[String: Any]] {
    let recognizer = (language.map { SFSpeechRecognizer(locale: Locale(identifier: $0)) } ?? SFSpeechRecognizer()) ?? SFSpeechRecognizer()
    guard let recognizer, recognizer.supportsOnDeviceRecognition else { throw Failure(description: "no on-device speech recognition here") }
    let pcm = try decode(path: path, track: track)
    var out: [[String: Any]] = []
    for (from, to) in stretches(pcm) {
      guard let text = recognize(recognizer, pcm, from, to), !text.isEmpty else { continue }
      out.append(["start": from * 1000 / rate, "end": to * 1000 / rate, "text": text])
    }
    return out
  }

  /// [track] of [path] as 16 kHz mono 16-bit samples.
  static func decode(path: String, track: Int) throws -> [Int16] {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let tracks = asset.tracks(withMediaType: .audio)
    guard track < tracks.count else { throw Failure(description: "no track \(track)") }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: tracks[track], outputSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
    ])
    reader.add(output)
    guard reader.startReading() else { throw Failure(description: reader.error?.localizedDescription ?? "can't read") }
    var samples: [Int16] = []
    while let buffer = output.copyNextSampleBuffer() {
      guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
      let n = CMBlockBufferGetDataLength(block)
      var chunk = [Int16](repeating: 0, count: n / 2)
      chunk.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: n, destination: $0.baseAddress!) }
      samples.append(contentsOf: chunk)
    }
    return samples
  }

  /// Where someone is talking, as android Scribe.kt finds it: 30 ms blocks louder than the track's quiet, joined
  /// across pauses under 0.7 s, each stretch at most 25 s and at least 0.3 s.
  static func stretches(_ pcm: [Int16]) -> [(Int, Int)] {
    let block = rate * 30 / 1000
    let count = pcm.count / block
    guard count > 0 else { return [] }
    var levels = [Double](repeating: 0, count: count)
    for b in 0..<count {
      var sum = 0.0
      for i in (b * block)..<((b + 1) * block) { sum += Double(pcm[i]) * Double(pcm[i]) }
      levels[b] = (sum / Double(block)).squareRoot()
    }
    let quiet = levels.sorted()[count / 10]
    let loud = max(300, quiet * 3)
    var out: [(Int, Int)] = []
    var start = -1, lastLoud = -1
    let gap = 700 / 30, most = 25_000 / 30
    for (b, l) in levels.enumerated() {
      if l >= loud {
        if start < 0 { start = b }
        lastLoud = b
      }
      if start >= 0 && (b - lastLoud > gap || b - start >= most || b == count - 1) {
        let end = lastLoud + 1
        if end - start >= 10 { out.append((max(0, start - 5) * block, min(count, end + 5) * block)) }
        start = -1
      }
    }
    return out
  }

  static func recognize(_ recognizer: SFSpeechRecognizer, _ pcm: [Int16], _ from: Int, _ to: Int) -> String? {
    guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(rate), channels: 1, interleaved: false),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(to - from)) else { return nil }
    buffer.frameLength = AVAudioFrameCount(to - from)
    pcm.withUnsafeBufferPointer { src in buffer.int16ChannelData![0].update(from: src.baseAddress! + from, count: to - from) }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = false
    request.append(buffer)
    request.endAudio()
    let done = DispatchSemaphore(value: 0)
    var heard: String?
    let task = recognizer.recognitionTask(with: request) { result, error in
      if let result, result.isFinal { heard = result.bestTranscription.formattedString; done.signal() } else if error != nil { done.signal() }
    }
    if done.wait(timeout: .now() + 60) == .timedOut { task.cancel() }
    return heard
  }
}
