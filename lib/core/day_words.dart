/// A day said in words, as the day a note writes (days.dart): "today", "tomorrow", "Friday", "next Friday", "next
/// week", "in two weeks", "the third of October", "October 3rd". A port of `src/app/core/dayWords.ts`, one to one.
/// What a spoken "due Friday" sets on a to-do and what the press-and-hold menu's Today, Tomorrow and Next week set,
/// so the menu's "Next week" and the voice's are one day (docs/DESIGN.md §158).
///
/// The rules, counted from `today`, the person's own day:
///
/// - **A weekday** is the next one, today included: "Friday" said on a Friday is today. "This Friday" is the same
///   day. "Next Friday" is the Friday of next week, a week that starts on a Monday, as a British calendar's does:
///   said on a Monday it is eleven days on, and said on a Thursday it is eight.
/// - **Next week** is that week's Monday, the day a thing put off to next week is looked at again; "the weekend" is
///   the coming Saturday, or today when today is the weekend.
/// - **A date** with no year is the next one, today included: "the third of October" said on the 4th is next
///   year's. "The third" alone is this month's, or next month's once it has gone.
/// - **A count** of days or weeks, "in three days", "in a week", "in a fortnight".
///
/// Words that are not one of these are not a day, and the caller keeps them as words: a due day that cannot be read
/// is never guessed at. Pure, so each rule is a line of test/core/day_words_test.dart.
///
/// What differs: nothing in the rules. `today` is a parameter, as the web's is, so nothing here reads a clock.
library;

import 'days.dart';
import 'item_syntax.dart' show jsTrim;

const List<String> _weekdays = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
const List<String> _months = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];

/// A month as it may be shortened, "Sept" and "Oct"; "May" is its own.
const Map<String, int> _monthShort = {'jan': 0, 'feb': 1, 'mar': 2, 'apr': 3, 'jun': 5, 'jul': 6, 'aug': 7, 'sep': 8, 'sept': 8, 'oct': 9, 'nov': 10, 'dec': 11};

const List<String> _units = ['', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'];
const List<String> _teens = ['ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
const List<String> _ordinalUnits = ['', 'first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth', 'ninth'];
const List<String> _ordinalTeens = ['tenth', 'eleventh', 'twelfth', 'thirteenth', 'fourteenth', 'fifteenth', 'sixteenth', 'seventeenth', 'eighteenth', 'nineteenth'];

final RegExp _spacesAndDashes = RegExp(r'[\s-]+');
final RegExp _digitsDay = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?$');
final RegExp _compoundDay = RegExp(r'^(twenty|thirty) (\w+)$');

/// "Third", "twenty-first", "3rd", "3": a day of the month, 1 to 31, or null.
int? _dayNumber(String said) {
  final word = jsTrim(said.replaceAll(_spacesAndDashes, ' '));
  final digits = _digitsDay.firstMatch(word);
  if (digits != null) return int.parse(digits.group(1)!);
  final plain = _ordinalUnits.indexOf(word);
  if (plain > 0) return plain;
  final teen = _ordinalTeens.indexOf(word);
  if (teen >= 0) return 10 + teen;
  if (word == 'twentieth') return 20;
  if (word == 'thirtieth') return 30;
  final compound = _compoundDay.firstMatch(word);
  final unit = compound != null ? _ordinalUnits.indexOf(compound.group(2) ?? '') : -1;
  return compound != null && unit > 0 ? (compound.group(1) == 'twenty' ? 20 : 30) + unit : null;
}

final RegExp _smallNumber = RegExp(r'^\d{1,3}$');

/// "Two", "a", "12": a small count, or null.
int? _count(String said) {
  if (_smallNumber.hasMatch(said)) return int.parse(said);
  if (said == 'a' || said == 'an') return 1;
  final unit = _units.indexOf(said);
  if (unit > 0) return unit;
  final teen = _teens.indexOf(said);
  return teen >= 0 ? 10 + teen : null;
}

/// A month by name, full or short, from 0; null for none.
int? _monthOf(String said) {
  final full = _months.indexOf(said);
  if (full >= 0) return full;
  return _monthShort[said];
}

/// Which day of the week [day] is, from Sunday's 0; null where it is not a day.
int? _weekdayOf(String day) {
  final at = dateOfDay(day);
  return at == null ? null : at.weekday % 7;
}

/// The Monday of the week after [today]'s: next week, as a thing is put off to it. A week starts on a Monday, so
/// said on a Sunday it is the next day.
String? nextWeek(String today) {
  final weekday = _weekdayOf(today);
  if (weekday == null) return null;
  return isoDayAfter(today, 7 - ((weekday + 6) % 7));
}

/// The next [weekday] (Sunday 0) from [today], today included.
String? _comingWeekday(String today, int weekday) {
  final now = _weekdayOf(today);
  return now == null ? null : isoDayAfter(today, (weekday - now + 7) % 7);
}

/// `year-month-day` written as a day, or null where the calendar has not got it. [month] counts from 0.
String? _written(int year, int month, int day) {
  final iso = '${year.toString().padLeft(4, '0')}-${(month + 1).toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  return isIsoDay(iso) ? iso : null;
}

/// A date with no year: this year's, or next year's once this year's has gone.
String? _comingDate(String today, int month, int day, int? year) {
  if (year != null) return _written(year, month, day);
  final thisYear = int.parse(today.substring(0, 4));
  final here = _written(thisYear, month, day);
  // 29 February in a year without one is the next year that has it, at most four on.
  if (here != null && here.compareTo(today) >= 0) return here;
  for (var ahead = 1; ahead <= 4; ahead += 1) {
    final there = _written(thisYear + ahead, month, day);
    if (there != null) return there;
  }
  return null;
}

/// "The third": this month's, or next month's once it has gone (and the one after, for a 31st a short month lacks).
String? _comingDayOfMonth(String today, int day) {
  var year = int.parse(today.substring(0, 4));
  var month = int.parse(today.substring(5, 7)) - 1;
  for (var ahead = 0; ahead < 3; ahead += 1) {
    final there = _written(year, month, day);
    if (there != null && there.compareTo(today) >= 0) return there;
    month += 1;
    if (month > 11) {
      month = 0;
      year += 1;
    }
  }
  return null;
}

/// A day of the month said as words or digits: "third", "twenty first", "3rd".
const String _day = r'(\d{1,2}(?:st|nd|rd|th)?|(?:twenty|thirty)[\s-]?\w+|\w+(?:st|nd|rd|th))';
const String _month = r'([a-z]{3,9})';
const String _year = r'(?:\s+(\d{4}))?';

/// "The third of October", "3 October 2027", "3rd of Oct".
final RegExp _dayMonth = RegExp('^(?:the\\s+)?$_day(?:\\s+of)?\\s+$_month$_year\$');

/// "October the third", "October 3rd", "Oct 3 2027".
final RegExp _monthDay = RegExp('^$_month\\s+(?:the\\s+)?$_day$_year\$');

/// "The third", "the 3rd".
final RegExp _theDay = RegExp('^the\\s+$_day\$');

final RegExp _stops = RegExp(r'[.,!?;:]+');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _leadIn = RegExp(r'^(?:on|by|for)\s+');
final RegExp _todayWords = RegExp(r'^(?:today|tonight|this (?:morning|afternoon|evening)|(?:the )?end of (?:the )?day)$');
final RegExp _tomorrowWords = RegExp(r'^tomorrow(?: (?:morning|afternoon|evening|night))?$');
final RegExp _dayAfterTomorrow = RegExp(r'^(?:the )?day after tomorrow$');
final RegExp _weekend = RegExp(r'^(?:this |the )?weekend$');
final RegExp _fortnight = RegExp(r'^in (?:a|one) fortnight$');
final RegExp _after = RegExp(r'^in (\w+) (day|days|week|weeks)$');
final RegExp _weekdayWords = RegExp(r'^(?:(this|next|on) )?(\w+)$');

/// The day [said] names, counted from [today], or null where the words are not a day this reads. Case, a leading
/// "on", "by" or "for", and the stops and commas Whisper writes inside a date are not part of what was said.
String? dayOfWords(String said, String today) {
  if (!isIsoDay(today)) return null;
  final words = jsTrim(said.toLowerCase().replaceAll(_stops, ' ').replaceAll(_spaces, ' ')).replaceFirst(_leadIn, '');
  if (words.isEmpty) return null;

  if (_todayWords.hasMatch(words)) return today;
  if (_tomorrowWords.hasMatch(words)) return isoDayAfter(today, 1);
  if (_dayAfterTomorrow.hasMatch(words)) return isoDayAfter(today, 2);
  if (words == 'yesterday') return isoDayAfter(today, -1);
  if (words == 'next week') return nextWeek(today);
  if (_weekend.hasMatch(words)) {
    final weekday = _weekdayOf(today);
    return weekday == 6 || weekday == 0 ? today : _comingWeekday(today, 6);
  }
  if (_fortnight.hasMatch(words)) return isoDayAfter(today, 14);
  final after = _after.firstMatch(words);
  if (after != null) {
    final n = _count(after.group(1) ?? '');
    return n == null ? null : isoDayAfter(today, after.group(2)!.startsWith('week') ? n * 7 : n);
  }

  final weekday = _weekdayWords.firstMatch(words);
  final named = weekday != null ? _weekdays.indexOf(weekday.group(2) ?? '') : -1;
  if (weekday != null && named >= 0) {
    if (weekday.group(1) != 'next') return _comingWeekday(today, named);
    final monday = nextWeek(today);
    return monday != null ? isoDayAfter(monday, (named + 6) % 7) : null;
  }

  final dayMonth = _dayMonth.firstMatch(words);
  if (dayMonth != null) {
    final day = _dayNumber(dayMonth.group(1) ?? '');
    final month = _monthOf(dayMonth.group(2) ?? '');
    final year = dayMonth.group(3);
    if (day != null && month != null) return _comingDate(today, month, day, year != null ? int.parse(year) : null);
  }
  final monthDay = _monthDay.firstMatch(words);
  if (monthDay != null) {
    final month = _monthOf(monthDay.group(1) ?? '');
    final day = _dayNumber(monthDay.group(2) ?? '');
    final year = monthDay.group(3);
    if (day != null && month != null) return _comingDate(today, month, day, year != null ? int.parse(year) : null);
  }
  final theDay = _theDay.firstMatch(words);
  if (theDay != null) {
    final day = _dayNumber(theDay.group(1) ?? '');
    if (day != null) return _comingDayOfMonth(today, day);
  }
  return null;
}
