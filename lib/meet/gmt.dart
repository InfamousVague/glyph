/// A Meet take, opened, as the service sealed it (docs/MEET.md): the pure half of reading one, with nothing here
/// that calls anything.
///
/// The service packs a take as `GMT1` before sealing it (server/src/meet.rs `pack`), framed as a mail's `GML1` is
/// (lib/mail/mail_note.dart `readMail`): four magic bytes, the head's length as four bytes big-endian, the head as
/// JSON, then the captions' bytes, then the audio's. The head is `{v, meeting, title, startedAt, endedAt, mime,
/// captionsBytes, audioBytes}`. The captions are NDJSON, a line `{at, speaker, text}` each, `at` in ms since the
/// recording started (meet/bot/lib/captions.mjs: when the phrase was first seen on screen); the audio is what the
/// bot's Chrome recorded, Opus in WebM.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';

/// One line of Meet's captions, as the bot read it.
@immutable
class CaptionLine {
  const CaptionLine({required this.at, required this.speaker, required this.text});

  /// When it was first seen, in ms since the recording started.
  final int at;

  /// The name Meet showed over it; empty where it showed none.
  final String speaker;
  final String text;

  @override
  bool operator ==(Object other) => other is CaptionLine && other.at == at && other.speaker == speaker && other.text == text;

  @override
  int get hashCode => Object.hash(at, speaker, text);

  @override
  String toString() => 'CaptionLine($at, $speaker, $text)';
}

/// A take as the service sealed it.
@immutable
class OpenedTake {
  const OpenedTake({required this.meeting, required this.title, required this.startedAt, required this.endedAt, required this.mime, required this.captions, required this.audio});

  /// The booking it was recorded for.
  final String meeting;

  /// The invite's title, trimmed; empty where it had none.
  final String title;

  /// When the recording started and ended, in ms; 0 where the head did not say.
  final int startedAt;
  final int endedAt;

  /// The audio's type: `audio/webm`.
  final String mime;
  final List<CaptionLine> captions;

  /// The recording's bytes; empty where the take carried none.
  final Uint8List audio;
}

/// Something about a sealed take that would not read.
class TakeError implements Exception {
  const TakeError(this.message);
  final String message;

  @override
  String toString() => message;
}

const List<int> _magic = [0x47, 0x4d, 0x54, 0x31];
const String _newer = 'That meeting was sealed by a newer Ghost.md. Update the app to file it.';

/// The take out of what the service sealed (`GMT1`, see the header). Throws [TakeError] for anything else.
OpenedTake readTake(Uint8List payload) {
  if (payload.length < 8) throw const TakeError('That meeting could not be read.');
  for (var i = 0; i < _magic.length; i += 1) {
    if (payload[i] != _magic[i]) throw const TakeError(_newer);
  }
  final length = ByteData.sublistView(payload).getUint32(4);
  if (8 + length > payload.length) throw const TakeError('That meeting could not be read.');
  final Object? head;
  try {
    head = jsonDecode(utf8.decode(Uint8List.sublistView(payload, 8, 8 + length), allowMalformed: true));
  } on FormatException {
    throw const TakeError('That meeting could not be read.');
  }
  if (head is! Map || (head['v'] != null && head['v'] != 1)) throw const TakeError(_newer);
  final said = head;
  int whole(String key) => said[key] is num ? (said[key] as num).toInt() : 0;
  String text(String key) => said[key] is String ? (said[key] as String).trim() : '';
  var at = 8 + length;
  final captionsBytes = whole('captionsBytes').clamp(0, payload.length - at);
  final captions = readCaptions(Uint8List.sublistView(payload, at, at + captionsBytes));
  at += captionsBytes;
  final audioBytes = said['audioBytes'] is num ? whole('audioBytes').clamp(0, payload.length - at) : payload.length - at;
  return OpenedTake(
    meeting: text('meeting'),
    title: text('title').replaceAll(RegExp(r'\s+'), ' '),
    startedAt: whole('startedAt'),
    endedAt: whole('endedAt'),
    mime: text('mime').isEmpty ? 'audio/webm' : text('mime').toLowerCase(),
    captions: captions,
    audio: Uint8List.sublistView(payload, at, at + audioBytes),
  );
}

/// The caption lines of an NDJSON part, in the order of their `at`: a line that is not one is passed over, as is one
/// with no words.
List<CaptionLine> readCaptions(Uint8List ndjson) {
  final lines = <CaptionLine>[];
  for (final raw in const LineSplitter().convert(utf8.decode(ndjson, allowMalformed: true))) {
    if (raw.trim().isEmpty) continue;
    Object? line;
    try {
      line = jsonDecode(raw);
    } on FormatException {
      continue;
    }
    if (line is! Map) continue;
    final text = line['text'] is String ? (line['text'] as String).replaceAll(RegExp(r'\s+'), ' ').trim() : '';
    if (text.isEmpty) continue;
    lines.add(CaptionLine(
      at: line['at'] is num ? (line['at'] as num).toInt() : 0,
      speaker: line['speaker'] is String ? (line['speaker'] as String).replaceAll(RegExp(r'\s+'), ' ').trim() : '',
      text: text,
    ));
  }
  // Stable: lines seen at the same moment keep the bot's order.
  final indexed = [for (final (i, line) in lines.indexed) (i, line)]..sort((a, b) => a.$2.at != b.$2.at ? a.$2.at.compareTo(b.$2.at) : a.$1.compareTo(b.$1));
  return List.unmodifiable([for (final (_, line) in indexed) line]);
}
