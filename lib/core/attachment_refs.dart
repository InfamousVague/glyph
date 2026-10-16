/// A file in a note's words: a plain Markdown link to the file's name under `file/`, alone on its line, with its
/// size as the link's title. Only the words, and nothing that reaches a device (lib/files/ keeps the files).
///
///     [Lease 2026.pdf](file/5f0c2e9a-1b2c-4d3e-8f40-0a1b2c3d4e5f.pdf "2.4 MB")
///
/// The + beside the line writes one (A file, Scan a document), the editor draws the card under it
/// (lib/editor/media/attachments.dart), and any other app shows a link named for the file, with its size when the
/// pointer rests on it. It is the pictures' pattern with a folder of its own: a picture is `![caption](image/<name>)`
/// (lib/core/images.dart), a film `[![video 0:12](image/<poster>)](video/<name>)` (lib/core/video_refs.dart).
///
/// - **The words are the file's own name**, as the person saw it where it came from, with `[`, `]` and line breaks
///   taken out, since those would end the link. They are only words: renaming them renames nothing on disk.
/// - **The name after `file/` is the file's name in the app's keeping**: a version 4 UUID and the extension it came
///   with, in lower case (`5f0c2e9a-….pdf`), given when it arrives and never changed or reused, which is what sync
///   carries it by (`a-<ext>-<stem>`, lib/sync/notes.dart `fileId`). A file with no extension, or one that is not
///   letters and digits, is kept as `.bin`.
/// - **The title is its size as a person reads it** (`2.4 MB`, lib/core/backup.dart `sizeSaid`), written when the
///   file arrived, so a device the file has not reached yet can still say how big it is, and whether it will come
///   at all ([attachmentSyncLimit]). A link without one is read the same, its size unknown.
library;

import 'package:flutter/foundation.dart';

import 'backup.dart' show sizeSaid;
import 'item_syntax.dart' show jsTrim, lineWords;

/// The most a file may be to travel with its note to the account's other devices: the pictures' own limit (the
/// core's `kept/images.rs` `MAX_BYTES`, 25 MB). A larger one is kept on the device it was added on, and its card
/// says so everywhere else. The service's own limit for one sealed file is 64 MB (server/src/sync.rs
/// `RECORDING_LIMIT`), well past it.
const int attachmentSyncLimit = 25 * 1024 * 1024;

/// The most a file may be to be kept at all: past this the phone would be filling its storage with one note's file.
const int attachmentKeepLimit = 512 * 1024 * 1024;

const String _stem = r'[A-Za-z0-9_-]{1,64}';
const String _ext = r'[a-z0-9]{1,10}';

/// A file's reference in a body: the words, the name, and the title, as groups 1 to 3 (`FILE_REF`). Read it with
/// `allMatches`.
final RegExp attachmentRef = RegExp('\\[([^\\]\\n]*)\\]\\(file/($_stem\\.$_ext)(?: "([^"\\n]*)")?\\)');

/// The one form a file's line takes, past its quote's markers and its list lead.
final RegExp _lineForm = RegExp('^${attachmentRef.pattern}\$');

/// A name the app keeps a file under: a UUID-like stem and a lower-case extension.
final RegExp attachmentName = RegExp('^$_stem\\.$_ext\$');

final RegExp _unsafeWords = RegExp(r'[\[\]\r\n\t]+');
final RegExp _extOf = RegExp(r'\.([A-Za-z0-9]{1,10})$');

/// A file read from a line (`FileLine`).
@immutable
class AttachmentLine {
  const AttachmentLine({required this.name, required this.label, this.size});

  /// The file's name in the app's keeping, under `file/`.
  final String name;

  /// The words: the file's own name as it arrived.
  final String label;

  /// Its size as the title says it, or null where the line has none.
  final String? size;

  /// What kind of file it is, by the extension it was kept with.
  AttachmentKind get kind => attachmentKindOf(name);

  @override
  bool operator ==(Object other) => other is AttachmentLine && other.name == name && other.label == label && other.size == size;

  @override
  int get hashCode => Object.hash(name, label, size);

  @override
  String toString() => 'AttachmentLine($name, $label, $size)';
}

/// The file a line is, or null: a line whose words, past its quote's markers and its list lead, are exactly one
/// reference. Asked of every line of a note, so the seven letters a reference cannot be without are looked for
/// first.
AttachmentLine? attachmentOfLine(String text) {
  if (!text.contains('](file/')) return null;
  final found = _lineForm.firstMatch(lineWords(text));
  if (found == null) return null;
  return AttachmentLine(name: found.group(2)!, label: found.group(1) ?? '', size: found.group(3));
}

/// Every file a body names, in order, without repeats.
List<String> attachmentNames(String body) {
  if (!body.contains('](file/')) return const <String>[];
  final names = <String>{};
  for (final found in attachmentRef.allMatches(body)) {
    names.add(found.group(2)!);
  }
  return names.toList();
}

/// The words a file's link carries: its own name with what would end the link taken out, or "File" for none.
String attachmentWords(String original) {
  final words = jsTrim(original.replaceAll(_unsafeWords, ' ')).replaceAll(RegExp(r' {2,}'), ' ');
  return words.isEmpty ? 'File' : words;
}

/// The extension a file is kept with: its own, in lower case, where that is letters and digits; else `bin`.
String keptExtension(String original) {
  final found = _extOf.firstMatch(jsTrim(original));
  return found == null ? 'bin' : found.group(1)!.toLowerCase();
}

/// The line for a file: its words linked to its name, its size the title. Written on a line of its own by the +.
String attachmentMarkdown(String name, String original, {int? bytes}) =>
    '[${attachmentWords(original)}](file/$name${bytes == null ? '' : ' "${sizeSaid(bytes)}"'})';

final RegExp _sizeWords = RegExp(r'^(\d+(?:\.\d+)?) (bytes|KB|MB|GB|TB)$');

/// About how many bytes a title's size says ("2.4 MB" is 2,400,000), or null where it says none.
int? bytesOfSize(String? size) {
  if (size == null) return null;
  final found = _sizeWords.firstMatch(jsTrim(size));
  if (found == null) return null;
  final value = double.parse(found.group(1)!);
  const scale = <String, int>{'bytes': 1, 'KB': 1000, 'MB': 1000000, 'GB': 1000000000, 'TB': 1000000000000};
  return (value * scale[found.group(2)!]!).round();
}

/// The kinds of file a card draws, each with its word and its mark.
enum AttachmentKind { pdf, document, sheet, slides, archive, sound, video, picture, code, file }

final Map<String, AttachmentKind> _kinds = <String, AttachmentKind>{
  'pdf': AttachmentKind.pdf,
  for (final e in ['doc', 'docx', 'odt', 'rtf', 'txt', 'md', 'pages', 'epub']) e: AttachmentKind.document,
  for (final e in ['xls', 'xlsx', 'ods', 'csv', 'tsv', 'numbers']) e: AttachmentKind.sheet,
  for (final e in ['ppt', 'pptx', 'odp', 'key']) e: AttachmentKind.slides,
  for (final e in ['zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz']) e: AttachmentKind.archive,
  for (final e in ['mp3', 'm4a', 'wav', 'ogg', 'oga', 'flac', 'aac', 'opus', 'aiff']) e: AttachmentKind.sound,
  for (final e in ['mp4', 'm4v', 'mov', 'webm', 'mkv', 'avi', '3gp']) e: AttachmentKind.video,
  for (final e in ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', 'tif', 'tiff', 'svg']) e: AttachmentKind.picture,
  for (final e in ['json', 'js', 'ts', 'py', 'dart', 'html', 'htm', 'css', 'xml', 'kt', 'swift', 'rs', 'sh', 'yaml', 'yml', 'toml', 'sql', 'c', 'h', 'cpp', 'java', 'go', 'rb']) e: AttachmentKind.code,
};

/// What kind a file kept under [name] is, by its extension.
AttachmentKind attachmentKindOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? AttachmentKind.file : (_kinds[name.substring(dot + 1).toLowerCase()] ?? AttachmentKind.file);
}

/// A kind as a card says it: "PDF", "Spreadsheet".
String attachmentKindWord(AttachmentKind kind) => switch (kind) {
      AttachmentKind.pdf => 'PDF',
      AttachmentKind.document => 'Document',
      AttachmentKind.sheet => 'Spreadsheet',
      AttachmentKind.slides => 'Slides',
      AttachmentKind.archive => 'Archive',
      AttachmentKind.sound => 'Sound',
      AttachmentKind.video => 'Video',
      AttachmentKind.picture => 'Picture',
      AttachmentKind.code => 'Code',
      AttachmentKind.file => 'File',
    };

/// The media type a file is handed to another app as, by its extension: what Android's own table would say for
/// the common kinds, and `application/octet-stream` for the rest (the phone's half asks its own table first).
String attachmentMimeOf(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'md' => 'text/markdown',
    'csv' => 'text/csv',
    'html' || 'htm' => 'text/html',
    'json' => 'application/json',
    'zip' => 'application/zip',
    'doc' => 'application/msword',
    'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'wav' => 'audio/wav',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    _ => 'application/octet-stream',
  };
}
