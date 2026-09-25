import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { buttonSaying, press, show, unmount } from '../../test/render.tsx';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

// A reset that would wipe this document's storage and reload it: stood in for, answering as each test says.
const resetLocalData = vi.fn((_options: { models: boolean }) => Promise.resolve());
vi.mock('../core/reset.ts', () => ({ resetLocalData: (options: { models: boolean }) => resetLocalData(options) }));

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
    const host = show(<DeveloperPane onGuide={() => undefined} />);
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
    const host = show(<DeveloperPane onGuide={() => undefined} />);
    const everything = resetRow(host, 'Reset everything');
    press(everything.action);
    await act(async () => everything.action.click());
    expect(resetLocalData).toHaveBeenCalledWith({ models: true });
  });

  it('disarms itself five seconds after the first tap', () => {
    vi.useFakeTimers();
    const host = show(<DeveloperPane onGuide={() => undefined} />);
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
    const host = show(<DeveloperPane onGuide={() => undefined} />);
    const reset = resetRow(host, 'Reset local data');
    press(reset.action);
    await act(async () => reset.action.click());
    expect(reset.hint()).toBe('The model folder is in use.');
    expect(reset.action.textContent).toBe('Reset');
    expect(reset.action.disabled).toBe(false);
  });
});

describe('the developer page', () => {
  it('opens the welcome guide on its first page, or on the model page', () => {
    const onGuide = vi.fn();
    const host = show(<DeveloperPane onGuide={onGuide} />);
    press(buttonSaying(host, 'Welcome guide'));
    expect(onGuide).toHaveBeenLastCalledWith(0);
    press(buttonSaying(host, 'Choose your model'));
    expect(onGuide).toHaveBeenCalledTimes(2);
    expect(onGuide.mock.lastCall?.[0]).toBeGreaterThan(0);
  });

  it('turns developer mode off from its own switch', () => {
    const host = show(<DeveloperPane onGuide={() => undefined} />);
    const toggle = host.querySelector<HTMLElement>('[aria-label="Developer settings"]')!;
    press(toggle);
    expect(localStorage.getItem('glyph-developer')).toBeNull();
  });
});
