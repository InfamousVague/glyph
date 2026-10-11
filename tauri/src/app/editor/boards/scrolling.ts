/**
 * The note's own scroller, and how near its edges a card counts as at them. A held card rolls the note along when it
 * nears the top or the foot (drag.ts), and a card that has just landed is scrolled clear of that same edge
 * (navigate.ts), so the two agree on where the edge is.
 */

/** How near an edge counts as at it, in px: a held card there rolls what it is in along; a landed one is kept clear. */
export const EDGE = 44;

/** The note's own scroller: the nearest box above the board that scrolls up and down. */
export function noteScroller(board: HTMLElement): HTMLElement | null {
  for (let at = board.parentElement; at; at = at.parentElement) {
    const flow = window.getComputedStyle(at).overflowY;
    if ((flow === 'auto' || flow === 'scroll') && at.scrollHeight > at.clientHeight + 1) return at;
  }
  const page = document.scrollingElement;
  return page instanceof HTMLElement && page.scrollHeight > page.clientHeight + 1 ? page : null;
}
