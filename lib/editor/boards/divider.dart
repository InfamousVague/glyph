/// The line under a board, which sets how tall its lanes are. Ports the drawing, the drag and the keys of
/// `src/app/editor/boards/divider.ts`.
///
/// How tall a board is, set by dragging the line under it (Matt: "make board height configurable with glacierUI
/// split view"). The line is Glacier's split-pane divider, made for a board that sits in a scrolling note rather
/// than in a box of its own: a hairline with a grip, a separator a screen reader can set, dragged, stepped with
/// the arrow keys, sent to either end with Home and End, and put back with a double tap. The grip shows all the time, since a phone has no hover to show it on, and the line takes a
/// finger's width of touch.
///
/// The height is the lanes', in their own ems, so a board keeps its number of cards when the text size changes. It
/// is written into the board's fence when the finger lifts (card_edits.dart `writeHeight`), so it goes wherever the
/// note goes; while the finger moves it is only the board's own state, and nothing is written.
///
/// What differs:
/// - The page's separator is `tabIndex=0`, and its press takes no focus (`mousedown` is prevented): a keyboard
///   reaches it and a pointer does not. Here it is a focus node in the traversal that nothing but the keyboard
///   gives the focus to, and focused it is drawn as it is while dragged (`.cm-boardSplit:focus-visible`). The same
///   steps are a screen reader's increase and decrease.
/// - `sized(board, split, height)` set a style and an attribute; the board's widget is simply built at the height
///   it is given (board_box.dart), and [BoardSplit.now] is `aria-valuenow`.
/// - The drag is a vertical drag in the gesture arena, where the page took the pointer as it went down: the line is
///   inside the note's own scroller, and being the inner of the two it wins a finger that moves up or down on it.
library;

import 'package:flutter/services.dart' show KeyUpEvent, LogicalKeyboardKey;
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

  /// The keyboard's focus on the line (`tabIndex=0`), and whether it has it.
  final FocusNode _focus = FocusNode(debugLabel: 'Board height');
  bool _focused = false;

  /// The height the keys last stepped to, until the fence it was written into is drawn again: the page read the
  /// lanes' own height at each key (`laneHeight(wrap)`), which the write had changed by then, so two presses in one
  /// frame are two steps.
  double? _stepped;

  @override
  void didUpdateWidget(BoardSplit oldWidget) {
    super.didUpdateWidget(oldWidget);
    _stepped = null;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// The arrow keys step the height by an em, Home and End send it to either end (`keydown`).
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final step = widget.onStep;
    if (step == null || event is KeyUpEvent) return KeyEventResult.ignored;
    final now = _stepped ?? widget.now;
    final key = event.logicalKey;
    final double? next = key == LogicalKeyboardKey.arrowUp
        ? now - 1
        : key == LogicalKeyboardKey.arrowDown
            ? now + 1
            : key == LogicalKeyboardKey.home
                ? boardHeight.min
                : key == LogicalKeyboardKey.end
                    ? boardHeight.max
                    : null;
    if (next == null) return KeyEventResult.ignored;
    step(_stepped = clampHeight(next));
    return KeyEventResult.handled;
  }

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
              // `.cm-boardSplit:focus-visible, .cm-boardSplit[data-dragging]`: the same line either way.
              Positioned.fill(child: ColoredBox(key: const ValueKey<String>('board-split'), color: _dragging || _focused ? look.splitInkHeld : look.splitInk)),
              Positioned(
                top: (look.splitLine - BoardLook.gripHeight) / 2,
                child: Container(
                  key: const ValueKey<String>('board-grip'),
                  width: look.gripWidth,
                  height: BoardLook.gripHeight,
                  decoration: ShapeDecoration(color: _dragging || _focused ? const Color(0xffffffff) : look.gripInk, shape: const StadiumBorder()),
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
          ? Focus(
              focusNode: _focus,
              onKeyEvent: _key,
              onFocusChange: (on) => setState(() => _focused = on),
              child: Listener(
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
              ),
            )
          : line,
    );
  }
}
