import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'core/locale_dates.dart';
import 'core/phone_dates.dart';

/// The phone's words for a date, alone, with no library under them: `flutter run -t lib/main_dates.dart` on an
/// Android phone. For each of a list of languages the phone is asked what its own ICU writes a date from
/// (`ghost_md/dates`, android/…/ghost_md/Dates.kt, with the language named, so the phone's own language is never
/// changed to look), and every form the app writes is written from the answer at one moment, down the screen.
///
/// What was answered is also said in the log, whole, in base64 between `GHOST_DATES<` and `>GHOST_DATES`, a line at
/// a time: test/core/fixtures/phone_dates.json is that, and test/core/phone_dates_test.dart holds this app's writing of it
/// to what a browser's own `Intl` writes for the same languages (tool/intl_dates.mjs).
const List<String> datesLookedAt = [
  'en-US', 'en-GB', 'en-AU', 'en-CA', 'en-IN', 'fr-FR', 'fr-CA', 'de-DE', 'es-ES', 'es-MX', 'pt-BR', 'pt-PT', 'it-IT', 'nl-NL', 'sv-SE', 'nb-NO', 'da-DK', //
  'fi-FI', 'pl-PL', 'cs-CZ', 'hu-HU', 'ro-RO', 'el-GR', 'ru-RU', 'uk-UA', 'tr-TR', 'he-IL', 'ar-EG', 'ar-SA', 'fa-IR', 'hi-IN', 'bn-BD', 'th-TH', 'vi-VN', //
  'id-ID', 'ja-JP', 'ko-KR', 'zh-CN', 'zh-TW',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ghost_md/dates');
  final skeletons = {for (final MapEntry(key: form, value: skeleton) in dateSkeletons.entries) form.name: skeleton};
  final answers = <String, Object?>{};
  for (final tag in datesLookedAt) {
    try {
      answers[tag] = await channel.invokeMethod<Object?>('words', {'skeletons': skeletons, 'locale': tag});
    } catch (failure) {
      answers[tag] = null;
      debugPrint('[dates] $tag was not answered: $failure');
    }
  }
  // In base64: a log's line is cut by its bytes, which would cut a letter of another alphabet in two.
  final whole = base64.encode(utf8.encode(jsonEncode(answers)));
  debugPrint('GHOST_DATES<');
  for (var at = 0; at < whole.length; at += 700) {
    debugPrint('GHOST_DATES ${whole.substring(at, at + 700 > whole.length ? whole.length : at + 700)}');
  }
  debugPrint('>GHOST_DATES');

  final at = DateTime(2026, 10, 9, 16, 5, 9);
  final lines = <String>[];
  toldLocale = DateLocale.enGB;
  for (final tag in datesLookedAt) {
    final words = DateWords.fromJson(answers[tag]);
    if (words == null) {
      lines.add('$tag: no words');
      continue;
    }
    toldWords = words;
    lines.add('$tag  ${localeDate(at, DateForm.yMMMMEEEEd)}  ·  ${localeDate(at, DateForm.MMMdhm)}  ·  ${localeDate(at, DateForm.yMMMM)}  ·  ${localeDate(at, DateForm.MMMEd)}  ·  ${localeDate(at, DateForm.medShort)}');
  }
  toldWords = null;
  // The phone's own, as the app asks for it at launch.
  final own = await phoneDateWords();
  lines.insert(0, 'this phone: ${own?.tag ?? 'no words'}');
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 48, 12, 12),
          child: ListView(children: [for (final line in lines) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(line, style: const TextStyle(color: Color(0xFF111111), fontSize: 11, height: 1.25)))]),
        ),
      ),
    ),
  );
}
