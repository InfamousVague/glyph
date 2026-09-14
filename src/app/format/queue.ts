import { listModels } from '../core/ai.ts';
import { preferences } from '../core/preferences.ts';
import { getNote } from '../core/store.ts';
import { invoke, isTauri } from '../core/tauri.ts';
import { isRunning, noteHash, passesFor, revisionPasses, runPipeline } from './pipeline.ts';

/**
 * Formatting in the background: the queue.
 *
 * A note that has just been spoken is formatted without being asked, so its
 * Formatted view is usually ready before it is opened - the same shape as the
 * whisper post-pass in capture/refine.ts, and run after it: a note whose
 * better words are still being worked out waits, or the draft would be
 * written from the live words and replaced under it a minute later.
 *
 * The queue lives in localStorage, so a note the phone did not get to runs on
 * the next launch. One note at a time, never while the recorder is on screen
 * (`setFormattingPaused`, called where the recorder marks itself live) and
 * never while the app is hidden: the model wants the same cores as speech,
 * and a phone in a pocket should not warm itself formatting.
 */

const QUEUE_KEY = 'glyph-format-queue';
const REFINE_QUEUE_KEY = 'glyph-refine-queue';
/** The binary generation that has `ai_generate`. */
const FORMAT_GENERATION = 10;
const MAX_TRIES = 3;
const RETRY_MS = 30_000;

interface Job {
  id: string;
  tries: number;
}

function readQueue(): Job[] {
  try {
    const value = JSON.parse(localStorage.getItem(QUEUE_KEY) ?? '[]') as unknown;
    return Array.isArray(value) ? (value as Job[]).filter((j) => j && typeof j.id === 'string') : [];
  } catch {
    return [];
  }
}

function writeQueue(jobs: Job[]): void {
  try {
    localStorage.setItem(QUEUE_KEY, JSON.stringify(jobs));
  } catch {
    // No storage: the job runs now or not at all.
  }
}

/** Whether the whisper post-pass still has this note: its words are about to change. */
function refinePending(id: string): boolean {
  try {
    const value = JSON.parse(localStorage.getItem(REFINE_QUEUE_KEY) ?? '[]') as unknown;
    return Array.isArray(value) && value.some((j) => j && typeof j === 'object' && (j as { id?: unknown }).id === id);
  } catch {
    return false;
  }
}

let paused = false;
let running = false;
let timer = 0;
let onChanged: (() => void) | null = null;
let generation: number | null = null;

/** Ask for the note to be formatted when the phone is free. */
export function enqueueFormat(id: string): void {
  if (!isTauri()) return;
  const queue = readQueue().filter((j) => j.id !== id);
  queue.push({ id, tries: 0 });
  writeQueue(queue);
  kick(2000);
}

/** The recorder is on screen (or not): nothing runs while it is. */
export function setFormattingPaused(on: boolean): void {
  paused = on;
  if (!on) kick(3000);
}

/** Wire the runner to the app: called once, with what to do when a note's formatted text landed. */
export function startFormatting(changed: () => void): () => void {
  onChanged = changed;
  const onVisible = () => {
    if (document.visibilityState === 'visible') kick(2500);
  };
  document.addEventListener('visibilitychange', onVisible);
  kick(6000);
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

async function canFormat(): Promise<boolean> {
  if (!isTauri()) return false;
  generation ??= await invoke<{ nativeGeneration?: number }>('ota_status').then(
    (status) => status.nativeGeneration ?? 0,
    () => 0,
  );
  return generation >= FORMAT_GENERATION;
}

async function runNext(): Promise<void> {
  if (running || paused || document.visibilityState !== 'visible') return;
  const job = readQueue()[0];
  if (!job) return;
  if (!(await canFormat())) return;
  if (refinePending(job.id) || isRunning(job.id)) {
    kick(RETRY_MS);
    return;
  }
  running = true;
  try {
    const note = await getNote(job.id);
    if (!note || !note.body.trim()) {
      finish(job);
      return;
    }
    const present = (await listModels()).filter((m) => m.present).map((m) => m.id);
    const passes = passesFor(present, preferences().formatModel);
    if (!passes.length) {
      // No model on the phone yet: the note waits for one, without retrying in a loop.
      kick(RETRY_MS * 4);
      return;
    }
    const owed = revisionPasses({ formatted: note.formatted, formattedFor: note.formattedFor, formattedModel: note.formattedModel }, noteHash(job.id, note.body), passes);
    if (owed.length) {
      await runPipeline(job.id, note.body, owed);
      onChanged?.();
    }
    finish(job);
  } catch (error) {
    console.warn('[glyph] background formatting did not finish:', error);
    if (job.tries + 1 >= MAX_TRIES) finish(job);
    else {
      writeQueue(readQueue().map((j) => (j.id === job.id ? { ...j, tries: j.tries + 1 } : j)));
      kick(RETRY_MS);
    }
  } finally {
    running = false;
    if (readQueue().length) kick(1000);
  }
}

function finish(job: Job): void {
  writeQueue(readQueue().filter((j) => j.id !== job.id));
}
