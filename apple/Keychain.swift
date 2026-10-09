import Foundation
import Security

/// The secure store over Apple's Keychain (lib/account/device_keys.dart `SecureStore`), for the iPhone app and
/// written for the Mac's too: one generic password to a name, all under a service that is this app's bundle id, so
/// nothing of another app's is ever read, written or removed, the Tauri app's least of all.
///
/// SHARED (apple/, README "Each channel, and its iPhone half"): compiled into ios/Runner. The Mac app still carries
/// the enum this was taken from inside macos/Runner/GhostChannels.swift, word for word but the two `#if`s below;
/// when that file is next at rest the Mac's copy goes and its target takes this file.
///
/// On an iPhone a secret is kept for this device alone and read once the phone has been unlocked since it was
/// started: never in an iCloud Keychain, never carried to another phone by a backup, as Android's Keystore holds
/// its own. The Mac's file keychain has no such classes and is told nothing.
enum Keychain {
  struct Failure: Error {
    let status: OSStatus
    var said: String {
      let words = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
      #if os(iOS)
      return "The iPhone’s Keychain would not answer: \(words)"
      #else
      return "The Mac’s Keychain would not answer: \(words)"
      #endif
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
    #if os(iOS)
    item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    #endif
    let added = SecItemAdd(item as CFDictionary, nil)
    return added == errSecSuccess ? nil : Failure(status: added)
  }

  static func delete(_ name: String) -> Failure? {
    let status = SecItemDelete(query(name) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound ? nil : Failure(status: status)
  }

  /// Every secret this app keeps, gone. The Mac's file keychain removes one match a call and the iPhone's all of
  /// them, so it is asked until there is none (and never more than a few hundred times).
  static func clear() -> Bool {
    for _ in 0..<512 {
      let status = SecItemDelete(query(nil) as CFDictionary)
      if status == errSecItemNotFound { return true }
      if status != errSecSuccess { return false }
    }
    return false
  }
}
