// Where an answer goes in the note (lib/ai/fills/edits.dart). A port of src/app/ai/fills/edits.test.ts, case for case.
// The web's own answers for a corpus are held in fills_landing_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/fills/edits.dart';
import 'package:ghost_md/ai/fills/shape.dart';
import 'package:ghost_md/core/blanks.dart';

const String model = 'Qwen3.5 4B';
const String date = '2026-09-28';
const FillSource memory = FillSource.memory();

/// The note after the last blank of [text] is answered with [words].
String landed(String text, List<String> words, [FillSource source = memory]) {
  final blank = blanksIn(text).last;
  final answer = Landing(from: blank.from, to: blank.to, question: blank.question, info: shapeOf(blank, text), words: words, model: model, date: date, source: source);
  return applyChanges(text, landingChanges(text, answer));
}

void main() {
  group('where an answer goes', () {
    test('replaces a blank in a sentence with the mark and its source', () {
      expect(
        landed('# Tokyo trip\n\nFlights are cheapest to Tokyo on {?what day / time?}', ['midweek']),
        '# Tokyo trip\n\nFlights are cheapest to Tokyo on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)',
      );
      expect(
        landed('# Weather\n\nLisbon tomorrow: {?weather}', ['Rain showers, 19 to 25 °C'], const FillSource.web('Open-Meteo')),
        contains('??Rain showers, 19 to 25 °C??(Qwen3.5 4B from Open-Meteo, 2026-09-28. Asked: weather)'),
      );
    });

    test('lands items one a line with the list’s own lead, each with its place', () {
      expect(
        landed('## Japan packing\n- Passport\n- Plug adapter\n- {?three more things}', ['Rail pass', 'Walking shoes', 'Cash in yen']),
        [
          '## Japan packing',
          '- Passport',
          '- Plug adapter',
          '- ??Rail pass??(Qwen3.5 4B from memory, 2026-09-28. Asked: three more things. 1 of 3)',
          '- ??Walking shoes??(Qwen3.5 4B from memory, 2026-09-28. Asked: three more things. 2 of 3)',
          '- ??Cash in yen??(Qwen3.5 4B from memory, 2026-09-28. Asked: three more things. 3 of 3)',
        ].join('\n'),
      );
      expect(landed('# Trip\n\n1. Passport\n2. {?more}', ['Rail pass', 'Cash']), contains('2. ??Rail pass??(Qwen3.5 4B from memory, 2026-09-28. Asked: more. 1 of 2)\n3. ??Cash??'));
      expect(
        landed('# Tap\n- [x] Found it\n- [ ] {?the next step}', ['Fit the washer']),
        '# Tap\n- [x] Found it\n- [ ] ??Fit the washer??(Qwen3.5 4B from memory, 2026-09-28. Asked: the next step)',
      );
    });

    test('never writes a mark into a title', () {
      const words = r' Book the cabin for the second week of October. Ferry once Sam confirms dates with her brother. Deposit $200 by Friday.';
      expect(landed('# {?}\n\n$words', ['Cabin booking']), '# Cabin booking\n\n$words');
      expect(landed('# Trip to {?capital of Japan}\n\nFlights booked.', ['Tokyo']), '# Trip to Tokyo\n\nFlights booked.');
      expect(landed('# {?who wrote Dune}', ['Frank Herbert']), '# who wrote Dune\n??Frank Herbert??(Qwen3.5 4B from memory, 2026-09-28. Asked: who wrote Dune)');
      expect(
        landed('{?how long to boil an egg}', ['About 6 minutes for soft, 10 for hard']),
        'how long to boil an egg\n\n??About 6 minutes for soft, 10 for hard??(Qwen3.5 4B from memory, 2026-09-28. Asked: how long to boil an egg)',
      );
    });

    test('lands in a table cell, and several answers in one set of changes', () {
      const table = '# Reading\n\n| Book | Author | Year |\n| --- | --- | --- |\n| The Remains of the Day | {?} | {?} |';
      final [a, b] = blanksIn(table);
      final answers = [
        Landing(from: a.from, to: a.to, question: '', info: shapeOf(a, table), words: const ['Kazuo Ishiguro'], model: model, date: date, source: memory),
        Landing(from: b.from, to: b.to, question: '', info: shapeOf(b, table), words: const ['1989'], model: model, date: date, source: memory),
      ];
      expect(
        applyChanges(table, allChanges(table, answers)).split('\n').last,
        '| The Remains of the Day | ??Kazuo Ishiguro??(Qwen3.5 4B from memory, 2026-09-28) | ??1989??(Qwen3.5 4B from memory, 2026-09-28) |',
      );
    });

    test('replaces an answer asked again with the new one', () {
      const note = '# Football\n\nThe 2022 World Cup was won by ??France??(Qwen3.5 4B from memory, 2026-09-28)';
      final fill = fillsIn(note)[0];
      final pseudo = '${note.substring(0, fill.from)}{?}${note.substring(fill.to)}';
      final info = shapeOf(blanksIn(pseudo)[0], pseudo);
      final next = applyChanges(note, landingChanges(note, Landing(from: fill.from, to: fill.to, question: '', info: info, words: const ['Argentina'], model: model, date: date, source: memory)));
      expect(next, '# Football\n\nThe 2022 World Cup was won by ??Argentina??(Qwen3.5 4B from memory, 2026-09-28)');
    });

    test('signs the note at its top, apart from the answers', () {
      const note = '# Trip\n\nWords {?}';
      final sign = signatureChange(note)!;
      expect(applyChanges(note, [sign]), matches(RegExp(r'^---\nauthors: Ghost\n---\n# Trip')));
      expect(sign.to, lessThanOrEqualTo(note.indexOf('{?')));
      expect(signatureChange(applyChanges(note, [sign])), isNull);
    });
  });
}
