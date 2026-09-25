import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Download, ModelInfo } from '../../core/ai.ts';

/** The phone, as the page reads it: whether this is the app, and what the catalogue says is here or coming. */
const phone = vi.hoisted(() => ({
  app: false,
  models: [] as ModelInfo[],
  download: null as Download | null,
  problem: null as string | null,
  fetch: vi.fn(async (_id: string) => undefined),
}));
vi.mock('../../core/tauri.ts', async (importOriginal) => ({ ...(await importOriginal<typeof import('../../core/tauri.ts')>()), isTauri: () => phone.app }));
vi.mock('../../core/ai.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../core/ai.ts')>()),
  useModels: () => ({ models: phone.models, download: phone.download, problem: phone.problem, fetch: phone.fetch, remove: async () => undefined, refresh: async () => undefined }),
}));

import { buttonSaying, press, show, unmount } from '../../../test/render.tsx';
import { MODELS } from '../../core/ai.ts';
import { preferences, reloadPreferences, setPreferences } from '../../core/preferences.ts';
import { Model } from './Model.tsx';

const rows = (el: HTMLElement) => [...el.querySelectorAll<HTMLButtonElement>('[role="radiogroup"] [role="radio"]')];
const row = (el: HTMLElement, name: string) => rows(el).find((b) => b.textContent?.includes(name));
const checked = (el: HTMLElement) => rows(el).filter((b) => b.getAttribute('aria-checked') === 'true').map((b) => b.textContent);
/** The line under the rows, about the chosen model's download. */
const fine = (el: HTMLElement) => el.querySelector('[role="radiogroup"] + p')?.textContent ?? null;

beforeEach(() => {
  phone.app = true;
  phone.models = [];
  phone.download = null;
  phone.problem = null;
  phone.fetch.mockClear();
  setPreferences({ formatModel: 'qwen3.5-4b' });
});
afterEach(() => {
  localStorage.clear();
  reloadPreferences();
});

describe('the guide’s model page', () => {
  it('has a row per model with its size, and sets the preference the moment one is tapped', () => {
    const el = show(<Model />);
    expect(rows(el)).toHaveLength(MODELS.length);
    expect(row(el, 'Qwen3.5 9B')?.textContent).toBe('5.7 GBQwen3.5 9BThe most careful, and the slowest. Wants 12 GB of memory.');
    expect(checked(el)).toEqual([row(el, 'Qwen3.5 4B')!.textContent]);
    press(row(el, 'Qwen3.5 9B'));
    expect(preferences().formatModel).toBe('qwen3.5-9b');
    expect(checked(el)).toEqual([row(el, 'Qwen3.5 9B')!.textContent]);
    expect(row(el, 'Qwen3.5 9B')!.className).toContain('app-inverse');
    expect(row(el, 'Qwen3.5 4B')!.className).not.toContain('app-inverse');
    // Nothing is fetched for a tap: the bytes wait to be asked for.
    expect(phone.fetch).not.toHaveBeenCalled();
  });

  it('offers to get the chosen model now when it is not on the phone', () => {
    const el = show(<Model />);
    expect(fine(el)).toBe('Qwen3.5 4B downloads the first time you ask the robot on a note, or get it now');
    press(buttonSaying(el, 'get it now'));
    expect(phone.fetch).toHaveBeenCalledWith('qwen3.5-4b');
  });

  it('says how far a download has got, and that the model is here once it is', () => {
    phone.download = { id: 'qwen3.5-4b', received: 1_000_000_000, total: 2_740_937_888 };
    const getting = show(<Model />);
    expect(fine(getting)).toBe('Getting Qwen3.5 4B, 1.0 GB of 2.7 GB. Keep Ghost.md open.');
    expect(buttonSaying(getting, 'get it now')).toBeUndefined();
    unmount();
    phone.download = null;
    phone.models = [{ id: 'qwen3.5-4b', file: 'qwen3.5-4b.gguf', bytes: 2_740_937_888, present: true, path: '/models/qwen3.5-4b.gguf' }];
    const here = show(<Model />);
    expect(fine(here)).toBe('Qwen3.5 4B is on the phone.');
    expect(buttonSaying(here, 'get it now')).toBeUndefined();
  });

  it('says what went wrong with a download, and still offers to try again', () => {
    phone.problem = 'Not enough space on the phone.';
    const el = show(<Model />);
    expect(fine(el)).toBe('Not enough space on the phone.get it now');
    expect(buttonSaying(el, 'get it now')).toBeDefined();
  });

  it('says nothing of downloads in a browser, where a row still sets the preference', () => {
    phone.app = false;
    const el = show(<Model />);
    expect(fine(el)).toBeNull();
    press(row(el, 'Gemma 4 E4B'));
    expect(preferences().formatModel).toBe('gemma-4-e4b');
  });
});
