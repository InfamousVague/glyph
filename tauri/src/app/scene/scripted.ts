import type { Hardware, Output, Progress, Run, RunOptions } from '../core/ai.ts';
import { isTauri } from '../core/tauri.ts';
import type { ReviewStage } from '../ai/useNoteReview.ts';

/**
 * The scene played from a script (diag/SceneBench.tsx, and `?scene=` in a
 * browser): the review's stages and its run as a phone would report them,
 * with pretend models, so the layout, the pictures and the steps can be
 * looked at without a recording - which is what Matt asked to review on his
 * Fold. Three scripts: with a heat reading, without one (a phone that hides
 * its thermal zones, §29g), and with no readings at all (the Mac, or a
 * binary before generation 14).
 *
 * The run is handed to the engine the way the browser's `?review` hands its
 * own (ai/runs.ts `simulateRuns`, ai/reviewSimulation.ts), round `startRun`
 * alone, so no real run is ever played by the script.
 */

export type SceneScript = 'heat' | 'cold' | 'none';

/** What the pretend fast model heard, "seat bar" and all (ai/reviewSimulation.ts's mishearing). */
export const SCRIPT_HEARD =
  'Notes from the planning call this morning. ' +
  'The seat bar on the player still jumps when the tape is scrubbed quickly. ' +
  'Hey Ghost, add a task fix the seat bar before the demo on Thursday. ' +
  'HelloTrade want the summary page ready by the end of the month. ' +
  'The onboarding flame reads well on the dark theme and less well on paper. ' +
  'Remember to measure the smoke on the Fold with the switch off and on. ' +
  'Groceries after work, milk, eggs, coffee and something for the garden. ' +
  'Call the plumber back about the boiler service.';

/** The note those words made. */
export const SCRIPT_BODY = [
  '# Planning call',
  '',
  'Notes from the planning call this morning.',
  'The seat bar on the player still jumps when the tape is scrubbed quickly.',
  '',
  '- [ ] Fix the seat bar before the demo on Thursday',
  '',
  'HelloTrade want the summary page ready by the end of the month.',
  'The onboarding flame reads well on the dark theme and less well on paper.',
  'Remember to measure the smoke on the Fold with the switch off and on.',
  '',
  'Groceries after work, milk, eggs, coffee and something for the garden.',
  'Call the plumber back about the boiler service.',
].join('\n');

/** The prompt the pretend run is given; the script never reads it. */
export const SCRIPT_PROMPT = `AS HEARD:\n${SCRIPT_HEARD}\n\nAS SAVED:\n${SCRIPT_BODY}`;

/** The thought the pretend model streams: the browser's own (ai/reviewSimulation.ts), a little longer. */
const THOUGHT = [
  'Thinking Process:',
  '',
  '1. Words. The two transcripts disagree in a few places. The slower model heard "seek bar" where the fast one heard "seat bar"; a seek bar is the scrubber in a player, so "seek" is right, and the task says the same words.',
  '2. Structure. The heading names the note, the to-do is a thing to do, and nothing else looks like a list. The groceries could be one, but they were said as a sentence.',
  '3. Commands. The one spoken command landed where its words said, as a task under the line about the player.',
  '4. Names. HelloTrade is written as one word in the note titles, and the note has it that way.',
].join('\n');

/** The findings the pretend model writes, typed in as JSON so the open "what" shows as the pen line. */
const FINDINGS = [
  { check: 'words', what: '“seek bar”, not “seat bar”', why: 'The slower speech model heard it this way, and a seek bar is the scrubber in a player.', find: 'The seat bar on the player still jumps when the tape is scrubbed quickly.', replace: 'The seek bar on the player still jumps when the tape is scrubbed quickly.' },
  { check: 'structure', what: 'The groceries as a list', why: 'Four things to buy were said in one breath; a list is what they are.', find: 'Groceries after work, milk, eggs, coffee and something for the garden.', replace: '## Groceries after work\n\n- Milk\n- Eggs\n- Coffee\n- Something for the garden' },
];

/** The report cadence, as the engine's. */
const REPORT_MS = 120;
/** Loading is one report, then silence while the model comes into memory. */
const LOAD_MS = 1800;
const PROMPT_TOKENS = 1040;
const PREFILL_STEP = 128;
const PREFILL_MS = 2400;
/** Six characters every thirty milliseconds (ai/reviewSimulation.ts), at the report cadence. */
const CHARS_A_REPORT = 24;

/**
 * The stages before the run: listening again 0 to 100 in tens every quarter second, then comparing for a moment,
 * then null. Answers the way to stop early.
 */
export function scriptedStages(onStage: (stage: ReviewStage | null) => void): () => void {
  let stopped = false;
  let timer = 0;
  const detail = 'The slower speech model is listening to the recording again.';
  let percent = 0;
  const listen = () => {
    if (stopped) return;
    onStage({ what: 'Listening again', detail, percent });
    if (percent < 100) {
      percent += 10;
      timer = window.setTimeout(listen, 250);
      return;
    }
    timer = window.setTimeout(() => {
      if (stopped) return;
      onStage({ what: 'Comparing', detail: '3 places where the two models heard different words.', percent: null });
      timer = window.setTimeout(() => {
        if (!stopped) onStage(null);
      }, 600);
    }, 250);
  };
  listen();
  return () => {
    stopped = true;
    window.clearTimeout(timer);
  };
}

/** The phone under the pretend model: the readings ramp as a real run's do. */
function hardwareAt(script: SceneScript, sinceRunMs: number, sinceStartMs: number, first: boolean): Hardware | null {
  if (script === 'none') return null;
  const busy = first ? 0 : Math.min(1, sinceRunMs / 1000);
  const reading: Hardware = { cores: 8, threads: 6, rssBytes: 3.1e9, totalBytes: 12e9, freeBytes: 4e9, cpuPercent: Math.round(640 * busy) };
  if (script === 'heat') reading.tempC = Math.round((31 + 13 * Math.min(1, sinceStartMs / 12_000)) * 10) / 10;
  return reading;
}

/** The pretend model, handed to the engine round `startRun` (ai/runs.ts `simulateRuns`). */
export function scriptedReview(script: SceneScript): (options: RunOptions) => Run {
  return (options) => {
    let cancelled = false;
    /** Ends the sleep under way, answering cancelled at once rather than at its end. */
    let wake: (() => void) | null = null;
    const sleep = (ms: number) =>
      new Promise<void>((resolve, reject) => {
        const timer = window.setTimeout(() => {
          wake = null;
          resolve();
        }, ms);
        wake = () => {
          window.clearTimeout(timer);
          wake = null;
          reject(new Error('cancelled'));
        };
      });
    const text = `<think>\n${THOUGHT}\n</think>\n\n${JSON.stringify(FINDINGS, null, 1)}`;
    const done = (async (): Promise<Output> => {
      const started = Date.now();
      const report = (progress: Omit<Progress, 'id' | 'promptTokens' | 'thinking' | 'elapsedMs'>) => {
        if (cancelled) throw new Error('cancelled');
        options.onProgress({ id: 'scene', promptTokens: PROMPT_TOKENS, thinking: true, ...progress, elapsedMs: Date.now() - started });
      };
      report({ phase: 'loading', promptTokensDone: 0, outputTokens: 0, tokensPerSecond: 0, partial: '' });
      await sleep(LOAD_MS);
      // Reading: ticks of a hundred and a bit up to the prompt's length, at about 430 a second.
      const ticks = Math.ceil(PROMPT_TOKENS / PREFILL_STEP);
      const runFrom = Date.now();
      for (let i = 1; i <= ticks; i += 1) {
        await sleep(PREFILL_MS / ticks);
        const read = Math.min(PROMPT_TOKENS, i * PREFILL_STEP);
        report({ phase: 'prefill', promptTokensDone: read, outputTokens: 0, tokensPerSecond: Math.round((read / Math.max(1, Date.now() - runFrom)) * 1000), partial: '', hardware: hardwareAt(script, Date.now() - runFrom, Date.now() - started, i === 1) });
      }
      // Writing: the thought, then the findings, a few characters a report.
      const writeFrom = Date.now();
      for (let at = CHARS_A_REPORT; at < text.length + CHARS_A_REPORT; at += CHARS_A_REPORT) {
        await sleep(REPORT_MS);
        const partial = text.slice(0, at);
        const outputTokens = Math.round(partial.length / 4);
        report({ phase: 'generating', promptTokensDone: PROMPT_TOKENS, outputTokens, tokensPerSecond: Math.round((outputTokens / Math.max(1, Date.now() - writeFrom)) * 1000 * 10) / 10, partial, hardware: hardwareAt(script, Date.now() - runFrom, Date.now() - started, false) });
      }
      const ms = Date.now() - started;
      const outputTokens = Math.round(text.length / 4);
      return { text, promptTokens: PROMPT_TOKENS, outputTokens, ms, cachedTokens: 0, prefillMs: PREFILL_MS, loadMs: LOAD_MS, tokensPerSecond: Math.round((outputTokens / Math.max(1, ms - LOAD_MS - PREFILL_MS)) * 1000 * 10) / 10, truncated: false, thinking: true };
    })();
    return {
      done,
      cancel: () => {
        cancelled = true;
        wake?.();
      },
    };
  };
}

/** `?scene=heat|cold|none` in a browser plays the bench at launch; nothing under Tauri, where the Developer page is the way in. */
export function sceneQuery(): SceneScript | null {
  if (isTauri() || typeof window === 'undefined') return null;
  const asked = new URLSearchParams(window.location.search).get('scene');
  return asked === 'heat' || asked === 'cold' || asked === 'none' ? asked : null;
}
