import Flutter
import ImageIO
import PhotosUI
import Security
import UIKit
import UniformTypeIdentifiers

/// The iPhone's half of the app's method channels (lib/**: every `MethodChannel(`), each named as the Android half
/// names it (android/…/ghost_md/*.kt) and answering in the same shapes, so the Dart is one for all three.
///
/// Here: where the app keeps its files, links opened, the secure store, a reset's forgetting, links that open the
/// app, pictures, and a day from the phone's calendar. A recording's player is the Mac's own file
/// (macos/Runner/TapeChannel.swift, compiled here too); the Keychain and a picture's shrinking are apple/'s.
///
/// WHAT AN IPHONE HAS NO HALF OF, AND WHY (README, "What the iPhone app left open"): the real iPhone app records
/// nothing and runs no model (tauri/ `core/platform.ts` `recordsVoice`, src-tauri/src/unsupported.rs), chooses no
/// folder, exports and backs up nowhere, finds no position and picks no film, and is updated by the App Store. So
/// there is no `ghost_md/mic`, `ghost_md/meeting`, `ghost_md/files`, `ghost_md/location`, `ghost_md/films`,
/// `ghost_md/updates`, and none of Android's own (`ghost_md/front`, `ghost_md/hinge`); the Dart offers none of
/// what they are for on an iPhone.
///
/// THE APP'S FILES ARE ITS OWN. The bundle id is `com.mattssoftware.glyph.flutter`, and an iPhone app sees nothing
/// outside its container, so the real Ghost.md's library (`com.mattssoftware.glyph`) cannot be opened, moved or
/// written from here.
///
/// THE BUILD THAT REPLACES THE TAURI iPHONE APP (tool/cutover-build-ios.sh; docs/CUTOVER.md §8) has that app's
/// bundle id, since it is that app's next version in the App Store, and so WAKES IN THAT APP'S CONTAINER, beside
/// what 1.10.0 kept there: `Library/Application Support/com.mattssoftware.glyph` (the notes, the pictures) and
/// `Library/WebKit/com.mattssoftware.glyph` (the page's settings, session and keys). It keeps a folder of its
/// own all the same, as the Mac's build does and for the Mac's reasons: `com.mattssoftware.glyph.v2` under
/// Application Support and under Caches ([cutoverFolder]). Not the Tauri app's folder and not a folder inside it,
/// so the rule every build is held to stays whole (no path with a folder named `com.mattssoftware.glyph` in it is
/// ever written, [ownDirectory]) and what 1.10.0 kept is exactly as it left it for as long as the app is
/// installed. Beside it and under the same two parents, so it is kept the way the old folder was: Application
/// Support is in an iCloud or computer backup and is not shown in Files (the app shares no Documents), Caches is
/// in neither. What the Tauri app kept is copied in once (lib/carry/iphone_carry.dart). `dirs` answers nothing
/// for a build whose folder would come out as the Tauri app's.
final class GhostChannels: NSObject, FlutterSceneLifeCycleDelegate {
  /// The Tauri app's bundle id: this app's only in the build that replaces it, and never the name of its folder.
  static let realApp = "com.mattssoftware.glyph"

  /// The folder of the build that replaces the Tauri app, under Application Support and under Caches.
  static let cutoverFolder = "com.mattssoftware.glyph.v2"

  private let tape: TapeChannel
  private let clips: TapeChannel
  private let day: DayChannel
  private var held: [FlutterMethodChannel] = []
  private var links: FlutterMethodChannel?
  private var keptLinks: [String] = []
  private var picker: PictureAsk?

  init(messenger: FlutterBinaryMessenger) {
    tape = TapeChannel(messenger: messenger)
    clips = TapeChannel(messenger: messenger, name: "ghost_md/clip")
    day = DayChannel(messenger: messenger)
    super.init()

    listen("ghost_md/device_paths", messenger) { call, result in
      guard call.method == "dirs" else { return result(FlutterMethodNotImplemented) }
      guard let dirs = GhostChannels.dirs() else {
        return result(FlutterError(code: "paths", message: "Ghost Flutter will not open another app's files.", details: nil))
      }
      result(["dataDir": dirs.data.path, "cacheDir": dirs.cache.path])
    }

    // The carry from the Tauri app (lib/carry/iphone_carry.dart, over the Mac's `MacCarryDevice`): the two things
    // only the phone can do for it. Nothing here writes outside this app's own folder, and nothing is asked of
    // the person.
    listen("ghost_md/tauri_carry", messenger) { call, result in
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "masterKey":
        result(GhostChannels.webCryptoMasterKey())
      case "clone":
        guard let from = args?["from"] as? String, let to = args?["to"] as? String else { return result(false) }
        result(GhostChannels.clone(from: from, to: to))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    listen("ghost_md/open", messenger) { call, result in
      guard call.method == "open" else { return result(FlutterMethodNotImplemented) }
      let said = (call.arguments as? [String: Any])?["url"] as? String ?? ""
      // What lib/core/open_link.dart lets through, asked again here: a channel is not trusted to have asked.
      guard let url = URL(string: said), let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel", "geo"].contains(scheme) else { return result(false) }
      var to = url
      if scheme == "geo" {
        // An iPhone has no `geo:`; Maps takes the same place by its own address, as on the Mac.
        let place = said.dropFirst(4).split(separator: "?").first.map(String.init) ?? ""
        guard let maps = URL(string: "https://maps.apple.com/?ll=\(place)") else { return result(false) }
        to = maps
      }
      UIApplication.shared.open(to, options: [:]) { opened in result(opened) }
    }

    listen("ghost_md/secure_store", messenger) { call, result in
      let args = call.arguments as? [String: Any]
      let name = args?["name"] as? String ?? ""
      guard !name.isEmpty else { return result(FlutterError(code: "secure_store", message: "A secret needs a name.", details: nil)) }
      switch call.method {
      case "read":
        switch Keychain.read(name) {
        case .success(let value): result(value)
        case .failure(let failure): result(FlutterError(code: "secure_store", message: failure.said, details: nil))
        }
      case "write":
        guard let value = args?["value"] as? String else { return result(FlutterError(code: "secure_store", message: "A secret needs a value.", details: nil)) }
        if let failure = Keychain.write(name, value) { result(FlutterError(code: "secure_store", message: failure.said, details: nil)) } else { result(nil) }
      case "delete":
        if let failure = Keychain.delete(name) { result(FlutterError(code: "secure_store", message: failure.said, details: nil)) } else { result(nil) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // A dot where the others have an underscore (`resetChannelName`, lib/core/reset.dart).
    listen("ghost.md/reset", messenger) { call, result in
      switch call.method {
      case "recording":
        // An iPhone records no meeting.
        result(false)
      case "cancelWriteUps":
        // And writes none up: there is no work queue to stop.
        result(nil)
      case "forgetSecrets":
        if Keychain.clear() { result(nil) } else { result(FlutterError(code: "secure_store", message: "A kept sign-in could not be forgotten.", details: nil)) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Links that open the app (`ghostmd://…`, lib/core/phone_links.dart): kept until the page asks.
    let links = FlutterMethodChannel(name: "ghost_md/links", binaryMessenger: messenger)
    links.setMethodCallHandler { [weak self] call, result in
      guard call.method == "take" else { return result(FlutterMethodNotImplemented) }
      let kept = self?.keptLinks ?? []
      self?.keptLinks = []
      result(kept)
    }
    self.links = links

    listen("ghost_md/pictures", messenger) { [weak self] call, result in
      switch call.method {
      case "pick": self?.pickPicture(result)
      case "clipboard": result(GhostChannels.clipboard())
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func listen(_ name: String, _ messenger: FlutterBinaryMessenger, _ handler: @escaping FlutterMethodCallHandler) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler(handler)
    held.append(channel)
  }

  // MARK: links

  /// A link the system handed the app. Only the app's own scheme is kept.
  func arrived(_ url: URL) {
    guard url.scheme?.lowercased() == "ghostmd" else { return }
    keptLinks.append(url.absoluteString)
    links?.invokeMethod("arrived", arguments: nil)
  }

  /// The app was opened by a link: it is among what `take` answers once the page asks.
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions?) -> Bool {
    for context in connectionOptions?.urlContexts ?? [] { arrived(context.url) }
    return false
  }

  /// A link opened while the app runs.
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    var ours = false
    for context in URLContexts where context.url.scheme?.lowercased() == "ghostmd" {
      arrived(context.url)
      ours = true
    }
    return ours
  }

  // MARK: files

  /// `<Application Support>/<bundle id>` and `<Caches>/<bundle id>`, as Tauri names its two (`app_data_dir`,
  /// `app_cache_dir`), inside this app's own container; for the build that has the Tauri app's id,
  /// [cutoverFolder] in place of the id. Nil should either ever come out as the Tauri app's folder or a place
  /// inside it.
  static func dirs() -> (data: URL, cache: URL)? {
    let manager = FileManager.default
    guard let id = Bundle.main.bundleIdentifier, let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first, let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first,
      let data = ownDirectory(in: support, id: folderName(id: id)), let cache = ownDirectory(in: caches, id: folderName(id: id))
    else { return nil }
    try? manager.createDirectory(at: data, withIntermediateDirectories: true)
    try? manager.createDirectory(at: cache, withIntermediateDirectories: true)
    return (data, cache)
  }

  /// What this app's folder is called for a build with the bundle id `id`.
  static func folderName(id: String) -> String { id == realApp ? cutoverFolder : id }

  /// This app's folder under `base`: `<base>/<id>`, for an id that is not the Tauri app's, and never the Tauri
  /// app's folder there or anything inside it (an id with a `/` or a `..` in it could otherwise name one). The
  /// Mac's rule, word for word (macos/Runner/GhostChannels.swift).
  static func ownDirectory(in base: URL, id: String) -> URL? {
    guard !id.isEmpty, id != realApp, !id.contains("/"), !id.contains("..") else { return nil }
    let own = base.appendingPathComponent(id, isDirectory: true).standardizedFileURL
    let theirs = base.appendingPathComponent(realApp, isDirectory: true).standardizedFileURL
    let ownParts = own.pathComponents, theirParts = theirs.pathComponents
    if ownParts.count >= theirParts.count && Array(ownParts.prefix(theirParts.count)) == theirParts { return nil }
    return own
  }

  // MARK: the carry from the Tauri app

  /// What the phone's Keychain holds as the Tauri app's "WebCrypto Master Key", as base64, for the carry to open
  /// the keys that app's web view kept (lib/carry/webkit_stores.dart). READ, never changed or removed.
  ///
  /// It is WebKit's own item, made in the app's process the first time its page stored a `CryptoKey`: a generic
  /// password with the account `com.apple.WebKit.WebCrypto.master+<bundle id>` and no service, readable while the
  /// phone is unlocked, in the app's own access group, `<team>.<bundle id>` (seen in a simulator's keychain as
  /// `F6ZAL7ANAD.com.mattssoftware.glyph`). An iPhone hands an item to whatever is signed into its access group
  /// and to nothing else, with no panel either way: the build that replaces the Tauri app is the same id signed
  /// by the same team, so it is handed it, and any other build asks for another account's item and finds none.
  /// Only that build asks.
  static func webCryptoMasterKey() -> String? {
    guard Bundle.main.bundleIdentifier == realApp else { return nil }
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: "com.apple.WebKit.WebCrypto.master+\(realApp)",
      kSecAttrSynchronizable: false,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var found: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
    return data.base64EncodedString()
  }

  /// A clone of one file: a second name for the same blocks (an iPhone's disk is APFS), each then changing alone.
  /// Only ever INTO this app's own folder, and never over a file.
  static func clone(from: String, to: String) -> Bool {
    guard let dirs = dirs() else { return false }
    let target = URL(fileURLWithPath: to).standardizedFileURL.path
    guard target.hasPrefix(dirs.data.standardizedFileURL.path + "/") else { return false }
    return clonefile(from, target, UInt32(CLONE_NOFOLLOW)) == 0
  }

  // MARK: pictures

  /// The view controller a chooser is put up over: the window's own, or whatever it is already showing.
  static func presenter() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let over = top?.presentedViewController { top = over }
    return top
  }

  /// A picture for a note, answered as the phone's chooser answers: `{path}` of a JPEG in the app's cache, shrunk
  /// and the right way up, `{cancelled: true}`, or an error with a sentence.
  ///
  /// The real iPhone app asks through the page's file input (tauri/ `core/images.ts` `pickWeb`), which an iPhone
  /// answers with a menu of its photo library, its camera and its files; so does this.
  private func pickPicture(_ result: @escaping FlutterResult) {
    // One chooser at a time: a second ask while the first is up is answered as none chosen.
    picker?.cancel()
    guard let over = GhostChannels.presenter(), let dirs = GhostChannels.dirs() else {
      return result(FlutterError(code: "pictures", message: "The picker did not open.", details: nil))
    }
    let ask = PictureAsk(cache: dirs.cache) { [weak self] answer in
      self?.picker = nil
      switch answer {
      case .picked(let path): result(["path": path])
      case .cancelled: result(["cancelled": true])
      case .failed(let sentence): result(FlutterError(code: "pictures", message: sentence, details: nil))
      }
    }
    picker = ask
    ask.begin(over: over)
  }

  /// The clipboard as the phone's is read (lib/editor/band/clipboard.dart): a picture copied out of it as
  /// `{path}`, else its words as `{text}`, else nothing. iOS asks the person before another app's copy is read.
  private static func clipboard() -> [String: Any] {
    let board = UIPasteboard.general
    if board.hasImages, let dirs = dirs() {
      let data = board.data(forPasteboardType: UTType.png.identifier) ?? board.data(forPasteboardType: UTType.jpeg.identifier) ?? board.image?.pngData()
      if let data = data, let path = PictureKeep.keep(data, cache: dirs.cache) { return ["path": path] }
      return ["error": "The picture on the clipboard could not be read."]
    }
    if board.hasStrings, let text = board.string, !text.isEmpty { return ["text": text] }
    return [:]
  }
}

/// One ask for a picture: the menu, then whichever chooser was picked from it, answered once.
private final class PictureAsk: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  enum Answer {
    case picked(String)
    case cancelled
    case failed(String)
  }

  private let cache: URL
  private var done: ((Answer) -> Void)?
  private weak var shown: UIViewController?

  init(cache: URL, done: @escaping (Answer) -> Void) {
    self.cache = cache
    self.done = done
  }

  private func answer(_ answer: Answer) {
    guard let done = done else { return }
    self.done = nil
    DispatchQueue.main.async { done(answer) }
  }

  /// Puts whatever is up away and answers that nothing was chosen.
  func cancel() {
    shown?.dismiss(animated: false)
    answer(.cancelled)
  }

  func begin(over: UIViewController) {
    let menu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
    menu.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self, weak over] _ in
      guard let self = self, let over = over else { return }
      var configuration = PHPickerConfiguration()
      configuration.filter = .images
      configuration.selectionLimit = 1
      let picker = PHPickerViewController(configuration: configuration)
      picker.delegate = self
      self.show(picker, over: over)
    })
    if UIImagePickerController.isSourceTypeAvailable(.camera) {
      menu.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self, weak over] _ in
        guard let self = self, let over = over else { return }
        let camera = UIImagePickerController()
        camera.sourceType = .camera
        camera.delegate = self
        self.show(camera, over: over)
      })
    }
    menu.addAction(UIAlertAction(title: "Choose File", style: .default) { [weak self, weak over] _ in
      guard let self = self, let over = over else { return }
      let files = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
      files.delegate = self
      files.allowsMultipleSelection = false
      self.show(files, over: over)
    })
    menu.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.answer(.cancelled) })
    // An iPad anchors a sheet somewhere; the app is an iPhone's, and this keeps a Duo from stopping on it.
    if let popover = menu.popoverPresentationController {
      popover.sourceView = over.view
      popover.sourceRect = CGRect(x: over.view.bounds.midX, y: over.view.bounds.maxY - 80, width: 1, height: 1)
      popover.permittedArrowDirections = []
    }
    shown = menu
    over.present(menu, animated: true)
  }

  private func show(_ controller: UIViewController, over: UIViewController) {
    controller.presentationController?.delegate = self
    shown = controller
    over.present(controller, animated: true)
  }

  private static let unread = "The picture could not be read."

  // Swiped away.
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    answer(.cancelled)
  }

  // MARK: the photo library

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let provider = results.first?.itemProvider else { return answer(.cancelled) }
    let cache = self.cache
    // The picture's own file, so its EXIF turn is read with it; a HEIC is opened by ImageIO as any other.
    provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _ in
      // The file is the system's and goes when this returns: it is shrunk into the cache here.
      if let url = url, let path = PictureKeep.keep(url, cache: cache) {
        self?.answer(.picked(path))
      } else {
        self?.answer(.failed(PictureAsk.unread))
      }
    }
  }

  // MARK: the camera

  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    picker.dismiss(animated: true)
    // A photo just taken has its turn in the UIImage, not in bytes: written as a JPEG it carries it as EXIF.
    guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.95), let path = PictureKeep.keep(data, cache: cache) else {
      return answer(.failed(PictureAsk.unread))
    }
    answer(.picked(path))
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    answer(.cancelled)
  }

  // MARK: the files

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { return answer(.cancelled) }
    if let path = PictureKeep.keep(url, cache: cache) { answer(.picked(path)) } else { answer(.failed(PictureAsk.unread)) }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    answer(.cancelled)
  }
}
