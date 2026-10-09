import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// `ghost_md/files` on the Mac: the Mac's own panels, each call answered with the JSON the Android half answers
/// (android/…/ghost_md/FilesBridge.kt), so lib/core/library_folder.dart and export_all.dart read one shape.
///
/// - `chooseLibraryFolder` -> `{path, name}` | `{cancelled: true}`: the Mac's folder panel, which is
///   `library_choose_folder`'s first half in the Tauri app (../glyph/src-tauri/src/library_commands.rs); the core's
///   `library_inspect {path}` is its second, and the folder is kept by its plain path (`library-root.json`).
/// - `chooseExport {name}` -> `{fd, name}` | `{cancelled: true}` | `{error}`: the save panel (`export_save` there),
///   the file made and a descriptor opened on it, which the core's `export_fd` writes through and closes.
///   `exportDone` keeps the file; `discardExport` removes it.
///
/// The app is not sandboxed, as the Tauri Mac app is not, so a folder chosen once is reached again by its path
/// and a drive is the core's to list, write and eject (`backup_drives`, `backup_eject`: diskutil, as there). The
/// first pass's bookmarks, its own list of drives and the panel that allowed one went with the sandbox.
final class FilesChannel: NSObject {
  private var channel: FlutterMethodChannel?
  private weak var window: NSWindow?

  /// The file an export is being written to, until it is done or discarded.
  private var exporting: URL?

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    self.window = window
    super.init()
    let channel = FlutterMethodChannel(name: "ghost_md/files", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in self?.asked(call, result) }
    self.channel = channel
  }

  private func asked(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "chooseLibraryFolder": chooseLibraryFolder(result)
    case "chooseExport": chooseExport(args?["name"] as? String ?? "", result)
    case "exportDone":
      exporting = nil
      result(nil)
    case "discardExport":
      if let url = exporting { try? FileManager.default.removeItem(at: url) }
      exporting = nil
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private static func json(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value), let text = String(data: data, encoding: .utf8) else { return "{\"error\":\"The answer could not be written.\"}" }
    return text
  }

  // MARK: the library's folder

  private func chooseLibraryFolder(_ result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.title = "Choose a folder for your notes"
    panel.message = "Choose a folder for your notes"
    panel.prompt = "Choose"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    Panels.show(panel, on: window) { url in
      guard let url = url else { return result(FilesChannel.json(["cancelled": true])) }
      result(FilesChannel.json(["path": url.path, "name": FileManager.default.displayName(atPath: url.path)]))
    }
  }

  // MARK: export

  private func chooseExport(_ name: String, _ result: @escaping FlutterResult) {
    let panel = NSSavePanel()
    panel.title = "Export everything"
    panel.nameFieldStringValue = name
    panel.allowedContentTypes = [.zip]
    panel.canCreateDirectories = true
    Panels.show(panel, on: window) { [weak self] url in
      guard let self = self, let url = url else { return result(FilesChannel.json(["cancelled": true])) }
      // A new, empty file, which is the only kind the core writes an archive through (export.rs
      // `adopt_descriptor`); the panel has already asked before replacing one of that name.
      guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
        return result(FilesChannel.json(["error": "Ghost.md can’t write to that place. It may be locked or read-only."]))
      }
      let fd = open(url.path, O_WRONLY)
      guard fd > 2 else {
        try? FileManager.default.removeItem(at: url)
        return result(FilesChannel.json(["error": "That place can’t be written to."]))
      }
      self.exporting = url
      result(FilesChannel.json(["fd": Int(fd), "name": url.lastPathComponent]))
    }
  }
}

/// How one of the Mac's panels is shown: as a sheet on the app's window, answered when the person does with what
/// they chose, or nil when they closed it.
///
/// A DEBUG BUILD'S ONLY, for the tour (lib/shell/desktop/mac_tour.dart): [answer] says how the next panel is to
/// be answered with no hand on it, so the panels can be walked with nothing sent to the screen. The panel is still
/// made, shown as the sheet it is and closed by AppKit; what it is said to have chosen is the tour's (a temporary
/// folder or file of its own), since a panel's own buttons are a hand's to press: macOS draws the panel in a
/// process of its own and `ok:` is not this app's to call. A release build has no such door.
enum Panels {
  #if DEBUG
  struct Answer {
    /// The folder a folder panel is taken to have chosen, and a save panel to be in.
    var folder: String?
    /// A save panel's file name.
    var name: String?
    /// A file taken as chosen, for a panel that chooses files.
    var file: String?
    var cancel = false
  }

  static var answer: Answer?
  #endif

  static func show(_ panel: NSSavePanel, on window: NSWindow?, _ done: @escaping (URL?) -> Void) {
    #if DEBUG
    if let answer = Panels.answer, let window = window {
      Panels.answer = nil
      if let folder = answer.folder { panel.directoryURL = URL(fileURLWithPath: folder, isDirectory: true) }
      if let name = answer.name { panel.nameFieldStringValue = name }
      var said: URL?
      if !answer.cancel {
        if let file = answer.file {
          said = URL(fileURLWithPath: file)
        } else if let folder = answer.folder {
          let base = URL(fileURLWithPath: folder, isDirectory: true)
          said = panel is NSOpenPanel ? base : base.appendingPathComponent(answer.name ?? panel.nameFieldStringValue)
        }
      }
      panel.beginSheetModal(for: window) { _ in done(said) }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        window.endSheet(panel, returnCode: said == nil ? .cancel : .OK)
      }
      return
    }
    #endif
    if let window = window {
      panel.beginSheetModal(for: window) { done($0 == .OK ? panel.url : nil) }
    } else {
      done(panel.runModal() == .OK ? panel.url : nil)
    }
  }
}
