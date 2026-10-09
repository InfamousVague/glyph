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
/// THE APP'S FILES ARE ITS OWN. The bundle id is `com.mattssoftware.glyph.flutter` and the app is sandboxed, so
/// everything it keeps is under `~/Library/Containers/<that id>/Data`; the Tauri app's library
/// (`~/Library/Application Support/com.mattssoftware.glyph`) is outside the sandbox and cannot be opened, moved
/// or written from here. `dirs` refuses to answer at all should a build ever carry the Tauri app's own id.
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

    listen("ghost_md/device_paths", messenger) { [weak self] call, result in
      guard call.method == "dirs" else { return result(FlutterMethodNotImplemented) }
      guard let dirs = GhostChannels.dirs() else {
        return result(FlutterError(code: "paths", message: "Ghost Flutter will not open another app's files.", details: nil))
      }
      // A folder of the person's chosen for the library, or a drive allowed for a backup: their grants are taken
      // up again before the core opens anything.
      self?.files.restoreGrants()
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
  /// `app_cache_dir`), inside this app's own container. Nil for a build with the Tauri app's id.
  static func dirs() -> (data: URL, cache: URL)? {
    guard let id = Bundle.main.bundleIdentifier, id != realApp, !id.isEmpty else { return nil }
    let manager = FileManager.default
    guard let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first, let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
    let data = support.appendingPathComponent(id, isDirectory: true), cache = caches.appendingPathComponent(id, isDirectory: true)
    // Belt and braces: whatever the sandbox says, never the Tauri app's folder.
    if data.lastPathComponent == realApp || cache.lastPathComponent == realApp { return nil }
    try? manager.createDirectory(at: data, withIntermediateDirectories: true)
    try? manager.createDirectory(at: cache, withIntermediateDirectories: true)
    return (data, cache)
  }

  // MARK: pictures

  /// The long side a picture is kept at, and its quality: Pictures.kt's `MAX_PX` and 85.
  private static let longSide = 1600

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
    let done: (NSApplication.ModalResponse) -> Void = { response in
      guard response == .OK, let url = panel.url else { return result(["cancelled": true]) }
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let path = GhostChannels.keep(source) else {
        return result(FlutterError(code: "pictures", message: url.pathExtension.lowercased() == "heic" ? "This Mac can’t open that HEIC picture. Save it as a JPEG first." : "The picture could not be read.", details: nil))
      }
      result(["path": path])
    }
    if let window = window { panel.beginSheetModal(for: window, completionHandler: done) } else { done(panel.runModal()) }
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

  /// A picture shrunk to [longSide], turned as its EXIF says, laid on paper (a transparent screenshot must not
  /// turn black as a JPEG) and written to `<cache>/picked/<uuid>.jpg`. Answers the file's path.
  private static func keep(_ source: CGImageSource) -> String? {
    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: longSide]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), let dirs = dirs() else { return nil }
    let width = image.width, height = image.height
    guard width > 0, height > 0, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    let all = CGRect(x: 0, y: 0, width: width, height: height)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(all)
    context.draw(image, in: all)
    guard let flat = context.makeImage() else { return nil }
    let folder = dirs.cache.appendingPathComponent("picked", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let out = folder.appendingPathComponent("\(UUID().uuidString.lowercased()).jpg")
    guard let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, flat, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    return CGImageDestinationFinalize(destination) ? out.path : nil
  }
}

/// The secure store over the Mac's Keychain (lib/account/device_keys.dart `SecureStore`): one generic password to
/// a name, all under a service that is this app's bundle id, so nothing of another app's is ever read, written or
/// removed, the Tauri app's least of all.
enum Keychain {
  struct Failure: Error {
    let status: OSStatus
    var said: String {
      let words = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
      return "The Mac’s Keychain would not answer: \(words)"
    }
  }

  static var service: String { "\(Bundle.main.bundleIdentifier ?? "ghost-flutter").secure" }

  private static func query(_ name: String?) -> [CFString: Any] {
    var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
    if let name = name { query[kSecAttrAccount] = name }
    return query
  }

  static func read(_ name: String) -> Result<String?, Failure> {
    var query = query(name)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var found: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &found)
    if status == errSecItemNotFound { return .success(nil) }
    guard status == errSecSuccess, let data = found as? Data else { return .failure(Failure(status: status)) }
    return .success(String(data: data, encoding: .utf8))
  }

  static func write(_ name: String, _ value: String) -> Failure? {
    let data = Data(value.utf8)
    let changed = SecItemUpdate(query(name) as CFDictionary, [kSecValueData: data] as CFDictionary)
    if changed == errSecSuccess { return nil }
    guard changed == errSecItemNotFound else { return Failure(status: changed) }
    var item = query(name)
    item[kSecValueData] = data
    item[kSecAttrLabel] = "Ghost Flutter"
    let added = SecItemAdd(item as CFDictionary, nil)
    return added == errSecSuccess ? nil : Failure(status: added)
  }

  static func delete(_ name: String) -> Failure? {
    let status = SecItemDelete(query(name) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound ? nil : Failure(status: status)
  }

  /// Every secret this app keeps, gone. The Mac's file keychain removes one match a call, so it is asked until
  /// there is none (and never more than a few hundred times).
  static func clear() -> Bool {
    for _ in 0..<512 {
      let status = SecItemDelete(query(nil) as CFDictionary)
      if status == errSecItemNotFound { return true }
      if status != errSecSuccess { return false }
    }
    return false
  }
}
