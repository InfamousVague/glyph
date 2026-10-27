import AVFoundation
import Cocoa
import FlutterMacOS

/// `ghost_md/sounds` on the Mac: the app's sounds inside the app (lib/sounds/sounds.dart; Matt, 2026-10-27: "build
/// ... the sounds settings"), as android/…/ghost_md/Sounds.kt is on the phone. One `AVAudioPlayer` for each sound,
/// made and prepared when it is primed, so a play is the player's alone (the doc's "primed when the app opens").
///
/// - `prime {key, bytes}` -> null: the pack's `.caf`, read from the app's assets by Dart and handed over.
/// - `play {key, volume, whileRecording}` -> whether it played; false for a key never primed.
/// - `narrate {key, bytes}` -> whether it plays: the walkthrough's voice for a page (lib/guide/narrator.dart; Matt,
///   2026-10-27: "a friendly elevenlabs v4 voice explaining each section"), on a player of its own, in place of any
///   page's voice still playing.
/// - `hush` -> null: that voice stopped, as the guide turns a page or goes.
///
/// The Mac has no ringer switch, and Focus is not something an app can read, so nothing more is asked here: the
/// Dart half keeps sounds out of a recording, and the person's switches are the rest.
final class SoundsChannel: NSObject {
  private var methods: FlutterMethodChannel?
  private var players: [String: AVAudioPlayer] = [:]
  /// The walkthrough's voice playing now, if it is.
  private var voice: AVAudioPlayer?

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    let methods = FlutterMethodChannel(name: "ghost_md/sounds", binaryMessenger: messenger)
    methods.setMethodCallHandler { [weak self] call, result in self?.asked(call, result) }
    self.methods = methods
  }

  private func asked(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "prime":
      guard let key = arguments["key"] as? String, let bytes = arguments["bytes"] as? FlutterStandardTypedData, bytes.data.count <= 1_048_576 else {
        result(FlutterError(code: "sounds", message: "No sound to keep.", details: nil))
        return
      }
      if players[key] != nil {
        result(nil)
        return
      }
      do {
        let player = try AVAudioPlayer(data: bytes.data)
        player.prepareToPlay()
        players[key] = player
        result(nil)
      } catch {
        result(FlutterError(code: "sounds", message: "The sound could not be decoded.", details: nil))
      }
    case "play":
      guard let key = arguments["key"] as? String, let player = players[key] else {
        result(false)
        return
      }
      let volume = (arguments["volume"] as? NSNumber)?.floatValue ?? 1
      player.volume = max(0, min(1, volume))
      // A sound asked again while it plays starts over rather than waiting: two ticks in a row are two ticks.
      player.currentTime = 0
      result(player.play())
    case "narrate":
      voice?.stop()
      voice = nil
      guard let bytes = arguments["bytes"] as? FlutterStandardTypedData, bytes.data.count <= 4_194_304, let player = try? AVAudioPlayer(data: bytes.data) else {
        result(FlutterError(code: "sounds", message: "No voice to play.", details: nil))
        return
      }
      voice = player
      result(player.play())
    case "hush":
      voice?.stop()
      voice = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
