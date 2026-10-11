import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { EditorView } from '@codemirror/view';
import { show } from '../../test/render.tsx';

/**
 * A card's editor costs 25-30 ms, so on a page that can watch the screen a card is a blank until it comes near it,
 * the editors are made one at a time in tasks of their own, and a card that goes far off gives its editor back and
 * keeps its height. NotePeek.test.tsx is the page that cannot watch, where every card draws at once.
 *
 * The screen is stood in for by an IntersectionObserver the test drives: `near(el)` and `far(el)` say what a real one
 * would when the card scrolled.
 */

/** Each element being watched, and the callback of the observer watching it: CodeMirror keeps observers of its own. */
const seen = vi.hoisted(() => ({ observed: new Map<Element, IntersectionObserverCallback>() }));
vi.hoisted(() => {
  globalThis.IntersectionObserver = class {
    constructor(private readonly callback: IntersectionObserverCallback) {}
    observe(el: Element) {
      seen.observed.set(el, this.callback);
    }
    unobserve(el: Element) {
      seen.observed.delete(el);
    }
    disconnect() {
      // Nothing here watches for a disconnect: the cards unobserve one by one.
    }
  } as unknown as typeof IntersectionObserver;
});

const { NotePeek } = await import('./NotePeek.tsx');

const tell = (el: Element, isIntersecting: boolean) =>
  act(() => seen.observed.get(el)!([{ target: el, isIntersecting } as IntersectionObserverEntry], {} as IntersectionObserver));
const card = (host: HTMLElement) => host.querySelector<HTMLElement>('[aria-hidden="true"]')!;
const editorIn = (host: HTMLElement) => host.querySelector<HTMLElement>('.cm-editor');

/**
 * The next task: the queue's next editor. A timer set for no delay from inside another fires a millisecond on under
 * fake timers, as Node's does, so a step is one millisecond, not none.
 */
const nextTask = () => act(() => void vi.advanceTimersByTime(1));

afterEach(() => {
  // The editors' queue is the module's own, and runs on the clock: let it run dry on the fake one it started on, or
  // the next test would find it still waiting on a timer that no longer exists.
  act(() => void vi.advanceTimersByTime(1000));
  vi.useRealTimers();
});

describe('a card on a page that watches the screen', () => {
  it('is a blank the height of its lines until it comes near, then draws in a task of its own', () => {
    vi.useFakeTimers();
    const host = show(<NotePeek body={'# Far\n\n- [ ] One\n- [ ] Two\n\nThree lines.'} />);
    expect(editorIn(host)).toBeNull();
    expect(card(host).style.blockSize).toBe('calc(var(--app-body) * 1.6 * 3)');
    expect(seen.observed.has(card(host))).toBe(true);
    tell(card(host), true);
    // Asked for, not yet made: the page paints first.
    expect(editorIn(host)).toBeNull();
    nextTask();
    expect(editorIn(host)).not.toBeNull();
    expect(card(host).style.blockSize).toBe('');
  });

  it('makes the editors of cards that come near together one after another', () => {
    vi.useFakeTimers();
    const first = show(<NotePeek body={'# One\n\nThe first card.'} />);
    const second = show(<NotePeek body={'# Two\n\nThe second card.'} />);
    tell(card(first), true);
    tell(card(second), true);
    // The task the queue started makes one editor, and the next card waits for a task of its own.
    act(() => void vi.advanceTimersByTime(0));
    expect([editorIn(first) !== null, editorIn(second) !== null]).toEqual([true, false]);
    nextTask();
    expect(editorIn(second)).not.toBeNull();
  });

  it('gives its editor back when it goes far off, and comes back from what it drew with no editor behind it', () => {
    vi.useFakeTimers();
    const host = show(<NotePeek body={'# Back\n\nDrawn once, kept.'} />);
    tell(card(host), true);
    nextTask();
    // Before it has settled and been kept: going away gives the editor back and keeps a blank in its place.
    tell(card(host), false);
    expect(editorIn(host)).toBeNull();
    expect(card(host).style.blockSize).toBe('0px');
    tell(card(host), true);
    nextTask();
    // Settled: what it drew is kept, and the editor let go.
    act(() => void vi.advanceTimersByTime(250));
    const kept = editorIn(host)!;
    expect(kept.textContent).toContain('Drawn once, kept.');
    expect(EditorView.findFromDOM(kept)).toBeNull();
    tell(card(host), false);
    // Near again: the kept drawing at once, with nothing queued.
    tell(card(host), true);
    expect(editorIn(host)?.textContent).toContain('Drawn once, kept.');
  });
});
