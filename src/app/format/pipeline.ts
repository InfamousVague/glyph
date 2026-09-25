import { MODELS, type Hardware, type Phase } from '../core/ai.ts';
import { modelFor } from '../ai/available.ts';
import { startRun, subscribeRuns, ended as runEnded, type RunState } from '../ai/runs.ts';
import { pluginContextFor, pluginContextVersion } from '../plugins/registry.ts';
import { cleanNote, cleanRewrite } from './clean.ts';
import { bodyHash, tidy, type Kept } from './formatter.ts';
import { protectLinks, restoreLinks } from './links.ts';
import type { Mode } from './modes.ts';
import { budgetFor, promptFor, TEMPERATURE } from './prompt.ts';
import { keepResult } from './results.ts';
import { protectTables, restoreTables } from './tables.ts';

/**
 * The robot's modes, run: one model, one pass, on the engine every AI run
 * shares (ai/runs.ts).
 *
 * This used to be formatting in passes - a quick draft by the smallest model
 * on the phone, then revisions by the bigger ones up to the chosen one - and
 * Matt has since chosen one pass by the chosen model: fastest to the first
 * line, and no draft for the careful model's lines to replace under the
 * person's eyes. `passesFor` keeps its name and its shape (a list of models,
 * the last of which has the last word) so the queue and the Formatted view
 * read as they did, and answers one model: the chosen one when it is on the
 * phone, else what is (ai/available.ts `modelFor`).
 *
 * What this module still owns is the note's preparation and its keeping: the
 * tidy-up before the model (clean.ts), tables and links swapped for tokens it
 * can copy and put back after (tables.ts, links.ts), the hash of the body it
 * was written from, and the result kept per mode (results.ts). The run
 * itself, its streaming, its queue and its log are the engine's; the events
 * here are the engine's, translated for the view and the queue that watch
 * them.
 */

export interface PipelineProgress {
  id: string;
  mode: Mode;
  /** Which pass is running, from 1, of how many. Always 1 of 1 now; kept for the view's words. */
  pass: number;
  passes: number;
  model: string;
  phase: Phase;
  /** The text so far: the lines the model has finished and the one under its pen. */
  text: string;
  promptTokens: number;
  promptTokensDone: number;
  outputTokens: number;
  tokensPerSecond: number;
  elapsedMs: number;
  /** The phone under the model, from a binary that reports it. */
  hardware?: Hardware | null;
}

export interface PassLanded {
  id: string;
  mode: Mode;
  text: string;
  model: string;
  /** The page's hash of the body the pass was written from. */
  hash: number;
  ms: number;
  truncated: boolean;
  /** The model of the pass that follows, or null when this was the last. Always null now. */
  next: string | null;
}

export type PipelineEvent = { kind: 'progress'; progress: PipelineProgress } | { kind: 'landed'; landed: PassLanded } | { kind: 'ended'; id: string; mode: Mode; reason: 'done' | 'stopped' | 'failed'; message?: string };

type Listener = (event: PipelineEvent) => void;

const listeners = new Set<Listener>();
const runs = new Map<string, { cancel: () => void; progress: PipelineProgress | null; done: Promise<void> }>();

export function subscribe(listener: Listener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function publish(event: PipelineEvent): void {
  listeners.forEach((l) => l(event));
}

/** The run in progress for a note, if any. */
export function runningFor(id: string): PipelineProgress | null {
  return runs.get(id)?.progress ?? null;
}

export function isRunning(id: string): boolean {
  return runs.has(id);
}

/** Stops a note's run, if any; resolves once it has ended, so a new one can start. */
export function cancelRun(id: string): Promise<void> {
  const run = runs.get(id);
  if (!run) return Promise.resolve();
  run.cancel();
  return run.done;
}

/**
 * The "model" of a formatted text the person has edited by hand. It sorts
 * above every real model, so no pass revises it: their words stand until the
 * note itself changes, and Redo is the way to ask for the model's again.
 */
export const EDITED = 'edited';

/**
 * The "model" of a formatted text that has been applied to the note: the
 * note's body is now this text, so formatting it again would only chew it
 * over. It sorts above every model, like an edit.
 */
export const APPLIED = 'applied';

/** Bytes of a model, for ordering; a person's edit, an applied text and an unknown id sort last. */
function sizeOf(id: string): number {
  if (id === EDITED || id === APPLIED) return Number.MAX_SAFE_INTEGER;
  return MODELS.find((m) => m.id === id)?.bytes ?? Number.MAX_SAFE_INTEGER;
}

/**
 * The passes for a note: one, by the model that runs here (ai/available.ts
 * `modelFor`) - the chosen one when it is on the phone, else what is. Nothing
 * on the phone is no passes at all.
 */
export function passesFor(present: readonly string[], chosen: string): string[] {
  const model = modelFor(present, chosen);
  return model ? [model] : [];
}

/**
 * What a formatted version was written from: the body, and the version of
 * the context plugins gave with it (plugins/registry.ts: the Projects plugin's
 * briefing), so a note whose project was re-read is formatted again as if it
 * had been edited.
 */
export function noteHash(id: string, body: string): number {
  const version = pluginContextVersion(id);
  return bodyHash(version ? `${body}\u0000project:${version}` : body);
}

/**
 * Whether a note needs formatting, given what it has: nothing kept, kept text
 * from a different body, or a text by a model smaller than the one that would
 * run now. `hash` is the note's `noteHash` now.
 */
export function needsPasses(kept: Kept | null, hash: number, passes: readonly string[]): boolean {
  const last = passes[passes.length - 1];
  if (!last) return false;
  if (!kept?.formatted || kept.formattedFor !== hash) return true;
  return sizeOf(kept.formattedModel ?? '') < sizeOf(last);
}

/**
 * The passes still owed to a note: all of them when nothing fresh is kept,
 * and only the ones by bigger models when a fresh text is - so a text by the
 * 2B is written again by the 4B once the 4B is on the phone, and never by the
 * 2B again.
 */
export function revisionPasses(kept: Kept | null, hash: number, passes: readonly string[]): string[] {
  if (!kept?.formatted || kept.formattedFor !== hash) return [...passes];
  const have = sizeOf(kept.formattedModel ?? '');
  return passes.filter((id) => sizeOf(id) > have);
}

/**
 * The note as the model should see it, and the way back: tables and links go
 * in as tokens the model can copy (tables first, so a link in a cell is
 * inside the block) and come back out in reverse; the tidy-up before
 * (clean.ts) keeps the hash the note's own. A summary may leave a table out.
 */
export function prepareNote(body: string, mode: Mode): { prompt: string; restore: (text: string, final: boolean) => string } {
  const { text: withoutTables, tables } = protectTables(cleanNote(body));
  const { text: prompt, links } = protectLinks(withoutTables);
  const put = (text: string, final: boolean) => restoreTables(restoreLinks(text, links, final), tables, final, mode !== 'summarize');
  return {
    prompt,
    restore: (text, final) => (final ? tidy(cleanRewrite(put(tidy(text), true))) : put(text, false)),
  };
}

function progressOf(run: RunState): PipelineProgress {
  return {
    id: run.noteId,
    mode: run.kind as Mode,
    pass: 1,
    passes: 1,
    model: run.model,
    phase: run.phase === 'queued' ? 'loading' : run.phase === 'stopped' ? 'cancelled' : run.phase === 'failed' ? 'error' : run.phase,
    text: [...run.lines, run.partial].join('\n'),
    promptTokens: run.promptTokens,
    promptTokensDone: run.promptTokensDone,
    outputTokens: run.outputTokens,
    tokensPerSecond: run.tokensPerSecond,
    elapsedMs: run.elapsedMs,
    hardware: run.hardware,
  };
}

/**
 * Runs the pass for a note and keeps its text. A second call for the same
 * note while one runs answers the run already going, whatever its mode: one
 * note, one model at a time. Resolves when the text has landed, or the run
 * was stopped, or it failed.
 */
export function runPipeline(id: string, body: string, passes: readonly string[], mode: Mode = 'format'): Promise<void> {
  const existing = runs.get(id);
  if (existing) return existing.done;
  const model = passes[passes.length - 1];
  if (!model) return Promise.resolve();

  const hash = noteHash(id, body);
  // What plugins know about the note (a linked project's briefing) goes in
  // with it, in the system message, so it is part of the snapshotted prefix.
  const context = pluginContextFor(id) ?? undefined;
  const { prompt, restore } = prepareNote(body, mode);
  const handle = startRun({
    noteId: id,
    kind: mode,
    model,
    system: promptFor(mode),
    context,
    prompt,
    maxTokens: budgetFor(mode, prompt.length),
    temperature: TEMPERATURE,
    restore,
    hash,
  });
  const entry = { cancel: handle.cancel, progress: null as PipelineProgress | null, done: Promise.resolve() };
  const off = subscribeRuns((run) => {
    if (run.id !== handle.id || runEnded(run)) return;
    entry.progress = progressOf(run);
    publish({ kind: 'progress', progress: entry.progress });
  });
  entry.done = handle.done
    .then(async (run) => {
      off();
      if (run.phase === 'done' && run.text !== null) {
        await keepResult(id, mode, run.text, hash, model).catch((failure: unknown) => console.warn('[glyph] result not kept:', failure));
        publish({ kind: 'landed', landed: { id, mode, text: run.text, model, hash, ms: run.elapsedMs, truncated: run.truncated, next: null } });
        publish({ kind: 'ended', id, mode, reason: 'done' });
      } else if (run.phase === 'stopped') {
        publish({ kind: 'ended', id, mode, reason: 'stopped' });
      } else {
        publish({ kind: 'ended', id, mode, reason: 'failed', message: run.message ?? 'The model stopped.' });
      }
    })
    .finally(() => {
      off();
      runs.delete(id);
    });

  runs.set(id, entry);
  return entry.done;
}
