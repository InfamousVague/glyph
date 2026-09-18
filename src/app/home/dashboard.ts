import { itemOnLine, itemWords } from '../core/boards.ts';
import type { Note } from '../core/store.ts';

/**
 * What the home page gathers from the notes (home/HomeScreen.tsx): the pinned ones, the ones touched last, and every
 * to-do not yet ticked, wherever it was written. Pure, so each rule is a test rather than a page to look at.
 */

/** Pinned notes, newest first. The archive is never on the home page. */
export function pinnedNotes(notes: readonly Note[]): Note[] {
  return notes.filter((n) => n.starred && !n.archivedAt).sort((a, b) => b.updatedAt - a.updatedAt);
}

/** The notes touched last, pinned ones left to their own row so nothing shows twice. */
export function recentNotes(notes: readonly Note[], count: number): Note[] {
  return notes
    .filter((n) => !n.starred && !n.archivedAt)
    .sort((a, b) => b.updatedAt - a.updatedAt)
    .slice(0, count);
}

export interface OpenTask {
  noteId: string;
  /** The line it is on, counting from 0, which is what ticking it rewrites. */
  line: number;
  text: string;
  /** Its anchor (core/boards.ts), when it has one: opening the note lands on it. */
  at?: string;
  /** When its note was touched, which orders the list: what was being worked on comes first. */
  touched: number;
}

/** A to-do with its box still empty: `- [ ] words`, `* [ ]`, `1. [ ]`. */
const OPEN = /^\s*(?:[-*+]|\d+[.)])\s+\[ \]/;
/** A code fence opening or closing: a to-do inside one is an example of a to-do, not one. */
const FENCE = /^\s*(`{3,}|~{3,})/;

/** Every unticked to-do in the notes, the most recently touched note's first, in the order each note has them. */
export function openTasks(notes: readonly Note[]): OpenTask[] {
  const tasks: OpenTask[] = [];
  for (const note of [...notes].filter((n) => !n.archivedAt).sort((a, b) => b.updatedAt - a.updatedAt)) {
    let fenced = false;
    note.body.split('\n').forEach((line, index) => {
      if (FENCE.test(line)) {
        fenced = !fenced;
        return;
      }
      if (fenced || !OPEN.test(line)) return;
      const text = itemWords(line)?.trim();
      if (!text) return;
      tasks.push({ noteId: note.id, line: index, text, at: itemOnLine(line)?.id, touched: note.updatedAt });
    });
  }
  return tasks;
}
