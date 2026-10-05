import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Updates } from '../core/ota.ts';
import type { SettingsSection } from './SettingsScreen.tsx';
import { show, unmount, waitUntil } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
// The kit's controls watch their boxes; jsdom has no observer.
stubResizeObserver();

// In the app or in a browser, on Android, an iPhone or neither, as each test says. The binary has the models a test
// puts in its catalogue (none unless it says), and answers nothing else: every other native read falls back to what a
// page shows before it has heard.
let native = false;
let android = false;
let iphone = false;
let catalogue: { id: string; file: string; bytes: number; present: boolean; path: string }[] = [];
vi.mock('../core/tauri.ts', () => ({
  isTauri: () => native,
  invoke: (command: string) => (command === 'ai_models' ? Promise.resolve(catalogue) : Promise.reject(new Error('no binary in a test'))),
}));
vi.mock('../core/platform.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../core/platform.ts')>();
  return {
    ...real,
    get isAndroid() {
      return android;
    },
    get isIOS() {
      return iphone;
    },
    get isMobile() {
      return android || iphone;
    },
    get isNativeMobile() {
      return (android || iphone) && native;
    },
  };
});
// A phone's width unless a test says the window is wide: the list, then a pane. The smoke under the header is its own
// test's (art/wispEdge.ts).
let wide = false;
vi.mock('../core/useWideScreen.ts', () => ({ useSidebar: () => wide }));
vi.mock('../art/wispEdge.ts', () => ({ useWispEdge: () => undefined }));
// Signed out, or signed in as sam, as each test says: the account the sheet and Account's page read.
let session: { handle: string; token: string; accountId: number } | null = null;
vi.mock('../core/account/account.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/account/account.ts')>()),
  useAccount: () => ({ session, unlocked: Boolean(session) }),
  accountState: () => ({ session, unlocked: Boolean(session) }),
}));
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
// The cheat sheet draws every mark with its own preview, thirty seconds of rendering on a loaded machine; all this file
// asks of it is that Settings can land on it, and the sheet itself is the guide's (guide/CheatSheet.tsx).
vi.mock('../guide/CheatSheet.tsx', () => ({ CheatSheet: () => <p>Every mark</p> }));
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
const { findSetting, searchSettings } = await import('./settingsSearch.ts');

/**
 * Settings as the app hands it over: which sections the list has on each kind of device, which are sub-pages behind
 * a row, what their readings say, and the promise its search makes - that a setting it finds is on its page, under the
 * name the search gave it. That last is a contract between two files for each page, the `findable` beside it (or a
 * plugin's `settings.settings`) and the labels the page draws, and nothing else checks that the two agree: a label
 * renamed in a pane leaves the search opening the page and finding nothing on it.
 *
 * Since docs/DESIGN.md §138: five rows, and every word the search found before still finds something. Notifications
 * joined Account on the first card with organizations (docs/TEAMS.md, D9), and Organizations is Account's sub-page.
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

/** What the examples' rows were asked to add, by the handler each called. */
const added: string[] = [];

/** The sheet as App.tsx hands it over, open unless a test closes it. */
function sheet(toCheatSheet = 0, toModel = 0, open = true) {
  const noop = () => undefined;
  const add = (what: string) => () => void added.push(what);
  return (
    <ToastProvider>
      <SettingsSheet
        open={open}
        onClose={noop}
        updates={updates}
        onGuide={noop}
        onSample={add('sample')}
        onGuideBook={noop}
        onBoard={add('board')}
        onCanvas={add('canvas')}
        onHowCanvas={add('how')}
        onAcademy={noop}
        toCheatSheet={toCheatSheet}
        toModel={toModel}
      />
    </ToastProvider>
  );
}

function settings(toCheatSheet = 0, toModel = 0): HTMLDivElement {
  return show(sheet(toCheatSheet, toModel));
}

const rows = (host: HTMLElement) => [...host.querySelectorAll<HTMLButtonElement>('.settingsScreen__row')];
const labels = (host: HTMLElement) => rows(host).map((row) => row.querySelector('.settingsScreen__rowLabel')?.textContent);
const reading = (host: HTMLElement, label: string) => rows(host).find((row) => row.querySelector('.settingsScreen__rowLabel')?.textContent === label)?.querySelector('.settingsScreen__rowSummary')?.textContent;
const section = (id: string) => handed.find((s) => s.id === id);
const names = (id: string) => section(id)?.settings?.map((s) => s.name);

beforeEach(() => {
  native = false;
  android = false;
  iphone = false;
  catalogue = [];
  added.length = 0;
  wide = false;
  session = null;
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
  // Changed on purpose (docs/DESIGN.md §138): twelve rows became four here, five where there is a recorder; and once
  // more for docs/TEAMS.md, which put Notifications beside Account on the first card.
  it('in a browser, is Account and Notifications, then Appearance, Plugins and About', () => {
    const host = settings();
    expect(labels(host)).toEqual(['Account', 'Organizations', 'Workspaces', 'Notifications', 'Appearance', 'Plugins', 'About']);
    expect(host.querySelectorAll('.settingsScreen__cluster')).toHaveLength(3);
    expect(names('theme')).not.toContain('Haptics');
  });

  it('on an Android phone, has Recording and AI beside Appearance and Plugins, and the haptics on Appearance', () => {
    native = true;
    android = true;
    const host = settings();
    expect(labels(host)).toEqual(['Account', 'Organizations', 'Workspaces', 'Backup', 'Notifications', 'Appearance', 'Recording', 'AI', 'Plugins', 'About']);
    expect([...host.querySelectorAll('.settingsScreen__cluster')].map((card) => [...card.querySelectorAll('.settingsScreen__rowLabel')].map((l) => l.textContent))).toEqual([
      ['Account', 'Organizations', 'Workspaces', 'Backup', 'Notifications'],
      ['Appearance', 'Recording', 'AI', 'Plugins'],
      ['About'],
    ]);
    expect(names('theme')).toContain('Haptics');
  });

  it('lists Notifications’ four switches for the search, and the card of organizations to mute only once there is one', async () => {
    settings();
    expect(names('notifications')).toEqual(['Team', 'Claude', 'Summaries', 'Conflicts']);
    expect(section('notifications')?.hue).toBeUndefined();
    unmount();
    session = { handle: 'sam', token: 't', accountId: 1 };
    const { saveOrgs, forgetOrgs } = await import('../core/orgs/orgs.ts');
    saveOrgs(1, { list: [{ id: 'o1', name: 'Ghost', hue: 'sea', role: 'member', state: 'member', members: 2, invitedBy: null, createdAt: 1 }], at: 1 });
    try {
      settings();
      expect(names('notifications')).toEqual(['Team', 'Claude', 'Summaries', 'Conflicts', 'Mute an organization']);
    } finally {
      forgetOrgs(1);
    }
  });

  it('on an Android phone, lists Recording’s rows for the search, each by its own name, the model gone to AI', () => {
    native = true;
    android = true;
    settings();
    expect(names('recording')).toEqual([
      'Stop when I go quiet',
      'Review after recording',
      'Better words',
      'Summaries',
      'Include sound from other apps',
      'Tell me when a meeting is written up',
      'Write up straight away',
      'Tapes',
      'Remove audio older than a month',
    ]);
    // The model and its own-fill switch are the AI section's now.
    expect(names('ai')).toEqual(['Model', 'Fill blanks on their own']);
  });

  it('in a browser on an Android phone, has Recording for the words, without the AI section, the meetings or the tapes', () => {
    android = true;
    const host = settings();
    expect(labels(host)).toEqual(['Account', 'Organizations', 'Workspaces', 'Notifications', 'Appearance', 'Recording', 'Plugins', 'About']);
    expect(names('recording')).toEqual(['Stop when I go quiet', 'Review after recording', 'Better words', 'Summaries']);
    // No model runs in a browser, so no AI section.
    expect(section('ai')).toBeUndefined();
  });

  it('on an iPhone, is the four a browser has: no Recording and no AI, where no model runs', () => {
    native = true;
    iphone = true;
    expect(labels(settings())).toEqual(['Account', 'Organizations', 'Workspaces', 'Notifications', 'Appearance', 'Plugins', 'About']);
    expect(section('ai')).toBeUndefined();
  });

  it('on the Mac, has Recording and AI too, the recording for the better words and the summaries', () => {
    native = true;
    const host = settings();
    expect(labels(host)).toEqual(['Account', 'Organizations', 'Workspaces', 'Backup', 'Notifications', 'Appearance', 'Recording', 'AI', 'Plugins', 'About']);
    expect(names('recording')).toEqual([
      'Stop when I go quiet',
      'Review after recording',
      'Better words',
      'Summaries',
      "Record the computer's sound too",
      'Tapes',
      'Remove audio older than a month',
    ]);
    expect(names('ai')).toEqual(['Model', 'Fill blanks on their own']);
  });

  it('grows Developer and Test results once developer mode is on, on a card of their own', () => {
    setDeveloperMode(true);
    const host = settings();
    expect(labels(host)).toEqual(['Account', 'Organizations', 'Workspaces', 'Notifications', 'Appearance', 'Plugins', 'About', 'Developer', 'Test results']);
    expect(host.querySelectorAll('.settingsScreen__cluster')).toHaveLength(4);
  });

  it('lists the sidebar’s choice for the search only on a window wide enough for it', () => {
    settings();
    expect(names('theme')).not.toContain('Sidebar');
    unmount();
    wide = true;
    settings();
    expect(names('theme')).toContain('Sidebar');
  });
});

describe('the sub-pages', () => {
  it('are each switched-on plugin’s page, the cheat sheet, the specification and the examples, off the list, each with its parent', () => {
    const host = settings();
    const hidden = handed.filter((s) => s.listed === false).map((s) => `${s.id} < ${s.parent}`);
    expect(hidden).toEqual(['plugin:notion < plugins', 'plugin:github < plugins', 'plugin:claude < plugins', 'cheatsheet < about', 'spec < about', 'examples < about']);
    for (const label of ['Notion', 'GitHub', 'Claude', 'Cheat sheet', 'Specification', 'Examples']) expect(labels(host)).not.toContain(label);
  });

  // The teams the account is in (docs/TEAMS.md): a row of their own under Account (Matt: "make an organizations tab
  // under account in the sidebar instead of nesting it inside the account page").
  it('open Organizations from its own row under Account, in blue, and step back to the list', async () => {
    session = { handle: 'sam', token: 't', accountId: 1 };
    const host = settings();
    const { act } = await import('react');
    act(() => rows(host).find((row) => row.textContent?.startsWith('Organizations'))!.click());
    expect(host.querySelector('.settingsScreen__display')?.textContent).toBe('Organizations');
    expect(host.querySelector('.settingsScreen__pane')?.getAttribute('data-hue')).toBe('blue');
    expect(host.querySelector('.setk__title')?.textContent).toBe('Your organizations');
  });

  it('open on a page asked for from outside by its id: Organizations, when an organization’s screen closes', () => {
    session = { handle: 'sam', token: 't', accountId: 1 };
    const host = show(
      <ToastProvider>
        <SettingsSheet open onClose={() => undefined} updates={updates} onGuide={() => undefined} onSample={() => undefined} onGuideBook={() => undefined} onBoard={() => undefined} onCanvas={() => undefined} onHowCanvas={() => undefined} onAcademy={() => undefined} toPage={{ id: 'organizations', nonce: 1 }} />
      </ToastProvider>,
    );
    expect(host.querySelector('.settingsScreen__display')?.textContent).toBe('Organizations');
  });

  it('drop a plugin’s page when it is switched off', async () => {
    const { plugins } = await import('../plugins/registry.ts');
    const host = settings();
    expect(section('plugin:github')).toBeDefined();
    plugins.setEnabled('github', false);
    try {
      await waitUntil(() => expect(section('plugin:github')).toBeUndefined());
      expect(reading(host, 'Plugins')).toMatch(/^\d+ of \d+ on$/);
    } finally {
      plugins.setEnabled('github', true);
    }
  });

  it('colour a plugin’s page as the plugin says, where the shell names no plugin', () => {
    settings();
    expect(['plugin:notion', 'plugin:github', 'plugin:claude'].map((id) => section(id)?.hue)).toEqual(['graphite', 'graphite', 'coral']);
  });

  it('open on the cheat sheet when the Academy asks for it, with About in the head', () => {
    const host = settings(Date.now());
    expect(host.querySelector('.settingsScreen__display')?.textContent).toBe('Cheat sheet');
    expect(host.querySelector('.settingsScreen__headWord')?.textContent?.trim()).toBe('About');
  });

  it('open on the list the next time, not on the page the last link opened', async () => {
    const { rerender } = await import('../../test/render.tsx');
    const asked = Date.now();
    const host = settings(asked);
    expect(host.querySelector('.settingsScreen__display')?.textContent).toBe('Cheat sheet');
    rerender(sheet(asked, 0, false));
    rerender(sheet(asked, 0, true));
    expect(host.querySelector('.settingsScreen__display')).toBeNull();
    expect(labels(host)).toContain('About');
  });

  it('open Examples from About’s Help in yellow, each row adding its own example, and step back to About', async () => {
    const host = settings();
    const { act } = await import('react');
    const pressRow = (label: string) =>
      act(() => [...host.querySelectorAll<HTMLButtonElement>('button.setk-row--press')].find((b) => b.querySelector('.setk-row__label')?.textContent === label)!.click());
    act(() => rows(host).find((row) => row.textContent?.includes('About'))!.click());
    pressRow('Examples');
    expect(host.querySelector('.settingsScreen__display')?.textContent).toBe('Examples');
    expect(host.querySelector('.settingsScreen__headWord')?.textContent?.trim()).toBe('About');
    expect(host.querySelector('.settingsScreen__pane')?.getAttribute('data-hue')).toBe('yellow');
    for (const label of ['Add the sample note', 'Add the example board', 'Add the example canvas', 'Add the “How Ghost.md works” canvas']) pressRow(label);
    expect(added).toEqual(['sample', 'board', 'canvas', 'how']);
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
    expect(host.querySelector('.settingsScreen__display')?.textContent).toBe('About');
  });

  it('open on a plugin’s page from its card on Plugins, and step back to Plugins', async () => {
    const host = settings();
    const { act } = await import('react');
    act(() => rows(host).find((row) => row.textContent?.includes('Plugins'))!.click());
    const card = [...host.querySelectorAll('section')].find((s) => s.querySelector('.setk-hero__title')?.textContent === 'GitHub')!;
    act(() => card.querySelector<HTMLButtonElement>('button.setk-row--press')!.click());
    expect(host.querySelector('.settingsScreen__display')?.textContent).toBe('GitHub');
    expect(host.querySelector('.settingsScreen__pane')?.getAttribute('data-hue')).toBe('graphite');
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
    expect(host.querySelector('.settingsScreen__display')?.textContent).toBe('Plugins');
  });
});

describe('the targets', () => {
  // Opened on Formatting before §138, then Recording's Model card; the model has its own AI section now.
  it('open on AI with the Model card lit when the shelf’s Get a model asks for it', async () => {
    native = true;
    android = true;
    const host = settings(0, Date.now());
    expect(host.querySelector('.settingsScreen__display')?.textContent).toBe('AI');
    await waitUntil(() => expect(host.querySelector('[data-found] .setk__title')?.textContent).toBe('Model'));
  });

  it('light the Privacy card from the words “Local only” in Account’s own callout', async () => {
    session = { handle: 'sam', token: 't', accountId: 1 };
    setPreferences({ localOnly: true });
    const host = settings();
    const { act } = await import('react');
    act(() => rows(host).find((row) => row.textContent?.includes('Account'))!.click());
    act(() => host.querySelector<HTMLButtonElement>('.setk-callout .setk-go')!.click());
    await waitUntil(() => expect(host.querySelector('[data-found] .setk__title')?.textContent).toBe('Privacy'));
  });

  it('open Account at the Privacy card from the words “Local only” on Plugins', async () => {
    setPreferences({ localOnly: true });
    const host = settings();
    const { act } = await import('react');
    act(() => rows(host).find((row) => row.textContent?.includes('Plugins'))!.click());
    act(() => host.querySelector<HTMLButtonElement>('.setk-callout .setk-go')!.click());
    expect(host.querySelector('.settingsScreen__display')?.textContent).toBe('Account');
    await waitUntil(() => expect(host.querySelector('[data-found] .setk__title')?.textContent).toBe('Privacy'));
  });
});

describe('the readings', () => {
  it('name the theme and the note’s face under Appearance, and only what else has moved off its default', () => {
    setPreferences({ theme: 'dark' });
    expect(reading(settings(), 'Appearance')).toBe('Dark · Maple Mono');
    unmount();
    setPreferences({ theme: 'dawn', accent: 'red' });
    expect(reading(settings(), 'Appearance')).toBe('Dawn · Maple Mono · Red');
    unmount();
    setPreferences({ theme: 'dark', accent: 'ink', density: 'compact', rounding: 'square', textSize: 'larger', noteFace: 'fira', typeface: 'plex' });
    expect(reading(settings(), 'Appearance')).toBe('Dark · Fira Code · Larger · Plex · Tight · Square');
  });

  // What a take becomes, under Recording, now that the model's line moved to AI.
  it('say what a take becomes under Recording, and leave the model to AI', async () => {
    native = true;
    android = true;
    setPreferences({ refine: true });
    expect(reading(settings(), 'Recording')).toBe('Better words');
    unmount();
    setPreferences({ refine: false });
    expect(reading(settings(), 'Recording')).toBe('Words as heard');
    unmount();
    // A browser on an Android phone: the same, and no AI section to read.
    native = false;
    setPreferences({ refine: true });
    const host = settings();
    expect(reading(host, 'Recording')).toBe('Better words');
    expect(section('ai')).toBeUndefined();
  });

  // The model the AI runs, and what it takes to get: the model first and no "on the phone", so the line fits the
  // split view's column.
  it('say the model the AI runs, and what it takes to get, under AI', async () => {
    native = true;
    android = true;
    setPreferences({ refine: true });
    expect(reading(settings(), 'AI')).toBe('Qwen3.5 4B, 2.7 GB to get');
    unmount();
    catalogue = [{ id: 'qwen3.5-4b', file: 'qwen3.5-4b.gguf', bytes: 2_740_937_888, present: true, path: '/models/qwen3.5-4b.gguf' }];
    const host = settings();
    await waitUntil(() => expect(reading(host, 'AI')).toBe('Qwen3.5 4B'));
  });

  it('say Local only after the account under Account while it holds the sync off', () => {
    setPreferences({ localOnly: true });
    expect(reading(settings(), 'Account')).toBe('Not signed in · Local only');
  });

  it('put the version before where its updates stand under About', () => {
    expect(reading(settings(), 'About')).toBe('1.8.0 · Web version');
  });

  // How many of the four switches are on, under Notifications (docs/TEAMS.md, D9).
  it('count the switches that are on under Notifications, in Plugins’ shape', () => {
    expect(reading(settings(), 'Notifications')).toBe('4 of 4 on');
    unmount();
    setPreferences({ notifications: { team: true, claude: false, summaries: true, conflicts: false, mutedOrgs: [] } });
    expect(reading(settings(), 'Notifications')).toBe('2 of 4 on');
  });
});

/**
 * Settings a page draws only in some states, which the search still lists so it can open the page: each is here with
 * the reason it is not on the page in the states these tests draw it in. The cheat sheet is left out whole: its names
 * are the marks' own (guide/marks.ts), drawn as its cards rather than as the kit's rows, and the search only opens it.
 */
const ELSEWHERE: Record<string, string> = {
  // Signed in, a card drawn only while a link is shared.
  'account/Shared links': 'signed in, with a link shared',
  // Signed in, the page's one row to its sub-page is in the signed-in branch; signed out the search lists it still.
  // The way in the page is showing is its form's title, not a row offering it.
  'account/I have an account': 'the mode the page opens in',
  // Android's own switch, drawn only where the activity has alerts to switch.
  'about/Update alerts': 'only where the activity has alerts',
  // Meetings' rows, drawn only on a phone whose binary has the service (native generation 20); the test's binary answers no generation.
  'recording/Tell me when a meeting is written up': 'only with the meeting service',
  'recording/Write up straight away': 'only with the meeting service',
  'recording/Include sound from other apps': 'only with the meeting service',
  // Notion's page is an empty state in a browser and on a binary without its commands; its boards, once signed in to Notion.
  'plugin:notion/Account': 'only in the app, with Notion’s commands',
  'plugin:notion/Boards': 'only signed in to Notion',
};

/** Every setting the search lists that its section's page, drawn as the sheet hands it over, does not name: listed pages, sub-pages and plugin pages. */
function missingFromTheirPages(): string[] {
  settings();
  const sections = handed;
  unmount();
  const missing: string[] = [];
  for (const one of sections) {
    if (one.id === 'cheatsheet') continue;
    const page = show(<ToastProvider>{one.content}</ToastProvider>);
    for (const { name } of one.settings ?? []) {
      if (!findSetting(page, name) && !ELSEWHERE[`${one.id}/${name}`]) missing.push(`${one.label}: ${name}`);
    }
    unmount();
  }
  return missing;
}

describe('the search', () => {
  it('finds every setting it lists on its page, in a browser, signed out', () => {
    expect(missingFromTheirPages()).toEqual([]);
  });

  it('finds every setting it lists on its page, on an Android phone with developer mode on, signed out', () => {
    native = true;
    android = true;
    setDeveloperMode(true);
    expect(missingFromTheirPages()).toEqual([]);
  });

  it('finds every setting it lists on its page, on an Android phone, signed in', () => {
    native = true;
    android = true;
    session = { handle: 'sam', token: 't', accountId: 1 };
    expect(missingFromTheirPages()).toEqual([]);
  });

  it('finds every setting it lists on its page, in a browser on an Android phone, signed out', () => {
    android = true;
    expect(missingFromTheirPages()).toEqual([]);
  });

  it('finds every setting it lists on its page, on an iPhone, signed in', () => {
    native = true;
    iphone = true;
    session = { handle: 'sam', token: 't', accountId: 1 };
    expect(missingFromTheirPages()).toEqual([]);
  });

  it('finds every setting it lists on its page, on the Mac on a wide window, signed in', () => {
    native = true;
    wide = true;
    session = { handle: 'sam', token: 't', accountId: 1 };
    expect(missingFromTheirPages()).toEqual([]);
  });

  it('lists nothing twice on a page', () => {
    native = true;
    android = true;
    setDeveloperMode(true);
    settings();
    for (const one of handed) {
      const list = (one.settings ?? []).map((s) => s.name);
      expect(new Set(list).size, one.id).toBe(list.length);
    }
  });

  /** Each kind of device, as the app tells them apart (core/platform.ts, core/tauri.ts). */
  const DEVICES: Record<string, () => void> = {
    'the Android app': () => {
      native = true;
      android = true;
    },
    'the Mac app': () => {
      native = true;
    },
    'the iPhone app': () => {
      native = true;
      iphone = true;
    },
    'a browser on an Android phone': () => {
      android = true;
    },
    'a browser': () => undefined,
  };

  /** Every section a device in developer mode has (an Android phone unless one is named), signed out and in, on a phone's window and a wide one. */
  function everySection(device: () => void = DEVICES['the Android app']!): SettingsSection[] {
    device();
    setDeveloperMode(true);
    const all: SettingsSection[] = [];
    for (const signedIn of [false, true]) {
      for (const isWide of [false, true]) {
        session = signedIn ? { handle: 'sam', token: 't', accountId: 1 } : null;
        wide = isWide;
        settings();
        all.push(...handed);
        unmount();
      }
    }
    return all;
  }

  /**
   * Every name and word the search knew on main before §138 (60716fa's SettingsSheet.tsx, its hand-kept lists), each
   * alone: each still finds something, so nothing a person looked for before is gone. Renamed rows are in the next test.
   */
  const BEFORE = `Account sign in login handle encrypted Sync now devices Sync meeting recordings audio meeting privacy Live typing (trial)
    realtime collaborate Password and recovery codes change Sign out log out logout Shared links share publish read Delete account
    remove close erase data I have an account Create an account sign up register Lost the password forgot recovery code reset Type
    text font Text size bigger smaller larger Note font typeface body note editor maple fira mono monospace code coding ligatures inter
    noto plex Interface font ui app tabs menus Link previews links url cards Appearance theme look Page light dark system dawn boreal
    ember Accent colour color highlight Spacing density compact padding roomy tight Size scale zoom interface Sidebar dock column
    popover notes list Corners rounding radius round square Code syntax highlighting colours colors Recording voice microphone mic
    dictate Stop when I go quiet silence auto stop Review after recording check transcript Better words refine clean up Summaries
    summary write-up minutes Write up battery charging Tell me when a meeting
    is written up notification alert Your tapes tapes storage space Location map place where geotag gps Map on a tagged note
    openstreetmap tiles Place names nominatim address geocode Tag new notes with my location automatic Formatting ai model Local
    only offline network internet nothing leaves the phone Model download llm Feel motion movement vibration Animation speed fast
    slow Ghostly typing wisp letters Smoke at the edges fade scroll Ripples while recording waves Haptics vibrate buzz touch Plugins
    extensions integrations add-ons Cheat sheet markdown marks help About version Updates update upgrade install Update alerts
    notifications notify What's new changelog releases Ghost.md Academy learn tutorial lessons How to talk to Ghost.md commands cues
    hey ghost keyword Add Ghost.md: The Guide guide manual book Add the sample note example Add the example board kanban Add the
    example canvas Privacy policy personal information Developer debug Welcome guide onboarding set-up Choose your model Smoke bench
    performance frames Developer settings mode Reset local data clear Reset everything models Window inset screen engine Test results
    tests report`;

  it('still finds every word it found before', () => {
    const all = everySection();
    const words = [...new Set(BEFORE.split(/\s+/).filter(Boolean))];
    const lost = words.filter((word) => searchSettings(all, word).length === 0);
    expect(lost).toEqual([]);
  });

  /*
   * The words above that find nothing on a device, each for a setting that device does not have. Most found nothing
   * there before §138 either (a browser never had a recorder). Those that did are said by name: they were a page's own
   * words on a device where the page had nothing of theirs to show.
   */
  /**
   * Recording's: no recorder in a browser on a computer, or on an iPhone. "Summaries" and "summary" are found on every
   * device since docs/TEAMS.md: Notifications' Summaries row, the feed's row for a meeting written up elsewhere.
   */
  const RECORDER = 'microphone mic dictate Stop go quiet silence stop Review after transcript Better refine clean write-up minutes';
  /**
   * The meetings', the Android app's with the service. A browser on an Android phone listed them before and never drew
   * them: there is no meeting service in a page. "written" is no longer theirs alone: Notifications' Summaries row
   * says "a meeting written up" on every device (docs/TEAMS.md, D9).
   */
  const MEETINGS = 'battery charging Tell';
  /**
   * The tapes', in the app. A browser on an Android phone listed "Your tapes" before and had no file to count. "space"
   * finds Workspaces on every device since it is a page of its own.
   */
  const TAPES = 'storage';
  /**
   * The model's, where a model runs (the Android app and the Mac). Formatting was listed everywhere before, with only an
   * empty state off Android, and Developer's "Choose your model" with it. "ai" finds the specification's AI fills on
   * every device since GLY-4, as the fills are written the same way everywhere.
   */
  const MODEL = 'download llm Choose';
  /** The haptics', where there is a motor. Feel's own word "vibration" found Feel before on a device with no motor. */
  const MOTOR = 'vibration Haptics vibrate buzz touch';
  /** What's new's, which About does not draw on an iPhone, where the App Store says it. Listed before, it lit nothing. */
  const RELEASES = "What's changelog releases";
  const LOSSES: Record<string, string> = {
    'the Android app': '',
    'the Mac app': [MEETINGS, MOTOR].join(' '),
    'the iPhone app': [RECORDER, MEETINGS, TAPES, MODEL, RELEASES].join(' '),
    'a browser on an Android phone': [MEETINGS, TAPES, MODEL, MOTOR].join(' '),
    'a browser': [RECORDER, MEETINGS, TAPES, MODEL, MOTOR].join(' '),
  };

  it('on each device, finds nothing only for a setting that device does not have', () => {
    const words = [...new Set(BEFORE.split(/\s+/).filter(Boolean))];
    const sorted = (list: string) => list.split(/\s+/).filter(Boolean).sort();
    for (const [name, device] of Object.entries(DEVICES)) {
      const all = everySection(device);
      native = false;
      android = false;
      iphone = false;
      expect(words.filter((word) => searchSettings(all, word).length === 0).sort(), name).toEqual(sorted(LOSSES[name]!));
    }
  });

  /** Where a search for what was there before lands now, section/setting (a section alone when its name is found). */
  const MOVED: [string, string][] = [
    ['formatting', 'ai/Model'],
    ['choose your model', 'ai/Model'],
    ['local only', 'account/Local only'],
    ['link previews', 'account/Link previews'],
    ['privacy policy', 'account/Privacy policy'],
    ['location', 'account/Location'],
    ['tag new notes', 'account/Tag new notes with my location'],
    ['type', 'theme/Type'],
    ['feel', 'theme'],
    ['animations', 'theme/Motion'],
    ['size', 'theme/Scale'],
    ['haptics', 'theme/Haptics'],
    ['write up', 'recording/Write up straight away'],
    ['your tapes', 'recording/Tapes'],
    ['how to talk to ghost.md', 'about/The welcome walkthrough'],
    ['hey ghost', 'about/The welcome walkthrough'],
    ['welcome guide', 'about/The welcome walkthrough'],
    ['add ghost.md: the guide', 'about/Ghost.md: The Guide'],
    ['cheat sheet', 'cheatsheet'],
    ['add the sample note', 'examples/Add the sample note'],
    ['kanban', 'examples/Add the example board'],
    ['notion', 'plugin:notion'],
    ['boards', 'plugin:notion/Boards'],
    ['tools', 'plugin:claude/What Claude can do'],
    ['token', 'plugin:github/Token'],
  ];

  it('opens the Privacy card first for “privacy”, signed in or out', () => {
    for (const signedIn of [false, true]) {
      session = signedIn ? { handle: 'sam', token: 't', accountId: 1 } : null;
      settings();
      const first = searchSettings(handed, 'privacy')[0];
      expect(first && `${first.section.id}/${first.setting}`, String(signedIn)).toBe('account/Privacy');
      unmount();
    }
  });

  it('shows a sub-page once, by its own name, and not About’s row that opens it as well', () => {
    settings();
    for (const [query, label] of [
      ['examples', 'Examples'],
      ['cheat sheet', 'Cheat sheet'],
    ]) {
      const hits = searchSettings(handed, query!).map((hit) => hit.setting ?? hit.section.label);
      expect(hits.filter((hit) => hit === label), query).toHaveLength(1);
    }
  });

  it('lands what was there before on its new place', () => {
    const all = everySection();
    for (const [query, place] of MOVED) {
      const hits = searchSettings(all, query).map((hit) => (hit.setting ? `${hit.section.id}/${hit.setting}` : hit.section.id));
      expect(hits, query).toContain(place);
    }
  });
});
