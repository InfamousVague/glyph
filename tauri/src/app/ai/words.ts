import { modelName, type Phase } from '../core/ai.ts';
import { kindWords } from './kinds.ts';
import type { RunState } from './runs.ts';

/**
 * What the strip says about a run: one sentence per phase, in the words the
 * robot's view and the AI card already used, so nothing the person read
 * before changes its name. Pure, so every sentence is a test.
 */

/** Milliseconds as m:ss. */
export function clock(ms: number): string {
  const seconds = Math.round(ms / 1000);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

/** Tokens a second as a number: a tenth under ten, whole above. */
export function paceNumber(perSecond: number): string {
  return perSecond.toFixed(perSecond < 10 ? 1 : 0);
}

export function pace(perSecond: number): string {
  return `${paceNumber(perSecond)} tokens a second`;
}

export function runSentence(run: RunState): string {
  const words = kindWords(run.kind);
  const name = modelName(run.model);
  // An ask says what was asked, since "Working" alone says nothing.
  const doing = run.kind === 'ask' && run.instruction ? `“${run.instruction}”` : words.doing;
  if (run.kind === 'fill') {
    const said = fillSentence(run, name);
    if (said) return said;
  }
  switch (run.phase) {
    case 'queued':
      return 'Waiting for the model, which is on another note.';
    case 'loading':
      return `Loading ${name}.`;
    case 'prefill':
      return run.promptTokens ? `Reading the note, ${run.promptTokensDone} of ${run.promptTokens}.` : 'Reading the note.';
    case 'generating': {
      if (run.kind === 'review') return `${name} is ${run.lines.length || run.partial ? 'writing what it found' : 'thinking it through'}, ${pace(run.tokensPerSecond)}, ${clock(run.elapsedMs)}.`;
      const lines = run.lines.length ? `, ${run.lines.length} ${run.lines.length === 1 ? 'line' : 'lines'}` : '';
      return `${doing} with ${name}, ${pace(run.tokensPerSecond)}, ${clock(run.elapsedMs)}${lines}.`;
    }
    case 'done':
      return `${words.done} by ${name} in ${clock(run.elapsedMs)}.${run.truncated ? ' It ran out of room. Try a shorter note.' : ''}`;
    case 'stopped':
      return 'Stopped.';
    case 'failed':
      return run.message ?? 'The model stopped.';
  }
}

/** Blanks as a count: "1 blank", "3 blanks". */
export function blanksWord(n: number): string {
  return `${n} ${n === 1 ? 'blank' : 'blanks'}`;
}

/**
 * A press of Fill as the strip says it (docs/DESIGN.md §145, 14): the answers as they are written in one generation,
 * the blank it is on across several, and the press's whole count once it has ended. Null for a phase said the usual way.
 */
function fillSentence(run: RunState, name: string): string | null {
  const batch = run.batch;
  if (run.phase === 'generating' && batch) {
    if (batch.total > batch.asked) return `Filling ${Math.min(batch.total, batch.before + 1)} of ${blanksWord(batch.total)} with ${name}.`;
    return `Filling with ${name}, ${pace(run.tokensPerSecond)}, ${clock(run.elapsedMs)}, ${Math.min(run.lines.length, batch.asked)} of ${batch.asked}.`;
  }
  if (run.phase === 'done' && run.said) return run.said;
  return null;
}

/** A press of Fill's one line, in the strip once it has ended and in the log. */
export function filledSentence(filled: number, model: string, ms: number): string {
  return filled ? `Filled ${blanksWord(filled)} with ${modelName(model)} in ${clock(ms)}.` : `Nothing filled by ${modelName(model)}.`;
}

/**
 * How far along a run is, 0 to 1, or null where there is no telling: reading
 * the note is prompt tokens done of prompt tokens, writing is tokens written
 * of the most it may write (a run usually finishes well short of that, so the
 * bar is a floor, not a promise), and a run that has ended is full.
 */
export function progressOf(run: Pick<RunState, 'phase' | 'promptTokens' | 'promptTokensDone' | 'outputTokens' | 'maxTokens'>): number | null {
  if (run.phase === 'prefill') return run.promptTokens ? Math.min(1, run.promptTokensDone / run.promptTokens) : null;
  if (run.phase === 'generating') return run.maxTokens ? Math.min(1, run.outputTokens / run.maxTokens) : null;
  if (run.phase === 'done') return 1;
  return null;
}

/** Marks left in the note with no run to speak of: how many, and that they are the AI's. */
export function marksSentence(count: number): string {
  return count === 1 ? 'One change from the AI is marked in the note.' : `${count} changes from the AI are marked in the note.`;
}

/** A run's phase in the AI card's older dialect (core/ai.ts `Phase`): waiting reads as loading, stopped as cancelled, failed as error. */
export function cardPhase(run: RunState): Phase {
  if (run.phase === 'queued') return 'loading';
  if (run.phase === 'stopped') return 'cancelled';
  if (run.phase === 'failed') return 'error';
  return run.phase;
}

/** A run's record as one line of the log: what, by which model, how long, and how it ended. */
export function recordSentence(record: { kind: RunState['kind']; instruction: string | null; model: string; ms: number; outcome: 'done' | 'stopped' | 'failed'; message: string | null; filled?: number }): string {
  const words = kindWords(record.kind);
  if (record.kind === 'fill' && record.outcome === 'done') return filledSentence(record.filled ?? 0, record.model, record.ms);
  const what = record.kind === 'ask' && record.instruction ? `“${record.instruction}”` : words.label;
  if (record.outcome === 'stopped') return `${what}, stopped after ${clock(record.ms)}.`;
  if (record.outcome === 'failed') return `${what} failed${record.message ? `: ${record.message}` : '.'}`;
  return `${what} by ${modelName(record.model)} in ${clock(record.ms)}.`;
}
