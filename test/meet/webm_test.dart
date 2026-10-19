// The Opus packets out of a WebM recording (lib/meet/webm.dart): a real one made by ffmpeg (two tones, stereo, 20 ms
// frames, 1.5 s), and ones laid out here the way Chrome's MediaRecorder writes a live recording - a Segment and
// Clusters of unknown size - with each of the three lacings; and the packets laid out for the device's decoder.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/meet/webm.dart';

/// An element: its ID's bytes, its size (eight bytes, or "unknown"), its bytes.
List<int> el(List<int> id, List<int> body, {bool unknown = false}) {
  final size = ByteData(8)..setUint64(0, body.length);
  final sized = size.buffer.asUint8List()..[0] |= 0x01;
  return [...id, ...(unknown ? [0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF] : sized), ...body];
}

List<int> uint(int value, [int bytes = 1]) => [for (var i = bytes - 1; i >= 0; i -= 1) (value >> (8 * i)) & 0xFF];

/// An `OpusHead`: version 1, [channels], [preSkip], 48 kHz, no gain, family 0.
List<int> opusHead(int channels, int preSkip) => [...ascii.encode('OpusHead'), 1, channels, preSkip & 0xFF, preSkip >> 8, 0x80, 0xBB, 0, 0, 0, 0, 0];

/// A packet of one 20 ms CELT frame (config 31, code 0) with [fill] after its TOC.
List<int> packet(int fill, [int length = 5]) => [0xF8, for (var i = 1; i < length; i += 1) fill];

/// A live recording: EBML header, a Segment and its Clusters of unknown size, an Opus track [number], a video track
/// before it whose blocks are not read.
Uint8List live(List<List<int>> clusters, {int number = 2, int channels = 1, int preSkip = 312}) => Uint8List.fromList([
      ...el([0x1A, 0x45, 0xDF, 0xA3], el([0x42, 0x82], ascii.encode('webm'))),
      ...el([0x18, 0x53, 0x80, 0x67], [
        ...el([0x15, 0x49, 0xA9, 0x66], el([0x2A, 0xD7, 0xB1], uint(1000000, 3))),
        ...el([0x16, 0x54, 0xAE, 0x6B], [
          ...el([0xAE], [...el([0xD7], uint(1)), ...el([0x86], ascii.encode('V_VP8'))]),
          ...el([0xAE], [
            ...el([0xD7], uint(number)),
            ...el([0x86], ascii.encode('A_OPUS')),
            ...el([0x63, 0xA2], opusHead(channels, preSkip)),
            ...el([0xE1], [...el([0xB5], [0x47, 0x3B, 0x80, 0x00]), ...el([0x9F], uint(channels))]),
          ]),
        ]),
        for (final cluster in clusters) ...cluster,
      ], unknown: true),
    ]);

/// A cluster at [time] ms of unknown size, holding [blocks].
List<int> cluster(int time, List<List<int>> blocks) => el([0x1F, 0x43, 0xB6, 0x75], [...el([0xE7], uint(time, 2)), for (final b in blocks) ...b], unknown: true);

/// A SimpleBlock of track [track] at [relative] ms, lacing [lacing] (0 none, 1 Xiph, 2 fixed, 3 EBML), its bytes
/// after the flags as given.
List<int> block(int track, int relative, List<int> laced, {int lacing = 0}) => el([0xA3], [0x80 | track, ...uint(relative & 0xFFFF, 2), 0x80 | (lacing << 1), ...laced]);

void main() {
  test('a real recording: its track, its pre-skip and every packet, timed', () {
    final track = readWebmOpus(File('test/meet/fixtures/two_tones.webm').readAsBytesSync());
    expect(track.channels, 2);
    expect(track.preSkip, 312);
    expect(String.fromCharCodes(track.head.sublist(0, 8)), 'OpusHead');
    expect(track.packets, hasLength(76));
    expect(track.packets.every((p) => opusSamples(p) == 960), isTrue, reason: '20 ms frames, as asked of ffmpeg');
    expect(track.durationMs, closeTo(1500, 20));
    expect(track.atMs.first, 0);
    expect(track.atMs.last, closeTo(1500, 20));
    for (var i = 1; i < track.atMs.length; i += 1) {
      expect(track.atMs[i], greaterThanOrEqualTo(track.atMs[i - 1]));
    }
  });

  test('a live recording: a Segment and Clusters of unknown size are read through, another track left out', () {
    final webm = live([
      cluster(0, [block(2, 0, packet(1)), block(1, 0, [9, 9, 9]), block(2, 20, packet(2))]),
      cluster(40, [block(2, 0, packet(3)), block(2, 20, packet(4))]),
    ]);
    final track = readWebmOpus(webm);
    expect(track.channels, 1);
    expect([for (final p in track.packets) p[1]], [1, 2, 3, 4]);
    expect(track.atMs, [0, 20, 40, 60]);
    expect(track.samples, 4 * 960);
    expect(track.durationMs, ((4 * 960 - 312) / 48).round());
  });

  test('each lacing: Xiph, fixed and EBML', () {
    final a = packet(1, 3), b = packet(2, 300), c = packet(3, 4);
    final xiph = block(2, 0, [2, a.length, 255, b.length - 255, ...a, ...b, ...c], lacing: 1);
    final fixed = block(2, 20, [2, ...packet(4, 6), ...packet(5, 6), ...packet(6, 6)], lacing: 2);
    // EBML: the first size as a vint (3, one byte), the second as a signed difference (+297, two bytes, biased 8191).
    final difference = b.length - a.length + 8191;
    final ebml = block(2, 40, [2, 0x80 | a.length, 0x40 | (difference >> 8), difference & 0xFF, ...a, ...b, ...c], lacing: 3);
    final track = readWebmOpus(live([cluster(0, [xiph, fixed, ebml])]));
    expect([for (final p in track.packets) (p[1], p.length)], [(1, 3), (2, 300), (3, 4), (4, 6), (5, 6), (6, 6), (1, 3), (2, 300), (3, 4)]);
    expect(track.atMs, [0, 0, 0, 20, 20, 20, 40, 40, 40]);
  });

  test('a recording cut short keeps the packets before the cut', () {
    final whole = live([
      cluster(0, [block(2, 0, packet(1)), block(2, 20, packet(2))]),
    ]);
    final cut = Uint8List.sublistView(whole, 0, whole.length - 3);
    expect([for (final p in readWebmOpus(cut).packets) p[1]], [1]);
  });

  test('a file that is not WebM, or has no Opus, is said so', () {
    expect(() => readWebmOpus(Uint8List.fromList(ascii.encode('RIFF....WAVE'))), throwsA(isA<WebmError>()));
    final vorbis = Uint8List.fromList([
      ...el([0x1A, 0x45, 0xDF, 0xA3], el([0x42, 0x82], ascii.encode('webm'))),
      ...el([0x18, 0x53, 0x80, 0x67], el([0x16, 0x54, 0xAE, 0x6B], el([0xAE], [...el([0xD7], uint(1)), ...el([0x86], ascii.encode('A_VORBIS'))]))),
    ]);
    expect(() => readWebmOpus(vorbis), throwsA(isA<WebmError>().having((e) => e.message, 'message', contains('no Opus'))));
  });

  test('an Opus packet\'s samples, from its TOC byte', () {
    expect(opusSamples(Uint8List.fromList([0xF8])), 960, reason: 'CELT 20 ms, one frame');
    expect(opusSamples(Uint8List.fromList([0x08])), 960, reason: 'SILK 20 ms');
    expect(opusSamples(Uint8List.fromList([0x18])), 2880, reason: 'SILK 60 ms');
    expect(opusSamples(Uint8List.fromList([0x78])), 960, reason: 'hybrid 20 ms');
    expect(opusSamples(Uint8List.fromList([0xF9])), 1920, reason: 'two frames');
    expect(opusSamples(Uint8List.fromList([0xFB, 0x03])), 2880, reason: 'code 3: three frames');
    expect(opusSamples(Uint8List(0)), 0);
  });

  test('the packets are laid out for the device\'s decoder as GOP1', () {
    final track = readWebmOpus(live([
      cluster(0, [block(2, 0, packet(7, 4)), block(2, 20, packet(8, 2))]),
    ], channels: 2, preSkip: 100));
    final packed = packedForDecoder(track);
    final data = ByteData.sublistView(packed);
    expect(ascii.decode(packed.sublist(0, 4)), 'GOP1');
    final length = data.getUint32(4);
    final head = jsonDecode(utf8.decode(packed.sublist(8, 8 + length))) as Map;
    expect(head, {'v': 1, 'channels': 2, 'preSkip': 100, 'codecDelayNs': 2083333, 'seekPreRollNs': 80000000, 'packets': 2, 'samples': 1920, 'headBytes': 19});
    var at = 8 + length;
    expect(ascii.decode(packed.sublist(at, at + 8)), 'OpusHead');
    at += 19;
    expect((data.getUint32(at), data.getUint32(at + 4)), (4, 960));
    expect(packed.sublist(at + 8, at + 12), [0xF8, 7, 7, 7]);
    at += 12;
    expect((data.getUint32(at), data.getUint32(at + 4)), (2, 960));
    expect(at + 8 + 2, packed.length);
  });
}
