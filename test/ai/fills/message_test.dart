// What the model reads for a fill, and how a press is split. A port of src/app/ai/fills/message.test.ts, case for
// case, and after it the web's own messages for a corpus of notes (tool/ai_fixtures.mjs).
//
// The page's fixture case builds the whole fixture with ai/fills/bar.ts `barFixture` and holds the file to it. bar.ts
// and web.ts are ported after this file, so here the file (test/ai/fixtures/fills.fixture.json, a copy of
// src/app/ai/fills.fixture.json) is replayed entry by entry with bar.ts's own few lines written out below: every
// case and every eye case at every rung, and every web case as far as this module decides it (the message the
// source's words are put into, its budget and its blank).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/fills/message.dart';
import 'package:ghost_md/ai/fills/prompts.dart';
import 'package:ghost_md/ai/fills/shape.dart';
import 'package:ghost_md/core/blanks.dart';

final DateTime today = DateTime(2026, 9, 28, 12);
List<Ask> asksOf(String note) => [for (final blank in blanksIn(note)) Ask(blank: blank, info: shapeOf(blank, note))];
String numbered(Ask ask, int index) => '{?${index + 1} ${ask.blank.question}}';

/// A case's asks, as ai/fills/bar.ts `barAsks` makes them: its blanks, or its one filled answer asked again (the
/// fixture does not say which, and only the asked-again case has no blank).
List<Ask> barAsks(String note) {
  final blanks = blanksIn(note);
  if (blanks.isNotEmpty) return [for (final blank in blanks) Ask(blank: blank, info: shapeOf(blank, note))];
  final fill = fillsIn(note).first;
  final blank = Blank(from: fill.from, to: fill.to, question: readFilled(fill.bracket)?.question ?? '');
  const info = ShapeInfo(shape: Shape.phrase, count: 1, language: null, cell: null, titleLine: false, wholeLine: false, tooShort: false);
  return [Ask(blank: blank, info: info, again: Again(words: fill.words))];
}

const Map<Shape, String> blockNames = {
  Shape.phrase: 'FILL_ANSWER',
  Shape.line: 'FILL_ANSWER',
  Shape.number: 'FILL_NUMBER',
  Shape.title: 'FILL_TITLE',
  Shape.summary: 'FILL_SUMMARY',
  Shape.items: 'FILL_ITEMS',
  Shape.cell: 'FILL_CELL',
  Shape.language: 'FILL_TRANSLATE',
};

const Map<String, String> promptsByName = {
  'FILL_PROMPT': fillPrompt,
  'FILL_CORE': fillCore,
  'FILL_ANSWER': fillAnswer,
  'FILL_NUMBER': fillNumber,
  'FILL_TITLE': fillTitle,
  'FILL_SUMMARY': fillSummary,
  'FILL_ITEMS': fillItems,
  'FILL_CELL': fillCell,
  'FILL_TRANSLATE': fillTranslate,
};

/// The generations a rung sends for a case, as ai/fills/bar.ts `barGenerations` writes them into the fixture.
List<Map<String, Object?>> barGenerations(String note, Rung rung) {
  final asks = barAsks(note);
  return [
    for (final generation in fillPlan(note, asks, rung, today))
      () {
        final built = buildFill(note, generation.asks, rung: rung, today: today, tight: generation.tight);
        final system = rung == 3 ? ['FILL_CORE', blockNames[generation.asks[0].info.shape]!] : ['FILL_PROMPT'];
        // The names are the prompts the message is really sent with.
        expect(built.system, system.map((name) => promptsByName[name]).join('\n\n'));
        return <String, Object?>{
          'system': system,
          'prompt': built.prompt,
          'max_tokens': built.maxTokens,
          // Each number the message asks, as the case's own blank: an items blank's slots all answer the one blank.
          'blanks': [
            for (var i = 0; i < generation.asks.length; i += 1)
              for (final _ in built.numbers[i]) asks.indexOf(generation.asks[i]) + 1,
          ],
        };
      }(),
  ];
}

void main() {
  group('the date the model is told', () {
    test('is fixed English whatever the phone speaks', () {
      expect(modelDay(today), 'Monday 28 September 2026');
      // The page asks again as an en-US and a de-DE phone; this app has no locale to set, and the names are two
      // fixed lists either way.
      expect(modelDay(DateTime(2026, 9, 28, 12)), 'Monday 28 September 2026');
      expect(modelDay(DateTime(2027, 1, 3)), 'Sunday 3 January 2027');
    });
  });

  group('what the model reads', () {
    test('is the Tokyo note as the spec writes it', () {
      const note = '# Tokyo trip\n\nFlights are cheapest to Tokyo on {?what day / time?}';
      expect(
        buildFill(note, asksOf(note), rung: 1, today: today).prompt,
        'Today is Monday 28 September 2026.\n\nThe note:\n# Tokyo trip\n\nFlights are cheapest to Tokyo on {?1 what day / time?}\n\nAnswer blank 1.',
      );
    });

    test('reads a cell’s headings, its header row and its own row, each blank named in words', () {
      const note = '# Kyoto in November\n\nIntro words here.\n\n## Phrases\n| Say | In Japanese |\n| --- | --- |\n| Thank you | {?} |\n| Where is the station? | {?} |';
      expect(
        buildFill(note, asksOf(note), rung: 1, today: today).prompt,
        [
          'Today is Monday 28 September 2026.',
          '',
          'The note:',
          '# Kyoto in November',
          '',
          '(lines left out)',
          '',
          '## Phrases',
          '| Say | In Japanese |',
          '| --- | --- |',
          '| Thank you | {?1 } |',
          '| Where is the station? | {?2 } |',
          '',
          'Blank 1 is Thank you in Japanese, in Japanese script.',
          'Blank 2 is Where is the station? in Japanese, in Japanese script.',
          '',
          'Answer blanks 1 to 2.',
        ].join('\n'),
      );
      const one = '# Reading\n\n| Book | Author | Year |\n| --- | --- | --- |\n| Never Let Me Go | Kazuo Ishiguro | 2005 |\n| The Remains of the Day | {?} | 1989 |';
      final scope = scopeText(one, asksOf(one), numbered);
      expect(scope, isNot(contains('Never Let Me Go')));
      expect(scope, contains('| The Remains of the Day | {?1 } | 1989 |'));
    });

    test('cuts a long section to a thousand characters before and six hundred after, at line ends', () {
      String filler(int n) => [for (var i = 0; i < n; i += 1) 'Line $i of words about the trip and nothing else much.'].join('\n');
      final note = '# Trip\n\n${filler(40)}\nFlights are cheapest on {?which day}\n${filler(40)}';
      final scope = scopeText(note, asksOf(note), numbered);
      final at = scope.indexOf('{?1 which day}');
      expect(at, greaterThan(0));
      final before = scope.substring(scope.indexOf('(lines left out)') + 17, at);
      expect(before.length, lessThanOrEqualTo(1060));
      expect(scope.length, lessThan(2000));
      expect(scope.startsWith('# Trip'), isTrue);
    });

    test('writes other blanks as ___, worked-out ones as their answers, fills as words, and no front matter', () {
      const note =
          '---\nlocation: 51.5,-0.1\n---\n# Trip\n\nTotal: {?total}\nWeather: {?}\nCheapest on ??midweek??(Qwen3.5 4B from memory, 2026-09-28) and [the site](https://x.y/z) or https://a.b\nAsk: {?which airport}';
      final asks = asksOf(note).where((a) => a.blank.question == 'which airport').toList();
      final scope = scopeText(note, asks, numbered, (blank) => blank.question == 'total' ? r'$325' : null);
      expect(scope, '# Trip\n\nTotal: \$325\nWeather: ___\nCheapest on midweek and the site or\nAsk: {?1 which airport}');
    });

    test('writes an answer asked again back as its question, and says which answer it is not', () {
      const note = '# Football\n\nThe 2022 World Cup was won by ??France??(Qwen3.5 4B from memory, 2026-09-28)';
      final fill = fillsIn(note)[0];
      final ask = Ask(blank: Blank(from: fill.from, to: fill.to, question: ''), info: asksOf('{?}')[0].info, again: const Again(words: 'France'));
      final prompt = buildFill(note, [ask], rung: 1, today: today).prompt;
      expect(prompt, contains('The 2022 World Cup was won by {?1 }'));
      expect(prompt.endsWith('It is not: France.\nAnswer blank 1.'), isTrue);
    });
  });

  group('an items blank', () {
    test('asks one new item a numbered blank, under the list’s own lead', () {
      const note = '# Japan packing\n\n1. Passport\n2. Plug adapter\n3. {?more}';
      final built = buildFill(note, asksOf(note), rung: 1, today: today);
      expect(built.prompt, contains('3. {?1 more}\n4. {?2 }\n5. {?3 }'));
      expect(built.prompt, contains('Blanks 1 to 3 are whole items of the list they are in, each one new.'));
      expect(built.prompt.endsWith('Answer blanks 1 to 3.'), isTrue);
      expect(built.numbers, [
        [1, 2, 3],
      ]);
      const todo = '# Tap\n- [x] Found the leak\n- [ ] {?the next step}\n\nThe capital of France is {?}.';
      final both = buildFill(todo, asksOf(todo), rung: 1, today: today);
      expect(both.numbers, [
        [1],
        [2],
      ]);
      expect(both.prompt, contains('Blank 1 is a whole item of the list it is in.'));
    });
  });

  group('the room', () {
    test('counts tokens by script, on the high side', () {
      expect(estimateTokens('abcd efgh'), 3);
      expect(estimateTokens('ありがとう'), 5);
      expect(estimateTokens('화장실이 어디예요'), 9);
      expect(estimateTokens('Спасибо'), 4);
    });

    test('puts seven language cells in one generation and the eighth in the next', () {
      final rows = [for (var i = 0; i < 8; i += 1) '| Phrase number ${i + 1} | {?} |'].join('\n');
      final note = '# Phrases\n\n| Say | In Japanese |\n| --- | --- |\n$rows';
      final plan = fillPlan(note, asksOf(note), 1, today);
      expect(plan.map((g) => g.asks.length), [7, 1]);
    });

    test('splits long Japanese scopes so each generation stays in the window', () {
      final para = 'これは長い段落です。' * 60;
      final note = [for (var i = 0; i < 12; i += 1) '## 第${i + 1}\n$para\n説明: {?}'].join('\n\n');
      final plan = fillPlan(note, asksOf(note), 1, today);
      expect(plan.length, greaterThan(1));
      for (final generation in plan) {
        expect(fits(buildFill(note, generation.asks, rung: 1, today: today, tight: generation.tight)), isTrue);
      }
    });

    test('gives each blank its own generation at the second rung, grouped by shape at the third', () {
      const note = '# Mixed\n\nThe capital of France is {?}.\n\n- Thank you: {?in Japanese}\n\nThe capital of Peru is {?}.';
      expect(fillPlan(note, asksOf(note), 2, today).map((g) => g.asks.length), [1, 1, 1]);
      expect(fillPlan(note, asksOf(note), 3, today).map((g) => g.asks[0].info.shape), [Shape.phrase, Shape.phrase, Shape.language]);
      expect(fillPlan(note, asksOf(note), 1, today).map((g) => g.asks.length), [3]);
    });
  });

  group('the fixture the Rust bar reads', () {
    final fixture = (jsonDecode(File('test/ai/fixtures/fills.fixture.json').readAsStringSync()) as Map).cast<String, Object?>();

    test('is what the page builds, every case at every rung', () {
      expect(fixture['prompt_tokens'], fillPromptTokens);
      var held = 0;
      for (final list in ['cases', 'eye']) {
        for (final one in (fixture[list]! as List).cast<Map<String, Object?>>()) {
          final note = one['note']! as String;
          final rungs = one['rungs']! as Map<String, Object?>;
          expect(rungs.keys, ['1', '2', '3'], reason: '${one['name']}');
          for (final rung in [1, 2, 3]) {
            expect(barGenerations(note, rung), rungs['$rung'], reason: '${one['name']} at rung $rung');
            held += (rungs['$rung']! as List).length;
          }
        }
      }
      expect((fixture['cases']! as List).length, 11);
      expect((fixture['eye']! as List).length, 17);
      expect(held, greaterThan(84));
      // The web cases: the message is this module's, with what the source returned put in before its last part by
      // ai/fills/web.ts `webMessage`, which is ported after this.
      final web = (fixture['web']! as List).cast<Map<String, Object?>>();
      expect(web.length, 3);
      for (final one in web) {
        final note = one['note']! as String;
        final built = buildFill(note, barAsks(note), rung: 1, today: today);
        final sent = ((one['rungs']! as Map)['1'] as List).single as Map<String, Object?>;
        final cut = built.prompt.lastIndexOf('\n\n');
        final prompt = sent['prompt']! as String;
        expect(prompt.startsWith('${built.prompt.substring(0, cut)}\n\nWhat ${one['source']} returned:\n'), isTrue, reason: '${one['name']}');
        expect(prompt.endsWith('\n\n${built.prompt.substring(cut + 2)}'), isTrue, reason: '${one['name']}');
        expect(sent['max_tokens'], built.maxTokens, reason: '${one['name']}');
        expect(sent['blanks'], [1], reason: '${one['name']}');
        expect(sent['system'], ['FILL_WEB_PROMPT'], reason: '${one['name']}');
      }
    });

    test('names the rungs the page ships, and a model never measured takes the middle one', () {
      expect(fixture['rungs'], fillRungs);
      expect(rungFor('a-model-nobody-measured'), 2);
    });
  });

  // ---- beyond the page's own cases ----------------------------------------------------------------------------------

  group('the web’s own messages (tool/ai_fixtures.mjs)', () {
    test('every note of the corpus at every rung: the plan, each message, its budget, its numbers and its room', () {
      final cases = (jsonDecode(File('test/ai/fixtures/message_web.json').readAsStringSync()) as List).cast<Map<String, Object?>>();
      expect(cases.length, greaterThan(60));
      var held = 0;
      var thrown = 0;
      for (final one in cases) {
        final text = one['text']! as String;
        final asks = asksOf(text);
        for (final rung in [1, 2, 3]) {
          final web = (one['rungs']! as Map)['$rung'] as List?;
          final plan = fillPlan(text, asks, rung, today);
          if (web == null) {
            // The page throws here (a table's one line ending the note); the port builds the message instead.
            thrown += 1;
            for (final generation in plan) {
              expect(buildFill(text, generation.asks, rung: rung, today: today, tight: generation.tight).prompt, contains('{?'));
            }
            continue;
          }
          final made = [
            for (final generation in plan)
              () {
                final built = buildFill(text, generation.asks, rung: rung, today: today, tight: generation.tight);
                return <String, Object?>{
                  'blanks': [for (final ask in generation.asks) asks.indexOf(ask)],
                  'tight': generation.tight,
                  'system': built.system == shapeBlocks[generation.asks[0].info.shape] ? 'block' : built.system.length,
                  'prompt': built.prompt,
                  'maxTokens': built.maxTokens,
                  'numbers': built.numbers,
                  'fits': fits(built),
                  'tokens': estimateTokens(built.prompt),
                };
              }(),
          ];
          expect(made, web, reason: 'rung $rung: ${text.length > 80 ? text.substring(0, 80) : text}');
          held += made.length;
        }
      }
      expect(held, greaterThan(200));
      expect(thrown, 3);
    });

    test('the next item’s lead, and the room’s numbers', () {
      expect(nextLead('3. Towel'), '4. ');
      expect(nextLead('  9) Towel', 2), '  11) ');
      expect(nextLead('- [x] Done'), '- [ ] ');
      expect(nextLead('* Towel'), '* ');
      expect(nextLead('Words'), '- ');
      expect(room, (output: 512, window: 6144));
      expect(leastBudget, 48);
      expect(shapeBlocks.keys.toSet(), Shape.values.toSet());
    });
  });
}
