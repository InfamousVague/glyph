import { useCallback, useEffect, useState, type RefObject } from 'react';
import type { EditorView } from '@codemirror/view';
import { fireNativeHaptic } from '../core/haptics.ts';
import { bookmarkLineIn, markedLine, markedWords, placeBookmark, showBookmark } from './bookmarkLine.ts';
import { caretPlace, placeOf, readBookmark, writeBookmark } from './notePlace.ts';

/**
 * The note's bookmark button, in its tools (editor/NoteTools.tsx): the bookmark is written in the note as `§§`
 * (editor/bookmarkLine.ts), and pressed, it goes on the line being read or written, moving from wherever it was;
 * pressed on the line that already has it, it comes off (Matt: "i should be able to tap bookmark again to update the
 * position as well right now its stuck"). The note opens at it (editor/notePlace.ts).
 *
 * "The line being read" is the caret's own line first and the top of the page second: a bookmark marks the words
 * being read, not the top of the page, and the other order is the bug Matt reported, a bookmark stuck at the top while
 * reading lower down.
 *
 * A bookmark kept on this device from before bookmarks were written in (notePlace.ts `readBookmark`) is ribboned while
 * it lasts and goes on the first press: the note carries its own from then on. The ribbon waits for the line it
 * belongs on, because the note's words can arrive a moment after its editor does (live sync replaces the document).
 */

/** How long the ribbon waits for a document long enough to hold the kept place, before it is drawn wherever it lands. */
const RIBBON_WAIT_MS = 2500;

export interface Bookmarking {
  /** Whether the note has a bookmark, in its words or kept on this device: the button is lit. */
  marked: boolean;
  /** The button's press. */
  bookmark: () => void;
}

/** The bookmark of `note` in `view`, whose page scrolls in `page`; `say` tells the person what the press did. */
export function useBookmark(note: { id: string; body: string }, view: EditorView | null, page: RefObject<HTMLElement | null>, say: (message: string) => void): Bookmarking {
  const [marked, setMarked] = useState(() => bookmarkLineIn(note.body) !== null || readBookmark(note.id) !== null);
  useEffect(() => setMarked(bookmarkLineIn(note.body) !== null || readBookmark(note.id) !== null), [note.id, note.body]);

  /** The bookmarked line, ribboned in the note so the place can be seen (editor/bookmarkLine.ts). */
  const showMark = useCallback(
    (at: number | null) => {
      view?.dispatch({ effects: showBookmark.of(at) });
    },
    [view],
  );
  useEffect(() => {
    if (!view) return undefined;
    const at = readBookmark(note.id)?.pos ?? null;
    if (at === null || view.state.doc.length >= at) {
      showMark(at);
      return undefined;
    }
    let frame = 0;
    const started = performance.now();
    const wait = () => {
      if (view.state.doc.length >= at || performance.now() - started > RIBBON_WAIT_MS) showMark(at);
      else frame = requestAnimationFrame(wait);
    };
    frame = requestAnimationFrame(wait);
    return () => cancelAnimationFrame(frame);
  }, [note.id, view, showMark]);

  const bookmark = () => {
    const scroller = page.current;
    if (!view || !scroller) return;
    const here = caretPlace(view, scroller) ?? placeOf(view, scroller);
    const current = bookmarkLineIn(view.state.doc);
    const kept = readBookmark(note.id);
    const target = here ? markedLine(view.state, here.pos) : view.state.doc.length ? 1 : null;
    const was = current ?? (kept ? markedLine(view.state, kept.pos) : null);
    if (kept) writeBookmark(note.id, null);
    if (target === null) {
      say('Write something first, then bookmark the line.');
      return;
    }
    if (was === target) {
      view.dispatch(placeBookmark(view.state, null));
      showMark(null);
      setMarked(false);
      fireNativeHaptic('warning');
      say('Bookmark taken off.');
      return;
    }
    view.dispatch(placeBookmark(view.state, target));
    showMark(null);
    setMarked(true);
    fireNativeHaptic('success');
    // The words it landed on are said back, so the place is known without scrolling to it.
    const words = markedWords(view, view.state.doc.line(target).from);
    const said = was === null ? 'Bookmarked at' : 'Bookmark moved to';
    say(words ? `${said} “${words}”. This note opens here.` : `${said} this line. This note opens here.`);
  };

  return { marked, bookmark };
}
