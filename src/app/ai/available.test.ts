import { describe, expect, it } from 'vitest';
import type { ModelInfo } from '../core/ai.ts';
import { availability, modelFor } from './available.ts';

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
