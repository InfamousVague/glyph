import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import type { Note } from '../core/store.ts';
import { bookNoteBody } from '../book/book.ts';
import { makeNote } from '../../test/notes.ts';
import { show, typeInto, unmount } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';
import { AllNotesScreen } from './AllNotesScreen.tsx';

// The wisp hook watches the bar's size; jsdom has no observer and no sizes, so it sees a page that never scrolls.
stubResizeObserver();

afterEach(() => {
  unmount();
  localStorage.clear();
});

const showNotes = (notes: Note[], onOpen = () => {}, onBack = () => {}, tapes = false) =>
  show(<AllNotesScreen notes={notes} loading={false} onOpen={onOpen} onBack={onBack} tapes={tapes} />);

const cardTitles = (page: HTMLElement) => [...page.querySelectorAll('ol[aria-label="Notes"] li')].map((li) => li.querySelector('[class*=title]')?.textContent);
const field = (page: HTMLElement) => page.querySelector<HTMLInputElement>('input[type="search"]')!;
const type = (page: HTMLElement, words: string) => typeInto(field(page), words);

describe('the All notes page', () => {
  it('draws every note as a card, the last touched first, and opens the one tapped', () => {
    const onOpen = vi.fn();
    const page = showNotes([makeNote('a', '# Apples', { updatedAt: 1 }), makeNote('b', '# Bread', { updatedAt: 2 }), makeNote('c', '', { updatedAt: 3 })], onOpen);
    expect(cardTitles(page)).toEqual(['Untitled', 'Bread', 'Apples']);
    expect(page.textContent).toContain('3 notes');
    // Drawn dense: each card is the grid's smaller one.
    expect(page.querySelectorAll('ol[aria-label="Notes"] li[data-dense]').length).toBe(3);
    act(() => page.querySelector<HTMLButtonElement>('ol[aria-label="Notes"] li button')!.click());
    expect(onOpen).toHaveBeenCalledWith('c');
  });

  it('narrows to the words typed, and says when nothing has them', () => {
    const page = showNotes([makeNote('a', '# Apples\n\nfor the pie'), makeNote('b', '# Bread'), makeNote('c', '# Cake\n\napples in it')]);
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
    const page = showNotes([makeNote('a', '# pear', { updatedAt: 3 }), makeNote('b', '# Apple', { updatedAt: 2 }), makeNote('c', '# Mango', { updatedAt: 1 })]);
    const az = page.querySelector<HTMLButtonElement>('[role="radio"][aria-checked="false"]')!;
    expect(az.textContent).toBe('A to Z');
    act(() => az.click());
    expect(cardTitles(page)).toEqual(['Apple', 'Mango', 'pear']);
    expect(localStorage.getItem('glyph-all-notes-sort')).toBe('title');
  });

  it('keeps the archive out until its word is pressed, then marks each archived card', () => {
    const page = showNotes([makeNote('a', '# Kept'), makeNote('b', '# Gone', { archivedAt: 5 })]);
    expect(cardTitles(page)).toEqual(['Kept']);
    const word = page.querySelector<HTMLButtonElement>('button[aria-pressed]')!;
    expect(word.textContent).toContain('Archived · 1');
    act(() => word.click());
    expect(cardTitles(page)).toEqual(['Kept', 'Gone']);
    expect(page.querySelector('[aria-label="Archived"]')).not.toBeNull();
  });

  it('shows only the notes with a tape while its Tapes word is on, typed ones included, and opens with it on when asked', () => {
    const notes = [
      makeNote('s', '# Spoken', { source: 'capture', recordingMs: 40_000, updatedAt: 3 }),
      makeNote('t', '# Typed then spoken', { recordingMs: 12_000, updatedAt: 2 }),
      makeNote('p', '# Plain', { updatedAt: 1 }),
    ];
    const page = showNotes(notes);
    expect(cardTitles(page)).toEqual(['Spoken', 'Typed then spoken', 'Plain']);
    const word = [...page.querySelectorAll<HTMLButtonElement>('button[aria-pressed]')].find((b) => b.textContent?.includes('Tapes'))!;
    expect(word.textContent).toContain('Tapes · 2');
    expect(word.getAttribute('aria-pressed')).toBe('false');
    act(() => word.click());
    expect(cardTitles(page)).toEqual(['Spoken', 'Typed then spoken']);
    expect(page.textContent).toContain('2 notes');
    type(page, 'typed');
    expect(page.textContent).toContain('1 of 2');
    unmount();
    // From the shelf's "and N more": the page opens with the word already on.
    const opened = showNotes(notes, () => {}, () => {}, true);
    expect(cardTitles(opened)).toEqual(['Spoken', 'Typed then spoken']);
    expect(opened.querySelector('button[aria-pressed="true"]')?.textContent).toContain('Tapes · 2');
    unmount();
    // No Tapes word at all where nothing has a recording.
    const none = showNotes([makeNote('p', '# Plain')]);
    expect([...none.querySelectorAll('button[aria-pressed]')].map((b) => b.textContent)).toEqual([]);
  });

  it('marks a pinned card, and draws a book as its index', () => {
    const page = showNotes([makeNote('p', '# Packing', { starred: true }), makeNote('b', bookNoteBody('Trip', ['Packing', 'Route']))]);
    expect(page.querySelector('[aria-label="Pinned"]')).not.toBeNull();
    expect(page.textContent).toContain('2 pages');
  });

  it('goes home from its arrow', () => {
    const onBack = vi.fn();
    const page = showNotes([], () => {}, onBack);
    expect(page.textContent).toContain('A blank page.');
    act(() => page.querySelector<HTMLButtonElement>('button[aria-label="Back to home"]')!.click());
    expect(onBack).toHaveBeenCalled();
  });
});
