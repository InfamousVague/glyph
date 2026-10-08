/// Rows dragged into a new order, by their grip (Matt: "drag to reorder pages"), by the app's one drag
/// (lib/core/hold_drag.dart; Matt: "the same mechanism as clicking and dragging on board view"): press and hold the
/// grip, a mouse as much as a finger, and the row lifts - a copy of it in the air under the pointer, the row itself
/// the gap it would leave, standing where it would land while the others make room. On release, the row's new place
/// is handed back as an index. The rows' own arrow buttons stay for the keyboard. A port of
/// `src/app/book/rowDrag.ts`, with the rows' shared look from `book/rows.module.css` (`.grip`, `.lifts[data-lifted]`).
///
///     RowDrag        the drag for one list: which row is lifted, where it would land, how far each row stands aside
///     DragRow        a row of that list: it is measured, shifted, and drawn as the gap while it is lifted
///     RowGrip        the grip a row is dragged by
///
/// What differs:
/// - **The hook is an object.** `useRowDrag(rows, onMove)` answered `{ lifted, over, grip, rowStyle }` on every
///   draw; [RowDrag] is a [ChangeNotifier] a list keeps for as long as it is mounted, and [DragRow] listens to it,
///   so a drag redraws the rows and not the page they are on.
/// - **The rows are found by key.** The page was handed the rows' elements; here each [DragRow] wears
///   [RowDrag.rowKey] on its own box, outside the shift, so a row is measured where the list laid it out.
/// - **`rowStyle` is [RowDrag.shiftOf]**, the `translateY` alone. `transition: transform 120ms` is on a row only
///   while it stands aside, as on the page, so the rows ease out of the way and are back at once when the row is put
///   down. `position: relative; z-index: 1` on the lifted row has nothing to lift over: it is the gap, with nothing
///   drawn in it.
/// - **The copy in the air** is built again by the caller ([RowDrag.press]'s `ghost`), where the page cloned the
///   row's element (lib/core/hold_drag.dart says why).
/// - `event.stopPropagation()` on the grip's press, which kept it from the page's long-press menu and the row's own
///   press, is the gesture arena's here: the recognizer claims the pointer at the hold, and everything else waiting
///   on it is refused.
library;

import 'dart:ui' show PathMetric;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/hold_drag.dart';
import '../sheet/css.dart';

/// How long a press holds before a row lifts (core/gestures.ts `HOLD_MS`), passed on for the rows' tests
/// (`ROW_HOLD_MS`).
const Duration rowHold = holdTime;

/// The drag for one list of rows (`useRowDrag`). [onMove] is called on release with a changed place.
class RowDrag extends ChangeNotifier {
  RowDrag(this.onMove);

  /// `onMove(from, to)`: the row at `from` let go where the row at `to` stood.
  void Function(int from, int to) onMove;

  final Map<int, GlobalKey> _keys = <int, GlobalKey>{};
  int? _lifted;
  int? _over;
  double _height = 40;

  /// How to give up a drag in flight, for rows taken off the page in the middle of one.
  VoidCallback? _abandon;

  /// The row being dragged (`lifted.index`), or null.
  int? get lifted => _lifted;

  /// Where it would land now.
  int? get over => _over;

  /// The lifted row's height: how far a row stands aside.
  double get step => _height;

  /// The key row [index] wears, for a drag to measure it by.
  GlobalKey rowKey(int index) => _keys[index] ??= GlobalKey(debugLabel: 'row $index');

  RenderBox? _boxOf(int index) {
    final box = _keys[index]?.currentContext?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  /// The grip's press, for row [index] of [count] (`grip(index).onPointerDown`). [ghost] builds the copy in the air,
  /// with corners of [radius].
  void press(PointerDownEvent event, int index, int count, {required WidgetBuilder ghost, BorderRadius radius = BorderRadius.zero}) {
    final row = _keys[index]?.currentContext;
    if (row == null || _abandon != null) return;
    Ghost? copy;
    var tops = const <double>[];
    var startY = event.position.dy;
    var to = index;
    var down = false;

    void putDown() {
      if (down) return;
      down = true;
      copy?.remove();
      copy = null;
      _abandon = null;
      final was = _lifted != null;
      _lifted = null;
      _over = null;
      if (was) notifyListeners();
    }

    // The first row whose middle is above the lifted row's middle, where it is now.
    int landing(double y) {
      final middle = tops[index] + _height / 2 + (y - startY);
      var at = 0;
      for (var i = 0; i < tops.length; i += 1) {
        if (tops[i] + _height / 2 < middle) at = i;
      }
      return at;
    }

    final finish = holdDrag(
      event,
      HoldDragHooks(
        lift: (at) {
          final box = _boxOf(index);
          if (box == null || !row.mounted) return;
          tops = <double>[for (var i = 0; i < count; i += 1) _boxOf(i)?.localToGlobal(Offset.zero).dy ?? 0];
          final rect = box.localToGlobal(Offset.zero) & box.size;
          _height = rect.height > 0 ? rect.height : 40;
          startY = at.dy;
          copy = liftGhost(row, box: rect, at: at, builder: ghost, radius: radius);
          _lifted = index;
          _over = index;
          notifyListeners();
        },
        move: (at) {
          if (_lifted == null) return;
          copy?.follow(at);
          final next = landing(at.dy);
          if (next == to) return;
          to = next;
          _over = next;
          notifyListeners();
        },
        drop: (_) {
          if (_lifted == null) return;
          putDown();
          if (to != index) onMove(index, to);
        },
        end: (wasLifted) {
          if (wasLifted) {
            putDown();
          } else {
            _abandon = null;
          }
        },
      ),
    );
    _abandon = () {
      finish();
      putDown();
    };
  }

  /// How far down row [index] is drawn from where it lies (`rowStyle(index).transform`): the gap standing where the
  /// row would land, the rows between making room for it, and nothing for the rest.
  double shiftOf(int index) {
    final lifted = _lifted, over = _over;
    if (lifted == null || over == null) return 0;
    if (index == lifted) return (over - lifted) * _height;
    if (lifted < over && index > lifted && index <= over) return -_height;
    if (lifted > over && index >= over && index < lifted) return _height;
    return 0;
  }

  /// Gives up a drag in flight.
  void abandon() => _abandon?.call();

  @override
  void dispose() {
    final abandon = _abandon;
    _abandon = null;
    // Quietly: nobody is listening any more.
    _lifted = null;
    abandon?.call();
    super.dispose();
  }
}

/// A row of a list that [drag] orders: measured where it lies, shifted to make room, and while it is the one lifted
/// drawn as the gap it leaves (`.lifts[data-lifted]`: washed, a dashed line round it, nothing in it).
class DragRow extends StatelessWidget {
  const DragRow({super.key, required this.drag, required this.index, this.radius = 0, required this.child});

  final RowDrag drag;
  final int index;

  /// The gap's corners: the index's rows round theirs (`.row[data-lifted] { border-radius: sm }`).
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: drag.rowKey(index),
      child: ListenableBuilder(
        listenable: drag,
        child: child,
        builder: (context, child) {
          final lifted = drag.lifted == index;
          final shift = drag.shiftOf(index);
          Widget row = child!;
          if (lifted) {
            // `currentColor`: the row's own ink.
            final ink = DefaultTextStyle.of(context).style.color ?? context.tokens.color('glacier-text');
            row = CustomPaint(
              foregroundPainter: _GapPainter(ink: ink, radius: radius, line: snapBorder(context, 1)),
              // `.lifts[data-lifted] > * { visibility: hidden }`: the room kept, nothing drawn, nothing pressed.
              child: Visibility(visible: false, maintainSize: true, maintainAnimation: true, maintainState: true, child: row),
            );
            return Transform.translate(offset: Offset(0, shift), child: row);
          }
          // `transition: transform 120ms`, on a row only while it stands aside.
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(end: shift),
            duration: shift == 0 ? Duration.zero : const Duration(milliseconds: 120),
            child: row,
            builder: (context, at, child) => at == 0 ? child! : Transform.translate(offset: Offset(0, at), child: child),
          );
        },
      ),
    );
  }
}

/// `background: color-mix(in oklch, currentColor 4%, transparent); outline: 1px dashed color-mix(in oklch,
/// currentColor 30%, transparent); outline-offset: -1px`.
class _GapPainter extends CustomPainter {
  const _GapPainter({required this.ink, required this.radius, required this.line});

  final Color ink;
  final double radius;
  final double line;

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.drawRRect(box, Paint()..color = ink.withValues(alpha: 0.04 * ink.a));
    // The outline lies inside the box by its offset, its middle half a line further in.
    final path = Path()..addRRect(box.deflate(line / 2));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = line
      ..color = ink.withValues(alpha: 0.3 * ink.a);
    // Dashes three times the line's width and as far apart, which is near enough to a browser's dashed line.
    final dash = 3 * line;
    for (final PathMetric metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 2 * dash) {
        canvas.drawPath(metric.extractPath(at, (at + dash).clamp(0, metric.length)), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_GapPainter old) => old.ink != ink || old.radius != radius || old.line != line;
}

/// The grip a row is dragged by (`.grip`): pressed and held, by a finger or a mouse, it lifts the row.
/// `display: inline-grid; place-items: center; block-size: 2em; color: var(--glacier-text-subtle)`, round
/// `<GripVertical size={16} />`. It says nothing to a screen reader (`aria-hidden`): the arrows are its way.
class RowGrip extends StatelessWidget {
  const RowGrip({super.key, required this.drag, required this.index, required this.count, required this.em, required this.ghost, this.radius = BorderRadius.zero});

  final RowDrag drag;
  final int index;

  /// How many rows the list has, for the drag to measure them all.
  final int count;

  /// The row's font size: the grip is two of it tall.
  final double em;
  final WidgetBuilder ghost;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ExcludeSemantics(
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => drag.press(event, index, count, ghost: ghost, radius: radius),
          child: SizedBox(
            height: 2 * em,
            child: Center(child: lucide(Lucide.gripVertical, size: 16, color: t.color('glacier-text-subtle'))),
          ),
        ),
      ),
    );
  }
}
