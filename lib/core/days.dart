/// A day as a note writes one, ISO's `2026-10-03`: what a to-do's `📅 2026-10-03` holds (task_fields.dart), what a
/// ticket's `due:` says (properties.dart), and what a query sorts, compares and lays out on a calendar. A port of
/// `src/app/core/days.ts`, one to one. The note keeps the date as these ten characters and nothing else, so it reads
/// the same in Obsidian, on GitHub and to a person, and two of them compare as text: `'2026-10-03'` is before
/// `'2026-10-10'`.
///
/// A day is the person's own day, by the device's clock and calendar, never the instant's day in UTC. An ISO string
/// of the instant is the trap: at 23:30 in New York on 3 October it says the 4th, and a to-do written "due today"
/// would be due tomorrow. So a moment is read here by its local fields, and the arithmetic is done on the calendar
/// (`DateTime.utc` of the day's parts, where no clock changes), so a week on from the Saturday the clocks go back is
/// still the next Saturday.
///
/// A leaf with no imports, as the web's is, so the grammars that need a day cannot go round in a circle.
///
/// What differs: the web's `isoDayAfter` is overloaded, a `Date` or a written day; Dart has no overloads, so
/// [isoDayAfter] takes the written day and [isoDayAfterDate] the moment. A `DateTime` made in UTC is read by the
/// device's clock, as a JavaScript `Date` always is. `DateTime.utc` does not read a year under 100 as 19xx, so the
/// web's `setUTCFullYear` detour has nothing to dodge here.
library;

const int _dayMs = 86400000;

/// A day as it is written: four figures, two and two.
final RegExp _isoDay = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

String _two(int n) => n.toString().padLeft(2, '0');

/// The parts of a day as it is written; [month] counts from 1.
String _written(int year, int month, int day) => '${year.toString().padLeft(4, '0')}-${_two(month)}-${_two(day)}';

/// "2026-10-03": the day [at] falls on by the device's clock and calendar.
String isoDay(DateTime at) {
  final local = at.toLocal();
  return _written(local.year, local.month, local.day);
}

/// Where a written day is on the calendar, as a count of milliseconds from 1970 in UTC, which no clock change moves;
/// null for words that are not a day, or for a day the calendar has not got (`2026-02-30`).
int? _calendarTime(String iso) {
  final found = _isoDay.firstMatch(iso);
  if (found == null) return null;
  final year = int.parse(found.group(1)!);
  final month = int.parse(found.group(2)!);
  final day = int.parse(found.group(3)!);
  final at = DateTime.utc(year, month, day);
  return at.year == year && at.month == month && at.day == day ? at.millisecondsSinceEpoch : null;
}

/// Whether [text] is a day as a note writes one, and one the calendar has: `2026-10-03`, not `2026-02-30` or
/// `3 Oct`.
bool isIsoDay(String text) => _calendarTime(text) != null;

/// The day [days] after the written [day] (before it, for a negative count), by the calendar; null where [day] is
/// not one. A count with a fraction is cut to whole days.
String? isoDayAfter(String day, num days) {
  final from = _calendarTime(day);
  if (from == null) return null;
  final at = DateTime.fromMillisecondsSinceEpoch(from + days.truncate() * _dayMs, isUtc: true);
  return _written(at.year, at.month, at.day);
}

/// The day [days] after the moment [at], counted from its day on the device's clock (the web's `isoDayAfter` given
/// a `Date`).
String isoDayAfterDate(DateTime at, num days) => isoDayAfter(isoDay(at), days)!;

/// Whole days from one written day to another: 7 from a Saturday to the next, -1 back to the day before; null where
/// either is not a day.
int? daysBetween(String from, String to) {
  final start = _calendarTime(from);
  final end = _calendarTime(to);
  return start == null || end == null ? null : ((end - start) / _dayMs).round();
}

/// A written day as a moment at noon on the device's clock, to name ("Saturday", "3 Oct") and for a calendar to
/// place: noon, so no clock change that day moves it into the next or the last. Null where it is not a day.
DateTime? dateOfDay(String iso) {
  final at = _calendarTime(iso);
  if (at == null) return null;
  final utc = DateTime.fromMillisecondsSinceEpoch(at, isUtc: true);
  return DateTime(utc.year, utc.month, utc.day, 12);
}
