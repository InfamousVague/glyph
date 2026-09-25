import { useCallback, useEffect, useState } from 'react';
import { answerHost } from './host.ts';
import { invoke, isTauri } from './tauri.ts';
import type { Segment } from '../capture/markdown.ts';

/**
 * Where notes live, and the one door the page uses to reach them.
 *
 * The store is owned by RUST, not by this file, and that is forced rather than
 * chosen: on Android the voice capture runs in its own process with no webview
 * alive, and it has to be able to write a note. A store that lived in the page
 * could not be written to by a process the page is not running in. So the
 * SQLite database is the truth, `src-tauri/src/store.rs` owns it, and this
 * module is a typed remote control.
 *
 * The localStorage half is not a toy. `npm run dev` in a browser is where most
 * of the editor work actually happens - a Vite reload is milliseconds and an
 * Android build is minutes - so the browser has to be a real working app, with
 * the same interface and the same persistence guarantees within its own world.
 * It is never used inside the Tauri webview.
 */

export interface Note {
  id: string;
  body: string;
  /** Milliseconds since the epoch. */
  createdAt: number;
  updatedAt: number;
  /** How the note came to exist: typed in the app, or spoken into a capture. */
  source: NoteSource;
  /**
   * Pinned to the top of the list, by a swipe. Optional because a binary from
   * before native generation 3 answers without it.
   */
  starred?: boolean;
  /** When it was swiped into the archive; absent or null for a note in the list. */
  archivedAt?: number | null;
  /** The kept recording's length, for a spoken note whose tape was kept. Native generation 6. */
  recordingMs?: number | null;
  /** The recording's phrases with their times, only on a note fetched by id; the list answers null. */
  segments?: Segment[] | null;
  /**
   * The on-device model's version of the body (core/ai.ts, format/). Only on a
   * note fetched by id; the list answers null. Native generation 10.
   */
  formatted?: string | null;
  /** The page's hash (format/formatter.ts) of the body `formatted` was written from. */
  formattedFor?: number | null;
  /** The model that wrote it, by its id in core/ai.ts. */
  formattedModel?: string | null;
  /** Where the note's file is in the library, relative to it (`Inbox/AttackFM.md`). Native generation 15; absent before, and in a browser. */
  path?: string;
}

export type NoteSource = 'editor' | 'capture';

/** Newest-updated first, which is the only order the list is ever shown in. */
const byRecency = (a: Note, b: Note): number => b.updatedAt - a.updatedAt;

// --- the browser half -------------------------------------------------------

const WEB_KEY = 'glyph-notes';

function webAll(): Note[] {
  try {
    const raw = localStorage.getItem(WEB_KEY);
    if (!raw) return [];
    const parsed: unknown = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as Note[]) : [];
  } catch {
    // A corrupt or unreadable store reads as empty rather than throwing: the
    // browser half exists so development never stops, and a parse error in a
    // dev fixture should not be the thing that stops it.
    return [];
  }
}

function webWrite(notes: Note[]): void {
  try {
    localStorage.setItem(WEB_KEY, JSON.stringify(notes));
  } catch {
    // Private mode, or quota. The note stays correct in memory for this run.
  }
}

// --- the public API ---------------------------------------------------------

/** Sent on `window` after this device changes a note, so sync (core/sync/engine.ts) sends it soon. */
export const NOTE_SAVED = 'glyph:note-saved';

function touched<T>(value: T): T {
  if (typeof window !== 'undefined') window.dispatchEvent(new Event(NOTE_SAVED));
  return value;
}

export async function listNotes(): Promise<Note[]> {
  if (isTauri()) return (await invoke<Note[]>('list_notes')).sort(byRecency);
  return webAll().sort(byRecency);
}

export async function getNote(id: string): Promise<Note | null> {
  if (isTauri()) return await invoke<Note | null>('get_note', { id });
  return webAll().find((n) => n.id === id) ?? null;
}

/**
 * Write a note and get back what was actually stored.
 *
 * The caller supplies the id even for a new note, so the editor can open on a
 * note that has never been saved and still know what it is editing. Rust
 * upserts on that id: `created_at` is set once and never moved, `updated_at`
 * always is.
 */
export async function saveNote(id: string, body: string, source: NoteSource = 'editor'): Promise<Note> {
  if (isTauri()) return touched(await invoke<Note>('save_note', { id, body, source }));

  const now = Date.now();
  const notes = webAll();
  const existing = notes.find((n) => n.id === id);
  const note: Note = existing ? { ...existing, body, updatedAt: now } : { id, body, createdAt: now, updatedAt: now, source };
  webWrite([note, ...notes.filter((n) => n.id !== id)]);
  return touched(note);
}

/**
 * Star or unstar a note. Not an edit: the note keeps its place by when it was
 * last written (see store.rs `set_starred`). Answers with the note, or null if
 * it has gone.
 */
export async function setNoteStarred(id: string, starred: boolean): Promise<Note | null> {
  if (isTauri()) return touched(await invoke<Note | null>('set_note_starred', { id, starred }));
  return touched(webFlag(id, { starred }));
}

/** Archive a note or bring it back. Not an edit either. */
export async function setNoteArchived(id: string, archived: boolean): Promise<Note | null> {
  if (isTauri()) return touched(await invoke<Note | null>('set_note_archived', { id, archived }));
  return touched(webFlag(id, { archivedAt: archived ? Date.now() : null }));
}

function webFlag(
  id: string,
  change: Partial<Pick<Note, 'starred' | 'archivedAt' | 'recordingMs' | 'segments' | 'formatted' | 'formattedFor' | 'formattedModel'>>,
): Note | null {
  const notes = webAll();
  const note = notes.find((n) => n.id === id);
  if (!note) return null;
  const next = { ...note, ...change };
  webWrite(notes.map((n) => (n.id === id ? next : n)));
  return next;
}

/**
 * Keep the formatted version of a note (or forget it with null): the text, the
 * hash of the body it came from, and the model that wrote it. Not an edit: the
 * body and its time stand.
 */
export async function setNoteFormatted(id: string, formatted: string | null, formattedFor: number | null, model: string | null): Promise<Note | null> {
  if (isTauri()) return touched(await invoke<Note | null>('set_note_formatted', { id, formatted, formattedFor, model }));
  return touched(webFlag(id, { formatted, formattedFor, formattedModel: model }));
}

/** Keep a spoken note's recording length and phrases (or forget both with null). Not an edit. */
export async function setNoteRecording(id: string, recordingMs: number | null, segments: Segment[]): Promise<Note | null> {
  if (isTauri()) return touched(await invoke<Note | null>('set_note_recording', { id, recordingMs, segments }));
  return touched(webFlag(id, { recordingMs, segments: recordingMs === null ? null : segments }));
}

/**
 * Write a note exactly as another device has it (core/sync/notes.ts): its own
 * times, pin, archive and recording, not now's. Native generation 16; the sync
 * engine checks the generation before it calls. Answers the note as stored.
 */
export async function applyNote(note: Note): Promise<Note> {
  if (isTauri()) return await invoke<Note>('store_apply', { note });
  const notes = webAll();
  webWrite([note, ...notes.filter((n) => n.id !== note.id)]);
  return note;
}

/** Sent on `window` when notes changed without the list's doing - sync wrote some - so the list asks again. */
export const NOTES_CHANGED = 'glyph:notes-changed';

export function announceNotesChanged(): void {
  if (typeof window !== 'undefined') window.dispatchEvent(new Event(NOTES_CHANGED));
}

/**
 * The list as the list screen shows it: starred notes first, each group newest
 * edit first, archived notes left out. The archive is the reverse selection,
 * most recently archived first.
 */
export function listOrder(notes: readonly Note[]): Note[] {
  return notes.filter((n) => !n.archivedAt).sort((a, b) => Number(Boolean(b.starred)) - Number(Boolean(a.starred)) || b.updatedAt - a.updatedAt);
}

export function archiveOrder(notes: readonly Note[]): Note[] {
  return notes.filter((n) => n.archivedAt).sort((a, b) => (b.archivedAt ?? 0) - (a.archivedAt ?? 0));
}

export async function deleteNote(id: string): Promise<void> {
  if (isTauri()) await invoke<void>('delete_note', { id });
  else webWrite(webAll().filter((n) => n.id !== id));
  touched(null);
}

/**
 * A fresh id.
 *
 * `crypto.randomUUID` needs a secure context, which a Tauri custom protocol is
 * and an `http://` dev server on a phone on the LAN is not - so the fallback is
 * not hypothetical, it is what runs when the editor is opened from another
 * device on the network.
 */
export function newNoteId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  return `n-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

// A note's title, and its lines with the front matter taken off, are core/noteTitle.ts: pure, so the MCP server
// titles a note with the code the list runs. Here for the many callers that have always found them here.
export { noteTitle, withoutFrontMatter } from './noteTitle.ts';

// --- the hook the list uses -------------------------------------------------

interface NotesState {
  notes: Note[];
  loading: boolean;
  refresh: () => Promise<void>;
}

/**
 * The notes list, refetched on demand and whenever the app comes back to the
 * front.
 *
 * The visibility listener is what makes voice capture appear without any
 * cross-process plumbing: a note written by the Android capture service while
 * the webview was dead shows up the moment the app is resumed, because the
 * page simply asks again. `MainActivity.onResume` also calls
 * `window.__glyph.refresh()` for the case where the webview was alive but
 * hidden and the browser never fired `visibilitychange`.
 */
/** Retries for the first read of the list, in ms: a store still opening, or an index busy after an install. */
const FIRST_READ_RETRIES_MS = [250, 900, 2400];

export function useNotes(): NotesState {
  const [notes, setNotes] = useState<Note[]>([]);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    const next = await listNotes();
    setNotes(next);
    setLoading(false);
  }, []);

  useEffect(() => {
    // The first read is the one that can go wrong: on a phone the store may
    // still be opening, or its index busy right after an install, and a
    // rejection here once left the list a blank page until a relaunch. So a
    // failed first read is tried again a few times, and an empty first answer
    // on the phone is asked once more a moment later, since a library that
    // was there a launch ago is more likely still there than gone.
    let cancelled = false;
    void (async () => {
      for (let attempt = 0; ; attempt += 1) {
        try {
          const next = await listNotes();
          if (cancelled) return;
          setNotes(next);
          setLoading(false);
          if (next.length === 0 && attempt === 0 && isTauri()) {
            // Where the empty answer came from, should it ever be wrong: a page under
            // another origin would be reading the browser store, not the phone's.
            console.info(`[glyph] first read of the notes was empty (tauri ${String(isTauri())}, origin ${location.origin}); asking again`);
            await new Promise((resolve) => setTimeout(resolve, 1200));
            if (!cancelled) await refresh().catch(() => undefined);
          }
          return;
        } catch (error) {
          const wait = FIRST_READ_RETRIES_MS[attempt];
          if (wait === undefined) {
            console.warn(`[glyph] the notes could not be read (tauri ${String(isTauri())}, origin ${location.origin})`, error);
            return;
          }
          await new Promise((resolve) => setTimeout(resolve, wait));
          if (cancelled) return;
        }
      }
    })();
    const onVisible = () => {
      if (document.visibilityState === 'visible') void refresh();
    };
    const onChanged = () => void refresh();
    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener(NOTES_CHANGED, onChanged);
    const unanswer = answerHost('refresh', () => void refresh());
    return () => {
      cancelled = true;
      document.removeEventListener('visibilitychange', onVisible);
      window.removeEventListener(NOTES_CHANGED, onChanged);
      unanswer();
    };
  }, [refresh]);

  return { notes, loading, refresh };
}
