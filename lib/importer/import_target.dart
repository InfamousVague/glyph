/// Where an import writes: the library's notes, its pictures, the files beside them, and the one workspace that
/// holds the lot.
///
/// **Why a workspace.** An import makes one group so it can be taken away in one go, and the app's folders are its
/// workspaces (the sidebar draws a folder for each, and each is a folder on disk, `workspaces/<name>/`). A folder of
/// the import's own with no workspace would be a folder only Finder and Obsidian could see; a notebook would make
/// every imported note one of its pages. So the import is a workspace, "Imported from Obsidian 2026-10-16", whose
/// folder holds the vault's own folders as they were. Taking it back is the workspace's own Delete with "put the
/// notes in the trash" (Settings › Workspaces, or the import's own Remove this import): every note goes to the
/// trash, where it can be restored, until the trash is emptied.
///
/// Each note is written whole with its own dates (`store_apply`, [NoteLibrary.apply]), at a path [ImportPaths] has
/// made sure is free, and filed in the workspace a batch at a time ([WorkspaceStore.fileNotes]), so an import cut
/// short still has everything it made in the workspace.
library;

import 'dart:typed_data';

import '../core/images.dart' show imageMarkdown;
import '../core/library.dart';
import '../core/note.dart';
import '../core/shared_files.dart';
import '../core/workspaces.dart';
import 'import_paths.dart';
import 'import_report.dart';

/// The largest picture the core keeps (native/src/kept/images.rs `MAX_BYTES`): a larger one is kept as a file.
const int largestPicture = 25 * 1024 * 1024;

/// The kind of picture the library keeps that [bytes] are, by their first bytes as the core reads them
/// (images.rs `kind`): `jpg`, `png` or `webp`, and null for anything else (a GIF, a HEIC, an SVG), which is kept as
/// a file.
String? pictureKind(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return 'jpg';
  if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 && bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A) return 'png';
  if (bytes.length >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) return 'webp';
  return null;
}

/// Keeps a picture's bytes among the library's pictures under [name] (`sync_put_file`, lib/core/native/files.dart).
typedef KeepPicture = Future<void> Function(String name, Uint8List bytes);

/// Keeps a file that is not a picture and answers its link, `file/<name>` (lib/core/shared_files.dart).
typedef KeepFile = Future<String> Function(SharedFileSource source, String name);

/// What an import is given to write with.
class ImportTarget {
  ImportTarget({required this.library, required this.workspaces, required this.keepPicture, required this.keepFile, DateTime Function()? now, String Function()? newId, String Function()? pictureId})
      : _now = now ?? DateTime.now,
        _newId = newId ?? (() => newNoteId()),
        _pictureId = pictureId ?? (() => newNoteId());

  final NoteLibrary library;
  final WorkspaceStore workspaces;
  final KeepPicture keepPicture;
  final KeepFile keepFile;
  final DateTime Function() _now;
  final String Function() _newId;
  final String Function() _pictureId;

  /// An import from [from] (`Obsidian`, `Evernote`) begun now: its workspace made and named, and every path the
  /// library holds known, so nothing is written over.
  ImportRun begin(String from) {
    final at = _now();
    final name = importGroupName(from, at, [for (final w in workspaces.value.list) w.name]);
    final group = workspaces.addWorkspace(name);
    final report = ImportReport(from: from)
      ..groupId = group?.id
      ..groupName = group?.name ?? name;
    final paths = ImportPaths(taken: [for (final note in library.value) ?note.path], group: report.groupName!);
    return ImportRun._(this, report, paths, at.millisecondsSinceEpoch);
  }
}

/// One import under way.
class ImportRun {
  ImportRun._(this._target, this.report, this.paths, this.startedAt);

  final ImportTarget _target;
  final ImportReport report;
  final ImportPaths paths;

  /// When it began, for a note with no date of its own.
  final int startedAt;

  /// Notes made and not yet filed in the workspace.
  final List<String> _unfiled = [];

  /// How many notes are filed at a time.
  static const int batch = 40;

  /// Keeps a picture and answers what a note shows it by (`image/<name>`), or null where it is not a picture the
  /// library keeps (by its bytes) or is too large: the caller keeps it as a file.
  Future<String?> picture(Uint8List bytes) async {
    final kind = pictureKind(bytes);
    if (kind == null || bytes.length > largestPicture) return null;
    final name = '${_target._pictureId()}.$kind';
    await _target.keepPicture(name, bytes);
    report.pictures += 1;
    return 'image/$name';
  }

  /// The Markdown for a picture kept by [picture]: `![caption](image/<name>)`.
  static String pictureMarkdown(String ref, [String caption = '']) => imageMarkdown(ref.substring('image/'.length), caption);

  /// Keeps a file that is not a picture and answers its link, `file/<name>`.
  Future<String> file(SharedFileSource source, String name) async {
    final ref = await _target.keepFile(source, name);
    report.files += 1;
    return ref;
  }

  /// Writes a note at [path] with [body] and its own dates, and answers its id. Never over another: [path] is one
  /// [paths] gave out, and the library itself takes another name for a path it finds taken.
  Future<String> note({required String body, required String path, int? createdAt, int? updatedAt, bool canvas = false, bool notebook = false}) async {
    final id = _target._newId();
    final created = createdAt ?? updatedAt ?? startedAt;
    final note = Note(id: id, body: body, createdAt: created, updatedAt: updatedAt ?? created, path: path);
    final stored = await _target.library.apply(note);
    report.noteIds.add(stored.id);
    if (canvas) {
      report.canvases += 1;
    } else if (notebook) {
      report.notebooks += 1;
    } else {
      report.notes += 1;
    }
    _unfiled.add(stored.id);
    if (_unfiled.length >= batch) _file();
    return stored.id;
  }

  void _file() {
    final id = report.groupId;
    if (_unfiled.isEmpty || id == null) return;
    _target.workspaces.fileNotes([..._unfiled], id);
    _unfiled.clear();
  }

  /// The end, whole or cut short: what is left is filed, and a workspace nothing went into is taken away again.
  ImportReport finish() {
    _file();
    report.renamed
      ..clear()
      ..addAll(paths.renamed);
    final id = report.groupId;
    if (report.empty && id != null) {
      _target.workspaces.removeWorkspace(id);
      report.groupId = null;
    }
    return report;
  }
}

/// Takes an import back: every note it made into the trash and its workspace gone (`deleteWorkspace` with the
/// notes trashed). Nothing is deleted for good: the trash holds them until it is emptied.
void removeImport(WorkspaceStore workspaces, ImportReport report) {
  final id = report.groupId;
  if (id == null) return;
  workspaces.deleteWorkspace(id, trashNotes: true);
}
