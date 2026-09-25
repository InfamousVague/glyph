import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, type ReactElement } from 'react';
import { EditorView } from '@codemirror/view';
import { ToastProvider } from '@glacier/react';
import { button, buttonSaying, rerender, show, typeInto, unmount } from '../../test/render.tsx';
import { createNote, getNote, setNoteRecording, updateNote, type Note } from '../core/store.ts';
import { goBack } from '../core/back.ts';
import { setTopBarTools } from '../core/topBarTools.ts';

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

vi.mock('../core/store.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../core/store.ts')>();
  return { ...real, updateNote: vi.fn(real.updateNote) };
});

/** Whether the AI can run here: the browser's answer, which is no, unless a test says the phone has a model. */
const ai = vi.hoisted(() => ({ ready: false }));
vi.mock('../ai/available.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../ai/available.ts')>();
  return {
    ...real,
    useAvailability: () => {
      const answer = real.useAvailability();
      return ai.ready ? { ...answer, availability: { ok: true as const, model: 'qwen3.5-4b', chosen: 'qwen3.5-4b' } } : answer;
    },
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
  ai.ready = false;
  setTopBarTools(null);
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

describe('the AI bar', () => {
  const bar = () => document.querySelector('section[aria-label="Ask the AI"]');

  it('is away until the ✨ shows it, and its own ✨ puts it away again', async () => {
    show(screen(await createNote('n1', '# Groceries')));
    expect(bar()).toBeNull();
    act(() => button('Show the AI bar').click());
    expect(bar()).not.toBeNull();
    act(() => button('Hide the AI bar').click());
    expect(bar()).toBeNull();
    expect(button('Show the AI bar')).toBeTruthy();
  });

  it('opens on the words when a selection asks the AI, whatever the setting, and asks which part', async () => {
    ai.ready = true;
    show(screen(await createNote('n1', '# Groceries\nmilk and eggs')));
    const view = editor();
    act(() => view.dispatch({ selection: { anchor: 12, head: 16 } }));
    act(() => {
      view.contentDOM.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true }));
    });
    await act(async () => new Promise<void>((resolve) => requestAnimationFrame(() => resolve())));
    await act(async () => button('Ask the AI', document.querySelector('[role="menu"]')!).click());
    expect(bar()).not.toBeNull();
    // A chip pressed now asks whether it means the selected words or the note.
    act(() => button('Format', bar()!).click());
    expect(button('This part', bar()!)).toBeTruthy();
  });

  it('is not offered on a canvas', async () => {
    show(screen(await createNote('c1', '{"nodes":[],"edges":[]}')));
    expect(document.querySelector('[aria-label="Show the AI bar"]')).toBeNull();
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

  it('comes off at once on Remove, and its Undo puts it back', async () => {
    show(screen(await spoken()));
    await act(async () => button("Remove this note's recording").click());
    await settle();
    expect(document.querySelector('section[aria-label="Recording"]')).toBeNull();
    expect((await getNote('n1'))?.recordingMs ?? null).toBeNull();
    expect(document.body.textContent).toContain('Recording removed.');
    await act(async () => button('Undo').click());
    await settle();
    expect(document.querySelector('section[aria-label="Recording"]')).not.toBeNull();
    expect((await getNote('n1'))?.recordingMs).toBe(4000);
  });
});

describe('the canvases framed in the note', () => {
  /** App's lookups, as it hands them down on each of its renders. */
  const lookups = () => ({
    hasTitle: () => true,
    onOpenTitle: () => {},
    bodyOfTitle: vi.fn((title: string) => (title === 'Map' ? '{"nodes":[],"edges":[]}' : null)),
  });

  it('are read again when the notes change, not each time the screen draws', async () => {
    const note = await createNote('n1', '# Trip\n![[Map]]\nwords');
    const first = lookups();
    show(screen(note, first));
    const read = first.bodyOfTitle.mock.calls.length;
    expect(read).toBeGreaterThan(0);
    // The screen draws again on its own - the More sheet opening, a tape's playhead moving - with App's lookups the same.
    act(() => button('More for this note').click());
    expect(first.bodyOfTitle).toHaveBeenCalledTimes(read);
    // App hands down new lookups when the notes change: a framed canvas may have been drawn on, so it is read again.
    const next = lookups();
    rerender(screen(note, next));
    expect(next.bodyOfTitle).toHaveBeenCalledWith('Map');
  });
});
