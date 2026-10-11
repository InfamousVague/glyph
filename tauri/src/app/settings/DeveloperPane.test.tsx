import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { button, buttonSaying, press, show, unmount } from '../../test/render.tsx';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

// A reset that would wipe this document's storage and reload it: stood in for, answering as each test says.
const resetLocalData = vi.fn((_options: { models: boolean }) => Promise.resolve());
vi.mock('../core/reset.ts', () => ({ resetLocalData: (options: { models: boolean }) => resetLocalData(options) }));

/** Whether the model is on a note, as the page hears it (ai/runs.ts `useAnyRunning`). */
const engine = vi.hoisted(() => ({ busy: false }));
vi.mock('../ai/runs.ts', async (importOriginal) => ({ ...(await importOriginal<typeof import('../ai/runs.ts')>()), useAnyRunning: () => engine.busy }));

const { DeveloperPane } = await import('./DeveloperPane.tsx');
const { setDeveloperMode } = await import('./developerMode.ts');

/**
 * The developer page: the resets that take two taps, and the switch that hides the page again. What the window facts
 * read is diag/windowFacts.test.ts, and the smoke bench is diag/WispBench.test.tsx.
 */

/** The reset row that says `label`, and the word on its button. */
function resetRow(host: HTMLElement, label: string) {
  const row = [...host.querySelectorAll<HTMLElement>('.setk-row')].find((r) => r.querySelector('.setk-row__label')?.textContent === label);
  if (!row) throw new Error(`no row ${label}`);
  const action = row.querySelector<HTMLButtonElement>('.setk-action')!;
  return { row, action, hint: () => row.querySelector('.setk-row__hint')?.textContent };
}

beforeEach(() => {
  resetLocalData.mockClear();
  setDeveloperMode(true);
});

afterEach(() => {
  // Unmounted before the real clock is back, so the armed row's timer is cleared on the clock that set it.
  unmount();
  vi.useRealTimers();
  localStorage.clear();
});

describe('a reset', () => {
  it('arms on the first tap and does nothing until the second', async () => {
    const host = show(<DeveloperPane />);
    const reset = resetRow(host, 'Reset local data');
    expect(reset.action.textContent).toBe('Reset');
    press(reset.action);
    expect(reset.action.textContent).toBe('Tap again');
    expect(resetLocalData).not.toHaveBeenCalled();
    await act(async () => reset.action.click());
    expect(resetLocalData).toHaveBeenCalledWith({ models: false });
    expect(reset.action.textContent).toBe('Resetting');
    expect(reset.action.disabled).toBe(true);
  });

  it('takes the models too only on the row that says so', async () => {
    const host = show(<DeveloperPane />);
    const everything = resetRow(host, 'Reset everything');
    press(everything.action);
    await act(async () => everything.action.click());
    expect(resetLocalData).toHaveBeenCalledWith({ models: true });
  });

  it('disarms itself five seconds after the first tap', () => {
    vi.useFakeTimers();
    const host = show(<DeveloperPane />);
    const reset = resetRow(host, 'Reset local data');
    press(reset.action);
    act(() => vi.advanceTimersByTime(4900));
    expect(reset.action.textContent).toBe('Tap again');
    act(() => vi.advanceTimersByTime(200));
    expect(reset.action.textContent).toBe('Reset');
    // The next tap arms it again rather than resetting.
    press(reset.action);
    expect(resetLocalData).not.toHaveBeenCalled();
  });

  it('says why in its hint when the reset fails, and can be tried again', async () => {
    resetLocalData.mockRejectedValueOnce(new Error('The model folder is in use.'));
    const host = show(<DeveloperPane />);
    const reset = resetRow(host, 'Reset local data');
    press(reset.action);
    await act(async () => reset.action.click());
    expect(reset.hint()).toBe('The model folder is in use.');
    expect(reset.action.textContent).toBe('Reset');
    expect(reset.action.disabled).toBe(false);
  });
});

describe('the developer page', () => {
  // Changed on purpose (docs/DESIGN.md §138): the Set-up card's two rows were About's walkthrough and Recording's model.
  it('has no Set-up card: the walkthrough is About’s, the model Recording’s', () => {
    const host = show(<DeveloperPane />);
    expect([...host.querySelectorAll('.setk__title')].map((t) => t.textContent)).toEqual(['Window', 'Smoke', 'The phone at work', 'Developer mode', 'Reset']);
    expect(buttonSaying(host, 'Welcome guide')).toBeUndefined();
    expect(buttonSaying(host, 'Choose your model')).toBeUndefined();
  });

  it('turns developer mode off from its own switch', () => {
    const host = show(<DeveloperPane />);
    const toggle = host.querySelector<HTMLElement>('[aria-label="Developer settings"]')!;
    press(toggle);
    expect(localStorage.getItem('glyph-developer')).toBeNull();
  });
});

describe('the phone at work', () => {
  const dialog = () => document.querySelector<HTMLElement>('[role="dialog"][aria-label="The phone at work"]');
  const row = (host: HTMLElement) => [...host.querySelectorAll<HTMLButtonElement>('.setk-row--press')].find((r) => r.querySelector('.setk-row__label')?.textContent === 'Play the scene')!;

  it('plays the scene from its row, under the bench’s bar', () => {
    vi.useFakeTimers();
    engine.busy = false;
    const host = show(<DeveloperPane />);
    expect(row(host).disabled).toBe(false);
    expect(dialog()).toBeNull();
    press(row(host));
    expect(dialog()).not.toBeNull();
    expect(dialog()?.querySelector('[aria-label="The models at work on this note"]')).not.toBeNull();
    press(button('Close'));
    expect(dialog()).toBeNull();
  });

  it('plays the readings chosen, one row and a choice where there were three rows', () => {
    vi.useFakeTimers();
    engine.busy = false;
    const host = show(<DeveloperPane />);
    expect([...host.querySelectorAll<HTMLButtonElement>('.setk-row--press')].filter((r) => r.querySelector('.setk-row__label')?.textContent?.startsWith('Play'))).toHaveLength(1);
    act(() => host.querySelector<HTMLInputElement>('input[type="radio"][value="none"]')!.click());
    press(row(host));
    expect(dialog()).not.toBeNull();
    press(button('Close'));
  });

  it('refuses to play while the model is on a note, and says why', () => {
    engine.busy = true;
    const host = show(<DeveloperPane />);
    expect(row(host).disabled).toBe(true);
    expect(row(host).textContent).toContain('The model is on a note. Try again when it is done.');
    engine.busy = false;
  });
});
