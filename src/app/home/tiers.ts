/**
 * How the home page is laid out, by the width of its own column (Matt: "Extend the dashboard to support wide phone /
 * tablet layouts too", and then: "It's okay if they're two across or the layout changes slightly on wide the four
 * column was a suggestion not a rule"). Three tiers, and the lines between them in rem:
 *
 * - the stack, under 44rem: the phone's one column, exactly as it shipped (docs/DESIGN.md §132);
 * - wide, from 44rem: two of those columns across, the gap between them on the Fold's hinge when it is opened out,
 *   the tapes a grid on the two columns' halves from 50rem;
 * - desk, from 60rem: a main two cards across beside a rail that holds To do.
 *
 * The page's width and never the window's. The page is the window less a docked sidebar (app.css `.app-split`), so a
 * 1280px window with the sidebar docked has a 900px page, and a query on the window would lay that out as a desk with
 * two cards of three hundred and a rail of two. The one thing on the screen that reads the window is the dock (§92).
 * HomeScreen.module.css and TapeShelf.module.css ask the same question with container queries on the page's column
 * (`home-page`); this is the page's code asking it (home/useColumnTier.ts), for the counts that are not CSS's to set.
 * The lines are in rem because the queries' are: Settings' interface size sets the root's size (core/preferences.ts
 * `uiScale`), a container query reads that rem, and so does `tierOf`.
 */

export type Tier = 'stack' | 'wide' | 'desk';

/** The page's lines in rem: the container queries' own numbers in HomeScreen.module.css and TapeShelf.module.css (home/tiers.test.ts holds them to these). */
export const LINES = { wide: 44, tapesGrid: 50, desk: 60 } as const;

/** Which tier a column of `columnPx` is in; `remPx` is the root's rem, which the container queries read too (Settings' interface size moves it). */
export function tierOf(columnPx: number, remPx: number): Tier {
  if (columnPx >= LINES.desk * remPx) return 'desk';
  return columnPx >= LINES.wide * remPx ? 'wide' : 'stack';
}

/**
 * How many the page holds in each tier: the notes touched last, and the to-dos the card shows before "Show all".
 *
 * The phone's four and five in the stack and on the two columns, where Recent is two rows of two. On a desk the main
 * is two cards across, so six is three whole rows (and two rows of three with no rail, when there is no To do at all);
 * the rail beside it is tall, so To do shows eight before its Show all. The shelf is not here: it holds eight
 * everywhere (HomeScreen.tsx `SHELF`), so the same library shows the same tapes on every screen and the biggest screen
 * never shows fewer than the cover screen.
 */
export const CAPS: Record<Tier, { recent: number; tasks: number }> = {
  stack: { recent: 4, tasks: 5 },
  wide: { recent: 4, tasks: 5 },
  desk: { recent: 6, tasks: 8 },
};
