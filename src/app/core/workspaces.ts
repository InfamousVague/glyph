import { useSyncExternalStore } from 'react';

/**
 * Workspaces: a name a note can be filed under, and the list shown one
 * workspace at a time.
 *
 * Matt: "add workspaces so we can sort notes by a given workspace". A
 * workspace is only a name; a note is in at most one, or in none. The list
 * has a row of them above the notes once one exists (notes/WorkspaceBar.tsx),
 * "All" first, and the chosen one is remembered, so the app opens where it
 * was left. A note is filed from its cog (editor/WorkspacePicker.tsx), and a
 * note made while a workspace is chosen is filed there, because that is the
 * list the person is looking at. Removing a workspace unfiles its notes and
 * deletes nothing.
 *
 * Kept on the page under one key, so it ships over the air: the note store is
 * Rust's (core/store.ts), and a column there is a native change. The archive
 * is not filtered: it is the place to find anything.
 */

export interface Workspace {
  id: string;
  name: string;
}

export interface Workspaces {
  /** Every workspace, in the order they were made. */
  list: readonly Workspace[];
  /** Which workspace each filed note is in, by note id. */
  of: Readonly<Record<string, string>>;
  /** The list's filter: the chosen workspace, or null for all notes. */
  current: Workspace | null;
}

interface Sheet {
  list: Workspace[];
  notes: Record<string, string>;
  current: string | null;
}

const KEY = 'glyph-workspaces';
const listeners = new Set<() => void>();
let sheet: Sheet | null = null;
let snapshot: Workspaces | null = null;

function read(): Sheet {
  try {
    const value = JSON.parse(localStorage.getItem(KEY) ?? 'null') as Partial<Sheet> | null;
    const list = Array.isArray(value?.list)
      ? value.list.filter((w): w is Workspace => Boolean(w) && typeof w.id === 'string' && typeof w.name === 'string')
      : [];
    const ids = new Set(list.map((w) => w.id));
    const notes: Record<string, string> = {};
    if (value?.notes && typeof value.notes === 'object') {
      for (const [note, id] of Object.entries(value.notes)) if (typeof id === 'string' && ids.has(id)) notes[note] = id;
    }
    const current = typeof value?.current === 'string' && ids.has(value.current) ? value.current : null;
    return { list, notes, current };
  } catch {
    return { list: [], notes: {}, current: null };
  }
}

function current(): Sheet {
  if (!sheet) sheet = read();
  return sheet;
}

function write(next: Sheet): void {
  sheet = next;
  snapshot = null;
  try {
    localStorage.setItem(KEY, JSON.stringify(next));
  } catch {
    // No storage: the change holds for this run.
  }
  listeners.forEach((listener) => listener());
}

/** Reads the sheet again: after a reset, and in tests. */
export function reloadWorkspaces(): void {
  sheet = null;
  snapshot = null;
  listeners.forEach((listener) => listener());
}

export function workspaces(): Workspaces {
  if (!snapshot) {
    const { list, notes, current: chosen } = current();
    snapshot = { list, of: notes, current: list.find((w) => w.id === chosen) ?? null };
  }
  return snapshot;
}

export function onWorkspaces(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function useWorkspaces(): Workspaces {
  return useSyncExternalStore(onWorkspaces, workspaces, workspaces);
}

/** The workspace `noteId` is filed in, or null. */
export function workspaceOf(noteId: string): Workspace | null {
  const { list, notes } = current();
  const id = notes[noteId];
  return id ? (list.find((w) => w.id === id) ?? null) : null;
}

const tidy = (name: string) => name.replace(/\s+/g, ' ').trim();

function freshId(taken: readonly Workspace[]): string {
  for (;;) {
    const id = `w-${Math.random().toString(36).slice(2, 8)}`;
    if (!taken.some((w) => w.id === id)) return id;
  }
}

/** A new workspace called `name`, or the one already called that; null for an empty name. */
export function addWorkspace(name: string): Workspace | null {
  const clean = tidy(name);
  if (!clean) return null;
  const { list, notes, current: chosen } = current();
  const had = list.find((w) => w.name.toLowerCase() === clean.toLowerCase());
  if (had) return had;
  const made = { id: freshId(list), name: clean };
  write({ list: [...list, made], notes, current: chosen });
  return made;
}

export function renameWorkspace(id: string, name: string): void {
  const clean = tidy(name);
  const { list, notes, current: chosen } = current();
  if (!clean || !list.some((w) => w.id === id)) return;
  write({ list: list.map((w) => (w.id === id ? { ...w, name: clean } : w)), notes, current: chosen });
}

/** Removes the workspace; its notes are simply not filed any more, and the list shows all notes if it was chosen. */
export function removeWorkspace(id: string): void {
  const { list, notes, current: chosen } = current();
  if (!list.some((w) => w.id === id)) return;
  const kept: Record<string, string> = {};
  for (const [note, where] of Object.entries(notes)) if (where !== id) kept[note] = where;
  write({ list: list.filter((w) => w.id !== id), notes: kept, current: chosen === id ? null : chosen });
}

/** Files `noteId` in a workspace, or in none with null. */
export function fileNote(noteId: string, id: string | null): void {
  const { list, notes, current: chosen } = current();
  if (id !== null && !list.some((w) => w.id === id)) return;
  if ((notes[noteId] ?? null) === id) return;
  const next = { ...notes };
  if (id === null) delete next[noteId];
  else next[noteId] = id;
  write({ list, notes: next, current: chosen });
}

/** A note just made: filed in the chosen workspace, if there is one and the note is not filed yet. */
export function fileNewNote(noteId: string): void {
  const { notes, current: chosen } = current();
  if (chosen && !(noteId in notes)) fileNote(noteId, chosen);
}

/** The note is gone: so is its filing. */
export function forgetNote(noteId: string): void {
  const { list, notes, current: chosen } = current();
  if (!(noteId in notes)) return;
  const next = { ...notes };
  delete next[noteId];
  write({ list, notes: next, current: chosen });
}

/** The list's filter. */
export function chooseWorkspace(id: string | null): void {
  const { list, notes, current: chosen } = current();
  const next = id !== null && list.some((w) => w.id === id) ? id : null;
  if (next === chosen) return;
  write({ list, notes, current: next });
}

/** Of `notes`, those filed in workspace `id`; all of them for null. */
export function inWorkspace<T extends { id: string }>(notes: readonly T[], id: string | null): T[] {
  if (id === null) return [...notes];
  const { notes: filed } = current();
  return notes.filter((note) => filed[note.id] === id);
}
