/// Settings › Import's calls, as one value the root makes and Settings is handed (`SettingsFeatures.importer`):
/// choose a vault or some exports with the device's own picker, bring them in, and take an import back. Todoist's
/// account is read with a token pasted for the one import, and Things' lists from its database on a Mac or from
/// the text it copies, read off the clipboard.
///
/// The root makes it over the library, the workspaces, the core's pictures and the app's data folder
/// ([Importer.overLibrary]); a test makes one from its own [ImportPicker] and [ImportTarget].
library;

import 'dart:io' hide Platform;

import 'package:flutter/services.dart' show Clipboard;

import '../core/library.dart';
import '../core/mac_app.dart' show runsAsMacApp;
import '../core/native/core.dart';
import '../core/native/device_paths.dart';
import '../core/native/files.dart';
import '../core/shared_files.dart';
import '../core/workspaces.dart';
import 'evernote.dart';
import 'import_report.dart';
import 'import_sources.dart';
import 'import_target.dart';
import 'obsidian.dart';
import 'things.dart';
import 'things_database.dart';
import 'things_paste.dart';
import 'todoist.dart';
import 'todoist_csv.dart';
import '../core/host_platform.dart';

/// The text on the clipboard, or null for none.
Future<String?> clipboardText() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;

class Importer {
  Importer({
    required this.picker,
    required this.target,
    required this.workspaces,
    TodoistFetch? fetch,
    Future<String?> Function()? clipboard,
    String? Function()? home,
    Future<String> Function()? scratch,
    bool? onMac,
  })  : _fetch = fetch,
        _clipboard = clipboard ?? clipboardText,
        _home = home ?? (() => Platform.environment['HOME']),
        _scratch = scratch ?? (() async => Directory.systemTemp.path),
        _onMac = onMac;

  /// Over the app's own library: its pictures through the core, any other file beside them in the data folder.
  factory Importer.overLibrary({required NoteLibrary library, required WorkspaceStore workspaces, required CoreInvoke invoke, ImportPicker? picker}) {
    final files = CoreFiles(invoke);
    Future<DevicePaths>? paths;
    Future<DevicePaths> where() => paths ??= DevicePaths.find();
    return Importer(
      picker: picker ?? ImportPicker(cacheDir: () async => (await where()).cacheDir),
      workspaces: workspaces,
      scratch: () async => (await where()).cacheDir,
      target: () => ImportTarget(
        library: library,
        workspaces: workspaces,
        keepPicture: (name, bytes) async {
          await files.write(CoreFileKind.image, name, bytes);
        },
        keepFile: (source, name) async => storeSharedFile(source, name: name, dataDir: (await where()).dataDir),
      ),
    );
  }

  final ImportPicker picker;
  final ImportTarget Function() target;
  final WorkspaceStore workspaces;
  final TodoistFetch? _fetch;
  final Future<String?> Function() _clipboard;
  final String? Function() _home;
  final Future<String> Function() _scratch;
  final bool? _onMac;

  /// Whether this device can choose what to import (not an iPhone).
  bool get offered => picker.offered;

  /// Whether Things' own database can be looked for: the Mac app's.
  bool get thingsOnMacOffered => _onMac ?? runsAsMacApp;

  /// A vault chosen and brought in; null when the picker was closed.
  Future<ImportReport?> obsidian({void Function(ImportProgress progress)? progress, bool Function()? stopped}) async {
    final folder = await picker.chooseFolder();
    if (folder == null) return null;
    return importObsidianVault(folder, target(), progress: progress, stopped: stopped);
  }

  /// Exports chosen and brought in; null when the picker was closed.
  Future<ImportReport?> evernote({void Function(ImportProgress progress)? progress, bool Function()? stopped}) async {
    final files = await picker.chooseFiles();
    if (files == null || files.isEmpty) return null;
    return importEvernote(files, target(), progress: progress, stopped: stopped);
  }

  /// The Todoist account behind [token], brought in; [done] with the last year's completed tasks. The token is
  /// used for this and not kept.
  Future<ImportReport?> todoist(String token, {bool done = false, void Function(ImportProgress progress)? progress, bool Function()? stopped}) =>
      importTodoist(token, target(), done: done, fetch: _fetch, progress: progress, stopped: stopped);

  /// A project's CSV exports chosen and brought in; null when the picker was closed.
  Future<ImportReport?> todoistCsv({void Function(ImportProgress progress)? progress, bool Function()? stopped}) async {
    final files = await picker.chooseFiles(kind: 'csv');
    if (files == null || files.isEmpty) return null;
    return importTodoistCsv(files, target(), progress: progress, stopped: stopped);
  }

  /// Things' own database on this Mac, read from a copy and brought in; [done] with the Logbook.
  Future<ImportReport?> thingsOnMac({bool done = false, void Function(ImportProgress progress)? progress, bool Function()? stopped}) async {
    final home = _home();
    final database = home == null ? null : thingsDatabaseIn(home);
    if (database == null) throw StateError('Things was not found on this Mac. Open it once, or use Paste from Things.');
    final library = await readThingsCopy(database, await _scratch());
    return importThingsLibrary(library, target(), done: done, progress: progress, stopped: stopped);
  }

  /// What Things copied (Share › Copy), read off the clipboard and brought in as one note.
  Future<ImportReport?> thingsPaste() async {
    final text = await _clipboard();
    if (text == null || text.trim().isEmpty) throw StateError('Nothing is copied. In Things, open a list, choose Share › Copy, and come back.');
    return importThingsPaste(text, target());
  }

  /// An import taken back: its notes in the trash, its workspace gone.
  void remove(ImportReport report) => removeImport(workspaces, report);
}
