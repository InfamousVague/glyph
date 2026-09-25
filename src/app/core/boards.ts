/**
 * Boards in markdown: the whole syntax, read and written in this room and nowhere else (docs/BOARDS.md). The fence is
 * known here; the item line it points at is spelled once, in core/itemSyntax.ts, and read here with it.
 *
 * Matt: "define and create a markdown standard we use to create kanban boards and task management boards entirely
 * within markdown, linking the tasks in the board to a task on the page", and later "come up with a generic way to
 * link list items to the board". Two pieces of ordinary markdown, and one of them is the link:
 *
 *   - [ ] Ship the pricing page ^ship-page      any list item may end with an anchor: the block id other tools write
 *   - Ask Sam about the copy ^ask-sam           the same way. A bullet, a number or a to-do, all the same.
 *
 *   ```board                                     a fence whose lines are the columns, each naming anchors
 *   To do: ship-page, ask-sam
 *   Done: pick-date
 *   ```
 *
 * The anchor is the generic part. It names an item, and anything that wants that item points at the anchor: the
 * board fence is only the first thing to do it, and `[[#^ask-sam]]` in any line is the same pointer written in
 * prose. Nothing is stored beside the note, so a board is readable as words wherever the note is opened, and Glyph
 * draws the columns with the items as cards (editor/boards.ts). A card IS its item: the same tick box, the same
 * words, and tapping it goes to the line.
 *
 * This file is the room's door, and every caller imports from it. The work is in core/boards/, one job to a module,
 * each pure and each with its own tests:
 *
 *   items.ts     the items a board points at: anchors, words, boxes, and `[[#^id]]` in prose
 *   fence.ts     the ```board fence read and written, its height, and where each board is
 *   columns.ts   columns as data: cards moved, dropped, taken off, drawn in Done, paired with their items
 *   settle.ts    a tick carried to every fence, so the markdown agrees with the boxes
 *   make.ts      boards and cards made from a note's own lists
 *   lanes.ts     lanes found and filled by voice
 *
 * Every transform answers new text or new columns and never changes what it was given.
 */

export {
  anchorFor,
  cardText,
  isItemLine,
  itemAt,
  itemOnLine,
  itemWords,
  itemsIn,
  refFor,
  refsIn,
  setItemDone,
  withAnchor,
  type Item,
  type ItemRef,
} from './boards/items.ts';
export {
  BOARD_HEIGHT,
  boardAt,
  boardCopy,
  boardsIn,
  clampHeight,
  readBoard,
  withBoardHeight,
  writeBoard,
  type Board,
  type BoardColumn,
} from './boards/fence.ts';
export {
  cardsOf,
  columnFor,
  columnOf,
  doneColumn,
  moveCard,
  nearAnchor,
  putCard,
  putCardAt,
  settleColumns,
  withoutCard,
  type Card,
} from './boards/columns.ts';
export { settleBoards, settleTicks, type FenceEdit, type SettledTicks } from './boards/settle.ts';
export {
  NEW_COLUMNS,
  addToBoard,
  boardFrom,
  boardFromList,
  listAround,
  newCard,
  type BoardMade,
  type CardAdded,
  type CardMade,
  type ListBoard,
} from './boards/make.ts';
export { addToLane, lanesOf, matchLane, moveToLane, type Lane } from './boards/lanes.ts';
