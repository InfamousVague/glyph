import { externalStore, type ExternalStore } from '../core/externalStore.ts';
import { listenTo } from '../core/events.ts';
import { failureText } from '../core/failure.ts';
import { hasNativeGeneration } from '../core/nativeGeneration.ts';
import { preferences } from '../core/preferences.ts';
import { readStored, writeStored } from '../core/stored.ts';
import { getNote, setNoteRecording, updateNote } from '../core/store.ts';
import { invoke, isTauri } from '../core/tauri.ts';
import { summarySection, withoutSummary, withSummary } from '../ai/summaryText.ts';
import type { Segment } from './markdown.ts';
import type { Placing } from './place.ts';
import { refinedBody, refinedSegments } from './refineText.ts';

/**
 * Better words after the recording: the post-pass.
 *
 * The live transcript comes from a small, fast model so the words keep up with
 * speech. A larger one makes about half as many mistakes but cannot keep up,
 * so it runs afterwards, in the background, over the recording the capture
 * kept (native generation 7): one pass per take, then the note's words are
 * replaced with the better ones - only if the note still reads exactly as Done
 * saved it, because an edit in between is the person's and wins.
 *
 * The queue lives in localStorage, so a pass the phone did not get to (the
 * app was closed, the recorder was opened again) runs on the next launch. One
 * pass at a time, never while the recorder is on screen: both models want the
 * same cores. The first pass downloads the larger model (190 MB); until it is
 * there, notes simply keep their live words. What the note reads as with the
 * better words - commands left out - is refineText.ts.
 *
 * Nor over a note that is open (`holdNote`): the editor's saving must be the only writer of an open note
 * (editor/useNoteSaving.ts), or its next keystroke's save conflicts and every save after it in that visit is dropped.
 * A recording that opens its note at Done (docs/DESIGN.md §126) has its better words land after the note is left.
 *
 * The summary queue (ai/summaries.ts) and the gist runner (format/gist.ts) follow this queue's hold (`onRefineHold`):
 * the recorder wins the cores, so a run of theirs in flight is cancelled the moment it comes up, and their queues
 * look again once it has gone. Told this way round, by a subscription, because the summary queue reads this module
 * (`refineHeld`, `refinePending`) and a module that imported it back would be a cycle. A summary that landed between
 * Done and the better words does not stop the better words: the compare reads both bodies with the app's own section
 * taken off, and the section is carried into the better words (§127 section 2).
 *
 * A job is marked `started` before its pass runs, and a job found `started` at launch counts that as one try, so a
 * pass that kills the app cannot kill it at every launch: three tries and the job is dropped.
 */

export interface RefineJob {
  /** The note. */
  id: string;
  /** Where this take starts on the recording's timeline. */
  fromMs: number;
  /** The recording's whole length after this take. */
  recordingMs: number;
  /** The note's text before this take: empty for a new note. */
  baseBody: string;
  /** What Done saved: the text that must still stand for the words to be replaced. */
  savedBody: string;
  /** Whether the take is the note's first, and so may take a title. */
  titled: boolean;
  /** The phrases before this take, already on the recording's timeline. */
  priorSegments: Segment[];
  /** The tail of the text before the take, so the model continues its casing. */
  promptTail: string;
  /**
   * Stretches of the recording that were commands ("Glyph, add buy milk to
   * HelloTrade"), on the recording's timeline: the better words leave them
   * out, as the live words did. Absent on jobs from before.
   */
  skip?: Array<{ startMs: number; endMs: number }>;
  /**
   * The voice memos a take left (core/clips.ts), each already written as its mark, on the recording's timeline: the
   * better words never heard them - their stretches are in `skip` - so they are put back where they were. A recording
   * no longer makes a memo (docs/DESIGN.md §127), so a new job has none; one queued by a build that still did may.
   */
  clips?: Segment[];
  /** Phrases that were words and then "Glyph": the better words keep what came before the keyword. */
  keywordAt?: Array<{ startMs: number; endMs: number }>;
  /**
   * Where the take's words went in the note (place.ts): into its lists rather than on its end. Absent on jobs from
   * before, and for the end, which is what those always meant.
   */
  placing?: Placing;
  /**
   * The take's own phrases as the live reader kept them, on the recording's timeline: a better phrase that ran a
   * command and what it sent together is replaced by these, so it neither erases the item nor brings the command back.
   * Absent on jobs from before, and on takes the live reader did nothing in.
   */
  live?: Segment[];
  tries: number;
  /** Set as the pass starts and cleared as it ends however it ends: found set at launch, the pass killed the app. */
  started?: boolean;
}

/** The binary generation that has `capture_refine`. */
const REFINE_GENERATION = 7;
const QUEUE_KEY = 'glyph-refine-queue';
const MAX_TRIES = 3;
/** How long to wait before trying again after "busy" or a failure. */
const RETRY_MS = 20_000;

// ---- the queue -------------------------------------------------------------------------

function readQueue(): RefineJob[] {
  return readStored(QUEUE_KEY, [], (value) => (Array.isArray(value) ? (value as RefineJob[]).filter((j) => j && typeof j.id === 'string') : []));
}

/** No storage: the job runs now or not at all. */
function writeQueue(jobs: RefineJob[]): void {
  writeStored(QUEUE_KEY, jobs);
}

// ---- what the screen sees ---------------------------------------------------------------

export interface RefineState {
  /** Notes whose better words are being worked out right now, or waiting their turn. */
  pending: ReadonlySet<string>;
  /** The larger model's download, while one is under way. */
  download: { received: number; total: number } | null;
}

const refining: ExternalStore<RefineState> = externalStore<RefineState>(
  { pending: new Set(), download: null },
  { server: () => refining.get() },
);
function publish(next: Partial<RefineState>): void {
  refining.update((was) => ({ ...was, ...next }));
}
function syncPending(): void {
  publish({ pending: new Set(readQueue().map((j) => j.id)) });
}

export const useRefining = refining.use;

// ---- running -------------------------------------------------------------------------------

/** A screen that wants the cores is up - the recorder, or a review running its own pass: no queued pass starts. */
let held = false;
/** Notes open in the editor, whose passes wait until they are left: the editor is the one writer of an open note. */
const heldNotes = new Set<string>();
let running = false;
let timer = 0;
let onChanged: (() => void) | null = null;
/** Who follows the hold: the summary queue and the gist runner, which stop their runs while it is on. */
const holdListeners = new Set<(on: boolean) => void>();

/** Whether the recorder or a review is up: no background run of any kind starts while one is. */
export function refineHeld(): boolean {
  return held;
}

/** Whether a note's better words are still to come: a pass for it is queued or running. */
export function refinePending(id: string): boolean {
  return readQueue().some((j) => j.id === id);
}

/** Called with `true` as the recorder or a review comes up and `false` as it goes; answers the way to stop listening. */
export function onRefineHold(listener: (on: boolean) => void): () => void {
  holdListeners.add(listener);
  return () => {
    holdListeners.delete(listener);
  };
}

/** Ask for a pass over a finished take. Runs when the recorder has gone and the phone is free. */
export function enqueueRefine(job: Omit<RefineJob, 'tries'>): void {
  if (!isTauri() || !preferences().refine) return;
  const queue = readQueue().filter((j) => j.id !== job.id || j.fromMs !== job.fromMs);
  queue.push({ ...job, tries: 0 });
  writeQueue(queue);
  syncPending();
  kick();
}

/** No queued pass starts while `on`; let go, the queue looks again a moment later. One flag for both screens that hold it. */
function hold(on: boolean): void {
  if (held === on) return;
  held = on;
  holdListeners.forEach((listener) => listener(on));
  if (!on) kick(1500);
}

/** The recorder is on screen (or not): no pass runs while it is. */
export function setRecorderLive(live: boolean): void {
  hold(live);
}

/** A note open (or left): no pass writes it while it is, and the queue looks again a moment after it is left. */
export function holdNote(id: string, on: boolean): void {
  if (on) {
    heldNotes.add(id);
    return;
  }
  heldNotes.delete(id);
  kick(1500);
}

/** A take's pass taken out of the queue: its words were undone, so its better words must not write them back. */
export function dropRefine(id: string, fromMs: number): void {
  const queue = readQueue();
  if (!queue.some((j) => j.id === id && j.fromMs === fromMs)) return;
  writeQueue(queue.filter((j) => !(j.id === id && j.fromMs === fromMs)));
  syncPending();
}

/** Wire the runner to the app: called once, with what to do when a note's words changed. */
export function startRefining(changed: () => void): () => void {
  onChanged = changed;
  // A job found started was running when the app stopped: that pass counts as a try, and its third drops the job.
  const queue = readQueue();
  if (queue.some((j) => j.started)) {
    writeQueue(queue.filter((j) => !j.started || j.tries + 1 < MAX_TRIES).map((j) => (j.started ? { ...j, started: false, tries: j.tries + 1 } : j)));
  }
  syncPending();
  const onVisible = () => {
    if (document.visibilityState === 'visible') kick(2000);
  };
  document.addEventListener('visibilitychange', onVisible);
  kick(4000);
  return () => {
    document.removeEventListener('visibilitychange', onVisible);
    window.clearTimeout(timer);
    onChanged = null;
  };
}

function kick(delay = 0): void {
  window.clearTimeout(timer);
  timer = window.setTimeout(() => void runNext(), delay);
}

async function canRefine(): Promise<boolean> {
  if (!isTauri() || !preferences().refine) return false;
  return hasNativeGeneration(REFINE_GENERATION);
}

interface ModelStatus {
  present: boolean;
  bytes: number;
}

/** The larger model, downloaded on first use with its progress shown. */
async function ensureRefineModel(): Promise<boolean> {
  const status = await invoke<ModelStatus>('capture_refine_model_status').catch(() => null);
  if (!status) return false;
  if (status.present) return true;
  // Local only: the better words wait until the model is on the phone.
  if (preferences().localOnly) return false;
  publish({ download: { received: 0, total: status.bytes } });
  const unlisten = await listenTo<{ receivedBytes: number; totalBytes: number }>('capture://refine-model-progress', (progress) =>
    publish({ download: { received: progress.receivedBytes, total: progress.totalBytes } }),
  );
  try {
    const fetched = await invoke<ModelStatus>('capture_fetch_refine_model');
    return fetched.present;
  } catch (error) {
    console.warn('[glyph] the larger voice model did not download:', error);
    return false;
  } finally {
    unlisten();
    publish({ download: null });
  }
}

/**
 * The first job in the queue, if the phone can take it now. What comes next is decided by how this one went: the next
 * job half a second after one that finished or was given up on, and this one again after a wait when the model was
 * not there or the pass failed. Each outcome picks its one wait, and the runner is kicked once, after it: a phone
 * without the larger model - Local only on, say - that was kicked again at the half-second would ask for the model
 * twice a second for as long as the app stayed open.
 */
async function runNext(): Promise<void> {
  if (running || held) return;
  const queue = readQueue();
  // The first whose note is not open: an open note's pass waits until it is left.
  const job = queue.find((j) => !heldNotes.has(j.id));
  if (!job) return;
  if (!(await canRefine())) return;
  running = true;
  let next = 500;
  try {
    if (!(await ensureRefineModel())) {
      next = RETRY_MS * 3;
      return;
    }
    mark(job, true);
    const refined = await invoke<Segment[]>('capture_refine', { id: job.id, fromMs: job.fromMs, promptTail: job.promptTail });
    await apply(job, refined);
    finish(job);
    onChanged?.();
  } catch (error) {
    const message = failureText(error);
    if (/busy|cancelled/i.test(message)) {
      next = RETRY_MS;
    } else {
      console.warn('[glyph] the better words did not come:', message);
      if (job.tries + 1 >= MAX_TRIES) finish(job);
      else {
        writeQueue(readQueue().map((j) => (j.id === job.id && j.fromMs === job.fromMs ? { ...j, tries: j.tries + 1 } : j)));
        next = RETRY_MS;
      }
    }
  } finally {
    mark(job, false);
    running = false;
    if (readQueue().length) kick(next);
  }
}

/** The job's `started` flag, written through to the queue while the job is still in it. */
function mark(job: RefineJob, started: boolean): void {
  const queue = readQueue();
  if (!queue.some((j) => j.id === job.id && j.fromMs === job.fromMs && Boolean(j.started) !== started)) return;
  writeQueue(queue.map((j) => (j.id === job.id && j.fromMs === job.fromMs ? { ...j, started } : j)));
}

/**
 * The better words go in only if the note still reads as Done left it - the app's own summary section aside, which
 * may have landed since and is carried into the better words as it stands; the better phrases go in either way.
 */
async function apply(job: RefineJob, refined: Segment[]): Promise<void> {
  if (!refined.length) return;
  const note = await getNote(job.id);
  if (!note) return;
  if (withoutSummary(note.body) === withoutSummary(job.savedBody)) {
    const section = summarySection(note.body);
    const better = refinedBody(job, refined);
    await updateNote(job.id, section ? withSummary(withoutSummary(better), section.text) : better, note.revision ?? 1).catch(() => null);
  }
  await setNoteRecording(job.id, job.recordingMs, refinedSegments(job, refined)).catch(() => null);
}

function finish(job: RefineJob): void {
  writeQueue(readQueue().filter((j) => !(j.id === job.id && j.fromMs === job.fromMs)));
  syncPending();
}

// ---- listening again for a review ---------------------------------------------------------

/**
 * The review after a recording (ai/review.ts) runs this take's pass itself, now,
 * and shows its progress instead of letting the queue do it later: the
 * careful words are what the fast ones are checked against. Answers the
 * better phrases, commands included (the review compares like with like), or
 * null when this phone cannot listen again: an old binary, better words
 * switched off, or the larger model not there and not fetched.
 */
export async function listenAgain(job: Omit<RefineJob, 'tries'>, onPercent: (percent: number) => void): Promise<Segment[] | null> {
  if (!(await canRefine())) return null;
  if (!(await ensureRefineModel())) return null;
  const unlisten = await listenTo<{ id: string; percent: number }>('capture://refine-progress', (progress) => {
    if (progress.id === job.id) onPercent(progress.percent);
  });
  try {
    return await invoke<Segment[]>('capture_refine', { id: job.id, fromMs: job.fromMs, promptTail: job.promptTail });
  } finally {
    unlisten();
  }
}

/** The recording's phrases after a review: the better ones, commands left out, for the tape's transcript. */
export async function keepBetterPhrases(job: Omit<RefineJob, 'tries'>, refined: readonly Segment[]): Promise<void> {
  await setNoteRecording(job.id, job.recordingMs, refinedSegments({ ...job, tries: 0 }, refined)).catch(() => null);
}

/** No queued pass runs while a review is on screen: the review's own pass and its model want the cores. */
export function holdRefining(on: boolean): void {
  hold(on);
}
