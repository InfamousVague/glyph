/// Done with the app closed: what the phone starts, in an engine of its own with no window, when a reminder's Done
/// is pressed or a to-do is ticked on the home screen and no app is running to take it (GhostBackground.kt). It opens
/// the library's core as the app does (the same process may have the app's open too: the core is the process's one,
/// and opening it again on the same folders is answered at once), reads the notes, writes the tick through the
/// library's own save (done_writer.dart), and says it has finished, so the phone lets the engine go.
///
/// The core is opened deaf to its events (`hears: false`), so an app started meanwhile keeps them. Nothing else of
/// the app is made here: no window, no account, no sync. The note is sent by the next sync like any other change
/// made on this device, and the app reads it the next time it opens.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/core_library.dart';
import '../core/native/ghost_core.dart';
import 'done_writer.dart';

/// The channel the phone hears the end on.
const MethodChannel backgroundChannel = MethodChannel('ghost_md/background');

/// The entry point GhostBackground.kt runs: [args] is one JSON object, `{dataDir, cacheDir, note, line, words}`.
@pragma('vm:entry-point')
Future<void> ghostBackground(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  var ok = false;
  String? why;
  GhostCore? core;
  try {
    final job = jsonDecode(args.isEmpty ? '{}' : args.first) as Map<String, Object?>;
    final note = job['note'], line = job['line'], words = job['words'], dataDir = job['dataDir'], cacheDir = job['cacheDir'];
    if (note is! String || line is! int || dataDir is! String || cacheDir is! String) throw const FormatException('not a job');
    core = await GhostCore.open(hears: false);
    await core.init(dataDir: dataDir, cacheDir: cacheDir);
    final library = CoreLibrary(core.invoke, resume: false);
    await library.load();
    ok = await writeDone(library, note, line, words is String ? words : '');
    library.dispose();
  } catch (failure) {
    why = '$failure';
  }
  try {
    await core?.close();
  } catch (_) {
    // Going anyway.
  }
  try {
    await backgroundChannel.invokeMethod<void>('finished', {'ok': ok, 'why': ?why});
  } on MissingPluginException {
    // Nobody to tell: the phone's own clock lets the engine go.
  }
}
