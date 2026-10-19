/// The Opus packets out of a WebM file (docs/MEET.md, "On the device"): what the Meet bot's recording is, Chrome's
/// `MediaRecorder` writing Opus in WebM. Pure Dart, so the one reading of the container is tested here, and the
/// phone and the Mac are handed only packets to decode (tape.dart).
///
/// WebM is Matroska, which is EBML: each element an ID (a variable-length integer with its marker kept), a size (one
/// with its marker taken off; all ones is "unknown"), then its bytes. A recording made live has a Segment and
/// Clusters of unknown size, so the containers this reads are not skipped by their size but entered: the walk goes
/// on inside them as if the file were flat, which reads a known size and an unknown one the same way. Everything
/// else is skipped by its size.
///
/// Read: the first track whose codec is `A_OPUS` (its `OpusHead`, its channels, its codec delay), the timecode scale,
/// each cluster's timecode and each block of that track (`SimpleBlock`, or `Block` in a `BlockGroup`), with any of
/// the three lacings. A file cut short ends where it was cut: the packets before it are kept.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Something about a recording that would not read as Opus in WebM.
class WebmError implements Exception {
  const WebmError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The Opus track of a WebM recording.
class OpusTrack {
  OpusTrack({required this.channels, required this.preSkip, required this.head, required this.codecDelayNs, required this.seekPreRollNs, required this.packets, required this.atMs});

  /// 1 or 2, from the `OpusHead` (or the track's own Channels where it has none).
  final int channels;

  /// Samples at 48 kHz to drop from the start of the decoded sound (the `OpusHead`'s pre-skip).
  final int preSkip;

  /// The `OpusHead` itself (the track's CodecPrivate), which Android's decoder is given as its first buffer.
  final Uint8List head;
  final int codecDelayNs;
  final int seekPreRollNs;

  /// Each packet as it was in the file, in order.
  final List<Uint8List> packets;

  /// When each packet starts, in ms from the start of the file.
  final List<int> atMs;

  /// Every packet's samples at 48 kHz, from its TOC byte ([opusSamples]).
  int get samples => packets.fold(0, (sum, packet) => sum + opusSamples(packet));

  /// How long the sound is, in ms: its samples less the pre-skip.
  int get durationMs => ((samples - preSkip).clamp(0, 1 << 62) / 48).round();
}

// --- element ids ----------------------------------------------------------------------------------------------------

const int _segment = 0x18538067;
const int _info = 0x1549A966;
const int _timecodeScale = 0x2AD7B1;
const int _tracks = 0x1654AE6B;
const int _trackEntry = 0xAE;
const int _trackNumber = 0xD7;
const int _codecId = 0x86;
const int _codecPrivate = 0x63A2;
const int _codecDelay = 0x56AA;
const int _seekPreRoll = 0x56BB;
const int _audio = 0xE1;
const int _channels = 0x9F;
const int _cluster = 0x1F43B675;
const int _timecode = 0xE7;
const int _simpleBlock = 0xA3;
const int _blockGroup = 0xA0;
const int _block = 0xA1;

/// The containers that are entered rather than skipped (see the header).
const Set<int> _entered = {_segment, _info, _tracks, _trackEntry, _audio, _cluster, _blockGroup};

class _Track {
  int number = 0;
  String codec = '';
  Uint8List? private;
  int channels = 0;
  int codecDelay = 0;
  int seekPreRoll = 0;
}

/// The value of a variable-length integer at [at] and its length, or null where there is none to read. With
/// [marker] the length marker is kept (an element ID); without it, it is taken off (a size, a track number).
({int value, int length, bool unknown})? _vint(Uint8List bytes, int at, {bool marker = false, int most = 8}) {
  if (at >= bytes.length) return null;
  final first = bytes[at];
  if (first == 0) return null;
  var length = 1;
  while (length <= 8 && first & (0x80 >> (length - 1)) == 0) {
    length += 1;
  }
  if (length > most || at + length > bytes.length) return null;
  var value = marker ? first : first & (0xFF >> length);
  var ones = value == (0xFF >> length);
  for (var i = 1; i < length; i += 1) {
    value = (value << 8) | bytes[at + i];
    if (bytes[at + i] != 0xFF) ones = false;
  }
  return (value: value, length: length, unknown: !marker && ones);
}

int _uint(Uint8List bytes, int from, int to) {
  var value = 0;
  for (var i = from; i < to; i += 1) {
    value = (value << 8) | bytes[i];
  }
  return value;
}

/// The frames of a block's payload after its four-byte header ([at] is where the lacing's own bytes start).
List<Uint8List> _frames(Uint8List bytes, int at, int end, int lacing) {
  if (lacing == 0) return [Uint8List.sublistView(bytes, at, end)];
  if (at >= end) return const [];
  final count = bytes[at] + 1;
  var p = at + 1;
  final sizes = <int>[];
  switch (lacing) {
    case 1: // Xiph
      for (var i = 0; i < count - 1; i += 1) {
        var size = 0;
        while (p < end) {
          final b = bytes[p++];
          size += b;
          if (b != 255) break;
        }
        sizes.add(size);
      }
    case 2: // fixed
      final each = (end - p) ~/ count;
      for (var i = 0; i < count - 1; i += 1) {
        sizes.add(each);
      }
    default: // EBML
      final first = _vint(bytes, p);
      if (first == null) return const [];
      p += first.length;
      sizes.add(first.value);
      for (var i = 1; i < count - 1; i += 1) {
        final delta = _vint(bytes, p);
        if (delta == null) return const [];
        p += delta.length;
        final bias = (1 << (7 * delta.length - 1)) - 1;
        sizes.add(sizes.last + delta.value - bias);
      }
  }
  final frames = <Uint8List>[];
  for (final size in sizes) {
    if (size < 0 || p + size > end) return frames;
    frames.add(Uint8List.sublistView(bytes, p, p + size));
    p += size;
  }
  if (p <= end) frames.add(Uint8List.sublistView(bytes, p, end));
  return frames;
}

/// The Opus track of [webm], with every packet of it. Throws [WebmError] for a file that is not WebM or has no Opus.
OpusTrack readWebmOpus(Uint8List webm) {
  if (webm.length < 4 || _uint(webm, 0, 4) != 0x1A45DFA3) throw const WebmError('That recording is not WebM.');
  final tracks = <_Track>[];
  _Track? track;
  _Track? opus;
  var scale = 1000000;
  var clusterTime = 0;
  final packets = <Uint8List>[];
  final atMs = <int>[];
  var at = 0;
  while (at < webm.length) {
    final id = _vint(webm, at, marker: true, most: 4);
    if (id == null) break;
    final size = _vint(webm, at + id.length);
    if (size == null) break;
    final start = at + id.length + size.length;
    if (_entered.contains(id.value)) {
      if (id.value == _trackEntry) tracks.add(track = _Track());
      at = start;
      continue;
    }
    if (size.unknown) break;
    final end = start + size.value;
    if (end > webm.length) break;
    switch (id.value) {
      case _timecodeScale:
        scale = _uint(webm, start, end);
      case _trackNumber:
        track?.number = _uint(webm, start, end);
      case _codecId:
        track?.codec = ascii.decode(Uint8List.sublistView(webm, start, end), allowInvalid: true).replaceAll('\u0000', '');
      case _codecPrivate:
        track?.private = Uint8List.fromList(Uint8List.sublistView(webm, start, end));
      case _codecDelay:
        track?.codecDelay = _uint(webm, start, end);
      case _seekPreRoll:
        track?.seekPreRoll = _uint(webm, start, end);
      case _channels:
        track?.channels = _uint(webm, start, end);
      case _timecode:
        clusterTime = _uint(webm, start, end);
      case _simpleBlock || _block:
        opus ??= tracks.where((t) => t.codec == 'A_OPUS').firstOrNull;
        final number = _vint(webm, start, most: 4);
        if (opus == null || number == null || number.value != opus.number || start + number.length + 3 > end) break;
        final header = start + number.length;
        final relative = ByteData.sublistView(webm, header, header + 2).getInt16(0);
        final lacing = (webm[header + 2] >> 1) & 3;
        final ms = ((clusterTime + relative) * scale / 1000000).round();
        for (final frame in _frames(webm, header + 3, end, lacing)) {
          packets.add(frame);
          atMs.add(ms);
        }
    }
    at = end;
  }
  final found = opus ?? tracks.where((t) => t.codec == 'A_OPUS').firstOrNull;
  if (found == null) throw const WebmError('That recording has no Opus sound in it.');
  final head = found.private ?? Uint8List(0);
  final hasHead = head.length >= 19 && ascii.decode(head.sublist(0, 8), allowInvalid: true) == 'OpusHead';
  final channels = hasHead ? head[9] : (found.channels == 0 ? 1 : found.channels);
  final preSkip = hasHead ? head[10] | (head[11] << 8) : (found.codecDelay * 48 / 1000000).round();
  return OpusTrack(
    channels: channels,
    preSkip: preSkip,
    head: hasHead ? head : _opusHead(channels, preSkip),
    codecDelayNs: found.codecDelay != 0 ? found.codecDelay : (preSkip * 1000000000 / 48000).round(),
    seekPreRollNs: found.seekPreRoll != 0 ? found.seekPreRoll : 80000000,
    packets: packets,
    atMs: atMs,
  );
}

/// An `OpusHead` for a track that came without one: version 1, 48 kHz in, no gain, mapping family 0.
Uint8List _opusHead(int channels, int preSkip) => Uint8List.fromList([
      ...ascii.encode('OpusHead'), 1, channels, preSkip & 0xFF, preSkip >> 8, //
      0x80, 0xBB, 0, 0, 0, 0, 0,
    ]);

/// How many samples at 48 kHz an Opus packet holds, from its TOC byte (RFC 6716 §3.1): its frames, times each
/// frame's length by the configuration. 0 for an empty packet.
int opusSamples(Uint8List packet) {
  if (packet.isEmpty) return 0;
  final toc = packet[0];
  final config = toc >> 3;
  final per = config < 12
      ? const [480, 960, 1920, 2880][config & 3]
      : config < 16
          ? const [480, 960][config & 1]
          : const [120, 240, 480, 960][config & 3];
  final frames = switch (toc & 3) {
    0 => 1,
    1 || 2 => 2,
    _ => packet.length > 1 ? packet[1] & 0x3F : 0,
  };
  return per * frames;
}

/// The packets laid out for the device's decoder (tape.dart, the `ghost_md/meet_audio` channel): `GOP1`, the head's
/// length as four bytes big-endian, the head as JSON `{v, channels, preSkip, codecDelayNs, seekPreRollNs, packets,
/// samples, headBytes}`, the `OpusHead`, then each packet as its length (four bytes big-endian), its samples at
/// 48 kHz (four bytes big-endian) and its bytes.
Uint8List packedForDecoder(OpusTrack track) {
  final head = utf8.encode(jsonEncode({
    'v': 1,
    'channels': track.channels,
    'preSkip': track.preSkip,
    'codecDelayNs': track.codecDelayNs,
    'seekPreRollNs': track.seekPreRollNs,
    'packets': track.packets.length,
    'samples': track.samples,
    'headBytes': track.head.length,
  }));
  final out = BytesBuilder(copy: false)
    ..add(ascii.encode('GOP1'))
    ..add((ByteData(4)..setUint32(0, head.length)).buffer.asUint8List())
    ..add(head)
    ..add(track.head);
  for (final packet in track.packets) {
    out.add((ByteData(8)
          ..setUint32(0, packet.length)
          ..setUint32(4, opusSamples(packet)))
        .buffer
        .asUint8List());
    out.add(packet);
  }
  return out.takeBytes();
}
