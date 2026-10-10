import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WebKit

#if os(iOS)
import Flutter
import UIKit

typealias DiagramHostView = UIView
#else
import Cocoa
import FlutterMacOS

typealias DiagramHostView = NSView
#endif

/// A note's diagrams, drawn (lib/editor/diagrams/bridge.dart, `ghost_md/diagrams`), as
/// android/…/ghost_md/DiagramRenderer.kt draws them on the phone: Mermaid itself, the release the web app pins, on
/// a page of the app's own (assets/diagrams/index.html), in ONE web view made the first time a diagram is asked
/// for. The page draws the diagram where a note would have it and says where that is; the web view's own snapshot
/// of that part of the page goes back as a PNG, and the app shows the picture.
///
/// ONE FILE FOR BOTH (apple/): the Mac's Runner and the iPhone's each compile this very file.
///
/// The web view is in the app's window, since WebKit paints nothing for one that is in none, and BEHIND the app's
/// own view, which covers the window: it is never seen and takes no touch.
///
/// - `draw` `{n, viewport, ask}` -> `{png, blockWidth, blockHeight, x, y, width, height, scale}`, or `{failed}`:
///   Mermaid's words for a diagram written wrong, and "" when the fault is not the person's.
///
/// NOTHING IS FETCHED: the page's own policy lets in its folder and nothing else, the web view may read only the
/// app's bundled `assets` folder, keeps no data, and goes nowhere but its page.
///
/// The page paints the picture's number as a colour in its corner in the same breath as the diagram (page.js
/// `markOf`), and a snapshot is used only when it shows that colour: a frame of the diagram before is never taken
/// for this one.
final class DiagramRenderer: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
  private struct Ask {
    let n: Int
    let viewport: Double
    let json: String
    let result: FlutterResult
  }

  /// Hears the page without holding the renderer: a web view keeps what it is told to tell.
  private final class Ear: NSObject, WKScriptMessageHandler {
    weak var owner: DiagramRenderer?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      owner?.userContentController(userContentController, didReceive: message)
    }
  }

  private static let page = "assets/diagrams/index.html"

  /// The page's corner mark, across (page.css `#mark`), and the levels its red, green and blue are each one of.
  private static let mark = 16.0
  private static let levels = [0, 64, 128, 192, 255]

  /// How tall the web view is laid out, in points; the most a picture is on a side, and in all, in pixels.
  private static let tall = 8000.0
  private static let side = 8192.0
  private static let pixels = 12_000_000.0

  /// How long one diagram may take, the page's first load with it; how often and how many times the page is
  /// photographed for its mark; how long the web view is kept with nothing to draw.
  private static let patience = 20.0
  private static let lookAgain = 0.016
  private static let looks = 120
  private static let restAfter = 180.0

  private let channel: FlutterMethodChannel
  private let host: () -> DiagramHostView?
  private var web: WKWebView?
  private var ready = false
  private var asking: Ask?
  private var line: [Ask] = []
  private var giveUp: DispatchWorkItem?
  private var rest: DispatchWorkItem?

  /// `host` answers the view the web view is put behind: the app's own, which covers the window.
  init(messenger: FlutterBinaryMessenger, host: @escaping () -> DiagramHostView?) {
    channel = FlutterMethodChannel(name: "ghost_md/diagrams", binaryMessenger: messenger)
    self.host = host
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(["failed": ""]) }
      guard call.method == "draw" else { return result(FlutterMethodNotImplemented) }
      let arguments = call.arguments as? [String: Any]
      guard let n = (arguments?["n"] as? NSNumber)?.intValue, let viewport = (arguments?["viewport"] as? NSNumber)?.doubleValue, viewport > 0, let json = arguments?["ask"] as? String else {
        return result(["failed": ""])
      }
      self.line.append(Ask(n: n, viewport: viewport, json: json, result: result))
      self.next()
    }
  }

  private func next() {
    guard asking == nil, !line.isEmpty else { return }
    let ask = line.removeFirst()
    asking = ask
    rest?.cancel()
    giveUp?.cancel()
    let tired = DispatchWorkItem { [weak self] in
      guard let self = self, let waiting = self.asking, waiting.n == ask.n else { return }
      // Patience ran out. A page that never loaded is let go with it, so the next diagram asks a new one.
      if self.ready { self.finish(waiting, ["failed": ""]) } else { self.lost() }
    }
    giveUp = tired
    DispatchQueue.main.asyncAfter(deadline: .now() + DiagramRenderer.patience, execute: tired)
    guard let view = open() else { return finish(ask, ["failed": ""]) }
    if ready { begin(view, ask) }
  }

  /// The page's file in the app, where Flutter puts its assets: `App.framework/flutter_assets` on an iPhone, and
  /// under `Resources` on a Mac.
  private static func pageFile() -> URL? {
    guard let frameworks = Bundle.main.privateFrameworksURL else { return nil }
    for inside in ["App.framework/Resources/flutter_assets", "App.framework/flutter_assets"] {
      let file = frameworks.appendingPathComponent(inside).appendingPathComponent(page)
      if FileManager.default.fileExists(atPath: file.path) { return file }
    }
    return nil
  }

  /// The web view, made and its page asked for the first time it is wanted.
  private func open() -> WKWebView? {
    if let view = web { return view }
    guard let behind = host(), let above = behind.superview, let file = DiagramRenderer.pageFile() else { return nil }
    let configuration = WKWebViewConfiguration()
    // Nothing kept: no cookies, no cache, no storage.
    configuration.websiteDataStore = .nonPersistent()
    let ear = Ear()
    ear.owner = self
    configuration.userContentController.add(ear, name: "ghostHost")
    let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 412, height: DiagramRenderer.tall), configuration: configuration)
    view.navigationDelegate = self
    #if os(iOS)
    view.isOpaque = false
    view.backgroundColor = .clear
    view.scrollView.backgroundColor = .clear
    view.scrollView.contentInsetAdjustmentBehavior = .never
    view.scrollView.isScrollEnabled = false
    view.isUserInteractionEnabled = false
    view.accessibilityElementsHidden = true
    above.insertSubview(view, belowSubview: behind)
    #else
    // A page with no ground of its own is drawn on nothing: the picture is the diagram and no paper.
    view.setValue(false, forKey: "drawsBackground")
    view.setAccessibilityElement(false)
    // Its top at the window's top, and kept there: the page's first screenful is where a diagram is drawn.
    view.setFrameOrigin(NSPoint(x: 0, y: above.bounds.height - DiagramRenderer.tall))
    view.autoresizingMask = [.minYMargin]
    above.addSubview(view, positioned: .below, relativeTo: behind)
    #endif
    web = view
    ready = false
    // Its own folder and the fonts beside it (`assets/diagrams`, `assets/fonts`), and nothing else of the disk.
    view.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent().deletingLastPathComponent())
    return view
  }

  private func close() {
    rest?.cancel()
    guard let view = web else { return }
    web = nil
    ready = false
    view.stopLoading()
    view.configuration.userContentController.removeScriptMessageHandler(forName: "ghostHost")
    view.navigationDelegate = nil
    view.removeFromSuperview()
  }

  /// The web view has nothing to answer with any more: whoever waits is told, and the next ask makes another.
  private func lost() {
    let ask = asking
    close()
    if let ask = ask { finish(ask, ["failed": ""]) }
  }

  private func begin(_ view: WKWebView, _ ask: Ask) {
    // As wide as the app's window, which is what a gantt is sized by; the page waits to hear of it.
    if abs(Double(view.frame.width) - ask.viewport) > 0.01 {
      #if os(iOS)
      view.frame = CGRect(x: 0, y: 0, width: ask.viewport, height: DiagramRenderer.tall)
      #else
      view.setFrameSize(NSSize(width: ask.viewport, height: DiagramRenderer.tall))
      #endif
    }
    // The ask is JSON as Dart wrote it, and JSON is a JavaScript value: nothing of a note is ever run.
    view.evaluateJavaScript("ghostDiagram.draw(\(ask.json))", completionHandler: nil)
  }

  // MARK: the page

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    // The page itself, and nowhere else.
    decisionHandler(navigationAction.request.url?.isFileURL == true && navigationAction.navigationType == .other ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if webView === web { lost() }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if webView === web { lost() }
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    if webView === web { lost() }
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let view = web, let text = message.body as? String, let data = text.data(using: .utf8), let said = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
    if said["ready"] as? Bool == true {
      ready = said["mermaid"] as? Bool == true
      // A page that loaded without Mermaid has nothing to draw with, now or later.
      guard ready else { return lost() }
      if let ask = asking { begin(view, ask) }
      return
    }
    guard let ask = asking, (said["n"] as? NSNumber)?.intValue == ask.n else { return }
    guard said["ok"] as? Bool == true else {
      if let why = said["why"] as? String, !why.isEmpty { NSLog("GhostDiagram: a diagram was not drawn: %@", why) }
      return finish(ask, ["failed": said["failed"] as? String ?? ""])
    }
    photograph(view, ask, said, 0)
  }

  // MARK: the picture

  private static func number(_ from: Any?, _ name: String) -> Double? { ((from as? [String: Any])?[name] as? NSNumber)?.doubleValue }

  /// The page says the diagram is on it: the picture, once the page as painted says so too.
  private func photograph(_ view: WKWebView, _ ask: Ask, _ said: [String: Any], _ tries: Int) {
    guard let waiting = asking, waiting.n == ask.n, web === view else { return }
    guard let blockWidth = DiagramRenderer.number(said["block"], "width"), let blockHeight = DiagramRenderer.number(said["block"], "height"),
      let originX = DiagramRenderer.number(said["origin"], "x"), let originY = DiagramRenderer.number(said["origin"], "y"),
      let x = DiagramRenderer.number(said["picture"], "x"), let y = DiagramRenderer.number(said["picture"], "y"),
      let width = DiagramRenderer.number(said["picture"], "width"), let height = DiagramRenderer.number(said["picture"], "height"), width > 0, height > 0
    else { return finish(ask, ["failed": ""]) }
    let ratio = max(1, (said["ratio"] as? NSNumber)?.doubleValue ?? 1)
    // From the page's corner, where the mark is, to the picture's far corner, out to whole pixels.
    let right = ceil((x + width) * ratio) / ratio, bottom = ceil((y + height) * ratio) / ratio
    // A diagram too big for a picture is made smaller, whole, rather than cut.
    let fit = min(1, min(DiagramRenderer.side / (right * ratio), DiagramRenderer.side / (bottom * ratio)), (DiagramRenderer.pixels / (right * ratio * bottom * ratio)).squareRoot())
    let configuration = WKSnapshotConfiguration()
    configuration.rect = CGRect(x: 0, y: 0, width: right, height: bottom)
    configuration.snapshotWidth = NSNumber(value: right * fit)
    configuration.afterScreenUpdates = true
    view.takeSnapshot(with: configuration) { [weak self] image, _ in
      guard let self = self, let waiting = self.asking, waiting.n == ask.n, self.web === view else { return }
      #if os(iOS)
      let taken = image?.cgImage
      #else
      let taken = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
      #endif
      guard let whole = taken, whole.width > 0 else { return self.again(view, ask, said, tries) }
      // Pixels of the photograph to a point of the page.
      let scale = Double(whole.width) / right
      DispatchQueue.global(qos: .userInitiated).async {
        let answer = DiagramRenderer.cut(whole, scale: scale, n: ask.n, x: x, y: y, width: width, height: height)
        DispatchQueue.main.async {
          guard let waiting = self.asking, waiting.n == ask.n else { return }
          switch answer {
          case .unmarked: self.again(view, ask, said, tries)
          case .failed: self.finish(ask, ["failed": ""])
          case let .cut(png, left, top, wide, high):
            self.finish(ask, ["png": FlutterStandardTypedData(bytes: png), "blockWidth": blockWidth, "blockHeight": blockHeight, "x": left / scale - originX, "y": top / scale - originY, "width": wide / scale, "height": high / scale, "scale": scale])
          }
        }
      }
    }
  }

  /// Not painted yet: the frame before. Photographed again in a moment, for as long as patience lasts.
  private func again(_ view: WKWebView, _ ask: Ask, _ said: [String: Any], _ tries: Int) {
    guard tries < DiagramRenderer.looks else { return finish(ask, ["failed": ""]) }
    DispatchQueue.main.asyncAfter(deadline: .now() + DiagramRenderer.lookAgain) { [weak self] in self?.photograph(view, ask, said, tries + 1) }
  }

  private enum Cut {
    case unmarked
    case failed
    case cut(Data, Double, Double, Double, Double)
  }

  /// The picture's part of a photograph of the page, as a PNG in sRGB, with where it was cut in pixels; `.unmarked`
  /// when the photograph does not show picture `n`'s mark.
  private static func cut(_ whole: CGImage, scale: Double, n: Int, x: Double, y: Double, width: Double, height: Double) -> Cut {
    guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return .failed }
    let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    // The middle of the mark, read in sRGB whatever the screen's own colours are.
    var corner = [UInt8](repeating: 0, count: 4)
    let at = Int((mark / 2 * scale).rounded(.down))
    guard at < whole.width, at < whole.height, let one = whole.cropping(to: CGRect(x: at, y: at, width: 1, height: 1)),
      let reader = CGContext(data: &corner, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: srgb, bitmapInfo: info)
    else { return .failed }
    reader.draw(one, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    let k = ((n % 125) + 125) % 125
    func near(_ seen: UInt8, _ digit: Int) -> Bool { abs(Int(seen) - levels[digit % 5]) <= 24 }
    guard corner[3] == 255, near(corner[0], k), near(corner[1], k / 5), near(corner[2], k / 25) else { return .unmarked }

    let left = (x * scale).rounded(.down), top = (y * scale).rounded(.down)
    let wide = min(Double(whole.width), ((x + width) * scale).rounded(.up)) - left, high = min(Double(whole.height), ((y + height) * scale).rounded(.up)) - top
    guard wide >= 1, high >= 1, let part = whole.cropping(to: CGRect(x: left, y: top, width: wide, height: high)),
      let paper = CGContext(data: nil, width: Int(wide), height: Int(high), bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: info)
    else { return .failed }
    paper.draw(part, in: CGRect(x: 0, y: 0, width: wide, height: high))
    let data = NSMutableData()
    guard let flat = paper.makeImage(), let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return .failed }
    CGImageDestinationAddImage(destination, flat, nil)
    guard CGImageDestinationFinalize(destination) else { return .failed }
    return .cut(data as Data, left, top, wide, high)
  }

  private func finish(_ ask: Ask, _ answer: [String: Any]) {
    guard let waiting = asking, waiting.n == ask.n else { return }
    asking = nil
    giveUp?.cancel()
    ask.result(answer)
    // Kept for the next diagram, and let go when none has come for a while: Mermaid is a few megabytes of page.
    let done = DispatchWorkItem { [weak self] in
      guard let self = self, self.asking == nil, self.line.isEmpty else { return }
      self.close()
    }
    rest = done
    DispatchQueue.main.asyncAfter(deadline: .now() + DiagramRenderer.restAfter, execute: done)
    next()
  }
}
