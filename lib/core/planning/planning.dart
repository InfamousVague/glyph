/// A notebook's planning, worked out from its tickets' front matter (Matt, 2026-10-31, of the ticket features he
/// chose: cycles, estimates and velocity, epics and milestones, priority and aging; docs/TICKETS.md). The cycles are
/// cycles.dart and the days a status changed are history.dart; this is the arithmetic over them, pure, so each sum is
/// a test (test/core/planning/planning_test.dart):
///
/// - **An estimate** is `estimate: 3`, points, or `estimate: 4h`, hours (`30m`, `2d` of eight hours, `3 points`
///   too). A cycle's or a person's total keeps the two apart, `13 points · 6h`, since three points and three hours
///   are not six of anything.
/// - **A burndown** is a cycle's remaining work on each of its days: every ticket in the cycle now, less those
///   finished by the end of that day (history.dart's day), weighed by its points, or one each where none of them is
///   estimated. The ideal falls straight from the first day's total to nothing on the last; the days after today
///   have no remaining to draw.
/// - **Velocity** is what each cycle finished: the points (or the count) of its tickets that are done.
/// - **An epic** is a ticket with `type: epic`, and the tickets under it name it as their `parent:` - the one link
///   between tickets that make up another, so an epic's tickets are its sub-tickets, and its progress is theirs:
///   how many are done, and how many of their points. A ticket may have sub-tickets of its own under an epic, as a
///   story has tasks under its epic in Jira, which since 2023 calls the link to an epic a parent too.
/// - **A milestone** is a dated target: a note with `type: milestone` and a `date:` (or `due:`), which a ticket or an
///   epic names, `milestone: "[[v2 launch]]"`.
/// - **Aging**: a ticket not finished whose status has not changed for longer than its notebook's `stale-after:`
///   (`7d`, `2w`; fourteen days where unsaid, `off` for never) is stale, "stale · 9 days".
library;

import '../days.dart' show daysBetween;
import '../front_matter.dart' show frontMatterValue;
import '../item_syntax.dart' show jsTrim;
import '../properties.dart' show StatusCategory;
import 'cycles.dart' show Cycle, daysOf;

// ---- estimates ----------------------------------------------------------------------------------------------------

/// What an estimate counts in.
enum EstimateUnit { points, hours }

/// An estimate as written, read.
class Estimate {
  const Estimate(this.value, this.unit);
  final double value;
  final EstimateUnit unit;

  @override
  bool operator ==(Object other) => other is Estimate && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => 'Estimate($value ${unit.name})';
}

final RegExp _estimate = RegExp(r'^(\d+(?:\.\d+)?|\.\d+)\s*([a-z]*)\.?$', caseSensitive: false);

/// An estimate as a ticket writes it: `3` and `3 points` (`pt`, `pts`, `sp`) are points; `4h` (`hr`, `hours`), `30m`
/// and `2d` (a working day of eight hours) are hours. Null for anything else.
Estimate? estimateOf(String? written) {
  final found = _estimate.firstMatch(jsTrim(written ?? ''));
  if (found == null) return null;
  final value = double.parse(found.group(1)!);
  final unit = found.group(2)!.toLowerCase();
  if (unit.isEmpty || const {'p', 'pt', 'pts', 'point', 'points', 'sp'}.contains(unit)) return Estimate(value, EstimateUnit.points);
  if (const {'h', 'hr', 'hrs', 'hour', 'hours'}.contains(unit)) return Estimate(value, EstimateUnit.hours);
  if (const {'m', 'min', 'mins', 'minute', 'minutes'}.contains(unit)) return Estimate(value / 60, EstimateUnit.hours);
  if (const {'d', 'day', 'days'}.contains(unit)) return Estimate(value * 8, EstimateUnit.hours);
  return null;
}

/// A number as a total says it: `3`, `2.5`.
String plainAmount(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(value * 10 == (value * 10).roundToDouble() ? 1 : 2);

/// Points and hours added up, and how many tickets had neither.
class EstimateTotals {
  const EstimateTotals({this.points = 0, this.hours = 0, this.count = 0, this.unestimated = 0});
  final double points;
  final double hours;

  /// How many tickets in all.
  final int count;
  final int unestimated;

  /// `13 points · 6h`, `1 point`, `6h`; `No estimates` for none.
  String get words {
    final parts = <String>[
      if (points > 0 || hours == 0 && count > unestimated) '${plainAmount(points)} ${points == 1 ? 'point' : 'points'}',
      if (hours > 0) '${plainAmount(hours)}h',
    ];
    return parts.isEmpty ? 'No estimates' : parts.join(' · ');
  }

  @override
  bool operator ==(Object other) => other is EstimateTotals && other.points == points && other.hours == hours && other.count == count && other.unestimated == unestimated;

  @override
  int get hashCode => Object.hash(points, hours, count, unestimated);

  @override
  String toString() => 'EstimateTotals($words, $count tickets, $unestimated without)';
}

/// [estimates], as written, added up.
EstimateTotals totalsOf(Iterable<String?> estimates) {
  var points = 0.0, hours = 0.0;
  var count = 0, none = 0;
  for (final written in estimates) {
    count += 1;
    final estimate = estimateOf(written);
    if (estimate == null) {
      none += 1;
    } else if (estimate.unit == EstimateUnit.points) {
      points += estimate.value;
    } else {
      hours += estimate.value;
    }
  }
  return EstimateTotals(points: points, hours: hours, count: count, unestimated: none);
}

/// [estimates] by whoever each is for (`null` for nobody), added up: the totals per assignee.
Map<String?, EstimateTotals> totalsBy(Iterable<({String? who, String? estimate})> estimates) {
  final by = <String?, List<String?>>{};
  for (final each in estimates) {
    by.putIfAbsent(each.who, () => []).add(each.estimate);
  }
  return {for (final entry in by.entries) entry.key: totalsOf(entry.value)};
}

/// What a ticket weighs in a burndown or a velocity: its estimate's number, points or hours alike, where [byPoints];
/// else one.
double weightOf(String? estimate, {required bool byPoints}) => byPoints ? (estimateOf(estimate)?.value ?? 0) : 1;

/// Whether a chart of these tickets is by points: any of them is estimated.
bool anyEstimated(Iterable<String?> estimates) => estimates.any((each) => estimateOf(each) != null);

// ---- a cycle's burndown -------------------------------------------------------------------------------------------

/// One day of a burndown: what remained at its end (null for a day still to come) and what the ideal says.
class BurndownDay {
  const BurndownDay({required this.day, required this.remaining, required this.ideal, this.left = const []});
  final String day;
  final double? remaining;
  final double ideal;

  /// The tickets still open at the end of it, by whatever key the caller gave.
  final List<String> left;

  @override
  bool operator ==(Object other) => other is BurndownDay && other.day == day && other.remaining == remaining && other.ideal == ideal;

  @override
  int get hashCode => Object.hash(day, remaining, ideal);

  @override
  String toString() => 'BurndownDay($day: $remaining, ideal $ideal)';
}

/// One ticket as a burndown weighs it: its key, its weight, and the day it was finished (null for not yet).
typedef BurndownTicket = ({String key, double weight, String? done});

/// [cycle]'s burndown over [tickets], on [today]. A ticket finished before the cycle began counts as finished on its
/// first day.
List<BurndownDay> burndownOf(Cycle cycle, List<BurndownTicket> tickets, String today) {
  final days = cycle.days;
  if (days.isEmpty) return const [];
  final total = tickets.fold<double>(0, (sum, ticket) => sum + ticket.weight);
  final span = days.length - 1;
  return [
    for (final (index, day) in days.indexed)
      () {
        final ideal = span == 0 ? 0.0 : total * (span - index) / span;
        if (day.compareTo(today) > 0) return BurndownDay(day: day, remaining: null, ideal: ideal);
        final left = [
          for (final ticket in tickets)
            if (ticket.done == null || ticket.done!.compareTo(day) > 0) ticket,
        ];
        return BurndownDay(day: day, remaining: left.fold<double>(0, (sum, ticket) => sum + ticket.weight), ideal: ideal, left: [for (final ticket in left) ticket.key]);
      }(),
  ];
}

// ---- velocity -----------------------------------------------------------------------------------------------------

/// What one cycle finished, of what it had.
class VelocityBar {
  const VelocityBar({required this.cycle, required this.finished, required this.committed, this.keys = const []});
  final Cycle cycle;
  final double finished;
  final double committed;

  /// The finished tickets, by the caller's key.
  final List<String> keys;

  @override
  bool operator ==(Object other) => other is VelocityBar && other.cycle == cycle && other.finished == finished && other.committed == committed;

  @override
  int get hashCode => Object.hash(cycle, finished, committed);

  @override
  String toString() => 'VelocityBar(${cycle.name}: $finished of $committed)';
}

/// One ticket as velocity weighs it: its key, its cycle, its weight, and whether it is finished.
typedef VelocityTicket = ({String key, Cycle? cycle, double weight, bool finished});

/// What each of [cycles] finished among [tickets], in the cycles' order; [same] says whether a ticket's cycle is one.
List<VelocityBar> velocityOf(List<Cycle> cycles, List<VelocityTicket> tickets, bool Function(Cycle? a, Cycle? b) same) => [
  for (final cycle in cycles)
    () {
      final mine = [for (final ticket in tickets) if (same(ticket.cycle, cycle)) ticket];
      final done = [for (final ticket in mine) if (ticket.finished) ticket];
      return VelocityBar(
        cycle: cycle,
        finished: done.fold<double>(0, (sum, ticket) => sum + ticket.weight),
        committed: mine.fold<double>(0, (sum, ticket) => sum + ticket.weight),
        keys: [for (final ticket in done) ticket.key],
      );
    }(),
];

/// The average of the cycles that have ended, for a line under the bars: `Averages 11 points`. Null for none.
double? averageVelocity(List<VelocityBar> bars, String today) {
  final ended = [for (final bar in bars) if (bar.cycle.endedBy(today)) bar.finished];
  return ended.isEmpty ? null : ended.reduce((a, b) => a + b) / ended.length;
}

// ---- epics and milestones -----------------------------------------------------------------------------------------

/// The `type:` of an epic, which is a ticket too.
const String epicType = 'epic';

/// The `type:` of a milestone note.
const String milestoneType = 'milestone';

/// Whether a `type:` says epic.
bool isEpicType(String? type) => jsTrim(type ?? '').toLowerCase() == epicType;

/// Whether a `type:` says milestone.
bool isMilestoneType(String? type) => jsTrim(type ?? '').toLowerCase() == milestoneType;

/// A milestone's day: its `date:`, else its `due:`.
String? milestoneDayOf(Map<String, String> props) {
  for (final key in const ['date', 'due']) {
    final said = jsTrim(props[key] ?? '');
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(said)) return said;
  }
  return null;
}

/// How far an epic is: its tickets done of all of them, and their points.
class EpicProgress {
  const EpicProgress({required this.done, required this.total, required this.pointsDone, required this.pointsTotal});
  final int done;
  final int total;
  final double pointsDone;
  final double pointsTotal;

  bool get isEmpty => total == 0;

  /// Done over all, by points where they are estimated, else by count.
  double get fraction => pointsTotal > 0 ? pointsDone / pointsTotal : (total == 0 ? 0 : done / total);

  /// `3 of 8 done · 5 of 13 points`.
  String get words => pointsTotal > 0 ? '$done of $total done · ${plainAmount(pointsDone)} of ${plainAmount(pointsTotal)} points' : '$done of $total done';

  @override
  bool operator ==(Object other) => other is EpicProgress && other.done == done && other.total == total && other.pointsDone == pointsDone && other.pointsTotal == pointsTotal;

  @override
  int get hashCode => Object.hash(done, total, pointsDone, pointsTotal);

  @override
  String toString() => 'EpicProgress($words)';
}

/// An epic's progress over its tickets: where each stands and its estimate as written.
EpicProgress epicProgressOf(Iterable<({StatusCategory category, String? estimate})> tickets) {
  var done = 0, total = 0;
  var pointsDone = 0.0, pointsTotal = 0.0;
  for (final ticket in tickets) {
    total += 1;
    final finished = ticket.category == StatusCategory.done;
    if (finished) done += 1;
    final weight = estimateOf(ticket.estimate)?.value ?? 0;
    pointsTotal += weight;
    if (finished) pointsDone += weight;
  }
  return EpicProgress(done: done, total: total, pointsDone: pointsDone, pointsTotal: pointsTotal);
}

// ---- priority -----------------------------------------------------------------------------------------------------

/// A ticket's priorities, the most urgent first, as a ticket writes them (Matt, 2026-10-31: `priority:
/// urgent|high|medium|low`), each with the name task_fields.dart ranks it by: Urgent is Tasks' highest.
const List<({String written, String name, String label})> ticketPriorities = [
  (written: 'urgent', name: 'highest', label: 'Urgent'),
  (written: 'high', name: 'high', label: 'High'),
  (written: 'medium', name: 'medium', label: 'Medium'),
  (written: 'low', name: 'low', label: 'Low'),
];

/// How a ticket's priority of [name] (task_fields.dart's) is said: Urgent for highest; Lowest stays itself.
String ticketPriorityLabel(String name) {
  for (final each in ticketPriorities) {
    if (each.name == name) return each.label;
  }
  return name == 'lowest' ? 'Lowest' : name;
}

/// The glacier hue a ticket's priority wears, as a to-do's chevrons wear theirs: red for urgent (filled, which sets it
/// apart from high) and high, amber, blue, and grey for the least. Glacier has no orange.
String priorityHue(String name) => switch (name) {
  'highest' => 'red',
  'high' => 'red',
  'medium' => 'amber',
  'low' => 'blue',
  _ => 'gray',
};

// ---- aging --------------------------------------------------------------------------------------------------------

/// How long a ticket may sit in one status before it is stale, where its notebook does not say.
const int defaultStaleDays = 14;

/// A notebook's `stale-after:`, in days: fourteen where unsaid or unreadable, null for `off`.
int? staleAfterOf(String? notebook) {
  final said = jsTrim(notebook == null ? '' : (frontMatterValue(notebook, 'stale-after') ?? '')).toLowerCase();
  if (said.isEmpty) return defaultStaleDays;
  if (const {'off', 'no', 'never', 'false', 'none', '0', '0d'}.contains(said)) return null;
  return daysOf(said) ?? defaultStaleDays;
}

/// How many days a ticket has sat in its status, where that is longer than [after]: null where it is fresh,
/// finished, or its notebook never says stale.
int? staleDays({required StatusCategory category, required String since, required String today, required int? after}) {
  if (after == null || category == StatusCategory.done) return null;
  final days = daysBetween(since, today);
  return days != null && days > after ? days : null;
}

/// `stale · 9 days`.
String staleWords(int days) => 'stale · $days ${days == 1 ? 'day' : 'days'}';
