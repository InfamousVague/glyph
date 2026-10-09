/// Whether a long date is written month first. The page asks the phone (`new Intl.DateTimeFormat(undefined, …)`,
/// core/stamp.ts), so on a phone set to American English a new note's name for the day is "Friday, October 9, 2026"
/// and a template's `{{date}}` "Friday, October 9", where a British one has "Friday, 9 October 2026" and
/// "Friday 9 October". This app's words are English, so the one thing read of the locale is that order: the
/// English of the United States, Canada and the Philippines, and English with no country said, put the month first.
///
/// Off until [useDayOrderOf] is told the phone's locale (lib/main.dart), so a test reads the day first whatever
/// machine runs it.
library;

import 'dart:ui' show Locale;

bool monthFirst = false;

const Set<String> _monthFirstCountries = {'US', 'CA', 'PH'};

/// Reads the order from the phone's locale.
void useDayOrderOf(Locale locale) {
  final country = locale.countryCode;
  monthFirst = locale.languageCode == 'en' && (country == null || country.isEmpty || _monthFirstCountries.contains(country));
}

/// "Friday, October 9" or "Friday 9 October" (`longDay`).
String longDayWords(String weekday, int day, String month) => monthFirst ? '$weekday, $month $day' : '$weekday $day $month';

/// "Friday, October 9, 2026" or "Friday, 9 October 2026" (`longDate`).
String longDateWords(String weekday, int day, String month, int year) => monthFirst ? '$weekday, $month $day, $year' : '$weekday, $day $month $year';
