import { useEffect, type RefObject } from 'react';
import type { EditorView } from '@codemirror/view';
import { itemAt } from '../core/boards.ts';
import { wordsEnd } from '../core/itemSyntax.ts';
import { scrollToPlace } from './notePlace.ts';

/**
 * Landing on an item: a note opened by a link that pointed inside it (`[[Launch week#^ask-sam]]`) puts the caret on
 * that item and scrolls the page to it, rather than going back to where the note was left last time
 * (editor/notePlace.ts steps aside while there is an `at`).
 *
 * Two stages. The caret goes to the end of the item's words, before its mark and its anchor, so what is typed next
 * goes on the words. The page scrolls so the line sits LAND_ROOM under the header, which floats over the page rather
 * than pushing it down. The first scroll works from the editor's own idea of where the line is, which is a guess for
 * lines it has not drawn - a board counts for a lot of page - so once the line is really on screen its own top is
 * measured and the last of it taken off, a few times at growing intervals, and a note with a board lands on the line
 * and not a screen past it.
 *
 * The note's words can arrive a moment after its editor does (live sync replaces the document), so the item is looked
 * for again every 100 ms, up to TRIES times, before the note is left where it opened.
 */

/** How far below the header a note opened at an item sits, so the line is not against it. */
const LAND_ROOM = 12;
/** How many more looks for an item that is not in the note yet, 100 ms apart. */
const TRIES = 24;
/** How many times the landing is measured and made, the first included. */
const LANDINGS = 4;

/** Lands on `at` (`^anchor` or `anchor`) in `view`, scrolling `page` to put it under `header`. Nothing without one. */
export function useLandAt(at: string | undefined, view: EditorView | null, page: RefObject<HTMLElement | null>, header: RefObject<HTMLElement | null>): void {
  useEffect(() => {
    const anchor = at?.replace(/^\^/, '');
    if (!anchor || !view) return undefined;
    const timers: number[] = [];
    let tries = 0;
    let landed = 0;
    const land = () => {
      const item = itemAt(view.state.doc.toString(), anchor);
      const scroller = page.current;
      if (item && scroller) {
        const line = view.state.doc.line(Math.min(item.line, view.state.doc.lines));
        if (!landed) view.dispatch({ selection: { anchor: line.from + wordsEnd(line.text) } });
        const seen = view.coordsAtPos(line.from);
        const room = (header.current?.getBoundingClientRect().bottom ?? scroller.getBoundingClientRect().top) + LAND_ROOM;
        if (seen) scroller.scrollTop += seen.top - room;
        else scrollToPlace(view, scroller, { pos: line.from, offset: 0 });
        landed += 1;
        if (landed < LANDINGS) timers.push(window.setTimeout(land, landed * 150));
        return;
      }
      if (tries < TRIES) {
        tries += 1;
        timers.push(window.setTimeout(land, 100));
      }
    };
    timers.push(window.setTimeout(land, 0));
    return () => timers.forEach((timer) => window.clearTimeout(timer));
  }, [at, view, page, header]);
}
