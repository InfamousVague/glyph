import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, type ComponentProps } from 'react';
import type { NoteScreen } from './editor/NoteScreen.tsx';
import type { CaptureScreen } from './capture/CaptureScreen.tsx';
import type { Guide } from './guide/Guide.tsx';
import type { SettingsSheet } from './settings/SettingsSheet.tsx';
import { createNote, getNote, listNotes, setNoteArchived, setNoteRecording, updateNote, type Note } from './core/store.ts';
import { preferences, reloadPreferences, setPreferences } from './core/preferences.ts';
import { button, buttonSaying, show, unmount, waitUntil } from '../test/render.tsx';
import { stubResizeObserver } from '../test/stubs.ts';
import { bookNoteBody } from './book/book.ts';
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

/** The props each stubbed screen was last drawn with, for the test to press what the screen would. */
const seen = vi.hoisted(() => ({ note: null as NoteProps | null, capture: null as CaptureProps | null, guide: null as GuideProps | null, settings: null as SettingsProps | null }));

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
    return props.open ? <div data-screen="settings" /> : null;
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
// The summary queue (§127 section 2) as the shelf reads it: here a tape can be made to wait for a model, for the shelf's
// Get a model. The queue itself is the real one, which does nothing off the phone.
const needsModel = vi.hoisted(() => new Set<string>());
vi.mock('./ai/summaries.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./ai/summaries.ts')>()),
  useSummaries: () => ({ pending: new Set<string>(), native: new Set<string>(), waiting: new Set<string>(), failed: new Set<string>(), needsModel }),
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
  // The preferences are held in memory as well as kept: a tab row, a group or the trash left by the last test goes.
  reloadPreferences();
  history.replaceState(null, '', '/');
  seen.note = null;
  seen.capture = null;
  seen.guide = null;
  seen.settings = null;
});

afterEach(() => {
  unmount();
  vi.useRealTimers();
  vi.mocked(createNote).mockImplementation(realStore.createNote);
  vi.mocked(updateNote).mockImplementation(realStore.updateNote);
  vi.mocked(createNote).mockClear();
  vi.mocked(updateNote).mockClear();
  vi.mocked(tagEntryIfWanted).mockClear();
  needsModel.clear();
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

describe('the shelf of tapes', () => {
  /** Recordings the recorder made, `take1` the newest. */
  async function record(count: number): Promise<void> {
    for (let i = count; i >= 1; i -= 1) {
      await createNote(`take${i}`, `# Take ${i}`, 'capture');
      await setNoteRecording(`take${i}`, 40_000, []);
    }
  }

  it('sends the Tapes heading’s See all to All notes with only the tapes showing', async () => {
    await record(9);
    await openApp();
    await waitUntil(() => expect(button('See all')).toBeTruthy());
    act(() => button('See all').click());
    await waitUntil(() => expect(document.querySelector('ol[aria-label="Notes"]')).not.toBeNull());
    expect(document.querySelector('button[aria-pressed="true"]')?.textContent).toContain('Tapes · 9');
  });

  it('opens Settings at Recording’s Model card from Get a model', async () => {
    needsModel.add('take1');
    await record(1);
    await openApp();
    await waitUntil(() => expect(button('Get a model')).toBeTruthy());
    expect(seen.settings?.open).toBe(false);
    act(() => button('Get a model').click());
    expect(seen.settings?.open).toBe(true);
    expect(seen.settings?.toModel).toBeGreaterThan(0);
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
    expect(seen.note!.caretAtEnd).toBe(true);
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
    act(() => buttonSaying(document.body, 'Notebook')!.click());
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
