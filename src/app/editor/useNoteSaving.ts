import { useCallback, useEffect, useRef, useState } from 'react';
import { transcriptOf, withoutTranscript, withTranscript } from '../capture/markdown.ts';
import { withFrontMatterTitle } from '../core/frontMatter.ts';
import { announceNotesChanged, getNote, noteTitle, updateNote, type Note } from '../core/store.ts';

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
 *
 * One writer outside the page is allowed in: the phone's own write-up of a meeting, which appends the transcript to
 * the note from Rust while the note may be open (docs/DESIGN.md §127 section 4). A save that then conflicts is read
 * again, and when the stored note differs from what was being saved by that transcript alone (capture/markdown.ts
 * `withoutTranscript`), the save is REBASED: the transcript is put onto the words as they are, the revision taken,
 * the save made again, and the editor handed the result (`onExternalChange`). Any other conflict stops the saving as
 * it always has. And a note the write-up changed while nothing here was unsaved is simply adopted (`adopt`), so the
 * transcript is seen arriving rather than found at the next visit.
 *
 * A note opened again is read again too. The app opens a note with the copy its list holds, and the list is read when
 * it is told to (core/store.ts `useNotes`), not after every save, so a note typed in and opened again - a notebook's
 * page from its bar, a journal's entry from its row, a tab - opened without its last words, and the next keystroke's
 * save, from the old revision, was refused and stopped the saving. So a screen, once the last screen on its note has
 * finished saving, takes the note as the store has it while nothing is typed here yet (`adopt`), and a screen that
 * saved anything says so as it goes, once its last save has landed, so the list, and the journal's rows and the cards
 * drawn from it, catch up.
 */

/** The saves each note's last screen made, by the note's id: what the next screen on that note waits for before it reads. */
const lastWrites = new Map<string, Promise<void>>();

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
  /**
   * The note as the store has it now, taken as the editor's words and revision, when nothing here is unsaved: true
   * when it was taken, and the editor was handed the words (`onExternalChange`). False with an edit still to save,
   * which the next save's rebase looks after.
   */
  adopt: (stored: Note) => boolean;
}

export interface NoteSavingOptions {
  /** The words changed under the editor - a transcript arrived - and the editor is to show them. */
  onExternalChange?: (body: string) => void;
}

const SAVE_DEBOUNCE_MS = 400;

export function useNoteSaving(note: Note, rename?: NoteRename | null, { onExternalChange }: NoteSavingOptions = {}): NoteSaving {
  const [title, setTitle] = useState(() => noteTitle(note.body));
  // The live document, held in a ref rather than state: it changes on every keystroke and nothing in the screen's
  // render depends on it, so putting it in state would re-render the screen once per character for nothing.
  const body = useRef(note.body);
  const saved = useRef(note.body);
  /** The body the store last took from here: what a conflict is measured against. */
  const written = useRef(note.body);
  const revision = useRef(note.revision ?? 1);
  const writes = useRef<Promise<void>>(Promise.resolve());
  /** Whether this screen has saved anything: said as it goes, so the app's list reads the note again. */
  const wrote = useRef(false);
  const writable = useRef(true);
  const timer = useRef<number | null>(null);
  const external = useRef(onExternalChange);
  external.current = onExternalChange;

  /** The editor shown words that came from outside it, and the header title with them. */
  const handOver = useCallback((next: string) => {
    setTitle(noteTitle(next));
    external.current?.(next);
  }, []);

  const flush = useCallback(() => {
    if (timer.current !== null) {
      window.clearTimeout(timer.current);
      timer.current = null;
    }
    if (body.current === saved.current) return;
    const pending = body.current;
    saved.current = pending;
    wrote.current = true;
    writes.current = writes.current.then(async () => {
      if (!writable.current) return;
      try {
        const stored = await updateNote(note.id, pending, revision.current);
        revision.current = stored.revision ?? revision.current + 1;
        written.current = pending;
      } catch (failure) {
        // Another writer won, or the row was deleted. The one writer allowed is the phone's write-up, which appends
        // the transcript: when that is the whole difference between the store and what was last written from here,
        // the save is made again over it (the header says why).
        const stored = await getNote(note.id).catch(() => null);
        const transcript = stored ? transcriptOf(stored.body) : null;
        if (stored && transcript !== null && transcript !== transcriptOf(written.current) && withoutTranscript(stored.body) === withoutTranscript(written.current)) {
          const rebased = withTranscript(pending, transcript);
          revision.current = stored.revision ?? revision.current;
          saved.current = rebased;
          // Typed on since: the words in hand keep the transcript's place for the next save; else they are these.
          if (body.current === pending) {
            body.current = rebased;
            handOver(rebased);
          } else body.current = withTranscript(body.current, transcript);
          try {
            const again = await updateNote(note.id, rebased, revision.current);
            revision.current = again.revision ?? revision.current + 1;
            written.current = rebased;
          } catch (second) {
            writable.current = false;
            console.warn('[glyph] editor save stopped:', second);
          }
          return;
        }
        // Most importantly, this editor has no insertion API and therefore cannot bring Delete back.
        writable.current = false;
        console.warn('[glyph] editor save stopped:', failure);
      }
    });
    lastWrites.set(note.id, writes.current);
  }, [note.id, handOver]);

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

  const adopt = useCallback(
    (stored: Note): boolean => {
      // Nothing unsaved, and nothing on its way either: a save flushed but not yet answered counts as unsaved, since
      // adopting over it would hand the editor words without the ones just typed, and leave that save to conflict
      // with a body this hook had already taken as written (its rebase would then see no transcript to put back).
      if (!writable.current || body.current !== saved.current || written.current !== saved.current) return false;
      revision.current = stored.revision ?? revision.current;
      written.current = stored.body;
      if (stored.body === body.current) return true;
      body.current = stored.body;
      saved.current = stored.body;
      setBlank(!stored.body.trim());
      handOver(stored.body);
      return true;
    },
    [handOver],
  );

  // A rename asked for from this note's tab, written the way the canvas itself writes (see the header).
  useEffect(() => {
    if (!rename || rename.id !== note.id) return;
    const next = withFrontMatterTitle(body.current, rename.title);
    if (next !== body.current) onChange(next);
    // Each asking is its own: `asked` is what changes, so renaming twice to the same name still lands.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rename?.asked]);

  // The note as the store has it, once the last screen on it has finished saving (see the header): taken only while
  // this screen has saved nothing, since its own saves are newer than any read begun before them, and only when the
  // store's is another revision than the copy this screen was opened with. Another, not a higher one: a note a sync
  // wrote carries the other device's count (src-tauri/src/library/mod.rs `apply_note`).
  useEffect(() => {
    let live = true;
    void (lastWrites.get(note.id) ?? Promise.resolve())
      .then(() => getNote(note.id))
      .then((stored) => {
        if (live && stored && !wrote.current && (stored.revision ?? 1) !== revision.current) adopt(stored);
      })
      .catch(() => undefined);
    return () => {
      live = false;
    };
  }, [note.id, adopt]);

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
      if (wrote.current) void writes.current.then(announceNotesChanged);
    };
  }, [flush]);

  return { body, onChange, flush, title, blank, adopt };
}
