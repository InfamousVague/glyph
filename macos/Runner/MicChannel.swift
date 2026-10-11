import AVFoundation
import Cocoa
import FlutterMacOS

/// `ghost_md/mic` on the Mac: the microphone for dictation (lib/capture/device_mic.dart), as
/// android/…/glyph/capture/DictationMic.kt is on the phone. The Tauri Mac app had no such file: its microphone was
/// the WebView's `getUserMedia` (capture/audio.ts), resampled by the page to the 16 kHz mono the engine takes.
/// Here `AVAudioEngine` hears the Mac's input in its own format and an `AVAudioConverter` makes the same 16 kHz
/// mono floats, in the same 200 ms chunks.
///
/// NO ALWAYS-ON MICROPHONE. The device is opened by `open`, which the recorder calls when a person starts
/// recording, and let go by `close`. Nothing here opens it at launch, and nothing keeps it past the take.
///
/// - `permission` -> "granted" | "ask" | "blocked" (refused: only System Settings changes it).
/// - `request` -> "granted" | "blocked", once macOS's dialog is answered.
/// - `openSettings` -> whether System Settings opened on Privacy › Microphone.
/// - `open {direct, noiseSuppression, autoGainControl, testWav?}` -> `{sampleRate, direct}`; an error "permission"
///   when the microphone is not allowed, "unavailable" when it would not open.
/// - `flow` -> null: the capture has started; what was held goes to the core (direct only).
/// - `close` -> `{samples, pushed, refused}`.
/// - Events on `ghost_md/mic/events`: `{event: "chunk", rms, samples, pcm?}` and `{event: "closed", reason}`.
///
/// `direct` pushes each chunk straight into the core (`ghost_capture_push`, native/src/capture.rs), found by name
/// in the library Dart already opened. `testWav` is a DEBUG BUILD'S ONLY: a 16 kHz mono PCM16 WAV played in place
/// of the device at a microphone's pace, so a take can be walked without the Mac's microphone being asked for.
///
/// What differs from the phone: `noiseSuppression` and `autoGainControl` are heard and not acted on. The Mac's
/// voice processing would do both, and it also changes what every other app plays while it is on; the take is the
/// input as the Mac gives it.
final class MicChannel: NSObject, FlutterStreamHandler {
  static let sampleRate = 16_000.0
  /// 200 ms: lib/capture/audio.dart's `_chunk`.
  static let chunk = 3_200
  /// Thirty seconds of chunks held while a capture starts; older ones go first.
  private static let heldChunks = 150

  private typealias Push = @convention(c) (UnsafePointer<Float>, Int) -> Int32

  private var methods: FlutterMethodChannel?
  private var events: FlutterEventChannel?
  private var sink: FlutterEventSink?

  /// Everything of a take is touched on this queue alone.
  private let work = DispatchQueue(label: "ghost.mic")
  private var engine: AVAudioEngine?
  private var converter: AVAudioConverter?
  private var fixture: DispatchSourceTimer?
  private var observer: NSObjectProtocol?
  private var running = false
  private var direct = false
  private var flowing = false
  private var pending: [Float] = []
  private var held: [[Float]] = []
  private var samples = 0
  private var pushed = 0
  private var refused = 0
  private var push: Push?

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    let methods = FlutterMethodChannel(name: "ghost_md/mic", binaryMessenger: messenger)
    methods.setMethodCallHandler { [weak self] call, result in self?.asked(call, result) }
    self.methods = methods
    let events = FlutterEventChannel(name: "ghost_md/mic/events", binaryMessenger: messenger)
    events.setStreamHandler(self)
    self.events = events
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private static func permission() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return "granted"
    case .notDetermined: return "ask"
    default: return "blocked"
    }
  }

  private func asked(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "permission":
      result(MicChannel.permission())
    case "request":
      if MicChannel.permission() != "ask" { return result(MicChannel.permission()) }
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async { result(granted ? "granted" : "blocked") }
      }
    case "openSettings":
      result(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone").map { NSWorkspace.shared.open($0) } ?? false)
    case "open":
      open(direct: args?["direct"] as? Bool ?? false, testWav: args?["testWav"] as? String, result)
    case "flow":
      work.async { [weak self] in
        guard let self = self, self.running else { return }
        self.flowing = true
        for chunk in self.held { self.send(chunk) }
        self.held.removeAll()
      }
      result(nil)
    case "close":
      work.async { [weak self] in
        guard let self = self else { return }
        let totals = self.running ? ["samples": self.samples, "pushed": self.pushed, "refused": self.refused] : nil
        self.stop()
        DispatchQueue.main.async { result(totals) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func open(direct: Bool, testWav: String?, _ result: @escaping FlutterResult) {
    var wav: [Float]?
    if let path = testWav {
      #if DEBUG
      guard let read = MicChannel.readWav(path) else {
        return result(FlutterError(code: "unavailable", message: "The fixture is not a 16 kHz mono PCM16 WAV.", details: nil))
      }
      wav = read
      #else
      return result(FlutterError(code: "unavailable", message: "Only a debug build plays a fixture.", details: nil))
      #endif
    } else if MicChannel.permission() != "granted" {
      return result(FlutterError(code: "permission", message: "Ghost.md needs the microphone to record.", details: nil))
    }
    work.async { [weak self] in
      guard let self = self else { return }
      self.stop()
      self.direct = direct
      self.flowing = false
      self.pending.removeAll(keepingCapacity: true)
      self.held.removeAll()
      self.samples = 0
      self.pushed = 0
      self.refused = 0
      if direct, self.push == nil, let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "ghost_capture_push") {
        self.push = unsafeBitCast(symbol, to: Push.self)
      }
      if direct, self.push == nil {
        return DispatchQueue.main.async { result(FlutterError(code: "unavailable", message: "Ghost.md’s core is not loaded.", details: nil)) }
      }
      self.running = true
      if let wav = wav {
        self.play(wav)
      } else if let failure = self.listen() {
        self.running = false
        return DispatchQueue.main.async { result(FlutterError(code: "unavailable", message: failure, details: nil)) }
      }
      DispatchQueue.main.async { result(["sampleRate": Int(MicChannel.sampleRate), "direct": direct]) }
    }
  }

  /// Starts the Mac's input. Answers a sentence when it would not start.
  private func listen() -> String? {
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let heard = input.outputFormat(forBus: 0)
    guard heard.sampleRate > 0, heard.channelCount > 0, let wanted = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: MicChannel.sampleRate, channels: 1, interleaved: false), let converter = AVAudioConverter(from: heard, to: wanted) else {
      return "This Mac has no microphone Ghost.md can open."
    }
    self.converter = converter
    input.installTap(onBus: 0, bufferSize: 4096, format: heard) { [weak self] buffer, _ in
      guard let self = self else { return }
      // Converted on the audio thread's buffer before it is reused, then handed to the take's own queue.
      let room = AVAudioFrameCount(Double(buffer.frameLength) * MicChannel.sampleRate / heard.sampleRate) + 32
      guard let out = AVAudioPCMBuffer(pcmFormat: wanted, frameCapacity: room) else { return }
      var given = false
      var failure: NSError?
      let status = converter.convert(to: out, error: &failure) { _, state in
        if given {
          state.pointee = .noDataNow
          return nil
        }
        given = true
        state.pointee = .haveData
        return buffer
      }
      guard status != .error, out.frameLength > 0, let floats = out.floatChannelData?[0] else { return }
      let made = Array(UnsafeBufferPointer(start: floats, count: Int(out.frameLength)))
      self.work.async { self.take(made) }
    }
    // The input changed under the take (a headset unplugged): the take ends rather than record silence.
    observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
      self?.work.async { self?.lost("error") }
    }
    do {
      engine.prepare()
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      return "The microphone could not be opened."
    }
    self.engine = engine
    return nil
  }

  /// Samples heard, cut into chunks.
  private func take(_ heard: [Float]) {
    guard running else { return }
    pending.append(contentsOf: heard)
    while pending.count >= MicChannel.chunk {
      let chunk = Array(pending.prefix(MicChannel.chunk))
      pending.removeFirst(MicChannel.chunk)
      emit(chunk)
    }
  }

  private func emit(_ chunk: [Float]) {
    samples += chunk.count
    var sum: Float = 0
    for value in chunk { sum += value * value }
    let rms = chunk.isEmpty ? 0 : Double((sum / Float(chunk.count)).squareRoot())
    var event: [String: Any] = ["event": "chunk", "rms": min(1, rms), "samples": samples]
    if direct {
      if flowing {
        send(chunk)
      } else {
        held.append(chunk)
        if held.count > MicChannel.heldChunks { held.removeFirst() }
      }
    } else {
      event["pcm"] = FlutterStandardTypedData(bytes: chunk.withUnsafeBufferPointer { Data(buffer: $0) })
    }
    DispatchQueue.main.async { [weak self] in self?.sink?(event) }
  }

  private func send(_ chunk: [Float]) {
    guard let push = push else { return }
    let taken = chunk.withUnsafeBufferPointer { push($0.baseAddress!, $0.count) }
    if taken == 0 { pushed += chunk.count } else { refused += chunk.count }
  }

  private func lost(_ reason: String) {
    guard running else { return }
    stop()
    DispatchQueue.main.async { [weak self] in self?.sink?(["event": "closed", "reason": reason]) }
  }

  private func stop() {
    running = false
    fixture?.cancel()
    fixture = nil
    if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    if let engine = engine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
    engine = nil
    converter = nil
    pending.removeAll()
    held.removeAll()
  }

  // MARK: the fixture (debug builds)

  private func play(_ wav: [Float]) {
    var at = 0
    let timer = DispatchSource.makeTimerSource(queue: work)
    timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(200))
    timer.setEventHandler { [weak self] in
      guard let self = self, self.running else { return }
      // The file, then quiet: a microphone does not end, and the recorder's own silence ends the take.
      var chunk = [Float](repeating: 0, count: MicChannel.chunk)
      if at < wav.count {
        let count = min(MicChannel.chunk, wav.count - at)
        chunk.replaceSubrange(0..<count, with: wav[at..<(at + count)])
        at += count
      }
      self.emit(chunk)
    }
    fixture = timer
    timer.resume()
  }

  /// A 16 kHz mono PCM16 WAV's samples as floats, or nil for any other file.
  private static func readWav(_ path: String) -> [Float]? {
    guard let data = FileManager.default.contents(atPath: path), data.count > 44, data.prefix(4) == Data("RIFF".utf8), data.subdata(in: 8..<12) == Data("WAVE".utf8) else { return nil }
    func u32(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 | Int(data[at + 2]) << 16 | Int(data[at + 3]) << 24 }
    func u16(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }
    var at = 12
    var format: (channels: Int, rate: Int, bits: Int, kind: Int)?
    while at + 8 <= data.count {
      let name = String(data: data.subdata(in: at..<(at + 4)), encoding: .ascii) ?? ""
      let size = u32(at + 4)
      let body = at + 8
      if name == "fmt ", body + 16 <= data.count {
        format = (u16(body + 2), u32(body + 4), u16(body + 14), u16(body))
      } else if name == "data" {
        guard let format = format, format.kind == 1, format.channels == 1, format.rate == Int(sampleRate), format.bits == 16 else { return nil }
        let end = min(data.count, body + size)
        var out = [Float]()
        out.reserveCapacity((end - body) / 2)
        var i = body
        while i + 1 < end {
          out.append(Float(Int16(bitPattern: UInt16(data[i]) | UInt16(data[i + 1]) << 8)) / 32768)
          i += 2
        }
        return out
      }
      at = body + size + (size & 1)
    }
    return nil
  }
}
