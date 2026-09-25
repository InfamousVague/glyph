import { useEffect, type RefObject } from 'react';
import { readStored, writeStored } from '../core/stored.ts';
import { noteTitle, type Note } from '../core/store.ts';
import { sameTitle } from '../editor/wikiLinks.ts';
import { chaptersOf, isBookBody } from './book.ts';

/**
 * Where a book was left, so it opens there again (Matt: "When opening a book re open to the same spot it was last
 * opened"). A book is read in one of three places, and the spot is whichever it was last:
 *
 * - **its index**, the book note itself (book/BookView.tsx);
 * - **a chapter**, the chapter's own note, opened from the index, the chapter bar or the foot's Next. The note keeps
 *   its own place on the page (editor/notePlace.ts), so a book that goes back to the chapter goes back to the line;
 * - **reading straight through**, at a chapter and how far into it the page was scrolled.
 *
 * Opening the book from outside it - the home page's Library, the sidebar, the notes list, search, a `[[link]]` -
 * goes to that spot (`whereLeft`): a chapter opens in the book's place, and the read-through opens where it was. From
 * inside the book it does not: the chapter bar's book button, a tab, Back and Forward go to the index as they always
 * did, or there would be no way back to it from a chapter.
 *
 * A chapter is kept by its title, the way the book finds it, so a chapter moved in the index is still the spot; one
 * taken out of the book, or whose note is gone, is not, and the book opens at its index. Kept on the page under one
 * key, for the most recently read books only.
 */

export type BookSpot = { kind: 'index' } | { kind: 'chapter'; title: string } | { kind: 'reading'; title: string; offset: number };

const KEY = 'glyph-book-spots';
/** Books remembered; the least recently read are forgotten first. */
const KEEP = 100;
/** Scrolling settles for this long before the read-through's place is written. */
const SAVE_AFTER_MS = 400;
/** How long an opening read-through is waited on for its chapters to lay out before it is left where it is. */
const WAIT_MS = 2500;

type Spots = Record<string, BookSpot & { at: number }>;

/** A spot as it was read back: another build's shape, or a half-written store, is no spot. */
function spotFrom(value: unknown): BookSpot | null {
  if (!value || typeof value !== 'object') return null;
  const spot = value as Record<string, unknown>;
  if (spot.kind === 'index') return { kind: 'index' };
  if (spot.kind === 'chapter' && typeof spot.title === 'string') return { kind: 'chapter', title: spot.title };
  if (spot.kind === 'reading' && typeof spot.title === 'string' && Number.isFinite(spot.offset)) return { kind: 'reading', title: spot.title, offset: spot.offset as number };
  return null;
}

function readAll(): Spots {
  return readStored<Spots>(KEY, {}, (value) => (value && typeof value === 'object' && !Array.isArray(value) ? (value as Spots) : {}));
}

export function readBookSpot(bookId: string): BookSpot | null {
  return spotFrom(readAll()[bookId]);
}

export function writeBookSpot(bookId: string, spot: BookSpot, now = Date.now()): void {
  const all = readAll();
  all[bookId] = { ...spot, at: now };
  const kept = Object.entries(all)
    .filter(([, each]) => each && typeof each === 'object' && Number.isFinite(each.at))
    .sort((a, b) => b[1].at - a[1].at)
    .slice(0, KEEP);
  writeStored(KEY, Object.fromEntries(kept));
}

/**
 * The note to show for `note` opened from outside its book: the chapter the book was left in, while that chapter is
 * still in the book and still a note, and not already the note on screen (where opening the book is asking for its
 * index); otherwise `note` itself. Only a book is ever swapped.
 */
export function whereLeft(note: Note, notes: readonly Note[], showing: string | null): Note {
  if (!isBookBody(note.body)) return note;
  const spot = readBookSpot(note.id);
  if (spot?.kind !== 'chapter') return note;
  if (!chaptersOf(note.body).some((c) => sameTitle(c.title, spot.title))) return note;
  const chapter = notes.find((n) => n.id !== note.id && !n.archivedAt && sameTitle(noteTitle(n.body), spot.title));
  return chapter && chapter.id !== showing ? chapter : note;
}

/** The read-through's sections, one per chapter in the index's order (book/BookView.tsx). */
function sectionsIn(root: HTMLElement): HTMLElement[] {
  return [...root.querySelectorAll<HTMLElement>(':scope > section')];
}

/**
 * Where the read-through is scrolled to: the chapter at the top of the page and how far into it, in pixels. Above the
 * first chapter (the bar of chapters, or the very top) it is the first chapter, at its start.
 */
export function readingPlaceOf(root: HTMLElement, page: HTMLElement, titles: readonly string[]): BookSpot | null {
  const top = page.getBoundingClientRect().top;
  const sections = sectionsIn(root);
  let at = -1;
  for (let i = 0; i < sections.length; i += 1) {
    if (sections[i]!.getBoundingClientRect().top <= top + 1) at = i;
    else break;
  }
  const index = Math.max(0, at);
  const title = titles[index];
  if (title === undefined) return null;
  const offset = at < 0 ? 0 : Math.max(0, Math.round(top - sections[index]!.getBoundingClientRect().top));
  return { kind: 'reading', title, offset };
}

/** Scrolls the page so the read-through is back at `spot`'s chapter, `offset` into it; false while that chapter is not drawn. */
export function scrollToReading(root: HTMLElement, page: HTMLElement, titles: readonly string[], spot: { title: string; offset: number }): boolean {
  const index = titles.findIndex((t) => sameTitle(t, spot.title));
  const section = sectionsIn(root)[index];
  if (!section) return false;
  page.scrollTop += section.getBoundingClientRect().top - page.getBoundingClientRect().top + spot.offset;
  return true;
}

/**
 * Keeps the book's spot while its view is open: the index while the index is shown, and the read-through's place as
 * it is scrolled, written as scrolling settles, when the app is hidden and when the view closes. A read-through the
 * book was left in is scrolled back to its place once, when `restore` is given: the chapters' words lay out a moment
 * after the view (lines never drawn only have estimated heights), so the page is scrolled back once the chapter is
 * there and again shortly after, unless the person scrolls first.
 */
export function useBookSpot(
  bookId: string | null,
  reading: boolean,
  root: RefObject<HTMLElement | null>,
  page: RefObject<HTMLElement | null> | undefined,
  titles: readonly string[],
  restore: { title: string; offset: number } | null,
): void {
  const titleKey = titles.join('\n');
  useEffect(() => {
    if (!bookId) return undefined;
    if (!reading) {
      writeBookSpot(bookId, { kind: 'index' });
      return undefined;
    }
    const scroller = page?.current;
    const view = root.current;
    if (!scroller || !view) return undefined;
    const names = titleKey ? titleKey.split('\n') : [];
    let latest: BookSpot | null = restore ? { kind: 'reading', ...restore } : readingPlaceOf(view, scroller, names);
    // Settled: restored, given up on, or scrolled by the person. Only then is the place theirs to write.
    let settled = !restore;
    let frame = 0;
    let again = 0;
    const started = performance.now();
    const wait = () => {
      if (settled || !restore) return;
      const ready = scroller.scrollHeight > scroller.clientHeight && scrollToReading(view, scroller, names, restore);
      if (ready) {
        again = window.setTimeout(() => {
          scrollToReading(view, scroller, names, restore);
          settled = true;
        }, 150);
        return;
      }
      if (performance.now() - started > WAIT_MS) settled = true;
      else frame = requestAnimationFrame(wait);
    };
    if (restore) frame = requestAnimationFrame(wait);
    const save = () => {
      if (settled && latest) writeBookSpot(bookId, latest);
    };
    const onTouch = () => {
      if (settled) return;
      cancelAnimationFrame(frame);
      window.clearTimeout(again);
      settled = true;
    };
    let saving = 0;
    const onScroll = () => {
      if (settled && scroller.isConnected) latest = readingPlaceOf(view, scroller, names) ?? latest;
      window.clearTimeout(saving);
      saving = window.setTimeout(save, SAVE_AFTER_MS);
    };
    const onHide = () => {
      if (document.visibilityState === 'hidden') save();
    };
    // The read-through is the spot as soon as it is shown, before any scroll.
    save();
    scroller.addEventListener('scroll', onScroll, { passive: true });
    scroller.addEventListener('pointerdown', onTouch, { passive: true });
    scroller.addEventListener('wheel', onTouch, { passive: true });
    scroller.addEventListener('touchstart', onTouch, { passive: true });
    document.addEventListener('visibilitychange', onHide);
    return () => {
      cancelAnimationFrame(frame);
      window.clearTimeout(again);
      window.clearTimeout(saving);
      scroller.removeEventListener('scroll', onScroll);
      scroller.removeEventListener('pointerdown', onTouch);
      scroller.removeEventListener('wheel', onTouch);
      scroller.removeEventListener('touchstart', onTouch);
      document.removeEventListener('visibilitychange', onHide);
      save();
    };
    // `restore` is read once, as the view opens: it is where the book was left, not where it is now.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [bookId, reading, root, page, titleKey]);
}
