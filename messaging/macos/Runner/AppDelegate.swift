import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// A circle's invite opened from its page (site/join: ghostmsg://join/#c.…): handed to the app (lib/desktop/links.dart),
  /// or held until it asks, when it is still starting.
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls { DeskLinks.shared.opened(url.absoluteString) }
  }
}

/// "ghost_desktop/links": links opened into the app, waiting in [pending] until the app takes them ("take"), then
/// handed over as they come ("open").
final class DeskLinks {
  static let shared = DeskLinks()
  private var channel: FlutterMethodChannel?
  private var pending: [String] = []
  private var taken = false

  func attach(messenger: FlutterBinaryMessenger) {
    let c = FlutterMethodChannel(name: "ghost_desktop/links", binaryMessenger: messenger)
    c.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == "take" else { return result(FlutterMethodNotImplemented) }
      self.taken = true
      result(self.pending)
      self.pending.removeAll()
    }
    channel = c
  }

  func opened(_ url: String) {
    if taken, let channel {
      channel.invokeMethod("open", arguments: url)
    } else {
      pending.append(url)
    }
    NSApp.activate(ignoringOtherApps: true)
  }
}
