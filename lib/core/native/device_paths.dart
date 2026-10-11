/// Where the app keeps its files: the two directories the Rust core is opened on (`init`, ghost_core.dart). It
/// stands in for `../glyph/src-tauri/src/paths.rs`'s `data_dir` and `cache_dir`, which asked Tauri.
///
/// **On Android they are the directories the Tauri app uses**, so the layout under them is the same file for
/// file (`Library/`, `recordings/`, `images/`, `library-root.json`): Tauri 2.11.5's `app_data_dir` is its
/// `PathPlugin.getDataDir`, which answers `activity.dataDir` (the parent of `filesDir`,
/// `/data/user/0/<application id>`), and `app_cache_dir` is `activity.cacheDir`. MainActivity.kt answers the
/// same two over a method channel. Not `path_provider`'s `getApplicationSupportDirectory`, which is `filesDir`:
/// one level down, where a library moved over from the Tauri app would not be found.
///
/// **In the Mac app** they are Tauri's two as well, `<Application Support>/<bundle id>` and `<Caches>/<bundle id>`,
/// answered by macos/Runner/GhostChannels.swift over the same channel. The bundle id is this app's own, so they
/// are `~/Library/Application Support/com.mattssoftware.glyph.flutter` and
/// `~/Library/Caches/com.mattssoftware.glyph.flutter`: beside the Tauri app's
/// `~/Library/Application Support/com.mattssoftware.glyph`, never it and never in it. The app is not sandboxed, so
/// that is held here, in code: whatever is answered is refused if it is the Tauri app's folder or a place inside
/// it ([isRealAppPath], lib/core/mac_app.dart), and the core is then never opened.
///
/// **In the iPhone app** they are the same two names inside the app's container
/// (`<container>/Library/Application Support/com.mattssoftware.glyph.flutter` and `…/Library/Caches/…`), answered
/// by ios/Runner/GhostChannels.swift: where Tauri's `app_data_dir` and `app_cache_dir` are on an iPhone. No other
/// app's files can be reached from there, the real Ghost.md's included.
///
/// **Anywhere else** (a test on the Mac, a `flutter run` outside an app bundle) it is a folder under the system's
/// temporary directory, so the app runs and nothing of a person's is mistaken for it.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import '../iphone_app.dart';
import '../mac_app.dart';

class DevicePaths {
  const DevicePaths({required this.dataDir, required this.cacheDir});

  /// `<app_data_dir>`: the library, recordings and pictures are under it.
  final String dataDir;

  /// `<app_cache_dir>`: what may be lost (`picked/`).
  final String cacheDir;

  /// The channel MainActivity.kt answers, and the Mac's GhostChannels.swift: `dirs` gives `{dataDir, cacheDir}`.
  static const MethodChannel channel = MethodChannel('ghost_md/device_paths');

  /// The app's directories on this device.
  static Future<DevicePaths> find() => Platform.isAndroid || runsAsMacApp || runsAsIPhoneApp ? fromActivity() : Future.value(fallback());

  /// What the Android activity, or the Mac app, says they are.
  static Future<DevicePaths> fromActivity() async {
    final dirs = await channel.invokeMapMethod<String, String>('dirs');
    final data = dirs?['dataDir'], cache = dirs?['cacheDir'];
    if (data == null || cache == null) {
      throw StateError('The device did not say where Ghost.md keeps its files.');
    }
    return DevicePaths.told(dataDir: data, cacheDir: cache, sandboxed: Platform.isAndroid);
  }

  /// What a device said its two directories are. [sandboxed] is an Android phone, where the system gives every app
  /// its own folder by its id and no other app's can be reached at all: there the folder IS this app's whatever
  /// its name, and when this app is built to replace the Tauri app (android/app/build.gradle.kts, `GHOST_CUTOVER`)
  /// its id, and so its folder's name, is the Tauri app's own, with that app's library in it to be carried on
  /// with (lib/carry/tauri_carry.dart). Anywhere else the name is all that keeps the two apart, and [own] refuses.
  factory DevicePaths.told({required String dataDir, required String cacheDir, required bool sandboxed}) =>
      sandboxed ? DevicePaths(dataDir: dataDir, cacheDir: cacheDir) : DevicePaths.own(dataDir: dataDir, cacheDir: cacheDir);

  /// The two directories, refused if either is the Tauri app's own folder or inside it: this app has a folder of
  /// its own and opens no other app's library.
  factory DevicePaths.own({required String dataDir, required String cacheDir}) {
    if (isRealAppPath(dataDir) || isRealAppPath(cacheDir)) {
      throw StateError('Ghost Flutter keeps its own files and will not open Ghost.md’s.');
    }
    return DevicePaths(dataDir: dataDir, cacheDir: cacheDir);
  }

  /// Off Android and outside the Mac app: `<temp>/ghost_md/data` and `<temp>/ghost_md/cache`, the same on every run.
  static DevicePaths fallback() {
    final root = '${Directory.systemTemp.path}${Platform.pathSeparator}ghost_md';
    return DevicePaths(
      dataDir: '$root${Platform.pathSeparator}data',
      cacheDir: '$root${Platform.pathSeparator}cache',
    );
  }
}
