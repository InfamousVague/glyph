import { readStored, writeStored } from './stored.ts';
import { binaryVersion } from './nativeGeneration.ts';

/**
 * The models this build of the app cannot run (GLY-2, GLY-5; docs/DESIGN.md §163). Matt saw "The summary didn't come"
 * every time and an "FFI error" on every fill: the chosen model was Gemma 4 E4B, whose chat template the engine's
 * llama.cpp has no name for, so every request it was given answered "cannot apply the chat template: ffi error -1"
 * (§145 had found it and left it). The engine now renders such a template itself (src-tauri/src/llm/prompt.rs
 * `render_template`), but that is in the binary, and a binary is a new install: until it is on the phone, the page
 * has to cope with the one it has.
 *
 * So a model that fails that way is remembered as one this binary cannot run, by the binary's version, and the model
 * that runs is chosen from the others (ai/available.ts `modelFor`): the next summary, fill or write-up goes to a Qwen
 * on the phone instead, and Settings › AI says why. A new binary is asked again, since it may carry the fix. With no
 * other model on the phone the failing one is still the one tried, and its failure is said in a sentence a person
 * can act on (core/ai.ts `generate`).
 */

const KEY = 'glyph-models-cannot-run';

/** The binary's version, once it has answered; null until then, and every record is believed meanwhile. */
let version: string | null = null;
let asked = false;

/** The binary's version as far as it is known yet, asked the first time a record needs it and not before. */
function knownVersion(): string | null {
  if (!asked) {
    asked = true;
    void binaryVersion().then((answered) => {
      version = answered;
    });
  }
  return version;
}

function records(): Record<string, string> {
  return readStored<Record<string, string>>(KEY, {}, (raw) => (raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as Record<string, string>) : null));
}

/** Whether a failure is a model's chat template the engine could not apply. */
export function isTemplateFailure(message: string): boolean {
  return /cannot apply the chat template/i.test(message);
}

/** Whether this binary has been found unable to run `model`. */
export function cannotRun(model: string): boolean {
  const said = records()[model];
  if (said === undefined) return false;
  const known = knownVersion();
  return known === null || said === known;
}

/** `model` remembered as one this binary cannot run. */
export async function markCannotRun(model: string): Promise<void> {
  const answered = await binaryVersion();
  writeStored(KEY, { ...records(), [model]: answered });
}

/** The models that can run, of those on the phone; all of them where none can, so the failure is still said. */
export function runnable(present: readonly string[]): string[] {
  const can = present.filter((id) => !cannotRun(id));
  return can.length ? can : [...present];
}
