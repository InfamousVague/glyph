import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { PluginManifest } from './types.ts';

/**
 * The parts of a plugin's host that depend on where the page runs: opening an address (the phone's browser in the
 * app, a new tab in a browser) and asking whether the binary has what the plugin needs. The rest of the host - its
 * commands, its storage, its permissions - is registry.test.ts.
 */

let native = true;
let generation = 12;
vi.mock('../core/tauri.ts', () => ({
  isTauri: () => native,
  invoke: async (command: string) => (command === 'ota_status' ? { nativeGeneration: generation } : null),
}));
const openUrl = vi.fn(async (_url: string) => undefined);
vi.mock('@tauri-apps/plugin-opener', () => ({ openUrl: (url: string) => openUrl(url) }));

const manifest = (extra: Partial<PluginManifest> = {}): PluginManifest => ({
  id: 'p',
  name: 'P',
  description: '',
  version: '1.0.0',
  author: 'test',
  standard: true,
  permissions: [{ kind: 'network', why: '' }],
  storage: [],
  ...extra,
});

/** The host module afresh, since the binary's generation is asked once per page. */
async function hostFor(extra: Partial<PluginManifest> = {}) {
  vi.resetModules();
  const { createHost } = await import('./host.ts');
  return createHost(manifest(extra));
}

beforeEach(() => {
  native = true;
  generation = 12;
  openUrl.mockClear();
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('a plugin’s host, on the phone and in a browser', () => {
  it('opens an address in the phone’s browser in the app, and in a new tab in a browser', async () => {
    await (await hostFor()).openUrl('https://www.notion.so/');
    expect(openUrl).toHaveBeenCalledExactlyOnceWith('https://www.notion.so/');
    native = false;
    const open = vi.spyOn(window, 'open').mockImplementation(() => null);
    await (await hostFor()).openUrl('https://github.com/');
    expect(open).toHaveBeenCalledExactlyOnceWith('https://github.com/', '_blank', 'noopener');
    expect(openUrl).toHaveBeenCalledOnce();
  });

  it('opens nothing for a plugin that did not ask for the network', async () => {
    const host = await hostFor({ permissions: [] });
    await expect(host.openUrl('https://example.com/')).rejects.toThrow(/didn't declare the “network” permission/);
    expect(openUrl).not.toHaveBeenCalled();
  });

  it('says the binary is ready only when it is the generation the manifest asks for, or newer', async () => {
    const needs = { permissions: [{ kind: 'native' as const, why: '' }], native: { generation: 12, commands: [] } };
    expect(await (await hostFor(needs)).nativeReady()).toBe(true);
    generation = 11;
    expect(await (await hostFor(needs)).nativeReady()).toBe(false);
    // A browser has no binary at all.
    native = false;
    generation = 99;
    expect(await (await hostFor(needs)).nativeReady()).toBe(false);
  });

  it('is never ready for a plugin that names no binary, which is "nothing asked for", not "nothing needed"', async () => {
    expect(await (await hostFor()).nativeReady()).toBe(false);
  });
});
