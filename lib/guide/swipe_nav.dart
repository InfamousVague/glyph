/// A quick sideways drag across a surface steps back or forward: right is back, left is forward. A port of
/// `useSwipeNav` from `src/app/core/swipe.ts`, for the walkthrough, the one surface ported so far that uses it.
///
/// A drag counts when it travelled at least [swipeMinDistance] sideways, at least twice as far sideways as up or
/// down, and took no longer than [swipeMaxMs]. A swipe back tells the back stack it has stepped, so the phone's own
/// back gesture a moment later is the same swipe and not a second step (lib/core/back.dart `markSteppedBack`).
///
/// What differs: the page listened on an element and left alone a drag that began on something that moves sideways
/// itself (an input, a slider, the kit's segmented control, `data-noswipe`). Here the pointer is only watched, never
/// claimed, and the walkthrough has none of those, so there is no list of them. It belongs in lib/core beside the
/// other swipes once another screen needs it.
library;

import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/widgets.dart';

import '../core/back.dart';

/// `MIN_DISTANCE`.
const double swipeMinDistance = 64;

/// `MAX_MS`.
const int swipeMaxMs = 1500;

class SwipeNav extends StatefulWidget {
  const SwipeNav({super.key, this.onBack, this.onForward, required this.child});

  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final Widget child;

  @override
  State<SwipeNav> createState() => _SwipeNavState();
}

class _SwipeNavState extends State<SwipeNav> {
  int? _pointer;
  Offset _from = Offset.zero;
  Duration _at = Duration.zero;

  void _down(PointerDownEvent event) {
    if (_pointer != null || event.buttons & ~kPrimaryButton != 0) return;
    _pointer = event.pointer;
    _from = event.position;
    _at = event.timeStamp;
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final moved = event.position - _from;
    final took = (event.timeStamp - _at).inMilliseconds;
    if (took > swipeMaxMs || moved.dx.abs() < swipeMinDistance || moved.dx.abs() < moved.dy.abs() * 2) return;
    if (moved.dx > 0) {
      // Android offers the same thumb-swipe as its own back gesture a moment later: one swipe, one step.
      BackScope.of(context).markSteppedBack();
      widget.onBack?.call();
    } else {
      widget.onForward?.call();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerUp: _up,
    onPointerCancel: (event) {
      if (event.pointer == _pointer) _pointer = null;
    },
    child: widget.child,
  );
}
