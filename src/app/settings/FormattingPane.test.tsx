import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import type { ModelInfo } from '../core/ai.ts';
import { button, show } from '../../test/render.tsx';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

// In the app, or in a browser, as each test says; the models on the phone are the list below.
let native = true;
vi.mock('../core/tauri.ts', () => ({ isTauri: () => native, invoke: () => Promise.reject(new Error('no binary in a test')) }));
let present: string[] = [];
let download: { id: string; received: number; total: number } | null = null;
const fetchModel = vi.fn(async (_id: string) => undefined);
const removeModel = vi.fn(async (id: string) => {
  present = present.filter((p) => p !== id);
});
vi.mock('../core/ai.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../core/ai.ts')>();
  return {
    ...real,
    useModels: () => ({
      models: real.MODELS.map((m) => ({ ...m, present: present.includes(m.id) }) as unknown as ModelInfo),
      download,
      problem: null,
      fetch: fetchModel,
      remove: removeModel,
      refresh: async () => undefined,
    }),
  };
});

const { FormattingPane } = await import('./FormattingPane.tsx');
const { DEFAULT_MODEL } = await import('../core/ai.ts');
const { preferences, setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');

/**
 * The Formatting page: the models, which are on the phone, choosing one, getting one, and what is chosen when the
 * chosen one is removed. The downloads and the models' files are core/ai.ts's; this is the page over them.
 */

beforeEach(() => {
  native = true;
  present = [];
  download = null;
  fetchModel.mockClear();
  removeModel.mockClear();
  setPreferences(DEFAULT_PREFERENCES);
});

afterEach(() => {
  setPreferences(DEFAULT_PREFERENCES);
});

/** The row a model's name labels, in the card titled `card`. */
function rowIn(host: HTMLElement, card: string, model: string): HTMLElement {
  const section = [...host.querySelectorAll('section')].find((s) => s.querySelector('.setk__title')?.textContent === card && s.textContent?.includes(model));
  const row = [...(section?.querySelectorAll<HTMLElement>('.setk-row') ?? [])].find((r) => r.querySelector('.setk-row__label')?.textContent === model);
  if (!row) throw new Error(`no ${model} in ${card}`);
  return row;
}

describe('the Formatting page', () => {
  it('in a browser, says the models run on the phone and offers none', () => {
    native = false;
    const host = show(<FormattingPane />);
    expect(host.textContent).toContain('Formatting runs on the phone.');
    expect(host.querySelector('[role="radio"]')).toBeNull();
  });

  it('offers Get for a model not on the phone, and a choice for one that is', () => {
    present = ['qwen3.5-2b'];
    const host = show(<FormattingPane />);
    act(() => button('Get', rowIn(host, 'Model', 'Qwen3.5 9B')).click());
    expect(fetchModel).toHaveBeenCalledWith('qwen3.5-9b');
    const pick = rowIn(host, 'Model', 'Qwen3.5 2B').querySelector<HTMLButtonElement>('[role="radio"]')!;
    act(() => pick.click());
    expect(preferences().formatModel).toBe('qwen3.5-2b');
    expect(host.textContent).toContain('1.3 GB of storage.');
  });

  it('holds every Get while one model is coming down, and shows it arriving', () => {
    download = { id: 'qwen3.5-4b', received: 1e9, total: 2.7e9 };
    const host = show(<FormattingPane />);
    expect(host.textContent).toContain('Getting Qwen3.5 4B, 1.0 GB of 2.7 GB. Keep Ghost.md open.');
    expect(button('Get', rowIn(host, 'Model', 'Qwen3.5 9B')).disabled).toBe(true);
  });

  it('chooses another model on the phone when the chosen one is removed, and the default when none is left', async () => {
    present = ['qwen3.5-2b', 'qwen3.5-9b'];
    setPreferences({ formatModel: 'qwen3.5-9b' });
    let host = show(<FormattingPane />);
    await act(async () => button('Remove', rowIn(host, 'On the phone', 'Qwen3.5 9B')).click());
    expect(removeModel).toHaveBeenCalledWith('qwen3.5-9b');
    expect(preferences().formatModel).toBe('qwen3.5-2b');
    host = show(<FormattingPane />);
    await act(async () => button('Remove', rowIn(host, 'On the phone', 'Qwen3.5 2B')).click());
    expect(preferences().formatModel).toBe(DEFAULT_MODEL);
  });

  it('leaves the choice alone when a model that was not chosen is removed', async () => {
    present = ['qwen3.5-2b', 'qwen3.5-9b'];
    setPreferences({ formatModel: 'qwen3.5-9b' });
    const host = show(<FormattingPane />);
    await act(async () => button('Remove', rowIn(host, 'On the phone', 'Qwen3.5 2B')).click());
    expect(preferences().formatModel).toBe('qwen3.5-9b');
  });

  it('switches Local only, and says what it holds off', () => {
    const host = show(<FormattingPane />);
    act(() => host.querySelector<HTMLElement>('[aria-label="Local only"]')!.click());
    expect(preferences().localOnly).toBe(true);
    expect(host.textContent).toContain('On. No update checks, no downloads, and plugins that use the network are off.');
  });
});
