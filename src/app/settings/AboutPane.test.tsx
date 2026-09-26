import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Release } from '../core/changelog.ts';
import type { Updates } from '../core/ota.ts';
import { button, press, show, waitUntil } from '../../test/render.tsx';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

// The page is in the app or in a browser as each test says.
let native = false;
vi.mock('../core/tauri.ts', () => ({ isTauri: () => native, invoke: () => Promise.reject(new Error('no binary in a test')) }));

// What was kept from the last reading of the releases, and what the site answers this time.
let kept: Release[] = [];
let fetched: Release[] = [];
vi.mock('../core/changelog.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/changelog.ts')>()),
  keptReleases: () => kept,
  fetchReleases: () => Promise.resolve(fetched),
}));

const { ToastProvider } = await import('@glacier/react');
const { AboutPane } = await import('./AboutPane.tsx');

/**
 * About: the version that is also the door to the developer tools, the Updates card on each kind of build, and the
 * releases read from what was kept and then from the site. The page's sentences about where a build stands are
 * updateLines.test.ts; this is the page doing what they say.
 */

function updates(over: Partial<Updates> = {}): Updates {
  return {
    ready: null,
    apk: { kind: 'none' },
    checking: false,
    lastError: null,
    lastChecked: null,
    status: null,
    build: '20260924221500',
    version: '1.8.0',
    check: vi.fn(),
    reload: vi.fn(),
    installApk: vi.fn(),
    ...over,
  };
}

function about(given: Updates = updates(), onDeveloper = vi.fn()) {
  const noop = () => undefined;
  const host = show(
    <ToastProvider>
      <AboutPane updates={given} onGuide={noop} onSample={noop} onGuideBook={noop} onBoard={noop} onCanvas={noop} onHowCanvas={noop} onAcademy={noop} onCheatSheet={noop} onDeveloper={onDeveloper} />
    </ToastProvider>,
  );
  return { host, onDeveloper };
}

beforeEach(() => {
  native = false;
  kept = [];
  fetched = [];
  localStorage.clear();
});

afterEach(() => {
  vi.useRealTimers();
});

describe('the version on About', () => {
  it('counts down from the third press and turns developer mode on at the seventh', () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    // Far from any press an earlier test made, so this run starts at one.
    vi.setSystemTime(new Date('2026-09-25T12:00:00Z'));
    const { host, onDeveloper } = about();
    const version = host.querySelector<HTMLButtonElement>('.setk-hero--press')!;
    expect(version.textContent).toContain('1.8.0');
    const presses = (n: number) => {
      for (let i = 0; i < n; i += 1) {
        vi.setSystemTime(Date.now() + 200);
        press(version);
      }
    };
    presses(2);
    expect(document.body.textContent).not.toContain('for developer settings');
    presses(1);
    expect(document.body.textContent).toContain('4 more taps for developer settings.');
    presses(3);
    expect(document.body.textContent).toContain('1 more tap for developer settings.');
    expect(onDeveloper).not.toHaveBeenCalled();
    presses(1);
    expect(onDeveloper).toHaveBeenCalledOnce();
    expect(localStorage.getItem('glyph-developer')).toBe('on');
    expect(document.body.textContent).toContain('Developer settings are on.');
  });

  it('starts the count again after a pause between presses', () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-09-25T13:00:00Z'));
    const { host, onDeveloper } = about();
    const version = host.querySelector<HTMLButtonElement>('.setk-hero--press')!;
    for (let i = 0; i < 6; i += 1) {
      vi.setSystemTime(Date.now() + 200);
      press(version);
    }
    // A second's rest: the seventh press is the first of a new run.
    vi.setSystemTime(Date.now() + 1000);
    press(version);
    expect(onDeveloper).not.toHaveBeenCalled();
    expect(localStorage.getItem('glyph-developer')).toBeNull();
  });
});

describe('the Updates card', () => {
  it('in a browser, says to reload and offers nothing to press', () => {
    const { host } = about();
    expect(host.textContent).toContain("You're on the web version");
    expect(host.textContent).not.toContain('Check for updates');
  });

  it('in the app, says where the build stands and offers what moves it on', () => {
    native = true;
    const given = updates({ ready: { build: '20260925000000', version: '1.8.1' }, apk: { kind: 'failed', info: { version: '1.9.0', versionCode: 1, native: 1, sha256: '', bytes: 1, url: '' }, message: 'no' } });
    const { host } = about(given);
    expect(host.textContent).toContain('A new version is downloaded.');
    press(button('Reload', host));
    expect(given.reload).toHaveBeenCalledOnce();
    press(button('Install 1.9.0', host));
    expect(given.installApk).toHaveBeenCalledOnce();
    press(button('Check for updates', host));
    expect(given.check).toHaveBeenCalledOnce();
  });

  it('holds the check while one is running, and sends a Play build to the store for the app itself', () => {
    native = true;
    const { host } = about(updates({ checking: true, status: { nativeVersion: '1.8.0', nativeGeneration: 20, embeddedBuild: null, embeddedVersion: null, activeBuild: null, activeVersion: null, runningBuild: null, quarantined: [], store: 'play' } }));
    expect(button('Check for updates', host).disabled).toBe(true);
    expect(host.textContent).toContain('New versions of the app itself come through the Play Store.');
  });

  it('on an App Store build, says the store updates it and lists no releases', () => {
    native = true;
    kept = [{ version: '1.8.0-1', build: '20260924221500', at: '2026-09-24T22:15:00Z' }];
    const { host } = about(updates({ status: { nativeVersion: '1.8.0', nativeGeneration: 20, embeddedBuild: null, embeddedVersion: null, activeBuild: null, activeVersion: null, runningBuild: null, quarantined: [], store: 'appstore' } }));
    expect(host.textContent).toContain('Ghost.md updates through the App Store.');
    expect(host.textContent).not.toContain("What's new");
  });
});

describe("What's new", () => {
  it('shows what was kept at once, then what the site says, marking the build that is running', async () => {
    kept = [{ version: '1.7.9-2', build: '20260920000000', at: '2026-09-20T00:00:00Z' }];
    fetched = [
      { version: '1.8.0-1', build: '20260924221500', at: '2026-09-24T22:15:00Z', notes: 'Smoke at the edges.', apk: '1.8.0' },
      { version: '1.7.9-2', build: '20260920000000', at: '2026-09-20T00:00:00Z' },
    ];
    const { host } = about();
    expect(host.textContent).toContain('1.7.9-2');
    await waitUntil(() => expect(host.textContent).toContain("1.8.0-1 · you're on this one"));
    // An app number is said on a build that installs its own apps.
    expect(host.textContent).toContain('Smoke at the edges. Installed as Ghost.md 1.8.0.');
  });

  it('says it is reading, and then that there is nothing yet, when neither has a release', async () => {
    const { host } = about();
    expect(host.textContent).toContain('Reading the updates…');
    await waitUntil(() => expect(host.textContent).toContain('No updates to show yet.'));
  });
});
