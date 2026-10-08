// The shape of a blank and the check before anything is written. A port of src/app/ai/fills/shape.test.ts, case for
// case, and after it the web's own answers for a corpus of notes and answers (tool/ai_fixtures.mjs).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/fills/shape.dart';
import 'package:ghost_md/core/blanks.dart';

/// The shape of the last blank in [text].
ShapeInfo shape(String text) => shapeOf(blanksIn(text).last, text);

/// The check on the last blank in [text] with these answer lines.
Checked check(String text, List<String> lines, [bool truncated = false]) {
  final blank = blanksIn(text).last;
  return checkShape(lines, blank, shapeOf(blank, text), text, truncated);
}

String words(String text, List<String> lines) {
  final checked = check(text, lines);
  return checked.ok ? checked.text! : checked.why!.id;
}

const String twenty = r'Book the cabin for the second week of October. Ferry once Sam confirms dates with her brother. Deposit $200 by Friday.';

void main() {
  group('the shape of a blank', () {
    test('reads a title only from a whole first line that asks for one', () {
      expect(shape('# {?}\n\n$twenty').shape, Shape.title);
      expect(shape('# {?a title}\n\n$twenty').shape, Shape.title);
      expect(shape('# {?}\n\nToo few words.').tooShort, isTrue);
      expect(shape('{?how long to boil an egg}').shape, Shape.line);
      expect(shape('# {?who wrote Dune}').shape, Shape.line);
      final trip = shape('# Trip to {?capital of Japan}');
      expect(trip.shape, Shape.phrase);
      expect(trip.titleLine, isTrue);
    });

    test('reads a language from the question or a cell’s header, and not from “in which year”', () {
      final morning = shape('- Good morning: {?in Japanese}');
      expect(morning.shape, Shape.language);
      expect(morning.language!.name, 'Japanese');
      final thanks = shape('| Say | In Japanese |\n| --- | --- |\n| Thank you | {?} |');
      expect(thanks.shape, Shape.language);
      expect(thanks.cell, (header: 'In Japanese', row: 'Thank you'));
      expect(shape('It was finished {?in which year}').shape, Shape.phrase);
      expect(shape('- Two coffees, please: {?in Portuguese}').language?.script, isNull);
    });

    test('counts items: one for a to-do, three otherwise, or the number asked', () {
      void items(String text, int count) {
        final found = shape(text);
        expect(found.shape, Shape.items, reason: text);
        expect(found.count, count, reason: text);
      }

      items('- [x] Found the leak\n- [ ] {?the next step}', 1);
      items('- Passport\n- {?more}', 3);
      items('- Passport\n- {?three more things}', 3);
      items('- Passport\n- {?two more}', 2);
      items('1. Passport\n2. {?a few}', 3);
    });

    test('reads a cell, a summary, a number, a line and a phrase', () {
      final cell = shape('| Book | Author |\n| --- | --- |\n| The Remains of the Day | {?} |');
      expect(cell.shape, Shape.cell);
      expect(cell.cell, (header: 'Author', row: 'The Remains of the Day'));
      expect(shape('Notes.\n\nIn one line: {?summary}').shape, Shape.summary);
      expect(shape('Words.\n\n1 cup of plain flour is about {?grams} grams.').shape, Shape.number);
      expect(shape('Words.\n\nA trip of {?how many} days.').shape, Shape.number);
      expect(shape('Words.\n\n{?something to add}').shape, Shape.line);
      expect(shape('Words.\n\nFlights are cheapest on {?which day}').shape, Shape.phrase);
    });

    test('gives each shape its hint and its budget', () {
      final items = shape('- Passport\n- {?three more things}');
      expect(hintFor(1, items), 'Blanks 1 to 3 are whole items of the list they are in, each one new.');
      expect(hintFor(4, shape('- [ ] Found it\n- [ ] {?next}')), 'Blank 4 is a whole item of the list it is in.');
      expect(budgetOf(items), 99);
      expect(hintFor(2, shape('Words here.\n\nThe capital is {?}.')), isNull);
      final cell = shape('| Book | Year |\n| --- | --- |\n| The Remains of the Day | {?} |');
      expect(hintFor(3, cell), 'Blank 3 is the Year of The Remains of the Day.');
    });
  });

  group('the check before anything is written', () {
    test('reads UNKNOWN and its kin as not known, and an empty answer as none', () {
      expect(words('Words.\n\nThe newest Pixel is the {?}', ['UNKNOWN']), 'unknown');
      expect(words('Words.\n\nThe newest Pixel is the {?}', ['I don’t know']), 'unknown');
      expect(words('Words.\n\nThe capital is {?which city}', ['which city']), 'none');
      expect(words('Words.\n\nThe capital is {?which city}', []), 'none');
    });

    test('takes an echo of the line off', () {
      expect(words('Words.\n\nThe newest Pixel is the {?}', ['the newest Pixel is the Pixel 10']), 'Pixel 10');
    });

    test('tidies quotes, bold, a list mark and a full stop the sentence already has', () {
      expect(words('Words.\n\nThe capital of Australia is {?}.', ['"Canberra."']), 'Canberra');
      expect(words('Words.\n\nThe capital of Australia is {?}.', ['**Canberra**']), 'Canberra');
      expect(words('Words.\n\nFlights are cheapest on {?which day} in winter', ['- Tuesday.']), 'Tuesday');
    });

    test('refuses a nine-word title and one naming what the note lacks, and passes one of its own words', () {
      const note = '# {?}\n\n$twenty';
      expect(words(note, ['Book the cabin for the second week of October']), 'didnt-fit');
      expect(words(note, ['Cabin booking']), 'Cabin booking');
      expect(words(note, ['Cabin trip to Lisbon']), 'didnt-fit');
      expect(words(note, ['# Cabin booking.']), 'Cabin booking');
    });

    test('refuses a summary naming someone the note lacks', () {
      const note = '# Standup\n\nPriya: export bug fixed, lands Tuesday. Tom: blocked on keys.\n\nIn one line: {?summary}';
      expect(words(note, ['Priya fixed the export bug for Tuesday and Tom is blocked on keys.']), matches(RegExp(r'^Priya fixed')));
      expect(words(note, ['Priya and Sanjay fixed the export bug.']), 'didnt-fit');
    });

    test('keeps a translation’s script, and takes a Latin one’s brackets off', () {
      expect(words('- Thank you: {?in Japanese}', ['Arigato gozaimasu (a-ree-ga-toh go-zah-im-as)']), 'didnt-fit');
      expect(words('- Thank you: {?in Japanese}', ['ありがとう (arigatō)']), 'ありがとう (arigatō)');
      expect(words('- Two coffees, please: {?in Portuguese}', ['Duas cafés, por favor (duas cafés, por favor)']), 'Duas cafés, por favor');
    });

    test('makes a pipe a slash in a table line', () {
      expect(words('| Film | Director |\n| --- | --- |\n| Heat | {?} |', ['Michael Mann | director']), 'Michael Mann / director');
    });

    test('holds each shape to its own caps, and a cut answer to none', () {
      const phrase = 'Words.\n\nFlights are cheapest on {?which day}';
      expect(words(phrase, ['one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twentyone']), 'didnt-fit');
      const line = 'Words.\n\n{?something to say}';
      final thirtyFive = [for (var i = 0; i < 35; i += 1) 'w$i'].join(' ');
      expect(words(line, [thirtyFive]), thirtyFive);
      expect(check(phrase, ['Tuesday or Wed'], true), const Checked.not(CheckWhy.didntFit));
      expect(words('Words.\n\nA cup is about {?grams} grams.', ['about a cup']), 'didnt-fit');
      expect(words('Words.\n\nA cup is about {?grams} grams.', ['120 grams']), '120');
    });

    test('relets items, drops what the list has, and keeps the count', () {
      const note = '## Japan packing\n- Passport\n- Plug adapter\n- {?three more things}';
      final checked = check(note, ['- Rail pass', 'Passport', '3. Comfortable walking shoes', 'Cash in yen', 'An umbrella']);
      expect(checked, const Checked.ok('Rail pass', ['Rail pass', 'Comfortable walking shoes', 'Cash in yen']));
      expect(check(note, ['Passport', 'Plug adapter']), const Checked.not(CheckWhy.didntFit));
      expect(check(note, ['Rail pass', 'Walking sh'], true), const Checked.ok('Rail pass', ['Rail pass']));
    });
  });

  // ---- beyond the page's own cases ----------------------------------------------------------------------------------

  group('the web’s own answers (tool/ai_fixtures.mjs)', () {
    final cases = (jsonDecode(File('test/ai/fixtures/shape_web.json').readAsStringSync()) as List).cast<Map<String, Object?>>();

    test('every note of the corpus: its shape, its hint and its budget', () {
      expect(cases.length, greaterThan(50));
      for (final one in cases) {
        final text = one['text']! as String;
        final info = shape(text);
        expect(
          {
            'shape': info.shape.name,
            'count': info.count,
            'language': info.language == null ? null : {'name': info.language!.name, 'script': info.language!.script != null},
            'cell': info.cell == null ? null : {'header': info.cell!.header, 'row': info.cell!.row},
            'titleLine': info.titleLine,
            'wholeLine': info.wholeLine,
            'tooShort': info.tooShort,
          },
          one['info'],
          reason: text,
        );
        expect(hintFor(4, info), one['hint'], reason: text);
        expect(budgetOf(info), one['budget'], reason: text);
      }
    });

    test('every note of the corpus against forty-six answers, whole and cut', () {
      var held = 0;
      for (final one in cases) {
        final text = one['text']! as String;
        for (final each in (one['checks']! as List).cast<Map<String, Object?>>()) {
          final lines = (each['lines']! as List).cast<String>();
          final truncated = each['truncated']! as bool;
          expect(check(text, lines, truncated).toJson(), each['checked'], reason: '$text\n  answered ${jsonEncode(lines)}${truncated ? ', cut' : ''}');
          held += 1;
        }
      }
      expect(held, greaterThan(2500));
    });

    test('the languages by name, and the words a check may give', () {
      expect(languageAsked('in Japanese')!.script, isNotNull);
      expect(languageAsked('Mandarin?')!.name, 'Chinese');
      expect(languageAsked('in farsi')!.name, 'Persian');
      expect(languageAsked('in Bangla')!.name, 'Bangla');
      expect(languageAsked('in which year'), isNull);
      expect(CheckWhy.values.map((why) => why.id), ['unknown', 'none', 'didnt-fit']);
      expect(tableCells(r'| a \| b | c |'), [r'a \| b', 'c']);
      expect(titleLineIndex('---\ntitle: x\n---\n![pic](a.png)\n\n# Words'), 5);
    });
  });
}
