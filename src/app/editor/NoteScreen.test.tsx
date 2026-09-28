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
import { readBookSpot } from '../book/bookSpot.ts';

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
});
