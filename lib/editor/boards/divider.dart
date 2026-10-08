/// The line under a board, which sets how tall its lanes are. Ports the drawing and the drag of
/// `src/app/editor/boards/divider.ts`.
///
/// How tall a board is, set by dragging the line under it (Matt: "make board height configurable with glacierUI
/// split view"). The line is Glacier's split-pane divider, made for a board that sits in a scrolling note rather
/// than in a box of its own: a hairline with a grip, a separator a screen reader can set, dragged, and put back
/// with a double tap. The grip shows all the time, since a phone has no hover to show it on, and the line takes a
/// finger's width of touch.
///
/// The height is the lanes', in their own ems, so a board keeps its number of cards when the text size changes. It
/// is written into the board's fence when the finger lifts (card_edits.dart `writeHeight`), so it goes wherever the
/// note goes; while the finger moves it is only the board's own state, and nothing is written.
///
/// What differs:
/// - The arrow keys, Home and End stepped a focused separator on the page. Nothing on a board takes the keyboard's
///   focus here; the same steps are a screen reader's increase and decrease.
/// - `sized(board, split, height)` set a style and an attribute; the board's widget is simply built at the height
///   it is given (board_box.dart), and [BoardSplit.now] is `aria-valuenow`.
/// - The drag is a vertical drag in the gesture arena, where the page took the pointer as it went down: the line is
///   inside the note's own scroller, and being the inner of the two it wins a finger that moves up or down on it.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../../core/boards.dart';
import 'board_look.dart';

class BoardSplit extends StatefulWidget {
  const BoardSplit({super.key, required this.look, required this.now, this.onDrag, this.onDone, this.onReset, this.onStep});

  final BoardLook look;

  /// How tall the lanes are now, in their own ems.
  final double now;

  /// The line dragged: the lanes follow at this height, clamped to what a board can be.
  final ValueChanged<double>? onDrag;

  /// Let go (`write` true) or called off: from where it started, and where it ended.
  final void Function(double from, double to, bool write)? onDone;

  /// A double tap: back to the board's own height.
  final VoidCallback? onReset;

  /// A step up or down by a screen reader.
  final ValueChanged<double>? onStep;

  @override
  State<BoardSplit> createState() => _BoardSplitState();
}

class _BoardSplitState extends State<BoardSplit> {
  bool _dragging = false;
  bool _calledOff = false;
  double _from = 0;
  double _height = 0;
  double _moved = 0;
  String? _edge;

  void _start(DragStartDetails details) {
    setState(() => _dragging = true);
    _from = widget.now;
    _height = _from;
    _moved = 0;
    _edge = null;
    _calledOff = false;
  }

  void _update(DragUpdateDetails details) {
    _moved += details.delta.dy;
    final wanted = _from + _moved / widget.look.em;
    _height = clampHeight(wanted);
    widget.onDrag?.call(_height);
    // A buzz at either end, as Glacier's divider gives, so the finger knows it can go no further.
    final at = wanted <= boardHeight.min ? 'min' : (wanted >= boardHeight.max ? 'max' : null);
    if (at != _edge) {
      _edge = at;
      if (at != null) fireMotor(HapticKind.medium);
    }
  }

  void _done(bool write) {
    if (!_dragging) return;
    setState(() => _dragging = false);
    widget.onDone?.call(_from, _height, write && !_calledOff && (_height - _from).abs() >= 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final live = widget.onDrag != null;
    final line = Padding(
      padding: EdgeInsets.only(top: look.splitReachAbove),
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: look.splitLine,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              Positioned.fill(child: ColoredBox(key: const ValueKey<String>('board-split'), color: _dragging ? look.splitInkHeld : look.splitInk)),
              Positioned(
                top: (look.splitLine - BoardLook.gripHeight) / 2,
                child: Container(
                  key: const ValueKey<String>('board-grip'),
                  width: look.gripWidth,
                  height: BoardLook.gripHeight,
                  decoration: ShapeDecoration(color: _dragging ? const Color(0xffffffff) : look.gripInk, shape: const StadiumBorder()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      label: 'Board height',
      value: '${widget.now.round()}',
      increasedValue: live ? '${clampHeight(widget.now + 1).round()}' : null,
      decreasedValue: live ? '${clampHeight(widget.now - 1).round()}' : null,
      slider: true,
      onIncrease: live ? () => widget.onStep?.call(clampHeight(widget.now + 1)) : null,
      onDecrease: live ? () => widget.onStep?.call(clampHeight(widget.now - 1)) : null,
      child: live
          // A drag the phone calls off ends as one let go does, to the recognizer; the pointer says which it was.
          ? Listener(
              onPointerCancel: (_) => _calledOff = true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: _start,
                onVerticalDragUpdate: _update,
                onVerticalDragEnd: (_) => _done(true),
                onVerticalDragCancel: () => _done(false),
                onDoubleTap: widget.onReset,
                child: line,
              ),
            )
          : line,
    );
  }
}
