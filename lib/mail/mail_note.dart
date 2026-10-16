/// A mail, opened, as the note it becomes (docs/MAIL.md): the pure half of email to a note, with nothing here that
/// calls anything.
///
/// The service sealed the mail on arrival as `GML1` (server/src/mail/message.rs): four magic bytes, the head's length
/// as four bytes big-endian, the head as JSON, then each file's bytes in the order the head lists them. The head is
/// `{v, subject, from, to, date, body, files: [{name, type, size, cid}]}`, the body already Markdown.
///
/// The note is plain Markdown, as every note is:
///
/// ```markdown
/// ---
/// from: "Sam Lee <sam@example.com>"
/// ---
/// # Café plans
///
/// The body, with each picture the mail showed inline at its place.
///
/// ![door.png](image/5f0c…-….png)
///
/// Came with it, not kept: menu.pdf (9 bytes).
/// ```
///
/// Pictures (JPEG, PNG, GIF, WebP) are kept as pictures, in the library's picture folder under a name made from the
/// mail's id, so filing the same mail twice writes the same files. Any other file is handed to [MailFileKeeper]: the
/// one here ([notKeptLine]) only names it, until general attachments land (feat/files), when the keeper is that
/// store's and answers the Markdown that links to the kept file.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/bytes.dart';
import '../core/front_matter.dart' show quotedTitle;

/// One file a mail carried.
@immutable
class MailFile {
  const MailFile({required this.name, required this.type, required this.bytes, this.cid});

  /// What the sender called it, without any path.
  final String name;

  /// Its MIME type, lower case: `image/png`.
  final String type;
  final Uint8List bytes;

  /// The `Content-ID` an HTML body showed it by (`cid:` in its `<img>`), without the angle brackets.
  final String? cid;

  /// Whether the library keeps it as a picture: what the core keeps under a picture's name.
  bool get isPicture => pictureExtension(type) != null;
}

/// A mail as the service sealed it.
@immutable
class OpenedMail {
  const OpenedMail({required this.subject, required this.from, required this.to, required this.date, required this.body, required this.files});
  final String subject;

  /// `Name <address>`, or the address alone.
  final String from;

  /// The address it was sent to.
  final String to;

  /// When it was sent, in ms; when it came, where it said nothing.
  final int date;

  /// Markdown.
  final String body;
  final List<MailFile> files;
}

/// Something about a sealed mail that would not read.
class MailError implements Exception {
  const MailError(this.message);
  final String message;

  @override
  String toString() => message;
}

const List<int> _magic = [0x47, 0x4d, 0x4c, 0x31];

/// The mail out of what the service sealed (`GML1`, see the header). Throws [MailError] for anything else.
OpenedMail readMail(Uint8List payload) {
  if (payload.length < 8) throw const MailError('That mail could not be read.');
  for (var i = 0; i < _magic.length; i += 1) {
    if (payload[i] != _magic[i]) throw const MailError('That mail was sealed by a newer Ghost.md. Update the app to file it.');
  }
  final length = ByteData.sublistView(payload).getUint32(4);
  if (8 + length > payload.length) throw const MailError('That mail could not be read.');
  final head = jsonDecode(utf8.decode(Uint8List.sublistView(payload, 8, 8 + length), allowMalformed: true));
  if (head is! Map || head['v'] != 1) throw const MailError('That mail was sealed by a newer Ghost.md. Update the app to file it.');
  String text(String key) => head[key] is String ? head[key] as String : '';
  final files = <MailFile>[];
  var at = 8 + length;
  for (final file in head['files'] is List ? head['files'] as List : const <Object?>[]) {
    if (file is! Map) continue;
    final size = file['size'] is int ? file['size'] as int : 0;
    if (size <= 0 || at + size > payload.length) break;
    files.add(MailFile(
      name: file['name'] is String ? file['name'] as String : 'file',
      type: file['type'] is String ? (file['type'] as String).toLowerCase() : 'application/octet-stream',
      bytes: Uint8List.fromList(Uint8List.sublistView(payload, at, at + size)),
      cid: file['cid'] is String ? file['cid'] as String : null,
    ));
    at += size;
  }
  return OpenedMail(
    subject: text('subject').trim(),
    from: text('from').trim(),
    to: text('to'),
    date: head['date'] is num ? (head['date'] as num).toInt() : 0,
    body: text('body'),
    files: List.unmodifiable(files),
  );
}

/// The extension a picture of [type] is kept under, or null for a file the library does not keep as a picture.
String? pictureExtension(String type) => switch (type) {
      'image/jpeg' || 'image/jpg' => 'jpg',
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      _ => null,
    };

/// Sixteen bytes from a mail's id (the service's are sixteen random bytes, base64url), and from anything else a
/// spread of its characters, so a name made from it is the same each time.
Uint8List _seed(String mailId) {
  try {
    final bytes = fromBase64Url(mailId);
    if (bytes.length == 16) return bytes;
  } catch (_) {
    // Not the service's shape: spread below.
  }
  final out = Uint8List(16);
  final units = utf8.encode(mailId);
  for (var i = 0; i < units.length; i += 1) {
    out[i % 16] = (out[i % 16] * 31 + units[i]) & 0xff;
  }
  return out;
}

String _uuid(Uint8List bytes) {
  final b = Uint8List.fromList(bytes);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = [for (final byte in b) byte.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// The id of the note a mail becomes: a UUID v4 made from the mail's id, so a device that files it twice (a pass cut
/// short before the service heard it was filed, or two devices at once) writes one note, not two.
String mailNoteId(String mailId) => _uuid(_seed(mailId));

/// The name the [index]th file of a mail is kept under as a picture: `<uuid>.<ext>`, made from the mail's id.
String mailPictureName(String mailId, int index, String extension) {
  final seed = _seed(mailId);
  seed[15] ^= 0xa5;
  seed[14] ^= (index + 1) & 0xff;
  seed[13] ^= ((index + 1) >> 8) & 0xff;
  return '${_uuid(seed)}.$extension';
}

/// What a note says of a file it does not keep, and how a keeper of other files is asked (see the header).
typedef MailFileKeeper = Future<String> Function(MailFile file, int index);

/// The keeper until general attachments land: the file named, with its size, and said plainly not to be kept.
Future<String> notKeptLine(MailFile file, int index) async => 'Came with it, not kept: ${file.name} (${sizeWords(file.bytes.length)}).';

/// A size as a person says it.
String sizeWords(int bytes) {
  if (bytes < 1000) return bytes == 1 ? '1 byte' : '$bytes bytes';
  if (bytes < 1000000) return '${(bytes / 1000).round()} KB';
  return '${(bytes / 1000000).toStringAsFixed(1)} MB';
}

/// The name part of `Name <address>`, or the address.
String senderName(String from) {
  final at = from.indexOf('<');
  final name = at > 0 ? from.substring(0, at).trim() : from.trim();
  return name.replaceAll('"', '');
}

/// The note's title: the subject, or who sent it where it has none.
String mailTitle(OpenedMail mail) {
  final subject = mail.subject.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (subject.isNotEmpty) return subject;
  final who = senderName(mail.from);
  return who.isEmpty ? 'A mail' : 'A mail from $who';
}

/// The note [mail] becomes, with [pictures] the names its pictures were kept under, by their place in its files, and
/// [others] the lines its other files are said in, in the same order (see the header).
String mailNoteBody(OpenedMail mail, {Map<int, String> pictures = const {}, List<String> others = const []}) {
  var body = mail.body.replaceAll('\r\n', '\n').trim();
  final shown = <int>{};
  // A picture the HTML showed in place is drawn in place; the rest go under the words.
  for (final MapEntry(key: index, value: name) in pictures.entries) {
    final cid = mail.files[index].cid;
    if (cid == null || cid.isEmpty) continue;
    final ref = '(cid:$cid)';
    if (body.contains(ref)) {
      body = body.split(ref).join('(image/$name)');
      shown.add(index);
    }
  }
  // A `cid:` the mail did not carry, or one whose file is not a picture, would draw nothing: its alt text stays.
  body = body.replaceAllMapped(RegExp(r'!\[([^\]]*)\]\(cid:[^)]*\)'), (m) => (m.group(1) ?? '').trim());
  final out = StringBuffer();
  if (mail.from.isNotEmpty) out.write('---\nfrom: ${quotedTitle(mail.from, '')}\n---\n');
  out.write('# ${mailTitle(mail)}\n');
  if (body.isNotEmpty) out.write('\n$body\n');
  for (final MapEntry(key: index, value: name) in pictures.entries) {
    if (shown.contains(index)) continue;
    out.write('\n![${mail.files[index].name.replaceAll(RegExp(r'[\[\]]'), '')}](image/$name)\n');
  }
  for (final line in others) {
    out.write('\n$line\n');
  }
  return out.toString();
}
