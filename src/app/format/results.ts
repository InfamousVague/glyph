import { noteSheet, sheetOf, type Sheet } from '../ai/noteSheet.ts';
import { readStoredShared, writeStored } from '../core/stored.ts';

/**
 * What the AI keeps on the page per note: the home page's one-line gist.
 *
 * Each mode's text used to be kept here too, beside the store's `formatted`
 * columns, for the robot's view over the note; the view is gone and the
 * model's words land in the note itself now (ai/useLanding.ts), so only the
 * gist is left, under the same key with the hash of the body it came from.
 * A reset clears the key with every other `glyph-` one (core/reset.ts).
 */

const KEY = 'glyph-ai-results';

/** Per note, the gist, beside whatever an older sheet still holds for a mode's text, which is read past and kept. */
type Kept = Partial<Record<string, unknown>>;

/**
 * Read shared (core/stored.ts `readStoredShared`): the home page reads a gist for every card it draws, and each read
 * was the whole sheet parsed again (measured: 24 parses to show the home page once). A read asks for the text, which
 * cannot be stale, and parses only when it has changed.
 */
const sheet = noteSheet<Kept>(
  () => readStoredShared<Sheet<Kept>>(KEY, {}, sheetOf),
  (value) => writeStored(KEY, value),
);

/** The home page's gist: its line, the body it came from as a hash, its length and its first line, and the model. */
export interface Gist {
  text: string;
  for: number;
  model: string;
  /** The body's length and first line when the gist was written: what "a meaningful change" is measured against. */
  len?: number;
  head?: string;
}

export function readGist(id: string): Gist | null {
  return (sheet.read()[id]?.gist as Gist | undefined) ?? null;
}

export function keepGist(id: string, gist: Gist): void {
  sheet.update(id, (was) => ({ ...(was ?? {}), gist }));
}

/** A note is gone: so is its gist. */
export function forgetResults(id: string): void {
  sheet.forget(id);
}
