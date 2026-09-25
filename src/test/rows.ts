import { act } from 'react';

/**
 * Rows laid out and dragged by their grip, for the tests of what book/rowDrag.ts drives: the drag itself
 * (rowDrag.test.tsx), a book's index (BookView.test.tsx) and the New book sheet (NewBookSheet.test.tsx). jsdom lays
 * nothing out, so the rows are given a place on the page of their own.
 */

/** Each row `height` pixels tall, one under another from the top of the page. */
export function layRowsOut(rows: Iterable<Element>, height = 40, width = 300): void {
  [...rows].forEach((row, i) => {
    row.getBoundingClientRect = () => ({ top: i * height, bottom: (i + 1) * height, height, left: 0, right: width, width, x: 0, y: i * height, toJSON: () => ({}) }) as DOMRect;
  });
}

/** A pointer event on a grip at this height on the page: a mouse's, unless said, which lifts a row at once. */
export function onGrip(grip: Element, type: string, clientY: number, pointerType = 'mouse'): void {
  act(() => {
    grip.dispatchEvent(Object.assign(new MouseEvent(type, { bubbles: true, clientY, button: 0 }), { pointerId: 1, pointerType }));
  });
}

/** A grip pressed at `from` with a mouse, moved to `to` and let go there. */
export function dragGrip(grip: Element, from: number, to: number): void {
  onGrip(grip, 'pointerdown', from);
  onGrip(grip, 'pointermove', to);
  onGrip(grip, 'pointerup', to);
}
