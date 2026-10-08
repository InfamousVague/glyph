/// A query drawn as a timeline (`show: gantt`): its records as bars by date on an axis of days, a section a group,
/// and today's line. Stands where `GanttView` of `src/app/editor/QueryView.tsx` stands.
///
/// **This is a different drawing from the page's.** The page hands the text lib/core/query/gantt.dart writes
/// (`ganttOf`) to Mermaid and shows Mermaid's own picture, quieted by `.gantt`'s rules. This app has no Mermaid; the
/// same records are drawn here by a painter, in the app's own look:
///
/// - the same bars: a record runs from its start to its due day, the due day drawn whole; one with only one of them
///   is a bar of that day; one with neither is left off and counted under the chart, in the page's words;
/// - the same sections, a group each, named at the left where the query is grouped;
/// - the same ticks, a day, a week, a month or three apart as the bars span days, weeks or months
///   (`ticksFor`), dated the same way, but a week's tick is its Monday, as a week starts everywhere else in the
///   app, where Mermaid's is its Sunday;
/// - a bar's colour says what Mermaid's words said: done is the faint ink, under way blue, and a bar that is
///   overdue is ringed in red (`done`, `active`, `crit`). Mermaid's own theme coloured them in its blues and greys;
/// - a bar's name is beside it, after it where there is room and before it where there is not, in the card's
///   small type; Mermaid puts a name inside its bar when it fits;
/// - today is a line in the red of an overdue day, where Mermaid's is its own red.
///
/// So nothing here is held to the page by measurement: the two pictures agree in what they say, not in where each
/// pixel is. [ganttChart] is pure, and is what the tests hold.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/days.dart' show dateOfDay, daysBetween, isoDayAfter;
import '../../core/properties.dart' show StatusCategory;
import '../../core/query/query.dart';
import 'query_layout.dart';
import 'query_look.dart';

/// One record on the timeline.
class GanttBar {
  const GanttBar({required this.name, required this.start, required this.end, required this.done, required this.active, required this.crit});

  final String name;

  /// Its first day, and the day after its last.
  final String start;
  final String end;
  final bool done;
  final bool active;
  final bool crit;
}

class GanttSection {
  const GanttSection(this.label, this.bars);

  /// The group's words; empty for a query that is not grouped.
  final String label;
  final List<GanttBar> bars;
}

/// A timeline's bars, and the days it runs from and to.
class GanttChart {
  const GanttChart({required this.sections, required this.from, required this.to, required this.named});

  final List<GanttSection> sections;
  final String from;
  final String to;

  /// Whether the sections are named: a grouped query's.
  final bool named;

  int get days => math.max(1, daysBetween(from, to) ?? 1);
  int get placed => sections.fold(0, (sum, section) => sum + section.bars.length);
}

/// The bars for [groups]' records, as lib/core/query/gantt.dart `ganttOf` writes them for Mermaid: the same records
/// placed, the same days, the same sections; null where it places none.
GanttChart? ganttChart(List<QueryGroup> groups, [String kind = 'Records']) {
  final named = groups.length > 1 || groups.any((group) => group.label.isNotEmpty);
  final sections = <GanttSection>[];
  String? from;
  String? to;
  for (final group in groups) {
    final bars = <GanttBar>[];
    for (final row in group.rows) {
      final first = row.start ?? row.due;
      final last = row.due ?? row.start;
      if (first == null || first.isEmpty || last == null || last.isEmpty) continue;
      // A start written after the due day is the two the wrong way round: the bar still runs between them.
      final ordered = first.compareTo(last) <= 0;
      final start = ordered ? first : last;
      final end = isoDayAfter(ordered ? last : first, 1);
      if (end == null || end.isEmpty) continue;
      if (from == null || start.compareTo(from) < 0) from = start;
      if (to == null || end.compareTo(to) > 0) to = end;
      final done = row.category == StatusCategory.done || row.done == true;
      final id = row.id;
      bars.add(GanttBar(name: ganttWords(id != null && id.isNotEmpty ? '$id ${row.name}' : row.name, 'Untitled'), start: start, end: end, done: done, active: !done && row.category == StatusCategory.doing, crit: row.overdue));
    }
    if (bars.isEmpty) continue;
    sections.add(GanttSection(named ? ganttWords(group.label, kind) : '', bars));
  }
  if (sections.isEmpty || from == null || to == null) return null;
  return GanttChart(sections: sections, from: from, to: to, named: named);
}

const List<String> _months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The days a timeline is ticked at between [from] and [to], and what each says, for bars that span that many days
/// ([ticksFor]): every day by its date, each Monday as "5 Oct", each month's first by its name, or each third
/// month's with its year.
List<({String day, String label})> ganttTicks(String from, String to) {
  final span = daysBetween(from, to) ?? 0;
  final (:tick, axis: _) = ticksFor(span);
  final ticks = <({String day, String label})>[];
  for (var day = from; day.compareTo(to) <= 0; day = isoDayAfter(day, 1)!) {
    final at = dateOfDay(day);
    if (at == null) break;
    switch (tick) {
      case '1day':
        ticks.add((day: day, label: '${at.day}'));
      case '1week':
        if (at.weekday == DateTime.monday) ticks.add((day: day, label: '${at.day} ${_months[at.month - 1]}'));
      case '1month':
        if (at.day == 1) ticks.add((day: day, label: _months[at.month - 1]));
      default:
        if (at.day == 1 && (at.month - 1) % 3 == 0) ticks.add((day: day, label: '${_months[at.month - 1]} ${at.year}'));
    }
  }
  return ticks;
}

class QueryGantt extends StatelessWidget {
  const QueryGantt({super.key, required this.look, required this.result, required this.today});

  final QueryLook look;
  final QueryResult result;
  final String today;

  /// A bar's height and the room between two (`barHeight`, `barGap` of the layout `ganttOf` asks Mermaid for).
  static const double barHeight = 22;
  static const double barGap = 6;

  @override
  Widget build(BuildContext context) {
    final chart = ganttChart(result.groups, kindWords[result.kind]!);
    Widget quiet(String name, String text) => Padding(
      padding: EdgeInsets.symmetric(vertical: look.space(1)),
      child: Part(name, child: PageWords(text, look.sans(look.em, color: look.ink3), line: look.line)),
    );
    if (chart == null) return quiet('empty', 'Nothing here has a start or a due day to put on a timeline.');
    final unplaced = result.shown - chart.placed;
    final small = look.sans(look.xs, color: look.ink2).copyWith(height: 1.2);
    // The sections' names, in a column of their own at the left, as wide as the widest and no wider than a third.
    var names = 0.0;
    if (chart.named) {
      for (final section in chart.sections) {
        final painter = TextPainter(text: TextSpan(text: section.label, style: small), textDirection: TextDirection.ltr, maxLines: 1)..layout();
        names = math.max(names, painter.width);
        painter.dispose();
      }
    }
    final rows = chart.placed;
    final tall = look.space(2) + rows * (barHeight + barGap) + chart.sections.length * barGap + 1.6 * look.xs + look.space(1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (context, constraints) {
            final room = constraints.maxWidth;
            final left = chart.named ? math.min(names, room / 3) + look.space(3) : 0.0;
            // A day is never narrower than a few pixels: a long span scrolls sideways in the card.
            final wide = math.max(room, left + chart.days * 4.0 + look.space(2));
            final painted = Semantics(
              label: 'Timeline',
              image: true,
              child: Part(
                'gantt',
                child: CustomPaint(size: Size(wide, tall), painter: GanttPainter(chart: chart, look: look, today: today, left: left, small: small)),
              ),
            );
            return wide > room + 0.5 ? SingleChildScrollView(scrollDirection: Axis.horizontal, physics: const ClampingScrollPhysics(), child: painted) : painted;
          },
        ),
        if (unplaced > 0) quiet('warning', unplaced == 1 ? 'One has no start or due day, and is not on the timeline.' : '$unplaced have no start or due day, and are not on the timeline.'),
      ],
    );
  }
}

class GanttPainter extends CustomPainter {
  const GanttPainter({required this.chart, required this.look, required this.today, required this.left, required this.small});

  final GanttChart chart;
  final QueryLook look;
  final String today;

  /// The room the sections' names take at the left.
  final double left;
  final TextStyle small;

  TextPainter _words(String text, TextStyle style, double width) =>
      TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…', textScaler: TextScaler.noScaling)..layout(maxWidth: math.max(0, width));

  @override
  void paint(Canvas canvas, Size size) {
    final t = look.t;
    final right = size.width - look.space(2);
    final span = right - left;
    final days = chart.days;
    double x(String day) => left + span * (daysBetween(chart.from, day) ?? 0) / days;
    final axis = size.height - 1.6 * look.xs - look.space(1);

    // The ticks: a faint line up the chart, and its date under it.
    final rule = Paint()
      ..color = look.rule
      ..strokeWidth = 1;
    var lastLabel = double.negativeInfinity;
    for (final tick in ganttTicks(chart.from, chart.to)) {
      final at = x(tick.day);
      canvas.drawLine(Offset(at, 0), Offset(at, axis), rule);
      final label = _words(tick.label, small.copyWith(color: look.ink3), 80);
      final from = (at - label.width / 2).clamp(left, math.max(left, size.width - label.width)).toDouble();
      // A date that would run into the one before it is left out.
      if (from > lastLabel + look.space(1)) {
        label.paint(canvas, Offset(from, axis + look.space(1)));
        lastLabel = from + label.width;
      }
      label.dispose();
    }

    // Today's line, where today is on the chart, under the bars and their names.
    if (today.compareTo(chart.from) >= 0 && today.compareTo(chart.to) <= 0) {
      final at = x(today);
      canvas.drawLine(
        Offset(at, 0),
        Offset(at, axis),
        Paint()
          ..color = t.color('glacier-red-9')
          ..strokeWidth = 1.5,
      );
    }

    var top = look.space(2);
    for (final section in chart.sections) {
      if (chart.named) {
        final name = _words(section.label, small, left - look.space(2));
        name.paint(canvas, Offset(0, top + (QueryGantt.barHeight - name.height) / 2));
        name.dispose();
      }
      for (final bar in section.bars) {
        final from = x(bar.start), to = math.max(x(bar.end), from + 3);
        final box = RRect.fromRectAndRadius(Rect.fromLTRB(from, top, to, top + QueryGantt.barHeight), const Radius.circular(4));
        // Done the faint ink, under way blue, the rest the ink; ringed in red once it is overdue.
        final Color fill = bar.done
            ? QueryLook.mix(look.ink4, 0.45)
            : bar.active
            ? t.colorOf('color-mix(in srgb, var(--glacier-blue-9) 55%, transparent)')
            : QueryLook.mix(look.ink2, 0.55);
        canvas.drawRRect(box, Paint()..color = fill);
        final Color edge = bar.crit ? t.color('glacier-red-9') : (bar.done ? look.ink4 : (bar.active ? t.color('glacier-blue-11') : look.ink2));
        canvas.drawRRect(
          box.deflate(0.75),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = edge,
        );
        // Its name beside it: after it where there is room, else before it, else over it.
        final style = small.copyWith(color: bar.done ? look.ink3 : look.ink, decoration: bar.done ? TextDecoration.lineThrough : TextDecoration.none, decorationColor: look.ink4);
        final after = size.width - to - look.space(1), before = from - left - look.space(1);
        final natural = _words(bar.name, style, double.infinity);
        final wide = natural.width;
        natural.dispose();
        final Offset at;
        final double roomFor;
        if (wide <= after || after >= before) {
          roomFor = after;
          at = Offset(to + look.space(1), 0);
        } else {
          roomFor = before;
          at = Offset(from - look.space(1) - math.min(wide, before), 0);
        }
        final name = _words(bar.name, style, roomFor);
        name.paint(canvas, Offset(at.dx, top + (QueryGantt.barHeight - name.height) / 2));
        name.dispose();
        top += QueryGantt.barHeight + QueryGantt.barGap;
      }
      top += QueryGantt.barGap;
    }

  }

  @override
  bool shouldRepaint(GanttPainter oldDelegate) => !identical(oldDelegate.chart, chart) || oldDelegate.today != today || oldDelegate.left != left || !identical(oldDelegate.look, look);
}
