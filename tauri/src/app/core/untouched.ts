import { frontMatterOffset } from './frontMatter.ts';
import { readStored, writeStored } from './stored.ts';

/**
 * The notes this device gave words to and nobody has written in yet (docs/DESIGN.md §142, §144): what lets one left
 * untouched be taken back. A journal's entry (App.tsx `newEntry`), a new note turned into a template from its blank page,
 * and a new note named from one of the names under its first line (editor/nameChips.ts) are each one.
 *
 * "A note opened and left leaves nothing behind" is the app's promise for a new note (docs/LIBRARY.md): a note with no
 * words is a draft with no file. Words the app writes break it, since a note with words is a file at once, and an
 * entry is a line in its journal too. So the record is written first, before the words or the line, and a note whose
 * words are still the words it was given, left, is taken back: the note, an entry's line, and the place still waiting
 * to be written into it (core/location.ts asks `isUntouched` before a tag lands). The record is kept on the page's own
 * storage, not in memory, because Android lets a backgrounded WebView go without a word, and the note must still be
 * taken back at the next launch rather than left with a place written in. The storage key is the one the journal wrote
 * first, `glyph-entry-drafts`, so a record a 1.10.0 build kept is still read.
 *
 * On this device only, never synced: another device neither made the note nor can know whether it is untouched. At
 * most twenty are kept, and none older than a week: a note that old was never going to be taken back.
 *
 * **Fresh.** A take-back is a delete with no Trash and no toast, so a record may be written only for a note this run is
 * making and nobody has written in. The names and the templates on a blank page are offered only on such a note: one
 * `newNote` made in this run (`markFresh`), until its words are first anything but empty or the app's own (a name, a
 * template, as its record has them). Kept in memory and nowhere else, so a relaunch empties it, and a note from before
 * this run, a note that came by sync, and a note typed in and emptied are never fresh: nothing offered there can take
 * an old note away.
 *
 * A leaf, but for the storage and the front matter rule, so core/location.ts can import it without a cycle.
 */

export interface UntouchedRecord {
  /** The journal it is an entry of; absent for a new note given words from its blank page. */
  journalId?: string;
  title: string;
  /** Its words as they were made, after the front matter: while they are still these, nobody has written in it. */
  words: string;
  /** When it was made. */
  at: number;
}

const KEY = 'glyph-entry-drafts';
const KEEP = 20;
const WEEK_MS = 7 * 24 * 60 * 60_000;

function isRecord(value: unknown): value is UntouchedRecord {
  if (!value || typeof value !== 'object') return false;
  const record = value as Record<string, unknown>;
  return (record.journalId === undefined || typeof record.journalId === 'string') && typeof record.title === 'string' && typeof record.words === 'string' && typeof record.at === 'number';
}

/** Every record kept, by the note's id: none of another build's shape, and none older than a week. */
export function untouchedRecords(now = Date.now()): Record<string, UntouchedRecord> {
  const all = readStored<Record<string, unknown>>(KEY, {}, (raw) => (raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as Record<string, unknown>) : null));
  const kept: Record<string, UntouchedRecord> = {};
  for (const [id, record] of Object.entries(all)) if (isRecord(record) && now - record.at <= WEEK_MS) kept[id] = record;
  return kept;
}

function writeAll(records: Record<string, UntouchedRecord>): void {
  const newest = Object.entries(records)
    .sort((a, b) => b[1].at - a[1].at)
    .slice(0, KEEP);
  writeStored(KEY, newest.length ? Object.fromEntries(newest) : null);
}

/** Keeps the record of a note just being given words. */
export function rememberUntouched(id: string, record: UntouchedRecord): void {
  writeAll({ ...untouchedRecords(), [id]: record });
}

export function untouchedRecord(id: string): UntouchedRecord | null {
  return untouchedRecords()[id] ?? null;
}

/** The words an untouched entry is taken as having now: its spoken entry's, which start without the line the words go on from. */
export function setUntouchedWords(id: string, words: string): void {
  const all = untouchedRecords();
  const record = all[id];
  if (!record) return;
  writeAll({ ...all, [id]: { ...record, words } });
}

/** The note is the person's now, or gone: nothing is kept for it. */
export function forgetUntouched(id: string): void {
  const all = untouchedRecords();
  if (!(id in all)) return;
  delete all[id];
  writeAll(all);
}

/** A note's words after its front matter: what a record compares. */
export function wordsOf(body: string): string {
  return body.slice(frontMatterOffset(body));
}

/**
 * Whether the note `id` is still as this device made it: a record, words that are still the record's (a place or a
 * look written into its front matter is not a word), and no recording, pin or archive, each of which is a person's
 * doing.
 */
export function isUntouched(id: string, body: string, note?: { recordingMs?: number | null; starred?: boolean; archivedAt?: number | null }): boolean {
  const record = untouchedRecord(id);
  if (!record) return false;
  if (note?.recordingMs || note?.starred || note?.archivedAt) return false;
  return wordsOf(body).trim() === record.words.trim();
}

/** The new notes made in this run that have had no words of the person's own. */
const fresh = new Set<string>();

/** A note `newNote` just made: nobody has written in it. */
export function markFresh(id: string): void {
  fresh.add(id);
}

/** Whether the note was made in this run and has had no words of the person's own. */
export function isFresh(id: string): boolean {
  return fresh.has(id);
}

/** The note has had words of the person's own: it is never offered a name or a template again. */
export function spoilFresh(id: string): void {
  fresh.delete(id);
}

/**
 * What a change to a fresh note's words does to it: words that are empty, or the app's own (the words its record was
 * made with), leave it fresh; anything else is the person's, and spoils it.
 */
export function keepFresh(id: string, body: string): void {
  if (!fresh.has(id)) return;
  if (wordsOf(body).trim() === '' || isUntouched(id, body)) return;
  fresh.delete(id);
}
