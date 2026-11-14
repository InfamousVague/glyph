import AVFoundation
import AVKit
import Cocoa
import FlutterMacOS

/// A video in a message, on the Mac (Matt, 2026-11-14: "mp4 files are not loading it just shows up as a string of
/// text for the filename"): a picture of where it starts and how long it runs, for the conversation to draw, and a
/// window that plays it with the Mac's own player and controls.
///
/// The video is the phone's: the app brings its bytes over the link (lib/desktop/remote.dart) and hands them here.
/// AVFoundation reads a file, so the bytes are written to this app's own folder in the temporary directory, readable
/// by this account alone, for as long as they are needed and no longer: until the picture is made, or until the
/// player's window is closed. The folder is removed as the app opens and as it quits, so nothing of a conversation
/// stays on the Mac's disk (docs/desktop.md: the Mac keeps no texts).
final class DeskVideo: NSObject, NSWindowDelegate {
  static let shared = DeskVideo()

  /// The player windows open now, and the file each plays.
  private var playing: [(window: NSWindow, file: URL)] = []

  /// Every run's folders are in here; this run's is named by its process, so two copies of the app open at once
  /// never touch each other's.
  private static var folders: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ghost-messaging-video", isDirectory: true)
  }

  private static var folder: URL {
    folders.appendingPathComponent("\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
  }

  /// Nothing of a video is left from an earlier run, or after this one: this run's folder goes, and any left by a
  /// run that is no longer running (one that was stopped before it could tidy).
  static func sweep() {
    let manager = FileManager.default
    try? manager.removeItem(at: folder)
    for name in (try? manager.contentsOfDirectory(atPath: folders.path)) ?? [] {
      guard let pid = Int32(name) else { continue }
      // kill with signal 0 asks only whether the process is there.
      if kill(pid, 0) != 0 && errno == ESRCH { try? manager.removeItem(at: folders.appendingPathComponent(name)) }
    }
  }

  /// A place in this run's folder for a file named [name], for this account alone (a recording: DeskSound.swift).
  static func place(named name: String) throws -> URL {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    return folder.appendingPathComponent(name)
  }

  /// A file's ending AVFoundation knows the kind by; anything else is tried as an mp4.
  private static func ending(_ said: String) -> String {
    let known = ["mp4", "m4v", "mov", "3gp", "3g2"]
    return known.contains(said.lowercased()) ? said.lowercased() : "mp4"
  }

  private static func write(_ data: Data, id: Int, ext: String) throws -> URL {
    let manager = FileManager.default
    try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let file = folder.appendingPathComponent("\(id)-\(UUID().uuidString).\(ending(ext))")
    guard manager.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
      throw CocoaError(.fileWriteUnknown)
    }
    return file
  }

  /// `picture` (a JPEG of where the video starts, or nil where none can be made), `millis`, and the picture's size.
  static func preview(data: Data, id: Int, ext: String) -> [String: Any?] {
    let nothing: [String: Any?] = ["picture": nil, "millis": 0, "width": 0, "height": 0, "videoWidth": 0, "videoHeight": 0]
    guard let file = try? write(data, id: id, ext: ext) else { return nothing }
    defer { try? FileManager.default.removeItem(at: file) }
    let asset = AVURLAsset(url: file)
    let seconds = CMTimeGetSeconds(asset.duration)
    let millis = seconds.isFinite && seconds > 0 ? Int(seconds * 1000) : 0
    // The video's own size as it plays (one filmed upright is kept on its side): the conversation says how small a
    // video came (lib/ui/video.dart). The file's size is known to the caller, which holds its bytes.
    var own = CGSize.zero
    if let track = asset.tracks(withMediaType: .video).first {
      let turned = track.naturalSize.applying(track.preferredTransform)
      own = CGSize(width: abs(turned.width), height: abs(turned.height))
    }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 720, height: 720)
    guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil),
          let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    else { return ["picture": nil, "millis": millis, "width": 0, "height": 0, "videoWidth": Int(own.width), "videoHeight": Int(own.height)] }
    return ["picture": FlutterStandardTypedData(bytes: jpeg), "millis": millis, "width": image.width, "height": image.height, "videoWidth": Int(own.width), "videoHeight": Int(own.height)]
  }

  /// Opens a window that plays the video. Nil when it is playing, or why it is not.
  func play(data: Data, id: Int, ext: String, title: String) -> String? {
    guard let file = try? DeskVideo.write(data, id: id, ext: ext) else { return "the video could not be made ready to play" }
    let asset = AVURLAsset(url: file)
    guard asset.isPlayable else {
      try? FileManager.default.removeItem(at: file)
      return "this Mac can’t play this kind of video"
    }
    // As large as the video is, within most of the screen; never tiny.
    var natural = CGSize(width: 640, height: 360)
    if let track = asset.tracks(withMediaType: .video).first {
      let turned = track.naturalSize.applying(track.preferredTransform)
      if abs(turned.width) > 0, abs(turned.height) > 0 { natural = CGSize(width: abs(turned.width), height: abs(turned.height)) }
    }
    let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
    let scale = min(1, min(screen.width * 0.7 / natural.width, screen.height * 0.7 / natural.height))
    let grown = max(1, 360 / (natural.width * scale))
    let content = CGSize(width: natural.width * scale * grown, height: natural.height * scale * grown)

    let view = AVPlayerView(frame: NSRect(origin: .zero, size: content))
    view.controlsStyle = .floating
    view.player = AVPlayer(url: file)
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: content), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = title
    window.isReleasedWhenClosed = false
    // Black, as the app's own top bar is.
    window.titlebarAppearsTransparent = true
    window.backgroundColor = .black
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = view
    window.contentAspectRatio = content
    window.center()
    window.delegate = self
    playing.append((window, file))
    window.makeKeyAndOrderFront(nil)
    view.player?.play()
    return nil
  }

  /// The player's window closed: it stops, and the file it played is removed.
  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, let at = playing.firstIndex(where: { $0.window === window }) else { return }
    let file = playing.remove(at: at).file
    if let view = window.contentView as? AVPlayerView {
      view.player?.pause()
      view.player = nil
    }
    try? FileManager.default.removeItem(at: file)
  }

  /// The app's own window is closing: the players go with it, so the app can quit.
  func closeAll() {
    for open in playing { open.window.close() }
  }
}
