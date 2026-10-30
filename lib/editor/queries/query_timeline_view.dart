/// A query drawn as a timeline (`show: timeline`, lib/core/query/timeline.dart; Matt, 2026-10-30, "add all 12"): a
/// Gantt chart the app draws itself, where the Mermaid gantt (`show: gantt`, query_timeline.dart) is a picture.
///
/// - **Rows.** A record a row, its name on the left where it stays as the days scroll sideways under it, in its
///   query's groups (as a board's lanes are), each group's name and count over its rows.
/// - **Bars.** From the day in its start field to the end of the day in its end field (`start:` and `end:`, `start`
///   and `due` unsaid): one under way in the activity work's sync blue, one done quiet, one overdue red, the rest in
///   the ink. A record with one of the two is a bar of a day; one with neither is counted under the rows.
/// - **Today** is a line down the days, and Today in the bar above scrolls to it; Week, Month and Quarter zoom.
/// - **Carried.** Where what the query lists can be changed, a bar's ends are carried to other days (each end
///   writes its own field into the record's front matter, or a to-do's line), and the middle of a bar carries both
///   once it is held, as everything carried in the app is (lib/core/hold_drag.dart [holdTime]), so a swipe across
///   scrolls. A tap on a bar, or on a row's name, opens it.
///
/// The days, the ticks, today and every bar are drawn by one painter, and a carry repaints that painter alone, so a
/// thousand rows cost a frame what ten do: each row's name is the only widget a row has.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../../core/days.dart' show daysBetween;
import '../../core/hold_drag.dart' show holdTime;
import '../../core/properties.dart' show StatusCategory;
import '../../core/query/query.dart';
import '../items/field_chips.dart' show daySaid;
import 'query_layout.dart';
import 'query_look.dart';
import 'query_parts.dart';

/// How tall a row is, a group's head, and the days' head.
const double timelineRow = 32;
const double timelineLaneHead = 28;
const double timelineDaysHead = 34;

/// A bar being carried: which, by which ends, and how many days so far.
class _Carry {
  const _Carry(this.bar, {required this.start, required this.end, this.by = 0});
  final TimelineBar bar;
  final bool start;
  final bool end;
  final int by;
  _Carry moved(int by) => _Carry(bar, start: start, end: end, by: by);
}

/// What a row of the timeline is: a group's head, or a bar's row.
class _Line {
  const _Line.head(this.lane) : bar = null;
  const _Line.bar(this.lane, TimelineBar this.bar);
  final TimelineLane lane;
  final TimelineBar? bar;
}

/// Where each row is, from the top of the rows.
class TimelineRows {
  TimelineRows(this.plan) {
    final grouped = plan.lanes.length > 1 || plan.lanes.any((lane) => lane.group.label.isNotEmpty);
    var y = 0.0;
    for (final lane in plan.lanes) {
      if (grouped) {
        _lines.add(_Line.head(lane));
        _tops.add(y);
        y += timelineLaneHead;
      }
      for (final bar in lane.bars) {
        _lines.add(_Line.bar(lane, bar));
        _tops.add(y);
        y += timelineRow;
      }
    }
    height = y;
  }

  final TimelinePlan plan;
  final List<_Line> _lines = <_Line>[];
  final List<double> _tops = <double>[];
  late final double height;

  int get length => _lines.length;
  double top(int index) => _tops[index];
  double heightOf(int index) => _lines[index].bar == null ? timelineLaneHead : timelineRow;
  TimelineBar? barAt(int index) => _lines[index].bar;
  TimelineLane laneAt(int index) => _lines[index].lane;

  /// The row at [y], by halving: rows are in order.
  int? at(double y) {
    if (y < 0 || y >= height || _tops.isEmpty) return null;
    var low = 0, high = _tops.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_tops[mid] <= y) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}

class QueryTimelineView extends StatefulWidget {
  const QueryTimelineView({super.key, required this.look, required this.result, required this.acts});

  final QueryLook look;
  final QueryResult result;
  final QueryActs acts;

  @override
  State<QueryTimelineView> createState() => QueryTimelineViewState();
}

class QueryTimelineViewState extends State<QueryTimelineView> {
  late TimelineZoom? _zoom = widget.result.zoom;
  final ScrollController _across = ScrollController();
  final ValueNotifier<_Carry?> _carry = ValueNotifier<_Carry?>(null);
  bool _placed = false;

  TimelinePlan? _plan;
  QueryResult? _planned;
  TimelineZoom? _plannedZoom;

  /// The plan, worked out again only when the result or the zoom changes.
  TimelinePlan get plan {
    if (_plan == null || !identical(_planned, widget.result) || _plannedZoom != _zoom) {
      _plan = timelineOf(widget.result.groups, widget.acts.today, zoom: _zoom);
      _planned = widget.result;
      _plannedZoom = _zoom;
    }
    return _plan!;
  }

  double get dayWide => dayWidth(plan.zoom);

  /// Whether a bar can be carried.
  bool get carries => widget.acts.editable && widget.acts.onSet != null;

  @override
  void didUpdateWidget(QueryTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.zoom != widget.result.zoom) _zoom = widget.result.zoom;
  }

  @override
  void dispose() {
    _across.dispose();
    _carry.dispose();
    super.dispose();
  }

  /// Scrolls the days so today is a quarter of the way in.
  void toToday({bool animate = true}) {
    if (!_across.hasClients) return;
    final view = _across.position.viewportDimension;
    final to = (plan.today * dayWide - view / 4).clamp(0.0, _across.position.maxScrollExtent);
    if (animate) {
      _across.animateTo(to, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
    } else {
      _across.jumpTo(to);
    }
  }

  void _setZoom(TimelineZoom zoom) {
    if (zoom == plan.zoom) return;
    fireMotor(HapticKind.selection);
    setState(() {
      _zoom = zoom;
      _placed = false;
    });
  }

  /// What a press at [at] on the days is on: a bar, and which of its ends it takes.
  ({TimelineBar bar, bool start, bool end})? grip(Offset at, TimelineRows rows) {
    final index = rows.at(at.dy - timelineDaysHead);
    if (index == null) return null;
    final bar = rows.barAt(index);
    if (bar == null) return null;
    final left = bar.from * dayWide;
    final right = bar.to * dayWide;
    const reach = 10.0;
    if (at.dx < left - reach || at.dx > right + reach) return null;
    final width = right - left;
    // A narrow bar is two halves; a wide one has its ends and its middle.
    if (width < 3 * reach) return at.dx < left + width / 2 ? (bar: bar, start: true, end: false) : (bar: bar, start: false, end: true);
    if (at.dx <= left + reach) return (bar: bar, start: true, end: false);
    if (at.dx >= right - reach) return (bar: bar, start: false, end: true);
    return (bar: bar, start: true, end: true);
  }

  void _put(_Carry carry) {
    final onSet = widget.acts.onSet;
    if (onSet == null || carry.by == 0) return;
    final bar = carry.bar;
    final next = movedBar(bar.start, bar.end, carry.by, moveStart: carry.start, moveEnd: carry.end);
    final result = widget.result;
    fireMotor(HapticKind.selection);
    if (next.start != bar.start || (carry.start && bar.row.start == null)) onSet(bar.row, result.startField, next.start);
    if (result.endField != result.startField && (next.end != bar.end || (carry.end && bar.row.end == null))) onSet(bar.row, result.endField, next.end);
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final plan = this.plan;
    final rows = TimelineRows(plan);
    if (!_placed) {
      _placed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) toToday(animate: false);
      });
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 560;
        final names = wide ? 200.0 : 112.0;
        final width = plan.days * dayWide;
        final height = timelineDaysHead + rows.height;
        final painter = _DaysPainter(plan: plan, rows: rows, look: look, carry: _carry, dayWide: dayWide, said: (bar) => '${bar.row.name}, ${daySaid(bar.start, widget.acts.today, widget.acts.locale)} to ${daySaid(bar.end, widget.acts.today, widget.acts.locale)}', open: widget.acts.onOpen);
        final days = RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(TapGestureRecognizer.new, (tap) {
              tap.onTapUp = (details) {
                final index = rows.at(details.localPosition.dy - timelineDaysHead);
                final bar = index == null ? null : rows.barAt(index);
                if (bar == null) return;
                final x = details.localPosition.dx;
                if (x >= bar.from * dayWide - 6 && x <= bar.to * dayWide + 6) widget.acts.onOpen(bar.row);
              };
            }),
            if (carries)
              _BarDrag: GestureRecognizerFactoryWithHandlers<_BarDrag>(() => _BarDrag(allowed: (at, kind) {
                    final found = grip(at, rows);
                    // A bar's ends are taken at once; its middle is the app's one carry, held first, so a swipe scrolls.
                    return found != null && !(found.start && found.end);
                  }), (drag) {
                double from = 0;
                drag.onStart = (details) {
                  final found = grip(details.localPosition, rows);
                  if (found == null) return;
                  from = details.localPosition.dx;
                  _carry.value = _Carry(found.bar, start: found.start, end: found.end);
                };
                drag.onUpdate = (details) {
                  final carry = _carry.value;
                  if (carry == null) return;
                  final by = ((details.localPosition.dx - from) / dayWide).round();
                  if (by != carry.by) {
                    fireMotor(HapticKind.selection);
                    _carry.value = carry.moved(by);
                  }
                };
                drag.onEnd = (_) {
                  final carry = _carry.value;
                  _carry.value = null;
                  if (carry != null) _put(carry);
                };
                drag.onCancel = () => _carry.value = null;
              }),
            if (carries)
              LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(() => LongPressGestureRecognizer(duration: holdTime), (press) {
                double from = 0;
                press.onLongPressStart = (details) {
                  final found = grip(details.localPosition, rows);
                  if (found == null) return;
                  from = details.localPosition.dx;
                  fireMotor(HapticKind.selection);
                  _carry.value = _Carry(found.bar, start: true, end: true);
                };
                press.onLongPressMoveUpdate = (details) {
                  final carry = _carry.value;
                  if (carry == null) return;
                  final by = ((details.localPosition.dx - from) / dayWide).round();
                  if (by != carry.by) _carry.value = carry.moved(by);
                };
                press.onLongPressEnd = (_) {
                  final carry = _carry.value;
                  _carry.value = null;
                  if (carry != null) _put(carry);
                };
                press.onLongPressCancel = () => _carry.value = null;
              }),
          },
          child: RepaintBoundary(child: CustomPaint(key: const ValueKey<String>('query-timeline'), size: Size(width, height), painter: painter)),
        );
        final titles = SizedBox(
          width: names,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: timelineDaysHead),
              for (var index = 0; index < rows.length; index += 1) _title(look, rows, index),
            ],
          ),
        );
        return Part(
          'timeline',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _bar(look),
              SizedBox(height: look.space(2)),
              if (plan.bars == 0)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: look.space(1)),
                  child: Part('empty', child: PageWords('Nothing has a day to put on the timeline.', look.sans(look.em, color: look.ink3), line: look.line)),
                )
              else
                Part(
                  'timelineRows',
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: look.paper, borderRadius: BorderRadius.circular(look.t.radius('md'))),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(look.t.radius('md')),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          titles,
                          Container(width: look.hair, height: height, color: look.rule),
                          Expanded(child: SingleChildScrollView(key: const ValueKey<String>('timeline-days'), controller: _across, scrollDirection: Axis.horizontal, child: days)),
                        ],
                      ),
                    ),
                  ),
                ),
              if (plan.undated > 0)
                Padding(
                  padding: EdgeInsets.only(top: look.space(2)),
                  child: Part(
                    'warning',
                    child: PageWords(plan.undated == 1 ? 'One has no days, and is not on the timeline.' : '${plan.undated} have no days, and are not on the timeline.', look.sans(look.em, color: look.ink3), line: look.line),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// A row's name, or a group's head, on the left.
  Widget _title(QueryLook look, TimelineRows rows, int index) {
    final bar = rows.barAt(index);
    if (bar == null) {
      final lane = rows.laneAt(index);
      return SizedBox(
        height: timelineLaneHead,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: look.space(2)),
          child: Row(
            children: <Widget>[
              Flexible(child: Part('laneName', child: PageWords(lane.group.label, look.sans(look.xs, weight: 'semibold', color: look.ink2), line: look.lineXs, maxLines: 1, overflow: TextOverflow.ellipsis))),
              SizedBox(width: look.space(1)),
              PageWords('${lane.bars.length}', look.sans(look.xs, color: look.ink3, tabular: true), line: look.lineXs, softWrap: false),
            ],
          ),
        ),
      );
    }
    final row = bar.row;
    final done = row.category == StatusCategory.done || row.done == true;
    final id = row.id;
    return Semantics(
      container: true,
      button: true,
      label: id != null && id.isNotEmpty ? '$id ${row.name}' : row.name,
      onTap: () => widget.acts.onOpen(row),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.acts.onOpen(row),
        child: Part(
          'timelineName',
          child: Container(
            height: timelineRow,
            padding: EdgeInsets.symmetric(horizontal: look.space(2)),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: QueryLook.mix(look.rule, 0.6), width: look.hair))),
            child: PageWords(
              id != null && id.isNotEmpty ? '$id  ${row.name}' : row.name,
              look.sans(look.xs, color: done ? look.ink3 : look.ink, struck: done, strike: look.ink4),
              line: look.lineXs,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  /// Today, and the zooms.
  Widget _bar(QueryLook look) {
    Widget button(String label, String said, bool here, VoidCallback onTap) => Semantics(
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
    final zoom = plan.zoom;
    return Part(
      'timelineBar',
      child: Row(
        children: <Widget>[
          button('Today', 'Scroll to today', false, () {
            fireMotor(HapticKind.selection);
            toToday();
          }),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: ShapeDecoration(color: QueryLook.mix(look.ink3, 0.1), shape: const StadiumBorder()),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final each in TimelineZoom.values)
                  button('${each.name[0].toUpperCase()}${each.name.substring(1)}', 'Zoom to a ${each.name}', zoom == each, () => _setZoom(each)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A drag that starts only where [allowed] says, so a swipe that is not on a bar scrolls the days.
class _BarDrag extends HorizontalDragGestureRecognizer {
  // From where the press went down, so the end it took is the end it carries.
  _BarDrag({required this.allowed}) : super(supportedDevices: null) {
    dragStartBehavior = DragStartBehavior.down;
  }

  final bool Function(Offset at, PointerDeviceKind kind) allowed;

  @override
  bool isPointerAllowed(PointerEvent event) => allowed(event.localPosition, event.kind) && super.isPointerAllowed(event);
}

class _DaysPainter extends CustomPainter {
  _DaysPainter({required this.plan, required this.rows, required this.look, required this.carry, required this.dayWide, required this.said, required this.open}) : super(repaint: carry);

  final TimelinePlan plan;
  final TimelineRows rows;
  final QueryLook look;
  final ValueListenable<_Carry?> carry;
  final double dayWide;
  final String Function(TimelineBar bar) said;
  final void Function(QueryRow row) open;

  Color _ink(QueryRow row) {
    final t = look.t;
    if (row.category == StatusCategory.done || row.done == true) return QueryLook.mix(look.ink3, 0.55);
    if (row.overdue) return t.color('glacier-red-9');
    if (row.category == StatusCategory.doing) return t.color('activity-sync');
    return QueryLook.mix(look.ink, 0.72);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()
      ..color = QueryLook.mix(look.rule, 0.6)
      ..strokeWidth = look.hair;
    final strong = Paint()
      ..color = look.rule
      ..strokeWidth = look.hair;
    // The weekends, quiet, where a day is wide enough to see one.
    if (plan.zoom != TimelineZoom.quarter) {
      final weekend = Paint()..color = QueryLook.mix(look.ink, 0.03);
      final first = DateTime.parse(plan.first);
      for (var n = 0; n < plan.days; n += 1) {
        final weekday = (first.weekday - 1 + n) % 7;
        if (weekday >= 5) canvas.drawRect(Rect.fromLTWH(n * dayWide, timelineDaysHead, dayWide, size.height - timelineDaysHead), weekend);
      }
    }
    // The ticks and their days.
    for (final tick in plan.ticks) {
      final x = tick.at * dayWide;
      canvas.drawLine(Offset(x, tick.major ? 0 : timelineDaysHead - 8), Offset(x, size.height), tick.major ? strong : rule);
      final today = tick.at == plan.today;
      final painter = TextPainter(
        text: TextSpan(text: tick.label, style: look.sans(look.xs, weight: tick.major || today ? 'semibold' : 'regular', color: today ? look.ink : look.ink3, tabular: true)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final room = plan.zoom == TimelineZoom.week && !tick.major ? dayWide : double.infinity;
      final left = plan.zoom == TimelineZoom.week ? x + (math.min(room, dayWide) - painter.width) / 2 : x + 4;
      painter.paint(canvas, Offset(tick.major && plan.zoom == TimelineZoom.week ? x + 4 : left, (timelineDaysHead - painter.height) / 2));
    }
    canvas.drawLine(Offset(0, timelineDaysHead), Offset(size.width, timelineDaysHead), strong);
    // Each row's rule, and its bar.
    final carried = carry.value;
    for (var index = 0; index < rows.length; index += 1) {
      final top = timelineDaysHead + rows.top(index);
      canvas.drawLine(Offset(0, top), Offset(size.width, top), rule);
      final bar = rows.barAt(index);
      if (bar == null) continue;
      var from = bar.from;
      var to = bar.to;
      final moving = carried != null && identical(carried.bar, bar);
      if (moving) {
        final next = movedBar(bar.start, bar.end, carried.by, moveStart: carried.start, moveEnd: carried.end);
        from = bar.from + (daysBetween(bar.start, next.start) ?? 0);
        to = bar.to + (daysBetween(bar.end, next.end) ?? 0);
      }
      final rect = Rect.fromLTRB(from * dayWide + 1, top + 7, math.max(from * dayWide + 6, to * dayWide - 1), top + timelineRow - 7);
      final ink = _ink(bar.row);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)), Paint()..color = ink);
      if (moving) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(7)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = look.ink,
        );
        final next = movedBar(bar.start, bar.end, carried.by, moveStart: carried.start, moveEnd: carried.end);
        final words = next.start == next.end ? next.start : '${next.start} – ${next.end}';
        final painter = TextPainter(text: TextSpan(text: words, style: look.sans(look.xs, weight: 'semibold', color: look.ink, tabular: true)), textDirection: TextDirection.ltr)..layout();
        painter.paint(canvas, Offset(rect.right + 6, top + (timelineRow - painter.height) / 2));
      } else if (rect.width >= 10) {
        // The ends' grips, a notch each.
        final grip = Paint()..color = QueryLook.mix(look.paper, 0.7);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(rect.left + 3, rect.center.dy - 4, 2, 8), const Radius.circular(1)), grip);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(rect.right - 5, rect.center.dy - 4, 2, 8), const Radius.circular(1)), grip);
      }
    }
    // Today, a line down the days.
    if (plan.today >= 0 && plan.today < plan.days) {
      final x = (plan.today + 0.5) * dayWide;
      canvas.drawLine(
        Offset(x, timelineDaysHead - 4),
        Offset(x, size.height),
        Paint()
          ..color = look.ink
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(Offset(x, timelineDaysHead - 4), 3, Paint()..color = look.ink);
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) => <CustomPainterSemantics>[
    for (var index = 0; index < rows.length; index += 1)
      if (rows.barAt(index) case final bar?)
        CustomPainterSemantics(
          rect: Rect.fromLTRB(bar.from * dayWide, timelineDaysHead + rows.top(index), math.max(bar.from * dayWide + 8, bar.to * dayWide), timelineDaysHead + rows.top(index) + timelineRow),
          properties: SemanticsProperties(label: said(bar), button: true, onTap: () => open(bar.row), textDirection: TextDirection.ltr),
        ),
  ];

  @override
  bool shouldRepaint(_DaysPainter old) => !identical(old.plan, plan) || old.dayWide != dayWide || old.look.ink != look.ink || old.look.paper != look.paper;

  @override
  bool shouldRebuildSemantics(_DaysPainter old) => !identical(old.plan, plan) || old.dayWide != dayWide;
}
