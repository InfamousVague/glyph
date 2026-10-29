import Cocoa
import FlutterMacOS

/// The app's running work on the Mac's own surfaces (docs/ACTIVITY.md, OS surfaces; Matt, 2026-10-29: "the Mac's Dock
/// icon progress ring and badge; a Mac menu bar item with the ring and a mini tray"), told by the record over
/// `ghost_md/jobs` (lib/activity/activity_surfaces.dart; MainFlutterWindow.swift hands the calls here):
///
/// - **The Dock icon**: while work runs, the header's ring drawn on the icon, one arc per job in its kind's colour
///   (another device's dimmed), each filled as far as the job is; the count of this Mac's jobs as the badge. Gone, and
///   the icon as it was, once nothing runs.
/// - **The menu bar**: the same ring, while work runs, or always where Settings › Appearance › Activity says
///   ("Always show in the menu bar"; drawn in the menu bar's own ink when nothing runs). Clicked, a mini tray: each
///   job with its glyph, what it does now and a bar, Stop where it can be stopped (said back as `activityStop`), a
///   click on the row to open what it makes (`activityOpen`), and Open Ghost.md.
///
/// Calm (Settings › Appearance) draws both in ink. Nothing is kept: the app tells every job the surfaces show each
/// time, and the app quits with its window.
final class ActivitySurfaces: NSObject, NSMenuDelegate {
  /// A job as the app tells it (`surfaceJob`).
  struct Job: Equatable {
    let id: String
    let kind: String
    let look: String
    let state: String
    let title: String
    let line: String
    let fraction: Double?
    let colour: NSColor?
    let colourDark: NSColor?
    let stoppable: Bool
    let openable: Bool
    let here: Bool
    let device: String?

    var live: Bool { state == "running" || state == "waiting" || state == "queued" }
    var dimmed: Bool { !here || look == "waiting" }

    init?(_ map: [String: Any]?) {
      guard let map = map, let id = map["id"] as? String else { return nil }
      self.id = id
      kind = map["kind"] as? String ?? "sync"
      look = map["look"] as? String ?? kind
      state = map["state"] as? String ?? "running"
      title = map["title"] as? String ?? "Ghost.md"
      line = map["line"] as? String ?? ""
      fraction = (map["fraction"] as? NSNumber)?.doubleValue
      colour = (map["colour"] as? NSNumber).map { ActivitySurfaces.colour($0.int64Value) }
      colourDark = (map["colourDark"] as? NSNumber).map { ActivitySurfaces.colour($0.int64Value) }
      stoppable = map["stoppable"] as? Bool ?? false
      openable = map["openable"] as? Bool ?? false
      here = map["here"] as? Bool ?? true
      device = map["device"] as? String
    }

    /// Its colour on [appearance], or the ink where Calm left the colours out.
    func drawn(dark: Bool) -> NSColor {
      (dark ? colourDark ?? colour : colour) ?? NSColor.labelColor
    }
  }

  private var jobs: [Job] = []
  private var calm = false
  private var always = false
  private var item: NSStatusItem?
  private var rows: [String: JobRow] = [:]
  private var menuOpen = false

  /// Says `activityStop` / `activityOpen` {id} to the app.
  private let say: (String, String) -> Void

  /// Brings the window to the front.
  private let front: () -> Void

  init(say: @escaping (String, String) -> Void, front: @escaping () -> Void) {
    self.say = say
    self.front = front
    super.init()
  }

  /// `activity` and `activityLook`; false for any other call.
  func told(_ method: String, _ args: [String: Any]?) -> Bool {
    switch method {
    case "activity":
      let all = (args?["jobs"] as? [Any] ?? []).compactMap { Job($0 as? [String: Any]) }
      jobs = all
    case "activityLook":
      calm = args?["calm"] as? Bool ?? false
      always = args?["menuBarAlways"] as? Bool ?? false
    default:
      return false
    }
    refresh()
    return true
  }

  private var live: [Job] { jobs.filter { $0.live } }

  private func refresh() {
    dock()
    menuBar()
  }

  // MARK: the Dock

  private func dock() {
    let tile = NSApp.dockTile
    let running = live
    guard !running.isEmpty else {
      if tile.contentView != nil || tile.badgeLabel != nil {
        tile.contentView = nil
        tile.badgeLabel = nil
        tile.display()
      }
      return
    }
    let view = (tile.contentView as? DockRing) ?? DockRing(frame: NSRect(origin: .zero, size: tile.size))
    view.arcs = arcs(running, dark: true)
    tile.contentView = view
    let here = running.filter { $0.here }.count
    tile.badgeLabel = here > 0 ? "\(here)" : nil
    tile.display()
  }

  private func arcs(_ jobs: [Job], dark: Bool) -> [RingArc] {
    jobs.map { job in
      let colour = calm ? (dark ? NSColor.white : NSColor.black) : job.drawn(dark: dark)
      return RingArc(colour: job.dimmed ? colour.withAlphaComponent(0.45) : colour, fraction: job.look == "waiting" ? (job.fraction ?? 0) : job.fraction)
    }
  }

  // MARK: the menu bar

  private func menuBar() {
    let running = live
    let shows = always || !running.isEmpty || jobs.contains { $0.state == "failed" }
    guard shows else {
      if let item = item { NSStatusBar.system.removeStatusItem(item) }
      item = nil
      rows = [:]
      return
    }
    let item = self.item ?? {
      let made = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      let menu = NSMenu()
      menu.delegate = self
      made.menu = menu
      self.item = made
      return made
    }()
    if let button = item.button {
      let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      button.image = ringImage(running, dark: dark)
      button.toolTip = running.isEmpty ? "Ghost.md" : running.count == 1 ? "Ghost.md: \(running[0].title)" : "Ghost.md: \(running.count) jobs running"
      button.setAccessibilityLabel(button.toolTip)
    }
    if menuOpen, let menu = item.menu { fill(menu) }
  }

  /// The ring at the menu bar's size: the jobs' arcs, or, with nothing running, a faint ring in the bar's own ink.
  private func ringImage(_ running: [Job], dark: Bool) -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let needsYou = jobs.contains { $0.state == "failed" }
    let template = running.isEmpty || calm
    let image = NSImage(size: size, flipped: false) { rect in
      let ring = rect.insetBy(dx: 2, dy: 2)
      if running.isEmpty {
        RingArc.draw([RingArc(colour: NSColor.black.withAlphaComponent(0.5), fraction: 1)], in: ring, width: 2)
      } else {
        RingArc.draw(self.calm ? running.map { RingArc(colour: NSColor.black.withAlphaComponent($0.dimmed ? 0.45 : 1), fraction: $0.look == "waiting" ? ($0.fraction ?? 0) : $0.fraction) } : self.arcs(running, dark: dark), in: ring, width: 2.2)
      }
      if needsYou {
        // A still red dot when something needs the person, as the header's ring has.
        let dot = NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 5, height: 5)
        (template ? NSColor.black : NSColor.systemRed).setFill()
        NSBezierPath(ovalIn: dot).fill()
      }
      return true
    }
    image.isTemplate = template
    return image
  }

  func menuWillOpen(_ menu: NSMenu) {
    menuOpen = true
  }

  func menuDidClose(_ menu: NSMenu) {
    menuOpen = false
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    fill(menu)
  }

  /// The mini tray: each job, then Open Ghost.md. Rows already there are told again in place, so a bar moves while
  /// the menu is open.
  private func fill(_ menu: NSMenu) {
    let shown = jobs.filter { $0.live || $0.state == "failed" }
    let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let ids = shown.map { $0.id }
    let same = ids == menu.items.compactMap { ($0.view as? JobRow)?.job.id }
    if same {
      for job in shown { rows[job.id]?.show(job, colour: calm ? NSColor.labelColor : job.drawn(dark: dark)) }
      return
    }
    menu.removeAllItems()
    rows = [:]
    if shown.isEmpty {
      let none = NSMenuItem(title: "Nothing running", action: nil, keyEquivalent: "")
      none.isEnabled = false
      menu.addItem(none)
    }
    for job in shown {
      let row = JobRow(job: job, colour: calm ? NSColor.labelColor : job.drawn(dark: dark))
      row.stop = { [weak self, weak menu] id in
        self?.say("activityStop", id)
        menu?.cancelTracking()
      }
      row.open = { [weak self, weak menu] id in
        menu?.cancelTracking()
        self?.front()
        self?.say("activityOpen", id)
      }
      let item = NSMenuItem()
      item.view = row
      menu.addItem(item)
      rows[job.id] = row
    }
    menu.addItem(.separator())
    let open = NSMenuItem(title: "Open Ghost.md", action: #selector(openApp), keyEquivalent: "")
    open.target = self
    menu.addItem(open)
  }

  @objc private func openApp() {
    front()
  }

  /// 0xAARRGGBB.
  static func colour(_ argb: Int64) -> NSColor {
    let value = UInt32(truncatingIfNeeded: argb)
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: CGFloat((value >> 24) & 0xFF) / 255)
  }
}

/// One arc of the ring: its colour, and how far (nil: it cannot say, two thirds drawn and still).
struct RingArc {
  let colour: NSColor
  let fraction: Double?

  /// The gap between two arcs, as the header's (lib/activity/activity_ring.dart `ActivityRingPainter.gap`).
  static let gap: CGFloat = 0.32

  /// Draws [arcs] round [rect] as the header's ring does: one arc each, from the top, clockwise, a faint track of its
  /// own colour under it.
  static func draw(_ arcs: [RingArc], in rect: NSRect, width: CGFloat) {
    guard !arcs.isEmpty else { return }
    let centre = NSPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2 - width / 2
    let each = 2 * CGFloat.pi / CGFloat(arcs.count)
    for (index, arc) in arcs.enumerated() {
      // Radians from the top, clockwise; AppKit's angles are degrees, anticlockwise from the right.
      let start = arcs.count == 1 ? 0 : CGFloat(index) * each + gap / 2
      let sweep = arcs.count == 1 ? 2 * CGFloat.pi : each - gap
      func stroke(_ from: CGFloat, _ length: CGFloat, _ colour: NSColor) {
        guard length > 0 else { return }
        let path = NSBezierPath()
        let a = 90 - from * 180 / .pi
        path.appendArc(withCenter: centre, radius: radius, startAngle: a, endAngle: a - length * 180 / .pi, clockwise: true)
        path.lineWidth = width
        path.lineCapStyle = arcs.count == 1 ? .butt : .round
        colour.setStroke()
        path.stroke()
      }
      stroke(start, sweep, arc.colour.withAlphaComponent(arc.colour.alphaComponent * 0.28))
      stroke(start, sweep * CGFloat(min(max(arc.fraction ?? 0.66, 0), 1)), arc.colour)
    }
  }
}

/// The Dock icon with the ring on it: the app's icon, and a dark disc at its foot with the jobs' arcs round it.
private final class DockRing: NSView {
  var arcs: [RingArc] = [] {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    NSApp.applicationIconImage?.draw(in: bounds)
    let side = bounds.width * 0.44
    let disc = NSRect(x: bounds.midX - side / 2, y: bounds.minY + bounds.height * 0.04, width: side, height: side)
    NSColor(white: 0.08, alpha: 0.82).setFill()
    NSBezierPath(ovalIn: disc).fill()
    RingArc.draw(arcs, in: disc.insetBy(dx: side * 0.12, dy: side * 0.12), width: max(3, side * 0.12))
  }
}

/// A job in the menu bar's mini tray: its glyph in its colour, its title, what it does now, a bar, and Stop.
private final class JobRow: NSView {
  private(set) var job: ActivitySurfaces.Job
  var stop: ((String) -> Void)?
  var open: ((String) -> Void)?

  private let glyph = NSImageView()
  private let title = NSTextField(labelWithString: "")
  private let line = NSTextField(labelWithString: "")
  private let bar = NSProgressIndicator()
  private let stopButton = NSButton(title: "Stop", target: nil, action: nil)

  init(job: ActivitySurfaces.Job, colour: NSColor) {
    self.job = job
    super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 56))
    title.font = .menuFont(ofSize: 13)
    title.lineBreakMode = .byTruncatingTail
    line.font = .menuFont(ofSize: 11)
    line.textColor = .secondaryLabelColor
    line.lineBreakMode = .byTruncatingTail
    bar.style = .bar
    bar.controlSize = .small
    bar.minValue = 0
    bar.maxValue = 1
    stopButton.bezelStyle = .inline
    stopButton.controlSize = .small
    stopButton.target = self
    stopButton.action = #selector(stopPressed)
    for view in [glyph, title, line, bar, stopButton] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
      glyph.widthAnchor.constraint(equalToConstant: 18),
      glyph.heightAnchor.constraint(equalToConstant: 18),
      title.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 10),
      title.topAnchor.constraint(equalTo: topAnchor, constant: 7),
      title.trailingAnchor.constraint(lessThanOrEqualTo: stopButton.leadingAnchor, constant: -8),
      line.leadingAnchor.constraint(equalTo: title.leadingAnchor),
      line.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
      line.trailingAnchor.constraint(lessThanOrEqualTo: stopButton.leadingAnchor, constant: -8),
      bar.leadingAnchor.constraint(equalTo: title.leadingAnchor),
      bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
      stopButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      stopButton.topAnchor.constraint(equalTo: topAnchor, constant: 7),
    ])
    show(job, colour: colour)
  }

  required init?(coder: NSCoder) {
    fatalError("not made from a nib")
  }

  /// Says [job] again, in place.
  func show(_ job: ActivitySurfaces.Job, colour: NSColor) {
    self.job = job
    let failed = job.state == "failed"
    let symbol = JobRow.symbol(failed ? "needsYou" : job.kind)
    glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: job.kind)?.withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
    glyph.contentTintColor = failed ? .systemRed : colour
    glyph.alphaValue = job.dimmed ? 0.5 : 1
    title.stringValue = job.title
    line.stringValue = [job.line == job.title ? nil : job.line, job.device].compactMap { $0 }.joined(separator: " · ")
    stopButton.isHidden = !job.stoppable
    bar.isHidden = failed
    if let f = job.fraction {
      bar.stopAnimation(nil)
      bar.isIndeterminate = false
      bar.doubleValue = f
    } else if job.look == "waiting" {
      bar.stopAnimation(nil)
      bar.isIndeterminate = false
      bar.doubleValue = 0
    } else {
      bar.isIndeterminate = true
      bar.startAnimation(nil)
    }
    setAccessibilityLabel("\(job.title), \(job.line)")
  }

  /// The SF Symbol nearest each kind's glyph in the tray (lib/activity/activity_look.dart).
  static func symbol(_ kind: String) -> String {
    switch kind {
    case "sync": return "arrow.triangle.2.circlepath"
    case "ai": return "sparkles"
    case "images": return "paintbrush.pointed"
    case "audio": return "recordingtape"
    case "meetings": return "person.2"
    case "downloads": return "arrow.down.circle"
    case "needsYou": return "exclamationmark.circle.fill"
    default: return "circle.dashed"
    }
  }

  @objc private func stopPressed() {
    stop?(job.id)
  }

  override func mouseUp(with event: NSEvent) {
    open?(job.id)
  }
}
