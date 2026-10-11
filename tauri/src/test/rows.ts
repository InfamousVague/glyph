import { act } from 'react';
import { vi } from 'vitest';
import { ROW_HOLD_MS } from '../app/book/rowDrag.ts';

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

/** A pointer event on a grip at this height on the page: a mouse's, unless said. */
export function onGrip(grip: Element, type: string, clientY: number, pointerType = 'mouse'): void {
  act(() => {
    grip.dispatchEvent(Object.assign(new MouseEvent(type, { bubbles: true, clientY, button: 0 }), { pointerId: 1, pointerType }));
  });
}

/** A grip pressed and held while the row lifts (core/holdDrag.ts), on a fake clock of its own unless one is running. */
export function holdGrip(grip: Element, at: number, pointerType = 'mouse'): void {
  const own = !vi.isFakeTimers();
  if (own) vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  onGrip(grip, 'pointerdown', at, pointerType);
  act(() => {
    vi.advanceTimersByTime(ROW_HOLD_MS + 10);
  });
  if (own) vi.useRealTimers();
}

/** A grip pressed and held at `from` with a mouse, moved to `to` and let go there. */
export function dragGrip(grip: Element, from: number, to: number): void {
  holdGrip(grip, from);
  onGrip(grip, 'pointermove', to);
  onGrip(grip, 'pointerup', to);
}
