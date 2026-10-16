import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// `ghost_md/files` on the Mac: the Mac's own panels, each call answered with the JSON the Android half answers
/// (android/…/ghost_md/FilesBridge.kt), so lib/core/library_folder.dart and export_all.dart read one shape.
///
/// - `chooseLibraryFolder` -> `{path, name}` | `{cancelled: true}`: the Mac's folder panel, which is
///   `library_choose_folder`'s first half in the Tauri app (tauri/src-tauri/src/library_commands.rs); the core's
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

  // MARK: grants (the Mac App Store's build only)

  /// IN THE SANDBOXED BUILD (GhostChannels.sandboxed; Runner/Store.entitlements) a folder outside the container is
  /// reached only because the person chose it in a panel, and only until the app ends. So the choice is kept as a
  /// security-scoped bookmark in this app's own defaults (`files.bookmarks.app-scope`) and taken up again at each
  /// launch before the core opens the library ([restoreGrants]); the core then reads and writes the folder by its
  /// plain path, as it does in the build that is not sandboxed. That build keeps no bookmark and none of this runs.
  private static let folderGrants = "ghost.folderGrants"
  /// The library's folder is one at a time; a few of the last chosen are kept so going back to one still opens.
  private static let foldersKept = 4
  /// The folders being reached through a grant now, by path: each is let go when the app ends.
  private var reached: [String: URL] = [:]
  private var restored = false

  private func grants() -> [String: Data] {
    (UserDefaults.standard.dictionary(forKey: FilesChannel.folderGrants) as? [String: Data]) ?? [:]
  }

  /// Keeps the person's choice of `url` past this run. A folder whose bookmark cannot be made is still reached
  /// until the app ends, and false says it will not be after: the caller tells the person.
  private func grant(_ url: URL) -> Bool {
    var kept = grants()
    guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return false }
    kept[url.path] = bookmark
    // The oldest go: a dictionary keeps no order, so the ones not reached this run.
    for path in kept.keys.sorted() where kept.count > FilesChannel.foldersKept && path != url.path && reached[path] == nil { kept[path] = nil }
    UserDefaults.standard.set(kept, forKey: FilesChannel.folderGrants)
    reach(url)
    return true
  }

  private func reach(_ url: URL) {
    guard reached[url.path] == nil else { return }
    if url.startAccessingSecurityScopedResource() { reached[url.path] = url }
  }

  /// Every folder the person chose before, reached again: called once, before the core opens the library. A grant
  /// that no longer resolves (the folder was removed, the drive is not plugged in) is skipped, and the core then
  /// says of the folder what it says of any folder it cannot open. One macOS says is stale is made again.
  func restoreGrants() {
    guard GhostChannels.sandboxed, !restored else { return }
    restored = true
    var kept = grants(), changed = false
    for (path, bookmark) in kept {
      var stale = false
      guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
      reach(url)
      if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
        kept[path] = fresh
        changed = true
      }
    }
    if changed { UserDefaults.standard.set(kept, forKey: FilesChannel.folderGrants) }
  }

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
    case "chooseImportFolder": chooseImportFolder(result)
    case "chooseImportFiles": chooseImportFiles(result)
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
    Panels.show(panel, on: window) { [weak self] url in
      guard let url = url else { return result(FilesChannel.json(["cancelled": true])) }
      if GhostChannels.sandboxed, self?.grant(url) != true {
        return result(FilesChannel.json(["error": "Ghost.md could not keep its way into that folder, so it would lose it the next time it opened. Choose another folder."]))
      }
      result(FilesChannel.json(["path": url.path, "name": FileManager.default.displayName(atPath: url.path)]))
    }
  }

  // MARK: import

  /// Settings › Import › Obsidian vault (lib/importer/import_sources.dart): a folder, read by its plain path with
  /// `dart:io`. In the sandboxed build the panel's choice is what lets the app read it, for this run, which is all
  /// an import needs: nothing is kept.
  private func chooseImportFolder(_ result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.title = "Choose an Obsidian vault"
    panel.message = "Choose the folder of an Obsidian vault to import"
    panel.prompt = "Import"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = false
    panel.allowsMultipleSelection = false
    Panels.show(panel, on: window) { url in
      guard let url = url else { return result(FilesChannel.json(["cancelled": true])) }
      result(FilesChannel.json(["path": url.path, "name": FileManager.default.displayName(atPath: url.path)]))
    }
  }

  /// Settings › Import › Evernote export: one or more `.enex` files, by their paths.
  private func chooseImportFiles(_ result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.title = "Choose Evernote exports"
    panel.message = "Choose one or more .enex files to import"
    panel.prompt = "Import"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    if let enex = UTType(filenameExtension: "enex") { panel.allowedContentTypes = [enex] }
    panel.beginSheetOrRun(on: window) { urls in
      guard let urls = urls, !urls.isEmpty else { return result(FilesChannel.json(["cancelled": true])) }
      let files: [[String: Any]] = urls.map { url in
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        return ["path": url.path, "name": url.lastPathComponent, "size": size]
      }
      result(FilesChannel.json(["files": files]))
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

extension NSOpenPanel {
  /// A panel that may choose several, shown as a sheet on the app's window (or on its own with none), answered with
  /// every URL chosen, or nil when it was closed. [Panels.show] answers one.
  func beginSheetOrRun(on window: NSWindow?, _ done: @escaping ([URL]?) -> Void) {
    #if DEBUG
    if let answer = Panels.answer, let file = answer.file, let window = window {
      Panels.answer = nil
      beginSheetModal(for: window) { _ in done(answer.cancel ? nil : [URL(fileURLWithPath: file)]) }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { window.endSheet(self, returnCode: answer.cancel ? .cancel : .OK) }
      return
    }
    #endif
    if let window = window {
      beginSheetModal(for: window) { done($0 == .OK ? self.urls : nil) }
    } else {
      done(runModal() == .OK ? urls : nil)
    }
  }
}
