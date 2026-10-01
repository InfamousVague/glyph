import { afterEach, describe, expect, it } from 'vitest';
import { modelFor } from '../ai/available.ts';
import { cannotRun, isTemplateFailure, markCannotRun, runnable } from './runnable.ts';

/*
 * A model this build cannot run (core/runnable.ts; GLY-2, GLY-5): remembered when it fails on its chat template,
 * passed over while another is on the phone, and still the one tried when it is the only one.
 */

afterEach(() => localStorage.clear());

describe('a model this build cannot run', () => {
  it('is known by the engine’s failure to apply its chat template', () => {
    expect(isTemplateFailure('cannot apply the chat template: ffi error -1')).toBe(true);
    expect(isTemplateFailure('cannot apply the chat template (ffi error -1): the model’s chat template cannot be rendered')).toBe(true);
    expect(isTemplateFailure('the window is 1024')).toBe(false);
  });

  it('is remembered, and passed over while another is on the phone', async () => {
    expect(cannotRun('gemma-4-e4b')).toBe(false);
    expect(modelFor(['gemma-4-e4b', 'qwen3.5-4b'], 'gemma-4-e4b')).toBe('gemma-4-e4b');
    await markCannotRun('gemma-4-e4b');
    expect(cannotRun('gemma-4-e4b')).toBe(true);
    expect(runnable(['gemma-4-e4b', 'qwen3.5-4b'])).toEqual(['qwen3.5-4b']);
    // Chosen, it gives way to the biggest model there that can run.
    expect(modelFor(['gemma-4-e4b', 'qwen3.5-2b', 'qwen3.5-4b'], 'gemma-4-e4b')).toBe('qwen3.5-4b');
  });

  it('is still the one tried when it is the only model, so its failure is said', async () => {
    await markCannotRun('gemma-4-e4b');
    expect(runnable(['gemma-4-e4b'])).toEqual(['gemma-4-e4b']);
    expect(modelFor(['gemma-4-e4b'], 'gemma-4-e4b')).toBe('gemma-4-e4b');
  });

  it('is asked again by a newer binary, which may carry the fix', () => {
    localStorage.setItem('glyph-models-cannot-run', JSON.stringify({ 'gemma-4-e4b': '0.11.0' }));
    // In a browser the binary's version is '', not the one it failed on.
    return Promise.resolve().then(() => {
      expect(cannotRun('gemma-4-e4b')).toBe(false);
      expect(modelFor(['gemma-4-e4b', 'qwen3.5-4b'], 'gemma-4-e4b')).toBe('gemma-4-e4b');
    });
  });
});
