import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import type { Note } from '../core/store.ts';
import { asideContent } from './aside.ts';
import { Aside, AsideCard } from './Aside.tsx';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

let root: Root | null = null;
let host: HTMLDivElement | null = null;
function show(element: React.ReactElement): void {
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
  act(() => root!.render(element));
}
afterEach(() => {
  act(() => root?.unmount());
  host?.remove();
  root = null;
  host = null;
});
const button = (label: string): HTMLButtonElement => {
  const found = [...document.querySelectorAll<HTMLButtonElement>('button')].find((b) => b.getAttribute('aria-label') === label || b.textContent?.trim() === label);
  if (!found) throw new Error(`no button ${label}`);
  return found;
};

const note = (id: string, body: string, updatedAt = 1): Note => ({ id, body, createdAt: 0, updatedAt, source: 'editor' });
const BOOK = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n- [[Trees]]\n- [[Birds]]\n';
const notes = [note('b', BOOK, 5), note('t', '# Trees\n', 4), note('x', '# Loose\n', 3)];

describe('the right-hand aside', () => {
  it('shows a page’s book: its chapters with the open one marked, a tap opening another, the title opening the book', () => {
    const onOpen = vi.fn();
    const onOpenTitle = vi.fn();
    show(<Aside content={asideContent(notes, notes[1]!)!} onOpen={onOpen} onOpenTitle={onOpenTitle} />);
    expect([...document.querySelectorAll('ol[aria-label="Chapters"] button')].map((b) => b.textContent?.trim())).toEqual(['1Trees', '2Birds']);
    expect(document.querySelector('[aria-current="page"]')?.textContent).toContain('Trees');
    act(() => button('2Birds').click());
    expect(onOpenTitle).toHaveBeenCalledWith('Birds');
    act(() => button('Open the book Field guide').click());
    expect(onOpen).toHaveBeenCalledWith('b');
  });

  it('lays out a run of chapters with no book: their numbers, the open one marked, a tap opening another by id', () => {
    const onOpen = vi.fn();
    const onClose = vi.fn();
    const run = [note('c2', '# 02 · Second\n\n« [[The book]]', 1), note('c1', '# 01 · First\n\n« [[The book]]', 2)];
    show(<Aside content={asideContent(run, run[0]!)!} onOpen={onOpen} onOpenTitle={() => {}} onClose={onClose} />);
    expect(document.body.textContent).toContain('The book');
    expect([...document.querySelectorAll('ol[aria-label="Chapters"] button')].map((b) => b.textContent?.trim())).toEqual(['1First', '2Second']);
    expect(document.querySelector('[aria-current="page"]')?.textContent).toContain('Second');
    // The book isn't a note, so its name is only a name: nothing to open, and nothing made by tapping it.
    expect(document.querySelector('button[aria-label="Open The book"]')).toBeNull();
    act(() => button('1First').click());
    expect(onOpen).toHaveBeenCalledWith('c1');
    act(() => button('Close').click());
    expect(onClose).toHaveBeenCalled();
  });
});

describe('the aside as the drawer’s card', () => {
  it('is a dialog at the right that closes on a tap outside, not on its own toggle, and on opening a page', async () => {
    const onClose = vi.fn();
    const onOpenTitle = vi.fn();
    const toggle = document.createElement('button');
    toggle.setAttribute('data-aside-toggle', '');
    document.body.appendChild(toggle);
    show(<AsideCard content={asideContent(notes, notes[1]!)!} onOpen={() => {}} onOpenTitle={onOpenTitle} onClose={onClose} />);
    const card = document.querySelector('[role="dialog"][data-side="end"]');
    expect(card?.getAttribute('aria-label')).toBe('Book index');
    expect(card?.querySelector('[data-popup]')).toBeTruthy();
    // The outside listener joins on the next tick, so the press that opened the card cannot close it.
    await new Promise((resolve) => setTimeout(resolve, 5));
    toggle.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    expect(onClose).not.toHaveBeenCalled();
    document.body.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    expect(onClose).toHaveBeenCalledTimes(1);
    const birds = [...document.querySelectorAll<HTMLButtonElement>('ol[aria-label="Chapters"] button')][1]!;
    act(() => birds.click());
    expect(onOpenTitle).toHaveBeenCalledWith('Birds');
    expect(onClose).toHaveBeenCalledTimes(2);
    toggle.remove();
  });
});
