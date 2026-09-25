import { EditorState } from '@codemirror/state';
import type { EditorView } from '@codemirror/view';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { show, unmount } from '../../test/render.tsx';
import { caretPlace, readPlace, useNotePlace, writeBookmark, writePlace } from './notePlace.ts';

describe('where a note was left', () => {
  beforeEach(() => localStorage.clear());

  it('is kept per note, and forgotten when the note is left at the top', () => {
    writePlace('a', { pos: 3124, offset: 51.5 });
    writePlace('b', { pos: 10, offset: 0 });
    expect(readPlace('a')).toEqual({ pos: 3124, offset: 51.5 });
    expect(readPlace('b')).toEqual({ pos: 10, offset: 0 });
    writePlace('a', null);
    expect(readPlace('a')).toBeNull();
    expect(readPlace('missing')).toBeNull();
  });

  it('keeps the most recently read notes, not every note ever opened', () => {
    for (let i = 0; i < 205; i += 1) writePlace(`n${i}`, { pos: i, offset: 0 }, i);
    expect(readPlace('n0')).toBeNull();
    expect(readPlace('n4')).toBeNull();
    expect(readPlace('n5')).toEqual({ pos: 5, offset: 0 });
    expect(readPlace('n204')).toEqual({ pos: 204, offset: 0 });
  });

  it('opens at the top when what is stored is not a place', () => {
    localStorage.setItem('glyph-note-places', '{"a":{"pos":"x"}}');
    expect(readPlace('a')).toBeNull();
    localStorage.setItem('glyph-note-places', 'not json');
    expect(readPlace('a')).toBeNull();
  });

  it('lets go of an entry that is not a place, rather than never keeping another', () => {
    // Sorting the kept places by when they were read met the null and threw, and every place after it was lost.
    localStorage.setItem('glyph-note-places', '{"gone":null,"a":{"pos":3,"offset":0,"at":1}}');
    writePlace('b', { pos: 10, offset: 0 }, 2);
    expect(readPlace('b')).toEqual({ pos: 10, offset: 0 });
    expect(readPlace('a')).toEqual({ pos: 3, offset: 0 });
    expect(JSON.parse(localStorage.getItem('glyph-note-places') ?? '{}')).not.toHaveProperty('gone');
  });
});

describe('the bookmark the button puts in', () => {
  /** A view and a page with just enough of them to place a caret: line blocks 20px tall, a 200px window. */
  const shown = (caret: number, scrollTop: number) => {
    const view = {
      // The document's top in the window moves up as the page scrolls, the way a real scroller reports it.
      documentTop: -scrollTop,
      state: { doc: { length: 1000 }, selection: { main: { head: caret } } },
      lineBlockAt: (pos: number) => ({ from: Math.floor(pos / 40) * 40, top: Math.floor(pos / 40) * 20, height: 20 }),
    } as unknown as Parameters<typeof caretPlace>[0];
    const page = { scrollTop, clientHeight: 200, getBoundingClientRect: () => ({ top: 0 }) } as unknown as HTMLElement;
    return caretPlace(view, page);
  };

  it('is the line the caret is on, from that line’s top', () => {
    // The caret is in the fourth line block (position 130 → line at 120), 60px down, and the page shows 0-200.
    expect(shown(130, 0)).toEqual({ pos: 120, offset: 0 });
  });

  it('is nothing when the caret’s line is not on screen, so the page itself is used instead', () => {
    // The same caret with the page scrolled well past it.
    expect(shown(130, 400)).toBeNull();
    // And a caret on a line that starts below the window's foot.
    expect(shown(400, 0)).toBeNull();
  });

  it('takes a caret on the first line the window shows, and one on the last', () => {
    // Scrolled to 100, the window is 100-300: the line at 100 is its first, and the line at 280 its last.
    expect(shown(200, 100)).toEqual({ pos: 200, offset: 0 });
    expect(shown(570, 100)).toEqual({ pos: 560, offset: 0 });
  });
});

describe('a note opening where it was left', () => {
  /**
   * An editor and its page with just what the hook reads, since jsdom lays nothing out: lines of 40 characters, each
   * 20px tall, the note starting 50px down the page, and a page that scrolls once the words are in.
   */
  function note() {
    let scrollTop = 0;
    const page = document.createElement('div');
    Object.defineProperties(page, {
      scrollTop: { get: () => scrollTop, set: (value: number) => (scrollTop = value), configurable: true },
      scrollHeight: { get: () => (view.state.doc.length ? 2000 : 0), configurable: true },
      clientHeight: { value: 400, configurable: true },
      getBoundingClientRect: { value: () => ({ top: 0 }), configurable: true },
    });
    document.body.append(page);
    const view = {
      state: EditorState.create({ doc: '' }),
      get documentTop() {
        return 50 - scrollTop;
      },
      lineBlockAt: (pos: number) => ({ from: Math.floor(pos / 40) * 40, top: Math.floor(pos / 40) * 20, height: 20 }),
      lineBlockAtHeight: (y: number) => ({ from: Math.floor(y / 20) * 40, top: Math.floor(y / 20) * 20, height: 20 }),
    };
    /** The note's words arriving from the store, a moment after its editor. */
    const arrive = (doc: string) => (view.state = EditorState.create({ doc }));
    return { page, view: view as unknown as EditorView, arrive, scrolled: () => scrollTop, scrollTo: (to: number) => (scrollTop = to) };
  }
  const words = Array.from({ length: 50 }, (_, n) => `Line ${n}`.padEnd(39, '.')).join('\n');

  function Hook({ page, view, id = 'trip' }: { page: HTMLElement; view: EditorView; id?: string }) {
    useNotePlace(id, { current: page }, view, true);
    return null;
  }

  beforeEach(() => {
    localStorage.clear();
    vi.useFakeTimers();
  });
  afterEach(() => {
    unmount();
    vi.useRealTimers();
  });

  it('scrolls back to the place once the words are in, and again once the lines it scrolled to are measured', () => {
    writePlace('trip', { pos: 400, offset: 5 });
    const { page, view, arrive, scrolled } = note();
    show(createElement(Hook, { page, view }));
    vi.advanceTimersByTime(100);
    expect(scrolled()).toBe(0);
    arrive(words);
    vi.advanceTimersToNextFrame();
    // Line 10 is 200px into the note, which starts 50px down the page; and 5px into the line.
    expect(scrolled()).toBe(255);
    page.scrollTop = 0;
    vi.advanceTimersByTime(150);
    expect(scrolled()).toBe(255);
  });

  it('opens at the bookmark rather than where the note was last left, and at one written in the note over both', () => {
    writePlace('trip', { pos: 400, offset: 5 });
    writeBookmark('trip', { pos: 800, offset: 0 });
    const kept = note();
    show(createElement(Hook, kept));
    kept.arrive(words);
    vi.advanceTimersToNextFrame();
    expect(kept.scrolled()).toBe(450);
    unmount();

    const marked = note();
    show(createElement(Hook, marked));
    // The bookmark written into line 30 of the words.
    marked.arrive(words.split('\n').map((line, n) => (n === 30 ? `${line} §§` : line)).join('\n'));
    vi.advanceTimersToNextFrame();
    expect(marked.scrolled()).toBe(50 + marked.view.lineBlockAt(marked.view.state.doc.line(31).from).top);
  });

  it('gives the restore up to a person who starts scrolling first', () => {
    writePlace('trip', { pos: 400, offset: 5 });
    const { page, view, arrive, scrolled } = note();
    show(createElement(Hook, { page, view }));
    page.dispatchEvent(new Event('pointerdown'));
    arrive(words);
    vi.advanceTimersByTime(3000);
    expect(scrolled()).toBe(0);
  });

  it('remembers where the page settles after a scroll, when the app is hidden, and when the note closes', () => {
    const { page, view, arrive, scrollTo } = note();
    show(createElement(Hook, { page, view }));
    arrive(words);
    vi.advanceTimersToNextFrame();
    scrollTo(50 + 300 + 7);
    page.dispatchEvent(new Event('scroll'));
    vi.advanceTimersByTime(399);
    expect(readPlace('trip')).toBeNull();
    vi.advanceTimersByTime(1);
    expect(readPlace('trip')).toEqual({ pos: 600, offset: 7 });

    scrollTo(50 + 500);
    page.dispatchEvent(new Event('scroll'));
    Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
    document.dispatchEvent(new Event('visibilitychange'));
    delete (document as Partial<Document> & { visibilityState?: string }).visibilityState;
    expect(readPlace('trip')).toEqual({ pos: 1000, offset: 0 });

    scrollTo(50 + 100);
    page.dispatchEvent(new Event('scroll'));
    unmount();
    expect(readPlace('trip')).toEqual({ pos: 200, offset: 0 });
  });

  it('keeps the old place of a note closed before its words arrived', () => {
    writePlace('trip', { pos: 400, offset: 5 });
    const { page, view } = note();
    show(createElement(Hook, { page, view }));
    vi.advanceTimersByTime(100);
    unmount();
    expect(readPlace('trip')).toEqual({ pos: 400, offset: 5 });
  });
});
