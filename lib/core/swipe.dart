/// The pure half of a swipeable row: which action a distance arms, and where a touch may start a swipe at all. A port
/// of `src/app/notes/swipe.ts` (docs/DESIGN.md §151): right to pin a note or unpin it; left to archive it, and
/// further left, past a second detent, to delete it instead. Nothing differs.
library;

import 'package:flutter/foundation.dart';

import 'note.dart';

/// How an armed action fills the gap behind its row (`SwipeTone`).
enum SwipeTone { accent, neutral, danger }

/// The picture behind the row (`SwipeAction['icon']`).
enum SwipeIcon { pin, unpin, archive, delete }

/// One thing a swipe can do (`SwipeAction`).
@immutable
class SwipeAction {
  const SwipeAction({required this.id, required this.label, required this.icon, required this.tone, required this.detent, this.removes = false});

  final String id;

  /// The word shown behind the row, and the action's name for assistive tech.
  final String label;
  final SwipeIcon icon;
  final SwipeTone tone;

  /// Fraction of the row's width at which this action arms.
  final double detent;

  /// Slide the row away before acting: for actions that take it out of this list.
  final bool removes;
}

/// What a note's swipe does, by the id the row hands back (`NoteSwipe`).
enum NoteSwipe { pin, archive, delete }

/// A note's swipes: right to pin it, or unpin it; left to archive it, and further left to delete it instead.
({List<SwipeAction> start, List<SwipeAction> end}) noteSwipes(Note note) => (
      start: [
        SwipeAction(id: 'pin', label: note.starred ? 'Unpin' : 'Pin', icon: note.starred ? SwipeIcon.unpin : SwipeIcon.pin, tone: SwipeTone.accent, detent: 0.22),
      ],
      end: const [
        SwipeAction(id: 'archive', label: 'Archive', icon: SwipeIcon.archive, tone: SwipeTone.neutral, detent: 0.22, removes: true),
        SwipeAction(id: 'delete', label: 'Delete', icon: SwipeIcon.delete, tone: SwipeTone.danger, detent: 0.55, removes: true),
      ],
    );

/// The swipe an id names, or null for any other (`isNoteSwipe`, as a reader).
NoteSwipe? noteSwipeOf(String id) => switch (id) { 'pin' => NoteSwipe.pin, 'archive' => NoteSwipe.archive, 'delete' => NoteSwipe.delete, _ => null };

bool isNoteSwipe(String id) => noteSwipeOf(id) != null;

/// The furthest action armed at [distance] (a fraction of the width, always positive), or null.
SwipeAction? armedAt(List<SwipeAction> actions, double distance) {
  SwipeAction? armed;
  for (final action in actions) {
    if (distance >= action.detent) armed = action;
  }
  return armed;
}

/// Android's back gesture owns a band at each edge of the screen; a touch that begins inside it is left to the
/// system (`EDGE_PX`).
const double swipeEdgePx = 28;

bool startsInGestureEdge(double clientX, double viewportWidth) => clientX < swipeEdgePx || clientX > viewportWidth - swipeEdgePx;

/// The row's offset for a finger [moveX] px from where it started. It follows the finger to a little past the last
/// detent, then only a quarter as fast: a rubber band that says "nothing further this way" without a hard stop.
double followFinger(double moveX, double lastDetent, double width) {
  final limit = (lastDetent + 0.18) * width;
  final over = moveX.abs() - limit;
  return over > 0 ? moveX.sign * (limit + over * 0.25) : moveX;
}
