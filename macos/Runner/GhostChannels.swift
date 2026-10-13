import Cocoa
import FlutterMacOS
import ImageIO
import LocalAuthentication
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
///
/// THE BUILD THAT REPLACES THE TAURI MAC APP (tool/cutover-build-mac.sh; docs/CUTOVER.md §7) has that app's bundle
/// id, since it is that app's next version, and STILL a folder of its own: `com.mattssoftware.glyph.v2` under
/// Application Support and under Caches ([cutoverFolder]). Not the Tauri app's folder, and not a folder inside it:
/// the rule above then holds for every build with nothing taken out of it (no path with a folder named
/// `com.mattssoftware.glyph` in it is ever written), the Tauri app's own reset and export never meet this app's
/// files, and somebody who puts the Tauri app back finds its folder exactly as it left it. Not
/// `com.mattssoftware.glyph.flutter` either, which is where a development build ("Ghost Flutter") keeps its
/// made-up notes: a person's library and a build under test never share a folder. What the Tauri app kept is
/// copied in once (lib/carry/mac_carry.dart).
final class GhostChannels: NSObject {
  /// The Tauri app's bundle id: this app's only in the build that replaces it, and never the name of its folder.
  static let realApp = "com.mattssoftware.glyph"

  /// The folder of the build that replaces the Tauri app, under Application Support and under Caches.
  static let cutoverFolder = "com.mattssoftware.glyph.v2"

  /// Whether this process runs in the App Sandbox: the Mac App Store's build (Runner/Store.entitlements,
  /// tool/cutover-build-mac-store.sh; docs/CUTOVER.md, section 9), and no other. macOS gives a sandboxed app its
  /// container's id in its environment. Sandboxed, `urls(for:in:)` answers inside the container
  /// (`~/Library/Containers/<bundle id>/Data/Library/…`), so [dirs] is there with no word changed; the Mac, not
  /// this code, keeps the app out of every other app's files; nothing is carried from an app outside the
  /// container ([webCryptoMasterKey] answers nothing); a folder the person chose is kept as a security-scoped
  /// bookmark (FilesChannel.swift); and the secure store has a service of its own (apple/Keychain.swift).
  static let sandboxed = !(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] ?? "").isEmpty

  private let files: FilesChannel
  private let tape: TapeChannel
  private let clips: TapeChannel
  private let mic: MicChannel
  private var held: [FlutterMethodChannel] = []
  private weak var window: NSWindow?
  private var links: FlutterMethodChannel?
  private var keptLinks: [String] = []

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    self.window = window
    files = FilesChannel(messenger: messenger, window: window)
    tape = TapeChannel(messenger: messenger)
    clips = TapeChannel(messenger: messenger, name: "ghost_md/clip")
    mic = MicChannel(messenger: messenger)
    super.init()

    listen("ghost_md/device_paths", messenger) { [unowned self] call, result in
      guard call.method == "dirs" else { return result(FlutterMethodNotImplemented) }
      // Asked once at launch, before the core is opened on the library: a sandboxed build takes up again the
      // folder the person chose for it (FilesChannel `restoreGrants`; nothing to do in a build that is not).
      self.files.restoreGrants()
      guard let dirs = GhostChannels.dirs() else {
        return result(FlutterError(code: "paths", message: "Ghost Flutter will not open another app's files.", details: nil))
      }
      result(["dataDir": dirs.data.path, "cacheDir": dirs.cache.path])
    }

    // The carry from the Tauri app (lib/carry/mac_carry.dart `MacCarryDevice`): the two things only the Mac can do
    // for it. Nothing here writes outside this app's own folder, and nothing is asked of the person.
    listen("ghost_md/tauri_carry", messenger) { call, result in
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "masterKey":
        result(GhostChannels.webCryptoMasterKey())
      case "clone":
        guard let from = args?["from"] as? String, let to = args?["to"] as? String else { return result(false) }
        result(GhostChannels.clone(from: from, to: to))
      default:
        result(FlutterMethodNotImplemented)
      }
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
  /// `app_cache_dir`); for the build that has the Tauri app's id, [cutoverFolder] in place of the id. Nil should
  /// either ever come out as the Tauri app's folder or a place inside it.
  static func dirs() -> (data: URL, cache: URL)? {
    let manager = FileManager.default
    guard let id = Bundle.main.bundleIdentifier, let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first, let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first,
      let data = ownDirectory(in: support, id: folderName(id: id)), let cache = ownDirectory(in: caches, id: folderName(id: id))
    else { return nil }
    try? manager.createDirectory(at: data, withIntermediateDirectories: true)
    try? manager.createDirectory(at: cache, withIntermediateDirectories: true)
    return (data, cache)
  }

  /// What this app's folder is called for a build with the bundle id `id`.
  static func folderName(id: String) -> String { id == realApp ? cutoverFolder : id }

  // MARK: the carry from the Tauri app

  /// What the login Keychain holds as the Tauri app's "WebCrypto Master Key" (WebKit's own item: a generic
  /// password, account `com.apple.WebKit.WebCrypto.master+<bundle id>`), as base64, for the carry to open the keys
  /// that app's web view kept (lib/carry/webkit_stores.dart). READ, never changed or removed.
  ///
  /// Only the build that replaces the Tauri app asks, and the Keychain is told not to ask the person: it hands
  /// the item over in silence to an app it takes for the one that made it (the same bundle id, signed by the same
  /// team), and to any other build it answers nothing, which the carry takes as "the password is asked once".
  static func webCryptoMasterKey() -> String? {
    guard Bundle.main.bundleIdentifier == realApp else { return nil }
    // Never from inside a sandbox: the item is another app's, and asking would only put a panel in front of the
    // person. The store's build carries nothing (lib/main.dart `_carry`), so nothing asks; this holds it here too.
    guard !sandboxed else { return nil }
    let context = LAContext()
    context.interactionNotAllowed = true
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: "com.apple.WebKit.WebCrypto.master+\(realApp)",
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
      kSecUseAuthenticationContext: context,
    ]
    // The login keychain's own switch for its "wants to use your confidential information" panel, off for this
    // one question and put back after it.
    var allowed: DarwinBoolean = true
    let known = SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess
    SecKeychainSetUserInteractionAllowed(false)
    defer { if known { SecKeychainSetUserInteractionAllowed(allowed.boolValue) } }
    var found: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
    return data.base64EncodedString()
  }

  /// A clone of one file: a second name for the same blocks on a disk that can (APFS), each then changing alone.
  /// Only ever INTO this app's own folder, and never over a file.
  static func clone(from: String, to: String) -> Bool {
    guard let dirs = dirs() else { return false }
    let target = URL(fileURLWithPath: to).standardizedFileURL.path
    guard target.hasPrefix(dirs.data.standardizedFileURL.path + "/") else { return false }
    return clonefile(from, target, UInt32(CLONE_NOFOLLOW)) == 0
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
