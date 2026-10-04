import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, type ComponentProps } from 'react';
import type { NoteScreen } from './editor/NoteScreen.tsx';
import type { CaptureScreen } from './capture/CaptureScreen.tsx';
import type { Guide } from './guide/Guide.tsx';
import type { SettingsSheet } from './settings/SettingsSheet.tsx';
import type { OrganizationSheet } from './settings/OrganizationSheet.tsx';
import type { NotificationsDrawer } from './notes/NotificationsDrawer.tsx';
import type { OrganizationLog } from './notes/OrganizationLog.tsx';
import type { OrganizationScreen } from './notes/OrganizationScreen.tsx';
import { createNote, getNote, listNotes, setNoteArchived, updateNote, type Note } from './core/store.ts';
import { preferences, reloadPreferences, setPreferences } from './core/preferences.ts';
import { button, buttonSaying, show, unmount, waitUntil } from '../test/render.tsx';
import { stubResizeObserver } from '../test/stubs.ts';
import { bookNoteBody } from './book/book.ts';
import { PRESETS } from './book/journal.ts';
import { writeBookSpot } from './book/bookSpot.ts';

/**
 * The Shell (App.tsx) as a person moves through it: which screen is up, the tab row it keeps, the trail the arrows
 * walk, where a capture comes back to, a delete that is hidden at once, and a shared link opened from the address.
 *
 * The screens it routes between are stood in for by stubs that show which note they were given and hand their props
 * to the test - the editor, the recorder, the guide and the Settings sheet each have their own tests, and mounting the
 * real ones here would put CodeMirror and a microphone under every case. What is real is the Shell, the tab row
 * (notes/NoteTabs.tsx), the home page and the note store's browser half.
 */

// The Glacier kit asks matchMedia as it loads, so the stub is in before anything imports it.
await vi.hoisted(async () => (await import('../test/stubs.ts')).stubMatchMedia());

type NoteProps = ComponentProps<typeof NoteScreen>;
type CaptureProps = ComponentProps<typeof CaptureScreen>;
type GuideProps = ComponentProps<typeof Guide>;
type SettingsProps = ComponentProps<typeof SettingsSheet>;
type OrganizationProps = ComponentProps<typeof OrganizationSheet>;
type NotificationsProps = ComponentProps<typeof NotificationsDrawer>;
type DashboardProps = ComponentProps<typeof OrganizationScreen>;
type LogProps = ComponentProps<typeof OrganizationLog>;

/** The props each stubbed screen was last drawn with, for the test to press what the screen would. */
const seen = vi.hoisted(() => ({
  note: null as NoteProps | null,
  capture: null as CaptureProps | null,
  guide: null as GuideProps | null,
  settings: null as SettingsProps | null,
  organization: null as OrganizationProps | null,
  notifications: null as NotificationsProps | null,
  dashboard: null as DashboardProps | null,
  log: null as LogProps | null,
}));

vi.mock('./editor/NoteScreen.tsx', () => ({
  NoteScreen: (props: NoteProps) => {
    seen.note = props;
    return <main data-screen="note" data-note={props.note.id} data-at={props.at ?? ''} data-body={props.note.body} />;
  },
}));
vi.mock('./capture/CaptureScreen.tsx', () => ({
  CaptureScreen: (props: CaptureProps) => {
    seen.capture = props;
    return <main data-screen="capture" data-from-assistant={String(props.fromAssistant)} data-stop={props.stopRequests ?? 0} data-into={props.noteId ?? ''} />;
  },
}));
vi.mock('./guide/Guide.tsx', () => ({
  Guide: (props: GuideProps) => {
    seen.guide = props;
    return <div data-screen="guide" data-index={props.index} data-too-soon={String(Boolean(props.tooSoon))} />;
  },
}));
vi.mock('./settings/SettingsSheet.tsx', () => ({
  SettingsSheet: (props: SettingsProps) => {
    seen.settings = props;
    return props.open ? <div data-screen="settings" data-to-page={props.toPage?.id ?? ''} /> : null;
  },
}));
// An organization's settings and dashboard, and the notifications drawer (docs/TEAMS.md), have their own tests against the service in memory.
vi.mock('./settings/OrganizationSheet.tsx', () => ({
  OrganizationSheet: (props: OrganizationProps) => {
    seen.organization = props;
    return <div data-screen="organization" data-org={props.orgId} data-from={props.from ?? ''} />;
  },
}));
vi.mock('./notes/NotificationsDrawer.tsx', () => ({
  NotificationsDrawer: (props: NotificationsProps) => {
    seen.notifications = props;
    return <div data-drawer="notifications" />;
  },
}));
vi.mock('./notes/OrganizationScreen.tsx', () => ({
  OrganizationScreen: (props: DashboardProps) => {
    seen.dashboard = props;
    return <main data-screen="dashboard" data-org={props.orgId} />;
  },
}));
vi.mock('./notes/OrganizationLog.tsx', () => ({
  OrganizationLog: (props: LogProps) => {
    seen.log = props;
    return <main data-screen="audit" data-org={props.orgId} />;
  },
}));
// A sync pass runs before the guide is added; the test sees when.
vi.mock('./core/sync/engine.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('./core/sync/engine.ts')>();
  return { ...real, syncNow: vi.fn(real.syncNow) };
});
// The guide's chapters are chunks fetched on the press; a test can make that fetch fail.
vi.mock('./guidebook/guidebook.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('./guidebook/guidebook.ts')>();
  return { ...real, addGuideBook: vi.fn(real.addGuideBook) };
});
vi.mock('./academy/AcademyScreen.tsx', () => ({ AcademyScreen: () => <main data-screen="academy" /> }));
// Its rAF clock and its wink are its own test's business; here the app is simply open.
vi.mock('./launch/LaunchScreen.tsx', () => ({ LaunchScreen: () => null }));
// A card's small drawing is a CodeMirror editor (notes/NotePeek.tsx), one per card: nothing the Shell decides.
vi.mock('./notes/NotePeek.tsx', () => ({ NotePeek: () => null }));
// The summary queue (§127 section 2), held quiet: the queue itself is the real one, which does nothing off the phone.
vi.mock('./ai/summaries.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./ai/summaries.ts')>()),
  useSummaries: () => ({ pending: new Set<string>(), native: new Set<string>(), waiting: new Set<string>(), failed: new Set<string>(), needsModel: new Set<string>() }),
  retrySummary: () => undefined,
}));
// The store's writes, watched: a test can see what was already kept when one was made, or have one lose a race.
vi.mock('./core/store.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('./core/store.ts')>();
  return { ...real, createNote: vi.fn(real.createNote), updateNote: vi.fn(real.updateNote) };
});
// Where a journal's entry was written is asked through here: a test sees whether it was asked, when, and how.
vi.mock('./core/location.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('./core/location.ts')>();
  return { ...real, tagEntryIfWanted: vi.fn(real.tagEntryIfWanted) };
});
// The Mac app, where a test says so: ⌘N is bound only there. A phone, where one says so: the bar is quieter on a note.
const device = vi.hoisted(() => ({ mac: false, mobile: false }));
vi.mock('./core/platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./core/platform.ts')>()),
  get isMacApp() {
    return device.mac;
  },
  get isMobile() {
    return device.mobile;
  },
}));
vi.mock('./share/share.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./share/share.ts')>()),
  readShared: vi.fn(async () => ({ v: 1, kind: 'note', title: 'Shared', pages: [{ title: 'Shared', body: '# Shared\n\nFrom a friend.' }], at: 1 })),
  forkShared: vi.fn(async () => createNote('forked', '# Shared\n\nFrom a friend.')),
}));

const { App } = await import('./App.tsx');
const { tagEntryIfWanted } = await import('./core/location.ts');
const realStore = await vi.importActual<typeof import('./core/store.ts')>('./core/store.ts');
const { addGuideBook } = await import('./guidebook/guidebook.ts');
const { syncNow } = await import('./core/sync/engine.ts');

// The home page and the tab row watch their own sizes; jsdom lays nothing out, so nothing ever resizes.
stubResizeObserver();

const root = document.documentElement;
const screenNow = () => document.querySelector<HTMLElement>('[data-screen]:not([data-screen="guide"]):not([data-screen="settings"])');
const noteShown = () => document.querySelector<HTMLElement>('[data-screen="note"]')?.dataset.note ?? null;
const tabs = () => [...document.querySelectorAll('[role="tablist"] [data-tab]')].map((tab) => tab.getAttribute('data-tab-id'));
/** A card on the home page, by the title it shows. */
const card = (title: string) => {
  const found = [...document.querySelectorAll<HTMLButtonElement>('ol li button')].find((b) => b.textContent?.includes(title));
  if (!found) throw new Error(`no card ${title}`);
  return found;
};

async function seed(...notes: [id: string, body: string][]): Promise<void> {
  // Oldest first, so the first named is the newest, as the home page orders them.
  for (const [id, body] of [...notes].reverse()) await createNote(id, body);
}

async function openApp(): Promise<void> {
  show(<App />);
  // The notes are read on the store's own schedule; the home page draws once they are.
  await waitUntil(() => expect(document.querySelector('nav[aria-label="New note"]')).not.toBeNull());
  await act(async () => {
    // One more turn, for the read's answer to reach every screen.
  });
}

beforeEach(() => {
  localStorage.clear();
  // The walkthrough opens by itself on a first launch; these tests are of a device that has seen it.
  localStorage.setItem('glyph-guide-seen', '1');
  // So has its way into an account, which comes first on a signed-out open (shell/useAccountGate.ts).
  localStorage.setItem('glyph-account-gate-seen', '1');
  // The preferences are held in memory as well as kept: a tab row, a group or the trash left by the last test goes.
  reloadPreferences();
  history.replaceState(null, '', '/');
  seen.note = null;
  seen.capture = null;
  seen.guide = null;
  seen.settings = null;
  seen.organization = null;
  seen.notifications = null;
  seen.dashboard = null;
  seen.log = null;
});

afterEach(() => {
  unmount();
  vi.useRealTimers();
  vi.mocked(createNote).mockImplementation(realStore.createNote);
  vi.mocked(updateNote).mockImplementation(realStore.updateNote);
  vi.mocked(createNote).mockClear();
  vi.mocked(updateNote).mockClear();
  vi.mocked(tagEntryIfWanted).mockClear();
  delete window.__glyph;
});

describe('the tab row', () => {
  it('opens home with the bar a single row, and a note shown becomes a tab the bar makes room for', async () => {
    await seed(['a', '# Apples'], ['b', '# Bread']);
    await openApp();
    expect(root.dataset.tabs).toBe('on');
    expect(tabs()).toEqual([]);
    act(() => card('Apples').click());
    expect(noteShown()).toBe('a');
    expect(tabs()).toEqual(['a']);
    expect(root.dataset.tabs).toBe('rows');
    // The row is a synced preference, so a reload or another device finds it.
    expect(preferences().openNotes).toEqual(['a']);
  });

  // The bar's four ways (shell/topBar.ts; docs/DESIGN.md §178, §180): how many lines it is.
  it('is two lines for the Ledger always, and for the Masthead only with a note open', async () => {
    await seed(['a', '# Apples']);
    setPreferences({ topBar: 'masthead' });
    await openApp();
    expect(root.dataset.topbar).toBe('masthead');
    expect(root.dataset.tabs).toBe('on');
    act(() => card('Apples').click());
    expect(root.dataset.tabs).toBe('rows');
    act(() => setPreferences({ topBar: 'ledger' }));
    act(() => button('Close Apples').click());
    expect(root.dataset.tabs).toBe('rows');
    act(() => setPreferences({ topBar: 'classic' }));
    expect(root.dataset.tabs).toBe('on');
    expect(root.dataset.topbar).toBeUndefined();
  });

  it('closes the tab being read onto its neighbour, and the last one home', async () => {
    await seed(['a', '# Apples'], ['b', '# Bread']);
    await openApp();
    act(() => card('Apples').click());
    act(() => button('Home').click());
    act(() => card('Bread').click());
    expect(tabs()).toEqual(['a', 'b']);
    act(() => button('Close Bread').click());
    expect(noteShown()).toBe('a');
    expect(tabs()).toEqual(['a']);
    act(() => button('Close Apples').click());
    expect(noteShown()).toBeNull();
    expect(document.querySelector('nav[aria-label="New note"]')).not.toBeNull();
    expect(root.dataset.tabs).toBe('on');
  });

  it('gives a page opened from inside a note the tab it was opened from', async () => {
    await seed(['a', '# Apples'], ['b', '# Bread']);
    await openApp();
    act(() => card('Apples').click());
    await act(async () => seen.note!.onOpenWithin!('Bread'));
    expect(noteShown()).toBe('b');
    expect(tabs()).toEqual(['b']);
    // An ordinary open after it takes a tab of its own again.
    await act(async () => seen.note!.onOpenTitle!('Apples'));
    expect(tabs()).toEqual(['b', 'a']);
  });

  it('gives a note opened after a page asked for its own tab again a tab of its own, from the + or from home', async () => {
    await seed(['a', '# Apples'], ['b', '# Bread']);
    await openApp();
    act(() => card('Apples').click());
    // The chapter being read, tapped in the aside: nothing changes, and nothing is left waiting to take its tab.
    await act(async () => seen.note!.onOpenWithin!('Apples'));
    expect(tabs()).toEqual(['a']);
    act(() => button('New note in a new tab').click());
    await act(async () => buttonSaying(document.body, 'A page of markdown')!.click());
    await waitUntil(() => expect(tabs()).toHaveLength(2));
    const made = tabs()[1];
    expect(tabs()).toEqual(['a', made]);
    act(() => button('Apples').click());
    await act(async () => seen.note!.onOpenWithin!('Apples'));
    act(() => button('Home').click());
    act(() => card('Bread').click());
    expect(tabs()).toEqual(['a', made, 'b']);
  });

  it('closes a whole group, the note being read in it, onto the first tab left outside it', async () => {
    await seed(['a', '# Apples'], ['b', '# Bread'], ['c', '# Cheese']);
    setPreferences({ openNotes: ['a', 'b', 'c'], tabGroups: { list: [{ id: 'g', name: 'Lunch', hue: 'sea' }], of: { a: 'g', b: 'g' } } });
    await openApp();
    act(() => button('Apples').click());
    act(() => void button('Lunch, 2 tabs').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })));
    act(() => [...document.querySelectorAll<HTMLElement>('[role="menuitem"]')].find((item) => item.textContent === 'Close group')!.click());
    expect(tabs()).toEqual(['c']);
    expect(noteShown()).toBe('c');
  });

  it("closes the note being read from the palette onto the tab beside it now, not one closed since", async () => {
    await seed(['a', '# Apples'], ['b', '# Bread'], ['c', '# Cheese']);
    setPreferences({ openNotes: ['a', 'b', 'c'] });
    await openApp();
    act(() => button('Cheese').click());
    // A tab behind the one being read, closed by hand: the row changes and the screen does not.
    act(() => button('Close Bread').click());
    expect(tabs()).toEqual(['a', 'c']);
    act(() => button('All your notes').click());
    act(() => button('Search and commands').click());
    const command = [...document.querySelectorAll<HTMLElement>('[role="option"]')].find((option) => option.textContent?.includes('Close the Cheese tab'));
    // The kit's palette runs a command on the press itself, before the click.
    act(() => void command!.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true })));
    expect(tabs()).toEqual(['a']);
    expect(noteShown()).toBe('a');
  });

  it('keeps tab groups through the first render, before any note has loaded', async () => {
    await seed(['a', '# Apples'], ['b', '# Bread']);
    const groups = { list: [{ id: 'g', name: 'Food', hue: 'sea' as const, collapsed: false }], of: { a: 'g' } };
    setPreferences({ openNotes: ['a', 'b'], tabGroups: groups });
    await openApp();
    expect(tabs()).toEqual(['a', 'b']);
    expect(preferences().tabGroups).toEqual(groups);
    expect(document.querySelector('[data-group-chip="g"]')).not.toBeNull();
  });
});

describe('a book opened from outside it', () => {
  it('goes back to the chapter it was left at, from the home page or a [[link]], while its tab shows the index', async () => {
    await seed(['book', bookNoteBody('Field guide', ['Introduction', 'Trees'])], ['intro', '# Introduction\n\nWelcome.'], ['trees', '# Trees\n\nOaks.'], ['walk', '# Walk\n\nSee [[Field guide]].']);
    writeBookSpot('book', { kind: 'chapter', title: 'Trees' });
    await openApp();
    act(() => card('Field guide').click());
    expect(noteShown()).toBe('trees');
    act(() => button('Home').click());
    act(() => card('Walk').click());
    await act(async () => seen.note!.onOpenTitle!('Field guide'));
    expect(noteShown()).toBe('trees');
    // Opened as itself, from its own tab, the book is its index: the way back to it from a chapter.
    await act(async () => seen.note!.onOpenWithin!('Field guide'));
    expect(noteShown()).toBe('book');
    act(() => button('Home').click());
    act(() => button('Field guide').click());
    expect(noteShown()).toBe('book');
    // The notes drawer is outside the book too.
    act(() => button('Home').click());
    act(() => button('All your notes').click());
    const row = [...document.querySelectorAll<HTMLButtonElement>('[role="dialog"] li button')].find((b) => b.textContent?.includes('Field guide'));
    act(() => row!.click());
    expect(noteShown()).toBe('trees');
  });
});

describe('the arrows', () => {
  it('walk back and forward through where he has been, without the walk itself counting as somewhere new', async () => {
    await seed(['a', '# Apples'], ['b', '# Bread']);
    await openApp();
    const back = () => button('Back to where you were');
    const on = () => button('Forward again');
    expect(back().disabled).toBe(true);
    act(() => card('Apples').click());
    act(() => button('Home').click());
    act(() => card('Bread').click());
    act(() => back().click());
    expect(screenNow()).toBeNull();
    act(() => back().click());
    expect(noteShown()).toBe('a');
    expect(back().disabled).toBe(false);
    act(() => on().click());
    act(() => on().click());
    expect(noteShown()).toBe('b');
    expect(on().disabled).toBe(true);
  });
});

describe('the arrows, after a step that lands where they already are', () => {
  it('still record the next note opened', async () => {
    await seed(['a', '# Apples'], ['b', '# Bread']);
    await openApp();
    act(() => card('Apples').click());
    // Deleted from the editor: home again, with a place on the trail that is no longer there.
    act(() => seen.note!.onDelete!('a'));
    // Back steps over the deleted note to home, which is where the page already is.
    act(() => button('Back to where you were').click());
    act(() => card('Bread').click());
    expect(button('Back to where you were').disabled).toBe(false);
    act(() => button('Back to where you were').click());
    expect(noteShown()).toBeNull();
  });
});

describe('a note deleted from the editor', () => {
  it('leaves its tab and the home page at once, and comes back with Undo', async () => {
    await seed(['a', '# Apples'], ['b', '# Bread']);
    await openApp();
    act(() => card('Apples').click());
    act(() => seen.note!.onDelete!('a'));
    expect(noteShown()).toBeNull();
    expect(tabs()).toEqual([]);
    expect(() => card('Apples')).toThrow();
    expect(card('Bread')).toBeTruthy();
    act(() => button('Undo').click());
    expect(card('Apples')).toBeTruthy();
  });
});

describe('the side key', () => {
  it('starts a capture over whatever is open, and during one asks it to stop', async () => {
    await seed(['a', '# Apples']);
    await openApp();
    act(() => card('Apples').click());
    await act(async () => window.__glyph!.capture!());
    expect(screenNow()?.dataset.screen).toBe('capture');
    expect(screenNow()?.dataset.fromAssistant).toBe('true');
    expect(screenNow()?.dataset.stop).toBe('0');
    // The tab row is not over a capture, and nor is its height.
    expect(document.querySelector('[role="tablist"]')).toBeNull();
    expect(root.dataset.tabs).toBeUndefined();
    await act(async () => window.__glyph!.capture!());
    expect(screenNow()?.dataset.stop).toBe('1');
  });

  it('on a signed-out first open shows the way into an account first, and the walkthrough after it', async () => {
    localStorage.removeItem('glyph-account-gate-seen');
    localStorage.removeItem('glyph-guide-seen');
    await openApp();
    expect(document.querySelector('[role="dialog"][aria-label="Sign in to Ghost.md"]')).not.toBeNull();
    // The walkthrough waits for it.
    expect(seen.guide).toBeNull();
    await act(async () => button('Use without an account').click());
    expect(document.querySelector('[aria-label="Sign in to Ghost.md"]')).toBeNull();
    expect(seen.guide?.index).toBe(0);
    expect(localStorage.getItem('glyph-account-gate-seen')).toBe('1');
  });

  it('does not ask again once the way in has been passed by', async () => {
    await openApp();
    expect(document.querySelector('[aria-label="Sign in to Ghost.md"]')).toBeNull();
  });

  it('on a reading page of the guide says it is too soon rather than recording', async () => {
    localStorage.removeItem('glyph-guide-seen');
    await openApp();
    expect(seen.guide?.index).toBe(0);
    await act(async () => window.__glyph!.capture!());
    expect(screenNow()?.dataset.screen).not.toBe('capture');
    expect(document.querySelector<HTMLElement>('[data-screen="guide"]')?.dataset.tooSoon).toBe('true');
  });

  it('held on a reading page of the guide before a relaunch, brings the guide back with its line and no recording', async () => {
    localStorage.removeItem('glyph-guide-seen');
    localStorage.setItem('glyph-guide-started', '1');
    localStorage.setItem('glyph-guide-page', '0');
    history.replaceState(null, '', '/?capture');
    show(<App />);
    await waitUntil(() => expect(document.querySelector('[data-screen="guide"]')).not.toBeNull());
    expect(document.querySelector<HTMLElement>('[data-screen="guide"]')?.dataset.tooSoon).toBe('true');
    await act(async () => {
      // Long enough for a capture to have begun, had one been going to.
    });
    expect(screenNow()?.dataset.screen).not.toBe('capture');
  });

  it('opens the app on a capture when it was what launched it', async () => {
    history.replaceState(null, '', '/?capture');
    show(<App />);
    await waitUntil(() => expect(screenNow()?.dataset.screen).toBe('capture'));
    expect(screenNow()?.dataset.fromAssistant).toBe('true');
    // A person who held the key is mid-sentence: the walkthrough waits.
    expect(document.querySelector('[data-screen="guide"]')).toBeNull();
  });
});

describe('a new note, and where it was made', () => {
  it('says what the first location ask is for, asks on the press, and tags a note but never a canvas', async () => {
    const { pendingTag } = await import('./core/location.ts');
    const calls: PositionOptions[] = [];
    Object.defineProperty(navigator, 'geolocation', {
      configurable: true,
      value: {
        getCurrentPosition: (ok: PositionCallback, _fail: PositionErrorCallback, options: PositionOptions) => {
          calls.push(options);
          ok({ coords: { latitude: 51.5074, longitude: -0.1278, accuracy: 15 }, timestamp: 1 } as GeolocationPosition);
        },
      },
    });
    try {
      await openApp();
      act(() => button('Write a note').click());
      await act(async () => buttonSaying(document.body, 'A page of markdown')!.click());
      await waitUntil(() => expect(noteShown()).not.toBeNull());
      const made = noteShown()!;
      // Never answered on this device: the app's own words first, and nothing asked of the device until the press.
      await waitUntil(() => expect(document.body.textContent).toContain('New notes can keep where they were written.'));
      expect(calls).toHaveLength(0);
      await act(async () => buttonSaying(document.body, 'Allow location')!.click());
      await waitUntil(() => expect(pendingTag(made)).toMatchObject({ lat: 51.5074, lon: -0.1278 }));
      expect(calls).toHaveLength(1);
      // A canvas is the app's page, not a note the person wrote: not tagged, and nothing asked.
      act(() => button('Home').click());
      act(() => button('Write a note').click());
      await act(async () => buttonSaying(document.body, 'Cards on a page')!.click());
      await waitUntil(() => expect(noteShown()).not.toBe(made));
      await act(async () => {
        await Promise.resolve();
      });
      expect(calls).toHaveLength(1);
      expect(pendingTag(noteShown()!)).toBeNull();
    } finally {
      Reflect.deleteProperty(navigator, 'geolocation');
    }
  });
});

describe('a new note, ready to type', () => {
  it('opens with the caret in line 1, fresh, with no record written, and holds its map box where a fix is expected', async () => {
    const { isFresh } = await import('./core/untouched.ts');
    const { heldFor } = await import('./core/location.ts');
    Object.defineProperty(navigator, 'geolocation', { configurable: true, value: { getCurrentPosition: () => undefined } });
    Object.defineProperty(navigator, 'permissions', { configurable: true, value: { query: async () => ({ state: 'granted' }) } });
    try {
      await openApp();
      act(() => button('Write a note').click());
      await act(async () => buttonSaying(document.body, 'A page of markdown')!.click());
      await waitUntil(() => expect(noteShown()).not.toBeNull());
      const made = noteShown()!;
      expect(seen.note!.caret).toBe(0);
      expect(isFresh(made)).toBe(true);
      expect(localStorage.getItem('glyph-entry-drafts')).toBeNull();
      // Allowed already, so the fix is on its way from the first frame, and the box is held for it.
      expect(heldFor(made)).toBe('waiting');
    } finally {
      Reflect.deleteProperty(navigator, 'geolocation');
      Reflect.deleteProperty(navigator, 'permissions');
    }
  });

  it('takes back a note given a template or a name and left without a word, and keeps one written in', async () => {
    const { rememberUntouched, untouchedRecord } = await import('./core/untouched.ts');
    const { setPendingTag, pendingTag } = await import('./core/location.ts');
    await seed(['a', '# Apples']);
    await openApp();
    const made = async () => {
      act(() => button('Write a note').click());
      await act(async () => buttonSaying(document.body, 'A page of markdown')!.click());
      await waitUntil(() => expect(noteShown()).not.toBeNull());
      return noteShown()!;
    };
    // As the note's screen writes a card's template: its record first, then its words, and a place waiting for words.
    const left = await made();
    rememberUntouched(left, { title: '', words: '# \n\n- [ ] ', at: Date.now() });
    await updateNote(left, '---\nlook: reading\n---\n# \n\n- [ ] ', (await getNote(left))!.revision ?? 1);
    setPendingTag(left, { lat: 51.5, lon: -0.12, rough: false, place: null });
    act(() => button('Home').click());
    await waitUntil(async () => expect(await getNote(left)).toBeNull());
    expect(untouchedRecord(left)).toBeNull();
    expect(pendingTag(left)).toBeNull();
    expect(tabs()).not.toContain(left);
    // Left before its screen's save of the words has landed: the store has none yet, so the record waits for a look
    // that finds them, and the note is taken back then.
    const early = await made();
    rememberUntouched(early, { title: '2026-09-28', words: '# 2026-09-28\n\n', at: Date.now() });
    act(() => button('Home').click());
    await act(async () => {
      await Promise.resolve();
    });
    expect(untouchedRecord(early)).not.toBeNull();
    await updateNote(early, '# 2026-09-28\n\n', (await getNote(early))!.revision ?? 1);
    // The next look: another note, and home again (behind another note its open tab would keep it).
    act(() => card('Apples').click());
    await waitUntil(() => expect(noteShown()).toBe('a'));
    act(() => button('Home').click());
    await waitUntil(async () => expect(await getNote(early)).toBeNull());
    // Written in, it is the person's: it stays, and its record goes.
    const kept = await made();
    rememberUntouched(kept, { title: '2026-09-28', words: '# 2026-09-28\n\n', at: Date.now() });
    await updateNote(kept, '# 2026-09-28\n\nA word.', (await getNote(kept))!.revision ?? 1);
    act(() => button('Home').click());
    await waitUntil(() => expect(untouchedRecord(kept)).toBeNull());
    expect(await getNote(kept)).not.toBeNull();
  });

  it('makes your Templates notebook from Your templates, pages first, opens it, and offers its pages on a blank page', async () => {
    const { isTemplatesBody } = await import('./notes/ownTemplates.ts');
    await openApp();
    const blank = async () => {
      if (noteShown()) act(() => button('Home').click());
      act(() => button('Write a note').click());
      await act(async () => buttonSaying(document.body, 'A page of markdown')!.click());
      await waitUntil(() => expect(seen.note?.note.body).toBe(''));
    };
    await blank();
    expect(seen.note!.templates).toBeNull();
    const left = seen.note!.note.id;
    const made = vi.mocked(createNote).mock.calls.length;
    await act(async () => seen.note!.onTemplates!());
    await waitUntil(() => expect(isTemplatesBody(seen.note!.note.body)).toBe(true));
    // In the blank note's tab: a note left with no words leaves nothing, its tab included.
    expect(tabs()).not.toContain(left);
    const bodies = vi.mocked(createNote).mock.calls.slice(made).map((call) => call[1]);
    // The eight pages, the last first so a list read newest first reads them in order, then the notebook.
    expect(bodies).toHaveLength(9);
    expect(bodies[0]).toContain('title: "Feature"');
    expect(bodies[7]).toContain('title: "A day"');
    expect(isTemplatesBody(bodies[8]!)).toBe(true);
    const book = seen.note!.note.id;
    // From then on a blank page's cards are its pages, and a second press opens the same notebook.
    await blank();
    expect(seen.note!.templates?.map((one) => one.name)).toEqual(['A day', 'A meeting', 'A checklist', 'Notes on a book', 'A map at the top', 'A page to read', 'Bug report', 'Feature']);
    await act(async () => seen.note!.onTemplates!());
    await waitUntil(() => expect(seen.note!.note.id).toBe(book));
    expect(vi.mocked(createNote).mock.calls.length).toBe(made + 10);
    // A page added from inside it is a template's page, marked and named by its title.
    await act(async () => seen.note!.onOpenWithin!('A walk'));
    await waitUntil(() => expect(seen.note!.note.body).toBe('---\ntitle: "A walk"\ntemplates: page\n---\n# {{title}}\n\n'));
  });

  it('never takes a note of the person’s named like a page for the page, from the seed or inside the notebook', async () => {
    const { isTemplatesBody } = await import('./notes/ownTemplates.ts');
    await seed(['mine', '# Notes on a book\n\n- [ ] Return Middlemarch to the library']);
    // The List layout, whose rows say how each note starts: the person's note is known from the page by its words.
    setPreferences({ homeLayout: 'list' });
    await openApp();
    expect(document.body.textContent).toContain('Return Middlemarch to the library');
    act(() => button('Write a note').click());
    await act(async () => buttonSaying(document.body, 'A page of markdown')!.click());
    await waitUntil(() => expect(seen.note?.note.body).toBe(''));
    const made = vi.mocked(createNote).mock.calls.length;
    await act(async () => seen.note!.onTemplates!());
    await waitUntil(() => expect(isTemplatesBody(seen.note!.note.body)).toBe(true));
    // All eight pages, the one sharing the person's note's name too.
    expect(vi.mocked(createNote).mock.calls.slice(made).map((call) => call[1]).filter((body) => body.includes('title: "Notes on a book"'))).toHaveLength(1);
    expect(vi.mocked(createNote).mock.calls.length).toBe(made + 9);
    // Inside the notebook its line is the page. Everywhere else the name is the person's note, still on home.
    await act(async () => seen.note!.onOpenWithin!('Notes on a book'));
    await waitUntil(() => expect(seen.note!.note.body).toContain('templates: page'));
    const page = seen.note!.note.id;
    expect(page).not.toBe('mine');
    await act(async () => seen.note!.onOpenTitle!('Notes on a book'));
    await waitUntil(() => expect(noteShown()).toBe('mine'));
    // Its place in a book is none: the Templates notebook's lines are its pages.
    expect(seen.note!.book ?? null).toBeNull();
    act(() => button('Home').click());
    await waitUntil(() => expect(document.body.textContent).toContain('Return Middlemarch to the library'));
    expect(seen.note!.templates?.find((one) => one.name === 'Notes on a book')?.id).toBe(page);
  });

  it('makes the notebook once for Your templates pressed twice at once, and keeps its pages out of a notebook’s pickers', async () => {
    await seed(['a', '# Apples']);
    await openApp();
    act(() => button('Write a note').click());
    await act(async () => buttonSaying(document.body, 'A page of markdown')!.click());
    await waitUntil(() => expect(seen.note?.note.body).toBe(''));
    const made = vi.mocked(createNote).mock.calls.length;
    const press = seen.note!.onTemplates!;
    await act(async () => {
      press();
      press();
    });
    await waitUntil(() => expect(vi.mocked(createNote).mock.calls.length).toBe(made + 9));
    await act(async () => {
      await Promise.resolve();
    });
    expect(vi.mocked(createNote).mock.calls.length).toBe(made + 9);
    // A notebook's page pickers offer the person's notes, not the templates.
    const offered = seen.note!.pageTitles!();
    expect(offered).toContain('Apples');
    expect(offered).not.toContain('A day');
  });

  it('offers a named note’s own name again after an undo, though the list was read again meanwhile', async () => {
    const { titleKey } = await import('./core/titleKey.ts');
    const { announceNotesChanged } = await import('./core/store.ts');
    const { trashNote } = await import('./core/trash.ts');
    await seed(['a', '# Apples'], ['old', '# Old plans'], ['binned', '# Binned list']);
    await setNoteArchived('old', true);
    trashNote('binned');
    await openApp();
    act(() => button('Write a note').click());
    await act(async () => buttonSaying(document.body, 'A page of markdown')!.click());
    await waitUntil(() => expect(seen.note?.note.body).toBe(''));
    const id = seen.note!.note.id;
    // Every other note's name is taken, archived and in the Trash too.
    for (const name of ['Apples', 'Old plans', 'Binned list']) expect(seen.note!.takenTitles?.has(titleKey(name))).toBe(true);
    // Named on its blank page, saved, and the list read again: the name is its own, not taken from it.
    await updateNote(id, '# Zebra crossing\n\n', (await getNote(id))!.revision ?? 1);
    await act(async () => announceNotesChanged());
    await waitUntil(() => expect(seen.note!.takenTitles?.has(titleKey('Apples'))).toBe(true));
    await act(async () => {
      await Promise.resolve();
    });
    expect(seen.note!.takenTitles?.has(titleKey('Zebra crossing'))).toBe(false);
  });

  it('speaks into a note given a template as into any note, not from its last line', async () => {
    const { rememberUntouched } = await import('./core/untouched.ts');
    await openApp();
    act(() => button('Write a note').click());
    await act(async () => buttonSaying(document.body, 'A page of markdown')!.click());
    await waitUntil(() => expect(seen.note?.note.body).toBe(''));
    const id = seen.note!.note.id;
    // As a card's press writes A meeting: its record first, then its words.
    const words = '# Meeting 2026-09-28 14.05\n\nWith \n\n## Notes\n\n- \n\n## To do\n\n- [ ] ';
    rememberUntouched(id, { title: 'Meeting 2026-09-28 14.05', words, at: Date.now() });
    await updateNote(id, words, (await getNote(id))!.revision ?? 1);
    await act(async () => seen.note!.onSpeak!(id));
    await waitUntil(() => expect(screenNow()?.dataset.screen).toBe('capture'));
    expect(screenNow()!.dataset.into).toBe(id);
    // Nothing taken off its end to be said as to-dos under To do.
    expect(seen.capture!.placing).toBeUndefined();
    expect((await getNote(id))!.body).toBe(words);
  });

  it('makes one from ⌘N in the Mac app, never in a browser, and not while a sheet is over the page', async () => {
    const press = () => act(() => void window.dispatchEvent(new KeyboardEvent('keydown', { key: 'n', metaKey: true, bubbles: true, cancelable: true })));
    await seed(['a', '# Apples']);
    await openApp();
    press();
    await act(async () => {
      await Promise.resolve();
    });
    expect(noteShown()).toBeNull();
    unmount();
    device.mac = true;
    try {
      await openApp();
      // The + sheet open: its own keys come first.
      act(() => button('Write a note').click());
      press();
      await act(async () => {
        await Promise.resolve();
      });
      expect(noteShown()).toBeNull();
      const { goBack } = await import('./core/back.ts');
      act(() => void goBack());
      await waitUntil(() => expect(document.querySelector('[aria-modal="true"]')).toBeNull());
      press();
      await waitUntil(() => expect(noteShown()).not.toBeNull());
      expect(seen.note!.caret).toBe(0);
      expect(seen.note!.note.body).toBe('');
    } finally {
      device.mac = false;
    }
  });

  it('takes only ⌘N itself, held once, and its own default, and never over a recording', async () => {
    device.mac = true;
    try {
      await seed(['a', '# Apples']);
      await openApp();
      const made = () => vi.mocked(createNote).mock.calls.length;
      const before = made();
      const key = (init: KeyboardEventInit) => {
        const event = new KeyboardEvent('keydown', { key: 'n', bubbles: true, cancelable: true, ...init });
        act(() => void window.dispatchEvent(event));
        return event;
      };
      for (const other of [{ metaKey: true, ctrlKey: true }, { metaKey: true, altKey: true }, { metaKey: true, shiftKey: true, key: 'N' }, { metaKey: true, repeat: true }, { ctrlKey: true }]) {
        expect(key(other).defaultPrevented).toBe(false);
      }
      await act(async () => {
        await Promise.resolve();
      });
      expect(made()).toBe(before);
      expect(noteShown()).toBeNull();
      // Over a recording, which is not a place: nothing made, and the recorder stays.
      await act(async () => window.__glyph!.capture!());
      expect(screenNow()?.dataset.screen).toBe('capture');
      key({ metaKey: true });
      await act(async () => {
        await Promise.resolve();
      });
      expect(made()).toBe(before);
      expect(screenNow()?.dataset.screen).toBe('capture');
      await act(async () => seen.capture!.onFinish(null, false));
      await waitUntil(() => expect(screenNow()?.dataset.screen).not.toBe('capture'));
      expect(key({ metaKey: true }).defaultPrevented).toBe(true);
      await waitUntil(() => expect(noteShown()).not.toBeNull());
    } finally {
      device.mac = false;
    }
  });

  it('forgets the name a closed tab’s editor gave it, so the note opened again says its own', async () => {
    const { setLiveTitle } = await import('./core/liveTitles.ts');
    await seed(['a', '# Apples'], ['b', '# Bread']);
    await openApp();
    act(() => card('Apples').click());
    await waitUntil(() => expect(noteShown()).toBe('a'));
    act(() => setLiveTitle('a', 'Apples and pears'));
    await waitUntil(() => expect(button('Close Apples and pears')).not.toBeNull());
    act(() => button('Close Apples and pears').click());
    await waitUntil(() => expect(tabs()).not.toContain('a'));
    act(() => card('Apples').click());
    await waitUntil(() => expect(noteShown()).toBe('a'));
    expect(document.querySelector('[aria-label="Close Apples"]')).not.toBeNull();
  });

  it('holds nothing where the prompt was never answered, and leaves a note opened to be read unfocused', async () => {
    const { heldFor } = await import('./core/location.ts');
    await seed(['a', '# Apples']);
    await openApp();
    act(() => button('Write a note').click());
    await act(async () => buttonSaying(document.body, 'A page of markdown')!.click());
    await waitUntil(() => expect(noteShown()).not.toBeNull());
    expect(heldFor(noteShown()!)).toBeNull();
    act(() => button('Home').click());
    act(() => card('Apples').click());
    await waitUntil(() => expect(noteShown()).toBe('a'));
    expect(seen.note!.caret).toBeUndefined();
  });
});

describe('a capture ending', () => {
  it('comes back to the note it was spoken into, read fresh', async () => {
    await seed(['a', '# Apples']);
    await openApp();
    act(() => card('Apples').click());
    await act(async () => seen.note!.onSpeak!('a'));
    expect(screenNow()?.dataset.into).toBe('a');
    const note = (await getNote('a'))!;
    // The words spoken were written into the note while the recorder was up.
    const { updateNote } = await import('./core/store.ts');
    await updateNote('a', '# Apples\n\nAnd pears.', note.revision ?? 1);
    await act(async () => seen.capture!.onFinish((await getNote('a')) as Note, false));
    expect(noteShown()).toBe('a');
    expect(document.querySelector<HTMLElement>('[data-screen="note"]')?.dataset.body).toBe('# Apples\n\nAnd pears.');
  });

  it('from home comes back home, the new note on it', async () => {
    await openApp();
    act(() => button('Speak a voice note').click());
    await waitUntil(() => expect(screenNow()?.dataset.screen).toBe('capture'));
    expect(screenNow()?.dataset.fromAssistant).toBe('false');
    const made = await createNote('spoken', '# Said aloud', 'capture');
    await act(async () => seen.capture!.onFinish(made, false));
    expect(screenNow()).toBeNull();
    await waitUntil(() => expect(card('Said aloud')).toBeTruthy());
  });
});

/** Organizations and notifications (docs/TEAMS.md): the drawer, an organization's dashboard and its settings, where each opens from and comes back to. */
describe('the bell, and an organization’s screen', () => {
  it('opens the notifications drawer from the bell over the page that is up, which stays, and the bell closes it again', async () => {
    await seed(['a', '# Apples']);
    await openApp();
    const drawer = () => document.querySelector('[data-drawer="notifications"]');
    expect(button('Notifications').hasAttribute('data-unread')).toBe(false);
    act(() => button('Notifications').click());
    expect(drawer()).not.toBeNull();
    expect(button('Notifications').getAttribute('aria-expanded')).toBe('true');
    // A drawer, not a page: the home page is still the screen under it.
    expect(document.querySelector('nav[aria-label="New note"]')).not.toBeNull();
    expect(root.dataset.tabs).toBe('on');
    act(() => button('Notifications').click());
    expect(drawer()).toBeNull();
    expect(button('Notifications').getAttribute('aria-expanded')).toBe('false');
    act(() => button('Notifications').click());
    act(() => seen.notifications!.onClose());
    expect(drawer()).toBeNull();
    // A note a row named opens at the line the edit landed on.
    act(() => button('Notifications').click());
    act(() => seen.notifications!.onOpenNote('a', 'line:3'));
    expect(noteShown()).toBe('a');
    expect(document.querySelector('[data-screen="note"]')?.getAttribute('data-at')).toBe('line:3');
  });

  // Matt: "don't show notifications on mobile while on the viewing of a note also don't show the organization on the
  // page when viewing notes either".
  it('takes the bell and the people icon off the bar on a phone while a note is read, and puts them back at home', async () => {
    device.mobile = true;
    try {
      await seed(['a', '# Apples']);
      await openApp();
      expect(button('Notifications')).toBeTruthy();
      expect(button('Organizations')).toBeTruthy();
      act(() => button('Notifications').click());
      act(() => seen.notifications!.onOpenNote('a'));
      expect(noteShown()).toBe('a');
      expect(() => button('Notifications')).toThrow();
      expect(() => button('Organizations')).toThrow();
      act(() => seen.note!.onBack());
      expect(noteShown()).toBeNull();
      expect(button('Notifications')).toBeTruthy();
      expect(button('Organizations')).toBeTruthy();
    } finally {
      device.mobile = false;
    }
  });

  it('opens an organization from Settings with the sheet closed first, and closing it reopens Settings on Organizations', async () => {
    await openApp();
    act(() => button('Settings').click());
    expect(document.querySelector('[data-screen="settings"]')).not.toBeNull();
    act(() => seen.settings!.onOrganization!('org-1'));
    expect(document.querySelector('[data-screen="settings"]')).toBeNull();
    expect(screenNow()?.dataset.screen).toBe('organization');
    expect(screenNow()?.dataset.org).toBe('org-1');
    expect(screenNow()?.dataset.from).toBe('settings');
    // The home page waits under it.
    expect(document.querySelector('nav[aria-label="New note"]')).not.toBeNull();
    act(() => seen.organization!.onClose());
    expect(document.querySelector('[data-screen="organization"]')).toBeNull();
    expect(document.querySelector('[data-screen="settings"]')?.getAttribute('data-to-page')).toBe('organizations');
  });

  // Matt: "when clicking an organization in the header don't take me to the settings, instead, take me to this
  // dashboard page and have a organization settings icon on that".
  it('opens an organization’s dashboard from a notification row, its cog the settings over it, and its arrow home', async () => {
    await openApp();
    act(() => button('Notifications').click());
    act(() => seen.notifications!.onOpenOrganization('org-2'));
    expect(screenNow()?.dataset.screen).toBe('dashboard');
    expect(screenNow()?.dataset.org).toBe('org-2');
    // A place, as All notes is: the tab row stays.
    expect(root.dataset.tabs).toBe('on');
    expect(document.querySelector('[data-screen="organization"]')).toBeNull();
    // The cog: the organization's settings over the dashboard, opened on their list, and closing finds it again.
    act(() => seen.dashboard!.onSettings());
    expect(document.querySelector('[data-screen="organization"]')?.getAttribute('data-org')).toBe('org-2');
    expect(seen.organization!.landOnMembers).toBe(false);
    expect(seen.organization!.from).toBe('dashboard');
    act(() => seen.organization!.onClose());
    expect(document.querySelector('[data-screen="organization"]')).toBeNull();
    expect(screenNow()?.dataset.screen).toBe('dashboard');
    act(() => seen.dashboard!.onBack());
    expect(document.querySelector('nav[aria-label="New note"]')).not.toBeNull();
  });

  // Matt: "an "audit log" for organizations to be able to browse history of changes across all files".
  it('opens an organization’s audit log from its dashboard, in the same pane, whose arrow is the dashboard again and whose changes open notes', async () => {
    await seed(['a', '# Apples']);
    await openApp();
    act(() => button('Notifications').click());
    act(() => seen.notifications!.onOpenOrganization('org-2'));
    act(() => seen.dashboard!.onLog());
    expect(screenNow()?.dataset.screen).toBe('audit');
    expect(screenNow()?.dataset.org).toBe('org-2');
    // A place still, as the dashboard is: the tab row stays.
    expect(root.dataset.tabs).toBe('on');
    act(() => seen.log!.onBack());
    expect(screenNow()?.dataset.screen).toBe('dashboard');
    expect(screenNow()?.dataset.org).toBe('org-2');
    act(() => seen.dashboard!.onLog());
    act(() => seen.log!.onOpenNote('a'));
    expect(noteShown()).toBe('a');
  });

  it('moves from one organization’s dashboard to another’s by its pill, the settings following the one on screen', async () => {
    await openApp();
    act(() => button('Notifications').click());
    act(() => seen.notifications!.onOpenOrganization('org-2'));
    act(() => seen.dashboard!.onOpenOrganization('org-3'));
    expect(screenNow()?.dataset.screen).toBe('dashboard');
    expect(screenNow()?.dataset.org).toBe('org-3');
    act(() => seen.dashboard!.onSettings());
    expect(document.querySelector('[data-screen="organization"]')?.getAttribute('data-org')).toBe('org-3');
    // From Settings › Organizations the settings open on Members, and closing goes back there.
    act(() => seen.organization!.onClose());
    act(() => seen.dashboard!.onBack());
    act(() => button('Settings').click());
    act(() => seen.settings!.onOrganization!('org-3'));
    expect(seen.organization!.landOnMembers).toBe(true);
  });

  it('offers both from the palette: Notifications as the drawer, Organizations as Settings on that page', async () => {
    await seed(['a', '# Apples']);
    await openApp();
    const run = (words: string) => {
      act(() => button('Search and commands').click());
      const command = [...document.querySelectorAll<HTMLElement>('[role="option"]')].find((option) => option.textContent?.trim() === words);
      act(() => void command!.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true })));
    };
    run('Organizations');
    expect(document.querySelector('[data-screen="settings"]')?.getAttribute('data-to-page')).toBe('organizations');
    act(() => seen.settings!.onClose());
    run('Notifications');
    expect(document.querySelector('[data-drawer="notifications"]')).not.toBeNull();
  });
});

describe('a shared link in the address', () => {
  it('is saved as a copy once the notes are read, opened, and taken out of the address', async () => {
    history.replaceState(null, '', `/#fork=https://attack.fm/glyph/read.html#${'a'.repeat(22)}.${'b'.repeat(43)}`);
    show(<App />);
    await waitUntil(() => expect(noteShown()).toBe('forked'));
    expect(location.hash).toBe('');
    const { forkShared } = await import('./share/share.ts');
    expect(forkShared).toHaveBeenCalledTimes(1);
  });
});

describe('the notes Settings › About adds', () => {
  it('says so when the guide does not load, and leaves the person where they were', async () => {
    await seed(['a', '# Apples']);
    await openApp();
    // Offline, or the chunks replaced by a deploy under an open tab.
    vi.mocked(addGuideBook).mockRejectedValueOnce(new TypeError('Failed to fetch dynamically imported module'));
    act(() => seen.settings!.onGuideBook());
    await waitUntil(() => expect(document.body.textContent).toContain('Ghost.md: The Guide did not load. Try again.'));
    expect(screenNow()).toBeNull();
    expect(tabs()).toEqual([]);
  });

  it('syncs before it looks for the book, so one added on another device is opened rather than made again', async () => {
    await openApp();
    vi.mocked(syncNow).mockClear();
    vi.mocked(addGuideBook).mockClear();
    vi.mocked(addGuideBook).mockResolvedValueOnce(await createNote('guide', '---\ntitle: "Ghost.md: The Guide"\nbook: true\n---\n# Ghost.md: The Guide\n'));
    act(() => seen.settings!.onGuideBook());
    await waitUntil(() => expect(noteShown()).toBe('guide'));
    expect(vi.mocked(syncNow).mock.invocationCallOrder[0]).toBeLessThan(vi.mocked(addGuideBook).mock.invocationCallOrder[0]!);
  });
});

describe('a notebook’s new page', () => {
  it('is made from the template picked under its title, in the notebook’s tab, and its line finds it', async () => {
    await seed(['book', bookNoteBody('Field guide', ['Introduction'])], ['intro', '# Introduction\n\nWelcome.']);
    await openApp();
    act(() => card('Field guide').click());
    expect(noteShown()).toBe('book');
    // The notebook's Add a page, with A morning page picked under the title (book/BookView.tsx `PageStarts`), and
    // its line put in the index as the form does.
    const book = (await getNote('book'))!;
    await updateNote('book', `${book.body}- [[Monday]]\n`, book.revision ?? 1);
    await act(async () => seen.note!.onNewPage!('Monday', PRESETS[2]!.text));
    await waitUntil(() => expect(noteShown()).not.toBe('book'));
    const page = (await getNote(noteShown()!))!;
    expect(page.body.startsWith('# Monday\n\n## ')).toBe(true);
    expect(page.body).toContain('> What is on your mind this morning?');
    expect(noteShown()).not.toBeNull();
    // In the notebook's tab, which the page takes, as a page opened from the index does.
    expect(tabs()).toEqual([noteShown()]);
  });
});

describe('a notebook’s tickets (docs/DESIGN.md §157)', () => {
  const NOTEBOOK = '---\ntitle: "Ghost.md"\nbook: true\nkey: GHO\nstatuses: [Ideas, Building, Live]\n---\n# Ghost.md\n\n- [[Fix the login loop]]\n';
  const LOOP = '---\ntype: ticket\nid: GHO-12\nstatus: Building\n---\n# Fix the login loop\n';

  it('makes a New ticket with the notebook’s next key, its first open status and the template picked', async () => {
    const { BUILT_INS } = await import('./notes/noteTemplates.ts');
    // A number named only in the Trash is not given again.
    const { trashNote } = await import('./core/trash.ts');
    await seed(['book', NOTEBOOK], ['loop', LOOP], ['old', '# Old\n\nWas GHO-20.']);
    trashNote('old');
    await openApp();
    act(() => card('Ghost.md').click());
    expect(seen.note!.ticketTemplates?.map((one) => one.name)).toEqual(['Bug report', 'Feature']);
    await act(async () => seen.note!.onNewTicket!('Session cookie expires', NOTEBOOK, BUILT_INS.find((one) => one.kind === 'bug')!));
    await waitUntil(() => expect(noteShown()).not.toBe('book'));
    const made = (await getNote(noteShown()!))!;
    expect(made.body).toBe('---\ntype: ticket\nid: GHO-21\nstatus: Ideas\n---\n# Session cookie expires\n\n## Steps to reproduce\n\n1. \n\n## Expected\n\n## Actual\n');
    expect(tabs()).toEqual([noteShown()]);
  });

  it('opens [[GHO-12]] as the ticket with that key, and draws its panel from the library', async () => {
    await seed(['book', NOTEBOOK], ['loop', LOOP], ['words', '# Standup\n\nSee [[GHO-12]].']);
    await openApp();
    act(() => card('Standup').click());
    expect(seen.note!.hasTitle!('GHO-12')).toBe(true);
    expect(seen.note!.hasTitle!('GHO-99')).toBe(false);
    expect(seen.note!.tickets?.find('gho-12')).toEqual({ key: 'GHO-12', title: 'Fix the login loop', status: 'Building', category: 'doing' });
    await act(async () => seen.note!.onOpenTitle!('GHO-12'));
    expect(noteShown()).toBe('loop');
    // The ticket's own workflow is its notebook's, and it is no choice of its own.
    expect(seen.note!.tickets?.statuses()).toEqual(['Ideas', 'Building', 'Live']);
    expect(seen.note!.tickets?.choices().map((choice) => choice.key)).toEqual([]);
  });
});

describe('a journal’s entries', () => {
  const DIARY = '---\ntitle: "Diary"\nbook: true\njournal: true\ntemplate: "# {{date}}\\n\\n**{{time}}** "\n---\n# Diary\n\n';
  const records = () => JSON.parse(localStorage.getItem('glyph-entry-drafts') ?? '{}') as Record<string, { title: string; journalId: string }>;
  /** Opens the journal from its card and makes an entry from its view; answers the entry's id and title. */
  const newEntry = async () => {
    await act(async () => seen.note!.onNewEntry!());
    await waitUntil(() => expect(noteShown()).not.toBe('diary'));
    const id = noteShown()!;
    return { id, title: records()[id]!.title };
  };
  const diaryBody = async () => (await getNote('diary'))!.body;

  it('makes an entry named by the minute from the template, its line last in the journal, and opens it with the caret at the end', async () => {
    await seed(['diary', DIARY]);
    await openApp();
    act(() => card('Diary').click());
    expect(noteShown()).toBe('diary');
    const { id, title } = await newEntry();
    expect(title).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}\.\d{2}$/);
    expect(records()[id]).toMatchObject({ journalId: 'diary', title });
    expect(await diaryBody()).toBe(`${DIARY}- [[${title}]]\n`);
    const body = (await getNote(id))!.body;
    expect(body).toMatch(new RegExp(`^---\\ntitle: "${title}"\\ndate: \\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}\\n---\\n# \\w+.*\\n\\n\\*\\*\\d{2}:\\d{2}\\*\\* $`));
    expect(seen.note!.caret).toBe('end');
    // In the journal's tab: made from inside it.
    expect(tabs()).toEqual([id]);
    // The journal keeps no places: nothing is asked for this entry.
    expect(tagEntryIfWanted).not.toHaveBeenCalled();
  });

  it('puts one line in for each entry made from inside the journal, a second in one minute named with (2)', async () => {
    const { updateNote } = await import('./core/store.ts');
    await seed(['diary', DIARY]);
    await openApp();
    act(() => card('Diary').click());
    const first = await newEntry();
    const made = (await getNote(first.id))!;
    await updateNote(first.id, `${made.body}Morning.`, made.revision ?? 1);
    // Back to the journal in the entry's tab, as its bar does, and another.
    await act(async () => seen.note!.onOpenWithin!('Diary'));
    await waitUntil(() => expect(noteShown()).toBe('diary'));
    const second = await newEntry();
    expect(second.title).not.toBe(first.title);
    if (second.title.startsWith(first.title)) expect(second.title).toBe(`${first.title} (2)`);
    expect(await diaryBody()).toBe(`${DIARY}- [[${first.title}]]\n- [[${second.title}]]\n`);
  });

  it('takes an entry nobody wrote in back when it is left for home: the note and its line, with no word said', async () => {
    await seed(['diary', DIARY]);
    await openApp();
    act(() => card('Diary').click());
    const { id } = await newEntry();
    act(() => button('Home').click());
    await waitUntil(async () => expect(await getNote(id)).toBeNull());
    await waitUntil(async () => expect(await diaryBody()).toBe(DIARY));
    expect(records()[id]).toBeUndefined();
    expect(tabs()).toEqual([]);
    expect(document.body.textContent).not.toContain('Moved');
  });

  it('keeps an entry written in, and forgets its record', async () => {
    const { updateNote } = await import('./core/store.ts');
    await seed(['diary', DIARY]);
    await openApp();
    act(() => card('Diary').click());
    const { id, title } = await newEntry();
    const made = (await getNote(id))!;
    await updateNote(id, `${made.body}Walked along the river.`, made.revision ?? 1);
    act(() => button('Home').click());
    await waitUntil(() => expect(records()[id]).toBeUndefined());
    expect((await getNote(id))?.body).toContain('Walked along the river.');
    expect(await diaryBody()).toContain(`[[${title}]]`);
  });

  it('keeps an untouched entry while its tab is open behind another note, and takes it back once the tab is closed', async () => {
    await seed(['diary', DIARY], ['walk', '# Walk']);
    await openApp();
    act(() => card('Walk').click());
    act(() => button('Home').click());
    act(() => card('Diary').click());
    const { id, title } = await newEntry();
    expect(tabs()).toEqual(['walk', id]);
    act(() => button('Walk').click());
    await act(async () => {
      await Promise.resolve();
    });
    expect(await getNote(id)).not.toBeNull();
    expect(records()[id]).toBeDefined();
    act(() => button(title).click());
    expect(noteShown()).toBe(id);
    act(() => button(`Close ${title}`).click());
    await waitUntil(async () => expect(await getNote(id)).toBeNull());
    await waitUntil(async () => expect(await diaryBody()).toBe(DIARY));
  });

  it('takes back at launch an entry the phone let go of, with its line, before any place lands on it', async () => {
    const { pendingTag, setPendingTag, settleWaitingTags } = await import('./core/location.ts');
    const title = '2026-09-28 14.05';
    const words = '# Monday 28 September\n\n**14:05** ';
    await seed(['diary', `${DIARY}- [[${title}]]\n`], ['left', `---\ntitle: "${title}"\ndate: 2026-09-28T14:05\n---\n${words}`]);
    localStorage.setItem('glyph-entry-drafts', JSON.stringify({ left: { journalId: 'diary', title, words, at: Date.now() } }));
    setPendingTag('left', { lat: 51.5074, lon: -0.1278, place: null, rough: false });
    // The launch sweep may run first: it lands nothing on an entry nobody wrote in.
    expect(await settleWaitingTags()).toBe(0);
    expect((await getNote('left'))?.body).not.toContain('location:');
    await openApp();
    await waitUntil(async () => expect(await getNote('left')).toBeNull());
    await waitUntil(async () => expect(await diaryBody()).toBe(DIARY));
    expect(pendingTag('left')).toBeNull();
  });

  it('leaves an entry moved to the Trash there with its line, for Undo to bring back', async () => {
    await seed(['diary', DIARY]);
    await openApp();
    act(() => card('Diary').click());
    const { id, title } = await newEntry();
    act(() => seen.note!.onDelete(id));
    await waitUntil(() => expect(records()[id]).toBeUndefined());
    expect(await getNote(id)).not.toBeNull();
    expect(await diaryBody()).toContain(`[[${title}]]`);
  });

  it('keeps where an entry was written when the journal says so, whatever Tag new notes says, and never under Local only', async () => {
    const { pendingTag, settleWaitingTags } = await import('./core/location.ts');
    const { updateNote } = await import('./core/store.ts');
    const calls: PositionOptions[] = [];
    Object.defineProperty(navigator, 'geolocation', {
      configurable: true,
      value: {
        getCurrentPosition: (ok: PositionCallback, _fail: PositionErrorCallback, options: PositionOptions) => {
          calls.push(options);
          ok({ coords: { latitude: 51.5074, longitude: -0.1278, accuracy: 15 }, timestamp: 1 } as GeolocationPosition);
        },
      },
    });
    // Answered before on this device: no introduction, the fix at once.
    Object.defineProperty(navigator, 'permissions', { configurable: true, value: { query: async () => ({ state: 'granted' }) } });
    try {
      setPreferences({ tagNewNotes: false, placeNames: false });
      await seed(['diary', DIARY.replace('---\n# Diary', 'entry-place: true\n---\n# Diary')]);
      await openApp();
      act(() => card('Diary').click());
      const { id } = await newEntry();
      // Asked at the tap, with the journal's own introduction for a device never asked before.
      expect(vi.mocked(tagEntryIfWanted).mock.calls[0]).toEqual([[id], { reviewing: false }, { introduce: expect.any(Function) }]);
      await waitUntil(() => expect(pendingTag(id)).toMatchObject({ lat: 51.5074, lon: -0.1278 }));
      // It waits for the entry's first own words, then lands.
      expect((await getNote(id))!.body).not.toContain('location:');
      const made = (await getNote(id))!;
      await updateNote(id, `${made.body}Coffee by the river.`, made.revision ?? 1);
      expect(await settleWaitingTags()).toBe(1);
      expect((await getNote(id))!.body).toContain('location: 51.5074,-0.1278');
      // Under Local only nothing is asked.
      setPreferences({ localOnly: true });
      act(() => button('Home').click());
      act(() => card('Diary').click());
      const second = await newEntry();
      await act(async () => {
        await Promise.resolve();
      });
      expect(pendingTag(second.id)).toBeNull();
      expect(calls).toHaveLength(1);
    } finally {
      Reflect.deleteProperty(navigator, 'geolocation');
      Reflect.deleteProperty(navigator, 'permissions');
    }
  });

  it('speaks an entry from the journal’s mic: made, its line in, the recorder aimed at it from its time line', async () => {
    await seed(['diary', DIARY]);
    await openApp();
    act(() => card('Diary').click());
    await act(async () => seen.note!.onSpeak!('diary'));
    await waitUntil(() => expect(screenNow()?.dataset.screen).toBe('capture'));
    const id = screenNow()!.dataset.into!;
    const { title } = records()[id]!;
    expect(await diaryBody()).toBe(`${DIARY}- [[${title}]]\n`);
    // The line the words go on from is off the entry until they come, and the recorder puts it back before them.
    expect(seen.capture!.placing).toMatchObject({ kind: 'end', lead: expect.stringMatching(/^\*\*\d{2}:\d{2}\*\* $/) });
    const made = (await getNote(id))!;
    expect(made.body).toMatch(/\n---\n# .+\n$/);
    // Words kept: the entry opens, and it is theirs.
    const { updateNote } = await import('./core/store.ts');
    const said = await updateNote(id, `${made.body}\n**14:05** Walked along the river.`, made.revision ?? 1);
    await act(async () => seen.capture!.onFinish(said, false));
    await waitUntil(() => expect(noteShown()).toBe(id));
    act(() => button('Home').click());
    await waitUntil(() => expect(records()[id]).toBeUndefined());
    expect(await getNote(id)).not.toBeNull();
  });

  it('speaks nothing and leaves nothing: back on the journal, the entry and its line taken back', async () => {
    await seed(['diary', DIARY]);
    await openApp();
    act(() => card('Diary').click());
    await act(async () => seen.note!.onSpeak!('diary'));
    await waitUntil(() => expect(screenNow()?.dataset.screen).toBe('capture'));
    const id = screenNow()!.dataset.into!;
    await act(async () => seen.capture!.onFinish(null, false));
    await waitUntil(() => expect(noteShown()).toBe('diary'));
    await waitUntil(async () => expect(await getNote(id)).toBeNull());
    await waitUntil(async () => expect(await diaryBody()).toBe(DIARY));
  });

  it('opens the meeting being recorded rather than making an entry to speak into', async () => {
    const { setMeetingStateForTests } = await import('./capture/meetingLive.ts');
    await seed(['diary', DIARY], ['m1', '# Meeting, 28 Sep 14:05']);
    await openApp();
    act(() => card('Diary').click());
    setMeetingStateForTests({ recording: true, noteId: 'm1', startedAt: Date.now(), writeUps: [] } as unknown as Parameters<typeof setMeetingStateForTests>[0]);
    const before = (await getNote('diary'))!;
    try {
      await act(async () => seen.note!.onSpeak!('diary'));
      await waitUntil(() => expect(document.querySelector('[aria-label="Stop and write up"]')).not.toBeNull());
      expect(noteShown()).toBeNull();
      expect(records()).toEqual({});
      expect(await diaryBody()).toBe(DIARY);
      // Not written and put back: never written at all, so a sync sends nothing and the journal is not newer.
      expect((await getNote('diary'))!.revision).toBe(before.revision);
      expect(createNote).not.toHaveBeenCalledWith(expect.any(String), expect.stringContaining('title: "20'), 'editor');
    } finally {
      setMeetingStateForTests(null);
    }
  });

  it('keeps an untouched entry spoken into from its own mic, aimed at its time line, and puts it back when nothing was said', async () => {
    await seed(['diary', DIARY]);
    await openApp();
    act(() => card('Diary').click());
    const { id } = await newEntry();
    const made = (await getNote(id))!.body;
    await act(async () => seen.note!.onSpeak!(id));
    await waitUntil(() => expect(screenNow()?.dataset.screen).toBe('capture'));
    expect(screenNow()!.dataset.into).toBe(id);
    expect(seen.capture!.placing).toMatchObject({ kind: 'end', lead: expect.stringMatching(/^\*\*\d{2}:\d{2}\*\* $/) });
    // The recorder's screen is aimed at it: the entry stays.
    expect(await getNote(id)).not.toBeNull();
    expect((await getNote(id))!.body).not.toMatch(/\*\* $/);
    await act(async () => seen.capture!.onFinish(null, false));
    await waitUntil(() => expect(noteShown()).toBe(id));
    expect((await getNote(id))!.body).toBe(made);
    expect(records()[id]).toBeDefined();
  });

  it('makes an entry from home through the +, in the journal written in last, in a tab of its own', async () => {
    // Written a second apart, so which is the last written in is plain. Dreams is made last and is the older one.
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(2026, 8, 28, 9, 0, 1));
    await createNote('diary', DIARY);
    vi.setSystemTime(new Date(2026, 8, 28, 9, 0, 0));
    await createNote('older', DIARY.replace(/Diary/g, 'Dreams'));
    vi.useRealTimers();
    await openApp();
    // The journal sits in a tab behind home: its line is written from the store, once.
    act(() => card('Diary').click());
    act(() => button('Home').click());
    act(() => button('Write a note').click());
    const row = buttonSaying(document.body, 'Entry in Diary')!;
    expect(row.textContent).toContain('Starts with the date and the time.');
    act(() => row.click());
    // The sheet asks what the entry starts with; the journal's usual template is first.
    await act(async () => buttonSaying(document.body, '· usual')!.click());
    await waitUntil(() => expect(noteShown()).not.toBeNull());
    const id = noteShown()!;
    expect(tabs()).toEqual(['diary', id]);
    const { title } = records()[id]!;
    expect(await diaryBody()).toBe(`${DIARY}- [[${title}]]\n`);
    expect((await getNote('older'))!.body).not.toContain(title);
  });

  it('aims the + at the journal on screen, and at the journal of an entry on screen, before the one written in last', async () => {
    // Dreams is written in last; Diary, with one entry, is the one being read.
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(2026, 8, 28, 9, 0, 0));
    await createNote('walk', '# Walk\n\nWalked.');
    await createNote('diary', `${DIARY}- [[Walk]]\n`);
    vi.setSystemTime(new Date(2026, 8, 28, 9, 0, 1));
    await createNote('dreams', DIARY.replace(/Diary/g, 'Dreams'));
    vi.useRealTimers();
    await openApp();
    const plus = () => document.querySelector<HTMLButtonElement>('button[aria-label="New note in a new tab"]')!;
    const closeSheet = () => act(() => (document.querySelector('[role="dialog"][aria-label="New"]')!.parentElement as HTMLElement).click());
    act(() => card('Diary').click());
    await act(async () => plus().click());
    expect(buttonSaying(document.body, 'Entry in Diary')).toBeDefined();
    expect(buttonSaying(document.body, 'Entry in Dreams')).toBeUndefined();
    closeSheet();
    await act(async () => seen.note!.onOpenWithin!('Walk'));
    await waitUntil(() => expect(noteShown()).toBe('walk'));
    await act(async () => plus().click());
    expect(buttonSaying(document.body, 'Entry in Diary')).toBeDefined();
    expect(buttonSaying(document.body, 'Entry in Dreams')).toBeUndefined();
  });

  it('makes the entry from the template picked in the + sheet', async () => {
    await seed(['diary', DIARY]);
    await openApp();
    act(() => button('Write a note').click());
    act(() => buttonSaying(document.body, 'Entry in Diary')!.click());
    await act(async () => buttonSaying(document.body, 'A morning page')!.click());
    await waitUntil(() => expect(noteShown()).not.toBeNull());
    const body = (await getNote(noteShown()!))!.body;
    expect(body).toContain('> What is on your mind this morning?');
    expect(body).not.toMatch(/\*\*\d{2}:\d{2}\*\*/);
  });

  it('makes the usual entry from the journal as the store has it now, not as the list last read it', async () => {
    const { updateNote } = await import('./core/store.ts');
    await seed(['diary', DIARY]);
    await openApp();
    // The template changed underneath the list, as a journal's More sheet changes it while the journal is open.
    const before = (await getNote('diary'))!;
    await updateNote('diary', before.body.replace('"# {{date}}\\n\\n**{{time}}** "', '"# {{date}}\\n\\n## To do\\n\\n- [ ] "'), before.revision ?? 1);
    expect((await getNote('diary'))!.body).toContain('## To do');
    act(() => button('Write a note').click());
    act(() => buttonSaying(document.body, 'Entry in Diary')!.click());
    await act(async () => buttonSaying(document.body, '· usual')!.click());
    await waitUntil(() => expect(noteShown()).not.toBeNull());
    const body = (await getNote(noteShown()!))!.body;
    expect(body).toContain('## To do');
    expect(body).toContain('- [ ] ');
  });

  it('offers no entry in a journal put away in the archive, however lately it was written in', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(2026, 8, 28, 9, 0, 0));
    await createNote('diary', DIARY);
    vi.setSystemTime(new Date(2026, 8, 28, 9, 0, 1));
    await createNote('old', DIARY.replace(/Diary/g, 'Old diary'));
    await setNoteArchived('old', true);
    vi.useRealTimers();
    await openApp();
    act(() => button('Write a note').click());
    expect(buttonSaying(document.body, 'Entry in Diary')).toBeDefined();
    expect(buttonSaying(document.body, 'Entry in Old diary')).toBeUndefined();
  });

  it('leaves an untouched entry as it was made when its mic opens the meeting being recorded instead', async () => {
    const { setMeetingStateForTests } = await import('./capture/meetingLive.ts');
    await seed(['diary', DIARY], ['m1', '# Meeting, 28 Sep 14:05']);
    await openApp();
    act(() => card('Diary').click());
    const { id } = await newEntry();
    const made = (await getNote(id))!.body;
    setMeetingStateForTests({ recording: true, noteId: 'm1', startedAt: Date.now(), writeUps: [] } as unknown as Parameters<typeof setMeetingStateForTests>[0]);
    try {
      await act(async () => seen.note!.onSpeak!(id));
      await waitUntil(() => expect(document.querySelector('[aria-label="Stop and write up"]')).not.toBeNull());
      expect((await getNote(id))!.body).toBe(made);
    } finally {
      setMeetingStateForTests(null);
    }
  });

  it('makes one entry for New entry pressed twice at once, and gives it its line', async () => {
    await seed(['diary', DIARY]);
    await openApp();
    act(() => card('Diary').click());
    const press = seen.note!.onNewEntry!;
    // A double tap: the second press comes before the first has read anything.
    act(() => {
      press();
      press();
    });
    await waitUntil(() => expect(noteShown()).not.toBe('diary'));
    const id = noteShown()!;
    await waitUntil(async () => expect(await diaryBody()).toBe(`${DIARY}- [[${records()[id]!.title}]]\n`));
    // The store here answers in the same turn (core/store.ts): everything either press started has landed by now.
    expect((await listNotes()).map((n) => n.id).filter((each) => each !== 'diary')).toEqual([id]);
    expect(Object.keys(records())).toEqual([id]);
    // Made once: the second press did nothing, rather than making a twin to be taken back.
    expect(vi.mocked(createNote).mock.calls.filter(([each]) => each !== 'diary')).toHaveLength(1);
  });

  it('names an entry past a line the journal still has for the minute, and notes archived or in the Trash with its name', async () => {
    const { trashNote } = await import('./core/trash.ts');
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(2026, 8, 28, 14, 5));
    // An entry left a moment ago whose line is still being taken out, an old note archived under the next name, and
    // one in the Trash under the name after that: Restore would bring back a second note of the new entry's name.
    await seed(['diary', `${DIARY}- [[2026-09-28 14.05]]\n`], ['old', '---\ntitle: "2026-09-28 14.05 (2)"\n---\nArchived.'], ['binned', '---\ntitle: "2026-09-28 14.05 (3)"\n---\nBinned.']);
    await setNoteArchived('old', true);
    trashNote('binned');
    await openApp();
    act(() => card('Diary').click());
    const { title } = await newEntry();
    expect(title).toBe('2026-09-28 14.05 (4)');
    expect(await diaryBody()).toBe(`${DIARY}- [[2026-09-28 14.05]]\n- [[2026-09-28 14.05 (4)]]\n`);
  });

  it('keeps the line of an entry taken back when another note is named by it, whose line it is too', async () => {
    const title = '2026-09-28 14.05';
    const words = '# Monday 28 September\n\n**14:05** ';
    await seed(
      ['diary', `${DIARY}- [[${title}]]\n`],
      ['kept', `---\ntitle: "${title}"\ndate: 2026-09-28T14:05\n---\n${words}Written in.`],
      ['left', `---\ntitle: "${title}"\ndate: 2026-09-28T14:05\n---\n${words}`],
    );
    localStorage.setItem('glyph-entry-drafts', JSON.stringify({ left: { journalId: 'diary', title, words, at: Date.now() } }));
    await openApp();
    await waitUntil(async () => expect(await getNote('left')).toBeNull());
    await waitUntil(() => expect(records()).toEqual({}));
    expect(await diaryBody()).toBe(`${DIARY}- [[${title}]]\n`);
    expect(await getNote('kept')).not.toBeNull();
  });

  it('takes out the line of an entry whose note is already gone', async () => {
    const title = '2026-09-28 14.05';
    await seed(['diary', `${DIARY}- [[${title}]]\n`]);
    localStorage.setItem('glyph-entry-drafts', JSON.stringify({ gone: { journalId: 'diary', title, words: 'x', at: Date.now() } }));
    await openApp();
    await waitUntil(async () => expect(await diaryBody()).toBe(DIARY));
    expect(records()).toEqual({});
  });

  it('takes an untouched entry back when its tab is closed behind another note', async () => {
    await seed(['diary', DIARY], ['walk', '# Walk']);
    await openApp();
    act(() => card('Walk').click());
    act(() => button('Home').click());
    act(() => card('Diary').click());
    const { id, title } = await newEntry();
    act(() => button('Walk').click());
    expect(noteShown()).toBe('walk');
    // Closed from the tab row while Walk stays on screen: nothing on screen changes but the tabs.
    act(() => button(`Close ${title}`).click());
    expect(noteShown()).toBe('walk');
    await waitUntil(async () => expect(await getNote(id)).toBeNull());
    await waitUntil(async () => expect(await diaryBody()).toBe(DIARY));
  });

  it('gives the journal back the tab an untouched entry took, on Back, and takes the entry back', async () => {
    await seed(['diary', DIARY]);
    await openApp();
    act(() => card('Diary').click());
    const { id } = await newEntry();
    expect(tabs()).toEqual([id]);
    act(() => button('Back to where you were').click());
    expect(noteShown()).toBe('diary');
    expect(tabs()).toEqual(['diary']);
    await waitUntil(async () => expect(await getNote(id)).toBeNull());
    await waitUntil(async () => expect(await diaryBody()).toBe(DIARY));
  });

  it('keeps the record before the line and the note, so a WebView let go at any step leaves it to finish from', async () => {
    await seed(['diary', DIARY]);
    await openApp();
    // The journal behind home, so its line is written through the store and the order can be watched there.
    act(() => card('Diary').click());
    act(() => button('Home').click());
    const kept: string[] = [];
    vi.mocked(updateNote).mockImplementation(async (id, body, revision) => {
      if (id === 'diary') kept.push(`line:${Object.keys(records()).length}`);
      return realStore.updateNote(id, body, revision);
    });
    vi.mocked(createNote).mockImplementation(async (id, body, source) => {
      kept.push(`note:${Object.keys(records()).length}`);
      return realStore.createNote(id, body, source);
    });
    act(() => button('Write a note').click());
    act(() => buttonSaying(document.body, 'Entry in Diary')!.click());
    await act(async () => buttonSaying(document.body, '· usual')!.click());
    await waitUntil(() => expect(noteShown()).not.toBeNull());
    expect(kept).toEqual(['line:1', 'note:1']);
  });

  it('leaves an entry still being made alone when the person goes home before it is open', async () => {
    await seed(['diary', DIARY]);
    await openApp();
    act(() => card('Diary').click());
    // The store slow to make the entry's note: its record and its line are in, and the note is not there yet.
    let made: () => void = () => undefined;
    const slow = new Promise<void>((resolve) => {
      made = resolve;
    });
    vi.mocked(createNote).mockImplementation(async (id, body, source) => {
      await slow;
      return realStore.createNote(id, body, source);
    });
    act(() => void seen.note!.onNewEntry!());
    await waitUntil(async () => expect(await diaryBody()).toMatch(/- \[\[\d{4}-\d{2}-\d{2} \d{2}\.\d{2}\]\]\n$/));
    const [id] = Object.keys(records());
    act(() => button('Home').click());
    await act(async () => {
      made();
      await slow;
    });
    await waitUntil(() => expect(noteShown()).toBe(id));
    // Made whole, and still the journal's: the look on the way home found it being made and let it be.
    expect(records()[id!]).toBeDefined();
    expect(await diaryBody()).toBe(`${DIARY}- [[${records()[id!]!.title}]]\n`);
    expect(await getNote(id!)).not.toBeNull();
  });

  it('writes the entry’s line again when another writer got to the journal first', async () => {
    await seed(['diary', DIARY]);
    await openApp();
    act(() => card('Diary').click());
    act(() => button('Home').click());
    let lost = false;
    vi.mocked(updateNote).mockImplementation(async (id, body, revision) => {
      if (id === 'diary' && !lost) {
        lost = true;
        throw new Error('the note changed since it was read');
      }
      return realStore.updateNote(id, body, revision);
    });
    act(() => button('Write a note').click());
    act(() => buttonSaying(document.body, 'Entry in Diary')!.click());
    await act(async () => buttonSaying(document.body, '· usual')!.click());
    await waitUntil(() => expect(noteShown()).not.toBeNull());
    const { title } = records()[noteShown()!]!;
    expect(lost).toBe(true);
    expect(await diaryBody()).toBe(`${DIARY}- [[${title}]]\n`);
  });

  it('puts an untouched entry back as it was made when its own mic keeps nothing, even with the entry handed back', async () => {
    await seed(['diary', DIARY]);
    await openApp();
    act(() => card('Diary').click());
    const { id } = await newEntry();
    const made = (await getNote(id))!.body;
    await act(async () => seen.note!.onSpeak!(id));
    await waitUntil(() => expect(screenNow()?.dataset.screen).toBe('capture'));
    // The record follows the entry as the recorder was given it, without the line the words go on from.
    const handed = (await getNote(id))!;
    expect((records()[id] as unknown as { words: string }).words).toBe(handed.body.slice(handed.body.indexOf('\n---\n') + 5));
    // The recorder answers with the entry as it had it: nothing was said into it.
    await act(async () => seen.capture!.onFinish(handed, false));
    await waitUntil(() => expect(noteShown()).toBe(id));
    await waitUntil(async () => expect((await getNote(id))!.body).toBe(made));
    expect(records()[id]).toBeDefined();
  });

  it('asks where a spoken entry was written only once the recorder has gone, with its own introduction', async () => {
    await seed(['diary', DIARY.replace('---\n# Diary', 'entry-place: true\n---\n# Diary')]);
    await openApp();
    act(() => card('Diary').click());
    await act(async () => seen.note!.onSpeak!('diary'));
    await waitUntil(() => expect(screenNow()?.dataset.screen).toBe('capture'));
    const id = screenNow()!.dataset.into!;
    // Never at the tap: the recorder's microphone prompt comes first.
    expect(tagEntryIfWanted).not.toHaveBeenCalled();
    const made = (await getNote(id))!;
    const said = await updateNote(id, `${made.body}\n**14:05** Walked along the river.`, made.revision ?? 1);
    await act(async () => seen.capture!.onFinish(said, false));
    await waitUntil(() => expect(noteShown()).toBe(id));
    await waitUntil(() => expect(tagEntryIfWanted).toHaveBeenCalledTimes(1));
    expect(vi.mocked(tagEntryIfWanted).mock.calls[0]).toEqual([[id], { reviewing: false }, { quiet: false, introduce: expect.any(Function) }]);
    // Its introduction, in the app's words.
    act(() => vi.mocked(tagEntryIfWanted).mock.calls[0]![2]!.introduce!(() => undefined));
    await waitUntil(() => expect(document.body.textContent).toContain('Diary keeps where each entry was written.'));
    expect(buttonSaying(document.body, 'Allow location')).toBeDefined();
  });

  it('offers no journal entry as a page for a notebook, from the New notebook sheet or a notebook’s index', async () => {
    const title = '2026-09-28 14.05';
    await seed(['diary', `${DIARY}- [[${title}]]\n`], ['e1', `---\ntitle: "${title}"\ndate: 2026-09-28T14:05\n---\nWords of mine.`], ['walk', '# Walk'], ['guide', '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n']);
    await openApp();
    act(() => button('Write a note').click());
    // The New sheet's Notebook, not the home page's filter of the same word.
    act(() => buttonSaying(document.querySelector('section[role="dialog"]')!, 'Notebook')!.click());
    const listed = () => [...document.querySelectorAll('ul[aria-label="Notes"] button')].map((b) => b.textContent?.trim());
    await waitUntil(() => expect(listed()).toContain('Walk'));
    expect(listed()).not.toContain(title);
    const { goBack } = await import('./core/back.ts');
    act(() => goBack());
    act(() => card('Field guide').click());
    expect(seen.note!.pageTitles!()).toContain('Walk');
    expect(seen.note!.pageTitles!()).not.toContain(title);
    // A [[link]] still finds an entry by its name.
    expect(seen.note!.allTitles!()).toContain(title);
  });

  it('opens the journal itself from its card, after an entry was read', async () => {
    const title = '2026-09-28 14.05';
    await seed(['diary', `${DIARY}- [[${title}]]\n`], ['e1', `---\ntitle: "${title}"\ndate: 2026-09-28T14:05\n---\nWords of mine.`]);
    writeBookSpot('diary', { kind: 'chapter', title });
    await openApp();
    act(() => card('Diary').click());
    expect(noteShown()).toBe('diary');
  });
});
