import { useCallback, useEffect, useRef, useState } from 'react';
import { withFrontMatterTitle } from '../core/frontMatter.ts';
import { noteTitle, updateNote, type Note } from '../core/store.ts';

/**
 * Saving the open note, which is the part of the note screen with teeth (editor/NoteScreen.tsx).
 *
 * A phone kills a backgrounded webview without warning and without a beforeunload, so a debounce alone would lose
 * whatever was typed in the last fraction of a second before the person switched apps - which is precisely the moment
 * a person has just written the thing they opened the app to write.
 *
 * So there are two paths. The debounce (400 ms after the last keystroke) keeps the common case cheap, and a flush on
 * `visibilitychange` to hidden, on `pagehide` and on unmount covers every way the app can go away; the screen flushes
 * too before every way off the note it offers (back, talking into it, pin, archive, an AI run). The flush is
 * synchronous in its decision - it checks a ref, not state - because by the time a re-render could happen the process
 * may be gone.
 *
 * The live document is that ref, `body`, and only `onChange` writes it. That is the trap for everything outside the
 * screen: a `saveNote` from elsewhere is flushed away by the next keystroke. So what must change the open note asks
 * the screen instead - a rename from the note's tab arrives as `rename` and is written here, through `onChange`, on
 * the same debounce as typing (App.tsx keeps the other half of this rule).
 */

/** A rename asked for from the note's tab (notes/NoteTabs.tsx); `asked` rises with each asking. */
export interface NoteRename {
  id: string;
  title: string;
  asked: number;
}

export interface NoteSaving {
  /** What the editor holds now: written by `onChange` and nothing else. */
  body: { readonly current: string };
  /** The editor's words changed: kept, and saved on the debounce. */
  onChange: (next: string) => void;
  /** Saves what is waiting now, if anything is. Safe to call as often as a way off the note is taken. */
  flush: () => void;
  /** The note's first line, which is the only title it has. */
  title: string;
  /** No words at all yet: the page shows the ghost with its pen (art/Ghost.tsx). */
  blank: boolean;
}

const SAVE_DEBOUNCE_MS = 400;

export function useNoteSaving(note: Note, rename?: NoteRename | null): NoteSaving {
  const [title, setTitle] = useState(() => noteTitle(note.body));
  // The live document, held in a ref rather than state: it changes on every keystroke and nothing in the screen's
  // render depends on it, so putting it in state would re-render the screen once per character for nothing.
  const body = useRef(note.body);
  const saved = useRef(note.body);
  const revision = useRef(note.revision ?? 1);
  const writes = useRef<Promise<void>>(Promise.resolve());
  const writable = useRef(true);
  const timer = useRef<number | null>(null);

  const flush = useCallback(() => {
    if (timer.current !== null) {
      window.clearTimeout(timer.current);
      timer.current = null;
    }
    if (body.current === saved.current) return;
    const pending = body.current;
    saved.current = pending;
    writes.current = writes.current.then(async () => {
      if (!writable.current) return;
      try {
        const stored = await updateNote(note.id, pending, revision.current);
        revision.current = stored.revision ?? revision.current + 1;
      } catch (failure) {
        // The row was deleted or another writer won. Most importantly, this
        // editor has no insertion API and therefore cannot bring Delete back.
        writable.current = false;
        console.warn('[glyph] editor save stopped:', failure);
      }
    });
  }, [note.id]);

  const [blank, setBlank] = useState(() => !note.body.trim());
  const onChange = useCallback(
    (next: string) => {
      body.current = next;
      setBlank(!next.trim());
      // The header title is the first line, so it does need to re-render - but
      // only when the first line actually changed, which is rare.
      setTitle((prev) => {
        const now = noteTitle(next);
        return prev === now ? prev : now;
      });
      if (timer.current !== null) window.clearTimeout(timer.current);
      timer.current = window.setTimeout(flush, SAVE_DEBOUNCE_MS);
    },
    [flush],
  );

  // A rename asked for from this note's tab, written the way the canvas itself writes (see the header).
  useEffect(() => {
    if (!rename || rename.id !== note.id) return;
    const next = withFrontMatterTitle(body.current, rename.title);
    if (next !== body.current) onChange(next);
    // Each asking is its own: `asked` is what changes, so renaming twice to the same name still lands.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rename?.asked]);

  useEffect(() => {
    const onHide = () => {
      if (document.visibilityState === 'hidden') flush();
    };
    document.addEventListener('visibilitychange', onHide);
    window.addEventListener('pagehide', flush);
    return () => {
      document.removeEventListener('visibilitychange', onHide);
      window.removeEventListener('pagehide', flush);
      flush();
    };
  }, [flush]);

  return { body, onChange, flush, title, blank };
}
