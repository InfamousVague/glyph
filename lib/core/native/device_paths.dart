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
/// **Anywhere else** (the Mac, while the app has no Mac target of its own) it is a folder under the system's
/// temporary directory, so the app runs and nothing of a person's is mistaken for it. Stage 10 gives the Mac its
/// real one (`~/Library/Application Support/<id>`, Tauri's).
library;

import 'dart:io';

import 'package:flutter/services.dart';

class DevicePaths {
  const DevicePaths({required this.dataDir, required this.cacheDir});

  /// `<app_data_dir>`: the library, recordings and pictures are under it.
  final String dataDir;

  /// `<app_cache_dir>`: what may be lost (`picked/`).
  final String cacheDir;

  /// The channel MainActivity.kt answers: `dirs` gives `{dataDir, cacheDir}`.
  static const MethodChannel channel = MethodChannel('ghost_md/device_paths');

  /// The app's directories on this device.
  static Future<DevicePaths> find() => Platform.isAndroid ? fromActivity() : Future.value(fallback());

  /// What the Android activity says they are.
  static Future<DevicePaths> fromActivity() async {
    final dirs = await channel.invokeMapMethod<String, String>('dirs');
    final data = dirs?['dataDir'], cache = dirs?['cacheDir'];
    if (data == null || cache == null) {
      throw StateError('The phone did not say where Ghost.md keeps its files.');
    }
    return DevicePaths(dataDir: data, cacheDir: cache);
  }

  /// Off Android: `<temp>/ghost_md/data` and `<temp>/ghost_md/cache`, the same on every run.
  static DevicePaths fallback() {
    final root = '${Directory.systemTemp.path}${Platform.pathSeparator}ghost_md';
    return DevicePaths(
      dataDir: '$root${Platform.pathSeparator}data',
      cacheDir: '$root${Platform.pathSeparator}cache',
    );
  }
}
