/// A shared meeting, for the page that reads it (docs/SHARING.md, "A meeting's recording"; Matt, 2026-10-29: "Update
/// the web version of the meeting transcripts to include the casette tape and the per user transcript so we can
/// listen along make a segmented toggle to switch between summary and transcript").
///
/// **What the words carry.** A meeting's share has a `meeting` beside its pages ([sharedMeeting]): how long the
/// recording is, the colour its cassette wears in the app ([tapeHue] of the note), when it was, who spoke, and the
/// turns, each a speaker's run of phrases with their times. The turns are the app's own reading of the meeting
/// (lib/tapes/transcript_words.dart): Whisper's phrases named by lib/meet/speakers.dart `phraseSpeakers` where the
/// phrases carry the meeting's words ([phrasesWhole]), a phrase each where nobody is named (a recording made on the
/// device); otherwise the paragraphs the note keeps under `## Transcript` or `## Captions`, timed where they say so
/// (`**Sam Lee (0:04):** …`) and plain where they do not. A share made by an older build has none, and the page reads
/// it as a note, as before.
///
/// **The recording** goes only where the person shares the meeting with "Include the recording" on (on unless turned
/// off: [ShareEntry.recording]), from the device that has it: a meeting's sound stays on the device that recorded it.
/// It is the recording as the app keeps it, the WAV (16 kHz mono, 16-bit): nothing in the app encodes sound, only
/// decodes it (lib/meet/tape.dart), so it is sent as it is kept, 115 MB an hour. It is too large for the share, so it is
/// an object of its own beside it on the service (server/src/shares.rs), sent a megabyte at a time ([audioChunk]),
/// each part sealed under the share's own key in a context naming the upload, the part and how many there are
/// ([audioPartContext]), so a part cannot be moved, dropped or swapped for another upload's without the page knowing.
/// Then a commit makes the upload the recording, and the words are written again naming it ([SharedAudio], in the
/// words as `meeting.audio`). The page reads the parts as they arrive and can play the first before the last is in.
///
/// **Not sent twice.** The share remembers what it sent ([SharedAudio.sent]: the file's length and the recording's), so
/// writing the share again after an edit sends the words alone; only a recording that grew (a take added) goes again,
/// as a new upload that replaces the old one whole.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../account/api.dart';
import '../account/crypto_api.dart';
import '../core/bytes.dart';
import '../core/note.dart';
import '../meet/speakers.dart' show captionIcons, phraseSpeakers;
import '../tapes/tape_art.dart' show tapeHue;
import '../tapes/transcript_words.dart' show captionsKept, phrasesWhole, writtenTranscript;

/// The context each part of a shared recording is sealed in, before its upload, its number and how many there are.
const String shareAudioContext = 'glyph/v1/share-audio';

/// Part [n] of [parts] of upload [upload]'s context (see the header).
String audioPartContext(String upload, int n, int parts) => '$shareAudioContext/$upload/$n/$parts';

/// How much of the recording a part carries before it is sealed: a megabyte, half a minute of the WAV.
const int audioChunk = 1 << 20;

/// What sealing adds to a part (a version byte, the IV and the tag), and the four bytes of length the service keeps
/// each part under.
const int _sealed = 1 + 12 + 16 + 4;

/// The most a share's recording may be, as the service keeps it (server/src/shares.rs `AUDIO_LIMIT`).
const int shareAudioLimit = 200 * 1024 * 1024;

/// Bytes of the WAV a second (16 kHz, one channel, two bytes a sample), for saying how long fits.
const int _wavPerSecond = 32000;

/// How many parts a recording of [bytes] is sent in.
int audioParts(int bytes) => (bytes + audioChunk - 1) ~/ audioChunk;

/// Whether a recording of [bytes] fits in a share.
bool audioFits(int bytes) => bytes > 0 && bytes + audioParts(bytes) * _sealed <= shareAudioLimit;

/// "1 h 49 min": the longest recording a share carries, in words.
String get audioLongest {
  final minutes = shareAudioLimit * 0.99 ~/ _wavPerSecond ~/ 60;
  return '${minutes ~/ 60} h ${minutes % 60} min';
}

/// The line for a recording past [audioFits].
String get audioTooLong => 'This recording is longer than a share can carry ($audioLongest at most), so the link goes without it.';

/// A meeting's recording on this device, read a part at a time.
class ShareRecording {
  const ShareRecording({required this.mime, required this.bytes, required this.read});

  /// What it is: `audio/wav`.
  final String mime;

  /// How long the file is.
  final int bytes;

  /// [length] bytes of it from [offset].
  final Future<Uint8List> Function(int offset, int length) read;
}

/// This device's recordings, as a share asks for them: a meeting's by its note's id, or null where this device has
/// none (it stayed on the device that recorded it, or was removed).
abstract interface class ShareRecordings {
  Future<ShareRecording?> recordingOf(String noteId);
}

/// A shared recording as the words name it, and what this device remembers of what it sent ([sent]).
class SharedAudio {
  const SharedAudio({required this.upload, required this.parts, required this.bytes, required this.mime, required this.ms, this.chunk = audioChunk, this.sent = ''});

  /// The upload's id, which every part's context names.
  final String upload;
  final int parts;

  /// The recording's length in bytes, before sealing.
  final int bytes;
  final String mime;

  /// The recording's length in ms.
  final int ms;

  /// How much of the recording each part carries, the last excepted.
  final int chunk;

  /// What was sent, by the file's length and the recording's ([recordingDigest]); kept on the device's side only.
  final String sent;

  /// What the page is told: everything but [sent].
  Map<String, Object?> toWords() => {'upload': upload, 'parts': parts, 'bytes': bytes, 'mime': mime, 'ms': ms, 'chunk': chunk};

  /// What the share's entry keeps.
  Map<String, Object?> toJson() => {...toWords(), 'sent': sent};

  /// A kept one back, or null where it is not one.
  static SharedAudio? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final upload = raw['upload'], parts = raw['parts'], bytes = raw['bytes'], mime = raw['mime'], ms = raw['ms'], chunk = raw['chunk'], sent = raw['sent'];
    if (upload is! String || parts is! int || bytes is! int || mime is! String || ms is! int) return null;
    return SharedAudio(upload: upload, parts: parts, bytes: bytes, mime: mime, ms: ms, chunk: chunk is int ? chunk : audioChunk, sent: sent is String ? sent : '');
  }
}

/// What a recording is remembered as having been sent by: its file's length and its own, which change together when a
/// take is added and not otherwise.
String recordingDigest(int bytes, int? ms) => '$bytes:${ms ?? 0}';

// ---- the turns ------------------------------------------------------------------------------------------------------

/// One phrase of a turn: when it began and ended, in ms into the recording (-1 for neither, where nothing says), and
/// its words.
typedef SharedPhrase = ({int startMs, int endMs, String text});

/// A speaker's run of phrases: [speaker] is an index into the meeting's speakers, or -1 for nobody named.
typedef SharedTurn = ({int speaker, List<SharedPhrase> phrases});

final RegExp _timedNamed = RegExp(r'^\*\*(.+?) \((\d+(?::\d{2}){1,2})\):\*\*\s*(.*)$', dotAll: true);
final RegExp _timedBare = RegExp(r'^\((\d+(?::\d{2}){1,2})\)\s*(.*)$', dotAll: true);
final RegExp _named = RegExp(r'^\*\*([^*\n]+?):\*\*\s*(.*)$', dotAll: true);

int _clockMs(String clock) => clock.split(':').fold(0, (total, part) => total * 60 + int.parse(part)) * 1000;

String _nameOf(String raw) {
  final name = raw.replaceAll(RegExp(r'[*\[\]()]'), '').replaceAll(RegExp(r'\s+'), ' ').trim().replaceFirst(RegExp(r':+$'), '');
  return captionIcons.contains(name) ? '' : name;
}

/// A meeting's speakers and turns (see the header): its phrases named where they carry its words, else its written
/// paragraphs.
({List<String> speakers, List<SharedTurn> turns}) meetingTurns(Note note) {
  final speakers = <String>[];
  int indexOf(String? name) {
    if (name == null || name.isEmpty) return -1;
    final at = speakers.indexOf(name);
    if (at >= 0) return at;
    speakers.add(name);
    return speakers.length - 1;
  }

  final turns = <SharedTurn>[];
  final segments = [for (final s in note.segments ?? const <Segment>[]) if (s.text.trim().isNotEmpty) s];
  final written = writtenTranscript(note.body) ?? captionsKept(note.body);
  if (phrasesWhole(segments, written)) {
    final named = phraseSpeakers(segments, note.body);
    final anyone = named.any((name) => name != null && name.isNotEmpty);
    for (final (i, segment) in segments.indexed) {
      final speaker = indexOf(i < named.length ? named[i] : null);
      final phrase = (startMs: segment.startMs, endMs: segment.endMs, text: segment.text.replaceAll(RegExp(r'\s+'), ' ').trim());
      // Named, a speaker's run is one turn; with nobody named, a phrase each, as the app lights them.
      if (anyone && turns.isNotEmpty && turns.last.speaker == speaker) {
        turns.last.phrases.add(phrase);
      } else {
        turns.add((speaker: speaker, phrases: [phrase]));
      }
    }
    return (speakers: speakers, turns: turns);
  }
  // The paragraphs: a timed one runs to the next one's time, the last to the recording's end; one with no time after a
  // timed one is more words of it.
  final length = note.recordingMs ?? 0;
  final read = <({int speaker, int? startMs, String text})>[];
  for (final paragraph in written ?? const <String>[]) {
    final line = paragraph.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (line.isEmpty) continue;
    if (_timedNamed.firstMatch(line) case final m?) {
      read.add((speaker: indexOf(_nameOf(m.group(1)!)), startMs: _clockMs(m.group(2)!), text: m.group(3)!.trim()));
    } else if (_timedBare.firstMatch(line) case final m?) {
      read.add((speaker: -1, startMs: _clockMs(m.group(1)!), text: m.group(2)!.trim()));
    } else if (_named.firstMatch(line) case final m?) {
      read.add((speaker: indexOf(_nameOf(m.group(1)!)), startMs: null, text: m.group(2)!.trim()));
    } else if (read.isNotEmpty && read.last.startMs != null) {
      final was = read.removeLast();
      read.add((speaker: was.speaker, startMs: was.startMs, text: '${was.text} $line'.trim()));
    } else {
      read.add((speaker: -1, startMs: null, text: line));
    }
  }
  for (final (i, turn) in read.indexed) {
    final start = turn.startMs;
    int end = -1;
    if (start != null) {
      final next = read.skip(i + 1).map((t) => t.startMs).whereType<int>().firstOrNull;
      end = math.max(start, next ?? math.max(length, start));
    }
    if (turn.text.isEmpty && start == null) continue;
    turns.add((speaker: turn.speaker, phrases: [(startMs: start ?? -1, endMs: end, text: turn.text)]));
  }
  return (speakers: speakers, turns: turns);
}

/// The `meeting` a meeting's share carries (see the header), [audio] naming its recording where one was sent. [at] is
/// when the meeting was, in ms.
Map<String, Object?> sharedMeeting(Note note, {required int at, SharedAudio? audio}) {
  final read = meetingTurns(note);
  return {
    'ms': note.recordingMs ?? 0,
    'hue': tapeHue(note.id),
    'at': at,
    'speakers': read.speakers,
    'turns': [
      for (final turn in read.turns)
        {
          's': turn.speaker,
          'p': [for (final p in turn.phrases) [p.startMs, p.endMs, p.text]],
        },
    ],
    if (audio != null) 'audio': audio.toWords(),
  };
}

// ---- sending it -----------------------------------------------------------------------------------------------------

/// Sends [recording] as share [shareId]'s, sealed under its [key] (see the header), and answers what the words are to
/// name. [progress] is told the share of it sent, after each part; [wanted] is asked before each, and a recording no
/// longer wanted (the switch turned off, the share stopped) stops there, with what was sent of it taken down. A part
/// that does not go is tried twice more where the service did not answer or failed; a refusal is thrown as it came.
Future<SharedAudio?> sendShareAudio({
  required Api api,
  required String token,
  required AccountCrypto crypto,
  required String shareId,
  required String key,
  required ShareRecording recording,
  required int ms,
  void Function(double sent)? progress,
  bool Function()? wanted,
}) async {
  if (!audioFits(recording.bytes)) throw ApiError(413, audioTooLong);
  final sealKey = await crypto.importSealKey(fromBase64Url(key));
  final upload = toBase64Url(crypto.randomBytes(16));
  final parts = audioParts(recording.bytes);
  for (var n = 0; n < parts; n += 1) {
    if (wanted != null && !wanted()) {
      await api.call('DELETE', 'shares/$shareId/audio', token: token).then<void>((_) {}, onError: (Object _) {});
      return null;
    }
    final at = n * audioChunk;
    final plain = await recording.read(at, math.min(audioChunk, recording.bytes - at));
    final sealed = await crypto.sealBytes(sealKey, plain, audioPartContext(upload, n, parts));
    for (var attempt = 1;; attempt += 1) {
      try {
        await api.call('PUT', 'shares/$shareId/audio/$upload/$n', token: token, bytes: sealed, timeout: const Duration(minutes: 2));
        break;
      } on ApiError catch (failure) {
        if (attempt >= 3 || (failure.status != 0 && failure.status < 500)) rethrow;
      }
    }
    progress?.call((n + 1) / parts);
  }
  await api.call('POST', 'shares/$shareId/audio', token: token, body: {'upload': upload, 'parts': parts}, timeout: const Duration(minutes: 2));
  return SharedAudio(upload: upload, parts: parts, bytes: recording.bytes, mime: recording.mime, ms: ms, sent: recordingDigest(recording.bytes, ms));
}

/// A shared recording read back, as the page reads it: the parts out of what the service answers ([framed]: each part
/// as its length, four bytes big-endian, then its bytes), opened under [key] and joined. For the tests, and for anyone
/// checking what a share carries.
Future<Uint8List> openShareAudio(AccountCrypto crypto, Uint8List framed, String key, SharedAudio audio) async {
  final sealKey = await crypto.importSealKey(fromBase64Url(key));
  final out = BytesBuilder(copy: false);
  final view = ByteData.sublistView(framed);
  var at = 0;
  for (var n = 0; n < audio.parts; n += 1) {
    if (at + 4 > framed.length) throw const FormatException('The recording stops short.');
    final length = view.getUint32(at);
    if (at + 4 + length > framed.length) throw const FormatException('The recording stops short.');
    out.add(await crypto.openBytes(sealKey, Uint8List.sublistView(framed, at + 4, at + 4 + length), audioPartContext(audio.upload, n, audio.parts)));
    at += 4 + length;
  }
  if (at != framed.length) throw const FormatException('The recording has more parts than its share names.');
  return out.takeBytes();
}
