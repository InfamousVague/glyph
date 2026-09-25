import { act } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { show, unmount } from '../../test/render.tsx';
import type { ModelInfo, Progress } from './ai.ts';

/*
 * The on-device model from the page's side (ai.ts): the catalogue and what is on the phone, a download and a
 * removal, and a run streaming its progress. A phone is core/tauri.ts mocked; the engine's events come through
 * core/events.ts, also mocked, so a test can say what Rust reports and when.
 */

let native = true;
const invoked: { command: string; args: unknown }[] = [];
/** Each command's answer by name: a value, or a function of the arguments that may throw. */
const answers = new Map<string, unknown>();

vi.mock('./tauri.ts', () => ({
  isTauri: () => native,
  invoke: async (command: string, args?: unknown) => {
    invoked.push({ command, args });
    const answer = answers.get(command);
    return typeof answer === 'function' ? (answer as (args: unknown) => unknown)(args) : answer;
  },
}));

/** Every listener attached, by event, and what was invoked at the moment it was. */
const listeners = new Map<string, (payload: unknown) => void>();
const invokedWhenListening: string[][] = [];
let unlistened = 0;
vi.mock('./events.ts', () => ({
  listenTo: async (event: string, handler: (payload: unknown) => void) => {
    listeners.set(event, handler);
    invokedWhenListening.push(invoked.map((call) => call.command));
    return () => {
      listeners.delete(event);
      unlistened += 1;
    };
  },
}));

const { gb, generate, listModels, modelName, useModels } = await import('./ai.ts');
const { setPreferences } = await import('./preferences.ts');

const HERE: ModelInfo = { id: 'qwen3.5-2b', file: 'q2.gguf', bytes: 1_280_835_840, present: true, path: '/models/q2.gguf' };
const AWAY: ModelInfo = { id: 'qwen3.5-4b', file: 'q4.gguf', bytes: 2_740_937_888, present: false, path: '/models/q4.gguf' };

beforeEach(() => {
  native = true;
  invoked.length = 0;
  answers.clear();
  listeners.clear();
  invokedWhenListening.length = 0;
  unlistened = 0;
  localStorage.clear();
  setPreferences({ localOnly: false });
});

afterEach(() => {
  unmount();
});

describe('the catalogue', () => {
  it('names a model by its id, and a size as a person reads it', () => {
    expect(modelName('qwen3.5-9b')).toBe('Qwen3.5 9B');
    expect(modelName('someone-elses')).toBe('someone-elses');
    expect(gb(2_740_937_888)).toBe('2.7 GB');
  });

  it('is empty in a browser, which has no engine, and the phone’s own list on a phone', async () => {
    native = false;
    expect(await listModels()).toEqual([]);
    expect(invoked).toEqual([]);
    native = true;
    answers.set('ai_models', [HERE, AWAY]);
    expect(await listModels()).toEqual([HERE, AWAY]);
  });
});

describe('the models on the phone', () => {
  let models: ReturnType<typeof useModels> | null = null;
  function Models() {
    models = useModels();
    return null;
  }

  /** Lets what is queued land, inside act since the hook follows it. */
  const flush = () => act(async () => new Promise((resolve) => setTimeout(resolve, 0)));

  beforeEach(() => {
    models = null;
    answers.set('ai_models', [HERE, AWAY]);
  });

  it('reads what is on the phone at once, and again when the app comes back', async () => {
    show(<Models />);
    await flush();
    expect(models?.models).toEqual([HERE, AWAY]);
    answers.set('ai_models', [HERE, { ...AWAY, present: true }]);
    document.dispatchEvent(new Event('visibilitychange'));
    await flush();
    expect(models?.models[1]?.present).toBe(true);
  });

  it('downloads a model with its own progress shown, then reads the phone again', async () => {
    let finish: () => void = () => undefined;
    answers.set('ai_fetch_model', () => new Promise<void>((resolve) => (finish = resolve)));
    show(<Models />);
    await flush();
    let fetching: Promise<void> = Promise.resolve();
    act(() => {
      fetching = models!.fetch('qwen3.5-4b');
    });
    await flush();
    expect(models?.download).toEqual({ id: 'qwen3.5-4b', received: 0, total: 2_740_937_888 });
    act(() => listeners.get('ai://model-progress')?.({ id: 'qwen3.5-9b', receivedBytes: 5, totalBytes: 9 }));
    act(() => listeners.get('ai://model-progress')?.({ id: 'qwen3.5-4b', receivedBytes: 1_000, totalBytes: 2_000 }));
    expect(models?.download).toEqual({ id: 'qwen3.5-4b', received: 1_000, total: 2_000 });
    // A second tap while one is coming is not a second download.
    await act(() => models!.fetch('qwen3.5-2b'));
    answers.set('ai_models', [HERE, { ...AWAY, present: true }]);
    await act(async () => {
      finish();
      await fetching;
    });
    expect(models?.download).toBeNull();
    expect(models?.models[1]?.present).toBe(true);
    expect(invoked.filter((call) => call.command === 'ai_fetch_model')).toEqual([{ command: 'ai_fetch_model', args: { id: 'qwen3.5-4b' } }]);
    expect(unlistened).toBe(1);
  });

  it('says why a download or a removal failed, and downloads nothing with Nothing leaves the phone on', async () => {
    answers.set('ai_fetch_model', () => {
      throw new Error('The phone ran out of room.');
    });
    answers.set('ai_delete_model', () => {
      throw new Error('The model is in use.');
    });
    show(<Models />);
    await flush();
    await act(() => models!.fetch('qwen3.5-4b'));
    expect(models?.problem).toBe('The phone ran out of room.');
    expect(models?.download).toBeNull();
    await act(() => models!.remove('qwen3.5-2b'));
    expect(models?.problem).toBe('The model is in use.');

    setPreferences({ localOnly: true });
    invoked.length = 0;
    await act(() => models!.fetch('qwen3.5-4b'));
    expect(models?.problem).toBe('Local only is on, so nothing is downloaded. Turn it off in Settings to get a model.');
    expect(invoked).toEqual([]);
  });

  it('removes a model and reads the phone again', async () => {
    show(<Models />);
    await flush();
    answers.set('ai_models', [{ ...HERE, present: false }, AWAY]);
    await act(() => models!.remove('qwen3.5-2b'));
    expect(invoked.some((call) => call.command === 'ai_delete_model')).toBe(true);
    expect(models?.models[0]?.present).toBe(false);
    expect(models?.problem).toBeNull();
  });
});

describe('a run', () => {
  const options = { model: 'qwen3.5-4b', system: 'Be brief.', prompt: 'Tidy this.', maxTokens: 64, temperature: 0.2 };

  it('listens before it asks, hears only its own reports, and stops listening when it ends', async () => {
    const heard: Progress[] = [];
    answers.set('ai_generate', (args: { request: { id: string } }) => {
      const report = (id: string): Progress => ({ id, phase: 'generating', promptTokens: 3, promptTokensDone: 3, outputTokens: 1, tokensPerSecond: 9, elapsedMs: 5, partial: 'T' });
      listeners.get('ai://progress')?.(report('someone-else'));
      listeners.get('ai://progress')?.(report(args.request.id));
      return { text: 'Tidied.', promptTokens: 3, outputTokens: 2, ms: 10, cachedTokens: 0, prefillMs: 1, loadMs: 1, tokensPerSecond: 9, truncated: false };
    });
    const run = generate({ ...options, onProgress: (progress) => heard.push(progress) });
    expect((await run.done).text).toBe('Tidied.');
    expect(invokedWhenListening).toEqual([[]]);
    expect(heard).toHaveLength(1);
    expect(unlistened).toBe(1);
    expect(invoked[0]).toEqual({
      command: 'ai_generate',
      args: { request: { id: heard[0]!.id, model: 'qwen3.5-4b', system: 'Be brief.', context: null, prompt: 'Tidy this.', maxTokens: 64, temperature: 0.2, think: false, thinkBudget: 0 } },
    });
  });

  it('answers with the engine’s sentence when it fails, and still stops listening', async () => {
    answers.set('ai_generate', () => {
      throw new Error('cancelled');
    });
    const run = generate({ ...options, onProgress: () => undefined });
    await expect(run.done).rejects.toThrow('cancelled');
    expect(unlistened).toBe(1);
  });

  it('is cancelled by its own id, and each run has one of its own', async () => {
    answers.set('ai_generate', () => new Promise(() => undefined));
    const one = generate({ ...options, onProgress: () => undefined });
    generate({ ...options, onProgress: () => undefined });
    await new Promise((resolve) => setTimeout(resolve, 0));
    one.cancel();
    const ids = invoked.filter((call) => call.command === 'ai_generate').map((call) => (call.args as { request: { id: string } }).request.id);
    expect(new Set(ids).size).toBe(2);
    expect(invoked.at(-1)).toEqual({ command: 'ai_cancel', args: { id: ids[0] } });
  });

  it('refuses in a browser, where there is no engine, and cancelling there does nothing', async () => {
    native = false;
    const run = generate({ ...options, onProgress: () => undefined });
    await expect(run.done).rejects.toThrow('Formatting runs on the phone. Install Ghost.md to use it.');
    run.cancel();
    expect(invoked).toEqual([]);
  });
});
