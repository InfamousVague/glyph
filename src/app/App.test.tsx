import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, type ComponentProps } from 'react';
import type { NoteScreen } from './editor/NoteScreen.tsx';
import type { CaptureScreen } from './capture/CaptureScreen.tsx';
import type { Guide } from './guide/Guide.tsx';
import { createNote, getNote, type Note } from './core/store.ts';
import { preferences, reloadPreferences, setPreferences } from './core/preferences.ts';
import { button, buttonSaying, show, unmount, waitUntil } from '../test/render.tsx';
import { stubResizeObserver } from '../test/stubs.ts';

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

/** The props each stubbed screen was last drawn with, for the test to press what the screen would. */
const seen = vi.hoisted(() => ({ note: null as NoteProps | null, capture: null as CaptureProps | null, guide: null as GuideProps | null }));

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
vi.mock('./settings/SettingsSheet.tsx', () => ({ SettingsSheet: ({ open }: { open: boolean }) => (open ? <div data-screen="settings" /> : null) }));
vi.mock('./academy/AcademyScreen.tsx', () => ({ AcademyScreen: () => <main data-screen="academy" /> }));
// Its rAF clock and its wink are its own test's business; here the app is simply open.
vi.mock('./launch/LaunchScreen.tsx', () => ({ LaunchScreen: () => null }));
// A card's small drawing is a CodeMirror editor (notes/NotePeek.tsx), one per card: nothing the Shell decides.
vi.mock('./notes/NotePeek.tsx', () => ({ NotePeek: () => null }));
vi.mock('./share/share.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./share/share.ts')>()),
  readShared: vi.fn(async () => ({ v: 1, kind: 'note', title: 'Shared', pages: [{ title: 'Shared', body: '# Shared\n\nFrom a friend.' }], at: 1 })),
  forkShared: vi.fn(async () => createNote('forked', '# Shared\n\nFrom a friend.')),
}));

const { App } = await import('./App.tsx');

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
  // The preferences are held in memory as well as kept: a tab row, a group or the trash left by the last test goes.
  reloadPreferences();
  history.replaceState(null, '', '/');
  seen.note = null;
  seen.capture = null;
  seen.guide = null;
});

afterEach(() => {
  unmount();
  vi.useRealTimers();
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

  it('on a reading page of the guide says it is too soon rather than recording', async () => {
    localStorage.removeItem('glyph-guide-seen');
    await openApp();
    expect(seen.guide?.index).toBe(0);
    await act(async () => window.__glyph!.capture!());
    expect(screenNow()?.dataset.screen).not.toBe('capture');
    expect(document.querySelector<HTMLElement>('[data-screen="guide"]')?.dataset.tooSoon).toBe('true');
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
