import { useSyncExternalStore } from 'react';
import { generate, type Hardware, type Output, type Progress } from '../core/ai.ts';
import type { RunKind } from './kinds.ts';
import { recordRun } from './log.ts';

/**
 * A run of the model on a note, as the screen watches it: the one engine
 * behind the robot's modes, the prompt bar, a spoken instruction and the
 * review after a recording.
 *
 * Matt: "more real time, more interactive, with UI updates, iconography and
 * general feedback". So a run is not a promise that resolves with a text a
 * minute later; it is a state the page can draw at every report - which
 * phase, which model, how fast, the phone underneath - and, the part the
 * editor lands, THE LINES AS THEY FINISH. The model writes token by token
 * and reports about every 120 ms with everything so far (core/ai.ts); this
 * module cuts that at the last newline, so `lines` only ever grows by whole
 * lines and `partial` is the one under the pen. A line the model has finished
 * does not change, which is what lets the editor put it in the note the
 * moment it arrives (editor/aiChanges.ts).
 *
 * One model, one pass (Matt), and one run at a time: the phone has one set of
 * cores and Rust queues generations anyway (ai_commands.rs), so a second run
 * on another note waits here as `queued`, where the strip can say so, rather
 * than in the dark. A second run on the SAME note takes the first one's
 * place: the newest ask is the one meant.
 *
 * Everything here is module state on purpose: a run outlives the screen that
 * started it, as the whisper post-pass and the old pipeline did, and a note
 * opened while its run is on finds it going. The latest run of each note stays
 * readable after it ends, until the strip is dismissed or the next run
 * replaces it, so "Formatted by Qwen 4B in 0:42" is there to read when the
 * person looks up.
 */

export type RunPhase = 'queued' | 'loading' | 'prefill' | 'generating' | 'done' | 'stopped' | 'failed';

/** A part of the note a run works on, as offsets into the body when it started. */
export interface RunScope {
  from: number;
  to: number;
}

export interface RunRequest {
  noteId: string;
  kind: RunKind;
  /** The words the person gave, for a kind that takes some. */
  instruction?: string;
  /** The model to run, already one that is on the phone (ai/available.ts `modelFor`). */
  model: string;
  system: string;
  /** The words it works on, links and tables already swapped for tokens it can copy (format/links.ts, tables.ts). */
  prompt: string;
  context?: string;
  maxTokens: number;
  temperature?: number;
  think?: boolean;
  thinkBudget?: number;
  /**
   * The model's text so far as the note's words - the links and tables put
   * back - and, with `final`, the tidy-up once it has finished. The identity
   * when absent.
   */
  restore?: (text: string, final: boolean) => string;
  /** The hash of the body it was written from (format/pipeline.ts `noteHash`), for what is kept. */
  hash?: number | null;
  scope?: RunScope | null;
}

export interface RunState {
  id: string;
  noteId: string;
  kind: RunKind;
  instruction: string | null;
  model: string;
  scope: RunScope | null;
  phase: RunPhase;
  /** The lines the model has finished, as the note's words. Only ever grows while it runs. */
  lines: readonly string[];
  /** The line under its pen, not finished. */
  partial: string;
  /** Its reasoning so far, for a run asked to think; empty otherwise. */
  thought: string;
  /** The whole answer once it is done, restored and tidied; null until then, and after a stop or a failure. */
  text: string | null;
  promptTokens: number;
  promptTokensDone: number;
  outputTokens: number;
  /** The most it may write: what the bar is measured against. */
  maxTokens: number;
  tokensPerSecond: number;
  elapsedMs: number;
  hardware: Hardware | null;
  /** Stopped by the budget rather than by finishing. */
  truncated: boolean;
  /** Why it failed, for a run that did. */
  message: string | null;
  /** When it was asked for, in ms since the epoch. */
  startedAt: number;
  endedAt: number | null;
  hash: number | null;
}

export interface RunHandle {
  id: string;
  /** Resolves with the run's last state, however it ended. Never rejects. */
  done: Promise<RunState>;
  cancel: () => void;
}

interface Entry {
  state: RunState;
  request: RunRequest;
  /** Stops the generation, once one is going. */
  stop: (() => void) | null;
  stopped: boolean;
  resolve: (state: RunState) => void;
  done: Promise<RunState>;
}

type Listener = (run: RunState) => void;

const listeners = new Set<Listener>();
/** The run the model is on, and the ones waiting for it, in order. */
let active: Entry | null = null;
const waiting: Entry[] = [];
/** The latest run of each note, going or ended, until it is dismissed or the next one replaces it. */
const latest = new Map<string, RunState>();
let count = 0;

export function subscribeRuns(listener: Listener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function ended(run: RunState): boolean {
  return run.phase === 'done' || run.phase === 'stopped' || run.phase === 'failed';
}

function publish(entry: Entry): void {
  latest.set(entry.state.noteId, entry.state);
  listeners.forEach((l) => l(entry.state));
}

function set(entry: Entry, patch: Partial<RunState>): void {
  entry.state = { ...entry.state, ...patch };
  publish(entry);
}

/**
 * The text cut at its last newline: the lines that are finished, and the
 * rest. A model writes a line's last word and then its newline in one or two
 * reports, so a line is only "finished" once the newline is there.
 */
export function splitLines(text: string): { lines: string[]; partial: string } {
  const cut = text.lastIndexOf('\n');
  if (cut < 0) return { lines: [], partial: text };
  return { lines: text.slice(0, cut).split('\n'), partial: text.slice(cut + 1) };
}

/**
 * A reasoning run's text as its thought and its answer, the answer's own
 * newlines kept: `splitThought` (core/ai.ts) trims the answer for a screen
 * that shows it whole, and a trimmed answer never ends in the newline that
 * says its last line is finished.
 */
export function splitThinking(text: string, thinking: boolean): { thought: string; answer: string } {
  if (!thinking) return { thought: '', answer: text };
  const body = text.replace(/^\s*<think>\s*/, '');
  const end = body.indexOf('</think>');
  if (end < 0) return { thought: body.trim(), answer: '' };
  return { thought: body.slice(0, end).trim(), answer: body.slice(end + '</think>'.length).replace(/^[ \t]*\n+/, '') };
}

/** Every line of a finished text, the trailing newline not counted as an empty one. */
export function allLines(text: string): string[] {
  const trimmed = text.replace(/\n+$/, '');
  return trimmed ? trimmed.split('\n') : [];
}

/** Starts a run, or queues it behind the one going. */
export function startRun(request: RunRequest): RunHandle {
  const id = `run-${Date.now().toString(36)}-${(count += 1)}`;
  const state: RunState = {
    id,
    noteId: request.noteId,
    kind: request.kind,
    instruction: request.instruction ?? null,
    model: request.model,
    scope: request.scope ?? null,
    phase: 'queued',
    lines: [],
    partial: '',
    thought: '',
    text: null,
    promptTokens: 0,
    promptTokensDone: 0,
    outputTokens: 0,
    maxTokens: request.maxTokens,
    tokensPerSecond: 0,
    elapsedMs: 0,
    hardware: null,
    truncated: false,
    message: null,
    startedAt: Date.now(),
    endedAt: null,
    hash: request.hash ?? null,
  };
  let resolve: (state: RunState) => void = () => undefined;
  const done = new Promise<RunState>((r) => {
    resolve = r;
  });
  const entry: Entry = { state, request, stop: null, stopped: false, resolve, done };
  // The newest ask for a note is the one meant: an earlier one on the same note ends first.
  stopNote(request.noteId);
  waiting.push(entry);
  publish(entry);
  pump();
  return { id, done, cancel: () => stopEntry(entry) };
}

/** Stops a note's run, going or waiting; resolves once it has ended. */
export function cancelRun(noteId: string): Promise<void> {
  const entries = [...waiting, ...(active ? [active] : [])].filter((e) => e.state.noteId === noteId);
  stopNote(noteId);
  return Promise.all(entries.map((e) => e.done)).then(() => undefined);
}

function stopNote(noteId: string): void {
  for (const entry of [...waiting]) if (entry.state.noteId === noteId) stopEntry(entry);
  if (active?.state.noteId === noteId) stopEntry(active);
}

function stopEntry(entry: Entry): void {
  if (entry.stopped || ended(entry.state)) return;
  entry.stopped = true;
  if (entry === active) {
    // The generation answers "cancelled", and the run ends there.
    entry.stop?.();
    return;
  }
  const at = waiting.indexOf(entry);
  if (at >= 0) waiting.splice(at, 1);
  end(entry, 'stopped', null, null);
}

function pump(): void {
  while (!active) {
    const next = waiting.shift();
    if (!next) return;
    if (next.stopped) continue;
    active = next;
    void execute(next);
  }
}

async function execute(entry: Entry): Promise<void> {
  set(entry, { phase: 'loading' });
  const { request } = entry;
  const run = generate({
    model: request.model,
    system: request.system,
    context: request.context,
    prompt: request.prompt,
    maxTokens: request.maxTokens,
    temperature: request.temperature ?? 0.3,
    think: request.think,
    thinkBudget: request.thinkBudget,
    onProgress: (progress) => onProgress(entry, progress),
  });
  entry.stop = run.cancel;
  // Stopped between being queued and started: the flag was raised, and the generation has only just been asked for.
  if (entry.stopped) run.cancel();
  try {
    const output = await run.done;
    end(entry, 'done', null, output);
  } catch (failure) {
    const message = failure instanceof Error ? failure.message : String(failure);
    end(entry, message === 'cancelled' ? 'stopped' : 'failed', message === 'cancelled' ? null : message, null);
  }
}

function onProgress(entry: Entry, progress: Progress): void {
  if (entry.stopped || ended(entry.state)) return;
  // The end comes with the output, not the last report.
  if (progress.phase === 'done' || progress.phase === 'error' || progress.phase === 'cancelled') return;
  const { thought, answer } = splitThinking(progress.partial, progress.thinking ?? false);
  const restore = entry.request.restore ?? ((text: string) => text);
  const { lines, partial } = splitLines(restore(answer, false));
  set(entry, {
    phase: progress.phase,
    lines,
    partial,
    thought,
    promptTokens: progress.promptTokens,
    promptTokensDone: progress.promptTokensDone,
    outputTokens: progress.outputTokens,
    tokensPerSecond: progress.tokensPerSecond,
    elapsedMs: progress.elapsedMs,
    hardware: progress.hardware ?? null,
  });
}

function end(entry: Entry, phase: 'done' | 'stopped' | 'failed', message: string | null, output: Output | null): void {
  if (ended(entry.state)) return;
  const endedAt = Date.now();
  const patch: Partial<RunState> = { phase, message, endedAt, elapsedMs: output?.ms ?? Math.max(entry.state.elapsedMs, endedAt - entry.state.startedAt) };
  if (output) {
    const { thought, answer } = splitThinking(output.text, output.thinking ?? false);
    const restore = entry.request.restore ?? ((text: string) => text);
    const text = restore(answer, true);
    Object.assign(patch, {
      text,
      lines: allLines(text),
      partial: '',
      thought: thought || entry.state.thought,
      outputTokens: output.outputTokens,
      promptTokens: output.promptTokens,
      promptTokensDone: output.promptTokens,
      tokensPerSecond: output.tokensPerSecond,
      truncated: output.truncated,
    });
  }
  set(entry, patch);
  const { state } = entry;
  recordRun({
    id: state.id,
    noteId: state.noteId,
    kind: state.kind,
    instruction: state.instruction,
    model: state.model,
    at: state.startedAt,
    ms: state.elapsedMs,
    outputTokens: state.outputTokens,
    outcome: phase,
    message,
    truncated: state.truncated,
  });
  entry.resolve(state);
  if (entry === active) {
    active = null;
    pump();
  }
}

/** The latest run of a note, going or ended, or null. */
export function runFor(noteId: string): RunState | null {
  return latest.get(noteId) ?? null;
}

/** Whether a run is going, or waiting to, for this note. */
export function isRunning(noteId: string): boolean {
  return (active !== null && active.state.noteId === noteId) || waiting.some((e) => e.state.noteId === noteId);
}

/** Whether the model is on any note at all. */
export function anyRunning(): boolean {
  return active !== null || waiting.length > 0;
}

/** An ended run put away: the strip has nothing more to say about it. */
export function dismissRun(noteId: string): void {
  const run = latest.get(noteId);
  if (!run || !ended(run)) return;
  latest.delete(noteId);
  listeners.forEach((l) => l(run));
}

/** Nothing going, nothing remembered: for a reset, and for tests. */
export function forgetAllRuns(): void {
  for (const entry of [...waiting]) stopEntry(entry);
  if (active) stopEntry(active);
  latest.clear();
}

const subscribeChanges = (listener: () => void) => subscribeRuns(() => listener());
const none = () => null;

/** A note's latest run as the screen sees it, redrawn on every report. */
export function useRun(noteId: string): RunState | null {
  return useSyncExternalStore(subscribeChanges, () => latest.get(noteId) ?? null, none);
}
