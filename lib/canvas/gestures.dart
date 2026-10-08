/// The fingers on a canvas: a press is a tap until it moves, one finger that moves pans, two pinch, and a press
/// held still on a card lifts it to be carried. A port of `src/app/canvas/gestures.ts` as a state machine fed raw
/// pointer events by the view's `Listener`, with no gesture arena: nothing here waits to win.
///
/// The point of the canvas under the fingers stays under them, whatever they do: a second finger's spread scales
/// about that point, and one finger's move carries it along; every move is measured from where the fingers took
/// hold, not from the last move. A press held [holdMs] on a card, on a canvas that can change, lifts it, and a
/// finger that moved first was panning, so a card never moves by mistake. A carried card, and a group with
/// everything wholly inside it, follows the finger in the canvas's own pixels from the canvas as it was at the
/// hold, and is put down where the finger lets go.
///
/// Some presses need no hold. A mouse that drags a card moves it, and the page is panned from the open ground
/// between cards, by the wheel, with Space held or with the middle button. A finger that drags the card already
/// picked moves it; any other card under a moving finger is still the page being panned. A group is taken by its
/// name or by its border, with either: its ground is the page's.
///
/// With snapping on, a carried card goes from dot to dot of the grid, and the phone ticks each time it lands on a
/// new one.
///
/// What differs from the web:
/// - What a press landed on is asked of the view ([CanvasGestures.hitAt]) where the web read the event's target
///   and its `data-card`: the view answers from the canvas's own geometry (canvas_view.dart `_hit`).
/// - Positions are in the canvas's own box, so a pinch keeps its point when the canvas is not at the window's
///   corner (the web measured from the window, and is right only there).
/// - A tap is told here ([onTap]) where the browser made a click; and nothing is "captured", since a pointer's
///   events all come to the one listener wherever it goes.
/// - A trackpad's two fingers ([panZoomStart], [panZoomUpdate]): pan and pinch about where the pointer is.
/// - The wait before a lift is lib/core/hold_drag.dart's [holdTime], the one the boards and the tabs wait
///   (`HOLD_MS`, core/gestures.ts). Only the wait is shared: the canvas's press is this machine's, as the web's
///   canvas has gestures.ts of its own beside `holdDrag.ts`, since a canvas's press may also become a pan or a
///   pinch, and its card is carried in the canvas's pixels under the camera rather than as a copy in the air.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import '../core/hold_drag.dart' show holdTime;
import 'camera.dart';
import 'edits.dart';
import 'json_canvas.dart';
import 'viewport.dart';

/// How far a finger moves before a press is a drag rather than a tap, in screen pixels (`SLOP_PX`).
const double slopPx = 4;

/// How near a group's edge a press is on its border, in screen pixels: a finger's reach (`BORDER_PX`).
const double borderPx = 14;

/// How long a press stays put before it lifts the card under it rather than panning the page (`HOLD_MS`).
final int holdMs = holdTime.inMilliseconds;

/// What a press landed on.
class CanvasHit {
  const CanvasHit({this.node, this.grip = false, this.name = false, this.title = false, this.line});

  /// The card or group under the press.
  final CanvasNode? node;

  /// On a group: on what it is taken by, its name or its border.
  final bool grip;

  /// On a group's name itself (`data-group-grip`).
  final bool name;

  /// On a card's title (`data-card-title`).
  final bool title;

  /// The line under the press, by id (`data-line`).
  final String? line;
}

class _Grip {
  const _Grip(this.x, this.y, this.distance);
  final double x;
  final double y;
  final double distance;
}

class _Held {
  const _Held(this.node, this.x, this.y, this.base);
  final CanvasNode node;
  final double x;
  final double y;
  final Canvas base;
}

class CanvasGestures {
  CanvasGestures({
    required this.camera,
    required this.live,
    required this.editable,
    required this.selected,
    required this.snap,
    required this.hitAt,
    required this.onPress,
    required this.onCarry,
    required this.onPutDown,
    required this.onTap,
    required this.onLifted,
    this.felt,
  });

  final CanvasCamera camera;

  /// The canvas as it is drawn now: a held card is carried from it.
  final Canvas Function() live;

  /// Whether a held press may lift a card: the canvas can change.
  final bool Function() editable;

  /// The card picked, by id: a finger that drags it moves it without the hold.
  final String? Function() selected;

  /// Whether a carried card lands on the grid's dots.
  final bool Function() snap;
  final CanvasHit Function(double x, double y) hitAt;

  /// Any press on the canvas itself, before it is anything else.
  final void Function() onPress;

  /// A carried card moved: the canvas with it where the finger is, drawn but not yet handed on.
  final void Function(Canvas next) onCarry;

  /// A carried card let go: the canvas with it where it was put down, which card it was, and whether it moved.
  final void Function(Canvas next, String id, bool moved) onPutDown;

  /// A press that ended without becoming a drag, where it began and what it began on.
  final void Function(double x, double y, CanvasHit hit) onTap;

  /// The card lifted, by id, for its look while it is carried; null when it is put down.
  final void Function(String? id) onLifted;

  /// A tick, each time a carried card lands on a new dot (`fireFelt('selection')`).
  final void Function()? felt;

  final Map<int, ({double x, double y})> _pointers = {};

  /// Where the fingers took hold and what the view was then.
  ({CameraView view, double x, double y, double distance})? _hold;

  /// Whether the press now under way became a drag.
  bool dragged = false;
  _Held? _carrying;
  _Held? _grab;
  String? _landed;
  Timer? _holdTimer;
  CanvasHit _downOn = const CanvasHit();
  ({double x, double y})? _downAt;

  /// Space held: every drag pans, whatever is under the pointer.
  bool spaceHeld = false;

  /// The card lifted, by id.
  String? lifted;

  void _setLifted(String? id) {
    if (lifted == id) return;
    lifted = id;
    onLifted(id);
  }

  _Grip _grip() {
    final all = _pointers.values.toList();
    if (all.isEmpty) return const _Grip(0, 0, 0);
    if (all.length < 2) return _Grip(all[0].x, all[0].y, 0);
    final a = all[0];
    final b = all[1];
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return _Grip((a.x + b.x) / 2, (a.y + b.y) / 2, math.sqrt(dx * dx + dy * dy));
  }

  void _takeHold() {
    final at = _grip();
    _hold = (view: camera.view, x: at.x, y: at.y, distance: at.distance);
  }

  /// The carried card moved by what the finger has moved since the hold, in the canvas's own pixels.
  Canvas? _carried(double toX, double toY) {
    final held = _carrying;
    if (held == null) return null;
    final scale = camera.view.scale;
    final x = held.node.x + (toX - held.x) / scale;
    final y = held.node.y + (toY - held.y) / scale;
    if (!snap()) return movedWithHeld(held.base, held.node, x, y);
    // On the grid: the card's corner at the nearest dot, and a tick when that is a new one.
    final dot = atDot(x, y);
    final key = '${dot.x},${dot.y}';
    if (_landed != key) {
      if (_landed != null) felt?.call();
      _landed = key;
    }
    return movedWithHeld(held.base, held.node, dot.x, dot.y);
  }

  /// A pointer down at (x, y) of the canvas's own box. [middle] is the middle button; [main] the main one, or a
  /// finger.
  void down(int pointer, double x, double y, {required PointerDeviceKind kind, bool middle = false, bool main = true}) {
    onPress();
    _holdTimer?.cancel();
    if (_pointers.isEmpty) {
      dragged = false;
      _carrying = null;
      _grab = null;
      _landed = null;
      final hit = hitAt(x, y);
      _downOn = hit;
      _downAt = (x: x, y: y);
      // The middle button and Space pan, whatever is under the pointer.
      final panning = middle || spaceHeld;
      // One finger on a card, on a canvas that can change: held still for a moment, it lifts the card.
      final node = editable() && !panning && hit.line == null ? hit.node : null;
      if (node != null) {
        // And some are moved by the drag itself, with no hold (see the header).
        final taken = node.isGroup ? hit.grip : kind == PointerDeviceKind.mouse || node.id == selected();
        final base = live();
        // The main button only: a right-click is a menu's, not a drag.
        if (taken && main) _grab = _Held(node, x, y, base);
        _holdTimer = Timer(holdTime, () {
          if (_pointers.length != 1 || !_pointers.containsKey(pointer)) return;
          _carrying = _Held(node, x, y, base);
          dragged = true;
          _setLifted(node.id);
        });
      }
    } else {
      // A second finger: the two pan and pinch the page, and nothing is carried.
      _carrying = null;
      _grab = null;
      _setLifted(null);
    }
    _pointers[pointer] = (x: x, y: y);
    _takeHold();
  }

  void move(int pointer, double x, double y) {
    final start = _hold;
    if (!_pointers.containsKey(pointer) || start == null) return;
    _pointers[pointer] = (x: x, y: y);
    final now = _grip();
    if (!dragged) {
      final dx = now.x - start.x;
      final dy = now.y - start.y;
      if (_pointers.length < 2 && math.sqrt(dx * dx + dy * dy) < slopPx) return;
      // Moved before the hold: a pan, and the card stays where it is - unless this press takes its card with it.
      _holdTimer?.cancel();
      dragged = true;
      final grab = _grab;
      if (grab != null && _pointers.length < 2) {
        _carrying = grab;
        _setLifted(grab.node.id);
      }
      _grab = null;
    }
    // A card being carried: it follows the finger in the canvas's own pixels, and the page stays put.
    final next = _pointers.length < 2 ? _carried(x, y) : null;
    if (next != null) {
      onCarry(next);
      return;
    }
    // The point of the canvas that was under the fingers stays under them, whatever they do.
    final scale = start.distance > 0 && now.distance > 0 ? clampScale((start.view.scale * now.distance) / start.distance) : start.view.scale;
    final underX = (start.x - start.view.x) / start.view.scale;
    final underY = (start.y - start.view.y) / start.view.scale;
    camera.moveTo(CameraView(x: now.x - underX * scale, y: now.y - underY * scale, scale: scale));
  }

  /// A pointer up, or cancelled.
  void up(int pointer, double x, double y, {bool cancelled = false}) {
    _holdTimer?.cancel();
    if (_pointers.remove(pointer) == null) return;
    // A card let go where it was carried to: the canvas is handed on with it there.
    final next = _carried(x, y);
    _grab = null;
    if (next != null) {
      final held = _carrying!;
      _carrying = null;
      _setLifted(null);
      onPutDown(next, held.node.id, x != held.x || y != held.y);
    }
    if (_pointers.isNotEmpty) {
      _takeHold();
      return;
    }
    _hold = null;
    final at = _downAt;
    if (!dragged && !cancelled && at != null) onTap(at.x, at.y, _downOn);
  }

  // ---- a trackpad's two fingers ----------------------------------------------------------------

  ({CameraView view, double x, double y})? _pad;

  void panZoomStart(double x, double y) {
    onPress();
    _pad = (view: camera.view, x: x, y: y);
  }

  /// The fingers have moved [panX], [panY] since they landed and spread to [scale] times apart.
  void panZoomUpdate(double panX, double panY, double scale) {
    final start = _pad;
    if (start == null) return;
    final next = clampScale(start.view.scale * scale);
    final underX = (start.x - start.view.x) / start.view.scale;
    final underY = (start.y - start.view.y) / start.view.scale;
    camera.moveTo(CameraView(x: start.x + panX - underX * next, y: start.y + panY - underY * next, scale: next));
  }

  void panZoomEnd() => _pad = null;

  void dispose() => _holdTimer?.cancel();
}
