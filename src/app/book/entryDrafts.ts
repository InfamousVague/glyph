import { frontMatterOffset } from '../core/frontMatter.ts';
import { readStored, writeStored } from '../core/stored.ts';

/**
 * The entries this device made and nobody has written in yet (docs/DESIGN.md §142): what lets one left untouched be
 * taken back.
 *
 * "A note opened and left leaves nothing behind" is the app's promise for a new note (docs/LIBRARY.md): a note with no
 * words is a draft with no file. A template breaks it, since an entry has words from birth - its date, its time - so it
 * is a file at once and a line in its journal. So New entry writes a record here first, before the note or the line
 * (App.tsx `newEntry`), and an entry whose words are still the words it was made with, left, is taken back: the note,
 * its line, and the place still waiting to be written into it (core/location.ts asks `untouchedEntry` before a tag
 * lands). The record is kept on the page's own storage, not in memory, because Android lets a backgrounded WebView go
 * without a word, and the entry must still be taken back at the next launch rather than left with a place written in.
 *
 * On this device only, never synced: another device neither made the entry nor can know whether it is untouched. At
 * most twenty are kept, and none older than a week: an entry that old was never going to be taken back.
 *
 * A leaf, but for the storage and the front matter rule, so core/location.ts can import it without a cycle.
 */

export interface EntryRecord {
  /** The journal it is an entry of. */
  journalId: string;
  title: string;
  /** Its words as they were made, after the front matter: while they are still these, nobody has written in it. */
  words: string;
  /** When it was made. */
  at: number;
}

const KEY = 'glyph-entry-drafts';
const KEEP = 20;
const WEEK_MS = 7 * 24 * 60 * 60_000;

function isRecord(value: unknown): value is EntryRecord {
  if (!value || typeof value !== 'object') return false;
  const record = value as Record<string, unknown>;
  return typeof record.journalId === 'string' && typeof record.title === 'string' && typeof record.words === 'string' && typeof record.at === 'number';
}

/** Every record kept, by the entry's id: none of another build's shape, and none older than a week. */
export function entryRecords(now = Date.now()): Record<string, EntryRecord> {
  const all = readStored<Record<string, unknown>>(KEY, {}, (raw) => (raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as Record<string, unknown>) : null));
  const kept: Record<string, EntryRecord> = {};
  for (const [id, record] of Object.entries(all)) if (isRecord(record) && now - record.at <= WEEK_MS) kept[id] = record;
  return kept;
}

function writeAll(records: Record<string, EntryRecord>): void {
  const newest = Object.entries(records)
    .sort((a, b) => b[1].at - a[1].at)
    .slice(0, KEEP);
  writeStored(KEY, newest.length ? Object.fromEntries(newest) : null);
}

/** Keeps the record of an entry just being made. */
export function rememberEntry(id: string, record: EntryRecord): void {
  writeAll({ ...entryRecords(), [id]: record });
}

export function entryRecord(id: string): EntryRecord | null {
  return entryRecords()[id] ?? null;
}

/** The words an untouched entry is taken as having now: its spoken entry's, which start without the line the words go on from. */
export function setEntryWords(id: string, words: string): void {
  const all = entryRecords();
  const record = all[id];
  if (!record) return;
  writeAll({ ...all, [id]: { ...record, words } });
}

/** The entry is the person's now, or gone: nothing is kept for it. */
export function forgetEntry(id: string): void {
  const all = entryRecords();
  if (!(id in all)) return;
  delete all[id];
  writeAll(all);
}

/** A note's words after its front matter: what an entry's record compares. */
export function wordsOf(body: string): string {
  return body.slice(frontMatterOffset(body));
}

/**
 * Whether the entry `id` is still as this device made it: a record, words that are still the record's (a place written
 * into its front matter is not a word), and no recording, pin or archive, each of which is a person's doing.
 */
export function untouchedEntry(id: string, body: string, note?: { recordingMs?: number | null; starred?: boolean; archivedAt?: number | null }): boolean {
  const record = entryRecord(id);
  if (!record) return false;
  if (note?.recordingMs || note?.starred || note?.archivedAt) return false;
  return wordsOf(body).trim() === record.words.trim();
}
