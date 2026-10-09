import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// `ghost_md/files` on the Mac: the system's own panels, each call answered with the JSON the Android half
/// answers (android/…/ghost_md/FilesBridge.kt), so lib/core/library_folder.dart, backup.dart and export_all.dart
/// read one shape.
///
/// - `chooseLibraryFolder` -> `{path, name}` | `{cancelled: true}` | `{error}`: the Mac's folder panel, which is
///   `library_choose_folder`'s first half in the Tauri app (../glyph/src-tauri/src/library_commands.rs); the core's
///   `library_inspect {path}` is its second.
/// - `chooseExport {name}` -> `{fd, name}` | `{cancelled: true}` | `{error}`: the save panel (`export_save` there),
///   the file made and a descriptor opened on it, which the core's `export_fd` writes through and closes.
///   `exportDone` keeps the file; `discardExport` removes it.
/// - `backupDrives` -> `[{id, name, free, total, tree?}]`: the removable drives mounted now, `id` the drive's path
///   under `/Volumes` and `tree` the same path once the person has allowed it (`backup_drives` there).
/// - `chooseBackupDrive {id}` -> `{tree}` | `{cancelled: true}` | `{error}`: the folder panel opened on the drive,
///   for the one grant a sandboxed app needs before it may write there.
/// - `ejectDrive {id}` -> null, or an error with the Tauri app's sentence (`backup_eject` there).
///
/// WHAT DIFFERS FROM THE TAURI APP, AND WHY. That app is not sandboxed: it reads `/Volumes`, asks `diskutil` which
/// mounts are removable, writes a drive by its path and runs `diskutil eject`. This one is sandboxed, so that
/// nothing it does can reach another app's files: which volumes are removable is asked of the volume itself
/// (`URLResourceKey`), a drive or a folder is written only after the person chose it in a panel, and that choice
/// is kept as a security-scoped bookmark (this app's own defaults) and taken up again at each launch
/// ([restoreGrants], before the core opens the library).
final class FilesChannel: NSObject {
  private var channel: FlutterMethodChannel?
  private weak var window: NSWindow?
  private let defaults = UserDefaults.standard

  /// The folders and drives being reached through a grant now, by path: each is let go when the app ends.
  private var reached: [String: URL] = [:]

  /// The file an export is being written to, until it is done or discarded.
  private var exporting: URL?

  private static let folderGrants = "ghost.folderGrants"
  private static let driveGrants = "ghost.driveGrants"
  /// The library's folder is one at a time; a few of the last chosen are kept so going back to one still opens.
  private static let foldersKept = 4

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
    case "backupDrives": result(FilesChannel.json(drives()))
    case "chooseBackupDrive": chooseBackupDrive(args?["id"] as? String ?? "", result)
    case "ejectDrive": ejectDrive(args?["id"] as? String ?? "", result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private static func json(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value), let text = String(data: data, encoding: .utf8) else { return "{\"error\":\"The answer could not be written.\"}" }
    return text
  }

  private func show(_ panel: NSSavePanel, _ done: @escaping (Bool) -> Void) {
    if let window = window {
      panel.beginSheetModal(for: window) { done($0 == .OK) }
    } else {
      done(panel.runModal() == .OK)
    }
  }

  // MARK: grants

  private func grants(_ key: String) -> [String: Data] {
    (defaults.dictionary(forKey: key) as? [String: Data]) ?? [:]
  }

  /// Keeps the person's choice of `url` past this run, and reaches it now.
  private func grant(_ url: URL, under key: String) {
    var kept = grants(key)
    if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
      kept[url.path] = bookmark
      if key == FilesChannel.folderGrants, kept.count > FilesChannel.foldersKept {
        // The oldest go: a dictionary keeps no order, so the ones not reached this run.
        for path in kept.keys where path != url.path && reached[path] == nil && kept.count > FilesChannel.foldersKept { kept[path] = nil }
      }
      defaults.set(kept, forKey: key)
    }
    reach(url)
  }

  private func reach(_ url: URL) {
    guard reached[url.path] == nil else { return }
    if url.startAccessingSecurityScopedResource() { reached[url.path] = url }
  }

  /// Every folder and drive the person chose before, reached again: called before the core opens the library, so
  /// a library in a folder of theirs is there to be opened. A grant that no longer resolves (the folder was
  /// removed, the drive is not plugged in) is skipped, and one macOS says is stale is renewed.
  func restoreGrants() {
    for key in [FilesChannel.folderGrants, FilesChannel.driveGrants] {
      var kept = grants(key), changed = false
      for (path, bookmark) in kept {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
        reach(url)
        if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
          kept[path] = fresh
          changed = true
        }
      }
      if changed { defaults.set(kept, forKey: key) }
    }
  }

  /// Lets go of everything reached (the app is ending).
  func release() {
    for url in reached.values { url.stopAccessingSecurityScopedResource() }
    reached.removeAll()
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
    show(panel) { [weak self] chosen in
      guard let self = self, chosen, let url = panel.url else { return result(FilesChannel.json(["cancelled": true])) }
      self.grant(url, under: FilesChannel.folderGrants)
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
    show(panel) { [weak self] chosen in
      guard let self = self, chosen, let url = panel.url else { return result(FilesChannel.json(["cancelled": true])) }
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

  // MARK: backup drives

  /// The removable drives mounted now: a volume of its own under `/Volumes` that is local, writable and either
  /// removable, ejectable or not internal; never the Mac's own disk, a network share or a read-only image
  /// (backup_commands.rs `is_removable` and `removable_by`, asked of the volume instead of `diskutil`).
  private func volumes() -> [(url: URL, name: String, free: Int64?, total: Int64?)] {
    let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsReadOnlyKey, .volumeIsRootFileSystemKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeIsBrowsableKey]
    guard let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else { return [] }
    var found: [(URL, String, Int64?, Int64?)] = []
    for url in mounted {
      guard url.path.hasPrefix("/Volumes/"), url.pathComponents.count == 3, let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
      if values.volumeIsRootFileSystem == true || values.volumeIsLocal == false || values.volumeIsReadOnly == true || values.volumeIsBrowsable == false { continue }
      let outside = values.volumeIsInternal == false || values.volumeIsRemovable == true || values.volumeIsEjectable == true
      // A mounted disk image is ejectable and not internal too; it is told apart by what it is mounted from.
      if !outside || FilesChannel.isDiskImage(url) { continue }
      found.append((url, values.volumeName ?? url.lastPathComponent, values.volumeAvailableCapacity.map(Int64.init), values.volumeTotalCapacity.map(Int64.init)))
    }
    return found.sorted { $0.1.lowercased() < $1.1.lowercased() }
  }

  /// Whether the volume at `url` is a mounted disk image (`BusProtocol == "Disk Image"` to `diskutil`): asked of
  /// DiskArbitration, the same answer without a tool to run.
  private static func isDiskImage(_ url: URL) -> Bool {
    guard let session = DASessionCreate(kCFAllocatorDefault), let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL), let said = DADiskCopyDescription(disk) as? [CFString: Any] else { return false }
    if let model = said[kDADiskDescriptionDeviceModelKey] as? String, model.trimmingCharacters(in: .whitespaces) == "Disk Image" { return true }
    if let bus = said[kDADiskDescriptionDeviceProtocolKey] as? String, bus == "Virtual Interface" { return true }
    return false
  }

  private func drives() -> [[String: Any]] {
    let allowed = grants(FilesChannel.driveGrants)
    return volumes().map { volume in
      var drive: [String: Any] = ["id": volume.url.path, "name": volume.name]
      if let free = volume.free { drive["free"] = free }
      if let total = volume.total { drive["total"] = total }
      if allowed[volume.url.path] != nil {
        // Allowed before: reached again now, should it have been plugged in since launch.
        if reached[volume.url.path] == nil, let bookmark = allowed[volume.url.path] {
          var stale = false
          if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) { reach(url) }
        }
        if reached[volume.url.path] != nil { drive["tree"] = volume.url.path }
      }
      return drive
    }
  }

  /// The person asked, once, to let the app write the drive: the folder panel opened on it. The grant must be to
  /// the drive itself, so the backup's `Ghost.md` folder lands on its root (BackupDrives.kt asks the same).
  private func chooseBackupDrive(_ id: String, _ result: @escaping FlutterResult) {
    guard let volume = volumes().first(where: { $0.url.path == id }) else {
      return result(FilesChannel.json(["error": "That drive isn’t plugged in any more."]))
    }
    let panel = NSOpenPanel()
    panel.title = "Back up to \(volume.name)"
    panel.message = "Allow Ghost.md to back up to \(volume.name)"
    panel.prompt = "Allow"
    panel.directoryURL = volume.url
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = false
    panel.allowsMultipleSelection = false
    show(panel) { [weak self] chosen in
      guard let self = self, chosen, let url = panel.url else { return result(FilesChannel.json(["cancelled": true])) }
      guard url.standardizedFileURL.path == volume.url.standardizedFileURL.path else {
        return result(FilesChannel.json(["error": "Choose \(volume.name) itself, not a folder inside it, so the backup is at the top of the drive."]))
      }
      self.grant(url, under: FilesChannel.driveGrants)
      result(FilesChannel.json(["tree": volume.url.path]))
    }
  }

  /// A drive put away, so it can be pulled out. Refused for anything that is not one of the drives listed now.
  private func ejectDrive(_ id: String, _ result: @escaping FlutterResult) {
    guard let volume = volumes().first(where: { $0.url.path == id }) else {
      return result(FlutterError(code: "drive", message: "That drive isn’t plugged in any more.", details: nil))
    }
    if let held = reached.removeValue(forKey: id) { held.stopAccessingSecurityScopedResource() }
    do {
      try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
      result(nil)
    } catch {
      result(FlutterError(code: "drive", message: "The drive could not be ejected. Close anything that has it open, then try again.", details: nil))
    }
  }
}
