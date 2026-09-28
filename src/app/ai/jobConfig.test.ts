import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { JobConfig, ModelInfo } from '../core/ai.ts';

/*
 * What the phone's write-up is told (ai/jobConfig.ts): the prompts each in its own place, the model the page would
 * pick from what is on the phone, the two preferences; sent only where the write-up runs, only when it changed, and
 * again when a model arrives, since a download changes the model without any preference changing.
 */

let android = true;
const generation = 20;
let models: ModelInfo[] = [];
const kept: JobConfig[] = [];
const invoke = vi.fn(async (command: string, args?: { config?: JobConfig }): Promise<unknown> => {
  if (command === 'ota_status') return { nativeGeneration: generation };
  if (command === 'ai_models') return models;
  if (command === 'ai_keep_job_config') {
    kept.push(args!.config!);
    return undefined;
  }
  throw new Error(`no ${command} here`);
});
vi.mock('../core/tauri.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/tauri.ts')>()),
  isTauri: () => true,
  invoke: (command: string, args?: { config?: JobConfig }) => invoke(command, args),
}));
vi.mock('../core/platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/platform.ts')>()),
  get isAndroid() {
    return android;
  },
}));

const { forgetSentJobConfig, jobConfigFor, keepJobConfigCurrent, sendJobConfig } = await import('./jobConfig.ts');
const { NOTES_CONTEXT, PIECE_CONTEXT, RECORDING_NOTES_PROMPT, RECORDING_SUMMARY_PROMPT } = await import('../format/prompt.ts');
const { reloadPreferences, setPreferences } = await import('../core/preferences.ts');
const { announceModelsChanged } = await import('../core/ai.ts');

const model = (id: string, present: boolean): ModelInfo => ({ id, file: `${id}.gguf`, bytes: 0, present, path: '' });
const settle = async () => {
  for (let i = 0; i < 20; i += 1) await Promise.resolve();
};

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
  forgetSentJobConfig();
  android = true;
  models = [];
  kept.length = 0;
  invoke.mockClear();
});

describe('the config', () => {
  it('puts each prompt where the write-up reads it, and names the model the page would run', () => {
    const config = jobConfigFor([model('qwen3.5-2b', true), model('qwen3.5-4b', false)], { formatModel: 'qwen3.5-4b', writeUp: 'now', summaries: 'meetings' });
    expect(config.prompts).toEqual({ summary: RECORDING_SUMMARY_PROMPT, notes: RECORDING_NOTES_PROMPT, piece: PIECE_CONTEXT, parts: NOTES_CONTEXT });
    expect(config.model).toBe('qwen3.5-2b');
    expect([config.writeUp, config.summaries]).toEqual(['now', 'meetings']);
    // No model at all: the one chosen, which the phone reports it needs.
    expect(jobConfigFor([], { formatModel: 'qwen3.5-4b', writeUp: 'charging', summaries: 'off' }).model).toBe('qwen3.5-4b');
  });
});

describe('sending it', () => {
  it('goes to Android with the write-up, once for each change, and never elsewhere', async () => {
    await sendJobConfig();
    expect(kept).toHaveLength(1);
    await sendJobConfig();
    expect(kept).toHaveLength(1);
    setPreferences({ writeUp: 'now' });
    await sendJobConfig();
    expect(kept.map((config) => config.writeUp)).toEqual(['charging', 'now']);
    android = false;
    setPreferences({ writeUp: 'charging' });
    await sendJobConfig();
    expect(kept).toHaveLength(2);
  });

  it('is sent again when a model arrives, and not for a preference that has nothing to do with it', async () => {
    const stop = keepJobConfigCurrent();
    await settle();
    expect(kept.map((config) => config.model)).toEqual(['qwen3.5-4b']);
    invoke.mockClear();
    setPreferences({ openNotes: ['n1'] });
    await settle();
    expect(invoke).not.toHaveBeenCalledWith('ai_models', undefined);
    models = [model('qwen3.5-2b', true)];
    announceModelsChanged();
    await settle();
    expect(kept.map((config) => config.model)).toEqual(['qwen3.5-4b', 'qwen3.5-2b']);
    stop();
  });
});
