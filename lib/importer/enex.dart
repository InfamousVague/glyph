/// An Evernote export (`.enex`) read as it streams: one note at a time, so a 500 MB export is never in memory at
/// once. Pure Dart over the `xml` package's event parser.
///
/// The format (Evernote's evernote-export4.dtd): `<en-export>` holds `<note>`s; each has a `<title>`, its body as
/// ENML in a `<content>`'s CDATA, `<created>` and `<updated>` as `20231015T120000Z`, any number of `<tag>`s,
/// `<note-attributes>` (its `<source-url>`, its `<author>`), and `<resource>`s: the bytes in a
/// `<data encoding="base64">`, a `<mime>`, and `<resource-attributes>` with a `<file-name>`. The body names a resource by
/// the MD5 of its bytes (`<en-media hash="…">`), so each resource's MD5 is worked out as its bytes are decoded.
///
/// **Linear, whatever the export holds.** The `xml` package parses a stream by keeping what it could not finish
/// and parsing it again with the next piece, which for a body of many megabytes in a single CDATA would be read
/// again at every piece. So the text is handed to it in pieces that each end just before a `<` that opens markup
/// outside any CDATA or comment ([EnexPieces]): a CDATA always arrives whole, and is parsed once. A resource's
/// base64, which has no `<` in it, may be cut anywhere, and is decoded as it arrives.
///
/// [EnexReader] runs the reading in an isolate of its own and hands notes over one at a time, as they are asked
/// for, so the screen's isolate only writes them.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show Digest, md5;
import 'package:xml/xml_events.dart';

/// One resource of a note: its bytes, what they are, and the MD5 its body names it by.
class EnexResource {
  EnexResource({required this.data, required this.mime, required this.hash, this.fileName});
  final Uint8List data;
  final String mime;

  /// The MD5 of [data], as lower-case hex.
  final String hash;
  final String? fileName;
}

/// One note of an export.
class EnexNote {
  EnexNote({required this.title, required this.content, this.created, this.updated, this.tags = const [], this.resources = const [], this.sourceUrl, this.author});
  final String title;

  /// Its body, ENML.
  final String content;

  /// Milliseconds since the epoch; null where the export does not say.
  final int? created;
  final int? updated;
  final List<String> tags;
  final List<EnexResource> resources;
  final String? sourceUrl;
  final String? author;
}

/// An ENEX date, `20231015T120000Z`, in milliseconds since the epoch; null for one that is not.
int? enexDate(String? text) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z?$').firstMatch((text ?? '').trim());
  if (m == null) return null;
  int n(int i) => int.parse(m.group(i)!);
  return DateTime.utc(n(1), n(2), n(3), n(4), n(5), n(6)).millisecondsSinceEpoch;
}

/// The text of an export in pieces that each end just before markup outside a CDATA or a comment, so the event
/// parser never has to parse anything twice (see the header). A piece is let go once it is [piece] long; a text
/// with no markup in it (a resource's base64) once it is [longest] long, never inside an entity.
class EnexPieces extends StreamTransformerBase<String, String> {
  const EnexPieces({this.piece = 64 * 1024, this.longest = 4 * 1024 * 1024});

  final int piece;
  final int longest;

  @override
  Stream<String> bind(Stream<String> stream) async* {
    final pending = StringBuffer();
    // What has been looked at of `pending`, and the last place a piece may end.
    var looked = 0;
    var cut = -1;
    // 0 outside, 1 inside a CDATA, 2 inside a comment; what of `<![CDATA[` or `<!--` has been seen after a `<`.
    var inside = 0;
    var opening = '';
    var closing = 0;
    await for (final chunk in stream) {
      pending.write(chunk);
      for (var i = 0; i < chunk.length; i += 1) {
        final c = chunk[i];
        final at = looked + i;
        if (inside == 1) {
          // `]]>`
          if (c == ']') {
            closing = closing < 2 ? closing + 1 : 2;
          } else if (c == '>' && closing == 2) {
            inside = 0;
            closing = 0;
          } else {
            closing = 0;
          }
          continue;
        }
        if (inside == 2) {
          // `-->`
          if (c == '-') {
            closing = closing < 2 ? closing + 1 : 2;
          } else if (c == '>' && closing == 2) {
            inside = 0;
            closing = 0;
          } else {
            closing = 0;
          }
          continue;
        }
        if (opening.isNotEmpty) {
          opening += c;
          if (opening == '<![CDATA[') {
            inside = 1;
            opening = '';
          } else if (opening == '<!--') {
            inside = 2;
            opening = '';
          } else if (!'<![CDATA['.startsWith(opening) && !'<!--'.startsWith(opening)) {
            opening = '';
          }
          continue;
        }
        if (c == '<') {
          cut = at;
          opening = '<';
        }
      }
      looked += chunk.length;
      if (inside == 0 && opening.isEmpty) {
        if (cut > 0 && pending.length >= piece) {
          final all = pending.toString();
          yield all.substring(0, cut);
          pending
            ..clear()
            ..write(all.substring(cut));
          looked -= cut;
          cut = 0;
        } else if (cut <= 0 && pending.length >= longest) {
          // Words with no markup in them, many megabytes of them: let go, short of an entity cut in two.
          final all = pending.toString();
          var end = all.length;
          final amp = all.lastIndexOf('&');
          if (amp >= 0 && amp > all.length - 12 && !all.substring(amp).contains(';')) end = amp;
          yield all.substring(0, end);
          final rest = all.substring(end);
          pending
            ..clear()
            ..write(rest);
          looked = rest.length;
          cut = -1;
        }
      }
    }
    if (pending.isNotEmpty) yield pending.toString();
  }
}

class _ResourceBuilder {
  _ResourceBuilder() {
    _hasher = md5.startChunkedConversion(ChunkedConversionSink<Digest>.withCallback((digests) => _digest = digests.single));
  }

  final BytesBuilder _bytes = BytesBuilder(copy: false);
  late final ByteConversionSink _hasher;
  StringConversionSink? _decoder;
  Digest? _digest;
  String mime = 'application/octet-stream';
  String? fileName;

  /// `<data>` opened: its base64 decoded as it arrives, into the bytes and their MD5 at once.
  void startData() {
    _decoder ??= base64.decoder.startChunkedConversion(_ChunkSink((bytes) {
      _bytes.add(bytes);
      _hasher.add(bytes);
    }));
  }

  static final RegExp _blank = RegExp(r'\s+');

  void data(String text) {
    final clean = text.replaceAll(_blank, '');
    if (clean.isNotEmpty) _decoder?.add(clean);
  }

  void endData() {
    _decoder?.close();
  }

  EnexResource? build() {
    _hasher.close();
    final digest = _digest;
    if (digest == null) return null;
    final data = _bytes.takeBytes();
    if (data.isEmpty) return null;
    return EnexResource(data: data, mime: mime.trim(), hash: digest.toString(), fileName: fileName?.trim());
  }
}

class _ChunkSink implements ByteConversionSink {
  _ChunkSink(this._take);
  final void Function(List<int> bytes) _take;

  @override
  void add(List<int> chunk) => _take(chunk);

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) => _take(chunk.sublist(start, end));

  @override
  void close() {}
}

class _NoteBuilder {
  final StringBuffer title = StringBuffer();
  final StringBuffer content = StringBuffer();
  final StringBuffer created = StringBuffer();
  final StringBuffer updated = StringBuffer();
  final StringBuffer tag = StringBuffer();
  final StringBuffer source = StringBuffer();
  final StringBuffer author = StringBuffer();
  final List<String> tags = [];
  final List<EnexResource> resources = [];

  EnexNote build() => EnexNote(
        title: title.toString().trim(),
        content: content.toString(),
        created: enexDate(created.toString()),
        updated: enexDate(updated.toString()),
        tags: List.unmodifiable(tags),
        resources: List.unmodifiable(resources),
        sourceUrl: source.isEmpty ? null : source.toString().trim(),
        author: author.isEmpty ? null : author.toString().trim(),
      );
}

/// The notes of an export, as its [bytes] stream, one at a time.
Stream<EnexNote> readEnex(Stream<List<int>> bytes) async* {
  final stack = <String>[];
  _NoteBuilder? note;
  _ResourceBuilder? resource;
  final events = bytes.transform(const Utf8Decoder(allowMalformed: true)).transform(const EnexPieces()).toXmlEvents();
  await for (final batch in events) {
    final done = <EnexNote>[];
    for (final event in batch) {
      switch (event) {
        case XmlStartElementEvent(:final name, :final isSelfClosing):
          if (name == 'note') note = _NoteBuilder();
          if (name == 'resource' && note != null) resource = _ResourceBuilder();
          if (name == 'data' && resource != null && !isSelfClosing) resource.startData();
          if (!isSelfClosing) stack.add(name);
        case XmlEndElementEvent(:final name):
          if (stack.isNotEmpty) stack.removeLast();
          final building = note;
          if (name == 'data') resource?.endData();
          if (name == 'tag' && building != null) {
            final tag = building.tag.toString().trim();
            if (tag.isNotEmpty) building.tags.add(tag);
            building.tag.clear();
          }
          if (name == 'resource' && building != null && resource != null) {
            final made = resource.build();
            if (made != null) building.resources.add(made);
            resource = null;
          }
          if (name == 'note' && building != null) {
            done.add(building.build());
            note = null;
          }
        case XmlTextEvent(:final value):
          _text(stack, note, resource, value);
        case XmlCDATAEvent(:final value):
          _text(stack, note, resource, value);
        default:
          break;
      }
    }
    for (final each in done) {
      yield each;
    }
  }
}

void _text(List<String> stack, _NoteBuilder? note, _ResourceBuilder? resource, String value) {
  if (note == null || stack.isEmpty) return;
  final here = stack.last;
  final parent = stack.length >= 2 ? stack[stack.length - 2] : '';
  if (resource != null) {
    switch (here) {
      case 'data':
        resource.data(value);
      case 'mime' when parent == 'resource':
        resource.mime = value;
      case 'file-name':
        resource.fileName = (resource.fileName ?? '') + value;
    }
    return;
  }
  switch (here) {
    case 'title' when parent == 'note':
      note.title.write(value);
    case 'content' when parent == 'note':
      note.content.write(value);
    case 'created' when parent == 'note':
      note.created.write(value);
    case 'updated' when parent == 'note':
      note.updated.write(value);
    case 'tag' when parent == 'note':
      note.tag.write(value);
    case 'source-url':
      note.source.write(value);
    case 'author' when parent == 'note-attributes':
      note.author.write(value);
  }
}

/// Reads an export at [path] in an isolate of its own, a note at a time, as [next] asks: the next note, or null at
/// the end. [close] lets the isolate go; an error in the export is thrown from [next].
class EnexReader {
  EnexReader._(this._isolate, this._replies, this._ask);

  final Isolate _isolate;
  final StreamIterator<Object?> _replies;
  final SendPort _ask;
  bool _closed = false;

  static Future<EnexReader> open(String path) async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(_work, (path, port.sendPort), errorsAreFatal: true, onExit: port.sendPort);
    final replies = StreamIterator<Object?>(port);
    if (!await replies.moveNext() || replies.current is! SendPort) {
      port.close();
      throw StateError('The export could not be read.');
    }
    return EnexReader._(isolate, replies, replies.current as SendPort);
  }

  Future<EnexNote?> next() async {
    if (_closed) return null;
    _ask.send('next');
    if (!await _replies.moveNext()) return null;
    final said = _replies.current;
    if (said is EnexNote) return said;
    if (said is String) throw StateError(said);
    await close();
    return null;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _isolate.kill(priority: Isolate.immediate);
    await _replies.cancel();
  }

  static Future<void> _work((String, SendPort) start) async {
    final (path, reply) = start;
    final asks = ReceivePort();
    reply.send(asks.sendPort);
    final notes = StreamIterator<EnexNote>(readEnex(File(path).openRead()));
    await for (final _ in asks) {
      try {
        if (await notes.moveNext()) {
          reply.send(notes.current);
        } else {
          reply.send(null);
          asks.close();
        }
      } catch (failure) {
        reply.send(failure is FormatException ? 'The export is not one Ghost.md can read: ${failure.message}' : 'The export could not be read.');
        asks.close();
      }
    }
  }
}
