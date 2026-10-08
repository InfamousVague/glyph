// The facts the phone works out itself. A port of src/app/core/fillFacts.test.ts, case for case, and after it the
// web's own answers for a corpus of notes and for every zone's offsets (tool/ai_fixtures.mjs).
//
// The page's tests run "in British English" (`inLocale('en-GB', …)`); this app's dates are en-GB's always
// (lib/ai/support/stamp.dart), so `inLocale` is nothing here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/support/stamp.dart';
import 'package:ghost_md/ai/support/time_zone_table.dart';
import 'package:ghost_md/ai/support/time_zones.dart';
import 'package:ghost_md/ai/support/unaccent.dart';
import 'package:ghost_md/core/blanks.dart';
import 'package:ghost_md/core/fill_facts.dart';

/// Monday 28 September 2026, 14:05 in London: 13:05 UTC.
final DateTime now = DateTime.utc(2026, 9, 28, 13, 5);
final FactClock clock = FactClock(now: now, zone: 'Europe/London');

/// What the app works out for the last blank of [text].
Worked? worked(String text, [FactClock? at]) => workOut(blanksIn(text).last, text, at ?? clock);

String? answer(String text) {
  final found = worked(text);
  return found is WorkedAnswer ? found.answer : null;
}

String? refusal(String text) {
  final found = worked(text);
  return found is CannotWork ? found.words : null;
}

Object? fixture(String name) => jsonDecode(File('test/ai/fixtures/$name').readAsStringSync());

void main() {
  group('totals and averages of the note’s own amounts', () {
    const cabin = '## Cabin weekend\n- Cabin deposit \$200\n- Ferry \$45\n- Food \$80\n\nTotal so far: {?total}';

    test('adds the list above, and follows a changed number', () {
      expect(answer(cabin), r'$325');
      expect(answer(cabin.replaceFirst(r'$80', r'$95')), r'$340');
      final found = worked(cabin);
      expect(found, isA<WorkedAnswer>());
      expect(found!.kind, 'answer');
      expect(found.icon, FactIcon.calculator);
      expect((found as WorkedAnswer).working, r'$200 + $45 + $80 = $325.');
    });

    test('reads a date among the costs as a date, and says so', () {
      final found = worked('- Cabin deposit \$200\n- Ferry \$45\n- Dinner on 3 Oct\n\nTotal: {?}');
      expect(found, isA<WorkedAnswer>());
      expect((found! as WorkedAnswer).answer, r'$245');
      expect((found as WorkedAnswer).working, r'$200 + $45 = $245. Dinner on 3 Oct has no amount.');
    });

    test('is no sum without a total word in the right place, or without two amounts', () {
      expect(worked('- Japan 2019\n- Peru 2022\n\nCountries so far: {?}'), isNull);
      expect(worked('- Japan \$200\n- Peru \$300\n\nThe total came as a surprise. Countries so far: {?}'), isNull);
      expect(worked('What’s the average lifespan of a cat? {?}'), isNull);
    });

    test('refuses two kinds of amount and a line with two', () {
      expect(refusal('- Cabin \$200\n- Ferry £45\n\nTotal: {?}'), r'The app adds these up itself, and $200 and £45 are different money.');
      expect(refusal('- Cabin 200\n- Ferry \$45\n\nTotal: {?}'), r'The app adds these up itself, and 200 and $45 are not the same kind of number.');
      expect(refusal('- Cabin \$200\n- Ferry \$45, \$30 back\n\nTotal: {?}'), r'The app adds these up itself, and one line has two amounts: Ferry $45, $30 back. Keep one to a line.');
    });

    test('averages, keeps a unit or a code, and passes a numbered list’s own numbers', () {
      expect(answer('- \$200\n- \$45\n- \$80\n\nThe average: {?}'), r'$108.33');
      expect(answer('1. Flour 2 kg\n2. Sugar 1.5 kg\n\nTotal: {?}'), '3.5 kg');
      expect(answer('- Hotel 200 EUR\n- Train 45 EUR\n\nIn all: {?}'), '245 EUR');
    });

    test('adds the column above a Total row', () {
      expect(answer('| Item | Cost |\n| --- | --- |\n| Cabin | \$200 |\n| Ferry | \$45 |\n| Total | {?} |'), r'$245');
    });
  });

  group('counts', () {
    test('counts the note’s to-dos, and the list above', () {
      const note = '- [x] Found the leak\n- [ ] Buy a washer\n- [ ] Fit it\n- [ ] Test\n\nTo-dos left: {?}';
      expect(answer(note), '3 left');
      expect(answer(note.replaceFirst('To-dos left', 'Tasks done')), '1 done');
      expect(answer('- Passport\n- Plug adapter\n- Rail pass\nItems on this list: {?}'), '3 items');
    });

    test('leaves a question about items that is not a count', () {
      expect(worked('How many items can I take in hand luggage? {?}'), isNull);
    });
  });

  group('days and dates, on Monday 28 September 2026', () {
    test('counts days until and since, today counting as nought', () {
      expect(answer('Days until Christmas: {?}'), '88 days');
      expect(answer('Days since Christmas: {?}'), '277 days');
      expect(answer('How many days until Christmas? {?}'), '88 days');
      expect(answer('Days until 28 September: {?}'), '0 days');
      expect(answer('Weeks until Christmas: {?}'), '12 weeks and 4 days');
    });

    test('shows its working in the person’s own form, and changes each day', () {
      final found = worked('Days until Christmas: {?}');
      expect(found!.icon, FactIcon.calendar);
      expect((found as WorkedAnswer).changes, Changes.day);
      final today = longDate(DateTime(2026, 9, 28));
      final christmas = longDate(DateTime(2026, 12, 25));
      expect(found.working, 'From today, $today, to $christmas. It changes each day.');
    });

    test('names a weekday, and a date some weeks on', () {
      expect(answer('Sam’s birthday, 14 November, is a {?weekday}.'), 'Saturday');
      expect(answer('3 weeks from today: {?}'), longDate(DateTime(2026, 10, 19)));
    });

    test('refuses a slashed date, a day that moves, and days with no date', () {
      expect(refusal('Days until 05/11: {?}'), '05/11 is a different day in London and in New York. Write it as 11 May or 5 November.');
      expect(refusal('Days until Easter: {?}'), 'Easter moves each year, and the app does not know when it falls.');
      expect(refusal('How many days until we fly? {?}'), 'The app counts days itself, and there is no date here to count to.');
      final easter = worked('Days until Easter: {?}');
      expect(easter!.kind, 'cannot');
      expect(easter.icon, FactIcon.calendar);
    });

    test('leaves a question with no day word and no date, and a count that is stated', () {
      expect(worked('How long until the bread is proven? {?}'), isNull);
      expect(worked('I have 3 days until my exam, so revise {?what}'), isNull);
      expect(worked('I fly out in two days, so pack {?what}'), isNull);
    });
  });

  group('what the app leaves to the model', () {
    test('works none of the model’s scenarios out, Matt’s Tokyo first', () {
      for (final text in [
        '# Tokyo trip\n\nFlights are cheapest to Tokyo on {?what day / time?}',
        'The capital of Australia is {?}.',
        'Sam said she would bring the charger and the dog food. I am booking the ferry.\n\nWho brings the charger? {?}',
        'Priya: export bug fixed, in review, lands Tuesday.\n\nIn one line: {?summary}',
        '# Kitchen tap\n- [x] Found the leak under the sink\n- [ ] {?the next step}',
        '## Japan packing\n- Passport\n- Plug adapter\n- {?three more things}',
        '| Say | In Japanese |\n| --- | --- |\n| Thank you | {?} |',
        '| Book | Author | Year |\n| --- | --- | --- |\n| The Remains of the Day | {?} | {?} |',
        'Petrichor: {?what it means}',
        '1 cup of plain flour is about {?grams} grams.',
        '# {?}\n\nBook the cabin for the second week of October.',
        'The 2022 World Cup was won by {?}',
        'Opening line, friendlier: {?a friendlier way to say: fix the boiler now}',
        '{?how long to boil an egg}',
        '# Trip to {?capital of Japan}',
        'What’s the average lifespan of a cat? {?}',
        'Which day of our trip is best for the temple? {?}',
      ]) {
        expect(worked(text), isNull, reason: text);
      }
    });
  });

  group('units', () {
    test('converts a temperature, a distance and a weight', () {
      expect(answer('180 °C in Fahrenheit is {?°F}.'), '356 °F');
      expect((worked('180 °C in Fahrenheit is {?°F}.')! as WorkedAnswer).working, '180 × 9 ÷ 5 + 32 = 356.');
      expect(answer('10 km is {?} miles.'), '6.2 mi');
      expect(answer('How far is 10 km in miles? {?}'), '6.2 mi');
      expect(answer('2 lb in kg: {?}'), '0.9 kg');
    });

    test('passes a cup to grams on, since that depends on the thing', () {
      expect(worked('1 cup of plain flour is about {?grams} grams.'), isNull);
      expect(worked('A tablespoon of butter is about {?grams} grams.'), isNull);
    });
  });

  group('the time', () {
    test('says the time in a city now, with its weekday, changing each minute', () {
      expect(answer('What time is it in Tokyo now? {?}'), '22:05 Monday');
      final found = worked('What time is it in Tokyo now? {?}')! as WorkedAnswer;
      expect(found.icon, FactIcon.globe);
      expect(found.changes, Changes.minute);
      expect(found.working, 'Tokyo is 8 hours ahead of London today. It changes each minute.');
    });

    test('gives the difference between two cities across a month, with the day the clocks change', () {
      expect(answer('Tokyo is {?how many hours} ahead of London in October.'), '8 hours, 9 from 25 October');
      expect(answer('Tokyo is {?how many hours} ahead of London in July.'), '8 hours');
      expect(answer('Tokyo is {?how many hours} ahead of London in December.'), '9 hours');
    });

    test('turns a time in one city into another’s', () {
      expect(answer('14:00 in London is {?} in Tokyo'), '22:00');
    });

    test('says so for a city it does not know', () {
      expect(refusal('What time is it in Ulaanbaatar? {?}'), 'The app knows the time in about sixty cities, and Ulaanbaatar is not one.');
    });
  });

  // ---- beyond the page's own cases ----------------------------------------------------------------------------------

  group('the web’s own answers (tool/ai_fixtures.mjs)', () {
    test('every zone’s offset, at every change of it and three hundred other moments from 2000 to 2040', () {
      final zones = fixture('zone_offsets.json')! as Map<String, Object?>;
      expect(zones.keys.toSet(), cityZones.values.toSet());
      expect(zoneTable.keys.toSet(), cityZones.values.toSet());
      var held = 0;
      for (final MapEntry(key: zone, value: points) in zones.entries) {
        for (final point in (points! as List).cast<List<Object?>>()) {
          final minute = point[0]! as int;
          final at = DateTime.fromMillisecondsSinceEpoch(minute * 60000, isUtc: true);
          expect(offsetMinutes(zone, at), point[1], reason: '$zone at $at');
          held += 1;
        }
      }
      expect(held, greaterThan(20000));
    });

    test('every note of the corpus, on four clocks', () {
      final data = fixture('fill_facts_web.json')! as Map<String, Object?>;
      final clocks = {
        for (final MapEntry(:key, :value) in (data['clocks']! as Map<String, Object?>).entries)
          key: FactClock(now: DateTime.fromMillisecondsSinceEpoch((value! as Map)['now'] as int, isUtc: true), zone: (value as Map)['zone'] as String),
      };
      final cases = (data['cases']! as List).cast<Map<String, Object?>>();
      expect(cases.length, greaterThan(600));
      for (final one in cases) {
        final text = one['text']! as String;
        final found = workOut(blanksIn(text).last, text, clocks[one['clock']]!);
        expect(found?.toJson(), one['worked'], reason: '${one['clock']}: $text');
      }
    });

    test('accents come off as NFD and \\p{Diacritic} take them', () {
      for (final one in (fixture('unaccent_web.json')! as List).cast<Map<String, Object?>>()) {
        final text = one['text']! as String;
        expect(unaccented(text), one['folded'], reason: text);
        expect(unaccented(text.toLowerCase()), one['lower'], reason: text);
      }
    });
  });

  group('what the port adds', () {
    test('a city’s zone whatever its case or accents, and the city a zone is named for', () {
      expect(zoneOf('São Paulo'), 'America/Sao_Paulo');
      expect(zoneOf('  bogotá '), 'America/Bogota');
      expect(zoneOf('Ulaanbaatar'), isNull);
      expect(cityOf('America/New_York'), 'New York');
      expect(cityOf('Europe/London'), 'London');
      expect(cityOf('Asia/Kolkata'), 'Kolkata');
      expect(cityOf('Asia/Bangkok'), 'Bangkok');
      expect(cityOf('Europe/Zurich'), 'Zurich');
      expect(cityOf('Mars/Olympus'), isNull);
      expect(cities.first, 'Rio de Janeiro');
      expect(cities.indexOf('New Delhi'), lessThan(cities.indexOf('Delhi')));
      expect(cities.length, cityZones.length);
    });

    test('a zone the table lacks is 0, and outside 2000 to 2040 the nearest offset stands', () {
      expect(knowsZone('Europe/London'), isTrue);
      expect(knowsZone('Asia/Ulaanbaatar'), isFalse);
      expect(offsetMinutes('Asia/Ulaanbaatar', now), 0);
      expect(offsetMinutes('Asia/Tokyo', DateTime.utc(1990, 6)), 540);
      expect(offsetMinutes('Asia/Tokyo', DateTime.utc(2060, 6)), 540);
      expect(offsetMinutes('Europe/London', DateTime.utc(1999, 12, 31)), 0);
    });

    test('a clock with no zone, or one the table lacks, is “here” at the device’s own offset', () {
      final device = now.toLocal().timeZoneOffset.inMinutes;
      for (final at in [FactClock(now: now), FactClock(now: now, zone: 'Asia/Ulaanbaatar')]) {
        final found = worked('What time is it in Tokyo now? {?}', at)! as WorkedAnswer;
        expect(found.answer, '22:05 Monday');
        final diff = 540 - device;
        final hours = diff.abs() ~/ 60;
        final minutes = diff.abs() % 60;
        final span = '$hours ${hours == 1 ? 'hour' : 'hours'}${minutes == 0 ? '' : ' $minutes ${minutes == 1 ? 'minute' : 'minutes'}'}';
        final relation = diff == 0 ? 'Tokyo keeps the same time as here today.' : 'Tokyo is $span ${diff > 0 ? 'ahead of' : 'behind'} here today.';
        expect(found.working, '$relation It changes each minute.');
      }
    });

    test('a clock may bring its own offsets', () {
      final fixed = FactClock(now: now, zone: 'Mars/Olympus', offsetOf: (zone, at) => zone == 'Asia/Tokyo' ? 600 : 60);
      final found = worked('What time is it in Tokyo now? {?}', fixed)! as WorkedAnswer;
      expect(found.answer, '23:05 Monday');
      expect(found.working, 'Tokyo is 9 hours ahead of here today. It changes each minute.');
    });

    test('a moment in words, as en-GB writes it', () {
      final at = DateTime(2026, 9, 28, 14, 5);
      expect(stamp(at), '28 Sept 2026, 14:05');
      expect(clockTime(DateTime(2026, 9, 28, 0, 5)), '00:05');
      expect(longDay(at), 'Monday 28 September');
      expect(longDate(at), 'Monday, 28 September 2026');
    });
  });
}
