import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import type { ModelInfo } from '../core/ai.ts';
import { button, buttonSaying, show } from '../../test/render.tsx';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

// In the app; the models on the phone are the list below.
vi.mock('../core/tauri.ts', () => ({ isTauri: () => true, invoke: () => Promise.reject(new Error('no binary in a test')) }));
// On an Android phone, or on the Mac.
let android = true;
vi.mock('../core/platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/platform.ts')>()),
  get isAndroid() {
    return android;
  },
}));
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

const { ModelCard } = await import('./ModelCard.tsx');
const { preferences, setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');

/**
 * The Model card on Recording (docs/DESIGN.md §138): each model once, choosing one, getting one, and removing one
 * that is here but not in use. The downloads and the models' files are core/ai.ts's; this is the card over them.
 */

beforeEach(() => {
  android = true;
  present = [];
  download = null;
  fetchModel.mockClear();
  removeModel.mockClear();
  setPreferences(DEFAULT_PREFERENCES);
});

/** The row a model's name labels. */
function row(host: HTMLElement, model: string): HTMLElement {
  const found = [...host.querySelectorAll<HTMLElement>('.setk-row')].find((r) => r.querySelector('.setk-row__label')?.textContent === model);
  if (!found) throw new Error(`no ${model}`);
  return found;
}

describe('the Model card', () => {
  it('lists every model once, in one card', () => {
    present = ['qwen3.5-2b'];
    const host = show(<ModelCard />);
    expect([...host.querySelectorAll('.setk__title')].map((t) => t.textContent)).toEqual(['Model']);
    expect([...host.querySelectorAll('.setk-row__label')].map((l) => l.textContent)).toEqual(['Qwen3.5 2B', 'Qwen3.5 4B', 'Qwen3.5 9B', 'Gemma 4 E4B']);
  });

  it('offers Get for a model not here, and a choice for one that is, with what they take in the footer', () => {
    present = ['qwen3.5-2b'];
    const host = show(<ModelCard />);
    act(() => button('Get', row(host, 'Qwen3.5 9B')).click());
    expect(fetchModel).toHaveBeenCalledWith('qwen3.5-9b');
    act(() => row(host, 'Qwen3.5 2B').querySelector<HTMLButtonElement>('[role="radio"]')!.click());
    expect(preferences().formatModel).toBe('qwen3.5-2b');
    expect(host.querySelector('.setk__footer')?.textContent).toBe('1.3 GB on the phone.');
  });

  it('holds every Get while one model is coming down, and shows it arriving', () => {
    download = { id: 'qwen3.5-4b', received: 1e9, total: 2.7e9 };
    const host = show(<ModelCard />);
    expect(host.textContent).toContain('Getting Qwen3.5 4B, 1.0 GB of 2.7 GB. Keep Ghost.md open.');
    expect(button('Get', row(host, 'Qwen3.5 9B')).disabled).toBe(true);
    expect(row(host, 'Qwen3.5 4B').querySelector('.setk-row__value')?.textContent).toBe('Downloading');
  });

  it('has no Remove on the model in use, and removes another that is here without changing the choice', async () => {
    present = ['qwen3.5-2b', 'qwen3.5-9b'];
    setPreferences({ formatModel: 'qwen3.5-9b' });
    const host = show(<ModelCard />);
    expect(row(host, 'Qwen3.5 9B').querySelector('.setk-row__value')?.textContent).toBe('In use');
    expect(buttonSaying(row(host, 'Qwen3.5 9B'), 'Remove')).toBeUndefined();
    await act(async () => button('Remove', row(host, 'Qwen3.5 2B')).click());
    expect(removeModel).toHaveBeenCalledWith('qwen3.5-2b');
    expect(preferences().formatModel).toBe('qwen3.5-9b');
  });

  it('says there is nothing here yet, and says the Mac where it runs on the Mac', () => {
    android = false;
    const host = show(<ModelCard />);
    expect(host.querySelector('.setk__footer')?.textContent).toBe('Nothing downloaded yet. Get one above, or tap the robot on a note and it will offer to.');
    expect(host.textContent).toContain('It runs on this Mac. Nothing is sent anywhere.');
  });
});
