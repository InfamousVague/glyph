import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Progress } from '../core/ai.ts';
import type { ReviewStage } from '../ai/useNoteReview.ts';
import { SCRIPT_BODY, SCRIPT_HEARD, sceneQuery, scriptedReview, scriptedStages } from './scripted.ts';

/**
 * The script the bench plays: the stages and then the run's phases in order, at the engine's cadence, with the
 * phone's readings from the first prefill tick on, a temperature only when asked for, and a clean stop.
 */

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
  window.history.replaceState(null, '', '/');
  Reflect.deleteProperty(window, '__TAURI_INTERNALS__');
});

describe('the stages', () => {
  it('listen again in tens every quarter second, compare for a moment, then clear', () => {
    const seen: (ReviewStage | null)[] = [];
    scriptedStages((stage) => seen.push(stage));
    expect(seen[0]).toMatchObject({ what: 'Listening again', percent: 0 });
    vi.advanceTimersByTime(250);
    expect(seen.at(-1)).toMatchObject({ what: 'Listening again', percent: 10 });
    vi.advanceTimersByTime(2250);
    expect(seen.at(-1)).toMatchObject({ what: 'Listening again', percent: 100 });
    vi.advanceTimersByTime(250);
    expect(seen.at(-1)).toMatchObject({ what: 'Comparing', detail: '3 places where the two models heard different words.', percent: null });
    vi.advanceTimersByTime(600);
    expect(seen.at(-1)).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('can be stopped', () => {
    const seen: (ReviewStage | null)[] = [];
    const stop = scriptedStages((stage) => seen.push(stage));
    vi.advanceTimersByTime(500);
    stop();
    const were = seen.length;
    vi.advanceTimersByTime(5000);
    expect(seen.length).toBe(were);
    expect(vi.getTimerCount()).toBe(0);
  });
});

describe('the run', () => {
  const play = (script: 'heat' | 'cold' | 'none') => {
    const reports: Progress[] = [];
    const run = scriptedReview(script)({ model: 'qwen3.5-4b', system: '', prompt: 'p', maxTokens: 1900, temperature: 0.2, onProgress: (p) => reports.push(p) });
    return { reports, run };
  };

  it('reports loading, then reading in ticks, then the thought and the findings, then done', async () => {
    const { reports, run } = play('heat');
    expect(reports.map((r) => r.phase)).toEqual(['loading']);
    expect(reports[0]?.hardware).toBeUndefined();
    await vi.advanceTimersByTimeAsync(1800 + 2400 + 10);
    const prefill = reports.filter((r) => r.phase === 'prefill');
    expect(prefill.length).toBe(9);
    expect(prefill.map((r) => r.promptTokensDone)).toEqual([128, 256, 384, 512, 640, 768, 896, 1024, 1040]);
    // The first sample is a new sampler's and reads 0; the rest ramp to six and a half cores busy.
    expect(prefill[0]?.hardware?.cpuPercent).toBe(0);
    expect(prefill.at(-1)?.hardware?.cpuPercent).toBe(640);
    expect(prefill.at(-1)?.hardware).toMatchObject({ cores: 8, threads: 6 });
    expect(prefill.at(-1)?.hardware?.tempC).toBeGreaterThan(31);
    await vi.advanceTimersByTimeAsync(30_000);
    const generating = reports.filter((r) => r.phase === 'generating');
    expect(generating.length).toBeGreaterThan(20);
    expect(generating[0]?.partial.startsWith('<think>')).toBe(true);
    expect(generating[0]?.thinking).toBe(true);
    expect(generating.at(-1)?.partial).toContain('"what"');
    const output = await run.done;
    expect(output.text).toContain('</think>');
    expect(JSON.parse(output.text.slice(output.text.indexOf('</think>') + '</think>'.length)).length).toBe(2);
    expect(output.promptTokens).toBe(1040);
    expect(output.thinking).toBe(true);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('carries a temperature only for the heat script, and no readings at all for none', async () => {
    const cold = play('cold');
    const none = play('none');
    await vi.advanceTimersByTimeAsync(1800 + 2400 + 500);
    const coldRead = cold.reports.find((r) => r.phase === 'generating');
    expect(coldRead?.hardware).toBeTruthy();
    expect(coldRead?.hardware?.tempC).toBeUndefined();
    const noneRead = none.reports.find((r) => r.phase === 'generating');
    expect(noneRead?.hardware).toBeNull();
    cold.run.cancel();
    none.run.cancel();
    await expect(cold.run.done).rejects.toThrow('cancelled');
    await expect(none.run.done).rejects.toThrow('cancelled');
  });

  it('answers cancelled at once when stopped, and leaves no timer', async () => {
    const { reports, run } = play('heat');
    await vi.advanceTimersByTimeAsync(3000);
    const were = reports.length;
    run.cancel();
    await expect(run.done).rejects.toThrow('cancelled');
    await vi.advanceTimersByTimeAsync(5000);
    expect(reports.length).toBe(were);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('has a transcript with the mishearing in it, and the note those words made', () => {
    expect(SCRIPT_HEARD).toContain('seat bar');
    expect(SCRIPT_BODY).toContain('seat bar');
    expect(SCRIPT_BODY.startsWith('# ')).toBe(true);
  });
});

describe('the query', () => {
  it('reads ?scene= in a browser, and nothing under Tauri', () => {
    expect(sceneQuery()).toBeNull();
    window.history.replaceState(null, '', '/?scene=heat');
    expect(sceneQuery()).toBe('heat');
    window.history.replaceState(null, '', '/?scene=none');
    expect(sceneQuery()).toBe('none');
    window.history.replaceState(null, '', '/?scene=other');
    expect(sceneQuery()).toBeNull();
    window.history.replaceState(null, '', '/?scene=cold');
    Object.defineProperty(window, '__TAURI_INTERNALS__', { configurable: true, value: {} });
    expect(sceneQuery()).toBeNull();
  });
});
