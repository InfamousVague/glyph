/// The one way a thing is picked up and carried in the app (Matt: "update the clicking and dragging ... the same
/// mechanism as clicking and dragging on board view, right now they seem to diverge"): a ```board's card
/// (editor/boards/drag.dart), a query board's card and a query list's row, a notebook's pages and a canvas's cards
/// are all carried by this gesture and drawn by [liftGhost], so none of them can drift from the others. Ports
/// `src/app/core/holdDrag.ts` and `src/app/core/useCarry.ts`.
///
/// Press and hold to lift, a mouse as much as a finger. Before the hold is up the pointer is still the page's: a
/// move past [dragSlop] is a scroll and nothing is taken over. Lifted, the pointer is the drag's - a scroll under it
/// is refused - until it lets go, which drops the thing where it is, or is cancelled.
///
///     holdDrag(down, hooks)     the gesture for one press: lift at the hold, move, drop, end
///     liftGhost(context, …)     the thing in the air: a copy over the whole app, under the pointer
///     EdgeRoller                what is under a carried thing rolled along while it is held near an edge
///     Carry<T>                  a thing carried in a list of lanes: what is carried, where it would land
///
/// What differs:
/// - **How the pointer is taken.** The page heard the moves on the window and refused a touch's pan, its long-press
///   menu and its text selection one by one (`touchmove`, `contextmenu`, `selectstart`). Here the press joins the
///   gesture arena with a recognizer of its own ([HoldDragGestureRecognizer]) that says nothing until the hold is up:
///   a scroll view's drag wins a finger that moves first, exactly as if the thing were not there. At [holdTime] the
///   recognizer claims the pointer, and every other recognizer on it (the scrollers', a tap's, a long press's) is
///   refused at once, which is all three of the page's refusals. The recognizer belongs to the gesture, not to the
///   widget pressed, so the thing may be rebuilt, moved to where it would land or taken off the page mid-carry, as
///   the page's element could be.
/// - **The copy in the air** cannot be a clone of an element: the caller hands [liftGhost] a builder for it, and the
///   box of the thing on the screen. A table's row lifted in a table of its own is the caller's builder's business.
/// - **`document.documentElement.dataset.dragging`** (no text picked up on the way, the grabbing cursor) has nothing
///   to switch off here: nothing selects under a claimed pointer.
/// - **A roll is a step a frame**, as `requestAnimationFrame` made it, through the scheduler; a scroller is named by
///   its [ScrollPosition] and the box it shows in ([CarryScroller]).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

/// How long a press is held before the thing under it is picked up (core/gestures.ts `HOLD_MS`).
const Duration holdTime = Duration(milliseconds: 220);

/// How far a pointer resting on a thing may stray before the hold is up (`DRAG_SLOP`).
const double dragSlop = 10;

/// How near an edge a carried thing rolls what is under it, and how far a frame (`ROLL_EDGE`, `ROLL_STEP`;
/// editor/boards/scrolling.ts `EDGE`).
const double rollEdge = 44;
const double rollStep = 14;

/// What a gesture tells the thing it carries (`HoldDragHooks`). Every point is the pointer's, in global logical
/// pixels.
class HoldDragHooks {
  const HoldDragHooks({required this.lift, required this.move, required this.drop, this.end});

  /// Held long enough: the thing is lifted under the pointer.
  final void Function(Offset at) lift;

  /// The lifted thing carried to `at`.
  final void Function(Offset at) move;

  /// Let go: dropped where it is.
  final void Function(Offset at) drop;

  /// Cancelled, or let go before it was lifted. `lifted` says whether it had been.
  final void Function(bool lifted)? end;
}

/// Starts the gesture for a pointer pressed on a thing (`holdDrag`). Call it from the thing's `Listener.onPointerDown`,
/// after the thing has decided the press is its own (not one of its controls'). Answers a way to give the gesture
/// up early.
VoidCallback holdDrag(PointerDownEvent down, HoldDragHooks hooks) {
  if (down.kind == PointerDeviceKind.mouse && down.buttons != kPrimaryMouseButton) return () {};
  final recognizer = HoldDragGestureRecognizer(hooks)..addPointer(down);
  return recognizer.giveUp;
}

/// The gesture in the arena: silent until [holdTime], then the pointer's owner. One is made for each press and
/// disposes of itself when the press ends.
class HoldDragGestureRecognizer extends OneSequenceGestureRecognizer {
  HoldDragGestureRecognizer(this.hooks);

  final HoldDragHooks hooks;

  Timer? _timer;
  int? _pointer;
  Offset _start = Offset.zero;
  bool _lifted = false;
  bool _finished = false;

  /// Whether the thing has been lifted.
  bool get lifted => _lifted;

  @override
  String get debugDescription => 'hold and drag';

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // One finger carries: a second one down is another gesture's.
    if (_pointer != null) return;
    super.addAllowedPointer(event);
    _pointer = event.pointer;
    _start = event.position;
    _timer = Timer(holdTime, _lift);
  }

  void _lift() {
    _timer = null;
    if (_finished) return;
    _lifted = true;
    // The pointer is the drag's from here: whatever else was waiting on it (a scroll, a tap, a long press) is told
    // it has lost.
    resolve(GestureDisposition.accepted);
    fireMotor(HapticKind.selection);
    hooks.lift(_start);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer || _finished) return;
    if (event is PointerMoveEvent) {
      if (!_lifted) {
        // Moved before the hold was up: the pointer is scrolling, so the thing is left alone.
        if ((event.position - _start).distance > dragSlop) _finish();
        return;
      }
      hooks.move(event.position);
    } else if (event is PointerUpEvent) {
      // Dropped first, then the gesture's own ending: the thing decides where it landed while it is still lifted.
      if (_lifted) hooks.drop(event.position);
      _finish();
    } else if (event is PointerCancelEvent) {
      _finish();
    }
  }

  @override
  void acceptGesture(int pointer) {}

  /// Something else took the pointer before the hold was up: a scroll that began, most often.
  @override
  void rejectGesture(int pointer) {
    if (!_lifted) _finish();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  /// Gives the gesture up, lifted or not; safe to call again.
  void giveUp() => _finish();

  void _finish() {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    _timer = null;
    final lifted = _lifted;
    if (!lifted) resolve(GestureDisposition.rejected);
    final pointer = _pointer;
    if (pointer != null) stopTrackingPointer(pointer);
    hooks.end?.call(lifted);
    // After the router has finished handing this event round.
    scheduleMicrotask(dispose);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _finished = true;
    super.dispose();
  }
}

/// A copy of a lifted thing following the pointer overhead ([liftGhost]).
class Ghost {
  Ghost._(this._entry, this._place, this._grab);

  OverlayEntry? _entry;
  final ValueNotifier<Offset> _place;
  final Offset _grab;

  /// Where the copy's top left is now, in global logical pixels.
  Offset get at => _place.value;

  /// The copy under a pointer at `to`, held by the spot it was taken by.
  void follow(Offset to) => _place.value = to - _grab;

  /// The copy taken away; safe to call again.
  void remove() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }
}

/// `box-shadow: 0 10px 24px rgb(0 0 0 / 28%)` (`.app-dragGhost`, `.cm-boardGhost`): a CSS blur of 24 is a sigma of
/// 12, which is this radius to Flutter.
const BoxShadow ghostShadow = BoxShadow(color: Color(0x47000000), offset: Offset(0, 10), blurRadius: (12 - 0.5) / 0.57735);

/// The copy's own opacity (`opacity: 0.96`).
const double ghostOpacity = 0.96;

/// The thing in the air (`liftGhost`): `builder`'s widget drawn over the whole app, as wide as `box` (the thing's
/// own box on the screen, global), under the pointer `at` by the spot it was taken by, lifted with a shadow of
/// `radius` corners. It lives in the app's top overlay, outside the page, so whatever look it needs must come with
/// the builder. Null where there is no overlay to draw in.
Ghost? liftGhost(BuildContext context, {required Rect box, required Offset at, required WidgetBuilder builder, BorderRadius radius = BorderRadius.zero}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;
  final origin = (overlay.context.findRenderObject() as RenderBox?)?.localToGlobal(Offset.zero) ?? Offset.zero;
  final place = ValueNotifier<Offset>(box.topLeft);
  final entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 0,
      top: 0,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: ValueListenableBuilder<Offset>(
            valueListenable: place,
            builder: (context, to, child) => Transform.translate(offset: to - origin, child: child),
            child: SizedBox(
              width: box.width,
              child: Opacity(
                opacity: ghostOpacity,
                child: DecoratedBox(
                  decoration: BoxDecoration(borderRadius: radius, boxShadow: const <BoxShadow>[ghostShadow]),
                  child: builder(context),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  return Ghost._(entry, place, at - box.topLeft);
}

/// Something that rolls under a carried thing: where it is scrolled to, which way, and the box it shows in.
class CarryScroller {
  const CarryScroller({required this.position, required this.axis, required this.box, this.zone = rollEdge, this.under = 0});

  final ScrollPosition position;
  final Axis axis;

  /// The scroller's own box on the screen now, global; null while it is not on it.
  final Rect? Function() box;

  /// How near its edges counts as at them: the note's is wider, since the finger is near the edge of the screen.
  final double zone;

  /// What covers its top (the note's header, `--wisp-under`): the zone starts below it.
  final double under;
}

/// Rolls a scroller while a carried thing is held near its edges (`edgeRoller`) - across for [Axis.horizontal], up
/// and down for [Axis.vertical] - so a thing can be taken past what it shows. Call [at] with each move; [stop] when
/// the thing is let go. `onRoll` runs each frame that moves it, for a gap to be placed again under a pointer that
/// is still.
class EdgeRoller {
  EdgeRoller(this.scroller, {this.onRoll, this.window});

  final CarryScroller scroller;
  final VoidCallback? onRoll;

  /// How tall the window is (`window.innerHeight`), for a scroller that runs past it; none, and its own box is all.
  final double Function()? window;

  int? _frame;
  double _lean = 0;

  /// How far a frame it is rolling now: 0 at rest.
  double get lean => _lean;

  void _roll(Duration _) {
    _frame = null;
    if (_lean == 0) return;
    final position = scroller.position;
    if (position.hasPixels && position.hasContentDimensions) {
      position.jumpTo((position.pixels + _lean).clamp(position.minScrollExtent, position.maxScrollExtent));
    }
    onRoll?.call();
    if (_lean != 0) _schedule();
  }

  void _schedule() => _frame = SchedulerBinding.instance.scheduleFrameCallback(_roll);

  /// The pointer is at `point`.
  void at(Offset point) {
    final box = scroller.box();
    final position = scroller.position;
    var next = 0.0;
    if (box != null && position.hasPixels && position.hasContentDimensions) {
      final across = scroller.axis == Axis.horizontal;
      // Only the one the pointer is over rolls: a lane beside the one held near its foot stays where it is.
      final over = across ? point.dy >= box.top && point.dy <= box.bottom : point.dx >= box.left && point.dx <= box.right;
      final pos = across ? point.dx : point.dy;
      final start = across ? box.left : math.max(box.top, 0.0) + scroller.under;
      final end = across ? box.right : math.min(box.bottom, window?.call() ?? box.bottom);
      final room = position.maxScrollExtent - position.minScrollExtent;
      final now = position.pixels - position.minScrollExtent;
      if (over && pos < start + scroller.zone && now > 0) {
        next = -rollStep;
      } else if (over && pos > end - scroller.zone && now < room - 1) {
        next = rollStep;
      }
    }
    if (next == _lean) return;
    _lean = next;
    final frame = _frame;
    if (frame != null) SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
    _frame = null;
    if (_lean != 0) _schedule();
  }

  void stop() {
    final frame = _frame;
    if (frame != null) SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
    _frame = null;
    _lean = 0;
  }
}

/// A place a carried thing may land (`Spot`): a lane and an index in it. A lane is a group of a board or a list (its
/// key), or '' for a list of one, and the index is where among its things it would go - or -1 in a lane whose order
/// is not the person's to set (a query's, sorted by its `sort:`), where only the lane counts.
@immutable
class Spot {
  const Spot(this.lane, this.index);

  final String lane;
  final int index;

  @override
  bool operator ==(Object other) => other is Spot && other.lane == lane && other.index == index;

  @override
  int get hashCode => Object.hash(lane, index);

  @override
  String toString() => 'Spot($lane, $index)';
}

/// `sameSpot`: both there, and the same lane and index.
bool sameSpot(Spot? a, Spot? b) => a != null && b != null && a == b;

/// What is in the air (`Carried`).
class Carried<T> {
  const Carried({required this.item, required this.from, required this.size});

  final T item;
  final Spot from;

  /// The thing's size, for the gap it leaves where it would land (the web kept its height alone).
  final Size size;

  double get height => size.height;
}

/// A thing carried in a list by the app's one drag (`useCarry`): a board's cards, a query's board cards and grouped
/// rows, a notebook's pages. It holds what is carried and where it would land, and tells its listeners when either
/// changes; the list draws the thing as the gap it leaves at that place, and the copy in the air is the gesture's.
class Carry<T> extends ChangeNotifier {
  Carry({required this.spotAt, required this.onDrop, this.scrollers, this.window, this.onLift, this.onPutDown});

  /// Where a thing held at a point would land; null where nothing would take it (it keeps the last place).
  Spot? Function(Offset at) spotAt;

  /// Let go somewhere else than it came from.
  void Function(T item, Spot from, Spot to) onDrop;

  /// What rolls along when the thing is held near its edges, asked on each move: a list may answer differently as
  /// the thing goes from lane to lane.
  List<CarryScroller> Function(Offset at)? scrollers;

  /// How tall the window is, for a scroller that runs past it.
  double Function()? window;

  /// The thing has just been lifted, or put down again (dropped or not).
  VoidCallback? onLift;
  VoidCallback? onPutDown;

  Carried<T>? _carried;
  Spot? _over;
  VoidCallback? _abandon;

  /// What is in the air, or null.
  Carried<T>? get carried => _carried;

  /// Where it would land now.
  Spot? get over => _over;

  /// The thing's pointer down, once it has decided the press is its own and not one of its controls'. `context` is
  /// the thing's own, read at the lift for its box; `ghost` builds the copy in the air, with corners of `radius`.
  void press(PointerDownEvent event, BuildContext context, T item, Spot from, {required WidgetBuilder ghost, BorderRadius radius = BorderRadius.zero}) {
    // One thing at a time, and never by a mouse's other buttons.
    if (_abandon != null) return;
    if (event.kind == PointerDeviceKind.mouse && event.buttons != kPrimaryMouseButton) return;
    Ghost? copy;
    final rollers = <ScrollPosition, EdgeRoller>{};
    var target = from;
    var at = event.position;
    var down = false;

    void place() {
      final spot = spotAt(at);
      if (spot != null && spot != target) {
        target = spot;
        _over = spot;
        notifyListeners();
      }
    }

    void roll() {
      final wanted = scrollers?.call(at) ?? const <CarryScroller>[];
      // A scroller no longer named stops; a new one starts.
      rollers.removeWhere((position, roller) {
        if (wanted.any((scroller) => identical(scroller.position, position))) return false;
        roller.stop();
        return true;
      });
      for (final scroller in wanted) {
        (rollers[scroller.position] ??= EdgeRoller(scroller, onRoll: place, window: window)).at(at);
      }
    }

    void putDown() {
      if (down) return;
      down = true;
      copy?.remove();
      copy = null;
      for (final roller in rollers.values) {
        roller.stop();
      }
      rollers.clear();
      _abandon = null;
      final was = _carried != null;
      _carried = null;
      _over = null;
      if (was) {
        onPutDown?.call();
        notifyListeners();
      }
    }

    final finish = holdDrag(
      event,
      HoldDragHooks(
        lift: (point) {
          if (!context.mounted) return;
          final box = context.findRenderObject();
          if (box is! RenderBox || !box.attached) return;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          copy = liftGhost(context, box: rect, at: point, builder: ghost, radius: radius);
          _carried = Carried<T>(item: item, from: from, size: rect.size);
          _over = from;
          onLift?.call();
          notifyListeners();
          at = point;
          place();
          roll();
        },
        move: (point) {
          if (_carried == null) return;
          at = point;
          copy?.follow(point);
          place();
          roll();
        },
        drop: (_) {
          if (_carried == null) return;
          final to = target;
          putDown();
          if (to != from) onDrop(item, from, to);
        },
        end: (lifted) {
          if (lifted) {
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

  /// Gives up a carry in flight, for a list taken off the page in the middle of one.
  void abandon() => _abandon?.call();

  @override
  void dispose() {
    final abandon = _abandon;
    _abandon = null;
    // Quietly: nobody is listening any more.
    onPutDown = null;
    abandon?.call();
    super.dispose();
  }
}
