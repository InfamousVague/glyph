import type { WheelEvent } from 'react';

/**
 * A row that scrolls sideways, spoken to by a mouse (Matt: "I should be able to scroll left or right on the tabs",
 * then "we can't scroll side to side on the workspace pills in the sidebar").
 *
 * A trackpad sends a sideways gesture as `deltaX` and the row scrolls by itself; a finger pans it natively. A mouse
 * wheel only ever sends `deltaY`, so over a row that can only move sideways, nothing happened at all - measured on the
 * pills with a listener: the wheel reached the row as dy 300, dx 0, and scrollLeft stayed at 0. Over such a row a
 * vertical turn of the wheel can only mean sideways, so that is what it does.
 *
 * Only the vertical turn. A sideways swipe is left to the row, which is already scrolling by it: this used to add the
 * swipe's `deltaX` as well, so a trackpad moved the tabs twice as far as the fingers did, once by the browser and once
 * from here, and the two fought through the swipe's glide (Matt: "scrolling on the tabs is glitchy on desktop").
 *
 * A row that fits leaves the wheel alone, so the page under it still scrolls when there is nowhere sideways to go.
 * Used by the tab row (notes/NoteTabs.tsx) and the workspace pills (notes/WorkspaceBar.tsx): one rule, not two copies
 * of it.
 */
export function scrollSideways(event: WheelEvent<HTMLElement>): void {
  const row = event.currentTarget;
  if (row.scrollWidth <= row.clientWidth) return;
  if (Math.abs(event.deltaX) >= Math.abs(event.deltaY)) return;
  row.scrollLeft += event.deltaY;
}
