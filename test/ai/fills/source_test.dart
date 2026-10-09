// Where an answer came from (lib/ai/fills/source.dart). A port of src/app/ai/fills/source.test.ts, case for case. The
// web's own answers for a corpus are held in fills_landing_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/fills/shape.dart';
import 'package:ghost_md/ai/fills/source.dart';
import 'package:ghost_md/core/blanks.dart';

/// Whether [answer] to the last blank of [text] reads as from this note.
bool fromNote(String text, String answer, [String? scope]) {
  final blank = blanksIn(text).last;
  return fromThisNote(answer, blank, shapeOf(blank, text).shape, text, scope ?? text);
}

void main() {
  group('where an answer came from', () {
    test('is this note when the answer stands in a sentence beside what was asked', () {
      expect(fromNote('Sam said she would bring the charger and the dog food. I am booking the ferry.\n\nWho brings the charger? {?}', 'Sam'), isTrue);
    });

    test('is memory when the words are in the note but not beside the question', () {
      expect(fromNote('We watched France play in Qatar.\n\nThe 2022 World Cup was won by {?}', 'France'), isFalse);
    });

    test('is memory for an answer that only echoes its own line, or stands beside the question without answering it', () {
      expect(fromNote('The capital of Australia is {?}', 'Australia'), isFalse);
      expect(fromNote('We watched the World Cup final in 2022: France against Argentina.\n\nThe 2022 World Cup was won by {?}', 'France'), isFalse);
      expect(fromNote('Argentina won the 2022 World Cup on penalties.\n\nThe 2022 World Cup was won by {?}', 'Argentina'), isTrue);
    });

    test('is memory for words the note lacks, and for an answer with no content words', () {
      expect(fromNote('# Kitchen tap\n- [x] Found the leak under the sink\n- [ ] {?the next step}', 'Turn off the water and fit the new washer'), isFalse);
      expect(fromNote('Is it done? {?}', 'no'), isFalse);
    });

    test('reads a summary from its scope', () {
      const note = '# Standup\n\nPriya: export bug fixed, in review, lands Tuesday. Tom: blocked on staging keys. We moved the launch to the 24th.\n\nIn one line: {?summary}';
      expect(fromNote(note, 'Priya fixed an export bug in review for Tuesday, Tom is blocked on staging keys, and the launch moved to the 24th.'), isTrue);
    });

    test('never lets an earlier fill vouch for a later one', () {
      const note = 'Who brings the charger? ??Sam??(Qwen3.5 4B from memory, 2026-09-28)\n\nWho brings the charger this time? {?}';
      expect(noteForSource(note), isNot(contains('Sam')));
      expect(fromNote(note, 'Sam'), isFalse);
    });

    test('compares words lower-cased, folded, a trailing s aside, numbers whole', () {
      expect(contentWords('The Cafés, 1,200 bags and a Dog'), ['cafe', '1200', 'bag', 'dog']);
    });
  });
}
