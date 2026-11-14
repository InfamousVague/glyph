import Cocoa
import FlutterMacOS
import Security

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
    system.setMethodCallHandler { [weak self] call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "name":
        // "Matt's MacBook Pro", as System Settings › General › About has it.
        result(Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
      case "keyRead":
        result(DeskChannels.keychain(read: args["account"] as? String ?? ""))
      case "keyWrite":
        result(DeskChannels.keychain(write: args["account"] as? String ?? "", value: args["value"] as? String ?? ""))
      case "keyDelete":
        result(DeskChannels.keychain(delete: args["account"] as? String ?? ""))
      // A video in a message (DeskVideo.swift): a picture of where it starts, and a window that plays it.
      case "videoPreview":
        guard let bytes = (args["bytes"] as? FlutterStandardTypedData)?.data else { return result(nil) }
        let id = args["id"] as? Int ?? 0, ext = args["ext"] as? String ?? "mp4"
        DispatchQueue.global(qos: .userInitiated).async {
          let made = DeskVideo.preview(data: bytes, id: id, ext: ext)
          DispatchQueue.main.async { result(made) }
        }
      case "videoPlay":
        guard let bytes = (args["bytes"] as? FlutterStandardTypedData)?.data else { return result("no video") }
        result(DeskVideo.shared.play(data: bytes, id: args["id"] as? Int ?? 0, ext: args["ext"] as? String ?? "mp4", title: args["title"] as? String ?? "Video"))
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
