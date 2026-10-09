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

/// Whether [path] is the Tauri app's own folder or a place inside it: any path with a folder named exactly
/// [realAppId] in it. This app's own folder is `com.mattssoftware.glyph.flutter`, a different name beside it.
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
