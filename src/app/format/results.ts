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

/** What is kept here per note: the home page's one-line gist. Older sheets may still hold a mode's text; it is read past. */
type Sheet = Record<string, Partial<Record<string, unknown>>>;

/**
 * The sheet, read shared (core/stored.ts `readStoredShared`): the home page reads a gist for every card it draws, and
 * each read was the whole sheet parsed again (measured: 24 parses to show the home page once). A read asks for the
 * text, which cannot be stale, and parses only when it has changed. What it answers is shared: a writer copies it
 * first.
 */
function readSheet(): Sheet {
  return readStoredShared<Sheet>(KEY, {}, (value) => (value && typeof value === 'object' && !Array.isArray(value) ? (value as Sheet) : {}));
}

/** No storage: the text stays on screen for now and is written again next time. */
function writeSheet(sheet: Sheet): void {
  writeStored(KEY, sheet);
}

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
  return (readSheet()[id]?.gist as Gist | undefined) ?? null;
}

export function keepGist(id: string, gist: Gist): void {
  const sheet = { ...readSheet() };
  sheet[id] = { ...(sheet[id] ?? {}), gist };
  writeSheet(sheet);
}

/** A note is gone: so is its gist. */
export function forgetResults(id: string): void {
  const sheet = { ...readSheet() };
  if (!(id in sheet)) return;
  delete sheet[id];
  writeSheet(sheet);
}
