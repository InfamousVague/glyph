import { useSyncExternalStore } from 'react';
import type { RunKind } from './kinds.ts';

/**
 * What the AI did to each note: the run log.
 *
 * Matt chose a log in the strip over a chat thread: each run, what was asked,
 * which model, how long, what came of it, and Undo for a run that changed
 * the note. Kept on the page under one key, per note, the newest first and
 * at most a handful each (a note is asked about a few times a day, not a few
 * hundred), beside the summaries in `glyph-ai-results`; moving it into the
 * store is a native change for a later APK. The key is on the reset list.
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

type Sheet = Record<string, RunRecord[]>;

/** The sheet as last parsed, with the text it came from, so a read parses only when the text has changed. */
let parsed: { raw: string; sheet: Sheet } | null = null;
const listeners = new Set<() => void>();

function readSheet(): Sheet {
  try {
    const raw = localStorage.getItem(KEY) ?? '{}';
    if (parsed && parsed.raw === raw) return parsed.sheet;
    const value = JSON.parse(raw) as unknown;
    const sheet = value && typeof value === 'object' && !Array.isArray(value) ? (value as Sheet) : {};
    parsed = { raw, sheet };
    return sheet;
  } catch {
    return {};
  }
}

function writeSheet(sheet: Sheet): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(sheet));
  } catch {
    // No storage: the log holds for this run of the app and not beyond it.
  }
  parsed = null;
  listeners.forEach((l) => l());
}

/** A run's record kept, newest first; the same id again replaces its earlier record. */
export function recordRun(record: RunRecord): void {
  const sheet = { ...readSheet() };
  const mine = (sheet[record.noteId] ?? []).filter((r) => r.id !== record.id);
  sheet[record.noteId] = [record, ...mine].slice(0, MOST);
  writeSheet(sheet);
}

/** The run changed the note: the words before and after go on its record, for Undo. */
export function recordChange(noteId: string, runId: string, before: string, after: string): void {
  const sheet = { ...readSheet() };
  const mine = sheet[noteId];
  if (!mine?.some((r) => r.id === runId)) return;
  sheet[noteId] = mine.map((r) => (r.id === runId ? { ...r, before, after } : r));
  writeSheet(sheet);
}

/** A run's change was undone: its record no longer offers it. */
export function recordUndone(noteId: string, runId: string): void {
  const sheet = { ...readSheet() };
  const mine = sheet[noteId];
  if (!mine?.some((r) => r.id === runId)) return;
  sheet[noteId] = mine.map((r) => {
    if (r.id !== runId) return r;
    const { before: _before, after: _after, ...rest } = r;
    return rest;
  });
  writeSheet(sheet);
}

/** No runs, the one array: a store snapshot has to be the same value while nothing has changed, or React re-reads it forever. */
const NONE: RunRecord[] = [];

/** A note's runs, newest first. */
export function runsOf(noteId: string): RunRecord[] {
  return readSheet()[noteId] ?? NONE;
}

/** A note is gone: so is its log. */
export function forgetRuns(noteId: string): void {
  const sheet = { ...readSheet() };
  if (!(noteId in sheet)) return;
  delete sheet[noteId];
  writeSheet(sheet);
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/** A note's log as the screen sees it, following every record written. */
export function useRunLog(noteId: string): RunRecord[] {
  return useSyncExternalStore(
    subscribe,
    () => runsOf(noteId),
    () => NONE,
  );
}
