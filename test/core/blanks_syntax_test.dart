import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/blanks_syntax.dart';

/// Blanks and fills as text (lib/core/blanks_syntax.dart), case for case with the web's `core/blanks.test.ts`.
///
/// What differs: three of the web's checks run the editor's parser over the text (`nodes`, `notesIn`, the
/// `readsBack` half of "the mark an answer is written as", and "makes no node in the parser, and no link"). The
/// parser is the editor's, not this module's, so those halves are left to the editor's own tests; every check of
/// what this module answers is here.

List<String> questions(String text) => [for (final b in blankMatches(text)) b.question];
const ({String model, FillSource source, String date}) memory = (model: 'Qwen3.5 4B', source: FillSource.memory(), date: '2026-09-28');

/// The rows of the web's `core/titles.fixture.json`: a first line, and what `titleWords` answers for it.
const Map<String, String> titleRows = {
  '# {?}': '',
  '# {?a title}': '',
  '{?}': '',
  '{?how long to boil an egg}': 'how long to boil an egg',
  '# {?who wrote Dune}': '# who wrote Dune',
  '# Trip to {?capital of Japan}': '# Trip to',
  '# Trip to Tokyo': '# Trip to Tokyo',
  '# Trip to ??Tokyo??(Qwen3.5 4B from memory, 2026-09-28. Asked: capital of Japan)': '# Trip to Tokyo',
  '# {?} for {?which city}': '# for',
  '# Doubts ??four hundred??(check with Sam)': '# Doubts ??four hundred??(check with Sam)',
};

void main() {
  group('the pattern', () {
    test('reads the sixteen cases', () {
      expect(questions('Flights are cheapest to Tokyo on {?what day / time?}'), ['what day / time?']);
      expect(questions('The capital of Australia is {?}.'), ['']);
      expect(questions('Journal {{?q}} stays a template'), isEmpty);
      expect(questions('Handlebars {{date}} and {?x}'), ['x']);
      expect(questions(r'Escaped \{?not a blank}'), isEmpty);
      expect(questions('Nested {?a {b} c}'), isEmpty);
      expect(questions('Unsure in braces {??maybe??}'), isEmpty);
      expect(questions('Two {?a} and {?b} on a line'), ['a', 'b']);
      expect(questions('| Thank you | {?} |'), ['']);
      expect(questions('# {?}'), ['']);
      expect(questions('{?${'x' * 160}}'), hasLength(1));
      expect(questions('{?${'x' * 161}}'), isEmpty);
      expect(questions(r'HOCON ${?HOME} in prose'), isEmpty);
      expect(questions('| {?Paris | London} |'), isEmpty);
      expect(questions('Paris or London: {?which, Paris | London}'), isEmpty);
      expect(questions(r'Costs $5 {?total}'), ['total']);
    });

    test('gives each match its span, counted from the offset', () {
      expect(blankMatches('on {? what day }', 10), [const Blank(from: 13, to: 26, question: 'what day')]);
      expect(blankSample, '{?a question}');
      expect(questions(blankSample), ['a question']);
    });
  });

  group('the reader away from the editor', () {
    test('skips front matter, code, comments, tags, maths and addresses', () {
      final note = [
        '---',
        'title: {?no}',
        '---',
        'Real {?yes}',
        '```',
        '{?fenced}',
        '```',
        'A `code {?span}` and ``two {?ticks}``',
        '<!-- {?comment} -->',
        '<span title="{?tag}">words</span>',
        r'Maths $x {?maths}$ here',
        '[words](https://x.y/{?address}) and <https://x.y/{?auto}>',
        'And {?last}',
      ].join('\n');
      expect([for (final b in blanksIn(note)) b.question], ['yes', 'last']);
      expect(hasBlank(note), isTrue);
      expect(hasBlank('```\n{?fenced}\n```'), isFalse);
      expect(hasBlank('no blank'), isFalse);
    });

    test('keeps a blank in a table cell and in a link’s words', () {
      expect([for (final b in blanksIn('| Say | In Japanese |\n| --- | --- |\n| Thank you | {?} |')) b.question], ['']);
      expect([for (final b in blanksIn('[{?which}](https://x.y)')) b.question], ['which']);
    });

    test('tells blanks with one question apart by their order', () {
      const text = '{?a} {?b} {?a}';
      final blanks = blanksIn(text);
      expect(orderOf(blanks, blanks[2]), 1);
      expect(findBlank(blanks, 'a', 1)?.from, 10);
      expect(findBlank(blanks, 'a', 2), isNull);
    });
  });

  group('the asking words', () {
    Asking asking(String text) => askingWords(blanksIn(text).last, text);

    test('read the question before an empty blank', () {
      expect(asking('How many days until Christmas? {?}').prior, 'How many days until Christmas?');
      expect(asking('Who brings the charger? {?}').text, contains('Who brings the charger?'));
    });

    test('read the line above a label', () {
      expect(asking('Q: Who won the 2026 World Cup?\nA: {?}').prior, 'Q: Who won the 2026 World Cup?');
      expect(asking('Who won the 2026 World Cup?\n\nAnswer: {?}').prior, 'Who won the 2026 World Cup?');
      expect(asking('What time is it in Tokyo?\n→ {?}').prior, 'What time is it in Tokyo?');
    });

    test('keep to a sentence that has words of its own', () {
      final summary = asking('Tom will get the keys today.\n\nIn one line: {?summary}');
      expect(summary.prior, '');
      expect(summary.text, isNot(contains('today')));
      expect(asking('Total so far: {?total}').label, 'Total so far:');
    });

    test('find the sentence the blank sits in, and the words after it', () {
      final found = asking('I left early. 1 cup of plain flour is about {?grams} grams. Then more.');
      expect(found.sentence, '1 cup of plain flour is about grams.');
      expect(found.after, 'grams.');
      expect(found.question, 'grams');
    });

    test('never let a question’s own question mark end a sentence', () {
      expect(asking('Flights are cheapest to Tokyo on {?what day / time?} in winter').sentence, 'Flights are cheapest to Tokyo on in winter');
    });
  });

  group('the bracket', () {
    test('reads all four forms, a web source and Claude, and refuses a person’s own note', () {
      expect(
        readFilled('Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?'),
        const Filled(model: 'Qwen3.5 4B', source: FillSource.memory(), date: '2026-09-28', question: 'what day / time?', place: null),
      );
      expect(readFilled('Qwen3.5 4B from this note, 2026-09-28')?.source, const FillSource.note());
      expect(readFilled('Qwen3.5 4B from memory, 2026-09-28. Asked: three more things. 2 of 3')?.place, (n: 2, of: 3));
      expect(readFilled('Qwen3.5 4B from Open-Meteo, 2026-09-28. Asked: weather')?.source, const FillSource.web('Open-Meteo'));
      expect(readFilled('Qwen3.5 4B from Wikipedia and Wikidata, 2026-09-28')?.source, const FillSource.web('Wikipedia and Wikidata'));
      expect(readFilled('Claude from memory, 2026-09-28. Asked: question')?.model, 'Claude');
      expect(readFilled('check with Sam'), isNull);
      expect(readFilled('Sam said 400, the email says 450'), isNull);
    });
  });

  group('the mark an answer is written as', () {
    /// The mark's words and its bracket read back by this module's own reader ([fillsIn]); the web reads it back
    /// through the editor's parser too.
    void readsBack(String line, String words) {
      final fills = fillsIn(line);
      expect(fills, hasLength(1), reason: line);
      expect(fills.first.words, words, reason: line);
      expect(readFilled(fills.first.bracket), isNotNull, reason: line);
    }

    test('is the Unsure mark with its source, in every case of the table', () {
      final plain = 'Flights are cheapest to Tokyo on ${filledMark('midweek', memory, 'what day / time?')}';
      expect(plain, 'Flights are cheapest to Tokyo on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)');
      readsBack(plain, 'midweek');

      final asked = 'Opening line: ${filledMark('Could you please get the boiler fixed as soon as possible?', memory, 'a friendlier way')}';
      expect(asked.endsWith(')?'), isTrue);
      readsBack(asked, 'Could you please get the boiler fixed as soon as possible');

      readsBack('Why: ${filledMark('why????', memory, 'x')}', 'why');
      final brackets = filledMark('Be kind', memory, 'a friendlier way (kind)');
      expect(brackets, contains('Asked: a friendlier way [kind]'));
      readsBack('Say: $brackets', 'Be kind');
      expect(filledMark('A', memory, 'is it ??maybe??'), contains('Asked: is it ?maybe?'));
      final who = 'Who?${filledMark('Sam', memory, '', 'Who?')}';
      expect(who, 'Who? ??Sam??(Qwen3.5 4B from memory, 2026-09-28)');
      readsBack(who, 'Sam');
      final picked = filledMark('A', memory, 'pick one. 2 of 3');
      expect(picked, contains('Asked: pick one, 2 of 3'));
      expect(readFilled(picked.substring(5, picked.length - 1))?.place, isNull);
    });

    test('carries an item’s place only when there are several', () {
      expect(filledMark('Rail pass', memory, 'three more things', '', (n: 1, of: 3)), contains('. Asked: three more things. 1 of 3)'));
      expect(filledMark('Rail pass', memory, 'the next step', '', (n: 1, of: 1)), isNot(contains('1 of 1')));
    });

    test('reads in a table cell', () {
      final row = '| Thank you | ${filledMark('ありがとう (arigatō)', memory, '')} |';
      expect(row, '| Thank you | ??ありがとう (arigatō)??(Qwen3.5 4B from memory, 2026-09-28) |');
      readsBack(row, 'ありがとう (arigatō)');
      expect(plainFills('| Say | In Japanese |\n| --- | --- |\n$row'), '| Say | In Japanese |\n| --- | --- |\n| Thank you | ありがとう (arigatō) |');
    });

    test('names a web source in the bracket, and reads it back', () {
      final mark = filledMark('14°C', (model: 'Qwen3.5 4B', source: const FillSource.web('Open-Meteo'), date: '2026-09-28'), 'weather');
      expect(mark, '??14°C??(Qwen3.5 4B from Open-Meteo, 2026-09-28. Asked: weather)');
      expect(fillsIn(mark).single.filled.source, const FillSource.web('Open-Meteo'));
      expect(filledMark('here', (model: 'Claude', source: const FillSource.note(), date: '2026-09-28'), ''), '??here??(Claude from this note, 2026-09-28)');
    });
  });

  group('a filled answer read as its words', () {
    test('drops the bracket of a fill and keeps a person’s own note', () {
      expect(plainFills('on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?) or so'), 'on midweek or so');
      expect(plainFills('as soon as possible??(Qwen3.5 4B from memory, 2026-09-28)?'), 'as soon as possible??(Qwen3.5 4B from memory, 2026-09-28)?');
      expect(plainFills('Say ??as soon as possible??(Qwen3.5 4B from memory, 2026-09-28)?'), 'Say as soon as possible?');
      expect(plainFills('??maybe??(check with Sam)'), '??maybe??(check with Sam)');
      expect(plainFills('no marks at all'), 'no marks at all');
    });

    test('finds each fill with its span', () {
      const text = 'a ??x??(Qwen3.5 4B from memory, 2026-09-28) b ??y??(mine)';
      expect([for (final f in fillsIn(text)) f.words], ['x']);
      expect(fillsIn(text).first.from, 2);
    });

    test('reads a blank as its question for an item’s words', () {
      expect(readableWords('{?the next step}'), 'the next step');
      expect(readableWords('??Turn off the water??(Qwen3.5 4B from memory, 2026-09-28. Asked: the next step)'), 'Turn off the water');
    });

    test('takes the blanks out for the gist, fills read as words', () {
      expect(withoutBlanks('Trip to {?capital}  in ??May??(Qwen3.5 4B from memory, 2026-09-28)'), 'Trip to in May');
      expect(withoutBlanks('no blanks'), 'no blanks');
    });
  });

  group('the title', () {
    test('knows a question that asks for one', () {
      for (final q in ['', 'title', 'a title', 'name', 'A name', 'heading', 'a heading', 'name this', 'title this', 'what to call this', 'Title?']) {
        expect(asksForTitle(q), isTrue, reason: q);
      }
      for (final q in ['how long to boil an egg', 'who wrote Dune', 'capital of Japan', 'name of the band']) {
        expect(asksForTitle(q), isFalse, reason: q);
      }
    });

    test('reads every row of the shared fixture', () {
      for (final row in titleRows.entries) {
        expect(titleWords(row.key), row.value, reason: row.key);
      }
    });
  });

  group('quiet words', () {
    test('are whole lines of front matter and fenced code, and spans of the rest', () {
      const text = '---\na: b\n---\nx `y` z\n~~~\ncode\n~~~';
      final quiet = quietRanges(text);
      expect([for (final q in quiet) text.substring(q.from, q.to)], ['---', 'a: b', '---', '`y`', '~~~', 'code', '~~~']);
      expect([for (final q in quietRanges('see [[A note]] <b>bold</b> [x](y) <!-- c -->')) 'see [[A note]] <b>bold</b> [x](y) <!-- c -->'.substring(q.from, q.to)], [
        '<b>',
        '</b>',
        '](y)',
        '[[A note]]',
        '<!-- c -->',
      ]);
    });
  });
}
