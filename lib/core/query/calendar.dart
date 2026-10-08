/// A query shown as a calendar (`show: calendar`, ../glyph docs/QUERIES.md): a month of weeks, each day with the
/// records it holds, which is the day run.dart gives each row (its due day, else its scheduled day, its start, or
/// its note's `date:`). A port of `src/app/core/query/calendar.ts`. Weeks start on Monday, as a week does everywhere
/// else in the app (day_words.dart `nextWeek`), and the days of the weeks either side of the month are there to fill
/// the rows, marked as not in it. Pure, so the drawing only draws.
///
/// What differs: [monthName] writes the month in English, "October 2026", whatever language is asked: the page asks
/// `Intl` for the device's, and this app has no table of other languages' months yet (lib/core/template.dart says
/// the same of a template's).
library;

import '../days.dart' show dateOfDay, isoDayAfter;
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

/// The month's name as a heading says it: "October 2026". [locale] is taken and not read (see above).
String monthName(String month, [String? locale]) {
  final at = dateOfDay('$month-01');
  return at != null ? '${_months[at.month - 1]} ${at.year}' : month;
}
