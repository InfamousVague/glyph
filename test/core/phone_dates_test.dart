import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/locale_dates.dart';
import 'package:ghost_md/ai/support/stamp.dart' as stamp;
import 'package:ghost_md/core/phone_dates.dart';
import 'package:ghost_md/core/query/calendar.dart' show monthName;
import 'package:ghost_md/core/template.dart' as template;
import 'package:ghost_md/notes/when.dart';

/// A date in the phone's own language (docs/PARITY.md, Differs 9). Ghost.md's page asks its WebView
/// (`new Intl.DateTimeFormat(undefined, …)`), so a French phone's new note is named "vendredi 9 octobre 2026"; this
/// app wrote English whatever the phone spoke. It asks the phone's own ICU for the words now
/// (lib/core/phone_dates.dart) and writes every form from them (lib/core/locale_dates.dart).
///
/// Held two ways:
/// - what an Android phone answered for thirty-nine languages (test/core/fixtures/phone_dates.json, read from the
///   emulator by lib/main_dates.dart) is written here in every form at four moments, and held to what a browser's
///   own `Intl` writes for the same language and options (test/core/fixtures/intl_dates.json, tool/intl_dates.mjs),
///   part for part. The two carry different versions of CLDR, and where those differ the two differ: each such
///   form is named below, and the test fails should one of them come to agree, so the list stays what is true;
/// - the seam: a phone that answers is asked once and its words kept, an American or a British one is not asked,
///   and one with no answer leaves the tables as they were.
void main() {
  tearDown(() {
    toldLocale = null;
    toldWords = null;
    toldLanguage = null;
  });

  final phone = (jsonDecode(File('test/core/fixtures/phone_dates.json').readAsStringSync()) as Map<String, dynamic>)['locales'] as Map<String, dynamic>;
  final web = jsonDecode(File('test/core/fixtures/intl_dates.json').readAsStringSync()) as Map<String, dynamic>;
  final moments = [
    for (final key in (web['dates'] as List).cast<String>())
      () {
        final n = key.split('-').map(int.parse).toList();
        return DateTime(n[0], n[1] + 1, n[2], n[3], n[4], n[5]);
      }(),
  ];
  final locales = web['locales'] as Map<String, dynamic>;

  /// Every form of `tag` that this app, writing from the phone's words, writes otherwise than the browser.
  Map<String, String> differing(String tag) {
    final words = DateWords.fromJson(phone[tag]);
    expect(words, isNotNull, reason: '$tag was answered whole');
    toldLocale = DateLocale.enGB;
    toldWords = words;
    final forms = (locales[tag] as Map<String, dynamic>)['forms'] as Map<String, dynamic>;
    final out = <String, String>{};
    for (final form in DateForm.values) {
      final set = forms[form.name] as Map<String, dynamic>;
      for (var i = 0; i < moments.length; i += 1) {
        final wanted = [for (final part in (set['parts'] as List)[i] as List) '${(part as List)[0]}:${part[1]}'].join('|');
        final got = [for (final part in localeDateParts(moments[i], form)) '${part.type}:${part.value}'].join('|');
        final text = localeDate(moments[i], form);
        if (got != wanted || text != (set['text'] as List)[i]) {
          out[form.name] = '$text  /  ${(set['text'] as List)[i]}';
          break;
        }
      }
    }
    return out;
  }

  test('both fixtures have the same languages, and every one was answered whole', () {
    expect(phone.keys.toSet(), locales.keys.toSet());
    expect(phone.length, greaterThanOrEqualTo(39));
    for (final tag in phone.keys) {
      expect(DateWords.fromJson(phone[tag]), isNotNull, reason: tag);
    }
  });

  // Where this app, writing from the emulator's Android 16 words, is not the browser's (Node's ICU 78, CLDR 48)
  // letter for letter. Every one is the two CLDRs, or a day's finer periods:
  const known = <String, Set<String>>{
    // "4 Uhr PM" on the phone, "4 PM" in the newer CLDR.
    'de-DE': {'dayPeriod'},
    // The space inside "p. m." is another kind of space.
    'es-ES': {'dayPeriod'},
    // "4 da tarde" on the phone, "4 p.m." in the newer CLDR.
    'pt-PT': {'dayPeriod'},
    // The meridiem in full on the phone, short in the newer CLDR.
    'fa-IR': {'dayPeriod'},
    // January is spelt another way in the newer CLDR.
    'bn-BD': {'MMMMd', 'yMMMMd', 'MMMMEEEEd', 'yMMMMEEEEd', 'yMMMM'},
    // The short weekday is longer in the newer CLDR ("ศ." against "ศุกร์"), and the meridiem is "PM" there.
    'th-TH': {'E', 'MMMEd', 'yMMMEd', 'dayPeriod'},
    // The short weekday again: "Th 6" against "Thứ 6".
    'vi-VN': {'E', 'MMMEd', 'yMMMEd'},
    // A space before the weekday on the phone and none in the newer CLDR; and Taiwan's clock names the part of
    // the day more finely than morning and afternoon (凌晨 at half past midnight), which this app writes as the
    // two meridiems (`B` read as `a`: lib/core/locale_dates.dart).
    'zh-TW': {'MMMEd', 'yMMMEd', 'MMMMEEEEd', 'yMMMMEEEEd', 'medShort', 'whole'},
  };

  for (final tag in locales.keys) {
    test('$tag is written as a browser writes it, part for part, in every form${known.containsKey(tag) ? ' but ${known[tag]!.length}' : ''}', () {
      expect(differing(tag).keys.toSet(), known[tag] ?? const <String>{}, reason: differing(tag).toString());
    });
  }

  test('a Thai phone counts its years as its calendar does, and a Persian one is written in the Gregorian calendar', () {
    toldLocale = DateLocale.enGB;
    toldWords = DateWords.fromJson(phone['th-TH']);
    expect(localeDate(DateTime(2026, 10, 9), DateForm.yMMMMd), '9 ตุลาคม 2569');
    expect(localeDate(DateTime(2026, 10, 9), DateForm.y), 'พ.ศ. 2569');
    // The browser writes 17 Mehr 1405 there; this app has no Persian calendar, and says so in its file.
    expect((locales['fa-IR'] as Map)['calendar'], 'persian');
    toldWords = DateWords.fromJson(phone['fa-IR']);
    expect(localeDate(DateTime(2026, 10, 9), DateForm.yMMMMd), '۹ اکتبر ۲۰۲۶');
  });

  test('a pattern\'s quoted words are written as they are, and its figures in the locale\'s own', () {
    toldLocale = DateLocale.enGB;
    toldWords = DateWords.fromJson(phone['es-ES']);
    expect(localeDate(DateTime(2026, 10, 9), DateForm.yMMMMEEEEd), 'viernes, 9 de octubre de 2026');
    expect([for (final part in localeDateParts(DateTime(2026, 10, 9), DateForm.yMMMMd)) part.type], ['day', 'literal', 'month', 'literal', 'year']);
    toldWords = DateWords.fromJson(phone['ar-EG']);
    expect(localeDate(DateTime(2026, 10, 9, 16, 5), DateForm.Hm23), '١٦:٠٥');
    toldWords = DateWords.fromJson(phone['fi-FI']);
    // A month as a date wears it, and standing alone.
    expect(localeDate(DateTime(2026, 10, 9), DateForm.MMMMd), '9. lokakuuta');
    expect(localeDate(DateTime(2026, 10, 9), DateForm.yMMMM), 'lokakuu 2026');
  });

  group('the places that named a day or a month in English name it in the phone\'s language', () {
    final friday = DateTime(2026, 10, 9, 16, 5);
    setUp(() {
      useLocaleOf('fr', 'FR');
      toldWords = DateWords.fromJson(phone['fr-FR']);
    });

    test('a template\'s date', () {
      expect(template.weekdayName(friday), 'vendredi');
      expect(template.shortWeekday(friday), 'ven.');
      expect(template.longMonth(friday), 'octobre');
      expect(template.shortMonth(friday), 'oct.');
      expect(template.clockTime(friday), '16:05');
      // Moment's tokens (`{{date:…}}`): the names, and the ordinal as a language that is not English writes it.
      expect(template.formatStamp(friday, 'dddd Do MMMM YYYY'), 'vendredi 9. octobre 2026');
      expect(template.formatStamp(friday, 'ddd D MMM, h:mm A'), 'ven. 9 oct., 4:05 PM');
    });

    test('an English phone keeps "9th", and its own meridiem', () {
      useLocaleOf('en', 'AU');
      toldWords = DateWords.fromJson(phone['en-AU']);
      expect(template.formatStamp(friday, 'dddd Do MMMM, h:mm a'), 'Friday 9th October, 4:05 pm');
      expect(template.formatStamp(friday, 'h A'), '4 PM');
    });

    test('a card\'s day, a calendar\'s month, a journal\'s time', () {
      final now = DateTime(2026, 10, 12, 9).millisecondsSinceEpoch;
      expect(when(friday.millisecondsSinceEpoch, now), 'vendredi');
      expect(when(DateTime(2026, 9, 1).millisecondsSinceEpoch, now), '1 septembre');
      expect(monthName('2026-10'), 'octobre 2026');
      expect(stamp.weekdayName(friday), 'vendredi');
      expect(stamp.longDate(friday), 'vendredi 9 octobre 2026');
    });

    test('where the page asks for English by name, the words stay English', () {
      expect(stamp.englishWeekday(friday), 'Friday');
      expect(stamp.monthName(10), 'October');
    });
  });

  group('the seam', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('test/dates');
    final asked = <Object?>[];
    void answer(Object? Function(MethodCall call) with_) => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
          asked.add(call.arguments);
          return with_(call);
        });
    setUp(asked.clear);
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    test('a French phone is asked once, for every form by its skeleton, and its dates are French', () async {
      answer((call) => phone['fr-FR']);
      await usePhoneDates('fr', 'FR', channel: channel);
      expect(asked, hasLength(1));
      final skeletons = ((asked.single as Map)['skeletons'] as Map).cast<String, String>();
      expect(skeletons.keys.toSet(), {for (final form in DateForm.values) if (form != DateForm.medShort) form.name});
      expect(skeletons['hm2'], 'jjmm');
      expect((asked.single as Map).containsKey('locale'), isFalse, reason: 'the phone\'s own language, not one named');
      final day = DateTime(2026, 10, 9, 16, 5);
      expect(toldDate(day, DateForm.yMMMMEEEEd), 'vendredi 9 octobre 2026');
      expect(toldDate(day, DateForm.MMMdhm), '9 oct., 16:05');
      expect(toldDate(day, DateForm.EEEE), 'vendredi');
      expect(toldMonth(day), 'octobre');
      expect(toldShortMonth(day), 'oct.');
      expect(toldLanguage, 'fr');
    });

    test('an American and a British phone are not asked: their tables are the page\'s own', () async {
      answer((call) => phone['fr-FR']);
      await usePhoneDates('en', 'US', channel: channel);
      expect(toldWords, isNull);
      expect(toldDate(DateTime(2026, 10, 9, 16, 5), DateForm.yMMMMEEEEd), 'Friday, October 9, 2026');
      await usePhoneDates('en', 'GB', channel: channel);
      expect(toldWords, isNull);
      expect(toldDate(DateTime(2026, 10, 9, 16, 5), DateForm.yMMMMEEEEd), 'Friday 9 October 2026');
      expect(asked, isEmpty);
    });

    test('an Australian phone is asked: its clock is not a British one', () async {
      answer((call) => phone['en-AU']);
      await usePhoneDates('en', 'AU', channel: channel);
      expect(toldDate(DateTime(2026, 10, 9, 16, 5), DateForm.MMMdhm), '9 Oct, 4:05 pm');
    });

    test('a phone with no answer, a wrong one, or none in time leaves the tables as they were', () async {
      await usePhoneDates('de', 'DE', channel: channel);
      expect(toldWords, isNull, reason: 'no such channel');
      expect(toldDate(DateTime(2026, 10, 9, 16, 5), DateForm.yMMMMEEEEd), 'Friday 9 October 2026');
      answer((call) => {'patterns': <String, String>{}, 'months': <String>[]});
      await usePhoneDates('de', 'DE', channel: channel);
      expect(toldWords, isNull, reason: 'not whole');
      answer((call) => throw PlatformException(code: 'dates'));
      await usePhoneDates('de', 'DE', channel: channel);
      expect(toldWords, isNull);
    });

    test('a language asked after another forgets the other\'s words', () async {
      answer((call) => phone['fr-FR']);
      await usePhoneDates('fr', 'FR', channel: channel);
      expect(toldWords, isNotNull);
      await usePhoneDates('en', 'US', channel: channel);
      expect(toldWords, isNull);
    });
  });
}
