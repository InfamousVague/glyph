/// The phone's own words for a date: what lib/core/locale_dates.dart writes every date from on a phone whose
/// language is not one of its two English tables. The Dart half of `ghost_md/dates`
/// (android/…/ghost_md/Dates.kt), which asks Android's ICU for the locale's patterns and names.
///
/// Ghost.md's page never needed this: its WebView's `Intl.DateTimeFormat(undefined, …)` reads the same CLDR in the
/// phone's language by itself. A Flutter app draws its own text, so the phone is asked once, as the app starts, and
/// the answer is kept ([toldWords]).
///
/// - A phone in American or British English is not asked: those two are the tables the page's own WebView was read
///   for, part for part (test/core/fixtures/locale_dates.json), and the app's start waits for nothing.
/// - Any other is asked, and the app's first frame waits for the answer a moment ([phoneDatesWait]) and no longer:
///   an answer that comes later is kept when it comes, and the dates drawn before it are the table's.
/// - A phone with no such channel (an iPhone, a Mac) answers nothing, and the tables are read as before.
///
/// The seam a test fakes is the channel ([phoneDateWords]'s `channel`), or [toldWords] itself.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'locale_dates.dart';

const MethodChannel _dates = MethodChannel('ghost_md/dates');

/// How long the app's start waits for the phone's words.
const Duration phoneDatesWait = Duration(milliseconds: 400);

/// What the phone is asked with: each form's skeleton, by the form's name.
Map<String, String> get _skeletons => {for (final MapEntry(key: form, value: skeleton) in dateSkeletons.entries) form.name: skeleton};

/// The words of the phone's locale, or of the one named by `locale` (a tag, "fr-FR"); null where the phone has no
/// answer or not a whole one.
Future<DateWords?> phoneDateWords({String? locale, MethodChannel channel = _dates}) async {
  try {
    final answer = await channel.invokeMethod<Object?>('words', {'skeletons': _skeletons, 'locale': ?locale});
    return DateWords.fromJson(answer);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// Whether a phone of this language and country is written from one of this file's own tables, and so not asked.
bool readsOwnTable(String language, [String? country]) {
  final where = country?.toUpperCase();
  return language.toLowerCase() == 'en' && (where == 'US' || where == 'GB');
}

/// Hears the phone's locale ([useLocaleOf]) and, where it is not a table's, asks the phone for its words and keeps
/// them. Completes when they are kept or after [wait], whichever is first; never fails.
Future<void> usePhoneDates(String language, String? country, {MethodChannel channel = _dates, Duration wait = phoneDatesWait}) async {
  useLocaleOf(language, country);
  toldWords = null;
  if (readsOwnTable(language, country)) return;
  final asked = phoneDateWords(channel: channel).then<void>((words) {
    if (words != null) toldWords = words;
  }, onError: (Object _) {});
  await asked.timeout(wait, onTimeout: () {});
}
