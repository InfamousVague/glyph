/// A query shown as a calendar (`show: calendar`, tauri/docs/QUERIES.md): a month of weeks, each day with the
/// records it holds, which is the day run.dart gives each row (its due day, else its scheduled day, its start, or
/// its note's `date:`). A port of `src/app/core/query/calendar.ts`. Weeks start on Monday, as a week does everywhere
/// else in the app (day_words.dart `nextWeek`), and the days of the weeks either side of the month are there to fill
/// the rows, marked as not in it. Pure, so the drawing only draws.
///
/// What differs: [monthName] writes the month in the phone's language, as the page's `Intl` does, from the words
/// the phone gave at launch (lib/core/locale_dates.dart); a language named to it is not read, and its words are
/// then English.
library;

import '../days.dart' show dateOfDay, isoDayAfter;
import '../locale_dates.dart';
import 'read.dart' show QueryData;
import 'run.dart' show QueryRow;

class CalendarDay extends QueryData {
  const CalendarDay({required this.day, required this.date, required this.inMonth, required this.today, required this.rows});

  /// The day, YYYY-MM-DD.
  final String day;

  /// The day of the month, 1 to 31, as it is printed.
  final int date;

  /// In the month being shown, or a day of the weeks either side that fills a row.
  final bool inMonth;
  final bool today;
  final List<QueryRow> rows;

  @override
  Object? toJson() => {'day': day, 'date': date, 'inMonth': inMonth, 'today': today, 'rows': [for (final row in rows) row.toJson()]};
}

/// A month as `YYYY-MM`.
String monthOf(String day) => day.length > 7 ? day.substring(0, 7) : day;

/// The month [count] months after [month] (before, for a negative count).
String monthAfter(String month, int count) {
  final parts = month.split('-');
  final at = int.parse(parts[0]) * 12 + (int.parse(parts[1]) - 1) + count;
  return '${(at ~/ 12).toString().padLeft(4, '0')}-${((at % 12) + 1).toString().padLeft(2, '0')}';
}

/// The month a calendar opens on: today's, unless nothing is on it and something is on a later or an earlier one.
String openingMonth(List<QueryRow> rows, String today) {
  final days = [
    for (final row in rows)
      if (row.day != null) row.day!,
  ];
  final here = monthOf(today);
  if (days.isEmpty || days.any((day) => monthOf(day) == here)) return here;
  final later = days.where((day) => day.compareTo(today) > 0).toList()..sort();
  if (later.isNotEmpty) return monthOf(later.first);
  days.sort();
  return monthOf(days.last);
}

/// [month]'s weeks, Monday first, each day with the rows on it in the order they came.
List<List<CalendarDay>> monthWeeks(String month, List<QueryRow> rows, String today) {
  final first = '$month-01';
  final start = dateOfDay(first);
  if (start == null) return const [];
  // Monday is 0: back to the Monday of the week the 1st is in.
  final lead = start.weekday - 1;
  final byDay = <String, List<QueryRow>>{};
  for (final row in rows) {
    final day = row.day;
    if (day == null || day.isEmpty) continue;
    byDay.putIfAbsent(day, () => []).add(row);
  }
  final weeks = <List<CalendarDay>>[];
  var day = isoDayAfter(first, -lead)!;
  do {
    final week = <CalendarDay>[];
    for (var i = 0; i < 7; i += 1) {
      week.add(CalendarDay(day: day, date: int.parse(day.substring(8)), inMonth: monthOf(day) == month, today: day == today, rows: byDay[day] ?? const []));
      day = isoDayAfter(day, 1)!;
    }
    weeks.add(week);
  } while (monthOf(day) == month);
  return weeks;
}

/// How many of [rows] fall in [month].
int inMonth(List<QueryRow> rows, String month) => rows.where((row) => row.day != null && monthOf(row.day!) == month).length;

const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// The month's name as a heading says it, in the phone's language: "October 2026"
/// (`{ month: 'long', year: 'numeric' }`). A [locale] named is not read (see above): its words are English.
String monthName(String month, [String? locale]) {
  final at = dateOfDay('$month-01');
  return at != null ? (locale == null ? toldDate(at, DateForm.yMMMM) : null) ?? '${_months[at.month - 1]} ${at.year}' : month;
}

// ---- a week (the port's own, 2026-10-30) -------------------------------------------------------------------------

/// The Monday of the week [day] is in.
String mondayOf(String day) {
  final at = dateOfDay(day);
  return at == null ? day : isoDayAfter(day, -(at.weekday - 1))!;
}

/// The Monday [count] weeks after the week [day] is in (before, for a negative count).
String weekAfter(String day, int count) => isoDayAfter(mondayOf(day), 7 * count)!;

/// The week [day] is in, Monday first, each day with the rows on it in the order they came; every day is "in" it.
List<CalendarDay> weekDays(String day, List<QueryRow> rows, String today) {
  final monday = mondayOf(day);
  final byDay = <String, List<QueryRow>>{};
  for (final row in rows) {
    final on = row.day;
    if (on == null || on.isEmpty) continue;
    byDay.putIfAbsent(on, () => []).add(row);
  }
  return [
    for (var i = 0; i < 7; i += 1)
      if (isoDayAfter(monday, i) case final each?) CalendarDay(day: each, date: int.parse(each.substring(8)), inMonth: true, today: each == today, rows: byDay[each] ?? const []),
  ];
}

/// A week's days as a heading says them: `5 – 11 Oct 2026`, `28 Sep – 4 Oct 2026`, `29 Dec 2025 – 4 Jan 2026`.
String weekName(String day) {
  final monday = mondayOf(day);
  final first = dateOfDay(monday);
  final last = dateOfDay(isoDayAfter(monday, 6) ?? monday);
  if (first == null || last == null) return day;
  String short(DateTime at) => _months[at.month - 1].substring(0, 3);
  if (first.year != last.year) return '${first.day} ${short(first)} ${first.year} – ${last.day} ${short(last)} ${last.year}';
  if (first.month != last.month) return '${first.day} ${short(first)} – ${last.day} ${short(last)} ${last.year}';
  return '${first.day} – ${last.day} ${short(last)} ${last.year}';
}

/// How many of [rows] fall in the week [day] is in.
int inWeek(List<QueryRow> rows, String day) {
  final monday = mondayOf(day);
  final sunday = isoDayAfter(monday, 6)!;
  return rows.where((row) => row.day != null && row.day!.compareTo(monday) >= 0 && row.day!.compareTo(sunday) <= 0).length;
}
