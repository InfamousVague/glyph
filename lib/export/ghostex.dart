/// Everything as one `.ghostex` file (docs/INTEGRATIONS.md §5): Settings › Account › Export everything, and read back
/// by Settings › Import › A .ghostex file (lib/importer/ghostex.dart). The writer.
///
/// A .ghostex is a ZIP:
///
/// ```
/// manifest.json                  { format: "ghostex", version: 1, exportedAt, app, notes: [...], workspaces, notebooks }
/// notes/<workspace>/<title>.md   each note's markdown, as kept, front matter included
/// pictures/<name>                the pictures the notes name
/// files/<name>                   attachments
/// recordings/<note id>.wav       only when "Include recordings" is ticked
/// ```
///
/// - **A note's path** is its workspace's folder (a folder inside a folder as `Work/Clients`), then its title as a
///   file name ([ghostexFileName]): what a file system will not hold taken out, never empty, never hidden, never one
///   of Windows' own device names, and short enough for any disk. Two notes of one title in one folder are
///   `Title.md` and `Title 2.md`, compared as a Mac or Windows compares names, without case. A note in no workspace
///   is directly under `notes/`.
/// - **The manifest** lists every note with its id, its path in the ZIP, title, created, updated, pinned, archived,
///   workspace, organization and tags, and what a read-back needs to make it again exactly: when it was archived,
///   where it came from, the pictures and files it names, and its recording's length and phrases. The workspaces are
///   listed with their names, hues and parents, an organization's with the organization's id; the notebooks with
///   their pages.
/// - **A recording** is the core's own (a RIFF WAV, `CoreFiles` `recording`), so it is `recordings/<id>.wav`; the
///   contract's `.m4a` is the extension a compressed one would have, and none is kept as one.
/// - **Options** ([GhostexOptions]): archived notes, organizations' notes and recordings are each left out unless
///   ticked; notes in the trash are never in it. "Protect with a password" seals the whole ZIP afterwards
///   (lib/export/ghostex_seal.dart).
///
/// **Not every byte at once.** The notes are read from the list the library already holds; the pictures, files and
/// recordings are named by their paths on this device and streamed into the ZIP one at a time, on an isolate of its
/// own, so a long recording is never in memory whole and the screen keeps its frames. The Markdown and the manifest
/// are compressed; pictures, files and recordings are stored, since they are compressed already or barely shrink.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import '../canvas/json_canvas.dart' show canvasOf, isCanvasBody;
import '../core/attachment_refs.dart' show attachmentNames;
import '../core/backup.dart' show isoInstant;
import '../core/book.dart' show chaptersOf, isBookBody, isJournalBody;
import '../core/images.dart' show imageNames;
import '../core/library.dart';
import '../core/note.dart';
import '../core/note_marks.dart';
import '../core/note_text.dart' show noteTitle;
import '../core/workspaces.dart';
import 'ghostex_seal.dart';

/// What the manifest says it is.
const String ghostexFormat = 'ghostex';

/// The manifest's version: what a reader checks before it trusts the rest.
const int ghostexVersion = 1;

/// The file's extension, without its dot.
const String ghostexExtension = 'ghostex';

String _two(int n) => n.toString().padLeft(2, '0');

/// `<handle>-<YYYY-MM-DD>.ghostex` on the device's own clock (docs/INTEGRATIONS.md §5): `matt-2026-10-17.ghostex`.
/// A device with no account is `ghost-…`.
String ghostexName(String? handle, DateTime at) {
  final who = ghostexFileName(handle ?? '', fallback: 'ghost').replaceAll(' ', '-');
  return '$who-${at.year}-${_two(at.month)}-${_two(at.day)}.$ghostexExtension';
}

final RegExp _unsafeInName = RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _leading = RegExp(r'^[.\s]+');
final RegExp _trailing = RegExp(r'[.\s]+$');
final RegExp _deviceName = RegExp(r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$', caseSensitive: false);

/// The most bytes of UTF-8 a name is given before its extension: room for ` 99.md` inside any disk's 255.
const int _longestName = 120;

/// [title] as a file or folder name that every disk holds: a slash, a colon and the rest of what Windows refuses
/// taken out, runs of space made one, no dot or space at either end (a name starting with a dot is hidden), cut to
/// [_longestName] bytes at a whole character, and never a device name (`CON`, `LPT1`). Empty, it is [fallback].
String ghostexFileName(String title, {String fallback = 'Untitled'}) {
  var name = title.replaceAll(_unsafeInName, ' ').replaceAll(_spaces, ' ').replaceFirst(_leading, '').replaceFirst(_trailing, '');
  if (utf8.encode(name).length > _longestName) {
    final runes = name.runes.toList();
    var bytes = 0, keep = 0;
    for (final rune in runes) {
      final size = utf8.encode(String.fromCharCode(rune)).length;
      if (bytes + size > _longestName) break;
      bytes += size;
      keep += 1;
    }
    name = String.fromCharCodes(runes.take(keep)).replaceFirst(_trailing, '');
  }
  if (name.isEmpty) name = fallback;
  if (_deviceName.hasMatch(name)) name = '$name (note)';
  return name;
}

/// The names given out in a ZIP, so no two are one, compared without case as a Mac's or Windows' disk compares them.
class GhostexNames {
  final Set<String> _taken = {};

  /// `folder/stem.ext`, or `folder/stem 2.ext` and on where that is taken. [folder] may be empty.
  String place(String folder, String stem, String ext) {
    String at(int n) => '${folder.isEmpty ? '' : '$folder/'}${n == 1 ? stem : '$stem $n'}${ext.isEmpty ? '' : '.$ext'}';
    var n = 1;
    while (!_taken.add(at(n).toLowerCase())) {
      n += 1;
    }
    return at(n);
  }
}

/// What an export takes in. Every one is left out unless asked for.
@immutable
class GhostexOptions {
  const GhostexOptions({this.archived = false, this.organizations = false, this.recordings = false, this.password});

  /// The notes in the archive.
  final bool archived;

  /// The notes filed in an organization's workspace: the team's, not only this person's.
  final bool organizations;

  /// Each spoken note's recording, as it was kept.
  final bool recordings;

  /// "Protect with a password": the whole file sealed (lib/export/ghostex_seal.dart). Null or empty is a plain ZIP.
  final String? password;

  bool get sealed => (password ?? '').isNotEmpty;
}

/// Where an export reads from: the notes, their workspaces, and where each picture, file and recording lies on this
/// device. The app's is made over the core (lib/export/ghostex_calls.dart); a test's over files of its own.
class GhostexSource {
  GhostexSource({required this.library, required this.workspaces, required this.picturePath, required this.filePath, required this.recordingPath});

  final NoteLibrary library;

  /// The workspaces and which notes are filed in each, and the trash ([WorkspaceStore.trash]), whose notes stay out.
  final WorkspaceStore workspaces;

  /// Where the picture of that name is on this device, or null where it is not here.
  final Future<String?> Function(String name) picturePath;

  /// Where the attachment of that name (`file/<name>`) is, or null.
  final Future<String?> Function(String name) filePath;

  /// Where the recording of the note of that id is, or null.
  final Future<String?> Function(String noteId) recordingPath;
}

/// How far an export has got: what it is on, and how many of how many.
typedef GhostexProgress = ({int done, int total, String step});

/// What an export wrote.
@immutable
class GhostexWritten {
  const GhostexWritten({required this.path, required this.notes, required this.pictures, required this.files, required this.recordings, required this.bytes, this.missing = 0});

  /// The finished file.
  final String path;
  final int notes;
  final int pictures;
  final int files;
  final int recordings;

  /// The file's size.
  final int bytes;

  /// Pictures, files and recordings a note names that are not on this device, and so are not in the file.
  final int missing;
}

/// What an export writes, and the end of it in words: "Exported 312 notes, 48 pictures and 3 files, 1.2 GB."
String ghostexDoneSaid(GhostexWritten written, {String? name}) {
  String count(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';
  final parts = [
    count(written.notes, 'note'),
    if (written.pictures > 0) count(written.pictures, 'picture'),
    if (written.files > 0) count(written.files, 'file'),
    if (written.recordings > 0) count(written.recordings, 'recording'),
  ];
  final listed = parts.length == 1 ? parts.first : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  final missing = written.missing == 0 ? '' : ' ${written.missing == 1 ? 'One file a note names is' : '${written.missing} files notes name are'} not on this device, and not in it.';
  return 'Exported $listed${name == null ? '' : ' as $name'}.$missing';
}

/// One entry of the ZIP: words, or a file on this device streamed in.
@immutable
class GhostexEntry {
  const GhostexEntry.text(this.name, String this.text, {required this.modified})
      : path = null,
        compress = true;
  const GhostexEntry.file(this.name, String this.path, {required this.modified})
      : text = null,
        compress = false;

  /// Its path in the ZIP.
  final String name;
  final String? text;
  final String? path;
  final bool compress;

  /// Milliseconds since the epoch.
  final int modified;
}

/// An organization's id, where the workspace [id] is one's.
String? _orgOf(String? id) => id == null ? null : orgIdOf(id);

final RegExp _pictureName = RegExp(r'^[A-Za-z0-9_-]{1,64}\.(?:jpg|jpeg|png|webp)$');

/// Every picture a note shows: its `![](image/<name>)` and, for a canvas, its picture cards' bare names.
List<String> ghostexPictures(String body) {
  final names = <String>{...imageNames(body)};
  if (isCanvasBody(body)) {
    for (final node in canvasOf(body)?.nodes ?? const []) {
      final file = node.fields['file'];
      if (node.fields['type'] == 'file' && file is String && _pictureName.hasMatch(file)) names.add(file);
    }
  }
  return names.toList();
}

/// The manifest and the ZIP's entries for [source] under [options]: everything the export will write, worked out
/// before a byte is. Asked of the library and the device; nothing is read whole but the notes' words.
Future<({Map<String, Object?> manifest, List<GhostexEntry> entries, int missing})> ghostexPlan(GhostexSource source, GhostexOptions options, {required DateTime at, String app = 'Ghost.md'}) async {
  final spaces = source.workspaces.value;
  final trash = source.workspaces.trash;
  final byId = {for (final w in spaces.list) w.id: w};
  final names = GhostexNames();
  final entries = <GhostexEntry>[];

  // Each workspace's folder, by id: its path of names, each made safe, and two that come out the same told apart.
  final folders = <String, String>{};
  final usedFolders = <String>{};
  String folderOf(String id) {
    final made = folders[id];
    if (made != null) return made;
    final parts = [for (final w in workspacePath(spaces.list, id)) ghostexFileName(w.name, fallback: 'Workspace')];
    final base = parts.join('/');
    var folder = base;
    for (var n = 2; usedFolders.contains(folder.toLowerCase()); n += 1) {
      folder = '$base $n';
    }
    usedFolders.add(folder.toLowerCase());
    return folders[id] = folder;
  }

  final chosen = <Note>[];
  for (final note in source.library.value) {
    if (trash?.isTrashed(note.id) ?? false) continue;
    if ((note.archivedAt ?? 0) != 0 && !options.archived) continue;
    final workspace = spaces.of[note.id];
    if (_orgOf(workspace) != null && !options.organizations) continue;
    chosen.add(note);
  }
  // Oldest first, so the first of two notes of one title keeps the plain name, whatever was edited last.
  chosen.sort((a, b) => a.createdAt != b.createdAt ? a.createdAt.compareTo(b.createdAt) : a.id.compareTo(b.id));

  final pictures = <String>{}, files = <String>{};
  final notes = <Map<String, Object?>>[];
  final notebooks = <Map<String, Object?>>[];
  final usedSpaces = <String>{};
  var missing = 0;
  for (final note in chosen) {
    final workspace = spaces.of[note.id];
    final inWorkspace = workspace != null && byId.containsKey(workspace) ? workspace : null;
    if (inWorkspace != null) {
      for (final w in workspacePath(spaces.list, inWorkspace)) {
        usedSpaces.add(w.id);
      }
    }
    final title = noteTitle(note.body);
    final path = names.place(inWorkspace == null ? 'notes' : 'notes/${folderOf(inWorkspace)}', ghostexFileName(title), 'md');
    entries.add(GhostexEntry.text(path, note.body, modified: note.updatedAt));
    final shows = ghostexPictures(note.body);
    final links = attachmentNames(note.body).toSet().toList();
    pictures.addAll(shows);
    files.addAll(links);
    final entry = <String, Object?>{
      'id': note.id,
      'path': path,
      'title': title,
      'created': isoInstant(DateTime.fromMillisecondsSinceEpoch(note.createdAt)),
      'updated': isoInstant(DateTime.fromMillisecondsSinceEpoch(note.updatedAt)),
      'pinned': note.starred,
      'archived': (note.archivedAt ?? 0) != 0,
      if ((note.archivedAt ?? 0) != 0) 'archivedAt': isoInstant(DateTime.fromMillisecondsSinceEpoch(note.archivedAt!)),
      'workspace': inWorkspace,
      'organization': _orgOf(inWorkspace),
      'tags': (NoteMarks.of(note).tags.toList()..sort()),
      'source': note.sourceWord,
      if (shows.isNotEmpty) 'pictures': shows,
      if (links.isNotEmpty) 'files': links,
    };
    if (options.recordings && (note.recordingMs ?? 0) > 0) {
      final where = await source.recordingPath(note.id);
      if (where == null) {
        missing += 1;
      } else {
        // The phrases are only on the note read whole (`get`); the list's copy has none.
        final whole = await source.library.get(note.id);
        final at = 'recordings/${note.id}.wav';
        entries.add(GhostexEntry.file(at, where, modified: note.updatedAt));
        entry['recording'] = {
          'path': at,
          'ms': note.recordingMs,
          'segments': [
            for (final s in whole?.segments ?? const <Segment>[]) {'start': s.startMs, 'end': s.endMs, 'text': s.text},
          ],
        };
      }
    }
    notes.add(entry);
    if (isBookBody(note.body)) {
      notebooks.add({
        'id': note.id,
        'title': title,
        'journal': isJournalBody(note.body),
        'pages': [for (final chapter in chaptersOf(note.body)) chapter.title],
      });
    }
  }

  final keptPictures = <String>[], keptFiles = <String>[];
  for (final name in pictures.toList()..sort()) {
    final where = await source.picturePath(name);
    if (where == null) {
      missing += 1;
      continue;
    }
    keptPictures.add(name);
    entries.add(GhostexEntry.file('pictures/$name', where, modified: at.millisecondsSinceEpoch));
  }
  for (final name in files.toList()..sort()) {
    final where = await source.filePath(name);
    if (where == null) {
      missing += 1;
      continue;
    }
    keptFiles.add(name);
    entries.add(GhostexEntry.file('files/$name', where, modified: at.millisecondsSinceEpoch));
  }

  final manifest = <String, Object?>{
    'format': ghostexFormat,
    'version': ghostexVersion,
    'exportedAt': isoInstant(at),
    'app': app,
    'options': {'archived': options.archived, 'organizations': options.organizations, 'recordings': options.recordings},
    'notes': notes,
    'workspaces': [
      for (final w in spaces.list)
        if (usedSpaces.contains(w.id))
          {
            'id': w.id,
            'name': w.name,
            'folder': folderOf(w.id),
            'hue': w.hue,
            'parent': w.parent,
            'organization': w.org,
          },
    ],
    'notebooks': notebooks,
    'pictures': keptPictures,
    'files': keptFiles,
  };
  return (manifest: manifest, entries: entries, missing: missing);
}

/// Writes [entries] and [manifest] as a ZIP at [out], [manifest] first, telling [step] after each entry. Pure
/// `dart:io`: what the isolate runs.
Future<void> writeGhostexZip(String out, Map<String, Object?> manifest, List<GhostexEntry> entries, {void Function(int done)? step}) async {
  final zip = ZipFileEncoder();
  zip.create(out);
  try {
    final manifestFile = ArchiveFile.string('manifest.json', '${const JsonEncoder.withIndent('  ').convert(manifest)}\n')
      ..lastModTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    zip.addArchiveFile(manifestFile);
    var done = 0;
    for (final entry in entries) {
      final ArchiveFile file;
      final text = entry.text;
      if (text != null) {
        file = ArchiveFile.string(entry.name, text);
      } else {
        final input = InputFileStream(entry.path!);
        file = ArchiveFile.stream(entry.name, input)..compression = CompressionType.none;
      }
      file.lastModTime = entry.modified ~/ 1000;
      // The encoder closes the entry's file once it is written.
      zip.addArchiveFile(file);
      done += 1;
      step?.call(done);
    }
  } finally {
    await zip.close();
  }
}

/// [writeGhostexZip] on an isolate of its own, each entry written said to [port]. A function of its own, so the
/// closure sent holds these four and nothing of the caller's.
Future<void> _zipApart(String out, Map<String, Object?> manifest, List<GhostexEntry> entries, SendPort port) =>
    Isolate.run(() => writeGhostexZip(out, manifest, entries, step: port.send));

/// Exports everything [source] holds under [options] to the file at [out]: the ZIP written on an isolate of its
/// own, then sealed where a password was given ([seal], which a sealed export needs). [temp] is a folder for the
/// ZIP while it is sealed. Answers what it wrote.
Future<GhostexWritten> writeGhostex(GhostexSource source, GhostexOptions options, String out, {GhostexSeal? seal, String? temp, DateTime? at, String app = 'Ghost.md', void Function(GhostexProgress progress)? progress}) async {
  final now = at ?? DateTime.now();
  if (options.sealed && seal == null) throw StateError('This build cannot protect an export with a password.');
  progress?.call((done: 0, total: 0, step: 'Reading the notes'));
  final plan = await ghostexPlan(source, options, at: now, app: app);
  final total = plan.entries.length;
  final zipPath = options.sealed ? '${temp ?? File(out).parent.path}/.${now.microsecondsSinceEpoch}.ghostex.zip' : '$out.part';
  final heard = ReceivePort();
  final listening = heard.listen((done) {
    if (done is int) progress?.call((done: done, total: total, step: 'Writing'));
  });
  try {
    await _zipApart(zipPath, plan.manifest, plan.entries, heard.sendPort);
    if (options.sealed) {
      progress?.call((done: total, total: total, step: 'Protecting it with the password'));
      await seal!.seal(zipPath, out, options.password!);
    } else {
      await File(zipPath).rename(out);
    }
  } finally {
    await listening.cancel();
    heard.close();
    final left = File(zipPath);
    if (await left.exists()) await left.delete().then<void>((_) {}, onError: (Object _) {});
  }
  final notes = plan.manifest['notes']! as List;
  return GhostexWritten(
    path: out,
    notes: notes.length,
    pictures: (plan.manifest['pictures']! as List).length,
    files: (plan.manifest['files']! as List).length,
    recordings: notes.where((n) => (n as Map).containsKey('recording')).length,
    bytes: await File(out).length(),
    missing: plan.missing,
  );
}
