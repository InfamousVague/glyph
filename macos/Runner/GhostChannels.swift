import Cocoa
import FlutterMacOS
import ImageIO
import LocalAuthentication
import PDFKit
import Security
import Vision
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
  /// The home page shelf's, the cassettes in view loaded into them ahead (lib/tapes/previews.dart `tapePreviewsMost`).
  private let previews: [TapeChannel]
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
    previews = (0..<6).map { TapeChannel(messenger: messenger, name: "ghost_md/preview/\($0)") }
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

    // A meeting Ghost was in: its Opus packets made the note's 16 kHz WAV (MeetAudio.swift, lib/meet/tape.dart), off
    // the main thread, since an hour's meeting takes a while.
    listen("ghost_md/meet_audio", messenger) { call, result in
      guard call.method == "opusToWav" else { return result(FlutterMethodNotImplemented) }
      let args = call.arguments as? [String: Any]
      guard let packets = args?["packets"] as? String, let wav = args?["wav"] as? String else {
        return result(FlutterError(code: "meet_audio", message: "Where are the packets, and where does the sound go?", details: nil))
      }
      DispatchQueue.global(qos: .utility).async {
        do {
          let ms = try MeetAudio.opusToWav(packets: URL(fileURLWithPath: packets), wav: URL(fileURLWithPath: wav))
          DispatchQueue.main.async { result(["ms": ms]) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "meet_audio", message: "\(error)", details: nil)) }
        }
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

    // Documents in notes (lib/files/phone_documents.dart): a file from the open panel, a file handed to the Mac's
    // own app or shared, a PDF drawn, read and searched by PDFKit, and the words in a picture or a PDF read by
    // Vision, on the Mac. The scanner is the phone's: unanswered here, so the app does not offer it on a Mac.
    listen("ghost_md/documents", messenger) { [weak self] call, result in
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "pick": self?.pickFile(result)
      case "openWith": result(GhostChannels.openWith(path: args?["path"] as? String, name: args?["name"] as? String))
      case "share": result(self?.share(path: args?["path"] as? String, name: args?["name"] as? String))
      case "saving": result(ProcessInfo.processInfo.isLowPowerModeEnabled)
      case "readerReady": result(true)
      default:
        if !MacDocuments.shared.answer(call.method, args, result) { result(FlutterMethodNotImplemented) }
      }
    }
  }

  // MARK: files

  /// The Mac's open panel for any one file, answered as the phone's picker answers: `{path, name, bytes}` of a copy
  /// in the app's cache (`picked/`), `{cancelled: true}`, or an error with a sentence. Read only through the panel's
  /// own grant (`files.user-selected` in the store's sandbox).
  private func pickFile(_ result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.title = "Add a file"
    panel.prompt = "Add"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    Panels.show(panel, on: window) { url in
      guard let url = url else { return result(["cancelled": true]) }
      guard let dirs = GhostChannels.dirs() else { return result(FlutterError(code: "documents", message: "The file could not be read.", details: nil)) }
      let picked = dirs.cache.appendingPathComponent("picked", isDirectory: true)
      let copy = picked.appendingPathComponent("\(UUID().uuidString).part")
      do {
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > 512 * 1024 * 1024 { return result(FlutterError(code: "documents", message: "That file is too large to add.", details: nil)) }
        try FileManager.default.copyItem(at: url, to: copy)
        let bytes = (try? copy.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? size
        result(["path": copy.path, "name": url.lastPathComponent, "bytes": bytes])
      } catch {
        try? FileManager.default.removeItem(at: copy)
        result(FlutterError(code: "documents", message: "The file could not be read.", details: nil))
      }
    }
  }

  /// A file of the app's handed to the Mac's own app for its kind, under its own name: a copy in the cache's
  /// `open/`, opened by the workspace. Nil, or an error with a sentence.
  private static func openWith(path: String?, name: String?) -> Any? {
    guard let path = path, FileManager.default.fileExists(atPath: path), let dirs = dirs() else {
      return FlutterError(code: "documents", message: "That file is not on this Mac.", details: nil)
    }
    let safe = (name ?? "File").replacingOccurrences(of: "/", with: " ").replacingOccurrences(of: ":", with: " ")
    let folder = dirs.cache.appendingPathComponent("open", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
    let copy = folder.appendingPathComponent(safe.isEmpty ? "File" : safe)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: copy)
    } catch {
      return FlutterError(code: "documents", message: "That file could not be handed over.", details: nil)
    }
    return NSWorkspace.shared.open(copy) ? nil : FlutterError(code: "documents", message: "No app on this Mac opens that file.", details: nil)
  }

  /// The Mac's share menu for a file of the app's, under its own name, from the window's top.
  private func share(path: String?, name: String?) -> Any? {
    guard let path = path, FileManager.default.fileExists(atPath: path), let dirs = GhostChannels.dirs(), let view = window?.contentView else {
      return FlutterError(code: "documents", message: "That file is not on this Mac.", details: nil)
    }
    let folder = dirs.cache.appendingPathComponent("open", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
    let copy = folder.appendingPathComponent((name ?? "File").replacingOccurrences(of: "/", with: " ").replacingOccurrences(of: ":", with: " "))
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: copy)
    } catch {
      return FlutterError(code: "documents", message: "That file could not be handed over.", details: nil)
    }
    NSSharingServicePicker(items: [copy]).show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 40, width: 1, height: 1), of: view, preferredEdge: .minY)
    return nil
  }

  private func listen(_ name: String, _ messenger: FlutterBinaryMessenger, _ handler: @escaping FlutterMethodCallHandler) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler(handler)
    held.append(channel)
  }

  /// A link the system handed the app (AppDelegate `application(_:open:)`). Only the app's own scheme is kept, and
  /// a .ghostex opened from Finder (Info.plist's `com.mattssoftware.ghostex`), kept as the app's own link to it,
  /// `ghostmd://ghostex?path=…`, which the page sends to Settings › Import (lib/export/ghostex_calls.dart
  /// `ghostexLinked`).
  func arrived(_ url: URL) {
    if url.isFileURL {
      guard url.pathExtension.lowercased() == "ghostex" else { return }
      var link = URLComponents()
      link.scheme = "ghostmd"
      link.host = "ghostex"
      link.queryItems = [URLQueryItem(name: "path", value: url.path)]
      guard let made = link.url?.absoluteString else { return }
      keptLinks.append(made)
      links?.invokeMethod("arrived", arguments: nil)
      return
    }
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

/// The Mac's half of a PDF drawn in the app and of the words read in pictures and PDFs (lib/files/phone_documents.dart):
/// PDFKit draws a page into RGBA pixels and finds words on it; Vision reads the words in a picture, or in a page
/// with none of its own. Each on a queue of its own, off the main thread; nothing leaves the Mac.
final class MacDocuments {
  static let shared = MacDocuments()

  private var open: [Int: PDFDocument] = [:]
  private var next = 1
  private let drawing = DispatchQueue(label: "ghost.documents.draw", qos: .userInitiated)
  private let reading = DispatchQueue(label: "ghost.documents.read", qos: .background)

  /// Answers one of the PDF or reading calls; false for any other.
  func answer(_ method: String, _ args: [String: Any]?, _ result: @escaping FlutterResult) -> Bool {
    let queue: DispatchQueue
    let work: () -> Any?
    switch method {
    case "pdfOpen": queue = drawing; work = { self.pdfOpen(args?["path"] as? String) }
    case "pdfPage": queue = drawing; work = { self.pdfPage(args) }
    case "pdfText": queue = drawing; work = { self.page(args).flatMap { $0.string } ?? "" }
    case "pdfFind": queue = drawing; work = { self.pdfFind(args) }
    case "pdfClose": queue = drawing; work = { self.open.removeValue(forKey: args?["id"] as? Int ?? 0); return nil }
    case "read": queue = reading; work = { self.read(args) }
    default: return false
    }
    queue.async {
      let said = work()
      DispatchQueue.main.async { result(said) }
    }
    return true
  }

  private func failed(_ sentence: String) -> FlutterError { FlutterError(code: "documents", message: sentence, details: nil) }

  private func pdfOpen(_ path: String?) -> Any? {
    guard let path = path, let document = PDFDocument(url: URL(fileURLWithPath: path)) else { return failed("This PDF can’t be opened.") }
    if document.isLocked { return failed("This PDF has a password, and can’t be opened here.") }
    var sizes: [[Double]] = []
    for index in 0..<document.pageCount {
      let box = document.page(at: index)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
      sizes.append([Double(box.width), Double(box.height)])
    }
    let id = next
    next += 1
    open[id] = document
    return ["id": id, "pages": sizes]
  }

  private func page(_ args: [String: Any]?) -> PDFPage? {
    guard let document = open[args?["id"] as? Int ?? 0] else { return nil }
    return document.page(at: args?["page"] as? Int ?? 0)
  }

  /// A page drawn `width` pixels across on white, as RGBA, its long side at most 4096 px.
  private func drawn(_ page: PDFPage, width: Int) -> (pixels: Data, width: Int, height: Int)? {
    let box = page.bounds(for: .mediaBox)
    guard box.width > 0, box.height > 0 else { return nil }
    var w = max(1, min(width, 4096))
    var h = max(1, Int((Double(w) * Double(box.height) / Double(box.width)).rounded()))
    if h > 4096 {
      w = max(1, Int(Double(w) * 4096 / Double(h)))
      h = 4096
    }
    var data = Data(count: w * h * 4)
    let made = data.withUnsafeMutableBytes { raw -> Bool in
      guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: w, height: h))
      context.scaleBy(x: CGFloat(w) / box.width, y: CGFloat(h) / box.height)
      context.translateBy(x: -box.minX, y: -box.minY)
      page.draw(with: .mediaBox, to: context)
      return true
    }
    return made ? (data, w, h) : nil
  }

  private func pdfPage(_ args: [String: Any]?) -> Any? {
    guard let page = page(args), let drawn = drawn(page, width: args?["width"] as? Int ?? 1080) else { return failed("There is no such page.") }
    return ["width": drawn.width, "height": drawn.height, "pixels": FlutterStandardTypedData(bytes: drawn.pixels)]
  }

  private func pdfFind(_ args: [String: Any]?) -> Any? {
    guard let document = open[args?["id"] as? Int ?? 0], let index = args?["page"] as? Int, let page = document.page(at: index), let query = args?["query"] as? String, !query.isEmpty else { return [] }
    let box = page.bounds(for: .mediaBox)
    var found: [[Double]] = []
    for selection in document.findString(query, withOptions: [.caseInsensitive]) where selection.pages.contains(page) {
      let at = selection.bounds(for: page)
      // PDF space is from the page's foot; the app's is from its top.
      found.append([Double(at.minX - box.minX), Double(box.maxY - at.maxY), Double(at.maxX - box.minX), Double(box.maxY - at.minY)])
    }
    return found
  }

  /// The words Vision reads in a picture.
  private func recognised(_ image: CGImage) -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
  }

  private func read(_ args: [String: Any]?) -> Any? {
    guard let path = args?["path"] as? String, FileManager.default.fileExists(atPath: path) else { return failed("That file is not here.") }
    let url = URL(fileURLWithPath: path)
    if args?["pdf"] as? Bool != true {
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return failed("That picture could not be read.") }
      return ["pages": [recognised(image)]]
    }
    guard let document = PDFDocument(url: url), !document.isLocked else { return failed("This PDF can’t be read.") }
    var pages: [String] = []
    for index in 0..<min(document.pageCount, args?["most"] as? Int ?? 60) {
      guard let page = document.page(at: index) else { pages.append(""); continue }
      let own = page.string ?? ""
      if !own.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        pages.append(own)
        continue
      }
      let box = page.bounds(for: .mediaBox)
      let width = Int(2000 * box.width / max(box.width, box.height, 1))
      guard let drawn = drawn(page, width: width), let provider = CGDataProvider(data: drawn.pixels as CFData),
        let image = CGImage(width: drawn.width, height: drawn.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: drawn.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
      else { pages.append(""); continue }
      pages.append(recognised(image))
    }
    return ["pages": pages]
  }
}
