// A take, as the service seals it (lib/meet/gmt.dart, server/src/meet.rs `pack`): GMT1's head, its captions and its
// audio read back; a take from a newer service, or one that is not a take, said so.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/meet/gmt.dart';

import 'support.dart';

void main() {
  test('the head, the captions in order and the audio', () {
    final take = readTake(gmt1(captions: [
      {'at': 5200, 'speaker': 'Daniel', 'text': 'Thanks.  The pricing page is drafted.'},
      {'at': 1200, 'speaker': ' Sam Lee ', 'text': 'Good morning everyone.'},
      {'at': 1200, 'speaker': 'Sam Lee', 'text': 'Launch checklist first.'},
    ], audio: [9, 8, 7]));
    expect((take.meeting, take.title, take.startedAt, take.endedAt, take.mime), ('m1', 'Launch sync', 1792159200000, 1792161900000, 'audio/webm;codecs=opus'));
    expect(take.captions, const [
      CaptionLine(at: 1200, speaker: 'Sam Lee', text: 'Good morning everyone.'),
      CaptionLine(at: 1200, speaker: 'Sam Lee', text: 'Launch checklist first.'),
      CaptionLine(at: 5200, speaker: 'Daniel', text: 'Thanks. The pricing page is drafted.'),
    ]);
    expect(take.audio, [9, 8, 7]);
  });

  test('a null title is none, and lines that are not captions are passed over', () {
    final lines = utf8.encode('{"at":1,"speaker":"A","text":"one"}\nnot json\n[1,2]\n{"at":2,"speaker":"B","text":"   "}\n\n{"at":3,"text":"three"}\n');
    final head = utf8.encode(jsonEncode({'v': 1, 'meeting': 'm2', 'title': null, 'startedAt': 5, 'endedAt': 9, 'mime': 'audio/webm', 'captionsBytes': lines.length, 'audioBytes': 2}));
    final take = readTake(Uint8List.fromList([...'GMT1'.codeUnits, 0, 0, 0, head.length, ...head, ...lines, 1, 2]));
    expect(take.title, '');
    expect(take.captions, const [CaptionLine(at: 1, speaker: 'A', text: 'one'), CaptionLine(at: 3, speaker: '', text: 'three')]);
    expect(take.audio, [1, 2]);
  });

  test('no captions, and no audio', () {
    final take = readTake(gmt1(audio: const []));
    expect(take.captions, isEmpty);
    expect(take.audio, isEmpty);
  });

  test('a take of a newer shape, or not a take, is said so', () {
    expect(() => readTake(Uint8List.fromList('GML1....'.codeUnits)), throwsA(isA<TakeError>().having((e) => e.message, 'message', contains('newer'))));
    expect(() => readTake(gmt1(head: {'v': 2})), throwsA(isA<TakeError>().having((e) => e.message, 'message', contains('newer'))));
    expect(() => readTake(Uint8List.fromList([...'GMT1'.codeUnits, 0, 0, 1, 0, 1])), throwsA(isA<TakeError>()));
    expect(() => readTake(Uint8List(3)), throwsA(isA<TakeError>()));
  });
}
