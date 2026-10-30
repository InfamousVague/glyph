/// A query's calendar on a wide window, and what carries a record from one day to another on any calendar (the
/// port's own; Matt, 2026-10-30, "add all 12"). The phone's month is query_view.dart's `QueryCalendar`, the web's
/// own: dots on the days and the day picked listed under it, a record held and carried from that list onto a day of
/// the month. A window wide enough for words in a day (a desktop, a tablet, the Fold open) draws this instead:
///
/// - **Month** and **Week**: a month's weeks with each record's name in its day (three, then "+ n more", which opens
///   the week), or one week's seven days with every record in each; the arrows turn a month or a week, Today comes
///   back to today's.
/// - **Carried.** Where what the query lists can be changed, a record's chip is carried to another day (at once on
///   a desktop, after holding it on a phone or a tablet), and the field its day is from (the query's `date:`, else the
///   first day field it has) is set to the day it is dropped on: a note's front matter, a to-do's line.
/// - A tap on a record opens it. The calendars' events, beside a calendar of to-dos, are quieter and never carried.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/properties.dart' show StatusCategory;
import '../../core/query/query.dart';
import '../items/field_chips.dart' show daySaid;
import 'query_layout.dart';
import 'query_look.dart';
import 'query_parts.dart';

/// How wide a calendar's room must be for words in its days.
const double wideCalendar = 560;

/// Whether [row] can be carried to another day: a record in a note, with a day from a field that can be written.
bool carriesDay(QueryRow row, QueryActs acts) => acts.editable && acts.onSet != null && row.kind != RecordKind.event && row.dayField != 'updated';

/// [child], carried as [row] where [enabled], as a chip of its name: at once on a desktop, where a pointer carries
/// it, and after holding it on a phone or a tablet, where a finger's swipe is the page's to scroll.
Widget carriedDay({required QueryLook look, required QueryRow row, required bool enabled, required Widget child}) {
  if (!enabled) return child;
  final feedback = _Chip(look: look, row: row, lifted: true);
  final ghost = Opacity(opacity: 0.35, child: child);
  final desktop = switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
    _ => false,
  };
  if (desktop) return Draggable<QueryRow>(data: row, feedback: feedback, childWhenDragging: ghost, onDragStarted: () => fireMotor(HapticKind.selection), child: child);
  return LongPressDraggable<QueryRow>(data: row, hapticFeedbackOnStart: false, onDragStarted: () => fireMotor(HapticKind.selection), feedback: feedback, childWhenDragging: ghost, child: child);
}

/// A day a carried record is dropped on: the field its day is from set to [day]. Lit while one is over it.
class DayDrop extends StatelessWidget {
  const DayDrop({super.key, required this.look, required this.day, required this.onDay, required this.child, this.radius});

  final QueryLook look;
  final String day;
  final void Function(QueryRow row, String day)? onDay;
  final Widget child;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final drop = onDay;
    if (drop == null) return child;
    return DragTarget<QueryRow>(
      onWillAcceptWithDetails: (details) => details.data.day != day,
      onAcceptWithDetails: (details) => drop(details.data, day),
      builder: (context, over, _) => over.isEmpty
          ? child
          : Container(
              foregroundDecoration: BoxDecoration(color: QueryLook.mix(look.ink, 0.06), borderRadius: radius, border: Border.all(color: QueryLook.mix(look.ink, 0.45), width: 1.5)),
              child: child,
            ),
    );
  }
}

/// A record in a day, as words: its key and its name, quiet once it is done, red once it is late.
class _Chip extends StatelessWidget {
  const _Chip({required this.look, required this.row, this.lifted = false, this.event = false});

  final QueryLook look;
  final QueryRow row;
  final bool lifted;
  final bool event;

  @override
  Widget build(BuildContext context) {
    final done = row.category == StatusCategory.done || row.done == true;
    final late = row.overdue;
    final colour = event ? look.ink3 : (done ? look.ink3 : (late ? look.t.color('glacier-red-11') : look.ink));
    final ground = event ? null : (late ? look.t.colorOf('color-mix(in oklch, var(--glacier-red-9) 12%, transparent)') : QueryLook.mix(look.ink, 0.06));
    final id = row.id;
    final words = id != null && id.isNotEmpty ? '$id ${row.name}' : row.name;
    final hours = event ? _hours(row) : null;
    Widget chip = Container(
      padding: EdgeInsets.symmetric(horizontal: look.space(1) + 1, vertical: 1),
      decoration: BoxDecoration(
        color: lifted ? look.paper2 : ground,
        borderRadius: BorderRadius.circular(look.t.radius('sm')),
        border: event ? Border.all(color: QueryLook.mix(look.ink3, 0.4), width: look.hair) : null,
        boxShadow: lifted ? const <BoxShadow>[BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))] : null,
      ),
      child: Text(
        hours == null ? words : '$hours $words',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        textScaler: TextScaler.noScaling,
        style: look.sans(look.xs, color: colour, struck: done && !event, strike: look.ink4),
      ),
    );
    if (lifted) chip = ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: chip);
    return Part('dayChip', child: chip);
  }

  static String? _hours(QueryRow row) {
    for (final cell in row.cells) {
      if (cell is TextCell && RegExp(r'^\d{2}:\d{2}').hasMatch(cell.text)) return cell.text.substring(0, 5);
    }
    return null;
  }
}

const List<String> _weekdayNames = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The calendar on a wide window: a month of named days, or a week.
class QueryWideCalendar extends StatefulWidget {
  const QueryWideCalendar({super.key, required this.look, required this.rows, required this.acts, required this.events, required this.month, required this.onMonth, required this.onDay});

  final QueryLook look;
  final List<QueryRow> rows;
  final QueryActs acts;
  final List<QueryRow> events;

  /// The month shown, `YYYY-MM`, the phone's month's own, so the two agree as the window is made wider or narrower.
  final String month;
  final void Function(String month) onMonth;

  /// A record dropped on a day.
  final void Function(QueryRow row, String day)? onDay;

  @override
  State<QueryWideCalendar> createState() => QueryWideCalendarState();
}

class QueryWideCalendarState extends State<QueryWideCalendar> {
  /// The week shown, its Monday; null for the month.
  String? week;

  QueryLook get look => widget.look;
  QueryActs get acts => widget.acts;

  void _turn(int by) {
    fireMotor(HapticKind.selection);
    final shown = week;
    if (shown != null) {
      final next = weekAfter(shown, by);
      setState(() => week = next);
      widget.onMonth(monthOf(next));
      return;
    }
    widget.onMonth(monthAfter(widget.month, by));
  }

  void _today() {
    fireMotor(HapticKind.selection);
    if (week != null) setState(() => week = mondayOf(acts.today));
    widget.onMonth(monthOf(acts.today));
  }

  /// Opens the week [day] is in.
  void openWeek(String day) {
    fireMotor(HapticKind.selection);
    setState(() => week = mondayOf(day));
  }

  Map<String, List<QueryRow>> _byDay(List<QueryRow> rows) {
    final into = <String, List<QueryRow>>{};
    for (final row in rows) {
      final day = row.day;
      if (day != null) into.putIfAbsent(day, () => <QueryRow>[]).add(row);
    }
    return into;
  }

  Widget _round(LucideIcon icon, String label, VoidCallback onTap) => Semantics(
    container: true,
    button: true,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(width: look.space(8), height: look.space(8), child: Center(child: AppIcon(icon, size: look.em, strokeWidth: 2.4, color: look.ink3))),
    ),
  );

  Widget _pill(String label, String said, bool here, VoidCallback onTap) => Semantics(
    container: true,
    button: true,
    selected: here,
    label: said,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: look.space(2), vertical: look.space(1)),
        decoration: here ? ShapeDecoration(color: look.t.color('glacier-bg'), shape: const StadiumBorder(), shadows: const <BoxShadow>[BoxShadow(color: Color(0x29000000), offset: Offset(0, 1), blurRadius: 2)]) : null,
        child: PageWords(label, look.sans(look.xs, weight: 'semibold', color: here ? look.ink : look.ink3), line: look.lineXs, softWrap: false),
      ),
    ),
  );

  /// A record in a day: a chip that opens it, carried where it can be.
  Widget _record(QueryRow row) {
    final chip = Semantics(
      container: true,
      button: true,
      label: row.id != null && row.id!.isNotEmpty ? '${row.id} ${row.name}' : row.name,
      onTap: () => acts.onOpen(row),
      excludeSemantics: true,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => acts.onOpen(row), child: _Chip(look: look, row: row)),
    );
    return carriedDay(look: look, row: row, enabled: carriesDay(row, acts), child: chip);
  }

  Widget _date(CalendarDay day, {bool long = false}) {
    final words = long ? '${_weekdayNames[(DateTime.parse(day.day).weekday - 1)]} ${day.date}' : '${day.date}';
    final style = look.sans(look.xs, weight: day.today ? 'semibold' : 'regular', color: day.today ? look.paper : (day.inMonth ? look.ink2 : look.ink4), tabular: true);
    final text = PageWords(words, style, line: pageLine(look.xs, 1.6), softWrap: false);
    if (!day.today) return Part('date', child: text);
    return Part(
      'date',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 0.5 * look.xs),
        decoration: ShapeDecoration(color: look.ink, shape: const StadiumBorder()),
        child: text,
      ),
    );
  }

  Widget _day(CalendarDay day, List<QueryRow> events, {required bool all, required double height}) {
    final radius = BorderRadius.circular(look.t.radius('sm'));
    final shown = all ? day.rows : day.rows.take(math.max(0, 3 - math.min(events.length, 1))).toList();
    final more = day.rows.length - shown.length;
    final count = day.rows.length;
    final said = '${daySaid(day.day, acts.today, acts.locale)}${count > 0 ? ', $count ${count == 1 ? 'thing' : 'things'}' : ''}';
    return DayDrop(
      look: look,
      day: day.day,
      onDay: widget.onDay,
      radius: radius,
      child: Semantics(
        container: true,
        label: said,
        child: Part(
          'dayCell',
          child: Container(
            constraints: BoxConstraints(minHeight: height),
            padding: EdgeInsets.all(look.space(1)),
            decoration: BoxDecoration(color: day.inMonth ? look.paper : null, borderRadius: radius),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Align(alignment: Alignment.centerLeft, child: _date(day, long: all)),
                for (final event in all ? events : events.take(1)) Padding(padding: const EdgeInsets.only(top: 2), child: _Chip(look: look, row: event, event: true)),
                for (final row in shown) Padding(padding: const EdgeInsets.only(top: 2), child: _record(row)),
                if (more > 0 || (!all && events.length > 1))
                  Semantics(
                    button: true,
                    label: 'Show the week of ${daySaid(day.day, acts.today, acts.locale)}',
                    onTap: () => openWeek(day.day),
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => openWeek(day.day),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Part('more', child: PageWords('+ ${more + (all ? 0 : math.max(0, events.length - 1))} more', look.sans(look.xs, color: look.ink3), line: look.lineXs, softWrap: false)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _weekRow(List<Widget> cells) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (index, cell) in cells.indexed) ...<Widget>[if (index > 0) const SizedBox(width: 2), Expanded(child: cell)],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final eventsOn = _byDay(widget.events);
    final shownWeek = week;
    final heading = shownWeek == null ? monthName(widget.month, acts.locale) : weekName(shownWeek);
    final count = shownWeek == null ? inMonth(rows, widget.month) : inWeek(rows, shownWeek);
    final onToday = shownWeek == null ? widget.month == monthOf(acts.today) : shownWeek == mondayOf(acts.today);
    final undated = rows.where((row) => row.day == null).length;
    final bar = Part(
      'monthBar',
      child: Row(
        children: <Widget>[
          _round(Lucide.chevronLeft, shownWeek == null ? 'The month before' : 'The week before', () => _turn(-1)),
          SizedBox(width: look.space(1)),
          Part(
            'monthName',
            child: Semantics(
              liveRegion: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  PageWords(heading, look.sans(look.em, weight: 'semibold'), line: look.line, softWrap: false),
                  SizedBox(width: look.space(2)),
                  Part('count', child: PageWords('$count', look.sans(look.xs, weight: 'semibold', color: look.ink3, tabular: true), line: look.lineXs, softWrap: false)),
                ],
              ),
            ),
          ),
          SizedBox(width: look.space(1)),
          _round(Lucide.chevronRight, shownWeek == null ? 'The month after' : 'The week after', () => _turn(1)),
          const Spacer(),
          if (!onToday) ...<Widget>[_pill('Today', shownWeek == null ? 'Today’s month' : 'This week', false, _today), SizedBox(width: look.space(2))],
          Container(
            padding: const EdgeInsets.all(2),
            decoration: ShapeDecoration(color: QueryLook.mix(look.ink3, 0.1), shape: const StadiumBorder()),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _pill('Month', 'Show the month', shownWeek == null, () {
                  if (week == null) return;
                  fireMotor(HapticKind.selection);
                  setState(() => week = null);
                }),
                _pill('Week', 'Show a week', shownWeek != null, () {
                  if (week != null) return;
                  final today = acts.today;
                  openWeek(monthOf(today) == widget.month ? today : '${widget.month}-01');
                }),
              ],
            ),
          ),
        ],
      ),
    );
    final head = _weekRow(<Widget>[
      for (final name in _weekdayNames)
        Semantics(
          label: name,
          excludeSemantics: true,
          child: Part('weekday', child: Padding(padding: EdgeInsets.symmetric(vertical: look.space(1)), child: PageWords(name, look.sans(look.xs, color: look.ink3), line: look.lineXs, softWrap: false))),
        ),
    ]);
    final Widget body;
    if (shownWeek == null) {
      final weeks = monthWeeks(widget.month, rows, acts.today);
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          head,
          for (final one in weeks) ...<Widget>[
            const SizedBox(height: 2),
            _weekRow(<Widget>[for (final day in one) _day(day, eventsOn[day.day] ?? const <QueryRow>[], all: false, height: 84)]),
          ],
        ],
      );
    } else {
      final days = weekDays(shownWeek, rows, acts.today);
      body = _weekRow(<Widget>[for (final day in days) _day(day, eventsOn[day.day] ?? const <QueryRow>[], all: true, height: 180)]);
    }
    return Part(
      'calendar',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          bar,
          SizedBox(height: look.space(2)),
          Part('month', child: Semantics(container: true, label: heading, child: body)),
          if (undated > 0)
            Padding(
              padding: EdgeInsets.only(top: look.space(2)),
              child: Part(
                'warning',
                child: PageWords(undated == 1 ? 'One has no day, and is not on the calendar.' : '$undated have no day, and are not on the calendar.', look.sans(look.em, color: look.ink3), line: look.line),
              ),
            ),
        ],
      ),
    );
  }
}
