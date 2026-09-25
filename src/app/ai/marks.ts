import type { AiChange } from '../editor/aiChanges.ts';
import { bodyHash } from '../format/bodyHash.ts';
import { readStored, writeStored } from '../core/stored.ts';
import { noteSheet, sheetOf, type Sheet } from './noteSheet.ts';

/**
 * The AI's marks on a note, kept with it: Matt chose marks that stay until
 * Keep, Revert, Clear marks, or typing on the line - leaving the note keeps
 * them for next time. Each note's changes are kept on the page with a hash
 * of the body they belong to; opened again, the marks go back on only when
 * the body still hashes the same, since a note edited elsewhere in between
 * (another device, Claude, a file) has words the positions no longer point
 * at. A reset clears the key with every other `glyph-` one (core/reset.ts).
 */

const KEY = 'glyph-ai-marks';

interface Kept {
  hash: number;
  changes: AiChange[];
}

/**
 * Per note, its marks and the hash of the body they were made on. Read afresh each time rather than shared: what
 * `loadMarks` answers goes back into an editor, which is given an array of its own.
 */
const sheet = noteSheet<Kept>(
  () => readStored<Sheet<Kept>>(KEY, {}, sheetOf),
  (value) => writeStored(KEY, value),
);

/** The marks on a note as it now reads. None clears what was kept. */
export function saveMarks(noteId: string, body: string, changes: readonly AiChange[]): void {
  sheet.update(noteId, () => (changes.length ? { hash: bodyHash(body), changes: [...changes] } : undefined));
}

/** The marks kept for a note, if the body is still the one they were made on. */
export function loadMarks(noteId: string, body: string): AiChange[] | null {
  const kept = sheet.read()[noteId];
  if (!kept || kept.hash !== bodyHash(body) || !Array.isArray(kept.changes)) return null;
  return kept.changes;
}

/** Whether a note has marks kept, for a card to wear a dot. */
export function hasMarks(noteId: string): boolean {
  return noteId in sheet.read();
}

/** A note is gone: so are its marks. */
export function forgetMarks(noteId: string): void {
  sheet.forget(noteId);
}
