import { getNote, type Note } from '../core/store.ts';

/**
 * Whether a held side key carries on the last voice note or starts a new one.
 *
 * People dictate in bursts: a thought, the phone back in the pocket, then "oh,
 * and" later. Five notes of one sentence each is worse than one note that
 * grew, so with memo mode on (the default) a recording - from the Speak button
 * or the side key - goes onto the last spoken note, below what is already
 * there, for as long as that note exists, until "New note" is tapped on the
 * recorder, after which the new note is the one that grows. With memo mode off
 * every recording is a new note.
 *
 * Remembered in localStorage, not the store: it is a fact about this device,
 * not about the note, and losing it costs one new note.
 */

const KEY = 'glyph-last-capture';

export interface LastCapture {
  id: string;
  /** When that capture ended, ms since the epoch. */
  at: number;
}

/** Whether a capture continues `last`: only with memo mode on, and only if there is a last. */
export function continues(last: LastCapture | null, memo: boolean): boolean {
  return memo && last !== null;
}

export function readLastCapture(): LastCapture | null {
  try {
    const value = JSON.parse(localStorage.getItem(KEY) ?? 'null') as unknown;
    if (value && typeof value === 'object' && typeof (value as LastCapture).id === 'string' && typeof (value as LastCapture).at === 'number') {
      return value as LastCapture;
    }
  } catch {
    // Unreadable is the same as none.
  }
  return null;
}

/** Called when a capture saves a note: the next side-key press within the window continues it. */
export function rememberCapture(id: string, at = Date.now()): void {
  try {
    localStorage.setItem(KEY, JSON.stringify({ id, at } satisfies LastCapture));
  } catch {
    // No storage: every capture is a new note, as before.
  }
}

/** The note a capture should continue, if memo mode is on and it still exists and is not archived. */
export async function continuationNote(memo: boolean): Promise<Note | null> {
  const last = readLastCapture();
  if (!continues(last, memo) || !last) return null;
  const note = await getNote(last.id).catch(() => null);
  return note && !note.archivedAt ? note : null;
}

/** `addition` below `base`, a blank line between, for a note that grew by another recording. */
export function appendBody(base: string, addition: string): string {
  if (!addition.trim()) return base;
  if (!base.trim()) return addition;
  return `${base.replace(/\s+$/, '')}\n\n${addition}`;
}
