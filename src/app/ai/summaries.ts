import { renderNote } from '../capture/markdown.ts';
import { onRefineHold, refineHeld, refinePending } from '../capture/refine.ts';
import { generate, listModels, type Run } from '../core/ai.ts';
import { externalStore } from '../core/externalStore.ts';
import { failureText } from '../core/failure.ts';
import { preferences } from '../core/preferences.ts';
import { readStored, writeStored } from '../core/stored.ts';
import { getNote, noteTitle, updateNote } from '../core/store.ts';
import { syncNow, syncSettled } from '../core/sync/engine.ts';
import { isTauri } from '../core/tauri.ts';
import { isTrashed } from '../core/trash.ts';
import { RECORDING_NOTES_PROMPT, RECORDING_SUMMARY_PROMPT, recordingNotesBudget, recordingSummaryBudget, TEMPERATURE } from '../format/prompt.ts';
import { modelFor, presentIds } from './available.ts';
import { anyRunning, type RunHandle } from './runs.ts';
import { keepSummary, readSummary } from './summaryKeep.ts';
import { carryTicked, shapeSummary, SUMMARY_HEADING, summarySection, transcriptPieces, withSummary } from './summaryText.ts';

/**
 * The summary queue: a recording written up on the phone, in the background, into a section under the note's title
 * (docs/DESIGN.md §127 section 2). Matt: "I'm going to start recording meetings and stuff and letting the audio be
 * transcribed then summarized by AI so I get summarized recording notes automatically". He chose the on-device model
 * for it, after the better words, and never the server.
 *
 * A job a note, kept in localStorage on capture/refine.ts's pattern, so one the phone did not get to runs at the next
 * launch. A job is queued for a meeting when its transcript is there (section 3, which nothing makes yet: the
 * 'meeting' kind is typed and handled and no path enqueues it), from the tape strip's Summarize word
 * (tapes/NoteTape.tsx), and for a long voice note when the setting says so (capture/CaptureScreen.tsx). Never again
 * on its own: a summary is remade only on purpose.
 *
 * What it reads is the tape, not the note: the recording's phrases as the note keeps them, commands left out.
 * A transcript past twenty thousand characters goes in pieces (ai/summaryText.ts `transcriptPieces`), each piece's
 * notes checkpointed in the job so a kill after four of five starts at the fifth, and the joined notes then go
 * through the summary prompt.
 *
 * The holds, in order: the recorder or a review up (`refineHeld`); the note's better words still to come
 * (`refinePending`, before the run and again before the write); a note's own run going (`anyRunning`, three seconds);
 * a note in the trash, which gets no write-up and whose job waits; a sync in flight. The recorder wins the cores:
 * when it comes up, a run in flight is cancelled and its job left queued, uncounted, and the hold is read again
 * after every wait and before every generation, so one that arrives mid-job starts nothing more. That cut is the
 * queue's own and is told from a stop by the person (the strip's Stop, the scene's, a run of their own on the note):
 * a job the person stopped is theirs to ask for again, and is dropped. A job is marked `started` before it runs,
 * and one found `started` at launch counts that as one try, so a run that kills the app cannot kill it at every
 * launch; three tries and it is `failed`, for the shelf's Try again. No model on the phone: the job waits, looks
 * again in a minute, and the shelf says "Needs a model".
 *
 * Two writers. A closed note is written plain by `withSummary`, through `generate()`, since a background write can
 * make no marks. An open note lands through its editor, the one writer of an open note (§126): the note screen
 * registers a starter (`openForSummaries`), the queue hands it the words, and the summary is a run of ai/runs.ts
 * whose lines land as tracked changes with Keep and Revert. A note opened while its generation ran is handed the
 * finished answer instead, and the editor lands it at once: the plain write never lands under an open editor, whose
 * next save would conflict and every save of that visit after it be dropped (editor/useNoteSaving.ts). Both place
 * and shape the section by ai/summaryText.ts's rules. On success the list is refreshed and, with the page visible,
 * a toast says "Summarized" with Open (shell/useHousekeeping.ts); not for a native job, whose notification already
 * said it (sections 4 and 5, generation 20: a native job waits here for its result, which nothing delivers yet).
 *
 * Only in Tauri: a browser has no summariser, and shows what synced.
 */

export type SummaryKind = 'meeting' | 'recording';

export interface SummaryJob {
  /** The note. */
  id: string;
  kind: SummaryKind;
  tries: number;
  /** Set as the run starts and cleared as it ends however it ends: found set at launch, the run killed the app. */
  started?: boolean;
  /** The notes on each finished piece of a long transcript, in order: the checkpoint. */
  pieces?: string[];
  /** The model's finished answer, kept when the write did not go through, so the next kick writes without asking again. */
  text?: string;
  /** The write-up runs natively, with the app closed (§127 section 4): the job waits here for its result. */
  native?: boolean;
  /** The queue gave up: three tries. Try again clears it. */
  failed?: boolean;
  /** Replace the section the note has even if it was edited: the strip's Replace was tapped. */
  replace?: boolean;
}

export interface SummariesState {
  /** Notes whose page summary is queued or running. */
  pending: ReadonlySet<string>;
  /** Notes a native write-up is running for (§127 section 4). */
  native: ReadonlySet<string>;
  /** Notes whose summary the queue gave up on, for the caption's Try again. */
  failed: ReadonlySet<string>;
  /** Notes whose job waits for a language model that is not on the phone. */
  needsModel: ReadonlySet<string>;
}

/** What the note screen gives the queue for a note it has open: the summary as a run in its editor (editor/useNoteAi.ts). */
export type SummaryStarter = (ask: SummaryAsk) => SummaryStarted;

export interface SummaryAsk {
  /** The recording's words, or the notes on its parts joined. */
  words: string;
  /** The line before the words, when they are notes on the parts of one recording. */
  context?: string;
  model: string;
  maxTokens: number;
  /** Replace the section the note has even if it was edited. */
  replace: boolean;
  /** The model's finished answer, when the queue already has it: landed as it is, the model not asked again. */
  text?: string;
}

/** A run in the editor to follow, or the section landed at once from an answer already in hand, or why not. */
export type SummaryStarted = { ok: true; handle: RunHandle } | { ok: true; landed: string } | { ok: false; reason: 'edited' | 'nothing' | string };

/** The line before a piece's words, and before the joined notes: the summary's length is measured against the recording, not the notes. */
export const PIECE_CONTEXT = (n: number, m: number) => `Part ${n} of ${m} of one recording.`;
export const NOTES_CONTEXT = (words: number) => `These are notes on the parts of one recording, in order. The recording itself was about ${words.toLocaleString('en')} words: the summary's length is measured against that, not against these notes.`;

const QUEUE_KEY = 'glyph-summary-queue';
const MAX_TRIES = 3;
/** How long to wait before trying again after "busy", "cancelled" or a failure. */
const RETRY_MS = 20_000;
/** How long to wait before looking for a model again. */
const NO_MODEL_MS = 60_000;
/** How long to wait for a note's own run to end. */
const RUN_WAIT_MS = 3000;

// ---- the queue -------------------------------------------------------------------------

function readQueue(): SummaryJob[] {
  return readStored(QUEUE_KEY, [], (value) => (Array.isArray(value) ? (value as SummaryJob[]).filter((j) => j && typeof j.id === 'string') : []));
}

function writeQueue(jobs: SummaryJob[]): void {
  writeStored(QUEUE_KEY, jobs);
}

function patch(id: string, change: Partial<SummaryJob>): void {
  writeQueue(readQueue().map((j) => (j.id === id ? { ...j, ...change } : j)));
}

// ---- what the shelf and the strip see ----------------------------------------------------

const NONE: SummariesState = { pending: new Set(), native: new Set(), failed: new Set(), needsModel: new Set() };
const summaries = externalStore<SummariesState>(NONE, { server: () => NONE });
/** Notes whose job is waiting for a model, said by the last look. */
const needsModel = new Set<string>();

function publish(): void {
  const queue = readQueue();
  summaries.set({
    pending: new Set(queue.filter((j) => !j.failed && !j.native).map((j) => j.id)),
    native: new Set(queue.filter((j) => j.native && !j.failed).map((j) => j.id)),
    failed: new Set(queue.filter((j) => j.failed).map((j) => j.id)),
    needsModel: new Set(queue.filter((j) => !j.failed && needsModel.has(j.id)).map((j) => j.id)),
  });
}

export const useSummaries = summaries.use;

/** The state as it is now, for callers outside React and for tests. */
export function summariesNow(): SummariesState {
  return summaries.get();
}

// ---- running -------------------------------------------------------------------------------

let running = false;
let paused = false;
let timer = 0;
let onChanged: (() => void) | null = null;
let onSummarized: ((done: { id: string; title: string }) => void) | null = null;
/** The generation or run in flight, so the recorder can cancel it. */
let activeRun: Run | null = null;
let activeHandle: RunHandle | null = null;
/** The run in flight was cut by the queue itself, for the recorder. A stop from anywhere else is the person's. */
let cut = false;
/** The notes open in an editor, each with the way to run a summary in it. */
const starters = new Map<string, SummaryStarter>();

/** Ask for a summary of the note's tape. Runs once the holds are clear; a job already queued for the note is replaced. */
export function enqueueSummary(id: string, kind: SummaryKind, options: { native?: boolean; replace?: boolean } = {}): void {
  if (!isTauri()) return;
  const queue = readQueue().filter((j) => j.id !== id);
  queue.push({ id, kind, tries: 0, ...(options.native ? { native: true } : {}), ...(options.replace ? { replace: true } : {}) });
  writeQueue(queue);
  publish();
  kick();
}

/** Try again, from the shelf's caption: the note's job back in the queue with its tries reset. */
export function retrySummary(id: string): void {
  const queue = readQueue();
  if (!queue.some((j) => j.id === id)) return;
  writeQueue(queue.map((j) => (j.id === id ? { ...j, tries: 0, failed: false, started: false } : j)));
  publish();
  kick();
}

/** A note deleted for good: its job goes with it. Trashed, the job waits. */
export function dropSummary(id: string): void {
  const queue = readQueue();
  needsModel.delete(id);
  if (!queue.some((j) => j.id === id)) return;
  writeQueue(queue.filter((j) => j.id !== id));
  publish();
}

/** Whether the note has a job queued or running. */
export function summaryPending(id: string): boolean {
  return readQueue().some((j) => j.id === id && !j.failed);
}

/**
 * No run starts while `on`, and the one in flight is cancelled and its job left queued, uncounted: the recorder wins
 * the cores. Let go, the queue looks again a moment later.
 */
export function pauseSummaries(on: boolean): void {
  if (paused === on) return;
  paused = on;
  if (on) {
    if (activeRun || activeHandle) cut = true;
    activeRun?.cancel();
    activeHandle?.cancel();
  } else kick(1500);
}

onRefineHold(pauseSummaries);

/**
 * A note open in its editor: its summary, when its turn comes, is handed here and lands as a run of the editor's.
 * Given null as the note is left.
 */
export function openForSummaries(id: string, starter: SummaryStarter | null): void {
  if (starter) starters.set(id, starter);
  else starters.delete(id);
}

/**
 * Wire the runner to the app: called once, with what to do when a note's words changed, and what to say once a
 * summary has landed with the page visible.
 */
export function startSummaries(changed: () => void, summarized: (done: { id: string; title: string }) => void): () => void {
  onChanged = changed;
  onSummarized = summarized;
  // A job found started was running when the app stopped: that run counts as a try, and its third fails the job.
  const queue = readQueue();
  if (queue.some((j) => j.started)) {
    writeQueue(queue.map((j) => (j.started ? { ...j, started: false, tries: j.tries + 1, ...(j.tries + 1 >= MAX_TRIES ? { failed: true } : {}) } : j)));
  }
  publish();
  const onVisible = () => {
    if (document.visibilityState === 'visible') kick(2000);
  };
  document.addEventListener('visibilitychange', onVisible);
  kick(4000);
  return () => {
    document.removeEventListener('visibilitychange', onVisible);
    window.clearTimeout(timer);
    onChanged = null;
    onSummarized = null;
  };
}

function kick(delay = 0): void {
  window.clearTimeout(timer);
  timer = window.setTimeout(() => void runNext(), delay);
}

/** Whether any job could still run, for the kick after one. */
function owed(): boolean {
  return readQueue().some((j) => !j.failed && !j.native);
}

/**
 * The first job in the queue the holds let through, if the phone can take it now. What comes next is decided by how
 * it went: the next job half a second after one that finished, and this one again after a wait when the model was
 * not there, the phone was busy, or the run failed.
 */
async function runNext(): Promise<void> {
  if (running || paused || !isTauri() || typeof document === 'undefined' || document.visibilityState !== 'visible') return;
  // The hold read at its source: the same answer as `paused`, which follows it and is what the cancel needs.
  if (refineHeld()) return;
  const queue = readQueue();
  // The first that is not failed, not native, not in the trash and not waiting for its better words.
  const job = queue.find((j) => !j.failed && !j.native && !isTrashed(j.id) && !refinePending(j.id));
  if (!job) {
    // A job held only by its better words looks again once they have come.
    if (queue.some((j) => !j.failed && !j.native && !isTrashed(j.id))) kick(RETRY_MS);
    return;
  }
  if (anyRunning()) {
    kick(RUN_WAIT_MS);
    return;
  }
  running = true;
  let next = 500;
  try {
    await syncSettled();
    const model = modelFor(presentIds(await listModels().catch(() => [])), preferences().formatModel);
    if (!model) {
      needsModel.add(job.id);
      publish();
      next = NO_MODEL_MS;
      return;
    }
    if (needsModel.delete(job.id)) publish();
    patch(job.id, { started: true });
    cut = false;
    const outcome = await summarize(job, model);
    if (outcome === 'written') {
      finish(job);
      onChanged?.();
    } else if (outcome === 'left') finish(job);
    else next = RETRY_MS;
  } catch (error) {
    const message = failureText(error);
    if (paused || /busy|cancelled/i.test(message)) next = RETRY_MS;
    else {
      console.warn('[glyph] the summary did not come:', message);
      const tries = job.tries + 1;
      patch(job.id, { tries, ...(tries >= MAX_TRIES ? { failed: true } : {}) });
    }
  } finally {
    if (readQueue().some((j) => j.id === job.id && j.started)) patch(job.id, { started: false });
    running = false;
    activeRun = null;
    activeHandle = null;
    publish();
    if (owed()) kick(next);
  }
}

type Outcome = 'written' | 'left' | 'wait';

/**
 * One job: the tape's words, in pieces when they are many, through the model, and the section into the note - by
 * its editor when the note is open, plain when it is closed. 'left' is a section the person edited that an automatic
 * job must not touch, a note with nothing to summarise, or a run the person stopped; 'wait' is a write that did not
 * go through this pass, or a run the recorder cut.
 */
async function summarize(job: SummaryJob, model: string): Promise<Outcome> {
  const note = await getNote(job.id);
  if (!note) return 'left';
  const plain = renderNote(note.segments ?? []).plain;
  if (!plain.trim()) return 'left';
  const pieces = transcriptPieces(plain);
  const budget = recordingSummaryBudget(plain.length);
  let words = plain;
  let context: string | undefined;
  if (pieces.length > 1) {
    const notes = [...(job.pieces ?? [])].slice(0, pieces.length);
    for (let n = notes.length; n < pieces.length; n += 1) {
      const piece = pieces[n]!;
      const output = await run({ model, system: RECORDING_NOTES_PROMPT, prompt: `${PIECE_CONTEXT(n + 1, pieces.length)}\n\n${piece}`, maxTokens: recordingNotesBudget(piece.length) });
      notes.push(output.trim());
      // Each finished piece is checkpointed, so a kill after four of five starts at the fifth.
      patch(job.id, { pieces: [...notes] });
    }
    words = notes.join('\n\n');
    context = NOTES_CONTEXT(plain.split(/\s+/).filter(Boolean).length);
  }
  const ask: SummaryAsk = { words, context, model, maxTokens: budget, replace: Boolean(job.replace) };
  const starter = starters.get(job.id);
  if (starter) return throughEditor(job, starter, job.text === undefined ? ask : { ...ask, text: job.text });
  const text = job.text ?? (await run({ model, system: RECORDING_SUMMARY_PROMPT, prompt: context ? `${context}\n\n${words}` : words, maxTokens: budget }));
  patch(job.id, { text });
  return write(job, text, ask, note.recordingMs ?? 0);
}

/** One generation, cancellable by the recorder, and not started once it is up. */
async function run(options: { model: string; system: string; prompt: string; maxTokens: number }): Promise<string> {
  if (paused) throw new Error('cancelled');
  activeRun = generate({ ...options, temperature: TEMPERATURE, onProgress: () => undefined });
  try {
    return (await activeRun.done).text;
  } finally {
    activeRun = null;
  }
}

/**
 * The summary as a run in the note's editor: the lines land there, and the section as it landed is what is kept -
 * the run's text less the blank line it may open with. An answer the queue already had is landed at once. A run cut
 * by the recorder leaves its job waiting, to land over whatever half of the section landed (`replace`, since that
 * half is the app's own); a run the person stopped is left.
 */
async function throughEditor(job: SummaryJob, starter: SummaryStarter, ask: SummaryAsk): Promise<Outcome> {
  if (paused) throw new Error('cancelled');
  const started = starter(ask);
  if (!started.ok) {
    if (started.reason === 'edited' || started.reason === 'nothing') return 'left';
    throw new Error(started.reason);
  }
  let landed: string;
  if ('landed' in started) landed = started.landed;
  else {
    activeHandle = started.handle;
    const state = await started.handle.done;
    activeHandle = null;
    if (state.phase === 'stopped') {
      if (!cut) return 'left';
      patch(job.id, { replace: true });
      return 'wait';
    }
    if (state.phase !== 'done') throw new Error(state.message ?? 'the summary did not come');
    landed = summarySection(state.text ?? '')?.text ?? '';
  }
  const fresh = await getNote(job.id).catch(() => null);
  keepSummary(job.id, { text: landed, model: ask.model, at: Date.now(), forMs: fresh?.recordingMs ?? 0 });
  said(job, fresh?.body ?? '');
  return 'written';
}

/**
 * The section into a closed note, plain: read fresh, the better words checked again, placed and shaped by
 * ai/summaryText.ts, with the ticked to-dos of the section it replaces carried in. A note opened meanwhile is handed
 * the answer for its editor to land instead. A conflict is read again and applied once more, then given up for this
 * pass; the text is kept on the job, so the next kick writes it without asking the model again. Any other failure
 * of the write counts as a try. Sync runs before the read and after the write, so the window in which another
 * device's edit could cross it is seconds.
 */
async function write(job: SummaryJob, text: string, ask: SummaryAsk, recordingMs: number): Promise<Outcome> {
  const shaped = shapeSummary(text);
  // Nothing under the heading (a label alone, say) is nothing to write.
  if (!shaped.section || shaped.section === SUMMARY_HEADING) return 'left';
  await syncNow().catch(() => undefined);
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const note = await getNote(job.id);
    if (!note) return 'left';
    if (refinePending(job.id)) return 'wait';
    // The note was opened while the model wrote: its editor is the one writer now, and lands the answer itself.
    const starter = starters.get(job.id);
    if (starter) return throughEditor(job, starter, { ...ask, text });
    const kept = readSummary(job.id);
    const current = summarySection(note.body, kept?.text ?? null);
    let section = shaped.section;
    if (current) {
      // Never remade behind the person's back: a section that is not the app's is left as it is.
      if (!(kept && kept.text === current.text) && !job.replace) return 'left';
      section = carryTicked(current.text, section);
    }
    const next = withSummary(note.body, section, { title: shaped.title, kept: kept?.text ?? null });
    try {
      await updateNote(job.id, next, note.revision ?? 1);
    } catch (error) {
      // Another writer won: read again. Anything else is the write failing, and a try.
      if (/changed|deleted/i.test(failureText(error))) continue;
      throw error;
    }
    keepSummary(job.id, { text: section, model: ask.model, at: Date.now(), forMs: note.recordingMs ?? recordingMs });
    await syncNow().catch(() => undefined);
    said(job, next);
    return 'written';
  }
  return 'wait';
}

/** "Summarized" with Open, when the page is visible and the job was the page's. */
function said(job: SummaryJob, body: string): void {
  if (job.native || typeof document === 'undefined' || document.visibilityState !== 'visible') return;
  onSummarized?.({ id: job.id, title: noteTitle(body) || 'Untitled' });
}

function finish(job: SummaryJob): void {
  needsModel.delete(job.id);
  writeQueue(readQueue().filter((j) => j.id !== job.id));
  publish();
}
