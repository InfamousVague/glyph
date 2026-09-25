import { act } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { show, unmount } from '../../test/render.tsx';
import type { OtaStatus, Updates } from './ota.ts';

/*
 * Over-the-air updates from the page's side (ota.ts): when the page looks, what it makes of the answer, and the APK
 * handed to Android's installer. A phone is core/tauri.ts mocked, answering `ota_check` and `ota_status` with what
 * each test lines up; the download's progress arrives through core/events.ts, also mocked. Under Vitest
 * `import.meta.env.DEV` is true, which is `tauri dev` to the page and so no checks at all: every test that wants a
 * check says it is a release build first.
 */

let native = true;
const invoked: string[] = [];
let check: Record<string, unknown> = {};
let status: OtaStatus;
/** What `ota_fetch_apk` does: answers the file's path, or fails. */
let fetchApk: () => Promise<string> = async () => '/cache/glyph.apk';

vi.mock('./tauri.ts', () => ({
  isTauri: () => native,
  invoke: async (command: string) => {
    invoked.push(command);
    if (command === 'ota_check') return { web: 'current', webBuild: null, webVersion: null, apk: null, error: null, ...check };
    if (command === 'ota_status') return status;
    if (command === 'ota_fetch_apk') return fetchApk();
    return undefined;
  },
}));

/** The APK download's progress handler, while one is listening. */
let progress: ((payload: { received: number; total: number }) => void) | null = null;
const unlisten = vi.fn();
vi.mock('./events.ts', () => ({
  listenTo: async (_event: string, handler: (payload: { received: number; total: number }) => void) => {
    progress = handler;
    return () => {
      progress = null;
      unlisten();
    };
  },
}));

const { settleBoot, storeOf, useUpdates } = await import('./ota.ts');
const { setPreferences } = await import('./preferences.ts');

const APK = { version: '9.0.0', versionCode: 900, native: 30, sha256: 'ab', bytes: 1_000, url: 'https://x/glyph.apk' };

/** The hook's latest answer, as Settings has it. */
let updates: Updates | null = null;
function Updates() {
  updates = useUpdates();
  return null;
}

async function wait(ms: number): Promise<void> {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(ms);
  });
}

/** How many times the page has asked for an update so far. */
const checks = () => invoked.filter((command) => command === 'ota_check').length;

function hidden(on: boolean): void {
  Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => (on ? 'hidden' : 'visible') });
  document.dispatchEvent(new Event('visibilitychange'));
}

beforeEach(() => {
  native = true;
  invoked.length = 0;
  check = {};
  status = {
    nativeVersion: '1.0.0',
    nativeGeneration: 20,
    embeddedBuild: null,
    embeddedVersion: null,
    activeBuild: null,
    activeVersion: null,
    runningBuild: null,
    quarantined: [],
  };
  fetchApk = async () => '/cache/glyph.apk';
  progress = null;
  unlisten.mockClear();
  updates = null;
  localStorage.clear();
  setPreferences({ localOnly: false });
  vi.stubEnv('DEV', false);
  vi.useFakeTimers();
});

afterEach(() => {
  unmount();
  hidden(false);
  delete window.GlyphHost;
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

describe('when the page looks for an update', () => {
  it('looks four seconds after launch, and not before', async () => {
    show(<Updates />);
    await wait(3_999);
    expect(checks()).toBe(0);
    // The status is read at once, for Settings, before any check.
    expect(invoked).toEqual(['ota_status']);
    await wait(1);
    expect(checks()).toBe(1);
    expect(updates?.lastChecked).not.toBeNull();
  });

  it('looks again on a two-minute beat while in front, and not while hidden', async () => {
    show(<Updates />);
    await wait(4_000);
    await wait(2 * 60_000);
    expect(checks()).toBe(2);
    hidden(true);
    await wait(4 * 60_000);
    expect(checks()).toBe(2);
  });

  it('looks when the app comes back, if it has not looked for a minute', async () => {
    show(<Updates />);
    await wait(4_000);
    // Back 59 s after the last look: too soon.
    hidden(true);
    await wait(59_000);
    hidden(false);
    await wait(0);
    expect(checks()).toBe(1);
    // Back again once the minute has passed, still short of the two-minute beat.
    hidden(true);
    await wait(1_001);
    hidden(false);
    await wait(0);
    expect(checks()).toBe(2);
  });

  it('never looks in a browser, with Nothing leaves the phone on, or under tauri dev', async () => {
    native = false;
    show(<Updates />);
    await wait(10 * 60_000);
    expect(invoked).toEqual([]);
    unmount();

    native = true;
    setPreferences({ localOnly: true });
    show(<Updates />);
    await wait(10 * 60_000);
    expect(checks()).toBe(0);
    unmount();

    setPreferences({ localOnly: false });
    vi.stubEnv('DEV', true);
    show(<Updates />);
    await wait(10 * 60_000);
    expect(checks()).toBe(0);
  });
});

describe('what the page makes of the answer', () => {
  it('offers a reload for a build installed by this check, or by one before it this run', async () => {
    check = { web: 'installed', webBuild: '20260925120000', webVersion: '1.9.0' };
    show(<Updates />);
    await wait(4_000);
    expect(updates?.ready).toEqual({ build: '20260925120000', version: '1.9.0' });
    unmount();

    check = {};
    status = { ...status, activeBuild: '20260925130000', activeVersion: '1.9.1', runningBuild: '20260925120000' };
    show(<Updates />);
    await wait(4_000);
    expect(updates?.ready).toEqual({ build: '20260925130000', version: '1.9.1' });
  });

  it('offers nothing for the build that is already running', async () => {
    status = { ...status, activeBuild: '20260925120000', activeVersion: '1.9.0', runningBuild: '20260925120000' };
    show(<Updates />);
    await wait(4_000);
    expect(updates?.ready).toBeNull();
  });

  it('says it is offline until a check gets through', async () => {
    check = { web: 'offline', error: 'The update source could not be reached.' };
    show(<Updates />);
    await wait(4_000);
    expect(updates?.lastError).toBe('The update source could not be reached.');
    check = {};
    await wait(2 * 60_000);
    expect(updates?.lastError).toBeNull();
  });

  it('offers an APK newer than this binary by its version or its native generation, and no other', async () => {
    check = { apk: APK };
    show(<Updates />);
    await wait(4_000);
    expect(updates?.apk).toEqual({ kind: 'available', info: APK });
    check = { apk: { ...APK, version: '1.0.0', native: 21 } };
    await wait(2 * 60_000);
    expect(updates?.apk.kind).toBe('available');
    check = { apk: { ...APK, version: '1.0.0', native: 20 } };
    await wait(2 * 60_000);
    expect(updates?.apk).toEqual({ kind: 'none' });
  });
});

describe('the APK', () => {
  async function offered(): Promise<void> {
    check = { apk: APK };
    show(<Updates />);
    await wait(4_000);
  }

  it('is downloaded with its progress shown and handed to the installer, and a check does not interrupt it', async () => {
    let path = '';
    window.GlyphHost = {
      installApk: (at: string) => {
        path = at;
        return 'started';
      },
    } as unknown as Window['GlyphHost'];
    let finish: (path: string) => void = () => undefined;
    fetchApk = () => new Promise((resolve) => (finish = resolve));
    await offered();
    act(() => updates?.installApk());
    await wait(0);
    act(() => progress?.({ received: 400, total: 1_000 }));
    expect(updates?.apk).toEqual({ kind: 'downloading', info: APK, received: 400, total: 1_000 });
    await wait(2 * 60_000);
    expect(updates?.apk.kind).toBe('downloading');
    await act(async () => finish('/cache/glyph.apk'));
    await wait(0);
    expect(path).toBe('/cache/glyph.apk');
    expect(updates?.apk).toEqual({ kind: 'installing', info: APK });
    expect(unlisten).toHaveBeenCalledTimes(1);
  });

  it('says when Android first has to be allowed to install, and when the installer did not start', async () => {
    let answer = 'permission';
    window.GlyphHost = { installApk: () => answer } as unknown as Window['GlyphHost'];
    await offered();
    act(() => updates?.installApk());
    await wait(0);
    expect(updates?.apk).toEqual({ kind: 'needs-permission', info: APK });
    answer = 'no-activity';
    act(() => updates?.installApk());
    await wait(0);
    expect(updates?.apk).toEqual({ kind: 'failed', info: APK, message: 'The installer did not start (no-activity).' });
  });

  it('says so on a build that cannot install, and when the download fails', async () => {
    window.GlyphHost = {} as unknown as Window['GlyphHost'];
    await offered();
    act(() => updates?.installApk());
    await wait(0);
    expect(updates?.apk).toEqual({ kind: 'failed', info: APK, message: 'This build can’t install updates itself. Download it from attack.fm/glyph.' });

    window.GlyphHost = { installApk: () => 'started' } as unknown as Window['GlyphHost'];
    fetchApk = async () => {
      throw new Error('The APK did not match its signature.');
    };
    act(() => updates?.installApk());
    await wait(0);
    expect(updates?.apk).toEqual({ kind: 'failed', info: APK, message: 'The APK did not match its signature.' });
    expect(unlisten).toHaveBeenCalledTimes(1);
  });
});

describe('the boot and the store', () => {
  it('reports a real mount once, with the build the loader staked', async () => {
    window.__glyphBoot = { build: '20260925120000' } as unknown as Window['__glyphBoot'];
    settleBoot();
    settleBoot();
    expect(window.__glyphBoot?.mounted).toBe(true);
    expect(invoked.filter((command) => command === 'ota_boot_ok')).toHaveLength(1);
    delete window.__glyphBoot;
  });

  it('names the store a build came from, and none for one that updates itself', () => {
    expect(storeOf(null)).toBeNull();
    expect(storeOf({ ...status, store: 'play' })).toBe('play');
    expect(storeOf({ ...status, store: null })).toBeNull();
  });
});
