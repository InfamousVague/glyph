import { readStored, writeStored } from '../core/stored.ts';
import type { AiChange } from '../editor/aiChanges.ts';
import { bodyHash } from '../format/formatter.ts';

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

type Sheet = Record<string, Kept>;

function readSheet(): Sheet {
  return readStored<Sheet>(KEY, {}, (value) => (value && typeof value === 'object' && !Array.isArray(value) ? (value as Sheet) : {}));
}

/** No storage: the marks hold while the note is open and not beyond it. */
function writeSheet(sheet: Sheet): void {
  writeStored(KEY, sheet);
}

/** The marks on a note as it now reads. None clears what was kept. */
export function saveMarks(noteId: string, body: string, changes: readonly AiChange[]): void {
  const sheet = { ...readSheet() };
  if (!changes.length) {
    if (!(noteId in sheet)) return;
    delete sheet[noteId];
  } else sheet[noteId] = { hash: bodyHash(body), changes: [...changes] };
  writeSheet(sheet);
}

/** The marks kept for a note, if the body is still the one they were made on. */
export function loadMarks(noteId: string, body: string): AiChange[] | null {
  const kept = readSheet()[noteId];
  if (!kept || kept.hash !== bodyHash(body) || !Array.isArray(kept.changes)) return null;
  return kept.changes;
}

/** Whether a note has marks kept, for a card to wear a dot. */
export function hasMarks(noteId: string): boolean {
  return noteId in readSheet();
}

export function forgetMarks(noteId: string): void {
  const sheet = { ...readSheet() };
  if (!(noteId in sheet)) return;
  delete sheet[noteId];
  writeSheet(sheet);
}
