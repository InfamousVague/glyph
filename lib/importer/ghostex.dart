/// A `.ghostex` read back (docs/INTEGRATIONS.md §5): Settings › Import › A .ghostex file, the other half of
/// lib/export/ghostex.dart. Every note the manifest lists is made again with its own id, words, dates, pin and
/// archive, in a workspace of its workspace's name, with its pictures, its files and, where the export carried it,
/// its recording.
///
/// - **A note whose id is already here** is skipped ([GhostexCollision.skip]), or made again beside it as a copy
///   under a new id ([GhostexCollision.copy]), as the person chose. A skipped note's pictures and files are not
///   brought either: the note here has its own.
/// - **Workspaces** are found by name, or made, with their hues and the folders inside them, as the store finds
///   them (`addWorkspace`). An organization's notes come in as this person's own, in a workspace of the
///   organization's name: filing a note in an organization's workspace shares it with the team, and an import never
///   shares anything by itself. The report says so.
/// - **Pictures, files and recordings** are copied out of the ZIP one at a time into a file of their own and moved
///   into place by the device ([GhostexTarget]), so a long recording is never in memory whole. One that is here
///   already, by its name, is left as it is: the names are the app's own, made once and never reused.
/// - **Only what the manifest names is read**, each by its exact path in the ZIP: a name in the ZIP is never made
///   into a path on this device, and an id, a picture's name or a file's name that is not one the app would make is
///   not used (an id is made anew, a picture or file is left out and said).
///
/// A protected export is opened first (lib/export/ghostex_seal.dart), into the ZIP this reads.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import '../canvas/json_canvas.dart' show isCanvasBody;
import '../core/attachment_refs.dart' show attachmentName;
import '../core/book.dart' show isBookBody;
import '../core/library.dart';
import '../core/note.dart';
import '../core/workspaces.dart';
import '../export/ghostex.dart' show ghostexFormat, ghostexVersion;
import 'import_report.dart';

/// What a note whose id is already here becomes.
enum GhostexCollision {
  /// Left out: the note here stays as it is.
  skip,

  /// Made again under a new id, beside the one here.
  copy,
}

/// Where a read-back writes: the library, the workspaces, and the device's pictures, files and recordings, each kept
/// from a file the reader has made ([keepPicture], [keepFile] and [keepRecording] may move it).
class GhostexTarget {
  GhostexTarget({
    required this.library,
    required this.workspaces,
    required this.hasPicture,
    required this.keepPicture,
    required this.hasFile,
    required this.keepFile,
    required this.keepRecording,
    required this.temp,
    String Function()? newId,
  }) : _newId = newId ?? (() => newNoteId());

  final NoteLibrary library;
  final WorkspaceStore workspaces;
  final Future<bool> Function(String name) hasPicture;
  final Future<void> Function(String name, String path) keepPicture;
  final Future<bool> Function(String name) hasFile;
  final Future<void> Function(String name, String path) keepFile;
  final Future<void> Function(String noteId, String path) keepRecording;

  /// A folder for each file on its way out of the ZIP.
  final String temp;
  final String Function() _newId;
}

/// What a read-back did: an import's report, with the notes left out as already here and those made as copies.
class GhostexReport extends ImportReport {
  GhostexReport() : super(from: 'a .ghostex file');

  /// Notes whose id was here already, left out.
  int alreadyHere = 0;

  /// Notes whose id was here already, made again as copies.
  int copies = 0;
  int recordings = 0;

  /// Notes of an organization's, brought in as this person's own.
  int fromOrganizations = 0;
}

String _count(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// What a read-back made, in one sentence: "Imported 42 notes, 10 pictures and 3 files from the .ghostex file; 5
/// notes were here already and were left as they are."
String ghostexImportSaid(GhostexReport report) {
  final parts = [
    if (report.notes > 0) _count(report.notes, 'note'),
    if (report.notebooks > 0) _count(report.notebooks, 'notebook'),
    if (report.canvases > 0) _count(report.canvases, 'canvas', 'canvases'),
    if (report.pictures > 0) _count(report.pictures, 'picture'),
    if (report.files > 0) _count(report.files, 'file'),
    if (report.recordings > 0) _count(report.recordings, 'recording'),
  ];
  final listed = parts.isEmpty ? null : (parts.length == 1 ? parts.first : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}');
  final made = listed == null ? 'Nothing new was imported' : 'Imported $listed';
  final here = report.alreadyHere == 0
      ? ''
      : '; ${report.alreadyHere == 1 ? 'one note was here already and was' : '${report.alreadyHere} notes were here already and were'} left as ${report.alreadyHere == 1 ? 'it is' : 'they are'}';
  final copies = report.copies == 0 ? '' : '; ${report.copies == 1 ? 'one note was here already, so it came in as a copy' : '${report.copies} notes were here already, so they came in as copies'}';
  final orgs = report.fromOrganizations == 0
      ? ''
      : ' ${report.fromOrganizations == 1 ? 'One note was an organization’s: it is yours now' : '${report.fromOrganizations} notes were an organization’s: they are yours now'}, in a workspace of the organization’s name. File ${report.fromOrganizations == 1 ? 'it' : 'them'} in the organization to share ${report.fromOrganizations == 1 ? 'it' : 'them'} again.';
  return '$made$here$copies.$orgs';
}

final RegExp _idForm = RegExp(r'^[A-Za-z0-9_-]{1,100}$');
final RegExp _pictureForm = RegExp(r'^[A-Za-z0-9_-]{1,64}\.(?:jpg|jpeg|png|webp)$');

int? _ms(Object? iso) {
  if (iso is num) return iso.toInt();
  if (iso is! String) return null;
  return DateTime.tryParse(iso)?.millisecondsSinceEpoch;
}

/// The manifest of the ZIP at [zip], checked: a .ghostex's, of a version this build reads. Throws a [StateError]
/// in the app's words otherwise.
Map<String, Object?> _manifestOf(Archive archive) {
  final file = archive.findFile('manifest.json');
  if (file == null) throw StateError('That is not a .ghostex file: it has no manifest.');
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(file.readBytes() ?? const []));
  } catch (_) {
    throw StateError('That .ghostex file’s manifest could not be read.');
  }
  if (json is! Map || json['format'] != ghostexFormat) throw StateError('That is not a .ghostex file.');
  final version = json['version'];
  if (version is! int || version < 1) throw StateError('That .ghostex file’s manifest could not be read.');
  if (version > ghostexVersion) throw StateError('That export was made by a newer Ghost.md. Update the app to import it.');
  return json.cast<String, Object?>();
}

/// How many notes the ZIP at [zip] holds, and how many of them are here already: what the sheet says before the
/// person chooses.
Future<({int notes, int here})> ghostexCounts(String zip, NoteLibrary library) async {
  final input = InputFileStream(zip);
  try {
    final manifest = _manifestOf(ZipDecoder().decodeStream(input));
    final notes = (manifest['notes'] as List? ?? const []).whereType<Map>().toList();
    final here = notes.where((n) => n['id'] is String && library.noteOf(n['id'] as String) != null).length;
    return (notes: notes.length, here: here);
  } finally {
    await input.close();
  }
}

/// Reads the .ghostex ZIP at [zip] into [target]. [progress] hears each note as it is reached; [stopped] is asked
/// between notes, and a read-back stopped keeps what it made. Answers what it did.
Future<GhostexReport> importGhostex(String zip, GhostexTarget target, {GhostexCollision collision = GhostexCollision.skip, void Function(ImportProgress progress)? progress, bool Function()? stopped}) async {
  final report = GhostexReport();
  final input = InputFileStream(zip);
  final made = <String, String>{};
  final filed = <String, List<String>>{};
  var step = 0;
  try {
    final archive = ZipDecoder().decodeStream(input);
    final manifest = _manifestOf(archive);
    final notes = (manifest['notes'] as List? ?? const []).whereType<Map>().map((n) => n.cast<String, Object?>()).toList();
    final spaces = {
      for (final w in (manifest['workspaces'] as List? ?? const []).whereType<Map>())
        if (w['id'] is String) w['id'] as String: w.cast<String, Object?>(),
    };

    // A workspace of the export's, found or made here; its parents first. An organization's is a personal one of
    // its name, at the top.
    String? place(String? id, [Set<String>? seen]) {
      if (id == null) return null;
      final already = made[id];
      if (already != null) return already;
      final w = spaces[id];
      final name = w?['name'];
      if (w == null || name is! String || name.trim().isEmpty) return null;
      final org = w['organization'] is String || isOrgWorkspace(id);
      final route = seen ?? <String>{};
      final parent = !org && w['parent'] is String && route.add(id) ? place(w['parent'] as String, route) : null;
      final hue = w['hue'] is String ? w['hue'] as String : 'ink';
      final here = target.workspaces.addWorkspace(name, hue, parent);
      if (here == null) return null;
      return made[id] = here.id;
    }

    final pictures = <String>{}, files = <String>{};
    Future<String> out(ArchiveFile file) async {
      final dir = Directory(target.temp);
      await dir.create(recursive: true);
      final to = '${dir.path}/.${DateTime.now().microsecondsSinceEpoch}-$step.ghostex-part';
      final stream = OutputFileStream(to);
      try {
        file.writeContent(stream);
      } finally {
        await stream.close();
      }
      return to;
    }

    Future<void> gone(String path) async {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Left for the cache's own clearing.
      }
    }

    // A picture or a file, out of the ZIP and kept, once, unless it is here already.
    Future<void> bring(String name, {required bool picture}) async {
      final seen = picture ? pictures : files;
      if (!seen.add(name)) return;
      final valid = picture ? _pictureForm.hasMatch(name) : attachmentName.hasMatch(name);
      final entry = valid ? archive.findFile('${picture ? 'pictures' : 'files'}/$name') : null;
      if (entry == null || !entry.isFile) {
        report.missing += 1;
        return;
      }
      if (await (picture ? target.hasPicture(name) : target.hasFile(name))) return;
      final path = await out(entry);
      try {
        await (picture ? target.keepPicture(name, path) : target.keepFile(name, path));
        if (picture) {
          report.pictures += 1;
        } else {
          report.files += 1;
        }
      } catch (_) {
        report.skipped.add('${picture ? 'the picture' : 'the file'} $name, which could not be kept');
      } finally {
        await gone(path);
      }
    }

    for (final entry in notes) {
      if (stopped?.call() ?? false) break;
      step += 1;
      final title = entry['title'] is String ? entry['title'] as String : 'a note';
      progress?.call((done: step - 1, total: notes.length, on: title));
      final path = entry['path'];
      final file = path is String ? archive.findFile(path) : null;
      if (file == null || !file.isFile) {
        report.skipped.add('$title, whose words are not in the file');
        continue;
      }
      final given = entry['id'];
      final validId = given is String && _idForm.hasMatch(given);
      var id = validId ? given : target._newId();
      if (validId && target.library.noteOf(given) != null) {
        if (collision == GhostexCollision.skip) {
          report.alreadyHere += 1;
          continue;
        }
        id = target._newId();
        report.copies += 1;
      }
      final body = utf8.decode(file.readBytes() ?? const [], allowMalformed: true);
      for (final name in (entry['pictures'] as List? ?? const []).whereType<String>()) {
        await bring(name, picture: true);
      }
      for (final name in (entry['files'] as List? ?? const []).whereType<String>()) {
        await bring(name, picture: false);
      }

      int? recordingMs;
      List<Segment>? segments;
      final recording = entry['recording'];
      if (recording is Map && recording['path'] is String) {
        final tape = archive.findFile(recording['path'] as String);
        if (tape == null || !tape.isFile) {
          report.missing += 1;
        } else {
          final at = await out(tape);
          try {
            await target.keepRecording(id, at);
            recordingMs = (recording['ms'] as num?)?.toInt();
            segments = [
              for (final s in (recording['segments'] as List? ?? const []).whereType<Map>())
                if (s['start'] is num && s['end'] is num && s['text'] is String) Segment(startMs: (s['start'] as num).toInt(), endMs: (s['end'] as num).toInt(), text: s['text'] as String),
            ];
            report.recordings += 1;
          } catch (_) {
            report.skipped.add('the recording of $title, which could not be kept');
          } finally {
            await gone(at);
          }
        }
      }

      final created = _ms(entry['created']) ?? _ms(entry['updated']) ?? DateTime.now().millisecondsSinceEpoch;
      final archivedAt = entry['archived'] == true ? (_ms(entry['archivedAt']) ?? _ms(entry['updated']) ?? created) : null;
      final source = entry['source'] is String ? entry['source'] as String : 'editor';
      final note = Note(
        id: id,
        body: body,
        createdAt: created,
        updatedAt: _ms(entry['updated']) ?? created,
        source: source == 'capture' ? NoteSource.capture : NoteSource.editor,
        sourceName: source == 'capture' || source == 'editor' ? null : source,
        starred: entry['pinned'] == true,
        archivedAt: archivedAt,
        recordingMs: recordingMs != null && recordingMs > 0 ? recordingMs : null,
        segments: recordingMs != null && recordingMs > 0 ? segments : null,
      );
      final Note stored;
      try {
        stored = await target.library.apply(note);
      } catch (_) {
        report.skipped.add('$title, which could not be written');
        continue;
      }
      report.noteIds.add(stored.id);
      if (isCanvasBody(body)) {
        report.canvases += 1;
      } else if (isBookBody(body)) {
        report.notebooks += 1;
      } else {
        report.notes += 1;
      }
      final from = entry['workspace'] is String ? entry['workspace'] as String : null;
      if (from != null && (entry['organization'] is String || isOrgWorkspace(from))) report.fromOrganizations += 1;
      final into = place(from);
      if (into != null) (filed[into] ??= []).add(stored.id);
    }
    progress?.call((done: step, total: notes.length, on: null));
  } finally {
    for (final MapEntry(key: workspace, value: ids) in filed.entries) {
      target.workspaces.fileNotes(ids, workspace);
    }
    await input.close();
  }
  return report;
}
