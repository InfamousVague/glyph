import Cocoa
import FlutterMacOS

/// The Mac app's one window, as the Tauri app's is (tauri/src-tauri/tauri.conf.json `app.windows[0]`, and
/// src/platform.rs `place_traffic_lights`): 1280 x 820 in the middle of the screen, never smaller than 360 x 560,
/// drawn under a transparent title bar with no title, its three lights set into the page's own top row.
///
/// The page says where that row's centre is (`ghost_md/window` `lights`), since the row's height is the page's to
/// know; until it has, the lights sit where the Tauri app's do for the default bar.
class MainFlutterWindow: NSWindow {
  /// The Tauri window's size and floor.
  static let opening = NSSize(width: 1280, height: 820)
  static let floor = NSSize(width: 360, height: 560)

  /// The lights' start gutter and the distance of their centre from the window's top, in points.
  private var lightsX: CGFloat = 16
  private var lightsCentre: CGFloat = 27

  private var channels: GhostChannels?

  /// The app's own updates (UpdatesChannel.swift), in every build but the Mac App Store's, which has none.
  private var updates: NSObject?

  /// A note's diagrams, drawn by a web view behind the app's own view (apple/DiagramRenderer.swift).
  private var diagrams: DiagramRenderer?
  private var windowChannel: FlutterMethodChannel?
  /// A job the app runs by itself (lib/core/background_jobs.dart), and the hold that keeps App Nap off it.
  private var jobsChannel: FlutterMethodChannel?
  private var jobHold: NSObjectProtocol?
  /// The jobs holding it: Lovart's header run, and any pictures Lovart is making besides. Let go when the last ends.
  private var jobsHeld = Set<String>()
  private var lastPress: NSEvent?
  private var pressMonitor: Any?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The window, before anything is drawn in it.
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    isMovableByWindowBackground = false
    minSize = MainFlutterWindow.floor
    contentMinSize = MainFlutterWindow.floor
    // The page's own ground (--app-ground in the dark), so a resize never flashes white at the edge.
    backgroundColor = NSColor(calibratedRed: 0.051, green: 0.051, blue: 0.051, alpha: 1)
    setContentSize(MainFlutterWindow.opening)
    if let screen = self.screen ?? NSScreen.main {
      // A screen smaller than the opening size gets what fits.
      let room = screen.visibleFrame
      let size = NSSize(width: min(frame.width, room.width), height: min(frame.height, room.height))
      setFrame(NSRect(x: room.midX - size.width / 2, y: room.midY - size.height / 2, width: size.width, height: size.height), display: false)
    }
    // Where the person left it, on later launches.
    setFrameAutosaveName("GhostFlutterMain")

    RegisterGeneratedPlugins(registry: flutterViewController)
    let messenger = flutterViewController.engine.binaryMessenger
    channels = GhostChannels(messenger: messenger, window: self)
    #if !GHOST_MAC_STORE
    updates = UpdatesChannel(messenger: messenger)
    #endif
    // A ```mermaid fence drawn as its diagram (apple/DiagramRenderer.swift; lib/editor/diagrams/bridge.dart).
    diagrams = DiagramRenderer(messenger: messenger) { [weak flutterViewController] in flutterViewController?.view }

    let window = FlutterMethodChannel(name: "ghost_md/window", binaryMessenger: messenger)
    window.setMethodCallHandler { [weak self] call, result in self?.asked(call, result) }
    windowChannel = window
    // A job the app runs by itself, Lovart's header images for the recent notes (lib/plugins/lovart/banner_run.dart):
    // while it runs the app is kept out of App Nap, which slows the timers and fetches of an app whose window is
    // behind others. The Mac app quits with its window, and a job it quit under goes on at the next launch.
    let jobs = FlutterMethodChannel(name: "ghost_md/jobs", binaryMessenger: messenger)
    jobs.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "running":
        let id = ((call.arguments as? [String: Any])?["id"] as? String) ?? ""
        self?.jobsHeld.insert(id)
        if self?.jobHold == nil {
          self?.jobHold = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Ghost.md is working on your notes")
        }
        result("running")
      case "ended":
        let id = ((call.arguments as? [String: Any])?["id"] as? String) ?? ""
        self?.jobsHeld.remove(id)
        if self?.jobsHeld.isEmpty ?? true {
          if let hold = self?.jobHold { ProcessInfo.processInfo.endActivity(hold) }
          self?.jobHold = nil
        }
        result("ended")
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    jobsChannel = jobs
    (NSApp.delegate as? AppDelegate)?.window = self

    // The press a drag of the window starts from: `performDrag` wants the event itself, and the page's word that a
    // drag began arrives a turn after it.
    pressMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
      if event.window === self { self?.lastPress = event }
      return event
    }

    let centre = NotificationCenter.default
    for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didExitFullScreenNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didBecomeKeyNotification] {
      centre.addObserver(self, selector: #selector(placeLights), name: name, object: self)
    }
    centre.addObserver(self, selector: #selector(fullScreenChanged), name: NSWindow.didEnterFullScreenNotification, object: self)
    centre.addObserver(self, selector: #selector(fullScreenChanged), name: NSWindow.didExitFullScreenNotification, object: self)

    super.awakeFromNib()
    placeLights()
  }

  /// A link the system handed the app (AppDelegate), kept for the page (`ghost_md/links`).
  func arrived(_ url: URL) {
    channels?.arrived(url)
  }

  /// Says a menu's choice to the page (`ghost_md/window` `menu`, lib/shell/desktop/mac_window.dart).
  func say(menu: String) {
    windowChannel?.invokeMethod("menu", arguments: menu)
  }

  @objc private func fullScreenChanged() {
    windowChannel?.invokeMethod("fullScreen", arguments: styleMask.contains(.fullScreen))
  }

  /// Sets the three lights into the page's row: the title bar's own strip is made as tall as twice the row's
  /// centre, so the lights, which AppKit centres in it, sit on that centre, and each is moved to the row's start
  /// gutter. AppKit lays them out again on every resize, so this is called again then.
  @objc func placeLights() {
    guard !styleMask.contains(.fullScreen), let close = standardWindowButton(.closeButton), let mini = standardWindowButton(.miniaturizeButton), let zoom = standardWindowButton(.zoomButton), let bar = close.superview, let container = bar.superview else { return }
    let height = max(lightsCentre * 2, 28)
    var held = container.frame
    held.size.height = height
    held.origin.y = frame.height - height
    container.frame = held
    let gap = mini.frame.minX - close.frame.minX
    let step = gap > 0 ? gap : 20
    for (index, button) in [close, mini, zoom].enumerated() {
      var at = button.frame
      at.origin.x = lightsX + CGFloat(index) * step
      at.origin.y = (bar.bounds.height - at.height) / 2
      button.frame = at
    }
  }

  private func asked(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "lights":
      // Where the page's top row puts them: its start gutter and its centre from the window's top.
      if let x = args?["x"] as? Double, let centre = args?["centre"] as? Double, x >= 0, centre >= 10, centre <= 200 {
        lightsX = CGFloat(x)
        lightsCentre = CGFloat(centre)
        placeLights()
      }
      result(nil)
    case "drag":
      // The page's drag strip was pressed and moved: the window follows, as under a title bar.
      if let press = lastPress, NSEvent.pressedMouseButtons & 1 == 1 {
        performDrag(with: press)
        result(true)
      } else {
        // No button is down (the press was not a mouse's): nothing to follow.
        result(false)
      }
    case "zoom":
      // A double click on the strip: what the person chose for a title bar's double click.
      let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
      if action == "Minimize" { miniaturize(nil) } else if action != "None" { zoom(nil) }
      result(nil)
    case "state":
      result(["fullScreen": styleMask.contains(.fullScreen), "width": Double(frame.width), "height": Double(frame.height)])
    case "snapshot":
      #if DEBUG
      result(snapshot(to: args?["name"] as? String ?? "window"))
      #else
      result(FlutterMethodNotImplemented)
      #endif
    case "key":
      #if DEBUG
      result(press(key: args?["key"] as? String ?? "", command: args?["command"] as? Bool ?? false, shift: args?["shift"] as? Bool ?? false))
      #else
      result(FlutterMethodNotImplemented)
      #endif
    case "resize":
      #if DEBUG
      if let width = args?["width"] as? Double, let height = args?["height"] as? Double {
        var to = frame
        to.origin.y += to.height - CGFloat(height)
        to.size = NSSize(width: CGFloat(width), height: CGFloat(height))
        setFrame(to, display: true)
      }
      result(nil)
      #else
      result(FlutterMethodNotImplemented)
      #endif
    case "panels":
      #if DEBUG
      // How the next panel is answered without a hand on it (FilesChannel.swift `Panels`).
      Panels.answer = Panels.Answer(folder: args?["folder"] as? String, name: args?["name"] as? String, file: args?["file"] as? String, cancel: args?["cancel"] as? Bool ?? false)
      result(nil)
      #else
      result(FlutterMethodNotImplemented)
      #endif
    case "link":
      #if DEBUG
      // A link handed to the app's own delegate, exactly as macOS hands one: nothing is opened through the
      // system, so no other app that claims the scheme can be the one that gets it.
      if let said = args?["url"] as? String, let url = URL(string: said), let delegate = NSApp.delegate as? AppDelegate {
        delegate.application(NSApp, open: [url])
        result(true)
      } else {
        result(false)
      }
      #else
      result(FlutterMethodNotImplemented)
      #endif
    case "quit":
      #if DEBUG
      result(nil)
      NSApp.terminate(nil)
      #else
      result(FlutterMethodNotImplemented)
      #endif
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  #if DEBUG
  /// A debug build's only, for looking at the app without touching the person's screen (lib/shell/desktop/
  /// mac_tour.dart): the window as it is drawn, frame and lights included, written as a PNG in the app's own
  /// temporary folder. Answers the file's path. The window's own picture is asked of the window server, which
  /// needs no screen recording permission for a window of this process; where that is refused the content view is
  /// drawn into a bitmap instead (no lights then).
  private func snapshot(to name: String) -> String? {
    let safe = name.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tour", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let out = dir.appendingPathComponent("\(safe.isEmpty ? "window" : safe).png")
    var rep: NSBitmapImageRep?
    if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(windowNumber), [.boundsIgnoreFraming, .bestResolution]), image.width > 1 {
      rep = NSBitmapImageRep(cgImage: image)
    } else if let view = contentView?.superview ?? contentView, let drawn = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
      view.cacheDisplay(in: view.bounds, to: drawn)
      rep = drawn
    }
    guard let png = rep?.representation(using: .png, properties: [:]) else { return nil }
    do {
      try png.write(to: out)
      return out.path
    } catch {
      return nil
    }
  }

  /// A debug build's only: a key pressed in this window alone, as the keyboard would send it, so the menu's
  /// shortcuts and the page's keys can be walked without a keystroke reaching any other app. Never a global event.
  private func press(key: String, command: Bool, shift: Bool) -> Bool {
    let codes: [String: UInt16] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, " ": 49, "#": 20, "*": 28, "-": 27, "escape": 53, "return": 36, "tab": 48, "left": 123, "right": 124, "down": 125, "up": 126, "delete": 51, "space": 49]
    guard let code = codes[key] else { return false }
    // With the bits that say which side's key it is (the left ones), as a keyboard's events carry them: Flutter
    // reads which modifiers are held from those.
    let leftCommand = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x08)
    let leftShift = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x02)
    var flags: NSEvent.ModifierFlags = []
    if command { flags.insert(leftCommand) }
    if shift { flags.insert(leftShift) }
    let chars: String
    switch key {
    case "escape": chars = "\u{1B}"
    case "return": chars = "\r"
    case "tab": chars = "\t"
    case "delete": chars = "\u{7F}"
    case "left": chars = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    case "right": chars = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    case "up": chars = String(UnicodeScalar(NSUpArrowFunctionKey)!)
    case "down": chars = String(UnicodeScalar(NSDownArrowFunctionKey)!)
    case "space": chars = " "
    default: chars = key
    }
    // The modifiers go down first and come up after, as a keyboard's do: Flutter keeps its own count of which
    // are held from these, not from a key's flags.
    func modifier(_ code: UInt16, _ held: NSEvent.ModifierFlags) {
      if let event = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: held, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code) {
        NSApp.sendEvent(event)
      }
    }
    var held: NSEvent.ModifierFlags = []
    if command {
      held.insert(leftCommand)
      modifier(55, held)
    }
    if shift {
      held.insert(leftShift)
      modifier(56, held)
    }
    for type in [NSEvent.EventType.keyDown, .keyUp] {
      guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil, characters: shift && key != "#" && key != "*" ? chars.uppercased() : chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) else { return false }
      // Through the app, as a key from the keyboard goes: the window's views first (Flutter's), then the menu.
      NSApp.sendEvent(event)
    }
    if shift {
      held.remove(leftShift)
      modifier(56, held)
    }
    if command {
      held.remove(leftCommand)
      modifier(55, held)
    }
    return true
  }
  #endif
}
