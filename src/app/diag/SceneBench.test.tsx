import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import type { Output, RunOptions } from '../core/ai.ts';
import { button, press, rerender, show, unmount } from '../../test/render.tsx';

// The kit reads matchMedia as it loads, and the scene's haze watches its list's size; jsdom has neither.
await vi.hoisted(async () => {
  const stubs = await import('../../test/stubs.ts');
  stubs.stubMatchMedia();
  stubs.stubResizeObserver();
});

/** The real engine's seam: a run that reaches it is one the script did not play. */
const fakes = vi.hoisted(() => [] as { options: RunOptions; cancel: () => void }[]);
vi.mock('../core/ai.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../core/ai.ts')>();
  return {
    ...real,
    generate: (options: RunOptions) => {
      let reject: (failure: Error) => void = () => undefined;
      const done = new Promise<Output>((_, rej) => {
        reject = rej;
      });
      const fake = { options, cancel: () => reject(new Error('cancelled')) };
      fakes.push(fake);
      return { done, cancel: fake.cancel };
    },
  };
});

const { BENCH_NOTE, SceneBench } = await import('./SceneBench.tsx');
const { forgetAllRuns, runFor, startRun } = await import('../ai/runs.ts');
const { HOLD_MS, LEAVE_MS } = await import('../scene/steps.ts');

/**
 * The scene bench: the scene under its bar, played from the script to done, played again on the word, and its run
 * cancelled and put away on close, after which a run reaches the real engine and not the script.
 */

const dialog = () => document.querySelector<HTMLElement>('[role="dialog"][aria-label="The phone at work"]');
const scene = () => document.querySelector<HTMLElement>('[aria-label="The models at work on this note"]');
const title = () => scene()?.querySelector('h2')?.textContent ?? null;
const later = (ms: number) => act(() => vi.advanceTimersByTimeAsync(ms));

/** The stages take this long: eleven listen ticks, then comparing. */
const STAGES_MS = 250 * 11 + 600;

beforeEach(() => {
  vi.useFakeTimers();
  localStorage.clear();
  fakes.length = 0;
});

afterEach(async () => {
  unmount();
  await act(async () => {
    forgetAllRuns();
    await vi.advanceTimersByTimeAsync(10);
  });
  vi.useRealTimers();
});

describe('the scene bench', () => {
  it('is nothing while closed', () => {
    show(<SceneBench script={null} onClose={() => undefined} />);
    expect(dialog()).toBeNull();
    expect(scene()).toBeNull();
  });

  it('opens with the scene under its bar, and plays the script to done', async () => {
    show(<SceneBench script="heat" onClose={() => undefined} />);
    expect(dialog()).not.toBeNull();
    expect(scene()).not.toBeNull();
    expect(dialog()?.contains(scene())).toBe(true);
    expect(dialog()?.querySelector('h2')?.textContent).toBe('The phone at work');
    expect(scene()?.hasAttribute('data-inline')).toBe(true);
    expect(title()).toBe('Listening again.');
    await later(1000);
    expect(title()).toBe('Listening again, 40%.');
    await later(STAGES_MS);
    // The run, played by the script and not the engine.
    expect(runFor(BENCH_NOTE)?.phase).toBe('loading');
    expect(fakes.length).toBe(0);
    expect(title()).toBe('Loading Qwen3.5 4B.');
    await later(1800 + 300);
    expect(title()).toMatch(/^Reading the note, \d+ of 1040\.$/);
    expect(scene()?.querySelectorAll('[data-pin]').length).toBe(8);
    await later(2400 + 400);
    expect(title()).toBe('Qwen3.5 4B is thinking it through.');
    // The heat script carries a temperature: the tile reads it, and the die lights.
    const heat = [...scene()!.querySelectorAll('dt')].find((dt) => dt.textContent === 'Heat')?.nextElementSibling?.textContent;
    expect(heat).toMatch(/^\d+ °C$/);
    expect(scene()?.querySelectorAll('[data-lit]').length).toBeGreaterThan(0);
    // On to the end, a moment at a time: the scene begins to leave the instant the run ends.
    for (let i = 0; i < 200 && runFor(BENCH_NOTE)?.phase !== 'done'; i += 1) await later(100);
    expect(runFor(BENCH_NOTE)?.phase).toBe('done');
    expect(title()).toMatch(/^Reviewed by Qwen3.5 4B in \d+:\d\d\.$/);
    await later(HOLD_MS + LEAVE_MS + 10);
    expect(scene()).toBeNull();
    expect(dialog()).not.toBeNull();
  });

  it('plays again on the word', async () => {
    show(<SceneBench script="cold" onClose={() => undefined} />);
    await later(STAGES_MS + 1000);
    expect(title()).toBe('Loading Qwen3.5 4B.');
    press(button('Play again'));
    expect(scene()).not.toBeNull();
    expect(title()).toBe('Listening again.');
    // The earlier run was cancelled and put away, so the scene does not take it for its own.
    await later(20);
    expect(runFor(BENCH_NOTE)).toBeNull();
  });

  it('cancels and puts away its run on close, after which a run reaches the engine and not the script', async () => {
    const onClose = vi.fn();
    show(<SceneBench script="heat" onClose={onClose} />);
    await later(STAGES_MS + 1000);
    expect(runFor(BENCH_NOTE)?.phase).toBe('loading');
    press(button('Close'));
    expect(onClose).toHaveBeenCalledOnce();
    rerender(<SceneBench script={null} onClose={onClose} />);
    await later(20);
    expect(dialog()).toBeNull();
    expect(runFor(BENCH_NOTE)).toBeNull();
    await act(async () => {
      startRun({ noteId: 'real', kind: 'format', model: 'qwen3.5-4b', system: 's', prompt: 'p', maxTokens: 100 });
    });
    expect(fakes.length).toBe(1);
    expect(runFor('real')?.phase).toBe('loading');
  });

  it('closes on the back gesture', async () => {
    const onClose = vi.fn();
    show(<SceneBench script="none" onClose={onClose} />);
    const { goBack } = await import('../core/back.ts');
    // The scene's own back is armed a commit later than the bench's, so the first gesture is the scene's.
    act(() => {
      goBack();
    });
    expect(scene()).toBeNull();
    expect(onClose).not.toHaveBeenCalled();
    act(() => {
      goBack();
    });
    expect(onClose).toHaveBeenCalledOnce();
  });
});
