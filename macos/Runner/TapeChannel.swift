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
/// the Tauri app. Two for the whole app, each on a channel of its own name: the tape's (`ghost_md/tape`) and the
/// voice memos' (`ghost_md/clip`, the `<audio>` the page made for a memo), so a memo takes nothing from the tape.
/// The Mac has six more, `ghost_md/preview/0` to `/5`, which the home page's shelf loads the cassettes in view into
/// ahead (lib/tapes/previews.dart), so a resting mouse only presses Play; the iPhone has none, with no mouse to rest.
///
/// ONE FILE FOR BOTH: the iPhone's Runner compiles this very file (ios/Runner.xcodeproj names it by its path here),
/// `AVAudioPlayer` being the same on each; what differs is the two imports above, the word for the device, and the
/// iPhone's audio session, which is told this is playback so a recording is heard with the ring switch off, as the
/// page's element was. Each app's `GhostChannels.dirs()` says where its recordings are.
///
/// Only ever a file under the app's own `recordings` folder, named by a note's id: an id is letters, digits, `-`
/// and `_`, and anything else is refused before a path is made of it.
///
/// - `load {noteId}` -> the recording's length in ms; an error where it is not on this device or will not open. `load
///   {file}` the same for a sound file a note links (`<data>/images/files/<name>`, a voice-over among them) and `load
///   {cached}` for a sound kept in the cache (`<cache>/sounds/<name>`, an ElevenLabs voice's preview), each by a kept
///   file's name and never a path (lib/tapes/phone_player.dart `loadArguments`).
/// - `play`, `pause`, `seek {ms}`, `release` -> null. `onDevice {noteId}` -> whether the file is here.
/// - Events on the channel's name with `/events` after it: `{event: "position", ms}` a few times a second while it plays,
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

  init(messenger: FlutterBinaryMessenger, name: String = "ghost_md/tape") {
    super.init()
    let methods = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    methods.setMethodCallHandler { [weak self] call, result in self?.asked(call, result) }
    self.methods = methods
    let events = FlutterEventChannel(name: "\(name)/events", binaryMessenger: messenger)
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

  /// A sound file a note links, or one in the cache's sounds, by its kept name: letters, digits, `-` and `_`, a dot, and
  /// a lower-case extension. Nil for a name that is not one, or a device that will not say where its folders are.
  private static func sound(file: String?, cached: String?) -> URL? {
    guard let name = file ?? cached, name.range(of: "^[A-Za-z0-9_-]{1,64}\\.[a-z0-9]{1,10}$", options: .regularExpression) != nil, let dirs = GhostChannels.dirs() else { return nil }
    if file != nil { return dirs.data.appendingPathComponent("images", isDirectory: true).appendingPathComponent("files", isDirectory: true).appendingPathComponent(name) }
    return dirs.cache.appendingPathComponent("sounds", isDirectory: true).appendingPathComponent(name)
  }

  private func asked(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "load":
      release()
      let named = args?["file"] as? String, cached = args?["cached"] as? String
      let found = named != nil || cached != nil ? TapeChannel.sound(file: named, cached: cached) : TapeChannel.file(of: args?["noteId"] as? String)
      guard let file = found, FileManager.default.fileExists(atPath: file.path) else {
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
