import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, type ReactElement } from 'react';
import { EditorView } from '@codemirror/view';
import { undo } from '@codemirror/commands';
import { ToastProvider } from '@glacier/react';
import { button, buttonSaying, press, rerender, show, typeInto, unmount, waitUntil } from '../../test/render.tsx';
import { applyCommandMutation, createNote, getNote, setNoteRecording, updateNote, type Note } from '../core/store.ts';
import type { CaptureLanding } from '../capture/landing.ts';
import { goBack } from '../core/back.ts';
import { setTapeId, tapeId } from '../core/clips.ts';
import { setTopBarTools } from '../core/topBarTools.ts';
import { bookOf } from '../book/book.ts';
import type { JournalWriter } from '../book/journal.ts';
import { readBookSpot } from '../book/bookSpot.ts';
import { insertSpots } from './inserts.ts';
import { cancelRun, forgetAllRuns, simulateRuns, startRun } from '../ai/runs.ts';

// The Glacier kit reads matchMedia as it loads, and the page's smoke watches its header's size.
await vi.hoisted(async () => {
  const stubs = await import('../../test/stubs.ts');
  stubs.stubMatchMedia();
  stubs.stubResizeObserver();
});

/**
 * One note open, and what a keystroke becomes. The screen keeps the words in a ref and saves them 400 ms after the
 * last keystroke, and at once whenever the app could be about to go - hidden, the page put away, the screen taken
 * down, every way off the note it offers - because a phone kills a backgrounded webview without warning. What to save
 * is decided at that moment; the write itself follows the one before it. The store is the real browser one
 * (core/store.ts), with its write watched.
 */

/** Every hold the screen put on a note's better words, and every let-go (capture/refine.ts `holdNote`). */
const holds = vi.hoisted(() => [] as [string, boolean][]);
/** Every recording's better words the screen took out of the queue (capture/refine.ts `dropRefine`). */
const drops = vi.hoisted(() => [] as [string, number][]);
/** A review's listening again held open, for a test that needs the review live while it acts: resolved to let it go. */
const listening = vi.hoisted(() => ({ hold: null as Promise<null> | null }));
vi.mock('../capture/refine.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../capture/refine.ts')>();
  return {
    ...real,
    holdNote: (id: string, on: boolean) => void holds.push([id, on]),
    dropRefine: (id: string, fromMs: number) => void drops.push([id, fromMs]),
    listenAgain: (...args: Parameters<typeof real.listenAgain>) => listening.hold ?? real.listenAgain(...args),
  };
});

/** Who is listening for the phone's write-up changing a note (ai/summaries.ts `onRecordingChanged`), to say it to them. */
const recordingListeners = vi.hoisted(() => new Set<(id: string) => void>());
vi.mock('../ai/summaries.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../ai/summaries.ts')>();
  return {
    ...real,
    onRecordingChanged: (listener: (id: string) => void) => {
      recordingListeners.add(listener);
      return () => void recordingListeners.delete(listener);
    },
  };
});
// The map card's Leaflet is a picture the card draws for itself (MapCard.test.tsx); here only that a card is there.
vi.mock('leaflet', () => {
  const L = { map: () => ({ setView: () => undefined, invalidateSize: () => undefined, remove: () => undefined }), tileLayer: () => ({ on: () => undefined, addTo: () => undefined }), divIcon: () => ({}), marker: () => ({ addTo: () => undefined }) };
  return { ...L, default: L };
});
vi.mock('leaflet/dist/leaflet.css', () => ({}));

vi.mock('../core/store.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../core/store.ts')>();
  return { ...real, updateNote: vi.fn(real.updateNote) };
});

/** Whether the AI can run here (ai/available.ts): a browser's answer unless a test says a model is on the phone. */
const ai = vi.hoisted(() => ({ ok: false }));
vi.mock('../ai/available.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../ai/available.ts')>();
  return {
    ...real,
    useAvailability: () => ({
      availability: ai.ok ? { ok: true, model: 'qwen3.5-4b', chosen: 'qwen3.5-4b' } : { ok: false, reason: 'The AI runs on the phone. Install Ghost.md on Android to use it.', get: null, waiting: false },
      models: [],
      download: null,
      problem: null,
      fetch: async () => undefined,
    }),
  };
});

/**
 * Films (core/videos.ts), on a phone that adds them only where a test says so: the picker, the keeping and whether a
 * film is here are stood in for, so the note screen's own part is what is tried.
 */
const films = vi.hoisted(() => ({
  can: false,
  pick: null as ((ways: import('../core/videos.ts').PickWays) => Promise<{ video: string; poster: string; ms: number; width: number; height: number } | null>) | null,
  where: 'elsewhere' as 'here' | 'missing' | 'update' | 'elsewhere',
}));
vi.mock('../core/videos.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../core/videos.ts')>();
  return {
    ...real,
    canAddVideos: async () => films.can,
    pickVideo: (ways: import('../core/videos.ts').PickWays = {}) => (films.pick ? films.pick(ways) : Promise.resolve(null)),
    filmHere: async () => films.where,
    filmsPlay: async () => (films.where === 'here' || films.where === 'missing' ? ('phone' as const) : films.where),
  };
});

const { NoteScreen } = await import('./NoteScreen.tsx');

const saves = vi.mocked(updateNote);

/** The screen for `note`, inside the toasts it speaks through, with every callback a no-op unless the test gives one. */
function screen(note: Note, over: Partial<Parameters<typeof NoteScreen>[0]> = {}): ReactElement {
  return (
    <ToastProvider>
      <NoteScreen note={note} onBack={() => {}} onDelete={() => {}} onSpeak={() => {}} onPin={() => {}} onArchive={() => {}} {...over} />
    </ToastProvider>
  );
}

/** The screen's one editor. */
function editor(): EditorView {
  const dom = document.querySelector<HTMLElement>('.cm-editor');
  const view = dom ? EditorView.findFromDOM(dom) : null;
  if (!view) throw new Error('no editor on the screen');
  return view;
}

/** A keystroke's worth: `words` put at the end of the note, as typing them would. */
function type(words: string): void {
  const view = editor();
  act(() => view.dispatch({ changes: { from: view.state.doc.length, insert: words }, userEvent: 'input.type' }));
}

/** Lets the writes the screen has chained run, so the store has been asked and has answered. */
async function settle(): Promise<void> {
  for (let i = 0; i < 5; i += 1) {
    await act(async () => {
      await Promise.resolve();
    });
  }
}

/** The body each save was handed, in order. */
const saved = () => saves.mock.calls.map((call) => call[1]);

function hide(): void {
  Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
  act(() => {
    document.dispatchEvent(new Event('visibilitychange'));
  });
}

beforeEach(() => {
  localStorage.clear();
  saves.mockClear();
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
});

afterEach(() => {
  unmount();
  setTopBarTools(null);
  ai.ok = false;
  Object.assign(films, { can: false, pick: null, where: 'elsewhere' });
  vi.useRealTimers();
  Reflect.deleteProperty(document, 'visibilityState');
});

describe('saving what is typed', () => {
  it('saves once, 400 ms after the last keystroke, with every keystroke in it', async () => {
    const note = await createNote('n1', '# Groceries');
    show(screen(note));
    type('\nmilk');
    act(() => vi.advanceTimersByTime(300));
    type(', eggs');
    act(() => vi.advanceTimersByTime(399));
    await settle();
    expect(saves).not.toHaveBeenCalled();
    act(() => vi.advanceTimersByTime(1));
    await settle();
    expect(saves).toHaveBeenCalledTimes(1);
    expect(saves).toHaveBeenCalledWith('n1', '# Groceries\nmilk, eggs', 1);
    expect((await getNote('n1'))?.body).toBe('# Groceries\nmilk, eggs');
  });

  it('saves the moment the app is hidden, what was there then, and the waiting save does not save again', async () => {
    const note = await createNote('n1', '# Groceries');
    show(screen(note));
    type('\nmilk');
    hide();
    // Typed after the flush: the next save's, not this one's.
    type('!');
    await settle();
    expect(saved()).toEqual(['# Groceries\nmilk']);
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect(saved()).toEqual(['# Groceries\nmilk', '# Groceries\nmilk!']);
    act(() => vi.advanceTimersByTime(1000));
    await settle();
    expect(saves).toHaveBeenCalledTimes(2);
  });

  it('does nothing on a visibility change that is not the app going away', async () => {
    const note = await createNote('n1', '# Groceries');
    show(screen(note));
    type('\nmilk');
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await settle();
    expect(saves).not.toHaveBeenCalled();
  });

  it('saves when the page is put away', async () => {
    const note = await createNote('n1', '# Groceries');
    show(screen(note));
    type('\nbread');
    act(() => {
      window.dispatchEvent(new Event('pagehide'));
    });
    await settle();
    expect(saved()).toEqual(['# Groceries\nbread']);
  });

  it('saves what is waiting when the screen is taken down', async () => {
    const note = await createNote('n1', '# Groceries');
    show(screen(note));
    type('\nbutter');
    unmount();
    await settle();
    expect(saved()).toEqual(['# Groceries\nbutter']);
    expect((await getNote('n1'))?.body).toBe('# Groceries\nbutter');
  });

  it('writes nothing when nothing was typed, however the note is left', async () => {
    const note = await createNote('n1', '# Groceries');
    show(screen(note));
    hide();
    act(() => {
      window.dispatchEvent(new Event('pagehide'));
    });
    unmount();
    await settle();
    expect(saves).not.toHaveBeenCalled();
  });

  it('carries the revision each save came back with into the next', async () => {
    const note = await createNote('n1', '# Groceries');
    show(screen(note));
    type('\nmilk');
    act(() => vi.advanceTimersByTime(400));
    await settle();
    type('\neggs');
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect(saves.mock.calls.map((call) => call[2])).toEqual([1, 2]);
    expect((await getNote('n1'))?.body).toBe('# Groceries\nmilk\neggs');
  });

  it('opens on the words the store has when the copy it was given is older, and saves from their revision', async () => {
    // The copy a list read before the last words were saved: a page opened again from its notebook's bar or its row.
    const old = await createNote('n1', '# Lisbon\n\nTrams.');
    await updateNote('n1', '# Lisbon\n\nTrams. And tarts.', 1);
    saves.mockClear();
    show(screen(old));
    await settle();
    expect(editor().state.doc.toString()).toBe('# Lisbon\n\nTrams. And tarts.');
    type(' And the river.');
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect(saves.mock.calls.map((call) => call[2])).toEqual([2]);
    expect((await getNote('n1'))?.body).toBe('# Lisbon\n\nTrams. And tarts. And the river.');
  });

  it('reads the note again only once the last screen on it has saved, however soon it is opened again', async () => {
    const note = await createNote('n1', '# Lisbon\n\nTrams.');
    show(screen(note));
    type(' And tarts.');
    // The phone's store slow to answer the save on the way out, as a write across the bridge is.
    let land: () => void = () => undefined;
    const landed = new Promise<void>((resolve) => {
      land = resolve;
    });
    const real = saves.getMockImplementation()!;
    saves.mockImplementationOnce(async (...args: Parameters<typeof real>) => {
      await landed;
      return real(...args);
    });
    // Left, and opened again at once with the copy it was opened with first: the last save is still on its way.
    unmount();
    show(screen(note));
    await settle();
    land();
    await settle();
    expect(editor().state.doc.toString()).toBe('# Lisbon\n\nTrams. And tarts.');
    type(' And the river.');
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect((await getNote('n1'))?.body).toBe('# Lisbon\n\nTrams. And tarts. And the river.');
  });

  it('says the notes changed once the last save of a note left has landed, so the lists drawn from them catch up', async () => {
    const { NOTES_CHANGED } = await import('../core/store.ts');
    const heard = vi.fn(async () => (await getNote('n1'))?.body);
    window.addEventListener(NOTES_CHANGED, heard);
    try {
      show(screen(await createNote('n1', '# Groceries')));
      unmount();
      await settle();
      // Nothing written, nothing said.
      expect(heard).not.toHaveBeenCalled();
      show(screen((await getNote('n1'))!));
      type('\nmilk');
      unmount();
      await settle();
      expect(heard).toHaveBeenCalledTimes(1);
      expect(await heard.mock.results[0]!.value).toBe('# Groceries\nmilk');
    } finally {
      window.removeEventListener(NOTES_CHANGED, heard);
    }
  });

  it('stops saving after a write is refused, rather than writing over the note that won', async () => {
    const note = await createNote('n1', '# Groceries');
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    show(screen(note));
    saves.mockRejectedValueOnce(new Error('the note was deleted or changed'));
    type('\nmilk');
    act(() => vi.advanceTimersByTime(400));
    await settle();
    type('\neggs');
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect(saves).toHaveBeenCalledTimes(1);
    expect(warn).toHaveBeenCalledWith('[glyph] editor save stopped:', expect.any(Error));
    warn.mockRestore();
  });

  it('saves before the back gesture leaves the note', async () => {
    const note = await createNote('n1', '# Groceries');
    const onBack = vi.fn();
    show(screen(note, { onBack }));
    type('\nmilk');
    act(() => {
      goBack();
    });
    expect(onBack).toHaveBeenCalledTimes(1);
    // Decided before the leaving: what is typed after it is not in this save.
    type('!');
    await settle();
    expect(saved()[0]).toBe('# Groceries\nmilk');
  });

  it('saves before talking into the note', async () => {
    const note = await createNote('n1', '# Groceries');
    const onSpeak = vi.fn();
    show(screen(note, { onSpeak }));
    type('\nmilk');
    act(() => button('Talk into this note').click());
    await settle();
    expect(onSpeak).toHaveBeenCalledWith('n1');
    expect(saved()).toEqual(['# Groceries\nmilk']);
  });

  it('saves before a pin, and pins and unpins from its own record of the note', async () => {
    const note = await createNote('n1', '# Groceries');
    const pinned: (boolean | undefined)[] = [];
    show(screen(note, { onPin: (n) => pinned.push(n.starred) }));
    type('\nmilk');
    act(() => button('More for this note').click());
    act(() => button('Pin to the top').click());
    await settle();
    expect(saved()).toEqual(['# Groceries\nmilk']);
    // App hands back the same note after a pin, so the screen says what it now is: pinned, and the next press unpins.
    act(() => button('More for this note').click());
    act(() => button('Unpin').click());
    expect(pinned).toEqual([false, true]);
  });

  it('saves before the note is archived', async () => {
    const note = await createNote('n1', '# Groceries');
    const onArchive = vi.fn();
    show(screen(note, { onArchive }));
    type('\nmilk');
    act(() => button('More for this note').click());
    act(() => button('Archive').click());
    await settle();
    expect(onArchive).toHaveBeenCalledTimes(1);
    expect(saved()).toEqual(['# Groceries\nmilk']);
  });
});

describe('a rename asked from the tab', () => {
  const CANVAS = '{"nodes":[],"edges":[]}';
  /** The canvas as its tab would name it: a `title:` in front matter above the JSON (core/frontMatter.ts). */
  const named = (title: string) => `---\ntitle: "${title}"\n---\n${CANVAS}`;

  it('writes the name through the screen, saved like typing, and again when the same name is asked again', async () => {
    const note = await createNote('c1', CANVAS);
    show(screen(note, { rename: { id: 'c1', title: 'Trip', asked: 1 } }));
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect(saved()).toEqual([named('Trip')]);
    // Renamed since in the note's own sheet, the same name asked for from the tab still lands.
    act(() => button('More for this note').click());
    const name = [...document.querySelectorAll('input')].find((field) => field.closest('label')?.textContent?.includes('Name'));
    typeInto(name!, 'Tour');
    act(() => vi.advanceTimersByTime(400));
    await settle();
    rerender(screen(note, { rename: { id: 'c1', title: 'Trip', asked: 2 } }));
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect(saved()).toEqual([named('Trip'), named('Tour'), named('Trip')]);
  });

  it('keeps a book’s new name through the next change made in its index', async () => {
    const book = '---\nbook: true\n---\n# Trip\n\n1. [[Day one]]\n2. [[Day two]]\n';
    show(screen(await createNote('b1', book), { rename: { id: 'b1', title: 'Road trip', asked: 1 }, hasTitle: () => true, onOpenTitle: () => {} }));
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect(saved().at(-1)).toContain('title: "Road trip"');
    act(() => button('Move Day two up').click());
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect(saved().at(-1)).toContain('title: "Road trip"');
    expect(saved().at(-1)!.indexOf('[[Day two]]')).toBeLessThan(saved().at(-1)!.indexOf('[[Day one]]'));
  });

  it('keeps a book’s name typed in the More sheet through the next change made in its index', async () => {
    const book = '---\nbook: true\n---\n# Trip\n\n1. [[Day one]]\n2. [[Day two]]\n';
    show(screen(await createNote('b1', book), { hasTitle: () => true, onOpenTitle: () => {} }));
    act(() => button('More for this note').click());
    const name = [...document.querySelectorAll('input')].find((field) => field.closest('label')?.textContent?.includes('Name'));
    typeInto(name!, 'Road trip');
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect(saved().at(-1)).toContain('title: "Road trip"');
    act(() => goBack());
    act(() => button('Move Day two up').click());
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect(saved().at(-1)).toContain('title: "Road trip"');
    expect(saved().at(-1)!.indexOf('[[Day two]]')).toBeLessThan(saved().at(-1)!.indexOf('[[Day one]]'));
  });

  it('leaves the note alone when the rename is for another', async () => {
    const note = await createNote('c1', CANVAS);
    show(screen(note, { rename: { id: 'c2', title: 'Trip', asked: 1 } }));
    act(() => vi.advanceTimersByTime(1000));
    await settle();
    expect(saves).not.toHaveBeenCalled();
  });
});

describe("the note's tools", () => {
  /** The view switch: the first of the tools, whatever it is called now. */
  const viewSwitch = () => document.querySelector<HTMLButtonElement>('header button, [data-slot] button')!;

  it('say what a press on the view switch will show, for a note of words, a canvas and a book', async () => {
    show(screen(await createNote('n1', '# Groceries')));
    expect(viewSwitch().getAttribute('aria-label')).toBe('Showing the marks. Show the formatted note.');
    act(() => viewSwitch().click());
    expect(viewSwitch().getAttribute('aria-label')).toBe('Showing the formatted note. Show the marks.');
    expect(viewSwitch().title).toBe('Formatted');
    unmount();

    show(screen(await createNote('c1', '{"nodes":[],"edges":[]}')));
    expect(viewSwitch().getAttribute('aria-label')).toBe('Showing the canvas. Show its JSON.');
    expect(viewSwitch().title).toBe('Canvas');
    act(() => viewSwitch().click());
    expect(viewSwitch().getAttribute('aria-label')).toBe('Showing the canvas as JSON. Show the canvas.');
    expect(viewSwitch().title).toBe('JSON');
    unmount();

    show(screen(await createNote('b1', '---\nbook: true\n---\n# Trip\n\n1. [[Day one]]\n'), { hasTitle: () => true, onOpenTitle: () => {} }));
    expect(viewSwitch().getAttribute('aria-label')).toBe('Showing the index. Show its Markdown.');
    act(() => viewSwitch().click());
    expect(viewSwitch().getAttribute('aria-label')).toBe('Showing the index as Markdown. Show the index.');
    expect(viewSwitch().title).toBe('Markdown');
  });

  it('are drawn in the top bar when it offers a place, and the header is left empty', async () => {
    const slot = document.createElement('div');
    slot.dataset.slot = '';
    document.body.appendChild(slot);
    act(() => setTopBarTools(slot));
    show(screen(await createNote('n1', '# Groceries')));
    expect(button('More for this note', slot)).toBeTruthy();
    // Nothing at all in the header, so `.header:empty` takes its padding away (NoteScreen.module.css).
    expect(document.querySelector('header')?.childNodes.length).toBe(0);
    slot.remove();
  });

  it('bookmarks the line, says where, and takes it off when pressed there again', async () => {
    show(screen(await createNote('n1', '# Groceries\nmilk')));
    const view = editor();
    act(() => view.dispatch({ selection: { anchor: view.state.doc.length } }));
    act(() => button('Bookmark this line').click());
    expect(view.state.doc.toString()).toContain('§§');
    expect(document.body.textContent).toContain('Bookmarked at');
    const again = button('Move the bookmark to this line, or take it off here');
    expect(again.getAttribute('aria-pressed')).toBe('true');
    act(() => again.click());
    expect(view.state.doc.toString()).not.toContain('§§');
    expect(document.body.textContent).toContain('Bookmark taken off.');
  });

  it('bookmarks the caret’s line, not the line at the top of the page', async () => {
    show(screen(await createNote('n1', '# Groceries\nmilk\neggs\nbread')));
    const view = editor();
    // Scrolled down, with the caret's line on screen: the page's top is one place, the caret another (jsdom lays
    // nothing out, so the page says its own scroll and height).
    const page = document.querySelector<HTMLElement>('[data-scrolls]')!;
    Object.defineProperty(page, 'scrollTop', { configurable: true, value: 100 });
    Object.defineProperty(page, 'clientHeight', { configurable: true, value: 800 });
    act(() => view.dispatch({ selection: { anchor: view.state.doc.line(3).from } }));
    act(() => button('Bookmark this line').click());
    expect(view.state.doc.line(3).text).toContain('§§');
    expect(view.state.doc.line(1).text).not.toContain('§§');
    expect(document.body.textContent).toContain('Bookmarked at “eggs”.');
  });

  it('asks for words before a bookmark on an empty note', async () => {
    show(screen(await createNote('n1', '')));
    act(() => button('Bookmark this line').click());
    expect(document.body.textContent).toContain('Write something first, then bookmark the line.');
  });
});

describe('the More sheet from the note', () => {
  it('makes a board of the list, says how many, and is offered only where there is a list', async () => {
    show(screen(await createNote('n1', '# Groceries\n- [ ] milk\n- [x] eggs')));
    act(() => button('More for this note').click());
    act(() => buttonSaying(document.body, 'Make a board')!.click());
    expect(editor().state.doc.toString()).toContain('```board');
    expect(document.body.textContent).toContain('2 items are now cards, 1 in Done.');
    unmount();
    show(screen(await createNote('n2', '# Just words')));
    act(() => button('More for this note').click());
    expect(buttonSaying(document.body, 'Make a board')).toBeUndefined();
  });
});

describe('a chapter of a book', () => {
  it('is where its book was left, so the book opens at it again from outside', async () => {
    const book = await createNote('bk', '---\nbook: true\n---\n# Trip\n\n1. [[Day one]]\n2. [[Day two]]\n');
    const chapter = await createNote('d1', '# Day one\nwords');
    show(screen(chapter, { book: bookOf([book, chapter], 'Day one'), hasTitle: () => true, onOpenTitle: () => {} }));
    expect(readBookSpot('bk')).toEqual({ kind: 'chapter', title: 'Day one' });
  });
});

describe('a spoken note’s recording', () => {
  async function spoken(): Promise<Note> {
    await createNote('n1', '# Walk\nwords');
    return (await setNoteRecording('n1', 4000, [{ text: 'words', startMs: 0, endMs: 4000 }]))!;
  }

  it('has the tape, and the tape’s Add in place of the mic', async () => {
    show(screen(await spoken()));
    expect(document.querySelector('section[aria-label="Recording"]')).not.toBeNull();
    expect(document.querySelector('[aria-label="Talk into this note"]')).toBeNull();
    expect(button('Record more into this note')).toBeTruthy();
  });

  it('has the tape’s Summarize word only where the AI can run', async () => {
    const note = await spoken();
    show(screen(note));
    expect(document.querySelector('[aria-label="Summarize the recording"]')).toBeNull();
    unmount();
    ai.ok = true;
    show(screen(note));
    expect(button('Summarize the recording')).toBeTruthy();
  });

  it('gives the page to the transcript while it plays, and the view switch waits till it stops', async () => {
    // The transcript keeps the phrase being played in view (tapes/NoteTape.tsx), and jsdom does no scrolling.
    Element.prototype.scrollIntoView = () => undefined;
    try {
      show(screen(await spoken()));
      const viewSwitch = () => document.querySelector<HTMLButtonElement>('header button')!;
      expect(viewSwitch().disabled).toBe(false);
      act(() => button('Play the recording').click());
      expect(editor().dom.closest('[hidden]')).not.toBeNull();
      expect(viewSwitch().disabled).toBe(true);
      act(() => button('Pause the recording').click());
      expect(editor().dom.closest('[hidden]')).toBeNull();
      expect(viewSwitch().disabled).toBe(false);
    } finally {
      Reflect.deleteProperty(Element.prototype, 'scrollIntoView');
    }
  });

  it('comes off at once on Remove, and its Undo puts it back', async () => {
    const note = await spoken();
    // The tape's id goes with it, so the note's voice memos fall quiet, and comes back with the Undo (core/clips.ts).
    setTapeId('n1', 't1');
    show(screen(note));
    await act(async () => button("Remove this note's recording").click());
    await settle();
    expect(document.querySelector('section[aria-label="Recording"]')).toBeNull();
    expect((await getNote('n1'))?.recordingMs ?? null).toBeNull();
    expect(document.body.textContent).toContain('Recording removed.');
    expect(tapeId('n1')).toBeNull();
    await act(async () => button('Undo').click());
    await settle();
    expect(document.querySelector('section[aria-label="Recording"]')).not.toBeNull();
    expect((await getNote('n1'))?.recordingMs).toBe(4000);
    expect(tapeId('n1')).toBe('t1');
  });
});

describe('the canvases framed in the note', () => {
  /** App's lookups, as it hands them down on each of its renders. */
  const lookups = () => ({
    hasTitle: () => true,
    onOpenTitle: () => {},
    bodyOfTitle: vi.fn((title: string) => (title === 'Map' ? '{"nodes":[],"edges":[]}' : null)),
  });

  it('are read again when App draws, not each time the screen does', async () => {
    const note = await createNote('n1', '# Trip\n![[Map]]\nwords');
    const first = lookups();
    show(screen(note, first));
    const read = first.bodyOfTitle.mock.calls.length;
    expect(read).toBeGreaterThan(0);
    // The screen draws again on its own - the More sheet opening, a tape's playhead moving - with App's lookups the same.
    act(() => button('More for this note').click());
    expect(first.bodyOfTitle).toHaveBeenCalledTimes(read);
    // App hands down new lookups each time it draws, as it does when the notes change: a framed canvas may have been
    // drawn on, so it is read again.
    const next = lookups();
    rerender(screen(note, next));
    expect(next.bodyOfTitle).toHaveBeenCalledWith('Map');
  });
});

describe('a note a recording just wrote into', () => {
  const HOUSE = '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician\n';
  const landing = (over: Partial<CaptureLanding> = {}) => ({ noteId: 'house', title: 'House TODOs', blocks: ['- [ ] Call an electrician'], others: [], made: [], key: 1, ...over });
  /** The toast's text, and its Undo. */
  const toastText = () => [...document.querySelectorAll('[role="status"], [role="alert"]')].map((toast) => toast.textContent).join(' ');

  it('says what was added, and its Undo takes it out in the editor, saved like typing, with the next keystroke saved too', async () => {
    const note = await createNote('house', HOUSE);
    show(screen(note, { landing: landing() }));
    await settle();
    expect(toastText()).toContain('Added to House TODOs');
    act(() => buttonSaying(document, 'Undo')!.click());
    await settle();
    expect(editor().state.doc.toString()).toBe('# House TODOs\n\n- [ ] Fix the gutter\n');
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect((await getNote('house'))?.body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n');
    type('- [ ] Clear the drains');
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect((await getNote('house'))?.body).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Clear the drains');
  });

  it('leaves a piece edited since as it is, and says so', async () => {
    const note = await createNote('house', HOUSE);
    show(screen(note, { landing: landing() }));
    await settle();
    const view = editor();
    act(() => view.dispatch({ changes: { from: view.state.doc.length - 1, insert: ' tomorrow' } }));
    act(() => buttonSaying(document, 'Undo')!.click());
    await settle();
    expect(editor().state.doc.toString()).toBe('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician tomorrow\n');
    expect(toastText()).toContain('House TODOs has changed since, so it was left as it is.');
  });

  it('undoes what it wrote into other notes through the guarded undo', async () => {
    await createNote('work', '# Work');
    const written = await applyCommandMutation({ mutationId: 'm1', noteId: 'work', kind: 'append', beforeRevision: 1, beforeBody: '# Work', afterBody: '# Work\n\n- Call Sam', source: 'editor' });
    expect(written.status).toBe('applied');
    const note = await createNote('house', HOUSE);
    show(screen(note, { landing: landing({ others: ['m1'] }) }));
    await settle();
    expect(toastText()).toContain('Added to House TODOs and one other note');
    act(() => buttonSaying(document, 'Undo')!.click());
    await settle();
    expect((await getNote('work'))?.body).toBe('# Work');
  });

  it('drops the recording’s better words only for words its Undo took out of this note', async () => {
    drops.length = 0;
    const note = await createNote('house', HOUSE);
    show(screen(note, { landing: landing({ fromMs: 4000 }) }));
    await settle();
    act(() => buttonSaying(document, 'Undo')!.click());
    await settle();
    expect(drops).toEqual([['house', 4000]]);
    unmount();

    drops.length = 0;
    await createNote('work', '# Work');
    const written = await applyCommandMutation({ mutationId: 'm2', noteId: 'work', kind: 'append', beforeRevision: 1, beforeBody: '# Work', afterBody: '# Work\n\n- Call Sam', source: 'editor' });
    expect(written.status).toBe('applied');
    const own = await createNote('own', '# Kevin owns the release');
    show(screen(own, { landing: landing({ noteId: 'own', title: 'Kevin owns the release', blocks: [], others: ['m2'], fromMs: 0 }) }));
    await settle();
    act(() => buttonSaying(document, 'Undo')!.click());
    await settle();
    expect((await getNote('work'))?.body).toBe('# Work');
    expect(drops).toEqual([]);
  });

  it('holds the better words off the note while it is open', async () => {
    const note = await createNote('house', HOUSE);
    show(screen(note));
    expect(holds).toContainEqual(['house', true]);
    unmount();
    expect(holds.at(-1)).toEqual(['house', false]);
  });
});

describe('a meeting the phone wrote up while it was open', () => {
  it('shows the transcript as it arrives when nothing typed is waiting, and leaves it to the next save when something is', async () => {
    const note = await createNote('m1', '# Meeting, 26 Sep 14:05\n', 'capture');
    show(screen(note));
    // Rust appends the transcript under the note: the revision moves on, and the page is told the note changed.
    const stored = await updateNote('m1', '# Meeting, 26 Sep 14:05\n\n## Transcript\n\nWe agreed.', note.revision ?? 1);
    for (const listener of recordingListeners) listener('m1');
    await settle();
    expect(editor().state.doc.toString()).toBe(stored.body);
    // Typed since, not yet saved: the stored note is not taken over the words in hand.
    type('\n\nMine.');
    await updateNote('m1', `${stored.body}\n\nMore was said.`, stored.revision ?? 2);
    for (const listener of recordingListeners) listener('m1');
    await settle();
    expect(editor().state.doc.toString()).toBe(`${stored.body}\n\nMine.`);
  });
});

describe('the review’s scene', () => {
  const review = { key: 1, noteId: 'n1', job: null, heard: 'Groceries for the week. Milk, eggs and coffee.', commands: [], touched: [] };
  const scene = () => document.querySelector<HTMLElement>('[aria-label="The models at work on this note"]');

  it('mounts the scene in the first render with a review key, and a back gesture closes it before the note', async () => {
    const note = await createNote('n1', '# Groceries');
    const onBack = vi.fn();
    show(screen(note, { onBack, review }));
    expect(scene()).not.toBeNull();
    expect(scene()?.textContent).toContain('Checking what was heard.');
    expect(document.querySelector('.cm-editor')).not.toBeNull();
    act(() => {
      goBack();
    });
    expect(scene()).toBeNull();
    expect(onBack).not.toHaveBeenCalled();
    // The note is still there under it, its editor and its strip's place in the screen.
    expect(document.querySelector('.cm-editor')).not.toBeNull();
    act(() => {
      goBack();
    });
    expect(onBack).toHaveBeenCalledOnce();
  });

  it('goes behind the note on Back to the note, leaving the note as it was', async () => {
    const note = await createNote('n1', '# Groceries');
    const onBack = vi.fn();
    show(screen(note, { onBack, review }));
    press(button('Back to the note', scene()!));
    expect(scene()).toBeNull();
    expect(onBack).not.toHaveBeenCalled();
    expect(document.querySelector('.cm-editor')).not.toBeNull();
  });
});

describe('where the note was written', () => {
  const TAGGED = '---\nlocation: 51.5074,-0.1278\n---\n# Groceries\n';
  const card = () => document.querySelector<HTMLElement>('[class*=mapCard][data-mode]');
  /** The device answers a fix, or refuses (jsdom has no geolocation). */
  const fixAt = (lat: number, lon: number, code?: number) => {
    Object.defineProperty(navigator, 'geolocation', {
      configurable: true,
      value: {
        getCurrentPosition: (ok: PositionCallback, fail: PositionErrorCallback) => {
          if (code) fail({ code, message: '' } as GeolocationPositionError);
          else ok({ coords: { latitude: lat, longitude: lon, accuracy: 15 }, timestamp: 1 } as GeolocationPosition);
        },
      },
    });
  };
  /** Nominatim, stood in for: the name it gives, and every address it was asked. */
  const nominatim = (name: string | null) => {
    const asked: string[] = [];
    vi.stubGlobal('fetch', async (url: string) => {
      asked.push(url);
      return { ok: true, json: async () => (name ? { name, addresstype: 'square', address: { city: 'London' } } : {}) };
    });
    return asked;
  };
  /** The queue of better-words passes as the phone keeps it (capture/refine.ts), with one for `id`, or none. */
  const queued = (id: string | null) => {
    if (id) localStorage.setItem('glyph-refine-queue', JSON.stringify([{ id, fromMs: 0, recordingMs: 1000, baseBody: '', savedBody: '# Said', titled: true, priorSegments: [], promptTail: '', tries: 0 }]));
    else localStorage.removeItem('glyph-refine-queue');
  };
  const addFromSheet = () => {
    act(() => button('More for this note').click());
    act(() => buttonSaying(document.body, 'Add my location')!.click());
  };

  /*
   * Nominatim is asked a second after the last ask across the app, by the clock (core/location.ts), and that module
   * is not imported afresh for each test here. So every test in this block runs an hour after the last on a clock of
   * its own: a wait left by an earlier test's ask is always over, however fast or slow the run.
   */
  let hours = 0;
  const start = Date.now();
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
    hours += 1;
    vi.setSystemTime(start + hours * 60 * 60_000);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    Reflect.deleteProperty(navigator, 'geolocation');
  });

  it('draws the map card at the top of a tagged note, and not over a canvas or a book’s index', async () => {
    show(screen(await createNote('n1', TAGGED)));
    expect(card()).not.toBeNull();
    expect(card()?.textContent).toContain('51.5074, -0.1278');
    // The words' column: the card sits before the editor.
    expect(card()!.compareDocumentPosition(document.querySelector('.cm-editor')!) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    unmount();
    show(screen(await createNote('c1', '---\nlocation: 51.5074,-0.1278\n---\n{"nodes":[],"edges":[]}')));
    expect(card()).toBeNull();
    unmount();
    show(screen(await createNote('b1', '---\nbook: true\nlocation: 51.5074,-0.1278\n---\n# Trip\n\n1. [[Packing]]\n')));
    expect(card()).toBeNull();
    unmount();
    show(screen(await createNote('n2', '# Groceries')));
    expect(card()).toBeNull();
  });

  it('adds the location from the More sheet as one undo step, saved like typing, with its name when it comes and no toast', async () => {
    fixAt(51.50741, -0.12776);
    const asked = nominatim('Trafalgar Square');
    show(screen(await createNote('n1', '# Groceries\n- milk')));
    const view = editor();
    act(() => view.dispatch({ selection: { anchor: view.state.doc.length } }));
    addFromSheet();
    await settle();
    // The fix, and its name, asked once of Nominatim at three decimals and written in as it came.
    expect(asked).toEqual(['https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=51.507&lon=-0.128&zoom=15&addressdetails=1']);
    expect(view.state.doc.toString()).toBe('---\nlocation: 51.5074,-0.1278\nplace: "Trafalgar Square, London"\n---\n# Groceries\n- milk');
    // The caret stayed on its words, moved with the block written above them.
    expect(view.state.selection.main.head).toBe(view.state.doc.length);
    expect(card()?.textContent).toContain('Trafalgar Square, London');
    expect(document.body.textContent).not.toContain('Location added');
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect(saved()).toEqual(['---\nlocation: 51.5074,-0.1278\nplace: "Trafalgar Square, London"\n---\n# Groceries\n- milk']);
    // Two undo steps: the name, then the location; the words untouched throughout.
    act(() => void undo(view));
    expect(view.state.doc.toString()).toBe('---\nlocation: 51.5074,-0.1278\n---\n# Groceries\n- milk');
    act(() => void undo(view));
    expect(view.state.doc.toString()).toBe('# Groceries\n- milk');
    expect(card()).toBeNull();
  });

  it('takes the location off from the sheet, both keys and the block, and says why a fix did not come', async () => {
    show(screen(await createNote('n1', '---\nlocation: 51.5074,-0.1278\nplace: "London"\n---\n# Groceries\n')));
    act(() => button('More for this note').click());
    expect(buttonSaying(document.body, 'Remove location')?.textContent).toContain('London');
    act(() => buttonSaying(document.body, 'Remove location')!.click());
    expect(editor().state.doc.toString()).toBe('# Groceries\n');
    // The card leaves on the beat it came on, and then is gone.
    expect(card()?.hasAttribute('data-leave')).toBe(true);
    act(() => vi.advanceTimersByTime(300));
    expect(card()).toBeNull();
    fixAt(0, 0, 1);
    addFromSheet();
    await settle();
    expect(document.body.textContent).toContain('Ghost.md wasn’t allowed to know where you are.');
    expect(editor().state.doc.toString()).toBe('# Groceries\n');
  });

  it('shows a tag waiting for the better words from what is kept aside, and writes it once the pass has landed', async () => {
    const { setPendingTag, pendingTag } = await import('../core/location.ts');
    queued('n1');
    setPendingTag('n1', { lat: 48.8566, lon: 2.3522, place: null, rough: false });
    show(screen(await createNote('n1', '# Said\n')));
    await settle();
    expect(card()?.textContent).toContain('48.8566, 2.3522');
    expect(editor().state.doc.toString()).toBe('# Said\n');
    unmount();
    // The pass landed while the note was closed: the next open writes the tag.
    queued(null);
    const fresh = await getNote('n1');
    show(screen(fresh!));
    await settle();
    expect(editor().state.doc.toString()).toBe('---\nlocation: 48.8566,2.3522\n---\n# Said\n');
    expect(pendingTag('n1')).toBeNull();
  });

  it('review path, listening fails, better words still land: the tag waits until the review hands its job back', async () => {
    const { setPendingTag } = await import('../core/location.ts');
    setPendingTag('n1', { lat: 40.7128, lon: -74.006, place: null, rough: false });
    const job = { id: 'n1', fromMs: 0, recordingMs: 4000, baseBody: '', savedBody: '# Said', titled: true, priorSegments: [], promptTail: '' };
    show(screen(await createNote('n1', '# Said\n'), { review: { key: 1, noteId: 'n1', job, heard: 'said', commands: [], touched: [] } }));
    expect(card()?.textContent).toContain('40.7128, -74.0060');
    expect(editor().state.doc.toString()).toBe('# Said\n');
    // The review ends and hands back (ai/useNoteReview.ts): in a browser the queue takes nothing, so the tag lands now.
    await waitUntil(() => expect(editor().state.doc.toString()).toBe('---\nlocation: 40.7128,-74.0060\n---\n# Said\n'));
  });

  it('waits for a new note’s first words, so an empty note is not made a file by its tag', async () => {
    const { setPendingTag } = await import('../core/location.ts');
    setPendingTag('n1', { lat: 35.6762, lon: 139.6503, place: null, rough: false });
    show(screen(await createNote('n1', '')));
    await settle();
    expect(card()).not.toBeNull();
    expect(editor().state.doc.toString()).toBe('');
    type('Hello');
    await settle();
    expect(editor().state.doc.toString()).toBe('---\nlocation: 35.6762,139.6503\n---\nHello');
  });

  it('writes a canvas’s tag through the screen’s own saving, since its editor is hidden', async () => {
    fixAt(52.52, 13.405);
    nominatim(null);
    show(screen(await createNote('c1', '{"nodes":[],"edges":[]}')));
    addFromSheet();
    await settle();
    act(() => vi.advanceTimersByTime(400));
    await settle();
    expect(saved()).toEqual(['---\nlocation: 52.5200,13.4050\n---\n{"nodes":[],"edges":[]}']);
  });

  it('draws a new note’s tag the moment it comes, and never writes one over a tag the note already has', async () => {
    const { tagNewNotes, pendingTag } = await import('../core/location.ts');
    const { setPreferences } = await import('../core/preferences.ts');
    setPreferences({ placeNames: false });
    show(screen(await createNote('n1', '')));
    expect(card()).toBeNull();
    // The shell's new-note tag, arriving while the note is open and still blank (App.tsx `newNote`).
    await act(async () => tagNewNotes(['n1'], Promise.resolve({ lat: 35.6762, lon: 139.6503, accuracy: 12, at: 0 }), { reviewing: false }));
    await settle();
    expect(card()?.textContent).toContain('35.6762, 139.6503');
    expect(editor().state.doc.toString()).toBe('');
    unmount();
    const here = '---\nlocation: 10.0000,20.0000\n---\n# Here\n';
    show(screen(await createNote('n2', here)));
    await act(async () => tagNewNotes(['n2'], Promise.resolve({ lat: 1, lon: 2, accuracy: 12, at: 0 }), { reviewing: false }));
    await settle();
    expect(editor().state.doc.toString()).toBe(here);
    expect(pendingTag('n2')).toBeNull();
    setPreferences({ placeNames: true });
  });

  it('holds a new note’s box from its first frame, the box its tag arrives in, and says when no place came', async () => {
    const { holdFor, tagNewNotes, LocateError } = await import('../core/location.ts');
    const box = () => document.querySelector<HTMLElement>('[class*=mapCard]');
    holdFor(['held1']);
    show(screen(await createNote('held1', ''), { caret: 0 }));
    // A picture of the card's own box: nothing to press, nothing read out.
    expect(box()?.hasAttribute('inert')).toBe(true);
    expect(box()?.querySelector('button')).toBeNull();
    expect(box()?.textContent).toBe('');
    await act(async () => tagNewNotes(['held1'], Promise.resolve({ lat: 51.52, lon: -0.1, accuracy: 12, at: 0 }), { reviewing: false }));
    await settle();
    // Found: the card itself, in the same box, arriving without the beat that would move the words.
    expect(box()?.querySelector('button')).not.toBeNull();
    expect(box()?.hasAttribute('data-arrive')).toBe(false);
    unmount();
    holdFor(['held2']);
    show(screen(await createNote('held2', ''), { caret: 0 }));
    await act(async () => tagNewNotes(['held2'], Promise.reject(new LocateError('timeout')), { reviewing: false }));
    await settle();
    expect(box()?.textContent).toBe('No place yet.');
    unmount();
    // Left, and opened again: no box at all.
    show(screen((await getNote('held2'))!));
    expect(box()).toBeNull();
  });

  it('sends nothing for a new note’s tag until it has words: the card quiet, no tiles, no name, then both once it lands', async () => {
    const { tagNewNotes, pendingTag } = await import('../core/location.ts');
    const asked = nominatim('Somerset House');
    show(screen(await createNote('w1', '')));
    await act(async () => tagNewNotes(['w1'], Promise.resolve({ lat: 51.511, lon: -0.1171, accuracy: 12, at: 0 }), { reviewing: false }));
    await settle();
    // A draft that may never be kept: the card is there, quiet, and nothing has been asked of OpenStreetMap.
    expect(card()?.getAttribute('data-mode')).toBe('quiet');
    expect(card()?.textContent).toContain('51.5110, -0.1171');
    expect(asked).toHaveLength(0);
    expect(pendingTag('w1')?.place).toBeNull();
    expect(editor().state.doc.toString()).toBe('');
    type('Hello');
    await settle();
    // Kept now: the tag is in the note, the map is drawn, and the name is asked once and written in.
    expect(card()?.getAttribute('data-mode')).toBe('map');
    await act(async () => vi.advanceTimersByTimeAsync(1200));
    await settle();
    expect(asked).toHaveLength(1);
    expect(editor().state.doc.toString()).toBe('---\nlocation: 51.5110,-0.1171\nplace: "Somerset House, London"\n---\nHello');
  });

  it('keeps an untouched entry’s tag waiting, its card quiet and its place unnamed, until its first own words', async () => {
    const { tagNewNotes, pendingTag } = await import('../core/location.ts');
    const { rememberUntouched } = await import('../core/untouched.ts');
    const asked = nominatim('Somerset House');
    const words = '# Monday 28 September\n\n**14:05** ';
    const made = `---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\n---\n${words}`;
    rememberUntouched('en1', { journalId: 'diary', title: '2026-09-28 14.05', words, at: Date.now() });
    show(screen(await createNote('en1', made)));
    // A place no other test here has named: names already known this run are not asked again.
    await act(async () => tagNewNotes(['en1'], Promise.resolve({ lat: 51.5033, lon: -0.1196, accuracy: 12, at: 0 }), { reviewing: false }));
    await settle();
    expect(card()?.getAttribute('data-mode')).toBe('quiet');
    expect(asked).toHaveLength(0);
    expect(pendingTag('en1')).not.toBeNull();
    expect(editor().state.doc.toString()).toBe(made);
    // Not the blank note's ghost: the entry has words.
    expect(document.querySelector('[class*=blankGhost]')).toBeNull();
    type('Walked along the river.');
    await settle();
    expect(card()?.getAttribute('data-mode')).toBe('map');
    expect(editor().state.doc.toString()).toContain('location: 51.5033,-0.1196');
    await act(async () => vi.advanceTimersByTimeAsync(1200));
    await settle();
    expect(asked).toHaveLength(1);
  });

  it('makes an entry the person’s on its first own word, before the save: left at once, it is not taken back', async () => {
    const { rememberUntouched, untouchedRecord } = await import('../core/untouched.ts');
    const words = '# Monday 28 September\n\n**14:05** ';
    const made = `---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\n---\n${words}`;
    rememberUntouched('en2', { journalId: 'diary', title: '2026-09-28 14.05', words, at: Date.now() });
    show(screen(await createNote('en2', made)));
    expect(untouchedRecord('en2')).not.toBeNull();
    type('W');
    // Nothing saved yet (400 ms), and the record is gone already: App's take-back reads the store and the record, and
    // Home pressed now finds no record to act on while the save on the way out is still a turn behind.
    expect(saves).not.toHaveBeenCalled();
    expect(untouchedRecord('en2')).toBeNull();
    unmount();
    await settle();
    expect((await getNote('en2'))?.body).toBe(`${made}W`);
  });

  it('takes a new note’s waiting tag with it when the note is left without a word', async () => {
    const { tagNewNotes, pendingTag } = await import('../core/location.ts');
    show(screen(await createNote('w2', '')));
    await act(async () => tagNewNotes(['w2'], Promise.resolve({ lat: 51.511, lon: -0.1171, accuracy: 12, at: 0 }), { reviewing: false }));
    await settle();
    expect(pendingTag('w2')).not.toBeNull();
    unmount();
    expect(pendingTag('w2')).toBeNull();
  });

  it('keeps the caret with the words when a tag is written above a note that had no front matter', async () => {
    fixAt(53.48081, -2.24263);
    nominatim(null);
    show(screen(await createNote('c0', '# Walk\n\nThe words.')));
    const view = editor();
    act(() => view.dispatch({ selection: { anchor: 0 } }));
    addFromSheet();
    await settle();
    const block = '---\nlocation: 53.4808,-2.2426\n---\n';
    expect(view.state.doc.toString()).toBe(`${block}# Walk\n\nThe words.`);
    // The caret is at the start of the words, not in front of the new fence: a keystroke there is words, and the
    // block stays a block (a share would carry a broken one's location as words).
    expect(view.state.selection.main.head).toBe(block.length);
    act(() => view.dispatch({ changes: { from: view.state.selection.main.head, insert: 'Hi ' }, userEvent: 'input.type' }));
    expect(view.state.doc.toString()).toBe(`${block}Hi # Walk\n\nThe words.`);
    expect(card()?.textContent).toContain('53.4808, -2.2426');
  });

  it('keeps a location added just before the note was left, and writes it into the note', async () => {
    let answer: ((position: GeolocationPosition) => void) | null = null;
    Object.defineProperty(navigator, 'geolocation', {
      configurable: true,
      value: {
        getCurrentPosition: (ok: PositionCallback) => {
          answer = ok;
        },
      },
    });
    nominatim(null);
    show(screen(await createNote('n1', '# Groceries\n- milk')));
    addFromSheet();
    await settle();
    unmount();
    // The fix comes after the note was left: it is not lost, and not written into a destroyed editor.
    await act(async () => answer!({ coords: { latitude: 55.95331, longitude: -3.18827, accuracy: 15 }, timestamp: 1 } as GeolocationPosition));
    await settle();
    expect((await getNote('n1'))?.body).toBe('---\nlocation: 55.9533,-3.1883\n---\n# Groceries\n- milk');
  });

  it('holds a location added by hand while a pass is queued or a review is live, so the better words still land', async () => {
    const { pendingTag } = await import('../core/location.ts');
    fixAt(48.8566, 2.3522);
    nominatim(null);
    queued('n1');
    show(screen(await createNote('n1', '# Said\n')));
    addFromSheet();
    await settle();
    // Drawn at once from the tag kept aside; the note reads as Done saved it, so the pass's compare still holds.
    expect(card()?.textContent).toContain('48.8566, 2.3522');
    expect(editor().state.doc.toString()).toBe('# Said\n');
    expect(pendingTag('n1')).not.toBeNull();
    unmount();
    queued(null);
    // And with a review live for the note, still listening again: held until it hands its job back.
    let letGo: (value: null) => void = () => undefined;
    listening.hold = new Promise<null>((resolve) => {
      letGo = resolve;
    });
    try {
      const job = { id: 'n2', fromMs: 0, recordingMs: 4000, baseBody: '', savedBody: '# Said', titled: true, priorSegments: [], promptTail: '' };
      show(screen(await createNote('n2', '# Said\n'), { review: { key: 2, noteId: 'n2', job, heard: 'said', commands: [], touched: [] } }));
      addFromSheet();
      await settle();
      expect(editor().state.doc.toString()).toBe('# Said\n');
      expect(pendingTag('n2')).not.toBeNull();
      // Listening fails (a browser cannot), the review hands back, and the tag lands then.
      letGo(null);
      await waitUntil(() => expect(editor().state.doc.toString()).toBe('---\nlocation: 48.8566,2.3522\n---\n# Said\n'));
    } finally {
      listening.hold = null;
    }
  });

  it('writes a name that came while the note was closed when it opens, and only onto the tag it was asked for', async () => {
    const { wantPlace, placeFor } = await import('../core/location.ts');
    nominatim('Pont Neuf');
    const PARIS = { lat: 48.8572, lon: 2.3413, place: null, rough: false };
    await createNote('p1', '---\nlocation: 48.8572,2.3413\n---\n# Seine\n');
    // Asked while the note was closed and a pass was queued for it: the name waits in memory, and the note is left be.
    queued('p1');
    wantPlace('p1', PARIS);
    await act(async () => vi.advanceTimersByTimeAsync(1200));
    await settle();
    expect(placeFor(PARIS)).toBe('Pont Neuf, London');
    expect((await getNote('p1'))?.body).toBe('---\nlocation: 48.8572,2.3413\n---\n# Seine\n');
    queued(null);
    show(screen((await getNote('p1'))!));
    await settle();
    expect(editor().state.doc.toString()).toBe('---\nlocation: 48.8572,2.3413\nplace: "Pont Neuf, London"\n---\n# Seine\n');
    unmount();
    // A name for other coordinates is not this note's.
    await createNote('p2', '---\nlocation: 40.7128,-74.0060\n---\n# NYC\n');
    show(screen((await getNote('p2'))!));
    await settle();
    wantPlace('p2', PARIS);
    await settle();
    expect(editor().state.doc.toString()).toBe('---\nlocation: 40.7128,-74.0060\n---\n# NYC\n');
  });

  it('draws the quiet card under Local only, fetching nothing, and none over the transcript', async () => {
    const { setPreferences } = await import('../core/preferences.ts');
    setPreferences({ localOnly: true });
    try {
      show(screen(await createNote('n1', TAGGED)));
      expect(card()?.getAttribute('data-mode')).toBe('quiet');
      expect(card()?.textContent).toContain('Local only is on.');
    } finally {
      setPreferences({ localOnly: false });
    }
    unmount();
    Element.prototype.scrollIntoView = () => undefined;
    try {
      await createNote('t1', TAGGED);
      show(screen((await setNoteRecording('t1', 4000, [{ text: 'words', startMs: 0, endMs: 4000 }]))!));
      expect(card()).not.toBeNull();
      act(() => button('Play the recording').click());
      expect(card()).toBeNull();
      act(() => button('Pause the recording').click());
      expect(card()).not.toBeNull();
    } finally {
      Reflect.deleteProperty(Element.prototype, 'scrollIntoView');
    }
  });

  it('says on the sheet why a note made since a refusal was not tagged, and nothing of it on an older note', async () => {
    const { rememberRefusal } = await import('../core/location.ts');
    fixAt(51.5074, -0.1278);
    const old = { ...(await createNote('old', '# Last year\n')), createdAt: Date.now() - 60 * 60_000 };
    rememberRefusal('refused');
    show(screen(await createNote('new', '# Today\n')));
    act(() => button('More for this note').click());
    expect(buttonSaying(document.body, 'Add my location')?.textContent).toContain('so this note wasn’t tagged');
    unmount();
    show(screen(old));
    act(() => button('More for this note').click());
    expect(buttonSaying(document.body, 'Add my location')?.textContent).not.toContain('wasn’t tagged');
  });

  it('follows a location typed by hand into the front matter', async () => {
    show(screen(await createNote('n1', '# Groceries')));
    expect(card()).toBeNull();
    const view = editor();
    act(() => view.dispatch({ changes: { from: 0, insert: '---\nlocation: 48.8566,2.3522\n---\n' }, userEvent: 'input.type' }));
    expect(card()?.textContent).toContain('48.8566, 2.3522');
  });

  describe('a place from the + beside the line', () => {
    /** The note focused with the caret on its last, empty line, the + come beside it, and pressed. */
    const openPlus = async (view: EditorView) => {
      vi.spyOn(document, 'hasFocus').mockReturnValue(true);
      act(() => {
        view.dispatch({ selection: { anchor: view.state.doc.length } });
        view.focus();
      });
      // CodeMirror tells its plugins of the focus 10ms on, and the + comes once the caret has rested.
      await act(async () => vi.advanceTimersByTimeAsync(10 + 200));
      const plus = view.scrollDOM.querySelector<HTMLButtonElement>('.cm-plus');
      expect(plus?.dataset.state).toBe('shown');
      act(() => plus!.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 })));
    };
    const place = () => {
      const row = [...document.querySelectorAll<HTMLButtonElement>('#add-list button')].find((found) => found.textContent === 'A place');
      if (!row) throw new Error(`no place row in: ${document.getElementById('add-list')?.textContent ?? 'no list'}`);
      act(() => row.click());
    };

    it('is one line at the caret, named in the same write, one Undo, with its map card under it', async () => {
      fixAt(51.50741, -0.12776);
      nominatim('Trafalgar Square');
      show(screen(await createNote('n1', '# Walk\n\n')));
      const view = editor();
      await openPlus(view);
      place();
      await settle();
      expect(view.state.doc.toString()).toBe('# Walk\n\n[Trafalgar Square, London](geo:51.5074,-0.1278)\n');
      // The note's own tag is left alone: a place is a line of the words.
      expect(card()).toBeNull();
      expect(view.dom.querySelectorAll('.cm-placeCard')).toHaveLength(1);
      act(() => void undo(view));
      expect(view.state.doc.toString()).toBe('# Walk\n\n');
      vi.restoreAllMocks();
    });

    it('says so while the fix is slow', async () => {
      Object.defineProperty(navigator, 'geolocation', { configurable: true, value: { getCurrentPosition: () => undefined } });
      show(screen(await createNote('n1', '# Walk\n\n')));
      await openPlus(editor());
      place();
      await act(async () => vi.advanceTimersByTimeAsync(600));
      expect(document.body.textContent).toContain('Finding where you are.');
      vi.restoreAllMocks();
    });

    it('asks for nothing and writes nothing when the note is left before the fix', async () => {
      let answer: ((position: GeolocationPosition) => void) | null = null;
      Object.defineProperty(navigator, 'geolocation', { configurable: true, value: { getCurrentPosition: (ok: PositionCallback) => void (answer = ok) } });
      const asked = nominatim('Trafalgar Square');
      show(screen(await createNote('n1', '# Walk\n\nwords')));
      const view = editor();
      act(() => view.dispatch({ changes: { from: view.state.doc.length, insert: '\n' } }));
      await openPlus(view);
      place();
      await settle();
      unmount();
      await act(async () => answer!({ coords: { latitude: 51.5, longitude: -0.12, accuracy: 15 }, timestamp: 1 } as GeolocationPosition));
      await settle();
      expect(asked).toEqual([]);
      expect(saved().some((body) => body?.includes('geo:'))).toBe(false);
      vi.restoreAllMocks();
    });

    it('waits a few seconds for the name, so one that takes a second still lands with the place, as one Undo', async () => {
      // A place of its own, so no name is known already.
      fixAt(51.50135, -0.14189);
      vi.stubGlobal(
        'fetch',
        () => new Promise((resolve) => window.setTimeout(() => resolve({ ok: true, json: async () => ({ name: 'Buckingham Palace', addresstype: 'square', address: { city: 'London' } }) }), 1500)),
      );
      show(screen(await createNote('n1', '# Walk\n\n')));
      const view = editor();
      await openPlus(view);
      place();
      await settle();
      await act(async () => vi.advanceTimersByTimeAsync(1500));
      await settle();
      expect(view.state.doc.toString()).toBe('# Walk\n\n[Buckingham Palace, London](geo:51.5014,-0.1419)\n');
      act(() => void undo(view));
      expect(view.state.doc.toString()).toBe('# Walk\n\n');
      vi.restoreAllMocks();
    });

    it('writes a name later than the wait as a second step, only while nothing came after it', async () => {
      // A place of its own: a name another test asked for would be known already, and come at once.
      fixAt(51.51009, -0.13402);
      let named: (() => void) | null = null;
      vi.stubGlobal('fetch', () => new Promise((resolve) => void (named = () => resolve({ ok: true, json: async () => ({ name: 'Piccadilly Circus', addresstype: 'square', address: { city: 'London' } }) }))));
      show(screen(await createNote('n1', '# Walk\n\n')));
      const view = editor();
      await openPlus(view);
      place();
      await settle();
      await act(async () => vi.advanceTimersByTimeAsync(3000));
      await settle();
      expect(view.state.doc.toString()).toBe('# Walk\n\n[51.5101, -0.1340](geo:51.5101,-0.1340)\n');
      await act(async () => named!());
      await settle();
      expect(view.state.doc.toString()).toBe('# Walk\n\n[Piccadilly Circus, London](geo:51.5101,-0.1340)\n');
      act(() => void undo(view));
      expect(view.state.doc.toString()).toBe('# Walk\n\n[51.5101, -0.1340](geo:51.5101,-0.1340)\n');
      act(() => void undo(view));
      expect(view.state.doc.toString()).toBe('# Walk\n\n');
      vi.restoreAllMocks();
    });

    it('writes a late name all the same in an untouched entry, whose waiting tag lands after the place', async () => {
      const { tagNewNotes } = await import('../core/location.ts');
      const { rememberUntouched } = await import('../core/untouched.ts');
      const words = '# Monday 28 September\n\n**14:05** \n\n';
      const made = `---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\n---\n${words}`;
      rememberUntouched('en9', { journalId: 'diary', title: '2026-09-28 14.05', words, at: Date.now() });
      // Places of their own, so no name is known already: the entry's tag is named at once, the + place's late.
      fixAt(51.51383, -0.09837);
      let named: (() => void) | null = null;
      vi.stubGlobal('fetch', (url: string) =>
        String(url).includes('lat=51.514')
          ? new Promise((resolve) => void (named = () => resolve({ ok: true, json: async () => ({ name: 'St Paul’s', addresstype: 'square', address: { city: 'London' } }) })))
          : Promise.resolve({ ok: true, json: async () => ({ name: 'Parliament Square', addresstype: 'square', address: { city: 'London' } }) }),
      );
      show(screen(await createNote('en9', made)));
      await act(async () => tagNewNotes(['en9'], Promise.resolve({ lat: 51.49929, lon: -0.12729, accuracy: 12, at: 0 }), { reviewing: false }));
      await settle();
      const view = editor();
      await openPlus(view);
      place();
      await settle();
      await act(async () => vi.advanceTimersByTimeAsync(3000));
      await settle();
      // The place, then the tag that waited for the entry's first words, and the tag's name, each a step of its own.
      await act(async () => vi.advanceTimersByTimeAsync(2000));
      await settle();
      const coords = '[51.5138, -0.0984](geo:51.5138,-0.0984)';
      expect(view.state.doc.toString()).toBe(`---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\nlocation: 51.4993,-0.1273\nplace: "Parliament Square, London"\n---\n${words}${coords}\n`);
      await act(async () => named!());
      await settle();
      expect(view.state.doc.toString()).toContain(`${words}[St Paul’s, London](geo:51.5138,-0.0984)\n`);
      // The name is the newest step: the first Undo gives the coordinates back.
      act(() => void undo(view));
      expect(view.state.doc.toString()).toContain(`${words}${coords}\n`);
      vi.restoreAllMocks();
    });

    it('keeps the coordinates when the person did something after the place, the tag landing or not', async () => {
      const { tagNewNotes } = await import('../core/location.ts');
      const { rememberUntouched } = await import('../core/untouched.ts');
      const words = '# Monday 28 September\n\n**14:05** \n\n';
      const made = `---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\n---\n${words}`;
      rememberUntouched('en10', { journalId: 'diary', title: '2026-09-28 14.05', words, at: Date.now() });
      fixAt(51.50332, -0.11951);
      let named: (() => void) | null = null;
      vi.stubGlobal('fetch', (url: string) =>
        String(url).includes('lat=51.503')
          ? new Promise((resolve) => void (named = () => resolve({ ok: true, json: async () => ({ name: 'Waterloo', addresstype: 'square', address: { city: 'London' } }) })))
          : Promise.resolve({ ok: true, json: async () => ({ name: 'Bankside', addresstype: 'square', address: { city: 'London' } }) }),
      );
      show(screen(await createNote('en10', made)));
      await act(async () => tagNewNotes(['en10'], Promise.resolve({ lat: 51.50759, lon: -0.09935, accuracy: 12, at: 0 }), { reviewing: false }));
      await settle();
      const view = editor();
      await openPlus(view);
      place();
      await settle();
      await act(async () => vi.advanceTimersByTimeAsync(5000));
      await settle();
      expect(view.state.doc.toString()).toContain('place: "Bankside, London"');
      type('Lunch.');
      await act(async () => named!());
      await settle();
      expect(view.state.doc.toString()).toContain(`${words}[51.5033, -0.1195](geo:51.5033,-0.1195)\nLunch.`);
      vi.restoreAllMocks();
    });

    it('keeps the coordinates when the person took the note’s location off while the name was coming', async () => {
      fixAt(51.50451, -0.08649);
      let named: (() => void) | null = null;
      vi.stubGlobal('fetch', () => new Promise((resolve) => void (named = () => resolve({ ok: true, json: async () => ({ name: 'London Bridge', addresstype: 'square', address: { city: 'London' } }) }))));
      show(screen(await createNote('n1', '---\nlocation: 51.5074,-0.1278\nplace: "London"\n---\n# Walk\n\n')));
      const view = editor();
      await openPlus(view);
      place();
      await settle();
      await act(async () => vi.advanceTimersByTimeAsync(3000));
      await settle();
      act(() => button('More for this note').click());
      act(() => buttonSaying(document.body, 'Remove location')!.click());
      await act(async () => named!());
      await settle();
      expect(view.state.doc.toString()).toBe('# Walk\n\n[51.5045, -0.0865](geo:51.5045,-0.0865)\n');
      // The person's last step is the first Undo takes back.
      act(() => void undo(view));
      expect(view.state.doc.toString()).toContain('location: 51.5074,-0.1278');
      vi.restoreAllMocks();
    });

    it('leaves the caret where the person took it while the fix was coming', async () => {
      let answer: ((position: GeolocationPosition) => void) | null = null;
      Object.defineProperty(navigator, 'geolocation', { configurable: true, value: { getCurrentPosition: (ok: PositionCallback) => void (answer = ok) } });
      nominatim(null);
      show(screen(await createNote('n1', '# Walk\n\n')));
      const view = editor();
      await openPlus(view);
      place();
      await settle();
      act(() => view.dispatch({ changes: { from: 2, insert: 'Long ' }, selection: { anchor: 7 }, userEvent: 'input.type' }));
      await act(async () => answer!({ coords: { latitude: 51.5, longitude: -0.12, accuracy: 15 }, timestamp: 1 } as GeolocationPosition));
      await settle();
      expect(view.state.doc.toString()).toBe('# Long Walk\n\n[51.5000, -0.1200](geo:51.5000,-0.1200)\n');
      expect(view.state.selection.main.head).toBe(7);
      vi.restoreAllMocks();
    });
  });
});

describe('the + beside the line', () => {
  it('is drawn on the note screen, and nowhere the note is only read', async () => {
    show(screen(await createNote('n1', '# Walk\n\n')));
    expect(document.querySelectorAll('.cm-plus')).toHaveLength(1);
    unmount();
    show(screen(await createNote('b1', '---\nbook: true\n---\n# Trip\n\n1. [[Packing]]\n')));
    // A book's index draws its chapters through read-only editors: none has a +.
    expect(document.querySelectorAll('.cm-plus').length).toBeLessThanOrEqual(1);
    const plus = document.querySelector<HTMLButtonElement>('.cm-plus');
    expect(plus === null || plus.hidden).toBe(true);
  });

  /** The note focused with the caret on its last, empty line, and time for the + to come: its state then. */
  const restOnLastLine = async (view: EditorView) => {
    vi.spyOn(document, 'hasFocus').mockReturnValue(true);
    act(() => {
      view.dispatch({ selection: { anchor: view.state.doc.length } });
      view.focus();
    });
    await act(async () => vi.advanceTimersByTimeAsync(10 + 200));
    return view.scrollDOM.querySelector<HTMLButtonElement>('.cm-plus')?.dataset.state;
  };
  const plusState = (view: EditorView) => view.scrollDOM.querySelector<HTMLButtonElement>('.cm-plus')?.dataset.state;

  it('goes while an AI run writes into the note, and comes back once it has ended', async () => {
    show(screen(await createNote('n1', '# Walk\n\n')));
    const view = editor();
    expect(await restOnLastLine(view)).toBe('shown');
    // A model that writes nothing until it is stopped.
    simulateRuns(() => {
      let stop: (why: Error) => void = () => undefined;
      return { done: new Promise<never>((_resolve, reject) => void (stop = reject)), cancel: () => stop(new Error('cancelled')) };
    });
    try {
      act(() => void startRun({ noteId: 'n1', kind: 'format', model: 'qwen3.5-4b', system: '', prompt: '', maxTokens: 16 }));
      await act(async () => vi.advanceTimersByTimeAsync(1000));
      expect(plusState(view)).toBe('off');
      await act(async () => cancelRun('n1'));
      act(() => view.focus());
      await act(async () => vi.advanceTimersByTimeAsync(1000));
      expect(plusState(view)).toBe('shown');
    } finally {
      simulateRuns(null);
      forgetAllRuns();
      vi.restoreAllMocks();
    }
  });

  it('never comes over a notebook’s index shown as its Markdown, which is not a note being written', async () => {
    show(screen(await createNote('b1', '---\nbook: true\n---\n# Trip\n\n1. [[Packing]]\n'), { hasTitle: () => true, onOpenTitle: () => {} }));
    act(() => document.querySelector<HTMLButtonElement>('header button')!.click());
    expect(await restOnLastLine(editor())).toBe('off');
    vi.restoreAllMocks();
  });

  it('goes while the recording plays and the transcript has the page', async () => {
    Element.prototype.scrollIntoView = () => undefined;
    try {
      await createNote('n1', '# Walk\nwords\n');
      show(screen((await setNoteRecording('n1', 4000, [{ text: 'words', startMs: 0, endMs: 4000 }]))!));
      const view = editor();
      expect(await restOnLastLine(view)).toBe('shown');
      act(() => button('Play the recording').click());
      await act(async () => vi.advanceTimersByTimeAsync(1000));
      expect(plusState(view)).toBe('off');
    } finally {
      Reflect.deleteProperty(Element.prototype, 'scrollIntoView');
      vi.restoreAllMocks();
    }
  });
});

describe('a film from the + beside the line', () => {
  /** The note focused with the caret on its last, empty line, the + come beside it, and pressed. */
  const openPlus = async (view: EditorView) => {
    vi.spyOn(document, 'hasFocus').mockReturnValue(true);
    act(() => {
      view.dispatch({ selection: { anchor: view.state.doc.length } });
      view.focus();
    });
    await act(async () => vi.advanceTimersByTimeAsync(10 + 200));
    const plus = view.scrollDOM.querySelector<HTMLButtonElement>('.cm-plus');
    expect(plus?.dataset.state).toBe('shown');
    act(() => plus!.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 })));
  };
  const rows = () => [...document.querySelectorAll<HTMLButtonElement>('#add-list button')].map((row) => row.textContent);
  const video = () => {
    const row = [...document.querySelectorAll<HTMLButtonElement>('#add-list button')].find((found) => found.textContent === 'A video');
    if (!row) throw new Error(`no video row in: ${rows().join(', ')}`);
    act(() => row.click());
  };
  const PICKED = { video: 'f1.mp4', poster: 'p1.jpg', ms: 12_300, width: 1080, height: 1920 };

  it('is offered only where the binary adds films', async () => {
    show(screen(await createNote('n1', '# Walk\n\n')));
    await settle();
    await openPlus(editor());
    expect(rows()).not.toContain('A video');
    unmount();
    films.can = true;
    show(screen(await createNote('n2', '# Walk\n\n')));
    await settle();
    await openPlus(editor());
    expect(rows()).toContain('A video');
    vi.restoreAllMocks();
  });

  it('is one line at the caret, its poster linked to it, one Undo, with its card under it', async () => {
    films.can = true;
    films.pick = async () => PICKED;
    show(screen(await createNote('n1', '# Walk\n\n')));
    await settle();
    const view = editor();
    await openPlus(view);
    video();
    await settle();
    expect(view.state.doc.toString()).toBe('# Walk\n\n[![video 0:12](image/p1.jpg)](video/f1.mp4)\n');
    expect(view.state.selection.main.head).toBe(view.state.doc.length);
    expect(view.dom.querySelectorAll('.cm-videoCard')).toHaveLength(1);
    // Its card knows it was just added: as the poster arrives, the caret under it is kept in sight, once.
    const dispatch = vi.spyOn(view, 'dispatch');
    act(() => void view.dom.querySelector('.cm-videoCard img')!.dispatchEvent(new Event('load')));
    expect(dispatch).toHaveBeenCalledTimes(1);
    dispatch.mockRestore();
    act(() => void undo(view));
    expect(view.state.doc.toString()).toBe('# Walk\n\n');
    vi.restoreAllMocks();
  });

  it('says so while a long film is copied, not while the picker is up, and says what went wrong on the note’s line', async () => {
    films.can = true;
    let fail: ((why: Error) => void) | null = null;
    let copying: (() => void) | undefined;
    films.pick = (ways) => new Promise((_resolve, reject) => void ((fail = reject), (copying = ways.copying)));
    show(screen(await createNote('n1', '# Walk\n\n')));
    await settle();
    const view = editor();
    await openPlus(view);
    video();
    // The picker is up: nothing is being added yet.
    await act(async () => vi.advanceTimersByTimeAsync(2000));
    expect(document.body.textContent).not.toContain('Adding the video.');
    act(() => copying!());
    await act(async () => vi.advanceTimersByTimeAsync(599));
    expect(document.body.textContent).not.toContain('Adding the video.');
    await act(async () => vi.advanceTimersByTimeAsync(1));
    expect(document.body.textContent).toContain('Adding the video.');
    await act(async () => fail!(new Error('There isn’t room on this phone for that video.')));
    await settle();
    expect(document.body.textContent).toContain('There isn’t room on this phone for that video.');
    expect(view.state.doc.toString()).toBe('# Walk\n\n');
    vi.restoreAllMocks();
  });

  it('keeps no film for a note that was left while it copied, and writes none into it', async () => {
    films.can = true;
    let ways: import('../core/videos.ts').PickWays = {};
    let land: ((film: typeof PICKED) => void) | null = null;
    films.pick = (asked) => new Promise((resolve) => void ((ways = asked), (land = resolve)));
    show(screen(await createNote('n1', '# Walk\n\n')));
    await settle();
    const view = editor();
    await openPlus(view);
    video();
    expect(ways.keep?.()).toBe(true);
    unmount();
    expect(ways.keep?.()).toBe(false);
    // A film that was kept all the same, the moment before the note went, is not written into the note left.
    await act(async () => land!(PICKED));
    await settle();
    expect(saved().some((body) => body?.includes('video/'))).toBe(false);
    vi.restoreAllMocks();
  });

  it('lands with no caret moved or focus taken when the person went to another field meanwhile, and lets its place go', async () => {
    films.can = true;
    let land: ((film: typeof PICKED) => void) | null = null;
    films.pick = () => new Promise((resolve) => void (land = resolve));
    show(screen(await createNote('n1', '# Walk\n\n')));
    await settle();
    const view = editor();
    await openPlus(view);
    video();
    const other = document.body.appendChild(document.createElement('input'));
    act(() => other.focus());
    const focus = vi.spyOn(view, 'focus');
    await act(async () => land!(PICKED));
    await settle();
    expect(view.state.doc.toString()).toBe('# Walk\n\n[![video 0:12](image/p1.jpg)](video/f1.mp4)\n');
    expect(focus).not.toHaveBeenCalled();
    expect(document.activeElement).toBe(other);
    expect(view.state.field(insertSpots).size).toBe(0);
    vi.restoreAllMocks();
  });

  it('draws its card to play on a phone that plays films', async () => {
    films.where = 'here';
    show(screen(await createNote('n1', '# Walk\n\n[![video 0:12](image/p1.jpg)](video/f1.mp4)\n')));
    await settle();
    const card = editor().dom.querySelector<HTMLElement>('.cm-videoCard');
    expect(card?.dataset.mode).toBe('play');
    await waitUntil(() => expect(card?.querySelector('button[aria-label="Play the video, 0:12"]')).not.toBeNull());
  });

  it('writes nothing when the picker is closed with nothing chosen', async () => {
    films.can = true;
    films.pick = async () => null;
    show(screen(await createNote('n1', '# Walk\n\n')));
    await settle();
    const view = editor();
    await openPlus(view);
    video();
    await settle();
    expect(view.state.doc.toString()).toBe('# Walk\n\n');
    vi.restoreAllMocks();
  });
});

describe('a notebook kept as a journal', () => {
  const NOTEBOOK = '---\ntitle: "Trip"\nbook: true\n---\n# Trip\n\n- [[Day one]]\n- [[Day two]]\n';
  const more = () => act(() => button('More for this note').click());
  const viewSwitch = () => document.querySelector<HTMLButtonElement>('header button')!;
  const written = async () => {
    act(() => vi.advanceTimersByTime(400));
    await settle();
    return saved().at(-1) ?? '';
  };

  it('is offered on a notebook’s More sheet, and keeping it writes the keys and leaves every page where it was', async () => {
    show(screen(await createNote('b1', NOTEBOOK), { hasTitle: () => true, onOpenTitle: () => {} }));
    more();
    expect(buttonSaying(document.body, 'Keep it as a journal')?.textContent).toContain('New pages start dated, from a template.');
    act(() => buttonSaying(document.body, 'Keep it as a journal')!.click());
    expect(document.querySelector('[role="dialog"]')?.getAttribute('aria-label')).toBe('Journal');
    // A draft until it is kept: nothing is written yet, so nothing is said about entries already written.
    expect(document.body.textContent).not.toContain('Entries you have written stay as they are.');
    expect(buttonSaying(document.body, 'Make it a journal')?.textContent).toContain('Its pages stay where they are.');
    act(() => button('Just the time').click());
    act(() => buttonSaying(document.body, 'Make it a journal')!.click());
    const body = await written();
    expect(body).toBe('---\ntitle: "Trip"\nbook: true\njournal: true\ntemplate: "**{{time}}** "\nentry-place: true\n---\n# Trip\n\n- [[Day one]]\n- [[Day two]]\n');
    // Back on the sheet, the row says what it is now; the name field says journal.
    expect(buttonSaying(document.body, 'Journal')?.textContent).toContain('Starts with the time. Keeps where each was written.');
    expect(document.querySelector('input[placeholder="What this journal is called"]')).not.toBeNull();
  });

  it('writes a journal’s changes as they are made, and makes it a notebook again with every page kept', async () => {
    const journal = '---\ntitle: "Trip"\nbook: true\njournal: true\ntemplate: "**{{time}}** "\nentry-place: true\n---\n# Trip\n\n- [[Day one]]\n';
    show(screen(await createNote('j1', journal), { hasTitle: () => true, onOpenTitle: () => {} }));
    more();
    act(() => buttonSaying(document.body, 'Journal')!.click());
    // Each change is written as it is made, and is for entries from then on.
    expect(document.body.textContent).toContain('Entries you have written stay as they are.');
    expect(buttonSaying(document.body, 'Make it a notebook again')?.textContent).toContain('Its entries stay as pages. New pages start plain.');
    act(() => button('A morning page').click());
    expect(await written()).toContain('template: "# {{date}}\\n\\n> What is on your mind this morning?\\n\\n"');
    act(() => document.querySelector<HTMLElement>('input[aria-label="With where you are"]')!.click());
    expect(await written()).not.toContain('entry-place');
    act(() => buttonSaying(document.body, 'Make it a notebook again')!.click());
    expect(await written()).toBe('---\ntitle: "Trip"\nbook: true\n---\n# Trip\n\n- [[Day one]]\n');
  });

  it('writes the keys into the Markdown when that is the view, so the next keystroke keeps them', async () => {
    show(screen(await createNote('b1', NOTEBOOK), { hasTitle: () => true, onOpenTitle: () => {} }));
    act(() => viewSwitch().click());
    more();
    act(() => buttonSaying(document.body, 'Keep it as a journal')!.click());
    act(() => buttonSaying(document.body, 'Make it a journal')!.click());
    act(() => goBack());
    type('- [[Day three]]\n');
    const body = await written();
    expect(body).toContain('journal: true');
    expect(body).toContain('[[Day three]]');
  });

  it('puts the caret at the end of a new entry’s words, and has the editor’s focus', async () => {
    const entry = '---\ntitle: "2026-09-28 14.05"\n---\n# Monday 28 September\n\n**14:05** ';
    show(screen(await createNote('en1', entry), { caret: 'end' }));
    await settle();
    expect(editor().state.selection.main.head).toBe(entry.length);
    expect(editor().hasFocus).toBe(true);
  });

  it('hands App a way to write the journal’s index through the screen, saved at once, and takes it back as it goes', async () => {
    const writers: (JournalWriter | null)[] = [];
    const journal = '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n';
    show(screen(await createNote('j1', journal), { hasTitle: () => true, onOpenTitle: () => {}, onJournal: (writer) => writers.push(writer) }));
    expect(writers.at(-1)?.id).toBe('j1');
    act(() => writers.at(-1)!.write((body) => `${body}- [[2026-09-28 14.05]]\n`));
    await settle();
    // Saved at once, not on the typing's wait.
    expect(saved().at(-1)).toBe(`${journal}- [[2026-09-28 14.05]]\n`);
    // A notebook that is not a journal hands nothing over; the journal's screen gone, the way is taken back.
    unmount();
    expect(writers.at(-1)).toBeNull();
    show(screen(await createNote('b1', NOTEBOOK), { hasTitle: () => true, onOpenTitle: () => {}, onJournal: (writer) => writers.push(writer) }));
    expect(writers.at(-1)).toBeNull();
  });

  it('is not offered on the Guide, a note of words, or a canvas', async () => {
    show(screen(await createNote('g1', '---\ntitle: "Ghost.md: The Guide"\nbook: true\n---\n# Ghost.md: The Guide\n\n1. [[Welcome]]\n'), { hasTitle: () => true, onOpenTitle: () => {} }));
    more();
    expect(buttonSaying(document.body, 'Keep it as a journal')).toBeUndefined();
    unmount();
    show(screen(await createNote('n1', '# Groceries')));
    more();
    expect(buttonSaying(document.body, 'Keep it as a journal')).toBeUndefined();
    unmount();
    show(screen(await createNote('c1', '{"nodes":[],"edges":[]}')));
    more();
    expect(buttonSaying(document.body, 'Keep it as a journal')).toBeUndefined();
  });
});

describe('a journal open', () => {
  it('is drawn as its entries by month rather than a numbered index, and keeps no spot for them', async () => {
    const journal = '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n- [[2026-09-28 14.05]]\n';
    const entry = await createNote('e1', '---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\n---\n**14:05** Walked.');
    show(screen(await createNote('j1', journal), { hasTitle: () => true, onOpenTitle: () => {}, noteOfTitle: (title) => (title === '2026-09-28 14.05' ? entry : undefined) }));
    expect(document.querySelector('ol[aria-label="Pages"]')).toBeNull();
    expect(document.querySelector('h2')?.textContent).toBe('September 2026');
    // Its mic makes an entry and speaks it.
    expect(document.querySelector('button[aria-label="Speak an entry"]')).not.toBeNull();
    expect(document.querySelector('button[aria-label="Talk into this note"]')).toBeNull();
    expect(document.querySelector('[data-entries]')?.getAttribute('data-entries')).toBe('1');
    expect(readBookSpot('j1')).toBeNull();
    unmount();
    // An entry open writes no spot for its journal: the journal opens on itself.
    const place = { ...bookOf([{ ...entry, id: 'j1', body: journal }], '2026-09-28 14.05')!, journal: true };
    show(screen(entry, { book: place, hasTitle: () => true, onOpenTitle: () => {} }));
    expect(document.querySelector('nav[aria-label="Journal"]')).not.toBeNull();
    expect(readBookSpot('j1')).toBeNull();
  });
});

describe('the + beside the line in a journal', () => {
  /** The +'s state once the caret has rested where it is, with the note focused. */
  const restHere = async (view: EditorView) => {
    act(() => view.focus());
    await act(async () => vi.advanceTimersByTimeAsync(10 + 200));
    return view.scrollDOM.querySelector<HTMLButtonElement>('.cm-plus')?.dataset.state;
  };

  it('comes beside an empty line of a new entry, and not beside the time its template wrote', async () => {
    vi.spyOn(document, 'hasFocus').mockReturnValue(true);
    try {
      const entry = '---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\n---\n# Monday 28 September\n\n**14:05** ';
      show(screen(await createNote('en1', entry), { caret: 'end' }));
      await settle();
      const view = editor();
      expect(view.state.selection.main.head).toBe(entry.length);
      expect(await restHere(view)).not.toBe('shown');
      // Enter, Enter: the caret on a line of its own under the time, and the + there.
      act(() => view.dispatch({ changes: { from: entry.length, insert: '\n\n' }, selection: { anchor: entry.length + 2 }, userEvent: 'input.type' }));
      expect(await restHere(view)).toBe('shown');
    } finally {
      vi.restoreAllMocks();
    }
  });

  it('never comes over a journal’s entries, or over its index shown as its Markdown', async () => {
    vi.spyOn(document, 'hasFocus').mockReturnValue(true);
    try {
      const journal = '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n- [[2026-09-28 14.05]]\n';
      show(screen(await createNote('j1', journal), { hasTitle: () => true, onOpenTitle: () => {}, noteOfTitle: () => undefined }));
      const shown = [...document.querySelectorAll<HTMLButtonElement>('.cm-plus')].filter((plus) => !plus.hidden && plus.dataset.state === 'shown');
      expect(shown).toEqual([]);
      act(() => document.querySelector<HTMLButtonElement>('header button')!.click());
      const view = editor();
      act(() => view.dispatch({ selection: { anchor: view.state.doc.length } }));
      expect(await restHere(view)).toBe('off');
    } finally {
      vi.restoreAllMocks();
    }
  });
});
