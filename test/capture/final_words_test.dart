import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/final_words.dart';
import 'package:ghost_md/capture/markdown.dart';

/// The words a stopped decode added after the last phrase (lib/capture/final_words.dart), case for case with the
/// web's `capture/finalWords.test.ts`.

const heard = [Segment(text: 'Weekend plans include', startMs: 0, endMs: 900), Segment(text: 'packing', startMs: 900, endMs: 1500)];

void main() {
  group('the last words of a recording', () {
    test('keeps what the stop’s transcript says past the phrases, as one more phrase to the end of the recording', () {
      expect(withFinalWords(heard, 'Weekend plans include packing sunscreen and a hat.', 2600), [
        ...heard,
        const Segment(text: 'sunscreen and a hat.', startMs: 1500, endMs: 2600),
      ]);
    });

    test('matches the words however Whisper cased, accented and punctuated them the second time', () {
      const cafe = [Segment(text: 'The café, on Main', startMs: 0, endMs: 1000)];
      expect(withFinalWords(cafe, 'the cafe on main... opens at nine.', 1800).last, const Segment(text: 'opens at nine.', startMs: 1000, endMs: 1800));
    });

    test('takes the whole transcript when no phrase had arrived at all', () {
      expect(withFinalWords(const [], 'Call Sam.', 1200), [const Segment(text: 'Call Sam.', startMs: 0, endMs: 1200)]);
    });

    test('never ends the new phrase before it starts', () {
      expect(withFinalWords(heard, 'Weekend plans include packing sunscreen', 1000).last, const Segment(text: 'sunscreen', startMs: 1500, endMs: 1501));
    });

    test('leaves the phrases as they were heard when the transcript says something else, nothing more, or nothing', () {
      expect(withFinalWords(heard, 'Weekend plans exclude packing sunscreen', 2600), heard);
      expect(withFinalWords(heard, 'Weekend plans include packing.', 2600), heard);
      expect(withFinalWords(heard, 'Weekend plans', 2600), heard);
      expect(withFinalWords(heard, null, 2600), heard);
      expect(withFinalWords(heard, '   ', 2600), heard);
    });

    test('answers a copy, so the take’s own phrases are never the array that grows', () {
      final answered = withFinalWords(heard, null, 2600);
      expect(identical(answered, heard), false);
    });
  });
}
