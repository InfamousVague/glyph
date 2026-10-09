import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/locale_dates.dart';

/// Every form the page asks `Intl.DateTimeFormat` with, held to what the page's own WebView answered for it
/// (test/core/fixtures/locale_dates.json: Chrome 133 on the emulator, en-US and en-GB, four moments), part for part
/// and whole; and which table a phone's locale reads (lib/core/locale_dates.dart).
void main() {
  tearDown(() => toldLocale = null);

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
      expect(dateLocaleOf(const Locale('en', 'US')), DateLocale.enUS);
      expect(dateLocaleOf(const Locale('en', 'CA')), DateLocale.enUS);
      expect(dateLocaleOf(const Locale('en', 'PH')), DateLocale.enUS);
      expect(dateLocaleOf(const Locale('en')), DateLocale.enUS);
    });

    test('any other English, and any other language, reads en-GB: the words are English either way', () {
      expect(dateLocaleOf(const Locale('en', 'GB')), DateLocale.enGB);
      expect(dateLocaleOf(const Locale('en', 'AU')), DateLocale.enGB);
      expect(dateLocaleOf(const Locale('en', 'IN')), DateLocale.enGB);
      expect(dateLocaleOf(const Locale('de', 'DE')), DateLocale.enGB);
      expect(dateLocaleOf(const Locale('es', 'US')), DateLocale.enGB);
    });

    test('nothing is told until the phone says, and then it is the phone’s', () {
      final day = DateTime(2026, 10, 9, 16, 5);
      expect(toldLocale, isNull);
      expect(toldDate(day, DateForm.yMMMMEEEEd), isNull);
      expect(toldDayMonth(day, DateForm.MMMd), isNull);
      expect(toldShortMonth(day), isNull);
      // Asked without a locale and with none told, a form is en-GB's.
      expect(localeDate(day, DateForm.yMMMMEEEEd), 'Friday 9 October 2026');

      useLocaleOf(const Locale('en', 'US'));
      expect(toldLocale, DateLocale.enUS);
      expect(toldDate(day, DateForm.yMMMMEEEEd), 'Friday, October 9, 2026');
      expect(localeDate(day, DateForm.yMMMMEEEEd), 'Friday, October 9, 2026');

      useLocaleOf(const Locale('en', 'GB'));
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
}
