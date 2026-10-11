/// Pointers on the note: a tap puts the caret, two take a word and three a line, a press held takes the word under
/// it (or, on empty paper, puts the caret there) and asks for the note's menu, and a drag selects.
///
/// On the web most of this is the browser's own doing over a `contenteditable`, with CodeMirror's mouse handling
/// (@codemirror/view input.ts `MouseSelection`, `rangeForClick`, `groupAt`) and three files of the app's:
/// - `pressAndHold.ts`: where the menu is asked for. A press held on a word selects it and the menu opens over
///   the caret a frame later; held [longPress] on empty paper (an empty line, the space past a line's last word)
///   within eight pixels of where it began, the caret goes to the finger, the phone ticks, and the menu opens
///   there. Never over something drawn that answers a press itself (`isDrawnBlock`: a board, a diagram, a place's
///   map, a film's card, a query's answer). Over anything else the note draws in place of its words (a table, a
///   canvas's frame, a formula, a chip) a press held is still the note's: the page hears its `contextmenu`
///   wherever it lands, and the menu opens over the caret as it stands, the selection left alone.
/// - `boxTaps.ts` and `taskToggle.ts`: a plain tap on a to-do's box, or within eight pixels of it, turns the box
///   and leaves the caret (and the keyboard) where it was.
/// - a widget that keeps its pointers (`ignoreEvent`, here `EditorWidget.takesPointer`) is left to itself: the
///   editor does not join the gesture at all.
///
/// The plugins' handlers (plugin.dart `EditorEventHandlers`) are asked before the editor acts, in precedence
/// order, and one that answers true has handled it.
///
/// What differs from the web:
/// - a finger's long press is timed here for a word too (the web leaves that one to the phone, about as long), so
///   both are [longPress];
/// - dragging on after a press was held extends the selection by words, as Android's own text does; the web's
///   WebView does the same under the page;
/// - a touch drag that was not held scrolls the page: the scroll view's own recogniser wins it.
///
/// A plugin's `mousedown` (plugin.dart `EditorEventHandlers.mouseDown`: a `[[link]]`, a to-do's box, a choice, a
/// footnote, a mark's note, an answer's panel) is asked when a browser would send one: at a mouse's press, and for a
/// finger when its tap has finished, since a touch is sent its mouse events only after it lifts from a tap. So a
/// finger that lands on a link and scrolls opens nothing, and one held there asks for the menu alone.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../commands/task_toggle.dart';
import '../state/char.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../view/drawn_block.dart' show isDrawnBlock;
import '../view/editor_view.dart';
import '../view/plugin.dart';
import 'motion.dart';

/// Where the note's menu is asked for (pressAndHold.ts `Held`): the caret's place when the view has one for it,
/// else the finger's, in global logical pixels; and the selection.
class Held {
  const Held({required this.x, required this.y, required this.from, required this.to});

  final double x;
  final double y;
  final int from;
  final int to;

  @override
  String toString() => 'Held($x, $y, $from-$to)';
}

/// What the gestures ask of the editor's widget.
abstract class EditorGesturesHost {
  EditorView get view;

  /// Takes the keyboard's focus; `keyboard` raises it too.
  void takeFocus({required bool keyboard});
  void showHandles();
  void hideHandles();
  void showMagnifier(Offset global);
  void hideMagnifier();
  void autoScroll(Offset global, VoidCallback again);
  void stopAutoScroll();
  void held(Held held);

  /// A global point in the editor's own box.
  Offset toLocal(Offset global);
}

/// CodeMirror's `groupAt` (@codemirror/view input.ts): the word, the run of spaces or the run of other characters
/// at `pos`, on its line. `bias` picks the character after `pos` (above zero) or before it.
SelectionRange groupAt(EditorState state, int pos, [int bias = 1]) {
  final categorize = state.charCategorizer(pos);
  final line = state.doc.lineAt(pos), linePos = pos - line.from;
  if (line.length == 0) return EditorSelection.cursor(pos);
  if (linePos == 0) {
    bias = 1;
  } else if (linePos == line.length) {
    bias = -1;
  }
  var from = linePos, to = linePos;
  if (bias < 0) {
    from = findClusterBreak(line.text, linePos, false);
  } else {
    to = findClusterBreak(line.text, linePos);
  }
  final cat = categorize(line.text.substring(from, to));
  while (from > 0) {
    final prev = findClusterBreak(line.text, from, false);
    if (categorize(line.text.substring(prev, from)) != cat) break;
    from = prev;
  }
  while (to < line.length) {
    final next = findClusterBreak(line.text, to);
    if (categorize(line.text.substring(to, next)) != cat) break;
    to = next;
  }
  return EditorSelection.range(from + line.from, to + line.from);
}

/// boxTaps.ts `tapsRange`: whether a tap lands on the characters `from`-`to`, or near enough to them.
bool tapsRange(EditorView view, Offset global, int from, int to) {
  const slop = 8.0;
  final start = view.coordsAtPos(from, 1), end = view.coordsAtPos(to, -1);
  if (start == null || end == null) return false;
  return global.dx >= start.left - slop && global.dx <= end.right + slop && global.dy >= start.top - slop && global.dy <= start.bottom + slop;
}

class EditorGestures {
  EditorGestures(this.host) {
    _tap
      ..onTapUp = ((details) => _tapped(details.globalPosition, details.kind))
      ..onSecondaryTapUp = ((details) => _secondary(details.globalPosition, details.kind));
    _long
      ..onLongPressStart = ((details) => _holdStart(details.globalPosition))
      ..onLongPressMoveUpdate = ((details) => _holdMove(details.globalPosition))
      ..onLongPressEnd = ((_) => _holdEnd())
      ..onLongPressCancel = _holdEnd;
    _drag
      ..onDown = ((details) => _mouseDown(details.globalPosition))
      ..onUpdate = ((details) => _mouseDrag(details.globalPosition))
      ..onEnd = ((_) => _mouseUp())
      ..onCancel = _mouseUp;
  }

  final EditorGesturesHost host;

  /// pressAndHold.ts `LONG_PRESS_MS`: about the phone's own long press.
  static const Duration longPress = Duration(milliseconds: 480);

  /// How long after a tap another one counts with it (a double tap, a triple).
  static const Duration multiTap = kDoubleTapTimeout;

  final TapGestureRecognizer _tap = TapGestureRecognizer();
  final LongPressGestureRecognizer _long = LongPressGestureRecognizer(
    duration: longPress,
    supportedDevices: const <PointerDeviceKind>{PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus, PointerDeviceKind.unknown},
  );
  final PanGestureRecognizer _drag = PanGestureRecognizer(supportedDevices: const <PointerDeviceKind>{PointerDeviceKind.mouse})..dragStartBehavior = DragStartBehavior.down;

  EditorView get _view => host.view;
  PointerDeviceKind _kind = PointerDeviceKind.touch;

  void dispose() {
    _taps?.cancel();
    _tap.dispose();
    _long.dispose();
    _drag.dispose();
  }

  bool _handled(bool Function(EditorEventHandlers handlers) ask) {
    for (final observers in _view.eventObservers) {
      ask(observers);
    }
    for (final handlers in _view.eventHandlers) {
      if (ask(handlers)) return true;
    }
    return false;
  }

  EditorTap _tapAt(Offset global, PointerDeviceKind kind) => EditorTap(global: global, local: host.toLocal(global), kind: kind, pos: _view.posAtCoords(global));

  /// Every pointer event on the editor comes through here.
  void pointer(PointerEvent event) {
    switch (event) {
      case PointerDownEvent():
        _kind = event.kind;
        _landed = null;
        if (_handled((h) => h.pointerDown?.call(event, _view) ?? false)) return;
        // A mouse's press is its `mousedown`. A finger's comes when its tap has finished ([_tapped]).
        final mouse = event.kind == PointerDeviceKind.mouse;
        if (mouse && _handled((h) => h.mouseDown?.call(event, _view) ?? false)) return;
        // A widget that keeps its pointers is left to itself. A finger held on it still asks for the note's menu,
        // unless it is one that answers a press held itself (drawnBlock.ts `isDrawnBlock`).
        final hit = _view.hitAt(event.position);
        if (hit != null && hit.inside && ((hit.widget?.takesPointer(event) ?? false) || (hit.block?.takesPointer(event) ?? false))) {
          if (!mouse && !isDrawnBlock(hit.block) && !isDrawnBlock(hit.widget)) {
            _onDrawn = true;
            _long.addPointer(event);
          }
          return;
        }
        _onDrawn = false;
        if (mouse && event.buttons == kPrimaryMouseButton) {
          _shift = HardwareKeyboard.instance.isShiftPressed;
          _drag.addPointer(event);
        } else {
          if (!mouse) _landed = event;
          _tap.addPointer(event);
          _long.addPointer(event);
        }
      case PointerMoveEvent():
        _handled((h) => h.pointerMove?.call(event, _view) ?? false);
      case PointerUpEvent():
        _handled((h) => h.pointerUp?.call(event, _view) ?? false);
      case PointerCancelEvent():
        _handled((h) => h.pointerCancel?.call(event, _view) ?? false);
      default:
    }
  }

  // -- taps ---------------------------------------------------------------------------------------------------------

  /// A finger's landing the editor joined, kept for the `mousedown` its finished tap is owed.
  PointerDownEvent? _landed;

  int _count = 0;
  Offset _lastTap = Offset.zero;
  Timer? _taps;

  int _counted(Offset global) {
    final near = (global - _lastTap).distance <= kDoubleTapSlop;
    _count = _taps != null && near ? _count + 1 : 1;
    _lastTap = global;
    _taps?.cancel();
    _taps = Timer(multiTap, () => _taps = null);
    return _count;
  }

  bool get _changeable => !_view.state.readOnly;
  bool get _editable => _view.state.facet(EditorViewLike.editable);

  ({int from, int to, bool done})? _boxUnder(Offset global) {
    final pos = _view.posAtCoords(global, precise: false);
    if (pos == null) return null;
    final box = boxAt(_view.state, pos);
    return box != null && tapsRange(_view, global, box.from, box.to) ? box : null;
  }

  void _select(EditorSelection selection, {bool scroll = false}) {
    _view.dispatch(TransactionSpec(selection: selection, userEvent: 'select.pointer', scrollIntoView: scroll));
  }

  /// The selection `count` taps at `global` make: a caret, a word, a line.
  SelectionRange? _rangeFor(Offset global, int count) {
    final hit = _view.hitAt(global);
    if (hit == null) return null;
    final state = _view.state;
    final pos = skipAtoms(_view, hit.pos);
    if (count == 1) return EditorSelection.cursor(pos, hit.assoc);
    if (count == 2) return groupAt(state, pos, hit.assoc);
    final line = state.doc.lineAt(pos);
    return EditorSelection.range(line.from, line.to < state.doc.length ? line.to + 1 : line.to);
  }

  void _tapped(Offset global, PointerDeviceKind kind) {
    // The `mousedown` of a finger's tap: the browser sends it now, the tap done, and never for a touch that
    // became a scroll or was held (those never get here: the scroll view or the long press won the pointer).
    final landed = _landed;
    _landed = null;
    if (landed != null && _handled((h) => h.mouseDown?.call(landed, _view) ?? false)) return;
    final count = _counted(global);
    final tap = _tapAt(global, kind);
    if (count == 2 && _handled((h) => h.doubleTap?.call(tap, _view) ?? false)) return;
    if (count == 1) {
      if (_handled((h) => h.tap?.call(tap, _view) ?? false)) return;
      // A to-do's box, before the caret moves: it turns and nothing else happens.
      final box = _changeable ? _boxUnder(global) : null;
      if (box != null) {
        _count = 0;
        _view.dispatch(toggleBox(_view.state, box));
        fireMotor(HapticKind.selection);
        return;
      }
    }
    final range = _rangeFor(global, count > 3 ? 1 : count);
    if (range == null) return;
    _select(EditorSelection.create(<SelectionRange>[range]));
    host.takeFocus(keyboard: _editable && range.empty);
    if (range.empty && !_editable) {
      host.hideHandles();
    } else {
      host.showHandles();
    }
  }

  void _secondary(Offset global, PointerDeviceKind kind) {
    final tap = _tapAt(global, kind);
    if (_handled((h) => h.secondaryTap?.call(tap, _view) ?? false)) return;
    final hit = _view.hitAt(global);
    if (hit == null || (hit.block != null && hit.inside)) return;
    // A right click outside the selection moves the caret to it first, as a browser does.
    final sel = _view.state.selection.main;
    if (hit.pos < sel.from || hit.pos > sel.to) _select(EditorSelection.single(skipAtoms(_view, hit.pos)));
    host.takeFocus(keyboard: false);
    _ask(global);
  }

  // -- a press held ---------------------------------------------------------------------------------------------------

  /// The word a hold selected, which a drag afterwards stretches from; null when the hold put a caret.
  SelectionRange? _heldWord;
  Offset _finger = Offset.zero;
  bool _holding = false;

  /// Whether the press being held landed on a widget that keeps its pointers.
  bool _onDrawn = false;

  void _holdStart(Offset global) {
    _heldWord = null;
    final tap = _tapAt(global, _kind);
    if (_handled((h) => h.longPress?.call(tap, _view) ?? false)) return;
    final hit = _view.hitAt(global);
    if (hit == null) return;
    if (_onDrawn || (hit.block != null && hit.inside)) {
      // Over something the note draws in place of its words. One that answers a press itself keeps it; on any
      // other (a table, a canvas's frame) the menu is asked for as the page's `contextmenu` asks: over the caret
      // where it is, nothing selected and the focus where it was.
      if (isDrawnBlock(hit.block) || isDrawnBlock(hit.widget)) return;
      fireMotor(HapticKind.selection);
      _ask(global);
      return;
    }
    // An empty note has no text under the finger; the nearest place in the note is what a press means anyway.
    final pos = skipAtoms(_view, tap.pos ?? hit.pos);
    final state = _view.state;
    final line = state.doc.lineAt(pos);
    bool wordAt(int offset) => offset >= line.from && offset < line.to && state.doc.sliceString(offset, offset + 1).trim().isNotEmpty;
    // Past a line's last word, or before its first, the finger is on paper though the nearest place is beside a
    // word.
    final edge = pos == line.to || pos == line.from ? _view.coordsAtPos(pos, pos == line.to ? -1 : 1) : null;
    final onPaper = edge != null && (pos == line.to ? global.dx > edge.right + 8 : global.dx < edge.left - 8);
    _holding = true;
    _finger = global;
    if (!onPaper && (wordAt(pos) || wordAt(pos - 1))) {
      final word = groupAt(state, pos, wordAt(pos) ? 1 : -1);
      _heldWord = word;
      _select(EditorSelection.create(<SelectionRange>[word]));
      host.takeFocus(keyboard: false);
      host.showHandles();
    } else {
      _select(EditorSelection.single(pos));
      host.takeFocus(keyboard: false);
    }
    fireMotor(HapticKind.selection);
    _ask(global);
  }

  /// The menu opens a frame later, when the selection has landed, over the caret.
  void _ask(Offset finger) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sel = _view.state.selection.main;
      final at = _view.coordsAtPos(sel.head, sel.assoc == 0 ? 1 : sel.assoc);
      host.held(Held(x: at?.center.dx ?? finger.dx, y: at?.top ?? finger.dy, from: sel.from, to: sel.to));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _holdMove(Offset global) {
    if (!_holding) return;
    _finger = global;
    _holdTo();
    host.autoScroll(global, _holdTo);
  }

  void _holdTo() {
    final word = _heldWord;
    if (!_holding || word == null) return;
    final found = _view.posAtCoords(_finger, precise: false);
    if (found == null) return;
    final pos = skipAtoms(_view, found);
    final here = pos >= word.from && pos <= word.to ? word : groupAt(_view.state, pos, pos < word.from ? 1 : -1);
    final range = here.from < word.from ? EditorSelection.range(word.to, here.from) : EditorSelection.range(word.from, here.to > word.to ? here.to : word.to);
    final sel = _view.state.selection.main;
    if (range.from != sel.from || range.to != sel.to) _select(EditorSelection.create(<SelectionRange>[range]));
    host.showMagnifier(_finger);
  }

  void _holdEnd() {
    if (!_holding) return;
    _holding = false;
    _heldWord = null;
    host.stopAutoScroll();
    host.hideMagnifier();
  }

  // -- a mouse ------------------------------------------------------------------------------------------------------

  SelectionRange? _dragFrom;
  int _dragCount = 1;
  bool _shift = false;

  void _mouseDown(Offset global) {
    final count = _counted(global);
    final tap = _tapAt(global, PointerDeviceKind.mouse);
    _dragFrom = null;
    if (count == 2 && _handled((h) => h.doubleTap?.call(tap, _view) ?? false)) return;
    if (count == 1) {
      if (_handled((h) => h.tap?.call(tap, _view) ?? false)) return;
      final box = _changeable && !_shift ? _boxUnder(global) : null;
      if (box != null) {
        _count = 0;
        _view.dispatch(toggleBox(_view.state, box));
        return;
      }
    }
    _dragCount = count > 3 ? 1 : count;
    final range = _rangeFor(global, _dragCount);
    if (range == null) return;
    final sel = _view.state.selection.main;
    final start = _shift ? EditorSelection.range(sel.anchor, range.head) : range;
    _dragFrom = _shift ? EditorSelection.cursor(sel.anchor) : range;
    _finger = global;
    _select(EditorSelection.create(<SelectionRange>[start]));
    host.takeFocus(keyboard: _editable);
    host.hideHandles();
  }

  void _mouseDrag(Offset global) {
    if (_dragFrom == null) return;
    _finger = global;
    _mouseTo();
    host.autoScroll(global, _mouseTo);
  }

  void _mouseTo() {
    final from = _dragFrom;
    if (from == null) return;
    final here = _rangeFor(_finger, _dragCount);
    if (here == null) return;
    final range = here.from < from.from ? EditorSelection.range(from.to, here.from) : EditorSelection.range(from.from, here.to > from.to ? here.to : from.to);
    final sel = _view.state.selection.main;
    if (range.anchor != sel.anchor || range.head != sel.head) _select(EditorSelection.create(<SelectionRange>[range]));
  }

  void _mouseUp() {
    _dragFrom = null;
    host.stopAutoScroll();
  }
}
