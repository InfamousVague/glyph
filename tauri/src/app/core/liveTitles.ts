import { useSyncExternalStore } from 'react';

/**
 * The title an open note has now, as its editor has it (docs/DESIGN.md §144): what its tab says.
 *
 * A tab is drawn from App's list of notes (shell/useOpenTabs.ts), which is read again when the store says the notes
 * changed, not on the editor's own saves, so a new note's tab said Untitled for as long as it was open, however its
 * first line was typed (measured: still Untitled eight seconds after a first line), and a note named from its blank
 * page would have looked unnamed beside its own heading. So the note screen says its title here as it changes
 * (editor/NoteScreen.tsx), which is only when line 1 changes, and the tab row reads it.
 *
 * A small store outside React, read through `useSyncExternalStore`, and only the tab row subscribes: App keeps no state
 * for it, so a letter typed in line 1 draws the note and its tab and not the whole app. A title here is kept with when
 * it was said, and the tab takes it only while it is newer than the note App has, so a rename that arrives by sync
 * afterwards wins.
 */

export interface LiveTitle {
  title: string;
  at: number;
}

let titles: ReadonlyMap<string, LiveTitle> = new Map();
const listeners = new Set<() => void>();

function tell(): void {
  for (const listener of listeners) listener();
}

/** The note's title as its editor has it now. */
export function setLiveTitle(id: string, title: string): void {
  if (titles.get(id)?.title === title) return;
  const next = new Map(titles);
  next.set(id, { title, at: Date.now() });
  titles = next;
  tell();
}

/** Forgets the notes whose tabs closed. */
export function dropLiveTitles(ids: readonly string[]): void {
  if (!ids.some((id) => titles.has(id))) return;
  const next = new Map(titles);
  for (const id of ids) next.delete(id);
  titles = next;
  tell();
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => void listeners.delete(listener);
}

const snapshot = () => titles;

/** Every open note's title as its editor has it, for the tab row. */
export function useLiveTitles(): ReadonlyMap<string, LiveTitle> {
  return useSyncExternalStore(subscribe, snapshot, snapshot);
}

/** The title a tab shows for a note: its editor's, while that is newer than the note as App has it, else the note's own. */
export function titleNow(note: { id: string; updatedAt: number }, stored: string, live: ReadonlyMap<string, LiveTitle>): string {
  const said = live.get(note.id);
  return said && said.at >= note.updatedAt ? said.title : stored;
}
