import { useSyncExternalStore } from 'react';
import { externalStore } from '../core/externalStore.ts';
import { readStoredShared, writeStored } from '../core/stored.ts';
import type { RunKind } from './kinds.ts';
import { noteSheet, sheetOf, type Sheet } from './noteSheet.ts';

/**
 * What the AI did to each note: the run log.
 *
 * Matt chose a log in the strip over a chat thread: each run, what was asked,
 * which model, how long, what came of it, and Undo for a run that changed
 * the note. Kept on the page under one key, per note, the newest first and
 * at most a handful each (a note is asked about a few times a day, not a few
 * hundred), beside the home page's gists in `glyph-ai-results`; moving it into
 * the store is a native change for a later APK. A reset clears the key with
 * every other `glyph-` one (core/reset.ts).
 *
 * A run that changed the note keeps the note as it was before and after, so
 * Undo can put the words back exactly - and only while the note still reads
 * as the run left it, which the screen checks before it does.
 */

export type RunOutcome = 'done' | 'stopped' | 'failed';

export interface RunRecord {
  id: string;
  noteId: string;
  kind: RunKind;
  /** The words the person gave, for a kind that takes some; null for the named kinds. */
  instruction: string | null;
  model: string;
  /** When it started, in ms since the epoch. */
  at: number;
  /** How long it took. */
  ms: number;
  outputTokens: number;
  outcome: RunOutcome;
  /** Why it failed, for a run that did. */
  message: string | null;
  truncated: boolean;
  /** The note before the run's words landed and after, for a run that changed it; absent for one that only wrote on the side. */
  before?: string;
  after?: string;
}

const KEY = 'glyph-ai-log';
/** The most runs kept per note. */
const MOST = 8;

/** Counts the writes, so a screen showing a note's log reads it again after each. */
const written = externalStore(0);

/**
 * Per note, its runs newest first. Read shared (core/stored.ts `readStoredShared`), so a read parses only when the
 * text has changed - which is also what keeps a note's log the same array between writes, as a store snapshot has to
 * be.
 */
const sheet = noteSheet<RunRecord[]>(
  () => readStoredShared<Sheet<RunRecord[]>>(KEY, {}, sheetOf),
  (value) => {
    writeStored(KEY, value);
    written.update((n) => n + 1);
  },
);

/** A run's record kept, newest first; the same id again replaces its earlier record. */
export function recordRun(record: RunRecord): void {
  sheet.update(record.noteId, (mine) => [record, ...(mine ?? []).filter((r) => r.id !== record.id)].slice(0, MOST));
}

/** One run's record changed, if the note's log has it; otherwise nothing is written. */
function changeRecord(noteId: string, runId: string, fn: (record: RunRecord) => RunRecord): void {
  sheet.update(noteId, (mine) => (mine?.some((r) => r.id === runId) ? mine.map((r) => (r.id === runId ? fn(r) : r)) : mine));
}

/** The run changed the note: the words before and after go on its record, for Undo. */
export function recordChange(noteId: string, runId: string, before: string, after: string): void {
  changeRecord(noteId, runId, (r) => ({ ...r, before, after }));
}

/** A run's change was undone: its record no longer offers it. */
export function recordUndone(noteId: string, runId: string): void {
  changeRecord(noteId, runId, ({ before: _before, after: _after, ...rest }) => rest);
}

/** No runs, the one array: a store snapshot has to be the same value while nothing has changed, or React re-reads it forever. */
const NONE: RunRecord[] = [];

/** A note's runs, newest first. */
export function runsOf(noteId: string): RunRecord[] {
  return sheet.read()[noteId] ?? NONE;
}

/** A note is gone: so is its log. */
export function forgetRuns(noteId: string): void {
  sheet.forget(noteId);
}

/** A note's log as the screen sees it, following every record written. */
export function useRunLog(noteId: string): RunRecord[] {
  return useSyncExternalStore(
    written.subscribe,
    () => runsOf(noteId),
    () => NONE,
  );
}
