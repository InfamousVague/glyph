import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var desk: DeskChannels?
  private var updates: UpdatesChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // Two panes side by side need room: the list and a conversation.
    self.minSize = NSSize(width: 760, height: 520)
    self.title = "Ghost Messaging"
    // The top bar is black, in the light theme and the dark (Matt, 2026-11-13: "make the top bar on the mac app
    // black"), as the app's icon and its dark pages are. A title bar with no material of its own shows the window's
    // colour, which is black; and the window's own chrome is drawn as on a dark window, so the title is white and
    // the three buttons read on it. This is the window's appearance only: the pages follow the Mac's light or dark
    // setting as before (Flutter reads the app's, not this window's).
    self.titlebarAppearsTransparent = true
    self.backgroundColor = .black
    self.appearance = NSAppearance(named: .darkAqua)

    // Nothing of a video played in an earlier run is left on the disk (DeskVideo.swift), nor after this one.
    DeskVideo.sweep()
    NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in DeskVideo.sweep() }

    RegisterGeneratedPlugins(registry: flutterViewController)
    desk = DeskChannels(messenger: flutterViewController.engine.binaryMessenger)
    // The app's own updates (UpdatesChannel.swift): its first act is to say this version opened, which an update
    // put in place a moment ago is waiting to hear.
    updates = UpdatesChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// The app's window closing takes any video's window with it, so the app quits as it did.
  override func close() {
    DeskVideo.shared.closeAll()
    super.close()
  }
}
