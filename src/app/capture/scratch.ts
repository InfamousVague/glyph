import type { Segment } from './markdown.ts';

/**
 * The memo's scratch page: where memo mode writes while a memo is said, instead of into the last note (Matt: "change
 * memo mode to write to a scratch file that's not real until the memo is done, then the AI can figure out how to
 * sort"). It is not a note: it lives in the page's own storage, written a second at a time so a killed app loses
 * nothing, and it becomes notes only when its sorting is committed (sort/). A scratch left behind by a take that
 * never finished (the app killed mid-memo) is sorted the next time the notes list opens.
 */

export interface Scratch {
  /** The id the take's recording is kept under, and the new note's id if one is made. */
  id: string;
  /** The memo as markdown, titled by its first words. */
  markdown: string;
  /** Every phrase heard, commands included. */
  heard: string;
  /** Length of the kept recording, when the take has ended and one was kept. */
  recordedMs: number | null;
  segments: Segment[];
  /** The take ended (Done); until then it may still be growing. */
  done: boolean;
  at: number;
}

const KEY = 'glyph-scratch';

export function saveScratch(scratch: Scratch): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(scratch));
  } catch {
    // Storage refused: the take still ends in sorting from what is in memory.
  }
}

export function readScratch(): Scratch | null {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Scratch;
    return typeof parsed.id === 'string' && typeof parsed.markdown === 'string' ? parsed : null;
  } catch {
    return null;
  }
}

export function clearScratch(): void {
  try {
    localStorage.removeItem(KEY);
  } catch {
    // Nothing to clear.
  }
}
