/**
 * How long a finger rests before a press lifts what is under it rather than scrolling or panning past it: a board's
 * card (editor/boards/drag.ts), a canvas's card (canvas/gestures.ts), a tab (notes/useTabDrag.ts) and a book's page
 * row (book/rowDrag.ts). One wait, so a lift feels the same wherever it is.
 */

export const HOLD_MS = 220;
