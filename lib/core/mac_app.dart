/// Whether this process is the Mac app itself, and where the Mac app keeps what it carries.
///
/// The web app asked `isMacApp` of the agent string (`core/platform.ts`). Here there are two questions, and they
/// have different answers under `flutter test` on a Mac:
///
/// - **How the app should look and behave on a Mac** is `defaultTargetPlatform == TargetPlatform.macOS`, which a
///   test can set (`debugDefaultTargetPlatformOverride`) and which is true in a test run on a Mac.
/// - **Whether the Mac's own halves are there to be called** (the channels in macos/Runner, the library in the
///   app's Frameworks, the real data directory) is [runsAsMacApp]: true only inside the built app, never in a
///   test, where nothing answers a channel and the app's files must not be touched.
library;

import 'dart:io';

/// True inside the built Mac app: the executable is in an app bundle, and this is not a test run.
final bool runsAsMacApp = _inMacApp(executable: Platform.resolvedExecutable, macOS: Platform.isMacOS, test: Platform.environment.containsKey('FLUTTER_TEST'));

/// [runsAsMacApp]'s rule, for a test.
bool inMacAppFor({required String executable, required bool macOS, required bool test}) => _inMacApp(executable: executable, macOS: macOS, test: test);

bool _inMacApp({required String executable, required bool macOS, required bool test}) => macOS && !test && executable.contains('.app/Contents/MacOS/');

/// The Tauri app's bundle id: the name of the folder it keeps its library, settings and models in
/// (`~/Library/Application Support/com.mattssoftware.glyph`) and its caches under.
const String realAppId = 'com.mattssoftware.glyph';

/// Whether this is the build that replaces the Tauri app (`--dart-define=GHOST_CUTOVER=true`: tool/cutover-build.sh
/// for a phone, tool/cutover-build-mac.sh for a Mac, tool/cutover-build-ios.sh for an iPhone; docs/CUTOVER.md). On
/// a Mac and on an iPhone that build has the Tauri app's bundle id and still a folder of its own
/// (`com.mattssoftware.glyph.v2`, `cutoverFolder` in each Runner's GhostChannels.swift), into which what the Tauri
/// app kept is copied once (lib/carry/mac_carry.dart, lib/carry/iphone_carry.dart).
const bool replacesTauriApp = bool.fromEnvironment('GHOST_CUTOVER');

/// Whether this is the Mac build made for the Mac App Store (`--dart-define=GHOST_MAC_STORE=true`:
/// tool/cutover-build-mac-store.sh; docs/CUTOVER.md, section 9). It has Ghost.md's name and bundle id and runs in
/// the App Sandbox, which the store requires, so it differs from the build on the website in what a sandbox
/// changes: its files are in its own container (`~/Library/Containers/com.mattssoftware.glyph/Data/…`), it carries
/// nothing from an app outside that container (it starts as a new install, and an account brings the notes), a
/// folder the person chose is reached again through a bookmark the Mac keeps, it backs up to no drive, and it says
/// its updates are the App Store's. False in every other build, by a constant.
const bool macAppStore = bool.fromEnvironment('GHOST_MAC_STORE');

/// Whether this process runs in the Mac's App Sandbox: macOS gives a sandboxed app its container's id in its
/// environment, and an app that is not sandboxed has no such variable.
final bool inMacSandbox = Platform.isMacOS && (Platform.environment['APP_SANDBOX_CONTAINER_ID'] ?? '').isNotEmpty;

/// Whether the Mac itself, and not this app's code, keeps the app out of every other app's files: the store's
/// build, when it really is running sandboxed. Its container is a folder named by the bundle id, which is the
/// Tauri app's id, so [isRealAppPath] would read the container's own path as that app's folder; there the kernel
/// holds the rule and the path is taken as told (lib/core/native/device_paths.dart). A store build that somehow
/// runs outside a sandbox is held to [isRealAppPath] like any other.
bool get macSandboxKeepsFiles => macSandboxKeepsFilesFor(store: macAppStore, sandboxed: inMacSandbox);

/// [macSandboxKeepsFiles]'s rule, for a test.
bool macSandboxKeepsFilesFor({required bool store, required bool sandboxed}) => store && sandboxed;

/// Whether [path] is the Tauri app's own folder or a place inside it: any path with a folder named exactly
/// [realAppId] in it. This app's own folder is `com.mattssoftware.glyph.flutter`, a different name beside it, and
/// the folder of the build that replaces the Tauri app is `com.mattssoftware.glyph.v2`, another: in no build is
/// this app's folder the Tauri app's, so this is asked the same of every build.
///
/// The Mac app is not sandboxed (Matt, 2026-10-09: "un sandbox it"), so nothing but the app's own code keeps it out
/// of the Tauri app's files. The directories the core is opened on are asked this before anything is opened
/// (lib/core/native/device_paths.dart), as the Swift that names them is (macos/Runner/GhostChannels.swift
/// `ownDirectory`): the Flutter app never opens, moves or writes the Tauri app's library.
bool isRealAppPath(String path) {
  final parts = path.replaceAll('\\', '/').split('/');
  final walked = <String>[];
  for (final part in parts) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (walked.isNotEmpty) walked.removeLast();
      continue;
    }
    walked.add(part);
  }
  return walked.any((part) => part.toLowerCase() == realAppId);
}

/// Where the Rust core is in the Mac app: `<app>/Contents/Frameworks/libghost_core.dylib`, put there and signed
/// by Xcode's "Bundle the core" phase (tool/bundle-mac-core.sh). Asked for by its whole path: a bare name is
/// looked for along the loader's own paths, which do not include an app's Frameworks.
String bundledCoreIn(String executable) {
  final macOS = File(executable).parent;
  return '${macOS.parent.path}/Frameworks/libghost_core.dylib';
}
