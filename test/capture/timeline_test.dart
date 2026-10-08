import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/markdown.dart';
import 'package:ghost_md/capture/take_types.dart';
import 'package:ghost_md/capture/timeline.dart';

/// A take on the tape of the note it is kept with (lib/capture/timeline.dart): what is appended, and where each
/// piece lands. Case for case with the web's `capture/timeline.test.ts`.
void main() {
  group('a take’s stretches on its note’s tape', () {
    test('move later by the tape the note already had, keeping what else they carry', () {
      const phrase = Segment(text: 'Call Sam.', startMs: 0, endMs: 5000);
      expect(shifted<Object>([phrase, const Span(startMs: 6000, endMs: 7000)], 12000), [
        const Segment(text: 'Call Sam.', startMs: 12000, endMs: 17000),
        const Span(startMs: 18000, endMs: 19000),
      ]);
      expect(shifted<Span>([], 500), isEmpty);
    });
  });

  group('which tape a take goes on the end of', () {
    test('is only a tape the continued note still has', () {
      expect(appendsTo(const TapedNote(recordingMs: 30000)), true);
      // A recording removed from the note leaves its file behind: the take starts the file afresh.
      expect(appendsTo(const TapedNote(recordingMs: 0)), false);
      expect(appendsTo(const TapedNote(recordingMs: null)), false);
      expect(appendsTo(const TapedNote()), false);
      expect(appendsTo(null), false);
    });
  });

  group('a take on its note’s tape', () {
    const take = TakeSpans(commandSpans: [Span(startMs: 0, endMs: 1800)], keywordSpans: [Span(startMs: 2000, endMs: 3500)]);
    const spoken = [Segment(text: 'Call Sam.', startMs: 2000, endMs: 3500)];

    test('puts every piece after the tape the continued note already had, and keeps its phrases before them', () {
      const before = [Segment(text: 'Eggs.', startMs: 0, endMs: 900)];
      final placed = onTape(const TapedNote(recordingMs: 30000, segments: before), take, spoken);
      expect(
        placed,
        OnTape(
          fromMs: 30000,
          prior: before,
          segments: [before[0], const Segment(text: 'Call Sam.', startMs: 32000, endMs: 33500)],
          skip: const [Span(startMs: 30000, endMs: 31800)],
          keywordAt: const [Span(startMs: 32000, endMs: 33500)],
        ),
      );
    });

    test('starts a new note’s tape, or one whose recording was removed, at nothing', () {
      for (final continued in [null, const TapedNote(recordingMs: 0, segments: null)]) {
        final placed = onTape(continued, take, spoken);
        expect(placed.fromMs, 0);
        expect(placed.prior, isEmpty);
        expect(placed.segments, spoken);
        expect(placed.skip, take.commandSpans);
        expect(placed.keywordAt, take.keywordSpans);
      }
    });
  });
}
