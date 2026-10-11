import Cocoa
import FlutterMacOS

/// The Mac app's delegate: its menu bar, and the links that open it.
///
/// THE MENU is the Mac's own for an app with one window (the Tauri app wears Tauri's default: the app's, File,
/// Edit, View, Window), with the page's keys in it by name, so each is found where a Mac's person looks for it and
/// works wherever the keyboard is: New Note (Command-N, ../glyph docs/DESIGN.md §144), Sync Now (Command-R, §210:
/// a Mac has no page to pull down), Find (Command-F), the command palette (Command-K, the kit's own key) and
/// Settings (Command-comma). Choosing one says its name to the page (`ghost_md/window` `menu`,
/// lib/shell/desktop/mac_window.dart), which does what its own button would.
///
/// Flutter is offered every key first (its view's `performKeyEquivalent`), so a key the page handles where the
/// keyboard is (Command-F in a note's editor, Command-Z in a field) is the page's, and the menu takes what it
/// leaves. Undo, Redo, Cut, Copy, Paste and Select All go to the first responder, which is Flutter's text input
/// while something is being typed into.
@main
class AppDelegate: FlutterAppDelegate {
  /// The app's one window, set by it once it is made.
  weak var window: MainFlutterWindow?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = menuBar()
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// A link that opens the app (`ghostmd://…`, claimed in Info.plist's CFBundleURLTypes; Matt, 2026-10-09: "claim
  /// it"): a note, the notifications, an organization, an invitation, something shared. macOS hands them here at
  /// launch and while the app runs; each is kept for the page, which takes them when it is ready
  /// (`ghost_md/links`, lib/core/phone_links.dart). On a Mac that also has the Tauri app, both claim the scheme
  /// and macOS chooses one of them.
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls { window?.arrived(url) }
  }

  @objc private func menuSaid(_ sender: NSMenuItem) {
    guard let name = sender.representedObject as? String else { return }
    window?.makeKeyAndOrderFront(nil)
    window?.say(menu: name)
  }

  private func item(_ title: String, _ key: String, said name: String, modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(menuSaid(_:)), keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.target = self
    item.representedObject = name
    return item
  }

  private func plain(_ title: String, _ action: Selector?, _ key: String = "", modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    return item
  }

  private func menuBar() -> NSMenu {
    let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ProcessInfo.processInfo.processName
    let bar = NSMenu()
    func add(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
      let menu = NSMenu(title: title)
      for item in items { menu.addItem(item) }
      let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      holder.submenu = menu
      bar.addItem(holder)
      return menu
    }

    let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
    let servicesMenu = NSMenu(title: "Services")
    services.submenu = servicesMenu
    NSApp.servicesMenu = servicesMenu
    _ = add(name, [
      plain("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
      .separator(),
      item("Settings…", ",", said: "settings"),
      .separator(),
      services,
      .separator(),
      plain("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
      plain("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option]),
      plain("Show All", #selector(NSApplication.unhideAllApplications(_:))),
      .separator(),
      plain("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"),
    ])

    _ = add("File", [
      item("New Note", "n", said: "newNote"),
      .separator(),
      item("Sync Now", "r", said: "sync"),
      .separator(),
      plain("Close Window", #selector(NSWindow.performClose(_:)), "w"),
    ])

    _ = add("Edit", [
      plain("Undo", Selector(("undo:")), "z"),
      plain("Redo", Selector(("redo:")), "z", modifiers: [.command, .shift]),
      .separator(),
      plain("Cut", #selector(NSText.cut(_:)), "x"),
      plain("Copy", #selector(NSText.copy(_:)), "c"),
      plain("Paste", #selector(NSText.paste(_:)), "v"),
      plain("Select All", #selector(NSText.selectAll(_:)), "a"),
      .separator(),
      item("Find…", "f", said: "find"),
    ])

    _ = add("View", [
      item("Command Palette…", "k", said: "palette"),
      .separator(),
      plain("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", modifiers: [.command, .control]),
    ])

    let windowMenu = add("Window", [
      plain("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
      plain("Zoom", #selector(NSWindow.performZoom(_:))),
      .separator(),
      plain("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
    ])
    NSApp.windowsMenu = windowMenu
    return bar
  }
}
