import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var desk: DeskChannels?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // Two panes side by side need room: the list and a conversation.
    self.minSize = NSSize(width: 760, height: 520)
    self.title = "Ghost Messaging"

    RegisterGeneratedPlugins(registry: flutterViewController)
    desk = DeskChannels(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
