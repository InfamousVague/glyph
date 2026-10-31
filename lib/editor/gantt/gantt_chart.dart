/// A Gantt chart the app draws itself (docs/GANTT.md; Matt, 2026-10-31: "work on making a better gannt chart
/// implementation in markdown replacing the one we have now that's quite hard to interact with"): what a ```gantt
/// fence draws (gantt.dart), and a query shown as one (lib/editor/queries/query_gantt.dart). It draws a [GanttModel]
/// and does what [GanttActions] lets it; every change is the actions', which write the fence's lines (or a ticket's
/// fields), so each is one step of the note's undo.
///
/// - **Rows.** A task a row, in its sections, each section's name and count over its rows; the names in a column on
///   the left that stays as the days scroll sideways under it.
/// - **Bars** from a task's first day to the end of its last, in its section's colour (or its person's, or its own
///   `colour:`), filled as far as it is along; a milestone a diamond; one with no days yet dashed; one done quiet.
///   In Calm every colour is the ink. An arrow runs from the end of each task to the start of what waits on it,
///   today is a line down the days, and with working days the weekends are shaded.
/// - **The days** along the top, in two rows: months over days, weeks or months as the zoom has room for. Zoom with
///   a pinch, with ctrl or cmd and the wheel (or the trackpad's pinch), or with − and +, Week, Month and Quarter.
///
/// What a hand does (each null action leaves its gesture out):
/// - **Carry** a bar to move it, its ends to make it longer or shorter; what waits on it is pushed along where the
///   chart follows, drawn as it would go while it is carried.
/// - **Drag from the round at a bar's end** to another bar: that one waits on it. A loop is refused, and said. A
///   click on an arrow takes the wait off.
/// - **Double-click, or long-press, empty days** in a row to add a task there.
/// - **Click a bar** for its panel (gantt_panel.dart): its name, days, person, how far along, what it waits on and
///   its colour. Delete takes it out, Enter adds the next task under it, the arrows move it a day and shift and the
///   arrows make it longer or shorter, up and down choose another, Escape lets go.
/// - **Drag a row's name** up or down, into another section too, to move its line.
/// - **On a phone** a tap chooses a bar, a long press then a drag carries it, the chosen bar's ends and its round are
///   taken at once, a second tap opens its panel as a sheet from the foot, and a row's name is held to be moved.
///
/// Drawn by one painter for the days and everything on them, which a carry repaints alone: the only widgets a row
/// has are its name's, so a chart of three hundred tasks carries a bar without building anything again
/// (test/gantt/gantt_chart_test.dart counts it).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../activity/job_mark.dart' show activityCalm;
import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/days.dart' show dateOfDay, daysBetween, isoDayAfter;
import '../../core/gantt/gantt.dart';
import '../../core/hold_drag.dart' show holdTime;
import '../queries/query_layout.dart' show Part, PageWords;
import '../queries/query_look.dart';
import 'gantt_panel.dart';

/// How tall a task's row is, a section's head, and the days' head.
const double ganttRow = 32;
const double ganttHead = 28;
const double ganttDaysHead = 40;

/// How wide a day is at each zoom, and the narrowest and widest a pinch makes one.
double ganttDayWidth(GanttZoom zoom) => switch (zoom) {
  GanttZoom.week => 44,
  GanttZoom.month => 16,
  GanttZoom.quarter => 6,
};
const double ganttNarrowest = 3;
const double ganttWidest = 96;

/// The zoom a chart opens at where `zoom:` is unsaid: as much as its bars span.
GanttZoom ganttZoomFor(int span) => span <= 21 ? GanttZoom.week : (span <= 120 ? GanttZoom.month : GanttZoom.quarter);

/// What the chart may do: each null where it cannot. A refusal comes back as the sentence to show.
class GanttActions {
  const GanttActions({
    this.move,
    this.addWait,
    this.removeWait,
    this.add,
    this.delete,
    this.moveRow,
    this.rename,
    this.setPeople,
    this.setProgress,
    this.setColour,
    this.setMilestone,
    this.setWaits,
    this.setFront,
    this.open,
    this.onText,
    this.undo,
    this.redo,
  });

  /// [key]'s days set, by [how]; what waits on it is the actions' to push.
  final String? Function(String key, String start, String end, GanttGrip how)? move;
  final String? Function(String key, String on)? addWait;
  final String? Function(String key, String on)? removeWait;

  /// A task added on [start] (to [end]) under [afterKey], or last in [group]: answers its key.
  final String? Function({String? afterKey, int? group, required String start, String? end})? add;
  final String? Function(String key)? delete;
  final String? Function(String key, int group, String? beforeKey)? moveRow;
  final String? Function(String key, String name)? rename;
  final String? Function(String key, List<String> people)? setPeople;
  final String? Function(String key, int? progress)? setProgress;
  final String? Function(String key, String? colour)? setColour;
  final String? Function(String key, bool milestone)? setMilestone;
  final String? Function(String key, List<String> names)? setWaits;

  /// A front line set, `follow` or `workdays`.
  final String? Function(String key, String? value)? setFront;

  /// Opens a ticket's note.
  final void Function(GanttItem item)? open;

  /// Shows the fence's own lines, to be typed.
  final VoidCallback? onText;
  final VoidCallback? undo;
  final VoidCallback? redo;

  bool get editable => move != null;
}

/// The hues a chart's sections take in turn, glacier's.
const List<String> ganttHues = <String>['blue', 'teal', 'green', 'amber', 'purple', 'red'];

/// The colour words a task's `colour:` can say, in the panel's order.
const List<String> ganttColours = <String>['blue', 'teal', 'green', 'amber', 'purple', 'red', 'gray'];

/// What a row of the chart is: a section's head, or a task's row.
class _Line {
  const _Line.head(this.group) : item = null;
  const _Line.item(this.group, GanttItem this.item);
  final int group;
  final GanttItem? item;
}

/// Where each row is, from the top of the rows.
class GanttRows {
  GanttRows(this.model) {
    final heads = model.groups.length > 1 || model.groups.any((group) => group.name.isNotEmpty);
    var y = 0.0;
    for (var index = 0; index < model.groups.length; index += 1) {
      final group = model.groups[index];
      if (heads) {
        _lines.add(_Line.head(index));
        _tops.add(y);
        y += ganttHead;
      }
      for (final item in group.items) {
        _index[item.key] = _lines.length;
        _lines.add(_Line.item(index, item));
        _tops.add(y);
        y += ganttRow;
      }
    }
    height = y;
  }

  final GanttModel model;
  final List<_Line> _lines = <_Line>[];
  final List<double> _tops = <double>[];
  final Map<String, int> _index = <String, int>{};
  late final double height;

  int get length => _lines.length;
  double top(int index) => _tops[index];
  double heightOf(int index) => _lines[index].item == null ? ganttHead : ganttRow;
  GanttItem? itemAt(int index) => _lines[index].item;
  int groupAt(int index) => _lines[index].group;
  int? indexOf(String key) => _index[key];

  /// The middle of [key]'s row.
  double? middleOf(String key) {
    final index = _index[key];
    return index == null ? null : _tops[index] + ganttRow / 2;
  }

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

  /// The gap nearest [y] between two rows, from 0 (above the first) to [length] (under the last).
  int gapAt(double y) {
    final index = at(y.clamp(0, height - 0.01));
    if (index == null) return 0;
    return y - _tops[index] < heightOf(index) / 2 ? index : index + 1;
  }

  /// Where a row let go in [gap] goes: its section, and the task it goes before there (null for last).
  ({int group, String? before}) landing(int gap) {
    final next = gap < _lines.length ? _lines[gap] : null;
    final previous = gap > 0 ? _lines[gap - 1] : null;
    if (next?.item != null) return (group: next!.group, before: next.item!.key);
    if (previous != null) return (group: previous.group, before: null);
    if (next != null) {
      final items = model.groups[next.group].items;
      return (group: next.group, before: items.isEmpty ? null : items.first.key);
    }
    return (group: 0, before: null);
  }
}

/// The days the chart shows: from [first], [count] of them, [wide] each.
class GanttFrame {
  GanttFrame({required this.first, required this.count, required this.wide});
  final String first;
  final int count;
  final double wide;

  /// Each day's place, worked out once: a carry asks for the same few hundred days every frame.
  final Map<String, double> _xs = <String, double>{};

  double get width => count * wide;
  double x(String day) => _xs[day] ??= (daysBetween(first, day) ?? 0) * wide;
  String dayAt(double x) => isoDayAfter(first, (x / wide).floor())!;

  /// The frame for [model] at [wide] a day, [room] wide at least: from a Monday a little before its first bar (or
  /// today) to a little after its last.
  factory GanttFrame.of(GanttModel model, double wide, double room) {
    final span = model.span;
    final low = model.today.compareTo(span.first) < 0 ? model.today : span.first;
    final high = model.today.compareTo(span.last) > 0 ? model.today : span.last;
    final pad = math.max(7, (room / wide / 4).ceil());
    var first = isoDayAfter(low, -pad)!;
    final at = dateOfDay(first)!;
    first = isoDayAfter(first, -(at.weekday - 1))!;
    final days = math.max((daysBetween(first, high) ?? 0) + 1 + pad, (room / wide).ceil() + 1);
    return GanttFrame(first: first, count: days, wide: wide);
  }
}

/// What a press on the days is on.
enum _Grip { move, start, end, link }

class _Hit {
  const _Hit({this.item, this.grip, this.arrow, this.row});
  final GanttItem? item;
  final _Grip? grip;

  /// An arrow: what waits, and what it waits on.
  final (String, String)? arrow;

  /// The row index the press is in.
  final int? row;
}

/// A bar or a round being carried, or a row's name.
class GanttDrag {
  const GanttDrag({required this.key, required this.grip, this.by = 0, this.moves = const <String, ({String start, String end})>{}, this.point, this.target, this.refused, this.gap});
  final String key;
  final String grip;
  final int by;

  /// Every bar's days as they would be if it were let go now: the carried one's and what it pushes.
  final Map<String, ({String start, String end})> moves;

  /// Where a wait's line is drawn to, and the bar it would land on; why that one cannot wait on it.
  final Offset? point;
  final String? target;
  final String? refused;

  /// The gap between rows a row's name would land in.
  final int? gap;
}

class GanttChart extends StatefulWidget {
  const GanttChart({super.key, required this.look, required this.model, this.actions = const GanttActions(), this.simple = false, this.label = 'Gantt chart', this.titled = true});

  final QueryLook look;
  final GanttModel model;
  final GanttActions actions;

  /// Simple mode (Preferences.simple): the panel's colour, follow and working days behind More.
  final bool simple;
  final String label;

  /// Whether the chart says its title over its bar (a fence's `title:`).
  final bool titled;

  @override
  State<GanttChart> createState() => GanttChartState();
}

class GanttChartState extends State<GanttChart> {
  /// How wide a day is: the fence's `zoom:`, or, until the chart is first laid out, as wide as fits its bars in.
  double? _wide;
  double get _dayWide => _wide ?? ganttDayWidth(widget.model.zoom ?? GanttZoom.month);
  set _dayWide(double value) => _wide = value;

  /// The day's width that fits every bar into [room], a little either side, no wider than a week's zoom.
  double _fit(double room) {
    final zoom = widget.model.zoom;
    if (zoom != null) return ganttDayWidth(zoom);
    final span = widget.model.span;
    final days = (daysBetween(span.first, span.last) ?? 0) + 1 + 4;
    return (room / days).clamp(ganttDayWidth(GanttZoom.quarter), ganttDayWidth(GanttZoom.week)).floorToDouble();
  }
  final ScrollController _across = ScrollController();
  final ValueNotifier<GanttDrag?> _drag = ValueNotifier<GanttDrag?>(null);
  final ValueNotifier<String?> _hover = ValueNotifier<String?>(null);
  final ValueNotifier<(String, String)?> _hoverArrow = ValueNotifier<(String, String)?>(null);
  final FocusNode _focus = FocusNode(debugLabel: 'Gantt chart');
  final LayerLink _anchor = LayerLink();
  bool _placed = false;
  double _room = 0;

  /// The task chosen, and the one whose panel is open.
  String? _selected;
  String? _editing;

  /// A sentence about what was just done or refused, and the clock that takes it away.
  String? _said;
  Timer? _saying;

  /// The last tap on empty days, to know a second one.
  ({Duration at, Offset where})? _lastTap;

  /// Two fingers on the days, for a pinch.
  final Map<int, Offset> _fingers = <int, Offset>{};
  double? _pinchFrom;
  double _pinchWide = 0;

  /// Where the carry going on started, how far it has gone at most, and by what.
  Offset _from = Offset.zero;
  double _far = 0;
  PointerDeviceKind _kind = PointerDeviceKind.mouse;

  GanttRows? _rows;
  GanttModel? _rowsFor;

  /// The rows, made again only when the model is.
  GanttRows get rows {
    if (_rows == null || !identical(_rowsFor, widget.model)) {
      _rows = GanttRows(widget.model);
      _rowsFor = widget.model;
    }
    return _rows!;
  }

  /// How many times the chart has been built, for the test that holds a carry to none.
  static int builds = 0;

  String? get selected => _selected;
  String? get editing => _editing;
  double get dayWide => _dayWide;
  ValueListenable<GanttDrag?> get drag => _drag;

  GanttFrame get frame {
    final made = _frame;
    if (made != null && identical(_frameFor, widget.model) && made.wide == _dayWide && _frameRoom == _room) return made;
    _frameFor = widget.model;
    _frameRoom = _room;
    return _frame = GanttFrame.of(widget.model, _dayWide, _room);
  }

  GanttFrame? _frame;
  GanttModel? _frameFor;
  double _frameRoom = -1;

  @override
  void didUpdateWidget(GanttChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A chosen task that is gone is let go of.
    if (_selected != null && widget.model.byKey[_selected!] == null) _selected = null;
    if (_editing != null && widget.model.byKey[_editing!] == null) _editing = null;
    if (oldWidget.model.zoom != widget.model.zoom && widget.model.zoom != null) _dayWide = ganttDayWidth(widget.model.zoom!);
  }

  @override
  void dispose() {
    _saying?.cancel();
    _across.dispose();
    _drag.dispose();
    _hover.dispose();
    _hoverArrow.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _say(String? words) {
    if (words == null) return;
    _saying?.cancel();
    setState(() => _said = words);
    _saying = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _said = null);
    });
  }

  /// Chooses [key], and the keyboard with it.
  void select(String? key, {bool edit = false}) {
    setState(() {
      _selected = key;
      _editing = edit ? key : null;
    });
    if (key != null && !_focus.hasFocus) _focus.requestFocus();
  }

  /// Scrolls the days so [day] is a quarter of the way in.
  void scrollTo(String day, {bool animate = true, bool edge = false}) {
    if (!_across.hasClients) return;
    final view = _across.position.viewportDimension;
    // A day's place a quarter of the way in, or, for the chart's first bar as it opens, two days from the edge.
    final to = (frame.x(day) - (edge ? 2 * _dayWide : view / 4)).clamp(0.0, _across.position.maxScrollExtent);
    if (animate) {
      _across.animateTo(to, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
    } else {
      _across.jumpTo(to);
    }
  }

  /// A day as wide as [wide], the day under [focal] (from the days' left edge on screen) kept where it is.
  void zoomTo(double wide, {double? focal}) {
    final next = wide.clamp(ganttNarrowest, ganttWidest);
    if (next == _dayWide) return;
    final had = frame;
    final offset = _across.hasClients ? _across.offset : 0.0;
    final at = focal ?? (_across.hasClients ? _across.position.viewportDimension / 2 : 0);
    final day = (offset + at) / had.wide;
    final dayKey = isoDayAfter(had.first, day.floor())!;
    final part = day - day.floor();
    setState(() => _dayWide = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_across.hasClients) return;
      final now = frame;
      final x = (now.x(dayKey) + part * now.wide) - at;
      _across.jumpTo(x.clamp(0.0, _across.position.maxScrollExtent));
    });
  }

  /// A bar's box on the days.
  Rect barRect(GanttItem item, GanttFrame frame, GanttRows rows, {({String start, String end})? days}) {
    if (days == null) {
      if (!identical(_rectsFor, frame) || !identical(_rectRows, rows)) {
        _rects.clear();
        _rectsFor = frame;
        _rectRows = rows;
      }
      return _rects[item.key] ??= _barRect(item, frame, rows, null);
    }
    return _barRect(item, frame, rows, days);
  }

  final Map<String, Rect> _rects = <String, Rect>{};
  GanttFrame? _rectsFor;
  GanttRows? _rectRows;

  Rect _barRect(GanttItem item, GanttFrame frame, GanttRows rows, ({String start, String end})? days) {
    final index = rows.indexOf(item.key);
    final top = ganttDaysHead + (index == null ? 0 : rows.top(index));
    final start = days?.start ?? item.start;
    final end = days?.end ?? item.end;
    final left = frame.x(start);
    if (item.milestone) {
      final middle = left + frame.wide / 2;
      return Rect.fromCenter(center: Offset(middle, top + ganttRow / 2), width: 16, height: 16);
    }
    final right = frame.x(end) + frame.wide;
    return Rect.fromLTRB(left + 1, top + 7, math.max(left + 6, right - 1), top + ganttRow - 7);
  }

  /// The round at a bar's end that a wait is drawn from.
  Offset knobOf(Rect bar) => Offset(bar.right + 11, bar.center.dy);

  /// The arrows: each wait's line, from the end of what is waited on to the start of what waits.
  List<({String from, String to, List<Offset> points})> arrows(GanttFrame frame, GanttRows rows, [Map<String, ({String start, String end})> moves = const {}]) {
    // Those of bars that stay where they are are worked out once for the frame; a carry works out its own.
    if (!identical(_arrowsFor, frame) || !identical(_arrowRows, rows)) {
      _arrowsFor = frame;
      _arrowRows = rows;
      _arrows = _arrowsOf(frame, rows, const {});
    }
    if (moves.isEmpty) return _arrows;
    return <({String from, String to, List<Offset> points})>[
      for (final arrow in _arrows)
        if (moves.containsKey(arrow.from) || moves.containsKey(arrow.to)) _arrowOf(arrow.from, arrow.to, frame, rows, moves) ?? arrow else arrow,
    ];
  }

  GanttFrame? _arrowsFor;
  GanttRows? _arrowRows;
  List<({String from, String to, List<Offset> points})> _arrows = const [];

  ({String from, String to, List<Offset> points})? _arrowOf(String on, String key, GanttFrame frame, GanttRows rows, Map<String, ({String start, String end})> moves) {
    final item = widget.model.byKey[key];
    final other = widget.model.byKey[on];
    if (item == null || other == null) return null;
    final a = barRect(other, frame, rows, days: moves[on]);
    final b = barRect(item, frame, rows, days: moves[item.key]);
    final x1 = a.right, y1 = a.center.dy, x2 = b.left, y2 = b.center.dy;
    final points = <Offset>[Offset(x1, y1)];
    if (x2 - 6 >= x1 + 6) {
      points.addAll(<Offset>[Offset(x1 + 6, y1), Offset(x1 + 6, y2), Offset(x2, y2)]);
    } else {
      final between = y2 > y1 ? b.top - 4 : b.bottom + 4;
      points.addAll(<Offset>[Offset(x1 + 6, y1), Offset(x1 + 6, between), Offset(x2 - 8, between), Offset(x2 - 8, y2), Offset(x2, y2)]);
    }
    return (from: on, to: item.key, points: points);
  }

  List<({String from, String to, List<Offset> points})> _arrowsOf(GanttFrame frame, GanttRows rows, Map<String, ({String start, String end})> moves) {
    final out = <({String from, String to, List<Offset> points})>[];
    for (final item in widget.model.items) {
      for (final on in item.after) {
        final other = widget.model.byKey[on];
        if (other == null) continue;
        final a = barRect(other, frame, rows, days: moves[on]);
        final b = barRect(item, frame, rows, days: moves[item.key]);
        final x1 = a.right, y1 = a.center.dy, x2 = b.left, y2 = b.center.dy;
        final points = <Offset>[Offset(x1, y1)];
        if (x2 - 6 >= x1 + 6) {
          points.addAll(<Offset>[Offset(x1 + 6, y1), Offset(x1 + 6, y2), Offset(x2, y2)]);
        } else {
          final between = y2 > y1 ? b.top - 4 : b.bottom + 4;
          points.addAll(<Offset>[Offset(x1 + 6, y1), Offset(x1 + 6, between), Offset(x2 - 8, between), Offset(x2 - 8, y2), Offset(x2, y2)]);
        }
        out.add((from: on, to: item.key, points: points));
      }
    }
    return out;
  }

  static double _toSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final length = ab.distanceSquared;
    if (length == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / length).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  /// What a press at [at] on the days is on; [touch] for a finger, which takes only the chosen bar's ends and round.
  _Hit _hit(Offset at, {bool touch = false}) {
    final frame = this.frame;
    final rows = this.rows;
    if (at.dy < ganttDaysHead) return const _Hit();
    final index = rows.at(at.dy - ganttDaysHead);
    final item = index == null ? null : rows.itemAt(index);
    _Hit? onBar(double reach) {
      if (item == null) return null;
      final bar = barRect(item, frame, rows);
      if (at.dx < bar.left - reach || at.dx > bar.right + reach || at.dy < bar.top - 6 || at.dy > bar.bottom + 6) return null;
      if (item.milestone) return _Hit(item: item, grip: _Grip.move, row: index);
      final grab = math.min(touch ? 14.0 : 7.0, bar.width / 3);
      if (at.dx <= bar.left + grab) return _Hit(item: item, grip: _Grip.start, row: index);
      if (at.dx >= bar.right - grab) return _Hit(item: item, grip: _Grip.end, row: index);
      return _Hit(item: item, grip: _Grip.move, row: index);
    }

    // On the bar itself first, then the round where it is shown (over another row's bar too), then near the bar.
    final on = onBar(0);
    if (on != null) return on;
    for (final key in <String?>[_selected, if (!touch) _hover.value]) {
      final shown = key == null ? null : widget.model.byKey[key];
      if (shown == null || widget.actions.addWait == null) continue;
      final knob = knobOf(barRect(shown, frame, rows));
      if ((at - knob).distance <= (touch ? 14 : 8)) return _Hit(item: shown, grip: _Grip.link, row: index);
    }
    for (final arrow in arrows(frame, rows)) {
      for (var n = 0; n + 1 < arrow.points.length; n += 1) {
        if (_toSegment(at, arrow.points[n], arrow.points[n + 1]) <= (touch ? 8 : 4)) return _Hit(arrow: (arrow.to, arrow.from), row: index);
      }
    }
    return onBar(touch ? 12 : 6) ?? _Hit(row: index);
  }

  /// Whether a press at [at] by [kind] is a grip taken at once: any bar's or round's for a mouse, the chosen bar's ends
  /// and round for a finger.
  bool takesAtOnce(Offset at, PointerDeviceKind kind) {
    if (!widget.actions.editable) return false;
    final touch = kind == PointerDeviceKind.touch;
    final found = _hit(at, touch: touch);
    if (found.item == null || found.grip == null) return false;
    if (found.grip == _Grip.link) return true;
    if (found.item!.ticket != null && widget.actions.move == null) return false;
    if (!touch) return true;
    return found.item!.key == _selected && found.grip != _Grip.move;
  }

  /// The days [item] has with its [grip] carried [by] days. Where the chart counts working days, a day carried onto a
  /// weekend goes on to the Monday (or back to the Friday, carried back), and a bar carried keeps its working days.
  ({String start, String end}) carried(GanttItem item, String grip, int by) {
    final workdays = widget.model.workdays;
    String snap(String day) {
      if (!workdays || !isWeekend(day)) return day;
      var at = day;
      while (isWeekend(at)) {
        at = isoDayAfter(at, by < 0 ? -1 : 1)!;
      }
      return at;
    }

    var start = item.start, end = item.end;
    if (grip == 'move' || item.milestone) {
      start = snap(isoDayAfter(start, by)!);
      end = item.milestone ? start : (workdays ? endAfter(start, lengthOf(item.start, item.end, workdays: true), workdays: true) : isoDayAfter(end, by)!);
    } else if (grip == 'start') {
      start = snap(isoDayAfter(start, by)!);
      if (start.compareTo(end) > 0) start = end;
    } else if (grip == 'end') {
      end = snap(isoDayAfter(end, by)!);
      if (end.compareTo(start) < 0) end = start;
    }
    return (start: start, end: end);
  }

  void _carry(GanttDrag drag, int by) {
    final item = widget.model.byKey[drag.key];
    if (item == null || by == drag.by) return;
    final days = carried(item, drag.grip, by);
    fireMotor(HapticKind.selection);
    _drag.value = GanttDrag(key: drag.key, grip: drag.grip, by: by, moves: followed(widget.model, <String, ({String start, String end})>{drag.key: days}));
  }

  void _letGo(GanttDrag drag) {
    final item = widget.model.byKey[drag.key];
    final move = widget.actions.move;
    if (item == null || move == null || (drag.by == 0 && !item.undated)) return;
    final days = carried(item, drag.grip, drag.by);
    fireMotor(HapticKind.success);
    _say(move(drag.key, days.start, days.end, switch (drag.grip) {
      'start' => GanttGrip.start,
      'end' => GanttGrip.end,
      _ => GanttGrip.move,
    }));
  }

  void _linkTo(GanttDrag drag, Offset point) {
    final found = _hit(point);
    final target = found.item?.key;
    String? refused;
    if (target != null && target != drag.key) refused = waitProblem(widget.model, target, drag.key);
    _drag.value = GanttDrag(key: drag.key, grip: 'link', point: point, target: target == drag.key ? null : target, refused: refused);
  }

  void _linkEnd(GanttDrag drag) {
    final target = drag.target;
    final addWait = widget.actions.addWait;
    if (target == null || addWait == null) return;
    final said = addWait(target, drag.key);
    fireMotor(said == null ? HapticKind.success : HapticKind.error);
    final item = widget.model.byKey[target];
    final other = widget.model.byKey[drag.key];
    _say(said ?? (item != null && other != null ? '“${item.name}” now waits on “${other.name}”.' : null));
  }

  /// A task added on [day] in [group], under [after]; chosen, its panel open for its name.
  void addAt(String day, {int? group, String? after}) {
    final add = widget.actions.add;
    if (add == null) return;
    fireMotor(HapticKind.selection);
    final key = add(afterKey: after, group: group, start: day, end: day);
    if (key != null) select(key, edit: true);
  }

  /// The next task under the chosen one: the working day after it ends, as long as it is.
  void addNext() {
    final item = _selected == null ? null : widget.model.byKey[_selected!];
    if (item == null) {
      addAt(widget.model.today, group: widget.model.groups.length - 1);
      return;
    }
    final add = widget.actions.add;
    if (add == null) return;
    final start = dayAfter(item.end, workdays: widget.model.workdays);
    final end = endAfter(start, lengthOf(item.start, item.end, workdays: widget.model.workdays), workdays: widget.model.workdays);
    final key = add(afterKey: item.key, group: item.group, start: start, end: item.milestone ? start : end);
    if (key != null) select(key, edit: true);
  }

  void _tapUp(TapUpDetails details) {
    final touch = details.kind == PointerDeviceKind.touch;
    final found = _hit(details.localPosition, touch: touch);
    final item = found.item;
    if (item != null) {
      fireMotor(HapticKind.selection);
      // A finger chooses, and a second tap opens; a mouse opens at once.
      select(item.key, edit: !touch || _selected == item.key);
      return;
    }
    final arrow = found.arrow;
    final remove = widget.actions.removeWait;
    if (arrow != null && remove != null) {
      final waiting = widget.model.byKey[arrow.$1];
      final on = widget.model.byKey[arrow.$2];
      fireMotor(HapticKind.selection);
      _hoverArrow.value = null;
      _say(remove(arrow.$1, arrow.$2) ?? (waiting != null && on != null ? '“${waiting.name}” no longer waits on “${on.name}”.' : null));
      return;
    }
    final now = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
    final last = _lastTap;
    if (last != null && now - last.at < const Duration(milliseconds: 400) && (details.localPosition - last.where).distance < 24 && found.row != null) {
      _lastTap = null;
      _addInRow(details.localPosition, found.row!);
      return;
    }
    _lastTap = (at: now, where: details.localPosition);
    if (_selected != null || _editing != null) select(null);
  }

  /// A task added where a press was in empty days of row [row]: in its section, under its task.
  void _addInRow(Offset at, int row) {
    final rows = this.rows;
    final day = frame.dayAt(at.dx);
    final item = rows.itemAt(row);
    addAt(day, group: rows.groupAt(row), after: item?.key);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final command = keys.isMetaPressed || keys.isControlPressed;
    final key = event.logicalKey;
    final actions = widget.actions;
    if (command && key == LogicalKeyboardKey.keyZ) {
      (keys.isShiftPressed ? actions.redo : actions.undo)?.call();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyY) {
      actions.redo?.call();
      return KeyEventResult.handled;
    }
    if (command && (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.numpadAdd)) {
      zoomTo(_dayWide * 1.5);
      return KeyEventResult.handled;
    }
    if (command && (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract)) {
      zoomTo(_dayWide / 1.5);
      return KeyEventResult.handled;
    }
    final item = _selected == null ? null : widget.model.byKey[_selected!];
    if (key == LogicalKeyboardKey.escape) {
      if (_selected == null && _editing == null) return KeyEventResult.ignored;
      select(null);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (actions.add == null) return KeyEventResult.ignored;
      addNext();
      return KeyEventResult.handled;
    }
    if (item == null) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      final items = widget.model.items;
      final at = items.indexWhere((each) => each.key == item.key);
      final next = (at + (key == LogicalKeyboardKey.arrowUp ? -1 : 1)).clamp(0, items.length - 1);
      select(items[next].key);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      final move = actions.move;
      if (move == null) return KeyEventResult.handled;
      final by = key == LogicalKeyboardKey.arrowLeft ? -1 : 1;
      final days = keys.isShiftPressed ? carried(item, 'end', by) : carried(item, 'move', by);
      fireMotor(HapticKind.selection);
      _say(move(item.key, days.start, days.end, keys.isShiftPressed ? GanttGrip.end : GanttGrip.move));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      final delete = actions.delete;
      if (delete == null) return KeyEventResult.ignored;
      final items = widget.model.items;
      final at = items.indexWhere((each) => each.key == item.key);
      fireMotor(HapticKind.selection);
      final said = delete(item.key);
      _say(said ?? '“${item.name}” is taken out. Undo puts it back.');
      // The next task is chosen, by where it will be once this one's line is gone.
      setState(() {
        _editing = null;
        _selected = null;
        if (at + 1 < items.length) {
          final line = lineOfKey(items[at + 1].key);
          final mine = lineOfKey(item.key);
          _selected = line != null && mine != null && line > mine ? ganttLineKey(line - 1) : items[at + 1].key;
        }
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _pointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _fingers[event.pointer] = event.localPosition;
    if (_fingers.length == 2) {
      final points = _fingers.values.toList();
      _pinchFrom = (points[0] - points[1]).distance;
      _pinchWide = _dayWide;
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_fingers.containsKey(event.pointer)) return;
    _fingers[event.pointer] = event.localPosition;
    final from = _pinchFrom;
    if (_fingers.length != 2 || from == null || from < 8) return;
    final points = _fingers.values.toList();
    final now = (points[0] - points[1]).distance;
    final focal = (points[0].dx + points[1].dx) / 2 - (_across.hasClients ? _across.offset : 0);
    zoomTo(_pinchWide * now / from, focal: focal);
  }

  void _pointerUp(PointerEvent event) {
    _fingers.remove(event.pointer);
    if (_fingers.length < 2) _pinchFrom = null;
  }

  void _signal(PointerSignalEvent event) {
    final keys = HardwareKeyboard.instance;
    if (event is PointerScrollEvent && (keys.isControlPressed || keys.isMetaPressed)) {
      GestureBinding.instance.pointerSignalResolver.register(event, (event) {
        final scroll = event as PointerScrollEvent;
        final focal = scroll.localPosition.dx - (_across.hasClients ? _across.offset : 0);
        zoomTo(_dayWide * math.pow(1.0015, -scroll.scrollDelta.dy), focal: focal);
      });
    } else if (event is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (event) {
        zoomTo(_dayWide * (event as PointerScaleEvent).scale, focal: event.localPosition.dx - (_across.hasClients ? _across.offset : 0));
      });
    }
  }

  void _hoverAt(PointerHoverEvent event) {
    final found = _hit(event.localPosition);
    final key = found.item?.key;
    if (_hover.value != key && !(found.grip == _Grip.link)) _hover.value = key;
    if (_hoverArrow.value != found.arrow) _hoverArrow.value = found.arrow;
  }

  MouseCursor _cursor() {
    final arrow = _hoverArrow.value;
    if (arrow != null && widget.actions.removeWait != null) return SystemMouseCursors.click;
    return SystemMouseCursors.basic;
  }

  @override
  Widget build(BuildContext context) {
    builds += 1;
    final look = widget.look;
    final model = widget.model;
    final rows = this.rows;
    if (!_placed) {
      _placed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final first = model.span.first;
        final lead = model.today.compareTo(first) < 0 || model.items.isEmpty;
        scrollTo(lead ? model.today : first, animate: false, edge: !lead);
      });
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 560;
        final names = wide ? 220.0 : 124.0;
        _room = math.max(0, constraints.maxWidth - names - look.hair);
        _wide ??= _fit(_room);
        final frame = this.frame;
        final height = ganttDaysHead + math.max(rows.height, ganttRow);
        final colours = GanttColours.of(look, model);
        final editing = _editing == null ? null : model.byKey[_editing!];
        final painter = GanttPainter(
          model: model,
          rows: rows,
          frame: frame,
          look: look,
          colours: colours,
          selected: _selected,
          drag: _drag,
          hover: _hover,
          hoverArrow: _hoverArrow,
          state: this,
        );
        final editable = widget.actions.editable;
        final days = Listener(
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerUp,
          onPointerCancel: _pointerUp,
          onPointerSignal: _signal,
          child: MouseRegion(
            onHover: _hoverAt,
            onExit: (_) {
              _hover.value = null;
              _hoverArrow.value = null;
            },
            cursor: MouseCursor.defer,
            child: ValueListenableBuilder<(String, String)?>(
              valueListenable: _hoverArrow,
              builder: (context, _, child) => MouseRegion(cursor: _cursor(), child: child),
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: <Type, GestureRecognizerFactory>{
                  TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(TapGestureRecognizer.new, (tap) => tap.onTapUp = _tapUp),
                  if (editable)
                    // Where a carry started is the state's, not the handlers': a rebuild mid-carry makes them again.
                    _GripDrag: GestureRecognizerFactoryWithHandlers<_GripDrag>(() => _GripDrag(allowed: takesAtOnce), (drag) {
                      drag.onStart = (details) {
                        _kind = drag.lastKind;
                        final kind = _kind;
                        final found = _hit(details.localPosition, touch: kind == PointerDeviceKind.touch);
                        final item = found.item;
                        if (item == null || found.grip == null) return;
                        _from = details.localPosition;
                        _far = 0;
                        final grip = found.grip!.name;
                        _drag.value = GanttDrag(key: item.key, grip: grip, point: grip == 'link' ? details.localPosition : null);
                      };
                      drag.onUpdate = (details) {
                        final drag = _drag.value;
                        if (drag == null) return;
                        _far = math.max(_far, (details.localPosition - _from).distance);
                        if (drag.grip == 'link') {
                          _linkTo(drag, details.localPosition);
                          return;
                        }
                        _carry(drag, ((details.localPosition.dx - _from.dx) / _dayWide).round());
                      };
                      drag.onEnd = (_) {
                        final drag = _drag.value;
                        _drag.value = null;
                        if (drag == null) return;
                        if (drag.grip == 'link') {
                          _linkEnd(drag);
                          return;
                        }
                        // Barely moved: a click, which opens the bar.
                        if (_far < 4) {
                          final touch = _kind == PointerDeviceKind.touch;
                          select(drag.key, edit: !touch || _selected == drag.key);
                          return;
                        }
                        _letGo(drag);
                      };
                      drag.onCancel = () => _drag.value = null;
                    }),
                  LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                    () => LongPressGestureRecognizer(duration: holdTime, supportedDevices: const <PointerDeviceKind>{PointerDeviceKind.touch, PointerDeviceKind.stylus}),
                    (press) {
                      press.onLongPressStart = (details) {
                        final found = _hit(details.localPosition, touch: true);
                        final item = found.item;
                        if (item == null) {
                          if (found.row != null && found.arrow == null && widget.actions.add != null) _addInRow(details.localPosition, found.row!);
                          return;
                        }
                        if (!editable) return;
                        _from = details.localPosition;
                        fireMotor(HapticKind.selection);
                        setState(() => _selected = item.key);
                        _drag.value = GanttDrag(key: item.key, grip: 'move');
                      };
                      press.onLongPressMoveUpdate = (details) {
                        final drag = _drag.value;
                        if (drag == null) return;
                        _carry(drag, ((details.localPosition.dx - _from.dx) / _dayWide).round());
                      };
                      press.onLongPressEnd = (_) {
                        final drag = _drag.value;
                        _drag.value = null;
                        if (drag != null) _letGo(drag);
                      };
                      press.onLongPressCancel = () => _drag.value = null;
                    },
                  ),
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    RepaintBoundary(child: CustomPaint(key: const ValueKey<String>('gantt-days'), size: Size(frame.width, height), painter: painter)),
                    if (editing != null && wide) ..._popover(editing, frame, rows),
                  ],
                ),
              ),
            ),
          ),
        );
        final names0 = _Names(state: this, rows: rows, look: look, colours: colours, width: names);
        final chart = Part(
          'ganttRows',
          child: DecoratedBox(
            decoration: BoxDecoration(color: look.paper, borderRadius: BorderRadius.circular(look.t.radius('md'))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(look.t.radius('md')),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  names0,
                  Container(width: look.hair, height: height, color: look.rule),
                  Expanded(
                    child: SingleChildScrollView(key: const ValueKey<String>('gantt-scroll'), controller: _across, scrollDirection: Axis.horizontal, child: days),
                  ),
                ],
              ),
            ),
          ),
        );
        final title = widget.titled ? model.title : null;
        return Focus(
          focusNode: _focus,
          onKeyEvent: _key,
          child: Semantics(
            container: true,
            label: widget.label,
            child: Part(
              'gantt',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!wide && title != null && title.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(bottom: look.space(1)),
                      child: PageWords(title, look.sans(look.em, weight: 'semibold', color: look.ink), line: look.line, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  _bar(look, wide ? title : null, wide),
                  SizedBox(height: look.space(2)),
                  chart,
                  if (_said != null)
                    Padding(
                      padding: EdgeInsets.only(top: look.space(2)),
                      child: Part('ganttSaid', child: PageWords(_said!, look.sans(look.xs, color: look.ink2), line: look.lineXs)),
                    ),
                  for (final problem in model.problems.take(4))
                    Padding(
                      padding: EdgeInsets.only(top: look.space(1)),
                      child: Part('warning', child: PageWords(problem, look.sans(look.xs, color: look.ink3), line: look.lineXs)),
                    ),
                  if (editing != null && !wide)
                    GanttSheet(
                      item: editing,
                      model: model,
                      actions: widget.actions,
                      simple: widget.simple,
                      onClose: () => setState(() => _editing = null),
                      onDone: (key) => setState(() {
                        _editing = null;
                        _selected = key;
                      }),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The panel over the bar being edited, and what it hangs from.
  List<Widget> _popover(GanttItem item, GanttFrame frame, GanttRows rows) {
    final bar = barRect(item, frame, rows);
    return <Widget>[
      Positioned.fromRect(rect: bar, child: CompositedTransformTarget(link: _anchor, child: const SizedBox.expand())),
      Positioned(
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        child: GlacierPopover(
          anchor: GlacierAnchor.link(_anchor),
          open: true,
          placement: Placement.bottomStart,
          ariaLabel: item.name,
          minWidth: 300,
          maxWidth: 340,
          onOpenChange: (open) {
            if (!open) setState(() => _editing = null);
          },
          child: GanttPanel(
            key: ValueKey<String>('gantt-panel:${item.key}'),
            item: item,
            model: widget.model,
            actions: widget.actions,
            simple: widget.simple,
            onClose: () {
              setState(() => _editing = null);
              _focus.requestFocus();
            },
            onDone: (key) {
              setState(() {
                _editing = null;
                _selected = key;
              });
              _focus.requestFocus();
            },
          ),
        ),
      ),
    ];
  }

  /// The chart's bar: its title, Today, the zoom, + Task and the fence's lines.
  Widget _bar(QueryLook look, String? title, bool wide) {
    Widget button(String label, String said, VoidCallback onTap, {bool here = false, LucideIcon? icon, Key? key}) => Semantics(
      container: true,
      button: true,
      selected: here,
      label: said,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: look.space(2), vertical: look.space(1)),
          decoration: here ? ShapeDecoration(color: look.t.color('glacier-bg'), shape: const StadiumBorder(), shadows: const <BoxShadow>[BoxShadow(color: Color(0x29000000), offset: Offset(0, 1), blurRadius: 2)]) : null,
          child: icon != null && label.isEmpty
              ? AppIcon(icon, size: look.xs * 1.25, color: look.ink2)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (icon != null) ...<Widget>[AppIcon(icon, size: look.xs * 1.2, color: look.ink2), SizedBox(width: look.space(1))],
                    PageWords(label, look.sans(look.xs, weight: 'semibold', color: here ? look.ink : look.ink3), line: look.lineXs, softWrap: false),
                  ],
                ),
        ),
      ),
    );
    final zoom = GanttZoom.values.where((each) => (ganttDayWidth(each) - _dayWide).abs() < 0.5).firstOrNull;
    final actions = widget.actions;
    return Part(
      'ganttBar',
      child: Row(
        children: <Widget>[
          if (title != null && title.isNotEmpty)
            Flexible(
              child: Padding(
                padding: EdgeInsets.only(right: look.space(2)),
                child: PageWords(title, look.sans(look.em, weight: 'semibold', color: look.ink), line: look.line, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          button('Today', 'Scroll to today', () {
            fireMotor(HapticKind.selection);
            scrollTo(widget.model.today);
          }),
          if (actions.add != null) button(wide ? 'Task' : '', 'Add a task', addNext, icon: Lucide.plus, key: const ValueKey<String>('gantt-add')),
          if (actions.onText != null) button('', 'Edit as text', actions.onText!, icon: Lucide.pencilLine, key: const ValueKey<String>('gantt-text')),
          const Spacer(),
          button('', 'Zoom out', () => zoomTo(_dayWide / 1.5), icon: Lucide.zoomOut, key: const ValueKey<String>('gantt-zoom-out')),
          button('', 'Zoom in', () => zoomTo(_dayWide * 1.5), icon: Lucide.zoomIn, key: const ValueKey<String>('gantt-zoom-in')),
          if (wide)
            Container(
              padding: const EdgeInsets.all(2),
              decoration: ShapeDecoration(color: QueryLook.mix(look.ink3, 0.1), shape: const StadiumBorder()),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final each in GanttZoom.values)
                    button('${each.name[0].toUpperCase()}${each.name.substring(1)}', 'Zoom to a ${each.name}', () {
                      fireMotor(HapticKind.selection);
                      zoomTo(ganttDayWidth(each));
                    }, here: zoom == each, key: ValueKey<String>('gantt-zoom-${each.name}')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A drag that a grip takes the moment it is pressed, so the days never scroll from under it, and that is allowed
/// only where [allowed] says.
class _GripDrag extends PanGestureRecognizer {
  _GripDrag({required this.allowed}) : super(supportedDevices: null) {
    dragStartBehavior = DragStartBehavior.down;
  }

  final bool Function(Offset at, PointerDeviceKind kind) allowed;

  @override
  bool isPointerAllowed(PointerEvent event) => allowed(event.localPosition, event.kind) && super.isPointerAllowed(event);

  /// The kind of pointer the drag is by.
  PointerDeviceKind lastKind = PointerDeviceKind.mouse;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    lastKind = event.kind;
    super.addAllowedPointer(event);
    resolvePointer(event.pointer, GestureDisposition.accepted);
  }
}

/// The colours a chart's bars are drawn in: each section's, each person's, a `colour:` word's.
class GanttColours {
  GanttColours(this.look, this.model, {required this.calm});

  factory GanttColours.of(QueryLook look, GanttModel model) => GanttColours(look, model, calm: activityCalm(look.t));

  final QueryLook look;
  final GanttModel model;

  /// Calm: every colour the ink.
  final bool calm;
  final Map<String, Color> _people = <String, Color>{};

  Color hue(String name) => name == 'gray' || name == 'grey' ? look.t.color('glacier-gray-9') : look.t.color('glacier-$name-9');

  /// The colour [item]'s bar is drawn in.
  Color of(GanttItem item) {
    if (item.done) return QueryLook.mix(look.ink3, 0.6);
    if (calm) return QueryLook.mix(look.ink, item.late ? 0.85 : 0.62);
    if (item.late) return look.t.color('glacier-red-9');
    final own = item.colour;
    if (own != null && (ganttColours.contains(own) || own == 'grey')) return hue(own);
    if (model.colourBy == GanttColourBy.person && item.person != null) {
      return _people[item.person!] ??= hue(ganttHues[item.person!.codeUnits.fold<int>(0, (sum, unit) => sum * 31 + unit).abs() % ganttHues.length]);
    }
    return group(item.group);
  }

  /// A section's colour.
  Color group(int index) => calm ? QueryLook.mix(look.ink, 0.62) : hue(ganttHues[index % ganttHues.length]);
}

/// The names on the left, a row each, and the line a row's name being dragged would land on.
class _Names extends StatelessWidget {
  const _Names({required this.state, required this.rows, required this.look, required this.colours, required this.width});

  final GanttChartState state;
  final GanttRows rows;
  final QueryLook look;
  final GanttColours colours;
  final double width;

  @override
  Widget build(BuildContext context) {
    final model = rows.model;
    final reorders = state.widget.actions.moveRow != null;
    Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: ganttDaysHead, child: Align(alignment: Alignment.bottomLeft, child: Container(height: look.hair, color: look.rule))),
        for (var index = 0; index < rows.length; index += 1) _row(index, model),
      ],
    );
    if (reorders) {
      column = _RowDrag(state: state, rows: rows, child: column);
    }
    return SizedBox(
      width: width,
      child: Stack(
        children: <Widget>[
          column,
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _GapPainter(state.drag, rows, look)))),
        ],
      ),
    );
  }

  Widget _row(int index, GanttModel model) {
    final item = rows.itemAt(index);
    if (item == null) {
      final group = model.groups[rows.groupAt(index)];
      return SizedBox(
        height: ganttHead,
        child: Container(
          color: QueryLook.mix(look.ink, 0.03),
          padding: EdgeInsets.symmetric(horizontal: look.space(2)),
          child: Row(
            children: <Widget>[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: colours.group(rows.groupAt(index)), shape: BoxShape.circle)),
              SizedBox(width: look.space(1)),
              Flexible(child: Part('ganttSection', child: PageWords(group.name.isEmpty ? 'Tasks' : group.name, look.sans(look.xs, weight: 'semibold', color: look.ink2), line: look.lineXs, maxLines: 1, overflow: TextOverflow.ellipsis))),
              SizedBox(width: look.space(1)),
              PageWords('${group.items.length}', look.sans(look.xs, color: look.ink3, tabular: true), line: look.lineXs, softWrap: false),
            ],
          ),
        ),
      );
    }
    final chosen = state.selected == item.key;
    return Semantics(
      container: true,
      button: true,
      selected: chosen,
      label: item.label != null ? '${item.label} ${item.name}' : item.name,
      onTap: () => state.select(item.key, edit: true),
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey<String>('gantt-name:${item.key}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => state.select(item.key, edit: state.selected == item.key),
        child: Part(
          'ganttName',
          child: Container(
            height: ganttRow,
            padding: EdgeInsets.symmetric(horizontal: look.space(2)),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: chosen ? QueryLook.mix(look.ink, 0.07) : null,
              border: Border(top: BorderSide(color: QueryLook.mix(look.rule, 0.6), width: look.hair)),
            ),
            child: Row(
              children: <Widget>[
                if (item.milestone) Padding(padding: EdgeInsets.only(right: look.space(1)), child: Transform.rotate(angle: math.pi / 4, child: Container(width: 7, height: 7, color: colours.of(item)))),
                if (item.label != null) Padding(padding: EdgeInsets.only(right: look.space(1)), child: PageWords(item.label!, look.mono(look.xs * 0.92, color: look.ink3), line: look.lineXs, softWrap: false)),
                Flexible(
                  child: PageWords(item.name, look.sans(look.xs, color: item.done ? look.ink3 : look.ink, struck: item.done, strike: look.ink4), line: look.lineXs, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row's name carried up or down: by a mouse at once, by a finger once it is held.
class _RowDrag extends StatelessWidget {
  const _RowDrag({required this.state, required this.rows, required this.child});

  final GanttChartState state;
  final GanttRows rows;
  final Widget child;

  void _start(Offset at) {
    final index = rows.at(at.dy - ganttDaysHead);
    final item = index == null ? null : rows.itemAt(index);
    if (item == null) return;
    fireMotor(HapticKind.selection);
    state._drag.value = GanttDrag(key: item.key, grip: 'row', gap: index);
  }

  void _update(Offset at) {
    final drag = state._drag.value;
    if (drag == null || drag.grip != 'row') return;
    final gap = rows.gapAt(at.dy - ganttDaysHead);
    if (gap != drag.gap) state._drag.value = GanttDrag(key: drag.key, grip: 'row', gap: gap);
  }

  void _end() {
    final drag = state._drag.value;
    state._drag.value = null;
    if (drag == null || drag.grip != 'row' || drag.gap == null) return;
    final landing = rows.landing(drag.gap!);
    final move = state.widget.actions.moveRow;
    if (move == null || landing.before == drag.key) return;
    fireMotor(HapticKind.success);
    state._say(move(drag.key, landing.group, landing.before));
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    gestures: <Type, GestureRecognizerFactory>{
      VerticalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
        () => VerticalDragGestureRecognizer(supportedDevices: const <PointerDeviceKind>{PointerDeviceKind.mouse}),
        (drag) {
          drag.dragStartBehavior = DragStartBehavior.down;
          drag.onStart = (details) {
            _start(details.localPosition);
          };
          drag.onUpdate = (details) {
            _update(details.localPosition);
          };
          drag.onEnd = (_) {
            _end();
          };
          drag.onCancel = () {
            state._drag.value = null;
          };
        },
      ),
      LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
        () => LongPressGestureRecognizer(duration: holdTime, supportedDevices: const <PointerDeviceKind>{PointerDeviceKind.touch, PointerDeviceKind.stylus}),
        (press) {
          press.onLongPressStart = (details) {
            _start(details.localPosition);
          };
          press.onLongPressMoveUpdate = (details) {
            _update(details.localPosition);
          };
          press.onLongPressEnd = (_) {
            _end();
          };
          press.onLongPressCancel = () {
            state._drag.value = null;
          };
        },
      ),
    },
    child: child,
  );
}

/// The line a row's name would land on.
class _GapPainter extends CustomPainter {
  _GapPainter(this.drag, this.rows, this.look) : super(repaint: drag);
  final ValueListenable<GanttDrag?> drag;
  final GanttRows rows;
  final QueryLook look;

  @override
  void paint(Canvas canvas, Size size) {
    final now = drag.value;
    if (now == null || now.grip != 'row' || now.gap == null) return;
    final gap = now.gap!;
    final y = ganttDaysHead + (gap >= rows.length ? rows.height : rows.top(gap));
    canvas.drawLine(Offset(4, y), Offset(size.width - 4, y), Paint()
      ..color = look.ink
      ..strokeWidth = 2);
    final from = rows.indexOf(now.key);
    if (from != null) canvas.drawRect(Rect.fromLTWH(0, ganttDaysHead + rows.top(from), size.width, ganttRow), Paint()..color = QueryLook.mix(look.ink, 0.08));
  }

  @override
  bool shouldRepaint(_GapPainter oldDelegate) => !identical(oldDelegate.rows, rows) || oldDelegate.look.ink != look.ink;
}

const List<String> _months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const List<String> _weekdays = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// The days and everything on them: the head, the weekends, the rows, the arrows, the bars, today, and what is being
/// carried.
class GanttPainter extends CustomPainter {
  GanttPainter({
    required this.model,
    required this.rows,
    required this.frame,
    required this.look,
    required this.colours,
    required this.selected,
    required this.drag,
    required this.hover,
    required this.hoverArrow,
    required this.state,
  }) : super(repaint: Listenable.merge(<Listenable>[drag, hover, hoverArrow]));

  final GanttModel model;
  final GanttRows rows;
  final GanttFrame frame;
  final QueryLook look;
  final GanttColours colours;
  final String? selected;
  final ValueListenable<GanttDrag?> drag;
  final ValueListenable<String?> hover;
  final ValueListenable<(String, String)?> hoverArrow;
  final GanttChartState state;

  /// How many times a painter of a chart has painted, for the test that holds a carry to repaints alone.
  static int paints = 0;

  final Map<String, TextPainter> _words = <String, TextPainter>{};

  TextPainter _text(String words, TextStyle style, String key) => _words[key] ??= (TextPainter(text: TextSpan(text: words, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout());

  /// How long painting has taken, all told, for the test that measures a carry.
  static Duration painting = Duration.zero;

  @override
  void paint(Canvas canvas, Size size) {
    paints += 1;
    final clock = Stopwatch()..start();
    _paint(canvas, size);
    painting += clock.elapsed;
  }

  void _paint(Canvas canvas, Size size) {
    final wide = frame.wide;
    final rule = Paint()
      ..color = QueryLook.mix(look.rule, 0.6)
      ..strokeWidth = look.hair;
    final strong = Paint()
      ..color = look.rule
      ..strokeWidth = look.hair;
    final first = dateOfDay(frame.first)!;
    // The weekends, quiet, where the chart counts working days and a day is wide enough to see one.
    if (model.workdays && wide >= 4) {
      final weekend = Paint()..color = QueryLook.mix(look.ink, 0.045);
      for (var n = 0; n < frame.count; n += 1) {
        final weekday = (first.weekday - 1 + n) % 7;
        if (weekday >= 5) canvas.drawRect(Rect.fromLTWH(n * wide, ganttDaysHead, wide, size.height - ganttDaysHead), weekend);
      }
    }
    // The sections' heads, a band across.
    for (var index = 0; index < rows.length; index += 1) {
      if (rows.itemAt(index) == null) canvas.drawRect(Rect.fromLTWH(0, ganttDaysHead + rows.top(index), size.width, ganttHead), Paint()..color = QueryLook.mix(look.ink, 0.03));
    }
    _head(canvas, size, first, rule, strong);
    // Each row's rule.
    for (var index = 0; index < rows.length; index += 1) {
      final top = ganttDaysHead + rows.top(index);
      canvas.drawLine(Offset(0, top), Offset(size.width, top), rule);
    }
    final carried = drag.value;
    final moves = carried?.moves ?? const <String, ({String start, String end})>{};
    // The arrows, under the bars.
    final lit = hoverArrow.value;
    // Every arrow in one stroke and its heads in one fill, the one under the pointer apart in red.
    final lines = Path();
    final heads = Path();
    final hotLines = Path();
    final hotHeads = Path();
    for (final arrow in state.arrows(frame, rows, moves)) {
      final hot = lit != null && lit.$1 == arrow.to && lit.$2 == arrow.from;
      final path = hot ? hotLines : lines;
      path.moveTo(arrow.points.first.dx, arrow.points.first.dy);
      for (var n = 1; n < arrow.points.length; n += 1) {
        path.lineTo(arrow.points[n].dx, arrow.points[n].dy);
      }
      final tip = arrow.points.last;
      (hot ? hotHeads : heads)
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - 5, tip.dy - 3.5)
        ..lineTo(tip.dx - 5, tip.dy + 3.5)
        ..close();
    }
    final arrowInk = QueryLook.mix(look.ink2, 0.75);
    canvas.drawPath(
      lines,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..color = arrowInk,
    );
    canvas.drawPath(heads, Paint()..color = arrowInk);
    if (lit != null) {
      final red = look.t.color('glacier-red-9');
      canvas.drawPath(
        hotLines,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = red,
      );
      canvas.drawPath(hotHeads, Paint()..color = red);
    }
    // The bars.
    for (final item in model.items) {
      final days = moves[item.key];
      final rect = state.barRect(item, frame, rows, days: days);
      final ink = colours.of(item);
      final moving = days != null;
      if (moving) {
        // Where it was, faint.
        final was = state.barRect(item, frame, rows);
        _bar(canvas, item, was, QueryLook.mix(ink, 0.18), ghost: true);
      }
      _bar(canvas, item, rect, ink, chosen: item.key == selected, moving: moving);
      if (moving && carried != null && item.key == carried.key) {
        final words = days.start == days.end ? _short(days.start) : '${_short(days.start)} – ${_short(days.end)}';
        final painter = TextPainter(text: TextSpan(text: words, style: look.sans(look.xs, weight: 'semibold', color: look.ink, tabular: true)), textDirection: TextDirection.ltr)..layout();
        painter.paint(canvas, Offset(rect.right + 8, rect.center.dy - painter.height / 2));
      }
    }
    // The round a wait is drawn from, on the bar chosen or under the pointer.
    if (state.widget.actions.addWait != null) {
      for (final key in <String?>{selected, hover.value}) {
        final item = key == null ? null : model.byKey[key];
        if (item == null || (carried != null && carried.grip != 'link')) continue;
        final knob = state.knobOf(state.barRect(item, frame, rows));
        canvas.drawCircle(knob, 5, Paint()..color = look.paper);
        canvas.drawCircle(
          knob,
          5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = look.ink2,
        );
      }
    }
    // A wait being drawn: its line to the pointer, and the bar it would land on.
    if (carried != null && carried.grip == 'link' && carried.point != null) {
      final from = model.byKey[carried.key];
      if (from != null) {
        final start = state.knobOf(state.barRect(from, frame, rows));
        final bad = carried.refused != null;
        final pen = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = bad ? look.t.color('glacier-red-9') : look.ink;
        canvas.drawLine(start, carried.point!, pen);
        canvas.drawCircle(carried.point!, 3.5, Paint()..color = pen.color);
        final target = carried.target == null ? null : model.byKey[carried.target!];
        if (target != null) {
          canvas.drawRRect(RRect.fromRectAndRadius(state.barRect(target, frame, rows).inflate(3), const Radius.circular(7)), pen);
          if (bad) {
            final painter = TextPainter(text: TextSpan(text: carried.refused, style: look.sans(look.xs, color: look.t.color('glacier-red-11'))), textDirection: TextDirection.ltr, maxLines: 1)..layout();
            painter.paint(canvas, carried.point! + const Offset(10, -18));
          }
        }
      }
    }
    // Today, a line down the days.
    final today = daysBetween(frame.first, model.today);
    if (today != null && today >= 0 && today < frame.count) {
      final x = (today + 0.5) * wide;
      final red = colours.calm ? look.ink : look.t.color('glacier-red-9');
      canvas.drawLine(
        Offset(x, ganttDaysHead - 4),
        Offset(x, size.height),
        Paint()
          ..color = red
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(Offset(x, ganttDaysHead - 4), 3, Paint()..color = red);
    }
  }

  /// How far past a bar's end its words start: clear of the arrow that leaves it, where one does.
  double _clear(GanttItem item) => (model.waiting[item.key]?.isNotEmpty ?? false) ? 12 : 6;

  String _short(String day) {
    final date = dateOfDay(day)!;
    return '${date.day} ${_months[date.month - 1]}';
  }

  void _bar(Canvas canvas, GanttItem item, Rect rect, Color ink, {bool chosen = false, bool moving = false, bool ghost = false}) {
    if (item.milestone) {
      final path = Path()
        ..moveTo(rect.center.dx, rect.top)
        ..lineTo(rect.right, rect.center.dy)
        ..lineTo(rect.center.dx, rect.bottom)
        ..lineTo(rect.left, rect.center.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = ink);
      if (chosen || moving) {
        canvas.drawPath(
          path.shift(Offset.zero),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = look.ink,
        );
      }
      if (!ghost) {
        final words = _text(item.name, look.sans(look.xs, color: look.ink2), 'name:${item.key}:${item.name}');
        words.paint(canvas, Offset(rect.right + _clear(item), rect.center.dy - words.height / 2));
      }
      return;
    }
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    if (item.undated && !moving) {
      canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.25
          ..color = QueryLook.mix(ink, 0.8),
      );
      canvas.drawRRect(shape, Paint()..color = QueryLook.mix(ink, 0.12));
    } else if (ghost) {
      canvas.drawRRect(shape, Paint()..color = ink);
    } else {
      final progress = item.progress;
      if (progress != null && progress < 100 && !item.done) {
        canvas.drawRRect(shape, Paint()..color = QueryLook.mix(ink, 0.35));
        if (progress > 0) {
          canvas.save();
          canvas.clipRect(Rect.fromLTWH(rect.left, rect.top, rect.width * progress / 100, rect.height));
          canvas.drawRRect(shape, Paint()..color = ink);
          canvas.restore();
        }
      } else {
        canvas.drawRRect(shape, Paint()..color = ink);
      }
    }
    if (chosen || moving) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(7)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = look.ink,
      );
    }
    if (ghost) return;
    if (rect.width >= 16 && !item.undated) {
      // The ends' grips, a notch each.
      final grip = Paint()..color = QueryLook.mix(look.paper, 0.7);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(rect.left + 3, rect.center.dy - 4, 2, 8), const Radius.circular(1)), grip);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(rect.right - 5, rect.center.dy - 4, 2, 8), const Radius.circular(1)), grip);
    }
    if (item.progress != null && item.progress! > 0 && item.progress! < 100 && !moving) {
      final words = _text('${item.progress}%', look.sans(look.xs * 0.9, color: look.ink3, tabular: true), 'progress:${item.progress}');
      final x = rect.right + (item.key == selected || item.key == hover.value ? 20 : _clear(item));
      words.paint(canvas, Offset(x, rect.center.dy - words.height / 2));
    }
  }

  void _head(Canvas canvas, Size size, DateTime first, Paint rule, Paint strong) {
    final wide = frame.wide;
    const split = 18.0;
    final small = look.sans(look.xs * 0.92, color: look.ink3, tabular: true);
    final bold = look.sans(look.xs * 0.92, weight: 'semibold', color: look.ink2, tabular: true);
    for (var n = 0; n < frame.count; n += 1) {
      final date = DateTime(first.year, first.month, first.day + n);
      final x = n * wide;
      final monday = date.weekday == DateTime.monday;
      // The top row: a month's name where it starts (or a year's, zoomed far out), and at the very left.
      final quarterly = wide < 5;
      final topStarts = quarterly ? (date.day == 1 && date.month == 1) || n == 0 : date.day == 1 || n == 0;
      if (topStarts) {
        if (n > 0) canvas.drawLine(Offset(x, 0), Offset(x, size.height), strong);
        final words = quarterly ? '${date.year}' : '${_months[date.month - 1]} ${date.year}';
        _text(words, bold, 'top:$words').paint(canvas, Offset(x + 4, (split - 14) / 2));
      }
      // The bottom row: each day, each week's Monday, or each month, as there is room.
      if (wide >= 18) {
        if (n > 0) canvas.drawLine(Offset(x, split), Offset(x, ganttDaysHead), rule);
        final words = wide >= 30 ? '${_weekdays[date.weekday - 1]} ${date.day}' : '${date.day}';
        final painter = _text(words, monday ? bold : small, 'day:$words:$monday');
        painter.paint(canvas, Offset(x + (wide - painter.width) / 2, split + (ganttDaysHead - split - painter.height) / 2));
        if (monday && n > 0) canvas.drawLine(Offset(x, ganttDaysHead), Offset(x, size.height), rule);
      } else if (wide >= 5) {
        if (monday) {
          canvas.drawLine(Offset(x, split), Offset(x, size.height), rule);
          final painter = _text('${date.day}', small, 'week:${date.day}');
          painter.paint(canvas, Offset(x + 3, split + (ganttDaysHead - split - painter.height) / 2));
        }
      } else if (date.day == 1) {
        canvas.drawLine(Offset(x, split), Offset(x, size.height), rule);
        final painter = _text(_months[date.month - 1], small, 'month:${date.month}');
        painter.paint(canvas, Offset(x + 3, split + (ganttDaysHead - split - painter.height) / 2));
      }
    }
    canvas.drawLine(Offset(0, ganttDaysHead), Offset(size.width, ganttDaysHead), strong);
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) => <CustomPainterSemantics>[
    for (final item in model.items)
      CustomPainterSemantics(
        rect: state.barRect(item, frame, rows),
        properties: SemanticsProperties(
          label: '${item.label != null ? '${item.label} ' : ''}${item.name}, ${item.milestone ? 'on ${_short(item.start)}' : '${_short(item.start)} to ${_short(item.end)}'}${item.progress != null ? ', ${item.progress}% done' : ''}',
          button: true,
          selected: item.key == selected,
          onTap: () => state.select(item.key, edit: true),
          textDirection: TextDirection.ltr,
        ),
      ),
  ];

  @override
  bool shouldRepaint(GanttPainter oldDelegate) =>
      !identical(oldDelegate.model, model) || oldDelegate.frame.wide != frame.wide || oldDelegate.frame.first != frame.first || oldDelegate.frame.count != frame.count || oldDelegate.selected != selected || oldDelegate.look.ink != look.ink || oldDelegate.look.paper != look.paper || oldDelegate.colours.calm != colours.calm;

  @override
  bool shouldRebuildSemantics(GanttPainter oldDelegate) => shouldRepaint(oldDelegate);
}
