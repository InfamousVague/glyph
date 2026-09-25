import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import type { Output, RunOptions } from '../core/ai.ts';

/** A model that answers when the test says so. */
const fakes: { options: RunOptions; finish: (text: string) => void; cancel: () => void }[] = [];

vi.mock('../core/ai.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../core/ai.ts')>();
  return {
    ...real,
    generate: (options: RunOptions) => {
      let resolve: (output: Output) => void = () => undefined;
      let reject: (failure: Error) => void = () => undefined;
      const done = new Promise<Output>((res, rej) => {
        resolve = res;
        reject = rej;
      });
      const fake = {
        options,
        finish: (text: string) => resolve({ text, promptTokens: 100, outputTokens: 20, ms: 42_000, cachedTokens: 0, prefillMs: 100, loadMs: 100, tokensPerSecond: 12, truncated: false }),
        cancel: () => reject(new Error('cancelled')),
      };
      fakes.push(fake);
      return { done, cancel: fake.cancel };
    },
  };
});

const { AiStrip } = await import('./AiStrip.tsx');
const { forgetAllRuns, startRun } = await import('./runs.ts');
const { recordChange } = await import('./log.ts');

let root: Root | null = null;
let host: HTMLDivElement | null = null;

function show(element: React.ReactElement): HTMLDivElement {
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
  act(() => root!.render(element));
  return host;
}

const tick = () => act(() => new Promise<void>((r) => setTimeout(r, 0)));

beforeEach(() => {
  localStorage.clear();
  fakes.length = 0;
});

afterEach(() => {
  act(() => root?.unmount());
  host?.remove();
  root = null;
  host = null;
  forgetAllRuns();
});

describe('the strip', () => {
  it('draws nothing for a note with no run', () => {
    const el = show(<AiStrip noteId="quiet" />);
    expect(el.textContent).toBe('');
  });

  it('says what the model is doing, with Stop, and then how it ended, with a way to put it away', async () => {
    const heights: number[] = [];
    const el = show(<AiStrip noteId="n" onHeight={(h) => heights.push(h)} />);
    let handle!: ReturnType<typeof startRun>;
    await act(async () => {
      handle = startRun({ noteId: 'n', kind: 'format', model: 'qwen3.5-4b', system: 's', prompt: 'p', maxTokens: 100 });
    });
    await tick();
    expect(el.textContent).toContain('Loading Qwen3.5 4B.');
    expect(el.querySelector('[aria-label="Stop"]')).not.toBeNull();
    await act(async () => {
      fakes[0]!.options.onProgress({ id: 'x', phase: 'generating', promptTokens: 100, promptTokensDone: 100, outputTokens: 25, tokensPerSecond: 20, elapsedMs: 3000, partial: '# Trip\n' });
    });
    expect(el.textContent).toContain('Formatting with Qwen3.5 4B, 20 tokens a second, 0:03, 1 line.');
    const bar = el.querySelector('span[style]') as HTMLElement;
    expect(bar.style.inlineSize).toBe('25%');
    await act(async () => {
      fakes[0]!.finish('# Trip\n');
      await handle.done;
    });
    expect(el.textContent).toContain('Formatted by Qwen3.5 4B in 0:42.');
    expect(el.querySelector('[aria-label="Stop"]')).toBeNull();
    // Nothing changed the note, so there is nothing to undo from the line.
    expect(el.querySelector('[aria-label="Undo this run"]')).toBeNull();
    (el.querySelector('[aria-label="Put this away"]') as HTMLButtonElement).click();
    await tick();
    expect(el.textContent).toBe('');
    expect(heights[heights.length - 1]).toBe(0);
  });

  it('opens the log under the line, with Undo for a run that changed the note', async () => {
    const undone: string[] = [];
    const el = show(<AiStrip noteId="n" onUndo={(record) => (undone.push(record.id), true)} />);
    let handle!: ReturnType<typeof startRun>;
    await act(async () => {
      handle = startRun({ noteId: 'n', kind: 'summarize', model: 'qwen3.5-2b', system: 's', prompt: 'p', maxTokens: 100 });
    });
    await tick();
    await act(async () => {
      fakes[0]!.finish('short\n');
      await handle.done;
    });
    await act(async () => recordChange('n', handle.id, 'before', 'after'));
    expect(el.querySelector('[aria-label="Undo this run"]')).not.toBeNull();
    (el.querySelector('[aria-expanded]') as HTMLButtonElement).click();
    await tick();
    expect(el.textContent).toContain('Summarize by Qwen3.5 2B in 0:42.');
    expect(el.textContent).toContain('Just now');
    const undo = [...el.querySelectorAll('button')].find((b) => b.textContent === 'Undo');
    undo?.click();
    expect(undone).toEqual([handle.id]);
  });

  it('says the review’s own stage while no run is on, with its percent along the foot', () => {
    const el = show(<AiStrip noteId="quiet" stage={{ what: 'Listening again', detail: 'The slower speech model is listening to the recording again.', percent: 40 }} />);
    expect(el.textContent).toContain('Listening again, 40%. The slower speech model is listening to the recording again.');
    const bar = el.querySelector('span[style]') as HTMLElement;
    expect(bar.style.inlineSize).toBe('40%');
  });

  it('shows a thinking model’s thought in the card', async () => {
    const el = show(<AiStrip noteId="n" />);
    await act(async () => {
      startRun({ noteId: 'n', kind: 'review', model: 'qwen3.5-4b', system: 's', prompt: 'p', maxTokens: 100, think: true });
    });
    await tick();
    await act(async () => {
      fakes[0]!.options.onProgress({ id: 'x', phase: 'generating', promptTokens: 10, promptTokensDone: 10, outputTokens: 5, tokensPerSecond: 9, elapsedMs: 2000, partial: '<think>Is seat right?', thinking: true });
    });
    expect(el.textContent).toContain('Qwen3.5 4B is thinking it through, 9.0 tokens a second, 0:02.');
    (el.querySelector('[aria-expanded]') as HTMLButtonElement).click();
    await tick();
    expect(el.querySelector('pre')?.textContent).toBe('Is seat right?');
    await act(async () => {
      fakes[0]!.cancel();
    });
  });

  it('stops the run from the line', async () => {
    const el = show(<AiStrip noteId="n" />);
    let handle!: ReturnType<typeof startRun>;
    await act(async () => {
      handle = startRun({ noteId: 'n', kind: 'enhance', model: 'qwen3.5-4b', system: 's', prompt: 'p', maxTokens: 100 });
    });
    await tick();
    await act(async () => {
      (el.querySelector('[aria-label="Stop"]') as HTMLButtonElement).click();
      await handle.done;
    });
    expect(el.textContent).toContain('Stopped.');
  });
});
