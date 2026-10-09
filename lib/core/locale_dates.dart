// ignore_for_file: constant_identifier_names

/// A date in the words the phone's own language writes it with. The page asks the device for every date a person
/// reads (`new Intl.DateTimeFormat(undefined, …)`, `toLocaleDateString(undefined, …)`: core/stamp.ts and the rest),
/// so on a phone set to American English a new note's name for the day is "Friday, October 9, 2026" and an update
/// is named "Oct 9, 04:05 PM", where a British one has "Friday 9 October 2026" and "9 Oct, 16:05". This app's words
/// are English, so there are two tables, en-US and en-GB, each a pattern for every set of options the page asks
/// with, and each answers what the page's own WebView answered, part for part
/// (test/core/fixtures/locale_dates.json, Chrome 133 on the emulator; test/core/locale_dates_test.dart holds every
/// form to it at four moments).
///
/// **Which table.** English of the United States, Canada and the Philippines, and English with no country said, is
/// en-US. Anything else is en-GB, another language included: the words are English either way, and the day before
/// the month and a 24-hour clock are how most of the world writes them.
///
/// **Until the phone has said.** Nothing is told until [useLocaleOf] hears the phone's language and country
/// (lib/main.dart, once, at launch; as two words and not a `Locale`, so this file imports nothing and the cores that
/// read it stay pure, which test/book_core/journal_test.dart holds them to). Until then [toldDate] and [toldDayMonth] answer null, and each place that words a date writes what
/// it wrote before there was a table, so a test reads the same whatever machine runs it. A test of the phone's
/// words tells a locale itself and takes it back in its `tearDown` (`toldLocale = null`).
///
/// A form is named by its CLDR skeleton, as the fixture names it and as `package:intl` names its own, which is why
/// the names are not lowerCamelCase. What each is asked with on the page is beside it below.
///
/// What a table does not say: a weekday's name, a month's name in full and the 24-hour clock ("16:05",
/// [DateForm.Hm23]) are the same in both, so a place that writes only those reads no table. The space before "PM" is
/// the browser's two ways, as the fixture has them: a narrow no-break space (U+202F) among the parts
/// ([localeDateParts], `formatToParts`), and a plain space in the words whole ([localeDate], `format`). And en-GB's
/// meridiem is lower case, "4 pm".
library;

/// The two ways this app writes a date.
enum DateLocale { enUS, enGB }

/// A set of options the page asks `Intl.DateTimeFormat` with, by its skeleton.
enum DateForm {
  /// `{ day: 'numeric' }`: "9".
  d,

  /// `{ year: 'numeric' }`: "2026".
  y,

  /// `{ weekday: 'short' }`: "Fri".
  E,

  /// `{ weekday: 'long' }`: "Friday".
  EEEE,

  /// `{ day: 'numeric', month: 'short' }`: "Oct 9", "9 Oct"; September is "Sep" and "Sept".
  MMMd,

  /// `{ day: 'numeric', month: 'long' }`: "October 9", "9 October".
  MMMMd,

  /// `{ day: 'numeric', month: 'short', year: 'numeric' }`: "Oct 9, 2026", "9 Oct 2026".
  yMMMd,

  /// `{ day: 'numeric', month: 'long', year: 'numeric' }`: "October 9, 2026", "9 October 2026".
  yMMMMd,

  /// `{ weekday: 'short', day: 'numeric', month: 'short' }`: "Fri, Oct 9", "Fri, 9 Oct".
  MMMEd,

  /// The same with `year: 'numeric'`: "Fri, Oct 9, 2026", "Fri, 9 Oct 2026".
  yMMMEd,

  /// `{ weekday: 'long', month: 'long', day: 'numeric' }`: "Friday, October 9", "Friday 9 October".
  MMMMEEEEd,

  /// The same with `year: 'numeric'`: "Friday, October 9, 2026", "Friday 9 October 2026".
  yMMMMEEEEd,

  /// `{ month: 'long', year: 'numeric' }`: "October 2026" in both.
  yMMMM,

  /// `{ hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }`: "16:05" in both, "00:30" at half past midnight.
  Hm23,

  /// `{ hour: '2-digit', minute: '2-digit' }`: "04:05 PM", "16:05".
  hm2,

  /// `{ hour: 'numeric', minute: '2-digit' }`: "4:05 PM", "16:05"; in the morning "9:07 AM" and "9:07".
  hm,

  /// `{ month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }`: "Oct 9, 04:05 PM", "9 Oct, 16:05".
  MMMdhm2,

  /// `{ month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }`: "Sep 28, 9:07 AM", "28 Sept, 9:07".
  MMMdhm,

  /// `{ dateStyle: 'medium', timeStyle: 'short' }`: "Oct 9, 2026, 4:05 PM", "9 Oct 2026, 16:05".
  medShort,

  /// A bare `toLocaleString()`: "10/9/2026, 4:05:09 PM", "09/10/2026, 16:05:09".
  whole,

  /// `{ hour: 'numeric', hour12: true }`: "4 PM", "4 pm".
  dayPeriod,
}

/// One part of a date as `formatToParts` answers it: its type ("day", "month", "year", "weekday", "hour", "minute",
/// "second", "dayPeriod", "literal") and its words.
typedef DatePart = ({String type, String value});

/// The phone's way of writing a date, or null until [useLocaleOf] has heard it.
DateLocale? toldLocale;

const Set<String> _monthFirstCountries = {'US', 'CA', 'PH'};

/// Which table a locale reads, by its language ("en") and its country ("US", or none): the rule is the file's.
DateLocale dateLocaleOf(String language, [String? country]) {
  final where = country?.toUpperCase();
  final american = language.toLowerCase() == 'en' && (where == null || where.isEmpty || _monthFirstCountries.contains(where));
  return american ? DateLocale.enUS : DateLocale.enGB;
}

/// Hears the phone's locale, its `languageCode` and `countryCode`: every date after this is in its words.
void useLocaleOf(String language, [String? country]) => toldLocale = dateLocaleOf(language, country);

const List<String> _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// What one locale writes: its short months, its meridiems, and a pattern for each form. A pattern's letters are
/// CLDR's: `y` the year, `M` and `MM` the month in figures, `MMM` and `MMMM` its name, `d` and `dd` the day, `EEE`
/// and `EEEE` the weekday, `h` and `hh` the hour of a 12-hour clock, `H` and `HH` of a 24-hour one, `mm`, `ss`, and
/// `a` the meridiem. Anything else is written as it is, a literal part.
class _Words {
  const _Words({required this.shortMonths, required this.am, required this.pm, required this.patterns});
  final List<String> shortMonths;
  final String am, pm;
  final Map<DateForm, String> patterns;
}

const Map<DateLocale, _Words> _tables = {
  DateLocale.enUS: _Words(
    shortMonths: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
    am: 'AM',
    pm: 'PM',
    patterns: {
      DateForm.d: 'd',
      DateForm.y: 'y',
      DateForm.E: 'EEE',
      DateForm.EEEE: 'EEEE',
      DateForm.MMMd: 'MMM d',
      DateForm.MMMMd: 'MMMM d',
      DateForm.yMMMd: 'MMM d, y',
      DateForm.yMMMMd: 'MMMM d, y',
      DateForm.MMMEd: 'EEE, MMM d',
      DateForm.yMMMEd: 'EEE, MMM d, y',
      DateForm.MMMMEEEEd: 'EEEE, MMMM d',
      DateForm.yMMMMEEEEd: 'EEEE, MMMM d, y',
      DateForm.yMMMM: 'MMMM y',
      DateForm.Hm23: 'HH:mm',
      DateForm.hm2: 'hh:mm\u202fa',
      DateForm.hm: 'h:mm\u202fa',
      DateForm.MMMdhm2: 'MMM d, hh:mm\u202fa',
      DateForm.MMMdhm: 'MMM d, h:mm\u202fa',
      DateForm.medShort: 'MMM d, y, h:mm\u202fa',
      DateForm.whole: 'M/d/y, h:mm:ss\u202fa',
      DateForm.dayPeriod: 'h\u202fa',
    },
  ),
  DateLocale.enGB: _Words(
    shortMonths: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'],
    am: 'am',
    pm: 'pm',
    patterns: {
      DateForm.d: 'd',
      DateForm.y: 'y',
      DateForm.E: 'EEE',
      DateForm.EEEE: 'EEEE',
      DateForm.MMMd: 'd MMM',
      DateForm.MMMMd: 'd MMMM',
      DateForm.yMMMd: 'd MMM y',
      DateForm.yMMMMd: 'd MMMM y',
      DateForm.MMMEd: 'EEE, d MMM',
      DateForm.yMMMEd: 'EEE, d MMM y',
      DateForm.MMMMEEEEd: 'EEEE d MMMM',
      DateForm.yMMMMEEEEd: 'EEEE d MMMM y',
      DateForm.yMMMM: 'MMMM y',
      DateForm.Hm23: 'HH:mm',
      DateForm.hm2: 'HH:mm',
      DateForm.hm: 'H:mm',
      DateForm.MMMdhm2: 'd MMM, HH:mm',
      DateForm.MMMdhm: 'd MMM, H:mm',
      DateForm.medShort: 'd MMM y, HH:mm',
      DateForm.whole: 'dd/MM/y, H:mm:ss',
      DateForm.dayPeriod: 'h\u202fa',
    },
  ),
};

/// A pattern's runs: each field's letters together, and what stands between two fields.
final RegExp _run = RegExp(r'([A-Za-z])\1*|[^A-Za-z]+');
final Map<String, List<String>> _runs = {};

String _two(int n) => n.toString().padLeft(2, '0');
int _hour12(DateTime at) => at.hour % 12 == 0 ? 12 : at.hour % 12;

DatePart _part(String run, DateTime at, _Words words) => switch (run) {
      'y' => (type: 'year', value: '${at.year}'),
      'M' => (type: 'month', value: '${at.month}'),
      'MM' => (type: 'month', value: _two(at.month)),
      'MMM' => (type: 'month', value: words.shortMonths[at.month - 1]),
      'MMMM' => (type: 'month', value: _months[at.month - 1]),
      'd' => (type: 'day', value: '${at.day}'),
      'dd' => (type: 'day', value: _two(at.day)),
      'EEE' => (type: 'weekday', value: _weekdays[at.weekday - 1].substring(0, 3)),
      'EEEE' => (type: 'weekday', value: _weekdays[at.weekday - 1]),
      'h' => (type: 'hour', value: '${_hour12(at)}'),
      'hh' => (type: 'hour', value: _two(_hour12(at))),
      'H' => (type: 'hour', value: '${at.hour}'),
      'HH' => (type: 'hour', value: _two(at.hour)),
      'mm' => (type: 'minute', value: _two(at.minute)),
      'ss' => (type: 'second', value: _two(at.second)),
      'a' => (type: 'dayPeriod', value: at.hour < 12 ? words.am : words.pm),
      _ => (type: 'literal', value: run),
    };

/// [at] in [form] as `formatToParts` answers it, in [locale]'s words: the phone's where none is given, and en-GB's
/// where the phone has not said. [at]'s own fields are read, so a wall clock kept in UTC reads as the clock it is.
List<DatePart> localeDateParts(DateTime at, DateForm form, [DateLocale? locale]) {
  final words = _tables[locale ?? toldLocale ?? DateLocale.enGB]!;
  final pattern = words.patterns[form]!;
  final runs = _runs[pattern] ??= [for (final found in _run.allMatches(pattern)) found.group(0)!];
  return [for (final run in runs) _part(run, at, words)];
}

/// [at] in [form] as `format` answers it (the same [locale] rule as [localeDateParts]): the parts together, the
/// narrow space before a meridiem a plain one.
String localeDate(DateTime at, DateForm form, [DateLocale? locale]) => localeDateParts(at, form, locale).map((part) => part.value).join().replaceAll('\u202f', ' ');

/// The day and the month of [form] alone, in the locale's order with a space between: "Oct 9", "9 Oct". What the
/// page's `stamp`, `timeLabel` and `meetingTitle` keep of a date's parts, the locale's own literals dropped.
String localeDayMonth(DateTime at, DateForm form, [DateLocale? locale]) =>
    localeDateParts(at, form, locale).where((part) => part.type == 'day' || part.type == 'month').map((part) => part.value).join(' ');

/// [at] in [form] in the phone's words, or null where the phone has not said: the caller then writes what it
/// always wrote.
String? toldDate(DateTime at, DateForm form) => toldLocale == null ? null : localeDate(at, form);

/// [localeDayMonth] in the phone's words, or null where the phone has not said.
String? toldDayMonth(DateTime at, DateForm form) => toldLocale == null ? null : localeDayMonth(at, form);

/// The month's short name alone in the phone's words, "Sep" or "Sept" (`{ month: 'short' }`), or null where the
/// phone has not said.
String? toldShortMonth(DateTime at) => toldLocale == null ? null : _tables[toldLocale]!.shortMonths[at.month - 1];
