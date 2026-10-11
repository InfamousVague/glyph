import { useSyncExternalStore } from 'react';
import type { Version } from './file.ts';

/**
 * The open note's editor, as the version history needs it from outside the note (Matt: "make a sidebar that can be
 * expanded on desktop to see the version history"): the history in the aside (aside/AsideHistory.tsx) sits beside the
 * note rather than in it, but what it compares a version with is the words as they are in the editor now, and a
 * version is put back through the editor, as one change to undo, saved the way typing is (editor/NoteScreen.tsx
 * `restoreVersion`). So the note on screen says here how to do both, for as long as it is on screen.
 */

export interface LiveNote {
  /** The words in the editor now. */
  current: () => string;
  /** Puts a version's words into the note, through the editor. */
  restore: (text: string, version: Version) => void;
}

const live = new Map<string, LiveNote>();
const listeners = new Set<() => void>();
let changes = 0;

function told(): void {
  changes += 1;
  for (const listener of listeners) listener();
}

/** Note `noteId`'s editor is on screen; answers the way to say it has gone. */
export function liveNoteOpened(noteId: string, note: LiveNote): () => void {
  live.set(noteId, note);
  told();
  return () => {
    if (live.get(noteId) !== note) return;
    live.delete(noteId);
    told();
  };
}

/** Note `noteId`'s editor, while it is on screen. */
export function liveNote(noteId: string): LiveNote | null {
  return live.get(noteId) ?? null;
}

/** `liveNote`, kept up to date as notes open and close. */
export function useLiveNote(noteId: string | null): LiveNote | null {
  useSyncExternalStore(
    (listener) => {
      listeners.add(listener);
      return () => void listeners.delete(listener);
    },
    () => changes,
    () => changes,
  );
  return noteId ? liveNote(noteId) : null;
}
