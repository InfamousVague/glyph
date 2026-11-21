// One MP4 of several voices from one MP4 a voice (lib/voice/mp4_merge.dart: how a call's recording is put together on
// Windows; Matt, 2026-11-21: "my friend is not able to see plugins added for recording calls on his pc"). The inputs
// are made by ffmpeg and by the Mac's own afconvert, so it runs where those are: on a machine without ffmpeg it is
// skipped.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/voice/mp4_merge.dart';
import 'package:ghost_messaging/voice/mp4_names.dart';

String? _which(String name) {
  for (final dir in ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin']) {
    if (File('$dir/$name').existsSync()) return '$dir/$name';
  }
  return null;
}

void main() {
  final ffmpeg = _which('ffmpeg'), ffprobe = _which('ffprobe');
  final skip = ffmpeg == null || ffprobe == null ? 'needs ffmpeg and ffprobe' : null;

  /// [seconds] of a tone at [hz], 48 kHz mono 16-bit.
  Uint8List tone(double hz, double seconds) {
    final n = (seconds * 48000).round();
    final out = ByteData(n * 2);
    for (var i = 0; i < n; i++) {
      out.setInt16(i * 2, (math.sin(2 * math.pi * hz * i / 48000) * 12000).round(), Endian.little);
    }
    return out.buffer.asUint8List();
  }

  /// The tone in [pcm], from how often it crosses zero.
  double pitch(Uint8List pcm) {
    final d = ByteData.sublistView(pcm);
    var crossings = 0;
    final n = pcm.length ~/ 2;
    for (var i = 1; i < n; i++) {
      if ((d.getInt16(i * 2 - 2, Endian.little) < 0) != (d.getInt16(i * 2, Endian.little) < 0)) crossings++;
    }
    return crossings / 2 / (n / 48000);
  }

  test('three files of one voice each become one file of three tracks, each still its own sound and length', () async {
    final dir = Directory.systemTemp.createTempSync('merge');
    addTearDown(() => dir.deleteSync(recursive: true));
    final voices = [(hz: 440.0, s: 3.0), (hz: 880.0, s: 2.0), (hz: 1320.0, s: 3.0)];
    final parts = <String>[];
    for (var i = 0; i < voices.length; i++) {
      final pcm = '${dir.path}/$i.pcm';
      File(pcm).writeAsBytesSync(tone(voices[i].hz, voices[i].s));
      final out = '${dir.path}/$i.m4a';
      // The second with its movie box first (a "fast start" file), the third by the Mac's own encoder where there
      // is one: the merge reads each as it finds it.
      final afconvert = i == 2 ? _which('afconvert') : null;
      final ProcessResult made;
      if (afconvert != null) {
        final wav = '${dir.path}/$i.wav';
        expect(Process.runSync(ffmpeg!, ['-v', 'error', '-f', 's16le', '-ar', '48000', '-ac', '1', '-i', pcm, wav]).exitCode, 0);
        made = Process.runSync(afconvert, ['-f', 'm4af', '-d', 'aac', '-b', '128000', wav, out]);
      } else {
        made = Process.runSync(ffmpeg!, ['-v', 'error', '-f', 's16le', '-ar', '48000', '-ac', '1', '-i', pcm, '-c:a', 'aac', '-b:a', '128k', if (i == 1) ...['-movflags', '+faststart'], out]);
      }
      expect(made.exitCode, 0, reason: '${made.stderr}');
      parts.add(out);
    }
    final out = '${dir.path}/call.mp4';
    await Mp4Merge.merge(parts, out);
    await Mp4Names.apply(out, ['Everyone', 'Maya', 'Sam']);

    final probe = Process.runSync(ffprobe!, ['-v', 'error', '-show_entries', 'stream=index,codec_name,duration:stream_tags=title', '-of', 'csv=p=0', out]);
    expect(probe.exitCode, 0, reason: '${probe.stderr}');
    final lines = '${probe.stdout}'.trim().split('\n');
    expect(lines, hasLength(3), reason: '${probe.stdout}');
    expect('${probe.stderr}', isEmpty);
    for (var i = 0; i < 3; i++) {
      final f = lines[i].split(',');
      expect(f[1], 'aac');
      expect(double.parse(f[2]), closeTo(voices[i].s, 0.1), reason: lines[i]);
      expect(lines[i], contains(['Everyone', 'Maya', 'Sam'][i]));
      // Each track decoded is still its own tone, the whole way through with no errors.
      final back = '${dir.path}/back$i.pcm';
      final dec = Process.runSync(ffmpeg!, ['-v', 'error', '-xerror', '-i', out, '-map', '0:$i', '-f', 's16le', '-ar', '48000', '-ac', '1', back]);
      expect(dec.exitCode, 0, reason: '${dec.stderr}');
      expect('${dec.stderr}', isEmpty);
      final pcm = File(back).readAsBytesSync();
      expect(pcm.length / 96000, closeTo(voices[i].s, 0.1));
      expect(pitch(pcm), closeTo(voices[i].hz, voices[i].hz * 0.02));
    }
  }, skip: skip);

  test('a file with no sound, or none at all, is said so and nothing is half made', () async {
    final dir = Directory.systemTemp.createTempSync('merge');
    addTearDown(() => dir.deleteSync(recursive: true));
    final junk = File('${dir.path}/junk.m4a')..writeAsBytesSync(List.filled(64, 7));
    await expectLater(Mp4Merge.merge([junk.path], '${dir.path}/out.mp4'), throwsA(isA<FormatException>()));
    await expectLater(Mp4Merge.merge(const [], '${dir.path}/out.mp4'), throwsA(isA<FormatException>()));
    expect(File('${dir.path}/out.mp4').existsSync(), isFalse);
  });
}
