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
/// **Another language, and English of another country.** The page's `undefined` is the phone's language, whatever
/// it is: a French phone names the day "vendredi 9 octobre 2026" and an Australian one writes "4:05 pm". Those
/// words are not tables here. The phone is asked for them once, at launch (lib/core/phone_dates.dart: Android's
/// own ICU, which holds the same CLDR a WebView's `Intl` reads from), and answers a [DateWords]: for each form the
/// pattern its pattern generator makes of the skeleton the page's options come to, the names of its months and
/// days as a date wears them and as they stand alone, its meridiems, its figures, and a year's offset where its
/// calendar counts from another year (the Buddhist one a Thai phone keeps). [toldWords] holds it, and every form
/// is then written from it. The two English tables stay as they are for the two locales the fixture was read on.
///
/// **Which table**, where the phone has given no words (an iPhone, a Mac, a test). English of the United States,
/// Canada and the Philippines, and English with no country said, is en-US. Anything else is en-GB: the words are
/// English either way, and the day before the month and a 24-hour clock are how most of the world writes them.
///
/// **What is not carried.** A phone whose language keeps a calendar with months of its own (the Persian one, in
/// Iran and Afghanistan) is written here in the Gregorian calendar with that language's names and figures, where
/// the page writes the other calendar's date. And the phone's CLDR is its Android's, the page's its WebView's:
/// where two versions differ on a comma, so do the two apps.
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
void useLocaleOf(String language, [String? country]) {
  toldLocale = dateLocaleOf(language, country);
  toldLanguage = language.toLowerCase();
}

/// The phone's language ("en", "fr"), or null until [useLocaleOf] has heard it
/// (`new Intl.DateTimeFormat().resolvedOptions().locale.split('-')[0]`).
String? toldLanguage;

/// The meridiem of [at] as the phone's language says it on a 12-hour clock, or null where the phone has not said
/// (the `dayPeriod` part of `{ hour: 'numeric', hour12: true }`).
String? toldMeridiem(DateTime at) {
  if (toldLocale == null) return null;
  for (final part in localeDateParts(at, DateForm.dayPeriod)) {
    if (part.type == 'dayPeriod') return part.value;
  }
  return null;
}

const List<String> _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// What one locale writes: a pattern for each form, and the words the patterns' letters stand for. A pattern's
/// letters are CLDR's: `y` the year and `G` its era, `M` and `MM` the month in figures, `MMM` and `MMMM` its name
/// as a date wears it, `LLL` and `LLLL` its name standing alone, `d` and `dd` the day, `EEE` and `EEEE` the weekday
/// (`ccc` and `cccc` alone), `h` and `hh` the hour of a 12-hour clock (`K` from 0), `H` and `HH` of a 24-hour one
/// (`k` from 1), `m` and `mm`, `s` and `ss`, and `a` the meridiem (`b` and `B`, a day's finer periods, are written
/// as the meridiem too). Words between two `'` are written as they are, as is anything that is not a letter.
///
/// The two English tables are consts of this file. Any other is what the phone answered
/// ([DateWords.fromJson], lib/core/phone_dates.dart).
class DateWords {
  const DateWords({
    required this.patterns,
    this.months = _months,
    required this.shortMonths,
    List<String>? monthsAlone,
    List<String>? shortMonthsAlone,
    this.weekdays = _weekdays,
    this.shortWeekdays = _shortWeekdays,
    List<String>? weekdaysAlone,
    List<String>? shortWeekdaysAlone,
    required this.am,
    required this.pm,
    this.digits = _latin,
    this.era = '',
    this.yearOffset = 0,
    this.tag,
  })  : monthsAlone = monthsAlone ?? months,
        shortMonthsAlone = shortMonthsAlone ?? shortMonths,
        weekdaysAlone = weekdaysAlone ?? weekdays,
        shortWeekdaysAlone = shortWeekdaysAlone ?? shortWeekdays;

  /// The locale these are the words of, as a tag ("fr-FR"), where the phone said.
  final String? tag;

  /// Each form's pattern.
  final Map<DateForm, String> patterns;

  /// January to December: in full and short, as a date wears them and as they stand alone.
  final List<String> months, shortMonths, monthsAlone, shortMonthsAlone;

  /// Monday to Sunday, the same four ways.
  final List<String> weekdays, shortWeekdays, weekdaysAlone, shortWeekdaysAlone;

  final String am, pm;

  /// The ten figures, nought first: "0123456789", or the locale's own ("٠١٢٣٤٥٦٧٨٩").
  final String digits;

  /// The era's name, for a pattern that writes one (`G`), and what the calendar's year is ahead of the Gregorian
  /// one by (543 in the Buddhist calendar).
  final String era;
  final int yearOffset;

  /// What the phone answered (android/…/ghost_md/Dates.kt `words`), or null where the answer is not whole: a form
  /// with no pattern, or a list of names that is not twelve or seven long.
  static DateWords? fromJson(Object? json) {
    if (json is! Map) return null;
    List<String>? names(String key, int count) {
      final list = json[key];
      if (list is! List || list.length != count || list.any((name) => name is! String)) return null;
      return list.cast<String>();
    }

    final said = json['patterns'];
    if (said is! Map) return null;
    final patterns = <DateForm, String>{};
    for (final form in DateForm.values) {
      final pattern = said[form.name];
      if (pattern is! String || pattern.isEmpty) return null;
      patterns[form] = pattern;
    }
    final months = names('months', 12), shortMonths = names('shortMonths', 12);
    final weekdays = names('weekdays', 7), shortWeekdays = names('shortWeekdays', 7);
    final am = json['am'], pm = json['pm'], digits = json['digits'], era = json['era'], offset = json['yearOffset'], tag = json['locale'];
    if (months == null || shortMonths == null || weekdays == null || shortWeekdays == null || am is! String || pm is! String) return null;
    return DateWords(
      tag: tag is String ? tag : null,
      patterns: patterns,
      months: months,
      shortMonths: shortMonths,
      monthsAlone: names('monthsAlone', 12),
      shortMonthsAlone: names('shortMonthsAlone', 12),
      weekdays: weekdays,
      shortWeekdays: shortWeekdays,
      weekdaysAlone: names('weekdaysAlone', 7),
      shortWeekdaysAlone: names('shortWeekdaysAlone', 7),
      am: am,
      pm: pm,
      digits: digits is String && digits.runes.length == 10 ? digits : _latin,
      era: era is String ? era : '',
      yearOffset: offset is int ? offset : 0,
    );
  }
}

const String _latin = '0123456789';
const List<String> _shortWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The phone's own words, once it has given them (lib/core/phone_dates.dart): another language than English, or
/// English of a country that is neither table's. Null where it gave none, and the tables are read.
DateWords? toldWords;

/// What the forms are written from now, for whoever keeps something made of a date's words: another object when
/// the phone's words, or the table, are other than they were.
Object? get toldDates => toldWords ?? toldLocale;

/// The skeleton each form's options come to as the page's `Intl.DateTimeFormat` reads them (V8
/// `JSDateTimeFormat::CreateDateTimeFormat`): what the phone's pattern generator is asked with, the hour's length
/// kept (`UDATPG_MATCH_HOUR_FIELD_LENGTH`). `j` is the locale's own hour. [DateForm.medShort] has none: it is the
/// locale's medium date and short time, as `dateStyle` and `timeStyle` ask for them.
const Map<DateForm, String> dateSkeletons = {
  DateForm.d: 'd',
  DateForm.y: 'y',
  DateForm.E: 'EEE',
  DateForm.EEEE: 'EEEE',
  DateForm.MMMd: 'MMMd',
  DateForm.MMMMd: 'MMMMd',
  DateForm.yMMMd: 'yMMMd',
  DateForm.yMMMMd: 'yMMMMd',
  DateForm.MMMEd: 'MMMEEEd',
  DateForm.yMMMEd: 'yMMMEEEd',
  DateForm.MMMMEEEEd: 'MMMMEEEEd',
  DateForm.yMMMMEEEEd: 'yMMMMEEEEd',
  DateForm.yMMMM: 'yMMMM',
  DateForm.Hm23: 'HHmm',
  DateForm.hm2: 'jjmm',
  DateForm.hm: 'jmm',
  DateForm.MMMdhm2: 'MMMdjjmm',
  DateForm.MMMdhm: 'MMMdjmm',
  DateForm.whole: 'yMdjmmss',
  DateForm.dayPeriod: 'h',
};

const Map<DateLocale, DateWords> _tables = {
  DateLocale.enUS: DateWords(
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
  DateLocale.enGB: DateWords(
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

/// A pattern's runs: each field's letters together (`field`), and what stands between two fields, quoted words
/// with it, as one literal.
typedef _Run = ({String? field, String text});
final Map<String, List<_Run>> _runs = {};

bool _letter(int unit) => (unit >= 0x41 && unit <= 0x5a) || (unit >= 0x61 && unit <= 0x7a);

List<_Run> _runsOf(String pattern) {
  final runs = <_Run>[];
  final literal = StringBuffer();
  void flush() {
    if (literal.isEmpty) return;
    runs.add((field: null, text: literal.toString()));
    literal.clear();
  }

  var i = 0;
  while (i < pattern.length) {
    final unit = pattern.codeUnitAt(i);
    if (unit == 0x27) {
      // `''` is an apostrophe, in or out of quotes; `'…'` is its words as they are.
      if (i + 1 < pattern.length && pattern.codeUnitAt(i + 1) == 0x27) {
        literal.write("'");
        i += 2;
        continue;
      }
      i += 1;
      while (i < pattern.length) {
        if (pattern.codeUnitAt(i) == 0x27) {
          if (i + 1 < pattern.length && pattern.codeUnitAt(i + 1) == 0x27) {
            literal.write("'");
            i += 2;
            continue;
          }
          i += 1;
          break;
        }
        literal.writeCharCode(pattern.codeUnitAt(i));
        i += 1;
      }
    } else if (_letter(unit)) {
      flush();
      var end = i + 1;
      while (end < pattern.length && pattern.codeUnitAt(end) == unit) {
        end += 1;
      }
      runs.add((field: pattern.substring(i, end), text: ''));
      i = end;
    } else {
      literal.writeCharCode(unit);
      i += 1;
    }
  }
  flush();
  return runs;
}

int _hour12(DateTime at) => at.hour % 12 == 0 ? 12 : at.hour % 12;

/// A number in the locale's figures, at least `width` of them.
String _figures(int n, int width, DateWords words) {
  final plain = n.toString().padLeft(width, '0');
  if (identical(words.digits, _latin) || words.digits == _latin) return plain;
  final own = words.digits.runes.toList();
  return String.fromCharCodes([for (final unit in plain.codeUnits) unit >= 0x30 && unit <= 0x39 ? own[unit - 0x30] : unit]);
}

DatePart _part(_Run run, DateTime at, DateWords words) {
  final field = run.field;
  if (field == null) return (type: 'literal', value: run.text);
  final n = field.length;
  // Three letters or fewer are the short name; four, the name in full. (A narrow name, five, is asked for nowhere.)
  String name(List<String> full, List<String> short, int index) => n >= 4 ? full[index] : short[index];
  switch (field[0]) {
    case 'y':
      final year = at.year + words.yearOffset;
      return (type: 'year', value: n == 2 ? _figures(year % 100, 2, words) : _figures(year, n, words));
    case 'G':
      return (type: 'era', value: words.era);
    case 'M':
      return (type: 'month', value: n <= 2 ? _figures(at.month, n, words) : name(words.months, words.shortMonths, at.month - 1));
    case 'L':
      return (type: 'month', value: n <= 2 ? _figures(at.month, n, words) : name(words.monthsAlone, words.shortMonthsAlone, at.month - 1));
    case 'd':
      return (type: 'day', value: _figures(at.day, n, words));
    case 'E':
      return (type: 'weekday', value: name(words.weekdays, words.shortWeekdays, at.weekday - 1));
    case 'c':
      return (type: 'weekday', value: name(words.weekdaysAlone, words.shortWeekdaysAlone, at.weekday - 1));
    case 'h':
      return (type: 'hour', value: _figures(_hour12(at), n, words));
    case 'K':
      return (type: 'hour', value: _figures(at.hour % 12, n, words));
    case 'H':
      return (type: 'hour', value: _figures(at.hour, n, words));
    case 'k':
      return (type: 'hour', value: _figures(at.hour == 0 ? 24 : at.hour, n, words));
    case 'm':
      return (type: 'minute', value: _figures(at.minute, n, words));
    case 's':
      return (type: 'second', value: _figures(at.second, n, words));
    case 'a' || 'b' || 'B':
      return (type: 'dayPeriod', value: at.hour < 12 ? words.am : words.pm);
    default:
      // A letter this file does not read is written as it is, which no pattern asked for here comes to.
      return (type: 'literal', value: field);
  }
}

/// The words a date is written from: [locale]'s table where one is asked for by name; else the phone's own where
/// it gave them, else the table the phone's language reads, and en-GB's where the phone has not said.
DateWords _wordsOf(DateLocale? locale) => locale != null ? _tables[locale]! : (toldWords ?? _tables[toldLocale ?? DateLocale.enGB]!);

/// [at] in [form] as `formatToParts` answers it, in [locale]'s words: the phone's where none is given, and en-GB's
/// where the phone has not said. [at]'s own fields are read, so a wall clock kept in UTC reads as the clock it is.
List<DatePart> localeDateParts(DateTime at, DateForm form, [DateLocale? locale]) {
  final words = _wordsOf(locale);
  final pattern = words.patterns[form]!;
  final runs = _runs[pattern] ??= _runsOf(pattern);
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
String? toldShortMonth(DateTime at) => toldLocale == null ? null : _wordsOf(null).shortMonthsAlone[at.month - 1];

/// The month's name alone in the phone's words (`{ month: 'long' }`), or null where the phone has not said.
String? toldMonth(DateTime at) => toldLocale == null ? null : _wordsOf(null).monthsAlone[at.month - 1];
