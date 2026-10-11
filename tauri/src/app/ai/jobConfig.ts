import { MEETING_GENERATION } from '../capture/meeting.ts';
import { keepJobConfig, listModels, onModelsChanged, type JobConfig, type ModelInfo } from '../core/ai.ts';
import { hasNativeGeneration } from '../core/nativeGeneration.ts';
import { isAndroid } from '../core/platform.ts';
import { onPreferences, preferences, type Preferences } from '../core/preferences.ts';
import { isTauri } from '../core/tauri.ts';
import { NOTES_CONTEXT, PIECE_CONTEXT, RECORDING_NOTES_PROMPT, RECORDING_SUMMARY_PROMPT, TEMPERATURE } from '../format/prompt.ts';
import { modelFor, presentIds } from './available.ts';
import { ONE_PASS_CHARS, PIECE_CHARS } from './summaryText.ts';

/**
 * What the phone's own write-up of a meeting reads when the app is not there to ask (core/ai.ts `keepJobConfig`,
 * src-tauri/src/jobs.rs `JobConfig`; docs/DESIGN.md §127 section 4): the model as the page would choose it, the
 * prompts as the page has them, and the two preferences it obeys. Nothing off the phone.
 *
 * Sent at launch, when one of the three preferences it is made from changes (the model chosen, Write up, Summaries),
 * and when a model arrives or goes: the model named is what the page would pick from what is on the phone, and a
 * download changes that without any preference changing. A config that still named the model the phone lacked would
 * send a meeting asked again after the download straight back to "Needs a model" (Rust also picks from what is there
 * by the same rule, `llm::model::model_for`, as a second guard). Only on Android, where the write-up runs, and only
 * to a binary that has it; the model list is not read for a preference that has nothing to do with it.
 */

/** The config for `models` on this phone and `prefs` as they stand. */
export function jobConfigFor(models: readonly ModelInfo[], prefs: Pick<Preferences, 'formatModel' | 'writeUp' | 'summaries'>): JobConfig {
  return {
    model: modelFor(presentIds(models), prefs.formatModel) ?? prefs.formatModel,
    prompts: { summary: RECORDING_SUMMARY_PROMPT, notes: RECORDING_NOTES_PROMPT, piece: PIECE_CONTEXT, parts: NOTES_CONTEXT },
    onePassChars: ONE_PASS_CHARS,
    pieceChars: PIECE_CHARS,
    temperature: TEMPERATURE,
    writeUp: prefs.writeUp,
    summaries: prefs.summaries,
  };
}

/** The preferences the config is made from, as one value: a change of any other leaves it alone. */
export function jobConfigKey(prefs: Pick<Preferences, 'formatModel' | 'writeUp' | 'summaries'>): string {
  return JSON.stringify([prefs.formatModel, prefs.writeUp, prefs.summaries]);
}

/** Whether this device writes meetings up itself: Android, on a binary with the write-up. */
async function writesUp(): Promise<boolean> {
  return isTauri() && isAndroid && hasNativeGeneration(MEETING_GENERATION);
}

let lastSent = '';

/** The config sent to the phone, unless it is what was sent last. Resolves once it is kept. */
export async function sendJobConfig(): Promise<void> {
  if (!(await writesUp())) return;
  const config = jobConfigFor(await listModels().catch(() => []), preferences());
  const text = JSON.stringify(config);
  if (text === lastSent) return;
  await keepJobConfig(config);
  lastSent = text;
}

/** For tests: forget what was sent, so the next send is made. */
export function forgetSentJobConfig(): void {
  lastSent = '';
}

/** Keeps the config current for the life of the app (shell/useHousekeeping.ts); answers the way to stop. */
export function keepJobConfigCurrent(): () => void {
  const send = () => void sendJobConfig().catch((failure: unknown) => console.warn('[glyph] the write-up’s configuration was not kept:', failure));
  let key = jobConfigKey(preferences());
  send();
  const unPreferences = onPreferences(() => {
    const next = jobConfigKey(preferences());
    if (next === key) return;
    key = next;
    send();
  });
  const unModels = onModelsChanged(send);
  return () => {
    unPreferences();
    unModels();
  };
}
