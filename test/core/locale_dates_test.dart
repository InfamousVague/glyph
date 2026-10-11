import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/locale_dates.dart';

/// Every form the page asks `Intl.DateTimeFormat` with, held to what the page's own WebView answered for it
/// (test/core/fixtures/locale_dates.json: Chrome 133 on the emulator, en-US and en-GB, four moments), part for part
/// and whole; and which table a phone's locale reads (lib/core/locale_dates.dart).
void main() {
  tearDown(() {
    toldLocale = null;
    toldWords = null;
  });

  final web = jsonDecode(File('test/core/fixtures/locale_dates.json').readAsStringSync()) as Map<String, dynamic>;
  // A moment's key is `y-m0-d-h-mi-s`, its month counted from 0, in the phone's own time.
  final moments = [
    for (final key in (web['dates'] as List).cast<String>())
      () {
        final n = key.split('-').map(int.parse).toList();
        return DateTime(n[0], n[1] + 1, n[2], n[3], n[4], n[5]);
      }(),
  ];
  final locales = web['locales'] as Map<String, dynamic>;
  const tables = {'en-US': DateLocale.enUS, 'en-GB': DateLocale.enGB};

  test('the fixture has both tables and every form, and no form goes unheld', () {
    expect(locales.keys.toSet(), tables.keys.toSet());
    expect(moments, hasLength(4));
    for (final sets in locales.values) {
      expect((sets as Map<String, dynamic>).keys.toSet(), {for (final form in DateForm.values) form.name});
    }
  });

  for (final MapEntry(key: tag, value: locale) in tables.entries) {
    group(tag, () {
      final sets = locales[tag] as Map<String, dynamic>;
      for (final form in DateForm.values) {
        test('${form.name} is written as the page writes it, part for part', () {
          final set = sets[form.name] as Map<String, dynamic>;
          final parts = set['parts'] as List, text = (set['text'] as List).cast<String>();
          for (var i = 0; i < moments.length; i += 1) {
            final wanted = [for (final part in parts[i] as List) (type: (part as List)[0] as String, value: part[1] as String)];
            expect(localeDateParts(moments[i], form, locale), wanted, reason: '${form.name} at ${moments[i]}');
            expect(localeDate(moments[i], form, locale), text[i], reason: '${form.name} at ${moments[i]}');
          }
        });
      }

      test('the phone’s words are these once it has said so', () {
        toldLocale = locale;
        final sets = locales[tag] as Map<String, dynamic>;
        for (final form in DateForm.values) {
          expect(toldDate(moments[0], form), ((sets[form.name] as Map<String, dynamic>)['text'] as List)[0], reason: form.name);
        }
      });
    });
  }

  group('which table', () {
    test('American, Canadian and Philippine English, and English with no country, read en-US', () {
      expect(dateLocaleOf('en', 'US'), DateLocale.enUS);
      expect(dateLocaleOf('en', 'CA'), DateLocale.enUS);
      expect(dateLocaleOf('en', 'PH'), DateLocale.enUS);
      expect(dateLocaleOf('en'), DateLocale.enUS);
      expect(dateLocaleOf('en', ''), DateLocale.enUS);
    });

    test('any other English, and any other language, reads en-GB: the words are English either way', () {
      expect(dateLocaleOf('en', 'GB'), DateLocale.enGB);
      expect(dateLocaleOf('en', 'AU'), DateLocale.enGB);
      expect(dateLocaleOf('en', 'IN'), DateLocale.enGB);
      expect(dateLocaleOf('en', '001'), DateLocale.enGB);
      expect(dateLocaleOf('de', 'DE'), DateLocale.enGB);
      expect(dateLocaleOf('de'), DateLocale.enGB);
      expect(dateLocaleOf('es', 'US'), DateLocale.enGB);
    });

    test('nothing is told until the phone says, and then it is the phone’s', () {
      final day = DateTime(2026, 10, 9, 16, 5);
      expect(toldLocale, isNull);
      expect(toldDate(day, DateForm.yMMMMEEEEd), isNull);
      expect(toldDayMonth(day, DateForm.MMMd), isNull);
      expect(toldShortMonth(day), isNull);
      // Asked without a locale and with none told, a form is en-GB's.
      expect(localeDate(day, DateForm.yMMMMEEEEd), 'Friday 9 October 2026');

      useLocaleOf('en', 'US');
      expect(toldLocale, DateLocale.enUS);
      expect(toldDate(day, DateForm.yMMMMEEEEd), 'Friday, October 9, 2026');
      expect(localeDate(day, DateForm.yMMMMEEEEd), 'Friday, October 9, 2026');

      useLocaleOf('en', 'GB');
      expect(toldDate(day, DateForm.yMMMMEEEEd), 'Friday 9 October 2026');
    });
  });

  group('the day and the month alone', () {
    final september = DateTime(2026, 9, 28, 9, 7);

    test('are in the locale’s order with a space between, its own literals dropped', () {
      expect(localeDayMonth(september, DateForm.MMMd, DateLocale.enUS), 'Sep 28');
      expect(localeDayMonth(september, DateForm.MMMd, DateLocale.enGB), '28 Sept');
      expect(localeDayMonth(september, DateForm.MMMMd, DateLocale.enUS), 'September 28');
      expect(localeDayMonth(september, DateForm.MMMMd, DateLocale.enGB), '28 September');
      // A form with more than the two keeps only the two.
      expect(localeDayMonth(september, DateForm.yMMMEd, DateLocale.enUS), 'Sep 28');
    });

    test('and the short month by itself is the table’s', () {
      toldLocale = DateLocale.enUS;
      expect(toldShortMonth(september), 'Sep');
      expect(toldDayMonth(september, DateForm.MMMd), 'Sep 28');
      toldLocale = DateLocale.enGB;
      expect(toldShortMonth(september), 'Sept');
      expect(toldDayMonth(september, DateForm.MMMd), '28 Sept');
    });
  });

  test('a wall clock kept in UTC reads as the clock it is', () {
    final wall = DateTime.utc(2026, 9, 28, 13, 5);
    expect(localeDate(wall, DateForm.MMMEd, DateLocale.enUS), 'Mon, Sep 28');
    expect(localeDate(wall, DateForm.Hm23, DateLocale.enUS), '13:05');
  });

  // Section 40 of docs/PARITY.md. What a phone answers is test/core/phone_dates_test.dart's; here the two readings
  // are held by words written out by hand, so that what is tested is this file's arithmetic and nothing else.
  group('words a phone could answer', () {
    tearDown(() => toldWords = null);

    /// A phone's answer with every form's pattern the same, and whatever else a test says.
    Map<String, Object?> answer(String pattern, Map<String, Object?> more) => {
          'patterns': {for (final form in DateForm.values) form.name: pattern},
          'months': [for (var m = 1; m <= 12; m += 1) 'month $m'],
          'shortMonths': [for (var m = 1; m <= 12; m += 1) 'm$m'],
          'weekdays': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
          'shortWeekdays': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
          'am': 'AM',
          'pm': 'PM',
          ...more,
        };

    int day(int y, int m, int d) => DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

    // The Persian year 1405 as it falls: six months of thirty-one days from 21 March 2026, five of thirty, and a
    // last of twenty-nine; and the first day of 1406 for where the table ends.
    final persian1405 = [
      day(2026, 3, 21), day(2026, 4, 21), day(2026, 5, 22), day(2026, 6, 22), day(2026, 7, 23), day(2026, 8, 23), //
      day(2026, 9, 23), day(2026, 10, 23), day(2026, 11, 22), day(2026, 12, 22), day(2027, 1, 21), day(2027, 2, 20),
      day(2027, 3, 21),
    ];

    test('a calendar with months of its own: the year, the month and the day are read from where its months begin', () {
      toldLocale = DateLocale.enGB;
      toldWords = DateWords.fromJson(answer('d MMMM y (M/d) EEEE', {'firstYear': 1405, 'monthStarts': persian1405}));
      expect(toldWords!.monthStarts, isNotNull);
      // 9 October 2026 is 17 Mehr 1405, a Friday in any calendar.
      expect(localeDate(DateTime(2026, 10, 9, 16, 5), DateForm.yMMMMd), '17 month 7 1405 (7/17) Friday');
      // The first and the last day of a month, a month of thirty-one, and the year's last day.
      expect(localeDate(DateTime(2026, 3, 21), DateForm.yMMMMd), '1 month 1 1405 (1/1) Saturday');
      expect(localeDate(DateTime(2026, 4, 20, 23, 59), DateForm.yMMMMd), '31 month 1 1405 (1/31) Monday');
      expect(localeDate(DateTime(2027, 1, 3, 0, 30), DateForm.yMMMMd), '13 month 10 1405 (10/13) Sunday');
      expect(localeDate(DateTime(2027, 3, 20), DateForm.yMMMMd), '29 month 12 1405 (12/29) Saturday');
      // A month's name by itself is the calendar's month too.
      expect(toldMonth(DateTime(2026, 10, 9)), 'month 7');
      expect(toldShortMonth(DateTime(2026, 5, 1)), 'm2');
      // A day the table does not reach is left as the Gregorian date it is.
      expect(localeDate(DateTime(2026, 3, 20), DateForm.yMMMMd), '20 month 3 2026 (3/20) Friday');
      expect(localeDate(DateTime(2027, 3, 21), DateForm.yMMMMd), '21 month 3 2027 (3/21) Sunday');
    });

    test('a table that is not whole is no table: the months are then the Gregorian ones', () {
      toldLocale = DateLocale.enGB;
      for (final broken in <Map<String, Object?>>[
        {'firstYear': 1405, 'monthStarts': persian1405.sublist(0, 12)},
        {'monthStarts': persian1405},
        {'firstYear': 1405, 'monthStarts': [...persian1405.sublist(0, 12), persian1405[3]]},
        {'firstYear': 1405, 'monthStarts': 'none'},
      ]) {
        toldWords = DateWords.fromJson(answer('d MMMM y', broken));
        expect(toldWords!.monthStarts, isNull, reason: '$broken');
        expect(localeDate(DateTime(2026, 10, 9), DateForm.yMMMMd), '9 month 10 2026');
      }
    });

    test('a day\'s finer periods: the part of the day by its hour, and noon at twelve exactly as the pattern reads exactly', () {
      toldLocale = DateLocale.enGB;
      final hours = [
        for (var h = 0; h < 24; h += 1)
          h < 5 ? 'before dawn' : h < 8 ? 'early' : h < 12 ? 'morning' : h < 13 ? 'midday' : h < 19 ? 'afternoon' : 'evening',
      ];
      Map<String, Object?> with_(String pattern) => answer(pattern, {
            'periods': {
              'B': {'hours': hours, 'noon': 'noon'},
            },
          });
      toldWords = DateWords.fromJson(with_('B h:mm'));
      expect(localeDate(DateTime(2027, 1, 3, 0, 30), DateForm.hm), 'before dawn 12:30');
      expect(localeDate(DateTime(2026, 9, 28, 9, 7, 3), DateForm.hm), 'morning 9:07');
      expect(localeDate(DateTime(2026, 10, 9, 16, 5), DateForm.hm), 'afternoon 4:05');
      expect(localeDate(DateTime(2026, 10, 9, 19, 0), DateForm.hm), 'evening 7:00');
      // Twelve: noon on the minute, the hour's own part after it. Seconds do not count where the pattern writes none.
      expect(localeDate(DateTime(2026, 5, 1, 12, 0, 40), DateForm.hm), 'noon 12:00');
      expect(localeDate(DateTime(2026, 5, 1, 12, 1), DateForm.hm), 'midday 12:01');
      expect([for (final part in localeDateParts(DateTime(2026, 5, 1, 12, 1), DateForm.hm)) part.type], ['dayPeriod', 'literal', 'hour', 'literal', 'minute']);
      // With seconds written, they count; with no minutes written, the whole hour is twelve o'clock.
      toldWords = DateWords.fromJson(with_('B h:mm:ss'));
      expect(localeDate(DateTime(2026, 5, 1, 12, 0, 40), DateForm.hm), 'midday 12:00:40');
      expect(localeDate(DateTime(2026, 5, 1, 12, 0, 0), DateForm.hm), 'noon 12:00:00');
      toldWords = DateWords.fromJson(with_('B h'));
      expect(localeDate(DateTime(2026, 5, 1, 12, 47), DateForm.hm), 'noon 12');
      // Names that are not whole, or none at all for the pattern's letters: the two meridiems, as before.
      toldWords = DateWords.fromJson(answer('B h:mm', {
        'periods': {
          'B': {'hours': hours.sublist(1), 'noon': 'noon'},
        },
      }));
      expect(toldWords!.periods, isNull);
      expect(localeDate(DateTime(2027, 1, 3, 0, 30), DateForm.hm), 'AM 12:30');
      toldWords = DateWords.fromJson(with_('BBBB h:mm'));
      expect(localeDate(DateTime(2026, 10, 9, 16, 5), DateForm.hm), 'PM 4:05');
    });
  });
}
