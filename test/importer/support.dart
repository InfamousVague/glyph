import 'dart:io';
import 'dart:typed_data';

import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/shared_files.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/importer/import_target.dart';

/// A library in memory to import into, with one note of its own already where an import might put one, the
/// pictures kept in a map, and the other files kept for real under a folder of the test's.
class ImportHarness {
  ImportHarness({List<Note> notes = const []})
      : library = SampleLibrary(notes),
        trash = MemoryTrash(),
        data = Directory.systemTemp.createTempSync('ghost-import-');

  final SampleLibrary library;
  final MemoryTrash trash;
  late final WorkspaceStore workspaces = WorkspaceStore(trash: trash);
  final Directory data;
  final Map<String, Uint8List> pictures = {};
  var _notes = 0;
  var _pictures = 0;

  ImportTarget target() => ImportTarget(
        library: library,
        workspaces: workspaces,
        keepPicture: (name, bytes) async => pictures[name] = bytes,
        keepFile: (source, name) => storeSharedFile(source, name: name, dataDir: data.path),
        now: () => DateTime(2026, 10, 16, 9),
        newId: () => 'n${++_notes}',
        pictureId: () => 'p${++_pictures}',
      );

  /// The note the import put at [path], or none.
  Note? at(String path) {
    for (final note in library.value) {
      if (note.path == path) return note;
    }
    return null;
  }

  /// The files kept beside the pictures, by name.
  Map<String, Uint8List> get files {
    final dir = Directory('${data.path}/$sharedFilesFolder');
    if (!dir.existsSync()) return {};
    return {for (final file in dir.listSync().whereType<File>()) file.uri.pathSegments.last: file.readAsBytesSync()};
  }

  void dispose() => data.deleteSync(recursive: true);
}

/// The fixtures' folder.
String fixture(String path) => 'test/importer/fixtures/$path';
