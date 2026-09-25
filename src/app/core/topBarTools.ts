import { externalStore } from './externalStore.ts';

/**
 * Where a screen's own controls go when the app's top bar is there to hold them.
 *
 * Matt: "Move the controls for the note into the topbar and put the tabs on the next line down". The note's tools -
 * the view toggle, the bookmark, the mic, the three dots - belong to the note screen and hold the editor's state, so
 * lifting them into App.tsx would drag the editor up with them. Instead the bar offers a slot, the screen keeps
 * owning its buttons, and React puts them in the bar's DOM with a portal.
 *
 * One slot, because there is one bar. The bar sets it while it is on screen (notes/NoteTabs.tsx) and clears it as it
 * goes; a screen asks for it and falls back to drawing its controls where it always did, so a route with no bar - or
 * a moment before the bar has mounted - still works.
 */

const slot = externalStore<HTMLElement | null>(null, {
  // On a server, and on the first paint, there is no bar yet: the screen draws its own.
  server: () => null,
});

/** The bar, saying where its slot is - or that it has gone. */
export const setTopBarTools = slot.set;

/** The slot to draw a screen's controls into, or null to draw them where they are. */
export const useTopBarTools = slot.use;
