import Cocoa
import FlutterMacOS
import ImageIO
import Security
import UniformTypeIdentifiers

/// The Mac's half of the app's method channels (lib/**: every `MethodChannel(`), each named as the Android half
/// names it (android/…/ghost_md/*.kt) and answering in the same shapes, so the Dart is one for both.
///
/// Here: where the app keeps its files, links opened, the secure store, a reset's forgetting, links that open the
/// app, and pictures. The pickers and drives are FilesChannel.swift, a recording's player TapeChannel.swift, the
/// microphone MicChannel.swift, the window itself MainFlutterWindow.swift.
///
/// THE APP'S FILES ARE ITS OWN. The bundle id is `com.mattssoftware.glyph.flutter`, and everything the app keeps
/// is in the folder of that name: `~/Library/Application Support/com.mattssoftware.glyph.flutter` and
/// `~/Library/Caches/com.mattssoftware.glyph.flutter`, as Tauri names its two. The app is not sandboxed (Matt,
/// 2026-10-09: "un sandbox it"), so nothing but this code keeps it out of the Tauri app's
/// `~/Library/Application Support/com.mattssoftware.glyph`: [ownDirectory] names a folder only for an id that is
/// not the Tauri app's and refuses any path that is that folder or inside it, `dirs` answers nothing for a build
/// that fails it, and lib/core/native/device_paths.dart asks the same of the answer before the core is opened.
final class GhostChannels: NSObject {
  /// The Tauri app's bundle id: never this app's.
  static let realApp = "com.mattssoftware.glyph"

  private let files: FilesChannel
  private let tape: TapeChannel
  private let mic: MicChannel
  private var held: [FlutterMethodChannel] = []
  private weak var window: NSWindow?
  private var links: FlutterMethodChannel?
  private var keptLinks: [String] = []

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    self.window = window
    files = FilesChannel(messenger: messenger, window: window)
    tape = TapeChannel(messenger: messenger)
    mic = MicChannel(messenger: messenger)
    super.init()

    listen("ghost_md/device_paths", messenger) { call, result in
      guard call.method == "dirs" else { return result(FlutterMethodNotImplemented) }
      guard let dirs = GhostChannels.dirs() else {
        return result(FlutterError(code: "paths", message: "Ghost Flutter will not open another app's files.", details: nil))
      }
      result(["dataDir": dirs.data.path, "cacheDir": dirs.cache.path])
    }

    listen("ghost_md/open", messenger) { call, result in
      guard call.method == "open" else { return result(FlutterMethodNotImplemented) }
      let said = (call.arguments as? [String: Any])?["url"] as? String ?? ""
      // What lib/core/open_link.dart lets through, asked again here: a channel is not trusted to have asked.
      guard let url = URL(string: said), let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel", "geo"].contains(scheme) else { return result(false) }
      if scheme == "geo" {
        // The Mac has no `geo:`; Maps takes the same place by its own address.
        let place = said.dropFirst(4).split(separator: "?").first.map(String.init) ?? ""
        guard let maps = URL(string: "https://maps.apple.com/?ll=\(place)") else { return result(false) }
        return result(NSWorkspace.shared.open(maps))
      }
      result(NSWorkspace.shared.open(url))
    }

    listen("ghost_md/secure_store", messenger) { call, result in
      let args = call.arguments as? [String: Any]
      let name = args?["name"] as? String ?? ""
      guard !name.isEmpty else { return result(FlutterError(code: "secure_store", message: "A secret needs a name.", details: nil)) }
      switch call.method {
      case "read":
        switch Keychain.read(name) {
        case .success(let value): result(value)
        case .failure(let failure): result(FlutterError(code: "secure_store", message: failure.said, details: nil))
        }
      case "write":
        guard let value = args?["value"] as? String else { return result(FlutterError(code: "secure_store", message: "A secret needs a value.", details: nil)) }
        if let failure = Keychain.write(name, value) { result(FlutterError(code: "secure_store", message: failure.said, details: nil)) } else { result(nil) }
      case "delete":
        if let failure = Keychain.delete(name) { result(FlutterError(code: "secure_store", message: failure.said, details: nil)) } else { result(nil) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // A dot where the others have an underscore (`resetChannelName`, lib/core/reset.dart).
    listen("ghost.md/reset", messenger) { call, result in
      switch call.method {
      case "recording":
        // A Mac's meeting has no service of its own to be recording behind the app.
        result(false)
      case "cancelWriteUps":
        // No work queue on the Mac: a write-up is the core's job, and a reset's own command stops it.
        result(nil)
      case "forgetSecrets":
        if Keychain.clear() { result(nil) } else { result(FlutterError(code: "secure_store", message: "A kept sign-in could not be forgotten.", details: nil)) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Links that open the app (`ghostmd://…`, lib/core/phone_links.dart): kept until the page asks.
    let links = FlutterMethodChannel(name: "ghost_md/links", binaryMessenger: messenger)
    links.setMethodCallHandler { [weak self] call, result in
      guard call.method == "take" else { return result(FlutterMethodNotImplemented) }
      let kept = self?.keptLinks ?? []
      self?.keptLinks = []
      result(kept)
    }
    self.links = links

    listen("ghost_md/pictures", messenger) { [weak self] call, result in
      switch call.method {
      case "pick": self?.pickPicture(result)
      case "clipboard": result(GhostChannels.clipboard())
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func listen(_ name: String, _ messenger: FlutterBinaryMessenger, _ handler: @escaping FlutterMethodCallHandler) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler(handler)
    held.append(channel)
  }

  /// A link the system handed the app (AppDelegate `application(_:open:)`). Only the app's own scheme is kept.
  func arrived(_ url: URL) {
    guard url.scheme?.lowercased() == "ghostmd" else { return }
    keptLinks.append(url.absoluteString)
    links?.invokeMethod("arrived", arguments: nil)
  }

  /// `<Application Support>/<bundle id>` and `<Caches>/<bundle id>`, as Tauri names its two (`app_data_dir`,
  /// `app_cache_dir`). Nil for a build with the Tauri app's id, or should either ever come out as the Tauri app's
  /// folder or a place inside it.
  static func dirs() -> (data: URL, cache: URL)? {
    let manager = FileManager.default
    guard let id = Bundle.main.bundleIdentifier, let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first, let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first,
      let data = ownDirectory(in: support, id: id), let cache = ownDirectory(in: caches, id: id)
    else { return nil }
    try? manager.createDirectory(at: data, withIntermediateDirectories: true)
    try? manager.createDirectory(at: cache, withIntermediateDirectories: true)
    return (data, cache)
  }

  /// This app's folder under `base`: `<base>/<id>`, for an id that is not the Tauri app's, and never the Tauri
  /// app's folder there or anything inside it (an id with a `/` or a `..` in it could otherwise name one).
  static func ownDirectory(in base: URL, id: String) -> URL? {
    guard !id.isEmpty, id != realApp, !id.contains("/"), !id.contains("..") else { return nil }
    let own = base.appendingPathComponent(id, isDirectory: true).standardizedFileURL
    let theirs = base.appendingPathComponent(realApp, isDirectory: true).standardizedFileURL
    let ownParts = own.pathComponents, theirParts = theirs.pathComponents
    if ownParts.count >= theirParts.count && Array(ownParts.prefix(theirParts.count)) == theirParts { return nil }
    return own
  }

  // MARK: pictures

  /// A picture made ready for a note in the app's cache, or nil where it cannot be read: shrunk, turned and laid
  /// on paper by apple/PictureKeep.swift, the one file the Mac and the iPhone both keep a picture with.
  private static func keep(_ source: CGImageSource) -> String? {
    guard let dirs = dirs() else { return nil }
    return PictureKeep.keep(source, cache: dirs.cache)
  }

  /// The Mac's open panel for one picture, answered as the phone's chooser answers: `{path}` of a JPEG in the
  /// app's cache, shrunk and the right way up, `{cancelled: true}`, or an error with a sentence.
  private func pickPicture(_ result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.title = "Add a picture"
    panel.prompt = "Add"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.image]
    Panels.show(panel, on: window) { url in
      guard let url = url else { return result(["cancelled": true]) }
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let path = GhostChannels.keep(source) else {
        return result(FlutterError(code: "pictures", message: url.pathExtension.lowercased() == "heic" ? "This Mac can’t open that HEIC picture. Save it as a JPEG first." : "The picture could not be read.", details: nil))
      }
      result(["path": path])
    }
  }

  /// The clipboard as the phone's is read (lib/editor/band/clipboard.dart): a picture copied out of it as
  /// `{path}`, else its words as `{text}`, else nothing.
  private static func clipboard() -> [String: Any] {
    let board = NSPasteboard.general
    let pictures: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]
    if let type = board.availableType(from: pictures), let data = board.data(forType: type), let source = CGImageSourceCreateWithData(data as CFData, nil) {
      if let path = keep(source) { return ["path": path] }
      return ["error": "The picture on the clipboard could not be read."]
    }
    if let text = board.string(forType: .string), !text.isEmpty { return ["text": text] }
    return [:]
  }
}
