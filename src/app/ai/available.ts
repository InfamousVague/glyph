import { useEffect, useState } from 'react';
import { MODELS, useModels, type Download, type ModelInfo } from '../core/ai.ts';
import { hasNativeGeneration, nativeGeneration } from '../core/nativeGeneration.ts';
import { isIOS } from '../core/platform.ts';
import { preferences, usePreferences } from '../core/preferences.ts';
import { isTauri } from '../core/tauri.ts';

/**
 * Whether the AI can run here, and if not, why - in one sentence a person can
 * act on.
 *
 * Matt: where there is no engine (a browser, iOS, a phone with no model), the
 * bar and Ask show, greyed, with the reason and a way to fix it where there
 * is one. So every surface that offers the AI asks this one question and
 * draws the same answer, rather than each finding its own words for "not
 * here". The rules, in the order they bite:
 *
 * - No Rust core (a browser tab): the AI runs on the phone.
 * - iOS: every model command refuses there (ai_commands.rs `NOT_ON_IOS`).
 * - A binary older than `ai_generate` (native generation 10).
 * - The catalogue not read yet: waiting, not refused.
 * - No model on the phone: get one - unless Local only forbids the download.
 *
 * Which model runs is decided here too: the one chosen in Settings when it is
 * on the phone, else the biggest that is no bigger than it, else the smallest
 * there is. One model, one pass (Matt), so there is always exactly one answer.
 */

/** The binary generation that has `ai_generate`. */
export const AI_GENERATION = 10;

export type Availability =
  | { ok: true; model: string; chosen: string }
  | {
      ok: false;
      reason: string;
      /** A model worth getting, when getting one is the fix. */
      get: string | null;
      /** The answer is not in yet (the catalogue is being read): grey, but not for long. */
      waiting: boolean;
    };

/** Bytes of a model, for choosing among what is on the phone; an unknown id sorts last. */
function sizeOf(id: string): number {
  return MODELS.find((m) => m.id === id)?.bytes ?? Number.MAX_SAFE_INTEGER;
}

/**
 * The model that runs, given what is on the phone: the chosen one, else the
 * biggest no bigger than it, else the smallest there is; null with none.
 */
export function modelFor(present: readonly string[], chosen: string): string | null {
  const here = [...new Set(present)];
  if (!here.length) return null;
  if (here.includes(chosen)) return chosen;
  const ceiling = sizeOf(chosen);
  const under = here.filter((id) => sizeOf(id) <= ceiling).sort((a, b) => sizeOf(b) - sizeOf(a));
  if (under[0]) return under[0];
  return here.sort((a, b) => sizeOf(a) - sizeOf(b))[0] ?? null;
}

/** The ids of the models the catalogue says are on the phone. */
export function presentIds(models: readonly ModelInfo[]): string[] {
  return models.filter((m) => m.present).map((m) => m.id);
}

/** The smallest model on the phone, for a line that wants speed over care (the gist); null with none. */
export function smallestOf(present: readonly string[]): string | null {
  return [...new Set(present)].sort((a, b) => sizeOf(a) - sizeOf(b))[0] ?? null;
}

export interface Where {
  tauri: boolean;
  ios: boolean;
  localOnly: boolean;
  /** The binary's generation, or null until it has answered. */
  generation: number | null;
}

/** The rules, pure, so each is a test. */
export function availability(models: readonly ModelInfo[], chosen: string, where: Where): Availability {
  if (!where.tauri) return { ok: false, reason: 'The AI runs on the phone. Install Ghost.md on Android to use it.', get: null, waiting: false };
  if (where.ios) return { ok: false, reason: 'The AI is not on iOS yet.', get: null, waiting: false };
  if (where.generation !== null && where.generation < AI_GENERATION) {
    return { ok: false, reason: 'The AI needs the newest Ghost.md. Install it from attack.fm/glyph.', get: null, waiting: false };
  }
  if (!models.length) return { ok: false, reason: 'Looking for the model.', get: null, waiting: true };
  const model = modelFor(presentIds(models), chosen);
  if (model) return { ok: true, model, chosen };
  if (where.localOnly) {
    return { ok: false, reason: 'No model is on the phone, and Local only is on, so none can be downloaded. Turn it off in Settings to get one.', get: null, waiting: false };
  }
  return { ok: false, reason: 'The AI needs a model on the phone. It runs here; nothing leaves the phone.', get: chosen, waiting: false };
}

/** Whether the binary can run a model at all (native generation 10). */
export function canRunModels(): Promise<boolean> {
  return hasNativeGeneration(AI_GENERATION);
}

export interface AvailabilityState {
  availability: Availability;
  /** What is on the phone, for a screen that names it. */
  models: ModelInfo[];
  download: Download | null;
  problem: string | null;
  /** Gets a model, in the open, with the bytes arriving in `download`. */
  fetch: (id: string) => Promise<void>;
}

/** The answer as a screen sees it, following the catalogue, the download, and the settings. */
export function useAvailability(): AvailabilityState {
  const prefs = usePreferences();
  const { models, download, problem, fetch } = useModels();
  const [known, setKnown] = useState<number | null>(null);
  useEffect(() => {
    let alive = true;
    void nativeGeneration().then((value) => {
      if (alive) setKnown(value);
    });
    return () => {
      alive = false;
    };
  }, []);
  const where: Where = { tauri: isTauri(), ios: isIOS, localOnly: prefs.localOnly, generation: known };
  return { availability: availability(models, prefs.formatModel, where), models, download, problem, fetch };
}

/** The model that would run now, from the catalogue as last read; for callers outside React. */
export function modelNow(models: readonly ModelInfo[]): string | null {
  return modelFor(presentIds(models), preferences().formatModel);
}
