/// Getting around from a board: a card's words take the caret to its item's line in the note, a card that has just
/// moved is shown where it landed, and for a moment after a card's status changes a press on its words is not taken
/// as "go to the line". Ports `src/app/editor/boards/navigate.ts` and `boards/scrolling.ts`.
///
/// What differs:
/// - `goToLine` was ported with the anchors (items/anchors.dart), which needed it first; it is handed on from here
///   under its own file's name.
/// - `reveal` looked the card up in the page two frames after the change and scrolled what it found. Here the card
///   to show is named to the board's own widget ([revealed]), which finds it once it has drawn the change and does
///   the scrolling itself (board_box.dart): the lane brought across the board, the card brought into its lane, the
///   note moved only as far as it takes, and the flash.
/// - `noteScroller` walked up the DOM for the nearest box that scrolls up and down; here it is the nearest vertical
///   `Scrollable` above the board.
library;

import 'package:flutter/widgets.dart';

import '../view/plugin.dart';

export '../items/anchors.dart' show goToLine;

/// How near an edge counts as at it, in px: a held card there rolls what it is in along; a landed one is kept clear
/// (`EDGE`).
const double boardEdge = 44;

/// How long a press on a card's words is not "go to the line" after a status changed (`QUIET_MS`).
const Duration quietTime = Duration(milliseconds: 700);

/// How long a card that has just arrived stays lit.
const Duration arrivedTime = Duration(milliseconds: 900);

DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);

/// The clock the hush is read by; a test sets its own.
DateTime Function() boardClock = DateTime.now;

/// A status changed on the board - a card ticked, or dropped in another lane - keeps the person on the board (Matt:
/// "when changing the status of a ticket to done it jumps me way down to the item in the list instead of moving me
/// to view the task on the board"). For a moment after one, a press on a card's words is not taken as "go to the
/// line": on a phone the tick box sits beside the words, and a finger a little off, or the tap a drop leaves
/// behind, landed on them and scrolled the note away.
void hushGoTo() => _quietUntil = boardClock().add(quietTime);

/// Whether a status has just changed on a board, so a press on a card's words is a near miss and not "go to the
/// line".
bool hushed() => boardClock().isBefore(_quietUntil);

final Expando<ValueNotifier<String?>> _revealed = Expando<ValueNotifier<String?>>('boardReveal');

/// The card `view`'s boards have been asked to show where it landed, by its anchor; a board that draws it shows it
/// and sets this back to null.
ValueNotifier<String?> revealed(EditorViewLike view) => _revealed[view] ??= ValueNotifier<String?>(null);

/// The card where it landed, shown (`reveal`): asked for here, done by the board once it has drawn the change.
void reveal(EditorViewLike view, String id) => revealed(view).value = id;

/// The note's own scroller: the nearest box above the board that scrolls up and down (`noteScroller`).
ScrollableState? noteScroller(BuildContext board) => Scrollable.maybeOf(board, axis: Axis.vertical);
