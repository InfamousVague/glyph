import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/day_words.dart';

/// A day said in words (lib/core/day_words.dart), case for case with the web's `core/dayWords.test.ts`: counted
/// from Thursday 1 October 2026 unless a case says otherwise, each rule the module promises, and the words it must
/// leave as words, since a due day that cannot be read is never guessed at.

const String thursday = '2026-10-01';
String? said(String words, [String today = thursday]) => dayOfWords(words, today);

void main() {
  group('days named by where they are from today', () {
    test('reads today, tonight, tomorrow and the days either side', () {
      expect(said('today'), '2026-10-01');
      expect(said('Tonight'), '2026-10-01');
      expect(said('this evening'), '2026-10-01');
      expect(said('end of day'), '2026-10-01');
      expect(said('tomorrow'), '2026-10-02');
      expect(said('tomorrow morning'), '2026-10-02');
      expect(said('the day after tomorrow'), '2026-10-03');
      expect(said('yesterday'), '2026-09-30');
    });

    test('reads a count of days or weeks', () {
      expect(said('in three days'), '2026-10-04');
      expect(said('in 10 days'), '2026-10-11');
      expect(said('in a week'), '2026-10-08');
      expect(said('in two weeks'), '2026-10-15');
      expect(said('in a fortnight'), '2026-10-15');
    });
  });

  group('weekdays', () {
    test('takes a weekday as the next one, today included', () {
      expect(said('Friday'), '2026-10-02');
      expect(said('on Friday'), '2026-10-02');
      expect(said('this Friday'), '2026-10-02');
      expect(said('by Saturday'), '2026-10-03');
      expect(said('Thursday'), '2026-10-01');
      expect(said('Wednesday'), '2026-10-07');
    });

    test('takes "next" as the week after this one, which starts on a Monday', () {
      expect(said('next Friday'), '2026-10-09');
      expect(said('next Thursday'), '2026-10-08');
      expect(said('next Monday'), '2026-10-05');
      // Said on a Monday, next Friday is eleven days on; said on a Sunday, the week after this one starts tomorrow.
      expect(said('next Friday', '2026-10-05'), '2026-10-16');
      expect(said('next Friday', '2026-10-04'), '2026-10-09');
    });

    test('takes next week as its Monday, and the weekend as its Saturday', () {
      expect(said('next week'), '2026-10-05');
      expect(nextWeek('2026-10-04'), '2026-10-05');
      expect(nextWeek('2026-10-05'), '2026-10-12');
      expect(nextWeek('3 Oct'), isNull);
      expect(said('the weekend'), '2026-10-03');
      expect(said('this weekend', '2026-10-03'), '2026-10-03');
      expect(said('weekend', '2026-10-04'), '2026-10-04');
    });
  });

  group('dates', () {
    test('reads a date said either way round, with its day in words or figures', () {
      expect(said('the third of October'), '2026-10-03');
      expect(said('October the third'), '2026-10-03');
      expect(said('October third'), '2026-10-03');
      expect(said('October 3rd'), '2026-10-03');
      expect(said('3 October'), '2026-10-03');
      expect(said('3rd of Oct'), '2026-10-03');
      expect(said('the twenty-first of December'), '2026-12-21');
      expect(said('December twenty first'), '2026-12-21');
      expect(said('the thirtieth of November'), '2026-11-30');
    });

    test('takes a date with no year as the next one, today included', () {
      expect(said('1 October'), '2026-10-01');
      expect(said('the 30th of September'), '2027-09-30');
      expect(said('29 February'), '2028-02-29');
    });

    test('keeps a year when one is said, commas and all', () {
      expect(said('December 21st, 2027'), '2027-12-21');
      expect(said('3 October 2025'), '2025-10-03');
    });

    test('takes "the third" as this month’s, or the next month that has it', () {
      expect(said('the third'), '2026-10-03');
      expect(said('the first'), '2026-10-01');
      expect(said('the 31st'), '2026-10-31');
      expect(said('the 31st', '2026-11-15'), '2026-12-31');
      expect(said('the second', '2026-12-20'), '2027-01-02');
    });
  });

  group('words that are not a day', () {
    test('reads nothing it was not taught', () {
      for (final words in ['', 'soon', 'later', 'the end of the month', 'Friday week', 'the 35th of October', '31 September', 'Fooday', 'next', 'in some days', 'the plumber']) {
        expect(said(words), isNull, reason: words);
      }
    });

    test('reads nothing from a today that is not a day', () {
      expect(dayOfWords('tomorrow', '1 Oct'), isNull);
    });
  });
}
