import { describe, expect, it, vi } from 'vitest';
import type { ModelInfo } from '../core/ai.ts';

/** A browser until a test says the page is on a phone, whose binary and catalogue it then answers for. */
let native = false;
let catalogue: ModelInfo[] = [];
vi.mock('../core/tauri.ts', () => ({
  isTauri: () => native,
  invoke: async (command: string) => (command === 'ota_status' ? { nativeGeneration: 19 } : command === 'ai_models' ? catalogue : null),
}));

const { show, waitUntil } = await import('../../test/render.tsx');
const { availability, modelFor, modelNow, presentIds, smallestOf, useAvailability } = await import('./available.ts');
const { setPreferences } = await import('../core/preferences.ts');

const model = (id: string, present: boolean): ModelInfo => ({ id, file: `${id}.gguf`, bytes: 1, present, path: '' });
const phone = { tauri: true, ios: false, localOnly: false, generation: 19 };

describe('which model runs', () => {
  it('is the chosen one when it is on the phone', () => {
    expect(modelFor(['qwen3.5-2b', 'qwen3.5-4b'], 'qwen3.5-4b')).toBe('qwen3.5-4b');
  });

  it('else the biggest no bigger than it, else the smallest there is', () => {
    expect(modelFor(['qwen3.5-2b', 'qwen3.5-9b'], 'qwen3.5-4b')).toBe('qwen3.5-2b');
    expect(modelFor(['qwen3.5-9b', 'gemma-4-e4b'], 'qwen3.5-2b')).toBe('gemma-4-e4b');
    expect(modelFor([], 'qwen3.5-4b')).toBeNull();
  });

  it('is chosen from the models the catalogue says are on the phone, and the gist takes the smallest', () => {
    const catalogue = [model('qwen3.5-9b', true), model('qwen3.5-4b', false), model('qwen3.5-2b', true)];
    expect(presentIds(catalogue)).toEqual(['qwen3.5-9b', 'qwen3.5-2b']);
    expect(smallestOf(presentIds(catalogue))).toBe('qwen3.5-2b');
    expect(smallestOf([])).toBeNull();
  });
});

describe('whether the AI can run here', () => {
  it('runs on the phone with a model on it', () => {
    expect(availability([model('qwen3.5-4b', true)], 'qwen3.5-4b', phone)).toEqual({ ok: true, model: 'qwen3.5-4b', chosen: 'qwen3.5-4b' });
    expect(availability([model('qwen3.5-2b', true)], 'qwen3.5-4b', phone)).toEqual({ ok: true, model: 'qwen3.5-2b', chosen: 'qwen3.5-4b' });
  });

  it('says why not, in a sentence, where it cannot', () => {
    expect(availability([], 'qwen3.5-4b', { ...phone, tauri: false })).toMatchObject({ ok: false, reason: expect.stringContaining('Install Ghost.md on Android'), get: null });
    expect(availability([], 'qwen3.5-4b', { ...phone, ios: true })).toMatchObject({ ok: false, reason: 'The AI is not on iOS yet.' });
    expect(availability([model('qwen3.5-4b', true)], 'qwen3.5-4b', { ...phone, generation: 9 })).toMatchObject({ ok: false, reason: expect.stringContaining('newest Ghost.md') });
    expect(availability([model('qwen3.5-4b', true)], 'qwen3.5-4b', { ...phone, generation: 10 })).toMatchObject({ ok: true });
  });

  it('waits while the catalogue is read, and offers the chosen model when none is here', () => {
    expect(availability([], 'qwen3.5-4b', phone)).toMatchObject({ ok: false, waiting: true });
    expect(availability([model('qwen3.5-4b', false)], 'qwen3.5-4b', phone)).toMatchObject({ ok: false, get: 'qwen3.5-4b', waiting: false });
    expect(availability([model('qwen3.5-4b', false)], 'qwen3.5-4b', { ...phone, localOnly: true })).toMatchObject({ ok: false, get: null, reason: expect.stringContaining('Local only') });
  });
});

describe('the answer as a screen sees it', () => {
  /** What the hook answers on its latest render. */
  function mounted() {
    const seen: { current: ReturnType<typeof useAvailability> | null } = { current: null };
    function Screen() {
      seen.current = useAvailability();
      return null;
    }
    show(<Screen />);
    return seen;
  }

  it('says the AI runs on the phone, in a browser', async () => {
    native = false;
    const seen = mounted();
    await waitUntil(() => expect(seen.current?.availability).toMatchObject({ ok: false, reason: expect.stringContaining('runs on the phone') }));
  });

  it('runs the chosen model on a phone that has it, and the next one down when it does not', async () => {
    native = true;
    catalogue = [model('qwen3.5-2b', true), model('qwen3.5-4b', true)];
    setPreferences({ formatModel: 'qwen3.5-4b' });
    const seen = mounted();
    await waitUntil(() => expect(seen.current?.availability).toEqual({ ok: true, model: 'qwen3.5-4b', chosen: 'qwen3.5-4b' }));
    expect(seen.current?.models.map((m) => m.id)).toEqual(['qwen3.5-2b', 'qwen3.5-4b']);
    // Outside React, from the catalogue as last read: the same rule.
    expect(modelNow([model('qwen3.5-2b', true), model('qwen3.5-4b', false)])).toBe('qwen3.5-2b');
  });
});
