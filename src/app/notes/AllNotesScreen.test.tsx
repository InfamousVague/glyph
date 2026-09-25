import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import type { Note } from '../core/store.ts';
import { bookNoteBody } from '../book/book.ts';
import { AllNotesScreen } from './AllNotesScreen.tsx';

// The wisp hook watches the bar's size; jsdom has no observer and no sizes, so it sees a page that never scrolls.
class StillObserver {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}
globalThis.ResizeObserver ??= StillObserver as unknown as typeof ResizeObserver;
(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

let root: Root | null = null;
let host: HTMLDivElement | null = null;
afterEach(() => {
  act(() => root?.unmount());
  host?.remove();
  localStorage.clear();
});

const note = (id: string, body: string, more: Partial<Note> = {}): Note => ({ id, body, createdAt: 0, updatedAt: 0, source: 'editor', ...more });

function show(notes: Note[], onOpen = () => {}, onBack = () => {}) {
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
  act(() => root!.render(<AllNotesScreen notes={notes} loading={false} onOpen={onOpen} onBack={onBack} />));
  return host;
}

const cardTitles = (page: HTMLElement) => [...page.querySelectorAll('ol[aria-label="Notes"] li')].map((li) => li.querySelector('[class*=title]')?.textContent);
const field = (page: HTMLElement) => page.querySelector<HTMLInputElement>('input[type="search"]')!;
const type = (page: HTMLElement, words: string) => {
  const input = field(page);
  const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  act(() => {
    set.call(input, words);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
};

describe('the All notes page', () => {
  it('draws every note as a card, the last touched first, and opens the one tapped', () => {
    const onOpen = vi.fn();
    const page = show([note('a', '# Apples', { updatedAt: 1 }), note('b', '# Bread', { updatedAt: 2 }), note('c', '', { updatedAt: 3 })], onOpen);
    expect(cardTitles(page)).toEqual(['Untitled', 'Bread', 'Apples']);
    expect(page.textContent).toContain('3 notes');
    // Drawn dense: each card is the grid's smaller one.
    expect(page.querySelectorAll('ol[aria-label="Notes"] li[data-dense]').length).toBe(3);
    act(() => page.querySelector<HTMLButtonElement>('ol[aria-label="Notes"] li button')!.click());
    expect(onOpen).toHaveBeenCalledWith('c');
  });

  it('narrows to the words typed, and says when nothing has them', () => {
    const page = show([note('a', '# Apples\n\nfor the pie'), note('b', '# Bread'), note('c', '# Cake\n\napples in it')]);
    type(page, 'apples');
    expect(cardTitles(page)).toEqual(['Apples', 'Cake']);
    expect(page.textContent).toContain('2 of 3');
    type(page, 'apples pie');
    expect(cardTitles(page)).toEqual(['Apples']);
    type(page, 'kettle');
    expect(cardTitles(page)).toEqual([]);
    expect(page.textContent).toContain('Nothing has “kettle”.');
    act(() => page.querySelector<HTMLButtonElement>('button[aria-label="Clear the search"]')!.click());
    expect(field(page).value).toBe('');
    expect(cardTitles(page).length).toBe(3);
  });

  it('orders by name when asked, and remembers the choice', () => {
    const page = show([note('a', '# pear', { updatedAt: 3 }), note('b', '# Apple', { updatedAt: 2 }), note('c', '# Mango', { updatedAt: 1 })]);
    const az = page.querySelector<HTMLButtonElement>('[role="radio"][aria-checked="false"]')!;
    expect(az.textContent).toBe('A to Z');
    act(() => az.click());
    expect(cardTitles(page)).toEqual(['Apple', 'Mango', 'pear']);
    expect(localStorage.getItem('glyph-all-notes-sort')).toBe('title');
  });

  it('keeps the archive out until its word is pressed, then marks each archived card', () => {
    const page = show([note('a', '# Kept'), note('b', '# Gone', { archivedAt: 5 })]);
    expect(cardTitles(page)).toEqual(['Kept']);
    const word = page.querySelector<HTMLButtonElement>('button[aria-pressed]')!;
    expect(word.textContent).toContain('Archived · 1');
    act(() => word.click());
    expect(cardTitles(page)).toEqual(['Kept', 'Gone']);
    expect(page.querySelector('[aria-label="Archived"]')).not.toBeNull();
  });

  it('marks a pinned card, and draws a book as its index', () => {
    const page = show([note('p', '# Packing', { starred: true }), note('b', bookNoteBody('Trip', ['Packing', 'Route']))]);
    expect(page.querySelector('[aria-label="Pinned"]')).not.toBeNull();
    expect(page.textContent).toContain('2 pages');
  });

  it('goes home from its arrow', () => {
    const onBack = vi.fn();
    const page = show([], () => {}, onBack);
    expect(page.textContent).toContain('A blank page.');
    act(() => page.querySelector<HTMLButtonElement>('button[aria-label="Back to home"]')!.click());
    expect(onBack).toHaveBeenCalled();
  });
});
