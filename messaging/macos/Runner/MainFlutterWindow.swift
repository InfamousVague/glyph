import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var desk: DeskChannels?
  private var updates: UpdatesChannel?
  private var chrome: FlutterMethodChannel?
  /// The app's header, which the three buttons sit centred in, and how far in from the left the first one is.
  private var barHeight: CGFloat = 56
  private var lightsX: CGFloat = 20

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // Two panes side by side need room: the list and a conversation.
    self.minSize = NSSize(width: 760, height: 520)
    self.title = "Ghost Messaging"
    // The window draws edge to edge: no title strip of the Mac's own above the app. Each page's header is the top
    // bar, in the theme's colours, with the three buttons folded down into it and the window dragged by it (Matt,
    // 2026-11-17: "move the toolbar top bar into our own topbar component so it can match themes on mac make it fold
    // the traffic lights down and shift over the chat list on the sidebar and make the top bars draggable areas").
    // The app says how tall its header is and whether its look is dark (lib/desktop/window_chrome.dart).
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.isMovableByWindowBackground = false
    self.backgroundColor = .black
    chrome = FlutterMethodChannel(name: "ghost_desktop/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    chrome?.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "chrome":
        let a = call.arguments as? [String: Any] ?? [:]
        if let h = a["height"] as? Double { self.barHeight = CGFloat(h) }
        if let x = a["x"] as? Double { self.lightsX = CGFloat(x) }
        if let dark = a["dark"] as? Bool { self.appearance = NSAppearance(named: dark ? .darkAqua : .aqua) }
        self.placeLights()
        result(nil)
      case "drag":
        // The press that began on a top bar moves the window, as a title bar does.
        if let e = NSApp.currentEvent ?? self.currentEvent { self.performDrag(with: e) }
        result(nil)
      case "zoom":
        // A double click on a top bar does what the Mac is set to (Desktop & Dock › Double-click a window's title bar).
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": self.performMiniaturize(nil)
        case "None": break
        default: self.performZoom(nil)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    for name in [NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
      NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in self?.placeLights() }
    }
    placeLights()
    DispatchQueue.main.async { [weak self] in self?.placeLights() }

    // Nothing of a video played in an earlier run is left on the disk (DeskVideo.swift), nor after this one.
    DeskVideo.sweep()
    NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in DeskVideo.sweep() }

    RegisterGeneratedPlugins(registry: flutterViewController)
    desk = DeskChannels(messenger: flutterViewController.engine.binaryMessenger)
    // The microphone's processing in calls (VoiceFx.swift).
    VoiceFx.shared.register(messenger: flutterViewController.engine.binaryMessenger)
    Sounds.shared.register(messenger: flutterViewController.engine.binaryMessenger)
    // The app's own updates (UpdatesChannel.swift): its first act is to say this version opened, which an update
    // put in place a moment ago is waiting to hear.
    updates = UpdatesChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// The three buttons centred in the app's header: the strip that holds them made as tall as the header, and each
  /// placed in it. AppKit puts them back at its own height on some changes, so this runs again after each.
  func placeLights() {
    guard !styleMask.contains(.fullScreen),
          let close = standardWindowButton(.closeButton),
          let mini = standardWindowButton(.miniaturizeButton),
          let zoom = standardWindowButton(.zoomButton),
          let strip = close.superview?.superview else { return }
    let size = close.frame.height
    var f = strip.frame
    f.size.height = barHeight
    f.origin.y = frame.height - barHeight
    strip.frame = f
    let gap = mini.frame.minX - close.frame.minX
    let step = gap > 0 ? gap : 20
    for (i, b) in [close, mini, zoom].enumerated() {
      b.setFrameOrigin(NSPoint(x: lightsX + CGFloat(i) * step, y: (barHeight - size) / 2))
    }
  }

  /// The app's window closing takes any video's window with it, so the app quits as it did.
  override func close() {
    DeskVideo.shared.closeAll()
    super.close()
  }
}
