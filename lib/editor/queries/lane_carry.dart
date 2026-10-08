/// A query's things carried between its groups: a board's cards, a grouped list's or table's rows, by the app's one
/// drag (lib/core/hold_drag.dart [Carry]), dropped by setting the grouped field to the group's value
/// (queries.dart). Ports `laneValue`, `boardMovable`, `laneKeyAt`, `carryPress`, `laneSpotAt`, `useLaneCarry` and
/// `noteRoller` of `src/app/editor/QueryView.tsx`, and the gap's look of `app.css` (`[data-drag-gap]`).
///
/// The carried thing stays in its group as the gap while it is held over it, and is taken out of it for the gap
/// [LaneCarry.gapIn] says to open in another.
///
/// What differs:
/// - **The lane under the pointer** was whatever element the page found there (`elementFromPoint`). Here each
///   group is given a place of its own ([LaneCarry.lane]) and the one whose box holds the pointer is it.
/// - **A carried thing in another group** was kept on the page out of sight, because a phone sends a finger's moves
///   to the element it first touched. The gesture is not the widget's here (hold_drag.dart), so the thing is simply
///   not drawn there.
/// - **A table's row** has no box of its own in Flutter's table: the press is taken by its cells, the row lifted
///   from its first cell, and its height and its cells' widths read from the cells as it is ([LaneCarry.cell]).
library;

import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

import '../../core/hold_drag.dart';
import '../../core/query/query.dart';
import '../boards/navigate.dart' show boardEdge, noteScroller;
import 'query_look.dart';
import 'query_parts.dart';

/// The value a lane writes to the grouped field when a card is dropped in it: a status' own text, or null to clear
/// the field in the "No …" lane. Only a status or a plain text field is written from what the lane shows; a day, a
/// priority or a person is drawn, not the value it is stored as, so a board grouped by one is not one cards can be
/// dragged across ([boardMovable]).
String? laneValue(QueryGroup group) {
  if (group.key.isEmpty) return null;
  return switch (group.cell) {
    StatusCell(:final text) || TextCell(:final text) => text,
    _ => null,
  };
}

/// Whether a board's cards can be dragged between its lanes: it is grouped, editable, and every lane can be written.
bool boardMovable(QueryResult result, bool editable) =>
    editable && result.group != null && result.groups.every((group) => group.key.isEmpty || group.cell is StatusCell || group.cell is TextCell);

/// A border dashed round a box, `offset` outside it (`outline: 1px dashed …; outline-offset: …`).
class DashedOutline extends CustomPainter {
  const DashedOutline(this.color, this.radius, {this.offset = 0});

  final Color color;
  final double radius;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    final box = (Offset.zero & size).inflate(offset + 0.5);
    final path = Path()..addRRect(RRect.fromRectAndRadius(box, Radius.circular(radius <= 0 ? 0 : radius + offset)));
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 6) {
        canvas.drawPath(metric.extractPath(at, (at + 3).clamp(0.0, metric.length).toDouble()), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedOutline oldDelegate) => oldDelegate.color != color || oldDelegate.radius != radius || oldDelegate.offset != offset;
}

/// `[data-drag-gap]`: the thing where it would land, its own shape emptied out.
class DragGap extends StatelessWidget {
  const DragGap({super.key, required this.look, this.radius = 0, this.height, this.child});

  final QueryLook look;
  final double radius;

  /// How tall the gap is, where nothing of the thing's own is left in it to say.
  final double? height;

  /// The thing itself, kept for its size and not drawn (`[data-drag-gap] > * { visibility: hidden }`).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final inside = child;
    // [data-drag-gap] { background: color-mix(in oklch, currentColor 4%, transparent);
    //   outline: 1px dashed color-mix(in oklch, currentColor 30%, transparent); outline-offset: -1px }
    return CustomPaint(
      foregroundPainter: DashedOutline(QueryLook.mix(look.ink, 0.3), radius, offset: -1),
      child: Container(
        height: height,
        decoration: BoxDecoration(color: QueryLook.mix(look.ink, 0.04), borderRadius: BorderRadius.circular(radius)),
        child: inside == null ? null : IgnorePointer(child: ExcludeSemantics(child: Opacity(opacity: 0, child: inside))),
      ),
    );
  }
}

class LaneCarry {
  LaneCarry({required this.context, required this.redraw, this.scrollers});

  /// The list's own context, read when a thing is lifted.
  final BuildContext Function() context;
  final VoidCallback redraw;

  /// What rolls along under a carried thing; the note the query is drawn in where none is given (`noteRoller`).
  final List<CarryScroller> Function(Offset at)? scrollers;

  late final Carry<QueryRow> carry = Carry<QueryRow>(spotAt: _spotAt, onDrop: _dropped, scrollers: scrollers ?? _note, window: () => MediaQuery.sizeOf(context()).height)
    ..addListener(_changed);

  QueryResult? _result;
  QueryActs? _acts;
  int Function()? _control;
  bool movable = false;
  final Map<String, GlobalKey> _laneKeys = <String, GlobalKey>{};
  final Map<String, Map<int, BuildContext>> _cells = <String, Map<int, BuildContext>>{};

  /// A lifted table row's cells' widths, and how tall the row was.
  List<double> cellWidths = const <double>[];
  double? _rowHeight;

  Carried<QueryRow>? get carried => carry.carried;
  Spot? get over => carry.over;

  void _changed() {
    if (carry.carried == null) _rowHeight = null;
    redraw();
  }

  void dispose() {
    carry
      ..removeListener(_changed)
      ..dispose();
  }

  /// The query as it is drawn now.
  void update(QueryResult result, QueryActs acts, {int Function()? control}) {
    _result = result;
    _acts = acts;
    _control = control;
    movable = boardMovable(result, acts.editable);
    final held = carried;
    // A thing in the air whose query changed under it is put down where it was.
    if (held != null && !result.groups.any((group) => group.rows.any((row) => row.key == held.item.key))) carry.abandon();
    _laneKeys.removeWhere((key, _) => !result.groups.any((group) => group.key == key));
  }

  Rect? _boxOf(BuildContext? of) {
    final box = of?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Where a query's card or row would land: the lane under the pointer, in no order of the person's (its
  /// `sort:`'s).
  Spot? _spotAt(Offset at) {
    for (final entry in _laneKeys.entries) {
      final box = _boxOf(entry.value.currentContext);
      if (box != null && box.contains(at)) return Spot(entry.key, -1);
    }
    return null;
  }

  void _dropped(QueryRow row, Spot from, Spot to) {
    final result = _result;
    if (result == null) return;
    final group = result.groups.where((group) => group.key == to.lane).firstOrNull;
    if (group == null) return;
    _acts?.onMove(row, laneValue(group));
  }

  List<CarryScroller> _note(Offset at) {
    final note = noteScroller(context());
    if (note == null || !note.position.hasContentDimensions || note.position.maxScrollExtent <= 1) return const <CarryScroller>[];
    return <CarryScroller>[
      CarryScroller(
        position: note.position,
        axis: Axis.vertical,
        box: () => _boxOf(note.context),
        zone: boardEdge * 2,
      ),
    ];
  }

  /// A group's box: the lane a carried thing may be dropped in.
  GlobalKey laneKey(QueryGroup group) => _laneKeys[group.key] ??= GlobalKey(debugLabel: 'lane ${group.key}');

  /// A group's own place: where a carried thing is dropped.
  Widget lane(QueryGroup group, {required Widget child}) => movable ? KeyedSubtree(key: laneKey(group), child: child) : child;

  /// Whether a carried thing is held over [group].
  bool isOver(QueryGroup group) => carried != null && over?.lane == group.key;

  /// Whether [row] is the carried thing held over another group: not drawn in its own.
  bool hidden(QueryRow row, QueryGroup group) => carried?.item.key == row.key && over?.lane != group.key;

  /// Whether [row] is the carried thing, drawn in its own group as the gap it leaves.
  bool isGap(QueryRow row) => carried?.item.key == row.key;

  /// How many of a group's things are drawn: not the carried one, held over another group.
  int seen(QueryGroup group) => group.rows.where((row) => !hidden(row, group)).length;

  /// The gap to open in [group]: as tall as the carried thing, where it is held over a group it did not come from.
  double? gapIn(QueryGroup group) {
    final held = carried;
    if (held == null || over?.lane != group.key || held.from.lane == group.key) return null;
    return _rowHeight ?? held.height;
  }

  bool _own(PointerDownEvent event) => movable && event.pointer != _control?.call();

  /// A thing's own place: carried from its group by a press and hold, and drawn as the gap while it is. [copy]
  /// builds the copy in the air.
  Widget thing(QueryRow row, QueryGroup group, {Key? key, required Widget Function() copy, required Widget child, double radius = 0, QueryLook? look}) {
    if (!movable) return KeyedSubtree(key: key, child: child);
    return Builder(
      key: key,
      builder: (context) => Listener(
        onPointerDown: (event) {
          if (!_own(event)) return;
          carry.press(event, context, row, Spot(group.key, -1), ghost: (_) => copy(), radius: BorderRadius.circular(radius));
        },
        child: isGap(row) && look != null ? DragGap(look: look, radius: radius, child: child) : (isGap(row) ? IgnorePointer(child: Opacity(opacity: 0, child: child)) : child),
      ),
    );
  }

  /// One cell of a table's row, which is carried as a row: pressed anywhere, it is lifted from its first cell.
  Widget cell(QueryRow row, QueryGroup group, {required int index, required int columns, required Widget Function() copy, required Widget child}) {
    if (!movable) return child;
    return Builder(
      builder: (context) {
        (_cells[row.key] ??= <int, BuildContext>{})[index] = context;
        return Listener(
          onPointerDown: (event) {
            if (!_own(event)) return;
            final cells = _cells[row.key] ?? const <int, BuildContext>{};
            final first = cells[0];
            if (first == null || !first.mounted) return;
            final boxes = <Rect?>[for (var at = 0; at < columns; at += 1) _boxOf(cells[at]?.mounted ?? false ? cells[at] : null)];
            cellWidths = <double>[for (final box in boxes) box?.width ?? 0];
            final tops = boxes.whereType<Rect>().map((box) => box.top), bottoms = boxes.whereType<Rect>().map((box) => box.bottom);
            final height = tops.isEmpty ? null : bottoms.reduce((a, b) => a > b ? a : b) - tops.reduce((a, b) => a < b ? a : b);
            final width = cellWidths.fold<double>(0, (sum, each) => sum + each);
            carry.onLift = () => _rowHeight = height;
            carry.press(
              event,
              first,
              row,
              Spot(group.key, -1),
              // As wide as the row, though it is lifted by a cell.
              ghost: (_) => OverflowBox(alignment: Alignment.topLeft, minWidth: width, maxWidth: width, fit: OverflowBoxFit.deferToChild, child: copy()),
            );
          },
          child: isGap(row) ? IgnorePointer(child: Opacity(opacity: 0, child: child)) : child,
        );
      },
    );
  }
}
