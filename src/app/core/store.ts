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
  if (isTauri()) return await invoke<Note>('save_note', { id, body, source });

  const now = Date.now();
  const notes = webAll();
  const existing = notes.find((n) => n.id === id);
  const note: Note = existing ? { ...existing, body, updatedAt: now } : { id, body, createdAt: now, updatedAt: now, source };
  webWrite([note, ...notes.filter((n) => n.id !== id)]);
  return note;
}

/**
 * Star or unstar a note. Not an edit: the note keeps its place by when it was
 * last written (see store.rs `set_starred`). Answers with the note, or null if
 * it has gone.
 */
export async function setNoteStarred(id: string, starred: boolean): Promise<Note | null> {
  if (isTauri()) return await invoke<Note | null>('set_note_starred', { id, starred });
  return webFlag(id, { starred });
}

/** Archive a note or bring it back. Not an edit either. */
export async function setNoteArchived(id: string, archived: boolean): Promise<Note | null> {
  if (isTauri()) return await invoke<Note | null>('set_note_archived', { id, archived });
  return webFlag(id, { archivedAt: archived ? Date.now() : null });
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
  if (isTauri()) return await invoke<Note | null>('set_note_formatted', { id, formatted, formattedFor, model });
  return webFlag(id, { formatted, formattedFor, formattedModel: model });
}

/** Keep a spoken note's recording length and phrases (or forget both with null). Not an edit. */
export async function setNoteRecording(id: string, recordingMs: number | null, segments: Segment[]): Promise<Note | null> {
  if (isTauri()) return await invoke<Note | null>('set_note_recording', { id, recordingMs, segments });
  return webFlag(id, { recordingMs, segments: recordingMs === null ? null : segments });
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
  if (isTauri()) {
    await invoke<void>('delete_note', { id });
    return;
  }
  webWrite(webAll().filter((n) => n.id !== id));
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

/** A note's lines with its front matter taken off, and its `title:` first where it has one. */
function withoutFrontMatter(lines: readonly string[]): string[] {
  if (!/^(---|\+\+\+)\s*$/.test(lines[0] ?? '')) return [...lines];
  for (let n = 1; n < Math.min(lines.length, 40); n += 1) {
    const line = lines[n] ?? '';
    if (/^(---|\+\+\+)\s*$/.test(line)) {
      const named = lines.slice(1, n).find((key) => /^\s*title\s*:/i.test(key));
      const title = named
        ? named
            .replace(/^\s*title\s*:\s*/i, '')
            .replace(/^['"]|['"]$/g, '')
            .trim()
        : '';
      return title ? [title, ...lines.slice(n + 1)] : lines.slice(n + 1);
    }
    if (!/^\s*[\w.-]+\s*:/.test(line) && line.trim() !== '') return [...lines];
  }
  return [...lines];
}

/** The first line of a note, which is the only title Glyph has. */
export function noteTitle(body: string): string {
  // A note that opens with front matter is titled by its words, not by the
  // fence: `---` in the list looked like a note with no name at all
  // (docs/MARKDOWN.md). The keys between the fences are skipped with it, and
  // `title:` among them is taken as the name, which is what wrote it.
  const lines = withoutFrontMatter(body.split('\n'));
  // The first line that is words, not a picture: a note that opens with a
  // photo is titled by what is said under it.
  const line = lines.find((l) => l.trim() && !/^!\[[^\]]*\]\([^)]*\)\s*$/.test(l)) ?? '';
  // Strip leading heading markers for the LIST only. The note itself keeps
  // every character; this is a label, not an edit.
  return line.replace(/^#{1,6}\s+/, '').trim();
}

/**
 * The line under the title in a row: the next non-empty line, unmarked - a
 * task's box included, which in a list reads as "[ ]" noise.
 *
 * Inline marks go too - `**`, `__`, `~~`, backticks, and a lone `_` or `*` at
 * a word's edge. The editor keeps every marker on screen because there the
 * text is being edited; in the list it is being scanned, set in a reading
 * size, and `**negative space**` reads as noise. A label, not an edit.
 */
export function notePreview(body: string): string {
  const lines = body.split('\n').slice(1);
  for (const line of lines) {
    const text = line
      .replace(/^[#>\-*\s]+/, '')
      .replace(/^\[[ xX]\]\s*/, '')
      .replace(/(\*\*|__|~~|`|\|\|)/g, '')
      .replace(/(^|\s)[*_](\S)/g, '$1$2')
      .replace(/(\S)[*_](?=\s|$|[.,;:!?])/g, '$1')
      .trim();
    if (text) return text;
  }
  return '';
}

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
    document.addEventListener('visibilitychange', onVisible);
    const unanswer = answerHost('refresh', () => void refresh());
    return () => {
      cancelled = true;
      document.removeEventListener('visibilitychange', onVisible);
      unanswer();
    };
  }, [refresh]);

  return { notes, loading, refresh };
}
