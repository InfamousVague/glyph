import { act } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi, type MockInstance } from 'vitest';
import { show, waitUntil } from '../../test/render.tsx';

/**
 * The voice model's fetch as the app opens (capture/useVoiceModel.ts): shown while it runs, said when it fails, and
 * tried again each time the app comes back to the screen until it is there - the freeze on the Fold that left an
 * empty models/ folder and nothing on screen is what the retry is for.
 */

let native = true;
const ensureModel = vi.fn<(onProgress?: (received: number, total: number) => void) => Promise<unknown>>();

vi.mock('../core/tauri.ts', () => ({ isTauri: () => native, invoke: vi.fn() }));
vi.mock('./engine.ts', () => ({ ensureModel }));

const { useVoiceModel } = await import('./useVoiceModel.ts');

let latest: ReturnType<typeof useVoiceModel> | null = null;
function Probe() {
  latest = useVoiceModel();
  return <p>{latest.state.kind}</p>;
}

const comeBack = () =>
  act(() => {
    Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' });
    document.dispatchEvent(new Event('visibilitychange'));
  });

let warn: MockInstance<typeof console.warn>;
beforeEach(() => {
  native = true;
  latest = null;
  ensureModel.mockReset();
  // A failed fetch is logged for logcat; the tests that fail one say so on screen instead.
  warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
});
afterEach(() => warn.mockRestore());

describe('the voice model', () => {
  it('is not asked about in a browser', () => {
    native = false;
    const host = show(<Probe />);
    expect(host.textContent).toBe('unsupported');
    expect(ensureModel).not.toHaveBeenCalled();
  });

  it('shows its download as it comes, and then that it is ready', async () => {
    let finish: () => void = () => undefined;
    ensureModel.mockImplementation((onProgress) => {
      onProgress?.(30, 60);
      return new Promise((resolve) => (finish = () => resolve({ present: true })));
    });
    const host = show(<Probe />);
    await waitUntil(() => expect(latest?.state).toEqual({ kind: 'downloading', received: 30, total: 60 }));
    await act(async () => finish());
    expect(host.textContent).toBe('ready');
  });

  it('says why it failed, and tries again when the app comes back to the screen', async () => {
    ensureModel.mockRejectedValueOnce(new Error('the download stopped')).mockResolvedValueOnce({ present: true });
    show(<Probe />);
    await waitUntil(() => expect(latest?.state).toEqual({ kind: 'failed', message: 'the download stopped' }));
    comeBack();
    await waitUntil(() => expect(latest?.state).toEqual({ kind: 'ready' }));
    expect(ensureModel).toHaveBeenCalledTimes(2);
    // There: coming back again asks nothing.
    comeBack();
    await act(async () => undefined);
    expect(ensureModel).toHaveBeenCalledTimes(2);
  });

  it('asks once while a fetch is still running, however often the app comes back', async () => {
    ensureModel.mockImplementation(() => new Promise(() => undefined));
    show(<Probe />);
    comeBack();
    comeBack();
    await act(async () => undefined);
    expect(ensureModel).toHaveBeenCalledOnce();
  });

  it('tries again on the retry it offers', async () => {
    ensureModel.mockRejectedValueOnce('offline').mockResolvedValueOnce({ present: true });
    show(<Probe />);
    await waitUntil(() => expect(latest?.state.kind).toBe('failed'));
    act(() => latest!.retry());
    await waitUntil(() => expect(latest?.state.kind).toBe('ready'));
  });
});
