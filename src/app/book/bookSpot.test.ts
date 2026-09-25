import { afterEach, describe, expect, it } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { bookNoteBody } from './book.ts';
import { readBookSpot, readingPlaceOf, scrollToReading, whereLeft, writeBookSpot } from './bookSpot.ts';

/**
 * Where a book was left: kept and read back, what opening the book from outside goes to, and the read-through's place
 * as the chapter at the top of the page and how far into it.
 */

const BOOK = makeNote('book', bookNoteBody('Field guide', ['Introduction', 'Trees', 'Birds']));
const TREES = makeNote('trees', '# Trees\n\nOaks and pines.');
const INTRO = makeNote('intro', '# Introduction\n\nWelcome.');
const NOTES = [BOOK, INTRO, TREES];

afterEach(() => localStorage.clear());

describe('the spot a book was left at', () => {
  it('is kept per book and read back, and a shape it does not know is no spot', () => {
    expect(readBookSpot('book')).toBeNull();
    writeBookSpot('book', { kind: 'chapter', title: 'Trees' });
    writeBookSpot('other', { kind: 'reading', title: 'Oaks', offset: 120 });
    expect(readBookSpot('book')).toEqual({ kind: 'chapter', title: 'Trees' });
    expect(readBookSpot('other')).toEqual({ kind: 'reading', title: 'Oaks', offset: 120 });
    localStorage.setItem('glyph-book-spots', JSON.stringify({ book: { kind: 'chapter' }, other: 'nonsense' }));
    expect(readBookSpot('book')).toBeNull();
    expect(readBookSpot('other')).toBeNull();
    localStorage.setItem('glyph-book-spots', 'not json');
    expect(readBookSpot('book')).toBeNull();
  });

  it('forgets the least recently read books past a hundred', () => {
    for (let i = 0; i < 101; i += 1) writeBookSpot(`b${i}`, { kind: 'index' }, 1000 + i);
    expect(readBookSpot('b0')).toBeNull();
    expect(readBookSpot('b1')).toEqual({ kind: 'index' });
    expect(readBookSpot('b100')).toEqual({ kind: 'index' });
  });
});

describe('opening a book from outside it', () => {
  it('goes to the chapter it was left in', () => {
    writeBookSpot('book', { kind: 'chapter', title: 'trees' });
    expect(whereLeft(BOOK, NOTES, null)).toBe(TREES);
  });

  it('opens the book itself when it was left at its index or reading straight through, or never opened', () => {
    expect(whereLeft(BOOK, NOTES, null)).toBe(BOOK);
    writeBookSpot('book', { kind: 'index' });
    expect(whereLeft(BOOK, NOTES, null)).toBe(BOOK);
    writeBookSpot('book', { kind: 'reading', title: 'Trees', offset: 40 });
    expect(whereLeft(BOOK, NOTES, null)).toBe(BOOK);
  });

  it('opens the index when the chapter is already on screen, since that is asking for the book', () => {
    writeBookSpot('book', { kind: 'chapter', title: 'Trees' });
    expect(whereLeft(BOOK, NOTES, 'trees')).toBe(BOOK);
    expect(whereLeft(BOOK, NOTES, 'intro')).toBe(TREES);
  });

  it('opens the index when the chapter has left the book, or its note is gone or archived', () => {
    writeBookSpot('book', { kind: 'chapter', title: 'Pines' });
    expect(whereLeft(BOOK, [...NOTES, makeNote('pines', '# Pines')], null)).toBe(BOOK);
    writeBookSpot('book', { kind: 'chapter', title: 'Birds' });
    expect(whereLeft(BOOK, NOTES, null)).toBe(BOOK);
    writeBookSpot('book', { kind: 'chapter', title: 'Trees' });
    expect(whereLeft(BOOK, [BOOK, { ...TREES, archivedAt: 5 }], null)).toBe(BOOK);
  });

  it('leaves a note that is not a book as it is', () => {
    writeBookSpot('trees', { kind: 'chapter', title: 'Introduction' });
    expect(whereLeft(TREES, NOTES, null)).toBe(TREES);
  });
});

describe('the read-through place', () => {
  /** A page whose top is at `pageTop`, over sections whose tops are where `tops` says, which move as it scrolls. */
  function layout(tops: number[], pageTop = 100) {
    const page = document.createElement('div');
    const root = document.createElement('div');
    page.append(root);
    const bar = document.createElement('div');
    root.append(bar);
    const sections = tops.map(() => root.appendChild(document.createElement('section')));
    page.getBoundingClientRect = () => ({ top: pageTop }) as DOMRect;
    sections.forEach((section, i) => {
      section.getBoundingClientRect = () => ({ top: tops[i]! - page.scrollTop }) as DOMRect;
    });
    return { page, root };
  }
  const TITLES = ['Introduction', 'Trees', 'Birds'];

  it('is the chapter at the top of the page and how far into it', () => {
    const { page, root } = layout([150, 700, 1400]);
    expect(readingPlaceOf(root, page, TITLES)).toEqual({ kind: 'reading', title: 'Introduction', offset: 0 });
    page.scrollTop = 800;
    expect(readingPlaceOf(root, page, TITLES)).toEqual({ kind: 'reading', title: 'Trees', offset: 200 });
    page.scrollTop = 1300;
    expect(readingPlaceOf(root, page, TITLES)).toEqual({ kind: 'reading', title: 'Birds', offset: 0 });
  });

  it('scrolls back to the chapter by its title, the same distance into it', () => {
    const { page, root } = layout([150, 700, 1400]);
    expect(scrollToReading(root, page, TITLES, { title: 'trees', offset: 200 })).toBe(true);
    expect(page.scrollTop).toBe(800);
    expect(readingPlaceOf(root, page, TITLES)).toEqual({ kind: 'reading', title: 'Trees', offset: 200 });
    // A chapter the book no longer has is not somewhere to go.
    expect(scrollToReading(root, page, TITLES, { title: 'Pines', offset: 0 })).toBe(false);
  });
});
