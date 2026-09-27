import { noteSheet, sheetOf, type Sheet } from '../core/noteSheet.ts';
import { readStoredShared, writeStored } from '../core/stored.ts';

/**
 * What the app wrote as a note's summary, kept per note on the page (docs/DESIGN.md §127 section 2): the exact
 * section text, the model, when, and how long the tape was. A summary is remade only on purpose, and this is how a
 * remake knows whether the section in the note is still the app's: if it reads exactly as kept it is replaced whole,
 * and if it differs the person edited it and the strip asks first (tapes/NoteTape.tsx). The kept text also closes
 * the section for every reader (ai/summaryText.ts `summarySection`), so a list of the person's straight under it
 * is never read as the section's. The tape's length says
 * whether the summary is from before the last take: an Add makes the tape longer and the summary older. A note
 * deleted for good takes its record with it (notes/useNoteActions.ts). A reset clears the key with every other
 * `glyph-` one (core/reset.ts).
 */

const KEY = 'glyph-summaries';

export interface KeptSummary {
  /** The section exactly as written, `## Summary` through its last item. */
  text: string;
  model: string;
  /** When it was written, in ms since the epoch. */
  at: number;
  /** The tape's length when it was written: a longer tape now means a take the summary never heard. */
  forMs: number;
}

const sheet = noteSheet<KeptSummary>(
  () => readStoredShared<Sheet<KeptSummary>>(KEY, {}, sheetOf),
  (value) => writeStored(KEY, value),
);

export function readSummary(id: string): KeptSummary | null {
  const kept = sheet.read()[id];
  return kept && typeof kept.text === 'string' ? kept : null;
}

/** The section text as written, for the readers that close the section by it (ai/summaryText.ts `summarySection`); null with none. */
export function keptText(id: string): string | null {
  return readSummary(id)?.text ?? null;
}

export function keepSummary(id: string, kept: KeptSummary): void {
  sheet.update(id, () => kept);
}

/** A note is gone: so is what was written for it. */
export function forgetSummary(id: string): void {
  sheet.forget(id);
}

/** Whether the section `text` in a note is the one the app wrote, word for word. */
export function summaryUnchanged(id: string, text: string): boolean {
  const kept = readSummary(id);
  return kept !== null && kept.text === text;
}

/** Whether the tape has grown since the summary was written: "Summary is from before the last take." */
export function summaryBehind(id: string, recordingMs: number): boolean {
  const kept = readSummary(id);
  return kept !== null && recordingMs > kept.forMs;
}
