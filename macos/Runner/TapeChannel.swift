import AVFoundation
#if os(iOS)
import Flutter
import UIKit
#else
import Cocoa
import FlutterMacOS
#endif

/// `ghost_md/tape` on the Mac and on the iPhone: the player of a note's recording (lib/tapes/phone_player.dart), as
/// android/…/ghost_md/TapePlayer.kt is on the phone and the page's `<audio>` element over the `rec` scheme was in
/// the Tauri app. One player for the whole app.
///
/// ONE FILE FOR BOTH: the iPhone's Runner compiles this very file (ios/Runner.xcodeproj names it by its path here),
/// `AVAudioPlayer` being the same on each; what differs is the two imports above, the word for the device, and the
/// iPhone's audio session, which is told this is playback so a recording is heard with the ring switch off, as the
/// page's element was. Each app's `GhostChannels.dirs()` says where its recordings are.
///
/// Only ever a file under the app's own `recordings` folder, named by a note's id: an id is letters, digits, `-`
/// and `_`, and anything else is refused before a path is made of it.
///
/// - `load {noteId}` -> the recording's length in ms; an error where it is not on this device or will not open.
/// - `play`, `pause`, `seek {ms}`, `release` -> null. `onDevice {noteId}` -> whether the file is here.
/// - Events on `ghost_md/tape/events`: `{event: "position", ms}` a few times a second while it plays,
///   `{event: "playing", on}`, `{event: "ended"}`, `{event: "failed"}`.
final class TapeChannel: NSObject, FlutterStreamHandler, AVAudioPlayerDelegate {
  #if os(iOS)
  private static let device = "iPhone"
  #else
  private static let device = "Mac"
  #endif

  private var methods: FlutterMethodChannel?
  private var events: FlutterEventChannel?
  private var sink: FlutterEventSink?
  private var player: AVAudioPlayer?
  private var ticker: Timer?

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    let methods = FlutterMethodChannel(name: "ghost_md/tape", binaryMessenger: messenger)
    methods.setMethodCallHandler { [weak self] call, result in self?.asked(call, result) }
    self.methods = methods
    let events = FlutterEventChannel(name: "ghost_md/tape/events", binaryMessenger: messenger)
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

  private static func file(of noteId: String?) -> URL? {
    guard let id = noteId, !id.isEmpty, id.count <= 128, id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" || $0 == "_" }), let dirs = GhostChannels.dirs() else { return nil }
    return dirs.data.appendingPathComponent("recordings", isDirectory: true).appendingPathComponent("\(id).wav")
  }

  private func asked(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "load":
      release()
      guard let file = TapeChannel.file(of: args?["noteId"] as? String), FileManager.default.fileExists(atPath: file.path) else {
        return result(FlutterError(code: "tape", message: "The recording is not on this \(TapeChannel.device).", details: nil))
      }
      do {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        #endif
        let made = try AVAudioPlayer(contentsOf: file)
        made.delegate = self
        made.prepareToPlay()
        player = made
        result(Int((made.duration * 1000).rounded()))
      } catch {
        result(FlutterError(code: "tape", message: "The recording could not be played.", details: nil))
      }
    case "play":
      if let player = player, player.play() {
        say(["event": "playing", "on": true])
        tick()
      } else if player != nil {
        say(["event": "failed"])
      }
      result(nil)
    case "pause":
      player?.pause()
      stopTicking()
      say(["event": "playing", "on": false])
      position()
      result(nil)
    case "seek":
      if let player = player {
        let ms = (args?["ms"] as? NSNumber)?.doubleValue ?? 0
        player.currentTime = max(0, min(player.duration, ms / 1000))
        position()
      }
      result(nil)
    case "onDevice":
      result(TapeChannel.file(of: args?["noteId"] as? String).map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
    case "release":
      release()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func say(_ event: [String: Any]) {
    sink?(event)
  }

  private func position() {
    guard let player = player else { return }
    say(["event": "position", "ms": Int((player.currentTime * 1000).rounded())])
  }

  private func tick() {
    stopTicking()
    ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.position() }
  }

  private func stopTicking() {
    ticker?.invalidate()
    ticker = nil
  }

  private func release() {
    stopTicking()
    player?.stop()
    player?.delegate = nil
    player = nil
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    stopTicking()
    say(["event": flag ? "ended" : "failed"])
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    stopTicking()
    say(["event": "failed"])
  }
}
