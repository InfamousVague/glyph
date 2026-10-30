/// A query drawn as a timeline (`show: timeline`; the port's own, Matt 2026-10-30, "add all 12"): a bar for each
/// record from the day in its start field to the day in its end field, its rows by note or in its query's groups
/// (as a board's lanes are), a line down the days at today, and the days ticked as far apart as its zoom asks. The
/// app draws it (lib/editor/queries/query_timeline_view.dart), so a bar's ends can be carried to other days; the
/// Mermaid gantt (`show: gantt`, gantt.dart) stays as it was.
///
///     ```query
///     from: tickets [[Kiln]]
///     show: timeline
///     start: start
///     end: due
///     group: assignee
///     zoom: month
///     ```
///
/// - **Fields.** `start:` and `end:` name them, `start` and `due` where unsaid (run.dart puts each row's on it). A
///   record with only one of the two is a bar of that one day; one with neither is not drawn, and counted.
/// - **Days.** A bar runs from its first day to the end of its last, the two the right way round whichever was
///   written first. The days shown run from a little before the first bar (or today) to a little after the last
///   (or today), from a Monday, or for a quarter from a month's first day.
/// - **Zoom.** How wide a day is: a week's (a day a column, each dated), a month's (Mondays dated), a quarter's (each
///   month named).
///
/// Pure: the plan says where everything is in days, and the drawing multiplies by [dayWidth].
library;

import '../days.dart' show dateOfDay, daysBetween, isoDayAfter;
import 'read.dart';
import 'run.dart';

/// How wide a day is drawn at each zoom, in logical pixels.
double dayWidth(TimelineZoom zoom) => switch (zoom) {
      TimelineZoom.week => 44,
      TimelineZoom.month => 16,
      TimelineZoom.quarter => 6,
    };

/// One record's bar: its row, and its first and last days, from the plan's first day.
class TimelineBar extends QueryData {
  const TimelineBar({required this.row, required this.start, required this.end, required this.from, required this.to});
  final QueryRow row;

  /// Its first and last days (YYYY-MM-DD), the last in it.
  final String start;
  final String end;

  /// Its first day and the day after its last, counted from the plan's first day.
  final int from;
  final int to;

  @override
  Object? toJson() => {'row': row.key, 'start': start, 'end': end, 'from': from, 'to': to};
}

/// A group's rows; one with no label where the query is not grouped.
class TimelineLane extends QueryData {
  const TimelineLane({required this.group, required this.bars});
  final QueryGroup group;
  final List<TimelineBar> bars;
  @override
  Object? toJson() => {'label': group.label, 'bars': [for (final bar in bars) bar.toJson()]};
}

/// A tick on the days: where it is, what it says, and whether it starts a week or a month.
class TimelineTick extends QueryData {
  const TimelineTick({required this.day, required this.at, required this.label, required this.major});
  final String day;
  final int at;
  final String label;
  final bool major;
  @override
  Object? toJson() => {'day': day, 'at': at, 'label': label, 'major': major};
}

class TimelinePlan extends QueryData {
  const TimelinePlan({required this.first, required this.days, required this.today, required this.lanes, required this.ticks, required this.undated, required this.zoom});

  /// The first day shown, and how many.
  final String first;
  final int days;

  /// Today, counted from [first]; outside `0..days` where it is not shown.
  final int today;
  final List<TimelineLane> lanes;
  final List<TimelineTick> ticks;

  /// How many records have neither day.
  final int undated;
  final TimelineZoom zoom;

  /// How many bars there are.
  int get bars => lanes.fold<int>(0, (sum, lane) => sum + lane.bars.length);

  /// The day [count] days after [first].
  String dayAt(int count) => isoDayAfter(first, count) ?? first;

  @override
  Object? toJson() => {
        'first': first,
        'days': days,
        'today': today,
        'lanes': [for (final lane in lanes) lane.toJson()],
        'ticks': [for (final tick in ticks) tick.toJson()],
        'undated': undated,
        'zoom': zoom.name,
      };
}

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The zoom a timeline opens at where `zoom:` is unsaid: as much as its bars span, from the first to the last.
TimelineZoom zoomFor(int span) => span <= 21 ? TimelineZoom.week : (span <= 120 ? TimelineZoom.month : TimelineZoom.quarter);

/// The plan for [groups]' rows (run.dart: each row's `start` and `end` are its query's start and end fields), on
/// [today], at [zoom], or the zoom its bars' span asks for.
TimelinePlan timelineOf(List<QueryGroup> groups, String today, {TimelineZoom? zoom}) {
  final placed = <(QueryGroup, List<(QueryRow, String, String)>)>[];
  var undated = 0;
  String? least;
  String? most;
  for (final group in groups) {
    final rows = <(QueryRow, String, String)>[];
    for (final row in group.rows) {
      final one = row.start ?? row.end;
      final two = row.end ?? row.start;
      if (one == null || two == null || dateOfDay(one) == null || dateOfDay(two) == null) {
        undated += 1;
        continue;
      }
      final ordered = one.compareTo(two) <= 0;
      final start = ordered ? one : two;
      final end = ordered ? two : one;
      if (least == null || start.compareTo(least) < 0) least = start;
      if (most == null || end.compareTo(most) > 0) most = end;
      rows.add((row, start, end));
    }
    placed.add((group, rows));
  }
  final span = least == null || most == null ? 0 : (daysBetween(least, most) ?? 0) + 1;
  final shown = zoom ?? zoomFor(span);
  final low = least == null || today.compareTo(least) < 0 ? today : least;
  final high = most == null || today.compareTo(most) > 0 ? today : most;
  final pad = switch (shown) {
    TimelineZoom.week => 3,
    TimelineZoom.month => 7,
    TimelineZoom.quarter => 14,
  };
  // From a Monday, or a quarter's month's first day, so the ticks start whole.
  var first = isoDayAfter(low, -pad)!;
  final at = dateOfDay(first)!;
  first = shown == TimelineZoom.quarter ? '${first.substring(0, 7)}-01' : isoDayAfter(first, -(at.weekday - 1))!;
  // At least as many days as a card's width shows at the zoom, so a short plan still fills it.
  final fewest = switch (shown) {
    TimelineZoom.week => 14,
    TimelineZoom.month => 42,
    TimelineZoom.quarter => 120,
  };
  var days = (daysBetween(first, isoDayAfter(high, pad)!) ?? 0) + 1;
  if (days < fewest) days = fewest;
  final lanes = <TimelineLane>[
    for (final (group, rows) in placed)
      TimelineLane(
        group: group,
        bars: [
          for (final (row, start, end) in rows) TimelineBar(row: row, start: start, end: end, from: daysBetween(first, start) ?? 0, to: (daysBetween(first, end) ?? 0) + 1),
        ],
      ),
  ];
  final ticks = <TimelineTick>[];
  for (var n = 0; n < days; n += 1) {
    final day = isoDayAfter(first, n)!;
    final date = dateOfDay(day)!;
    final monthStart = date.day == 1;
    switch (shown) {
      case TimelineZoom.week:
        ticks.add(TimelineTick(day: day, at: n, label: date.weekday == DateTime.monday || n == 0 ? '${date.day} ${_months[date.month - 1]}' : '${date.day}', major: date.weekday == DateTime.monday));
      case TimelineZoom.month:
        if (date.weekday == DateTime.monday) ticks.add(TimelineTick(day: day, at: n, label: '${date.day} ${_months[date.month - 1]}', major: monthStart || date.day <= 7));
      case TimelineZoom.quarter:
        if (monthStart) ticks.add(TimelineTick(day: day, at: n, label: date.month == 1 || ticks.isEmpty ? '${_months[date.month - 1]} ${date.year}' : _months[date.month - 1], major: true));
    }
  }
  return TimelinePlan(first: first, days: days, today: daysBetween(first, today) ?? -1, lanes: lanes, ticks: ticks, undated: undated, zoom: shown);
}

/// A bar's days moved by [by] at one end or both: [end] the last day's, [start] the first's. The two never cross:
/// a start carried past the end stops on it.
({String start, String end}) movedBar(String start, String end, int by, {required bool moveStart, required bool moveEnd}) {
  var nextStart = moveStart ? isoDayAfter(start, by)! : start;
  var nextEnd = moveEnd ? isoDayAfter(end, by)! : end;
  if (nextStart.compareTo(nextEnd) > 0) {
    if (moveStart && !moveEnd) nextStart = nextEnd;
    if (moveEnd && !moveStart) nextEnd = nextStart;
  }
  return (start: nextStart, end: nextEnd);
}
