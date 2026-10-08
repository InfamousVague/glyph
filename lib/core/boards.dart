/// Boards in markdown: the whole syntax, read and written in this room and nowhere else (docs/BOARDS.md). The fence is
/// known here; the item line it points at is spelled once, in item_syntax.dart, and read here with it. A port of
/// `src/app/core/boards.ts`, the room's door.
///
/// Matt: "define and create a markdown standard we use to create kanban boards and task management boards entirely
/// within markdown, linking the tasks in the board to a task on the page", and later "come up with a generic way to
/// link list items to the board". Two pieces of ordinary markdown, and one of them is the link:
///
///     - [ ] Ship the pricing page ^ship-page      any list item may end with an anchor: the block id other tools
///     - Ask Sam about the copy ^ask-sam           write the same way. A bullet, a number or a to-do, all the same.
///
///     ```board                                     a fence whose lines are the columns, each naming anchors
///     To do: ship-page, ask-sam
///     Done: pick-date
///     ```
///
/// The anchor is the generic part. It names an item, and anything that wants that item points at the anchor: the
/// board fence is only the first thing to do it, and `[[#^ask-sam]]` in any line is the same pointer written in
/// prose. Nothing is stored beside the note, so a board is readable as words wherever the note is opened, and the app
/// draws the columns with the items as cards. A card IS its item: the same tick box, the same words, and tapping it
/// goes to the line.
///
/// This file is the room's door, and every caller imports from it. The work is in core/boards/, one job to a module,
/// each pure and each with its own tests:
///
///     items.dart     the items a board points at: anchors, words, boxes, and `[[#^id]]` in prose
///     fence.dart     the ```board fence read and written, its height, and where each board is
///     columns.dart   columns as data: cards moved, dropped, taken off, drawn in Done, paired with their items
///     settle.dart    a tick carried to every fence, so the markdown agrees with the boxes
///     make.dart      boards and cards made from a note's own lists
///     lanes.dart     lanes found by name and filled, for "add … to Doing" said on a board's own Speak
///
/// Every transform answers new text or new columns and never changes what it was given.
///
/// What differs: the constants are lowerCamel: `BOARD_HEIGHT` is `boardHeight` and `NEW_COLUMNS` is `newColumns`.
/// `fencedLines` stays behind the door, as on the web, where only make.ts reads it. lanes.dart writes out the
/// recorder's `similarity` itself until `capture/route.ts` is ported (see there).
library;

export 'boards/columns.dart'
    show Card, cardsOf, columnFor, columnOf, doneColumn, moveCard, nearAnchor, putCard, putCardAt, settleColumns, withoutCard;
export 'boards/fence.dart'
    show Board, BoardColumn, boardAt, boardCopy, boardHeight, boardsIn, clampHeight, readBoard, withBoardHeight, writeBoard;
export 'boards/items.dart'
    show Item, ItemRef, anchorFor, cardText, isItemLine, itemAt, itemOnLine, itemWords, itemsIn, refFor, refsIn, setItemDone, withAnchor;
export 'boards/lanes.dart' show Lane, addToLane, lanesOf, matchLane, moveToLane;
export 'boards/make.dart' show BoardMade, CardAdded, CardMade, ListBoard, addToBoard, boardFrom, boardFromList, listAround, newCard, newColumns;
export 'boards/settle.dart' show FenceEdit, SettledTicks, settleBoards, settleTicks;
