import { beforeEach, describe, expect, it, vi } from 'vitest';

let native = true;
const invoke = vi.fn<(command: string) => Promise<unknown>>();

vi.mock('./tauri.ts', () => ({ isTauri: () => native, invoke }));

/** A fresh copy of the module, so each case starts before the one question has been asked. */
async function fresh() {
  vi.resetModules();
  return import('./nativeGeneration.ts');
}

describe('the native generation', () => {
  beforeEach(() => {
    native = true;
    invoke.mockReset();
  });

  it('asks Rust once per page load, however many features want to know', async () => {
    invoke.mockResolvedValue({ nativeGeneration: 18, nativeVersion: '1.7.0' });
    const { hasNativeGeneration, nativeGeneration } = await fresh();
    const answers = await Promise.all([nativeGeneration(), nativeGeneration(), hasNativeGeneration(16), hasNativeGeneration(19)]);
    expect(answers).toEqual([18, 18, true, false]);
    expect(await nativeGeneration()).toBe(18);
    expect(invoke).toHaveBeenCalledTimes(1);
    expect(invoke).toHaveBeenCalledWith('ota_status');
  });

  it('answers 0 in a browser without asking anything', async () => {
    native = false;
    const { hasNativeGeneration, nativeGeneration } = await fresh();
    expect(await nativeGeneration()).toBe(0);
    expect(await hasNativeGeneration(1)).toBe(false);
    expect(invoke).not.toHaveBeenCalled();
  });

  it('answers 0 when the binary will not say, and does not ask again', async () => {
    invoke.mockRejectedValue(new Error('no such command'));
    const { hasNativeGeneration, nativeGeneration } = await fresh();
    expect(await nativeGeneration()).toBe(0);
    expect(await hasNativeGeneration(6)).toBe(false);
    expect(invoke).toHaveBeenCalledTimes(1);
  });

  it('reads a status from before the field existed as generation 0', async () => {
    invoke.mockResolvedValue({ nativeVersion: '0.2.0' });
    const { nativeGeneration } = await fresh();
    expect(await nativeGeneration()).toBe(0);
  });

  it('holds the answer for the whole page, as the binary cannot change under it', async () => {
    invoke.mockResolvedValueOnce({ nativeGeneration: 9 }).mockResolvedValueOnce({ nativeGeneration: 18 });
    const { nativeGeneration } = await fresh();
    expect(await nativeGeneration()).toBe(9);
    expect(await nativeGeneration()).toBe(9);
  });
});
