/// Settings › Import's calls, as one value the root makes and Settings is handed (`SettingsFeatures.importer`):
/// choose a vault or some exports with the device's own picker, bring them in, and take an import back.
///
/// The root makes it over the library, the workspaces, the core's pictures and the app's data folder
/// ([Importer.overLibrary]); a test makes one from its own [ImportPicker] and [ImportTarget].
library;

import '../core/library.dart';
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

class Importer {
  Importer({required this.picker, required this.target, required this.workspaces});

  /// Over the app's own library: its pictures through the core, any other file beside them in the data folder.
  factory Importer.overLibrary({required NoteLibrary library, required WorkspaceStore workspaces, required CoreInvoke invoke, ImportPicker? picker}) {
    final files = CoreFiles(invoke);
    Future<DevicePaths>? paths;
    Future<DevicePaths> where() => paths ??= DevicePaths.find();
    return Importer(
      picker: picker ?? ImportPicker(cacheDir: () async => (await where()).cacheDir),
      workspaces: workspaces,
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

  /// Whether this device can choose what to import (not an iPhone).
  bool get offered => picker.offered;

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

  /// An import taken back: its notes in the trash, its workspace gone.
  void remove(ImportReport report) => removeImport(workspaces, report);
}
