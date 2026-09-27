import { gb, modelName, modelSpec } from '../core/ai.ts';
import { kindWords } from '../ai/kinds.ts';
import { ended, type RunState } from '../ai/runs.ts';
import type { ReviewStage } from '../ai/useNoteReview.ts';
import { runSentence } from '../ai/words.ts';

/**
 * The steps, the title and the heat of the scene while the models work on a
 * recording (scene/AtWork.tsx): everything the scene says or shades, worked
 * out from what the review is doing, with no DOM in it, so each line is a
 * test.
 *
 * Matt: "make the analyzing steps of the AI full screen high contrast SVG
 * iconography with cool effects like a piping hot phone CPU scrolling through
 * the thoughts and transcriptions of the AI". The steps are the review's own
 * (ai/useNoteReview.ts): listening again with the careful speech model,
 * comparing what the two heard, then the thinking run - loading the model,
 * reading the note, thinking it through, writing what it found. The list is
 * drawn whole from the start, in the order things really happen, so the steps
 * can be seen coming; a stage the hook says wins over whatever run the note
 * has, since the run is a later step.
 *
 * Two kinds of heat, kept apart. WARMTH is state: a model at work is a fact,
 * so the die's hatch, the column of stipple and the shimmer say so on the
 * phone and on the Mac alike. GLOW is measured: the rings and the pins light
 * only from the phone's own busy figure and temperature, which the engine
 * samples with every report (src-tauri/src/llm/hardware.rs), and a phone
 * that gives none keeps them dark.
 */

export type StepId = 'listen' | 'load' | 'read' | 'think' | 'write' | 'done';
export type StepState = 'waiting' | 'working' | 'done' | 'skipped';

export interface Step {
  id: StepId;
  words: string;
  state: StepState;
  /** After the words, in the quiet ink: what the step found, or why it was skipped. */
  detail?: string;
}

/** What the scene knows at one moment. */
export interface SceneInput {
  /** The review's own stage before its run (listening again, comparing), or null. */
  stage: ReviewStage | null;
  /** The better voice model's download, while one is under way (capture/refine.ts). */
  download: { received: number; total: number } | null;
  /** The note's run, going or ended; null before one has started, and for a run the scene ignores. */
  run: RunState | null;
  /** Whether a listen will happen at all: the recorder kept a recording. */
  hasJob: boolean;
  /** What Comparing said, once it has: kept after the stage clears, since the run replaces it. */
  compared: string | null;
  /** The review is over with no run to speak of: no thinking model, so only the words landed. */
  ended: boolean;
}

/** After an end, the scene holds the settle this long before it starts to leave. */
export const HOLD_MS = 400;
/** How long the fade out takes. */
export const LEAVE_MS = 260;
/** How long the scene waits for a run after the stage clears before it takes the review as over. */
export const GRACE_MS = 1500;
/** How long the scene waits to see anything at all after opening before it leaves quietly. */
export const OPEN_GRACE_MS = 8000;
/** How often the haze may step, at most: one write a report, never more than this a second. */
export const HAZE_HZ = 8;
/** The words' own share of the heat filter's bend (editor/textEffects.ts `own`): the bend that still reads as solid. */
export const HAZE_OWN = 0.3;
/** How many lines the pane holds in the DOM at once. */
export const PANE_LINES = 24;

/** The words Comparing says when the careful model never spoke. */
export const NOTHING_TO_COMPARE = 'Nothing to compare against.';

/** Where a run's phase sits in the order things happen; an ended run is placed by what it got to. */
function reached(run: RunState): number {
  switch (run.phase) {
    case 'queued':
      return 0;
    case 'loading':
      return 1;
    case 'prefill':
      return 2;
    case 'generating':
      return 3;
    case 'done':
      return 5;
    default:
      // Stopped or failed: nothing more ticks, so the steps stand where the evidence says it got to.
      if (run.lines.length || run.partial) return 4;
      if (run.thought || run.outputTokens) return 3;
      if (run.promptTokensDone) return 2;
      return 1;
  }
}

/** Whether the run's answer has begun: a thinking run is writing once anything follows its thought. */
function answering(run: RunState): boolean {
  return run.lines.length > 0 || run.partial.length > 0;
}

function megabytes(bytes: number): number {
  return Math.round(bytes / 1e6);
}

/** The download's words, as notes/Notices.tsx says them. */
export function downloadWords(download: { received: number; total: number }): string {
  return `Getting the better voice model, ${megabytes(download.received)} of ${megabytes(download.total)} MB.`;
}

export function stepsOf(input: SceneInput): Step[] {
  const { stage, download, hasJob, compared, ended: over } = input;
  // A stage wins: while the hook says one, whatever run the note has is a later step, or an earlier ask's (useNoteAi.ts).
  const run = stage ? null : input.run;
  const kind = run?.kind ?? 'review';
  const summary = kind !== 'review';
  const at = run ? reached(run) : 0;
  const stopped = run !== null && ended(run) && run.phase !== 'done';
  const steps: Step[] = [];

  if (hasJob && !summary) {
    const skipped = compared === NOTHING_TO_COMPARE;
    // Comparing is one frame, so it is this step's tick and its detail, not a line of its own.
    const done = compared !== null || run !== null || over;
    const listening = stage?.what === 'Listening again';
    steps.push({
      id: 'listen',
      words: 'Listening again',
      state: skipped ? 'skipped' : done ? 'done' : 'waiting',
      detail: download && listening ? downloadWords(download) : (compared ?? undefined),
    });
  }
  steps.push({ id: 'load', words: 'Loading the model', state: at >= 2 || over ? 'done' : 'waiting' });
  steps.push({ id: 'read', words: summary ? 'Reading the recording' : 'Reading the note', state: at >= 3 || over ? 'done' : 'waiting' });
  if (!summary) steps.push({ id: 'think', words: 'Thinking it through', state: (run && at >= 3 && (answering(run) || run.phase === 'done')) || over ? 'done' : 'waiting' });
  steps.push({ id: 'write', words: summary ? 'Writing the summary' : 'Writing what it found', state: at >= 5 || over ? 'done' : 'waiting' });
  steps.push({ id: 'done', words: 'Done', state: at >= 5 || over ? 'done' : 'waiting' });

  // The first step not done is the one working, unless the run stopped: then nothing is.
  if (!stopped) {
    const first = steps.find((step) => step.state === 'waiting');
    if (first) first.state = 'working';
  }
  return steps;
}

/** The step at work now, or null once nothing is. */
export function workingStep(input: SceneInput): StepId | null {
  return stepsOf(input).find((step) => step.state === 'working')?.id ?? null;
}

/** The title: one sentence, in the strip's own words wherever it has them (ai/words.ts). */
export function sceneTitle(input: SceneInput): string {
  const { stage, download, run, ended: over } = input;
  if (stage) {
    if (download) return downloadWords(download);
    return `${stage.what}${stage.percent !== null && stage.percent > 0 ? `, ${stage.percent}%` : ''}.`;
  }
  if (!run) return over ? 'Done.' : 'Checking what was heard.';
  if (run.phase === 'generating') {
    const name = modelName(run.model);
    if (run.kind === 'review') return `${name} is ${answering(run) ? 'writing what it found' : 'thinking it through'}.`;
    return `${kindWords(run.kind).doing} with ${name}.`;
  }
  return runSentence(run);
}

/** The line under the title. */
export function sceneDetail(input: SceneInput): string {
  const { stage, download, run } = input;
  if (stage) return download ? 'Once, then it stays on the phone.' : stage.detail;
  if (!run) return input.ended ? '' : 'The recording is saved.';
  switch (run.phase) {
    case 'loading': {
      const spec = modelSpec(run.model);
      return spec ? `${gb(spec.bytes)} on this phone.` : '';
    }
    case 'prefill':
      return 'The note and everything that was heard.';
    case 'generating':
      if (run.kind !== 'review') return '';
      return answering(run) ? 'What it finds is checked against the note, then marked.' : 'Thinking it through out loud.';
    default:
      return '';
  }
}

/** The hidden live line for a screen reader: the working step's words, or the end's sentence. No numbers. */
export function liveWords(input: SceneInput): string {
  const working = stepsOf(input).find((step) => step.state === 'working');
  if (working) return `${working.words}.`;
  return sceneTitle(input);
}

/** The pieces of a title, its progress numbers apart, so they can be hidden from a screen reader that reads the heading. */
export function titlePieces(title: string): { text: string; number: boolean }[] {
  return title
    .split(/(, \d+%|, \d+ of \d+(?: MB)?| in \d+:\d\d)/)
    .filter((piece) => piece !== '')
    .map((piece, i) => ({ text: piece, number: i % 2 === 1 }));
}

export type Warmth = 'cold' | 'warm' | 'hot';

/** State, not a reading: how alive the die is. */
export function warmthOf(input: SceneInput): Warmth {
  const { stage, download, run, compared, ended: over } = input;
  if (over) return 'cold';
  if (stage || download) return 'warm';
  if (!run) return compared !== null ? 'warm' : 'cold';
  switch (run.phase) {
    case 'loading':
      return 'warm';
    case 'prefill':
    case 'generating':
      return 'hot';
    default:
      return 'cold';
  }
}

const clamp = (value: number) => Math.min(1, Math.max(0, value));

/**
 * Measured: how brightly the rings glow, 0 to 1, from the phone's own readings. Nothing before a sample past loading
 * (loading's one sample is a new sampler's, and reads 0). Busy is the engine's share of the threads it runs on, so six
 * of eight cores at full tilt is full; heat, where the phone lets it be read, is the AI card's share; the blend when
 * both are there. An ended run has cooled.
 */
export function glowOf(run: RunState | null): number {
  if (!run || !run.hardware || ended(run) || run.phase === 'queued' || run.phase === 'loading') return 0;
  const { cpuPercent, threads, cores, tempC } = run.hardware;
  const over = threads || Math.min(6, Math.max(2, cores)) || 1;
  const busy = clamp(cpuPercent / (100 * over));
  const heat = tempC != null ? clamp((tempC - 20) / 40) : null;
  return heat === null ? busy : 0.5 * busy + 0.5 * heat;
}

/** The glow as the ring it reaches, 0 to 5. */
export function glowStepOf(glow: number): number {
  return Math.round(clamp(glow) * 5);
}

/** How many of the die's pins are lit: one per busy core, capped at the pins drawn. */
export function litPinsOf(cpuPercent: number, pins: number): number {
  return Math.min(pins, Math.max(0, Math.round(cpuPercent / 100)));
}

/** How many pins the die has: the phone's cores, capped at twelve so the die keeps its shape. */
export function pinsOf(cores: number | null | undefined): number {
  const have = cores || (typeof navigator !== 'undefined' && navigator.hardwareConcurrency) || 8;
  return Math.max(2, Math.min(12, have));
}
