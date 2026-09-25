import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Updates } from '../core/ota.ts';
import type { SettingsSection } from './SettingsScreen.tsx';
import { show, unmount, waitUntil } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
// The side key's rings on Recording watch their box; jsdom has no observer.
stubResizeObserver();

// In the app or in a browser, on Android or not, as each test says. The binary has no models, and answers nothing
// else: every other native read falls back to what a page shows before it has heard.
let native = false;
let android = false;
vi.mock('../core/tauri.ts', () => ({
  isTauri: () => native,
  invoke: (command: string) => (command === 'ai_models' ? Promise.resolve([]) : Promise.reject(new Error('no binary in a test'))),
}));
vi.mock('../core/platform.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../core/platform.ts')>();
  return {
    ...real,
    get isAndroid() {
      return android;
    },
    get isNativeMobile() {
      return android && native;
    },
  };
});
// A phone's width: the list, then a pane. The smoke under the header is its own test's (art/wispEdge.ts).
vi.mock('../core/useWideScreen.ts', () => ({ useSidebar: () => false }));
vi.mock('../art/wispEdge.ts', () => ({ useWispEdge: () => undefined }));
// The sections the sheet hands its screen, kept for the search's contract below; the screen itself is the real one.
let handed: SettingsSection[] = [];
vi.mock('./SettingsScreen.tsx', async (importOriginal) => {
  const real = await importOriginal<typeof import('./SettingsScreen.tsx')>();
  return {
    ...real,
    SettingsScreen: (props: Parameters<typeof real.SettingsScreen>[0]) => {
      handed = props.sections;
      return <real.SettingsScreen {...props} />;
    },
  };
});
// The releases would be read from the site.
vi.mock('../core/changelog.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/changelog.ts')>()),
  keptReleases: () => [],
  fetchReleases: () => Promise.resolve([]),
}));

const { ToastProvider } = await import('@glacier/react');
const { SettingsSheet } = await import('./SettingsSheet.tsx');
const { setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');
const { setDeveloperMode } = await import('./developerMode.ts');
const { findSetting } = await import('./settingsSearch.ts');

/**
 * Settings as the app hands it over: which sections the list has on each kind of device, what their readings say,
 * and the promise its search makes - that a setting it finds is on its page, under the name the search gave it. That
 * last is a contract between two files, the section's `settings` names in SettingsSheet.tsx and the labels the pane
 * draws, and nothing else checks that the two agree: a label renamed in a pane leaves the search opening the page and
 * finding nothing on it.
 */

const updates: Updates = {
  ready: null,
  apk: { kind: 'none' },
  checking: false,
  lastError: null,
  lastChecked: null,
  status: null,
  build: '20260924221500',
  version: '1.8.0',
  check: () => undefined,
  reload: () => undefined,
  installApk: () => undefined,
};

function settings(toCheatSheet = 0): HTMLDivElement {
  const noop = () => undefined;
  return show(
    <ToastProvider>
      <SettingsSheet open onClose={noop} updates={updates} onGuide={noop} onSample={noop} onBoard={noop} onCanvas={noop} onHowCanvas={noop} onAcademy={noop} toCheatSheet={toCheatSheet} />
    </ToastProvider>,
  );
}

const rows = (host: HTMLElement) => [...host.querySelectorAll<HTMLButtonElement>('.settingsScreen__row')];
const labels = (host: HTMLElement) => rows(host).map((row) => row.querySelector('.settingsScreen__rowLabel')?.textContent);
const reading = (host: HTMLElement, label: string) => rows(host).find((row) => row.querySelector('.settingsScreen__rowLabel')?.textContent === label)?.querySelector('.settingsScreen__rowSummary')?.textContent;

beforeEach(() => {
  native = false;
  android = false;
  localStorage.clear();
  setPreferences(DEFAULT_PREFERENCES);
  setDeveloperMode(false);
});

afterEach(() => {
  unmount();
  setPreferences(DEFAULT_PREFERENCES);
  localStorage.clear();
});

describe('the list of sections', () => {
  it('in a browser, has neither Recording nor Feel nor the hidden pages', () => {
    const host = settings();
    expect(labels(host)).toEqual(['Account', 'Type', 'Appearance', 'Formatting', 'Notion', 'GitHub', 'Claude', 'Plugins', 'Animations', 'Cheat sheet', 'About']);
  });

  it('on an Android phone, has Recording for its side key and Feel for its motor', () => {
    native = true;
    android = true;
    const host = settings();
    expect(labels(host)).toEqual(['Account', 'Type', 'Appearance', 'Recording', 'Formatting', 'Feel', 'Notion', 'GitHub', 'Claude', 'Plugins', 'Animations', 'Cheat sheet', 'About']);
  });

  it('grows Developer and Test results once developer mode is on', () => {
    setDeveloperMode(true);
    const host = settings();
    expect(labels(host).slice(-3)).toEqual(['About', 'Developer', 'Test results']);
  });

  it('gives each switched-on plugin with a page its own section, and drops one switched off', async () => {
    const { plugins } = await import('../plugins/registry.ts');
    const host = settings();
    expect(labels(host)).toContain('GitHub');
    plugins.setEnabled('github', false);
    try {
      await waitUntil(() => expect(labels(host)).not.toContain('GitHub'));
      expect(reading(host, 'Plugins')).toMatch(/^\d+ of \d+ on$/);
    } finally {
      plugins.setEnabled('github', true);
    }
  });

  it('opens on the cheat sheet when the Academy asks for it', () => {
    const host = settings(Date.now());
    expect(host.querySelector('.settingsScreen__display')?.textContent).toBe('Cheat sheet');
  });
});

describe('the readings', () => {
  it('say the text size and both faces under Type', () => {
    setPreferences({ textSize: 'larger', noteFace: 'fira', typeface: 'plex' });
    expect(reading(settings(), 'Type')).toBe('Larger · Fira Code · Plex');
  });

  it('name a tinted theme as its card does, and only what has moved off its default', () => {
    setPreferences({ theme: 'dawn', accent: 'red' });
    const host = settings();
    expect(reading(host, 'Appearance')).toBe('Dawn · Red');
    unmount();
    setPreferences({ theme: 'dark', accent: 'ink', density: 'compact', rounding: 'square' });
    expect(reading(settings(), 'Appearance')).toBe('Dark · Tight · Square');
  });

  it('say what moves under Animations, and All still when nothing does', () => {
    setPreferences({ wisp: true, wispEdge: false, ripples: true, motionSpeed: 'brisk' });
    expect(reading(settings(), 'Animations')).toBe('Ghostly typing · ripples · brisk');
    unmount();
    setPreferences({ wisp: false, wispEdge: false, ripples: false, motionSpeed: 'normal' });
    expect(reading(settings(), 'Animations')).toBe('All still');
  });

  it('put the version before where its updates stand under About', () => {
    expect(reading(settings(), 'About')).toBe('1.8.0 · Web version');
  });
});

/**
 * Settings a page draws only in some states, which the search still lists so it can open the page: each is here with
 * the reason it is not on the page in the state these tests draw it in. The cheat sheet is left out whole: its names
 * are the marks' own (guide/marks.ts), drawn as its cards rather than as the kit's rows, and the search only opens it.
 */
const ELSEWHERE: Record<string, string> = {
  // Signed out, the page is the ways in, and the signed-in rows are not drawn. The ways in are checked.
  'account/Sync now': 'signed in only',
  'account/Live typing (trial)': 'signed in only',
  'account/Password and recovery codes': 'signed in only',
  'account/Sign out': 'signed in only',
  'account/Shared links': 'signed in, with a link shared',
  'account/Delete account': 'signed in only',
  // The way in the page is showing is its form's title, not a row offering it.
  'account/I have an account': 'the mode the page opens in',
  // Android's own switch, drawn only where the activity has alerts to switch.
  'about/Update alerts': 'only where the activity has alerts',
};

/** Every setting the search lists that its section's page, drawn as the sheet hands it over, does not name. */
function missingFromTheirPages(): string[] {
  settings();
  const sections = handed;
  unmount();
  const missing: string[] = [];
  for (const section of sections) {
    if (section.id === 'cheatsheet') continue;
    const page = show(<ToastProvider>{section.content}</ToastProvider>);
    for (const { name } of section.settings ?? []) {
      if (!findSetting(page, name) && !ELSEWHERE[`${section.id}/${name}`]) missing.push(`${section.label}: ${name}`);
    }
    unmount();
  }
  return missing;
}

describe('the search', () => {
  it('finds every setting it lists on its page, in a browser', () => {
    // A browser has no models to list, so Formatting's page is the one card saying it runs on the phone.
    expect(missingFromTheirPages()).toEqual(['Formatting: Local only', 'Formatting: Model']);
  });

  it('finds every setting it lists on its page, on an Android phone with developer mode on', () => {
    native = true;
    android = true;
    setDeveloperMode(true);
    expect(missingFromTheirPages()).toEqual([]);
  });
});
