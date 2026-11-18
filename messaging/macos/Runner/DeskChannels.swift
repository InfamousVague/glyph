import Cocoa
import FlutterMacOS
import AVFoundation
import Security
import UniformTypeIdentifiers

/// What the Mac app asks of macOS itself (lib/desktop/platform.dart): the Mac's name, the Keychain for the pairing's
/// key, and Bonjour to find the phone on the local network. Everything else, the sealing and the connections, is
/// Dart (lib/desktop/link), so it is the same code the tests run.
final class DeskChannels: NSObject, FlutterStreamHandler, NetServiceBrowserDelegate, NetServiceDelegate {
  private let system: FlutterMethodChannel
  private let found: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var browser: NetServiceBrowser?
  private var services: [NetService] = []

  init(messenger: FlutterBinaryMessenger) {
    system = FlutterMethodChannel(name: "ghost_desktop/system", binaryMessenger: messenger)
    found = FlutterEventChannel(name: "ghost_desktop/bonjour", binaryMessenger: messenger)
    super.init()
    found.setStreamHandler(self)
    // Where the voice message being played has got to, told to the screens as the phone tells its own.
    DeskSound.shared.heard = { [weak self] state in self?.system.invokeMethod("voice", arguments: state) }
    system.setMethodCallHandler { [weak self] call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "videoFrame":
        // A frame of the video at `path` as a PNG, for its preview in a Files space (Matt, 2026-11-18: "videos having a
        // frame from the first minute of the video"): a tenth of the way in, at least a second, never past the first
        // minute; at most 480 across. Nil where AVFoundation can't read it.
        guard let path = args["path"] as? String else { return result(nil) }
        DispatchQueue.global(qos: .userInitiated).async {
          let png = videoFramePNG(path)
          DispatchQueue.main.async { result(png.map { FlutterStandardTypedData(bytes: $0) }) }
        }
      case "name":
        // "Matt's MacBook Pro", as System Settings › General › About has it.
        result(Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
      case "keyRead":
        result(DeskChannels.keychain(read: args["account"] as? String ?? ""))
      case "keyWrite":
        result(DeskChannels.keychain(write: args["account"] as? String ?? "", value: args["value"] as? String ?? ""))
      case "keyDelete":
        result(DeskChannels.keychain(delete: args["account"] as? String ?? ""))
      // What the message field has on a Mac that the phone has from Android: pictures to choose, the Mac's own
      // emoji, and a voice message to record and to play (DeskSound.swift).
      case "pickPictures":
        result(DeskChannels.pickPictures(most: args["most"] as? Int ?? 5))
      case "pasteImage":
        result(DeskChannels.pasteImage())
      // A Files space (lib/files/file_platform.dart): any files to add, where to save one, and the Mac's share menu.
      case "pickFiles":
        result(DeskChannels.pickFiles(most: args["most"] as? Int ?? 50))
      case "saveFile":
        result(DeskChannels.saveFile(name: args["name"] as? String ?? "File"))
      case "shareFile":
        DeskChannels.shareFile(path: args["path"] as? String ?? "")
        result(nil)
      case "emoji":
        // The Mac's own "Emoji & Symbols": what is chosen there is typed into the field the cursor is in.
        NSApp.orderFrontCharacterPalette(nil)
        result(nil)
      case "voiceStart":
        DeskSound.shared.start(most: args["bytes"] as? Int ?? 0) { result($0) }
      case "voiceLevel":
        result(DeskSound.shared.level())
      case "voiceCancel":
        DeskSound.shared.cancel()
        result(nil)
      case "voiceStop":
        result(DeskSound.shared.stop().map { FlutterStandardTypedData(bytes: $0) })
      case "voicePlay":
        result(DeskSound.shared.play(part: args["part"] as? Int ?? -1, data: (args["bytes"] as? FlutterStandardTypedData)?.data))
      case "voicePause":
        DeskSound.shared.pause()
        result(nil)
      case "voiceHalt":
        DeskSound.shared.halt()
        result(nil)
      case "voiceLength":
        result((args["bytes"] as? FlutterStandardTypedData).map { DeskSound.length(of: $0.data) } ?? 0)
      // A video in a message (DeskVideo.swift): a picture of where it starts. It plays in the app's own player.
      case "videoPreview":
        guard let bytes = (args["bytes"] as? FlutterStandardTypedData)?.data else { return result(nil) }
        let id = args["id"] as? Int ?? 0, ext = args["ext"] as? String ?? "mp4"
        DispatchQueue.global(qos: .userInitiated).async {
          let made = DeskVideo.preview(data: bytes, id: id, ext: ext)
          DispatchQueue.main.async { result(made) }
        }
      case "browse":
        self?.browse()
        result(nil)
      case "stopBrowsing":
        self?.stopBrowsing()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: Choosing pictures

  /// The Mac's own panel for choosing files, for pictures: the paths chosen, none where it was put away.
  /// A picture on the clipboard, for pasting into the message field (Matt, 2026-11-16: "add the ability to paste
  /// images into the chatbar on desktop"): the path of an image file copied in the Finder, or a copied picture (a
  /// screenshot, an image copied from a page) written as a PNG to this run's folder. Nil where there is none, and
  /// the field pastes words as it always has.
  static func pasteImage() -> String? {
    let board = NSPasteboard.general
    if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
       let file = urls.first(where: { (try? $0.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) == true }) {
      return file.path
    }
    guard let image = (board.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first,
          let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
          let url = try? DeskVideo.place(named: "pasted-\(UUID().uuidString).png") else { return nil }
    do {
      try png.write(to: url)
      return url.path
    } catch {
      return nil
    }
  }

  private static func pickPictures(most: Int) -> [String] {
    let panel = NSOpenPanel()
    panel.title = "Choose pictures"
    panel.prompt = "Add"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = most > 1
    panel.allowedContentTypes = [.image]
    guard panel.runModal() == .OK else { return [] }
    return panel.urls.prefix(max(1, most)).map { $0.path }
  }

  // MARK: A Files space's files

  /// The Mac's panel for choosing files of any kind: the paths chosen, none where it was put away.
  private static func pickFiles(most: Int) -> [String] {
    let panel = NSOpenPanel()
    panel.title = "Choose files"
    panel.prompt = "Add"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = most > 1
    guard panel.runModal() == .OK else { return [] }
    return panel.urls.prefix(max(1, most)).map { $0.path }
  }

  /// The Mac's Save panel, starting in Downloads with the file's own name: the path chosen, nil where it was put away.
  /// The file is copied there by the app (Dart), which has it.
  private static func saveFile(name: String) -> String? {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    panel.canCreateDirectories = true
    panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return url.path
  }

  /// The Mac's share menu for the file at [path], shown from the middle of the window.
  private static func shareFile(path: String) {
    guard !path.isEmpty, let view = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else { return }
    let picker = NSSharingServicePicker(items: [URL(fileURLWithPath: path)])
    let at = NSRect(x: view.bounds.midX - 1, y: view.bounds.midY - 1, width: 2, height: 2)
    picker.show(relativeTo: at, of: view, preferredEdge: .minY)
  }

  // MARK: The Keychain: the pairing's key, as a generic password of this app's.

  private static let service = Bundle.main.bundleIdentifier ?? "com.infamousvague.ghostmessaging.mac"

  private static func query(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
  }

  private static func keychain(read account: String) -> String? {
    var q = query(account)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func keychain(write account: String, value: String) -> Bool {
    SecItemDelete(query(account) as CFDictionary)
    var q = query(account)
    q[kSecValueData as String] = value.data(using: .utf8)
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
  }

  private static func keychain(delete account: String) -> Bool {
    let status = SecItemDelete(query(account) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  // MARK: Bonjour: phones announcing _ghostmsg._tcp on this network (android DeskService.kt).

  private func browse() {
    if browser != nil { return }
    let b = NetServiceBrowser()
    b.delegate = self
    browser = b
    b.searchForServices(ofType: "_ghostmsg._tcp.", inDomain: "local.")
  }

  private func stopBrowsing() {
    browser?.stop()
    browser = nil
    services.removeAll()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    publish()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
    services.append(service)
    service.delegate = self
    service.resolve(withTimeout: 5)
  }

  func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
    services.removeAll { $0 == service }
    publish()
  }

  func netServiceDidResolveAddress(_ sender: NetService) { publish() }

  func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
    // It announced and could not be reached by name: asked again while it is still announced.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      guard let self = self, self.services.contains(sender) else { return }
      sender.resolve(withTimeout: 5)
    }
  }

  /// Every phone found and resolved: its name, its port, and its addresses as numbers.
  private func publish() {
    let list: [[String: Any]] = services.compactMap { s in
      guard s.port > 0 else { return nil }
      var addresses: [String] = []
      for data in s.addresses ?? [] {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let ok = data.withUnsafeBytes { raw -> Bool in
          guard let base = raw.baseAddress else { return false }
          return getnameinfo(base.assumingMemoryBound(to: sockaddr.self), socklen_t(data.count), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
        }
        if ok { addresses.append(String(cString: host)) }
      }
      if addresses.isEmpty, let name = s.hostName { addresses.append(name) }
      if addresses.isEmpty { return nil }
      return ["name": s.name, "port": s.port, "addresses": addresses]
    }
    sink?(list)
  }
}

/// A frame of the video at [path], a tenth of the way in (at least a second, never past the first minute), as a CGImage
/// at most 480 across.
func videoFrameImage(_ path: String) -> CGImage? {
  let asset = AVURLAsset(url: URL(fileURLWithPath: path))
  let secs = CMTimeGetSeconds(asset.duration)
  let at = secs.isFinite && secs > 0 ? min(max(secs * 0.1, min(1, secs / 2)), 60) : 1
  let gen = AVAssetImageGenerator(asset: asset)
  gen.appliesPreferredTrackTransform = true
  gen.maximumSize = CGSize(width: 480, height: 480)
  gen.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
  gen.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
  return try? gen.copyCGImage(at: CMTime(seconds: at, preferredTimescale: 600), actualTime: nil)
}

func videoFramePNG(_ path: String) -> Data? {
  guard let cg = videoFrameImage(path) else { return nil }
  return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
}
