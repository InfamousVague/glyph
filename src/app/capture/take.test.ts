import { describe, expect, it } from 'vitest';
import { bookNoteBody, chaptersOf } from '../book/book.ts';
import { quietHost } from '../../test/takeHost.ts';
import { describeOffer, Take, type Offer, type TakeNote } from './take.ts';

/**
 * The take with a book among the notes (docs/BOOKS.md): a chapter asked for lands in the book's index after a yes, a
 * book asked for is made by the host, and what cannot be a chapter is said and not offered.
 */

interface FakeNote extends TakeNote {
  title: string;
}

function fakeHost(notes: FakeNote[], target: FakeNote | null = null) {
  const calls: string[] = [];
  const host = quietHost<FakeNote>({
    notes: () => notes.map((n) => ({ id: n.id, title: n.title, note: n })),
    target: () => target,
    route: (view) => {
      if (view?.phase === 'said') calls.push(`said: ${view.text}`);
    },
    changeNote: (note, change, title) => {
      calls.push(`changed ${title}`);
      const next = change(note.body);
      if (next !== null) note.body = next;
    },
    newBook: (title, pages) => {
      calls.push(`book ${title}: ${pages.join(', ') || '(no pages)'}`);
    },
  });
  return { host, calls };
}

const say = (take: Take<FakeNote>, text: string, at: number) => take.phrase({ text, startMs: at, endMs: at + 900 }, at + 1000);
const guide = (): FakeNote => ({ id: 'f', title: 'Field guide', body: bookNoteBody('Field guide', ['Trees']) });

describe('a book by voice', () => {
  it('adds a chapter named in the next phrase to the book’s index, after a yes', () => {
    const book = guide();
    const { host, calls } = fakeHost([book, { id: 'b', title: 'Birds', body: '# Birds' }]);
    const take = new Take(host);
    say(take, 'Hey Ghost, add a chapter to the field guide.', 0);
    expect(take.offering).toBeNull();
    say(take, 'Rivers.', 2000);
    expect(take.offering).toMatchObject({ kind: 'change', title: 'Field guide', heading: 'New chapter', lines: ['Rivers'] });
    take.confirm(3500);
    expect(calls).toEqual(['changed Field guide']);
    expect(chaptersOf(book.body).map((c) => c.title)).toEqual(['Trees', 'Rivers']);
  });

  it('makes the note being recorded a chapter for "put this in", and says so when it has no name yet', () => {
    const birds: FakeNote = { id: 'b', title: 'Birds', body: '# Birds' };
    const onBirds = fakeHost([guide(), birds], birds);
    const take = new Take(onBirds.host);
    say(take, 'Hey Ghost, put this in the field guide.', 0);
    expect(take.offering).toMatchObject({ kind: 'change', lines: ['Birds'] });

    const fresh = fakeHost([guide()], null);
    const unnamed = new Take(fresh.host);
    say(unnamed, 'Hey Ghost, add this to the field guide.', 0);
    expect(unnamed.offering).toBeNull();
    expect(fresh.calls).toEqual(['said: This note has no name yet, so it can’t be a chapter.']);
  });

  it('does not offer a chapter the book has, or the book itself', () => {
    const { host, calls } = fakeHost([guide()]);
    const take = new Take(host);
    say(take, 'Hey Ghost, add Trees to the field guide.', 0);
    expect(take.offering).toBeNull();
    say(take, 'Hey Ghost, add a chapter called field guide to the field guide.', 5000);
    expect(take.offering).toBeNull();
    expect(calls).toEqual(['said: Trees is already in Field guide.', 'said: Field guide can’t be a chapter of itself.']);
  });

  it('makes a book by name with the notes named as its pages, through the host, after a yes', () => {
    const { host, calls } = fakeHost([guide(), { id: 'p', title: 'Packing list', body: '# Packing list' }]);
    const take = new Take(host);
    say(take, 'Hey Ghost, make a book called Trip with the packing list and maps.', 0);
    expect(take.offering).toEqual({ kind: 'book', title: 'Trip', pages: ['Packing list', 'Maps'], span: { startMs: 0, endMs: 900 } });
    take.confirm(2000);
    expect(calls).toEqual(['book Trip: Packing list, Maps']);
  });
});

describe('what a command did, in words', () => {
  it('says each added line by its words, whatever list it went into (core/itemSyntax.ts)', () => {
    // A starred or numbered to-do was said with its box: "add “[ ] Buy milk”".
    const offer = { kind: 'place', title: 'Shopping', added: ['* [ ] Buy milk', '2. [ ] Ring Sam', '-  Bread'], into: 'list' } as unknown as Offer<TakeNote>;
    expect(describeOffer(offer, 'done')).toBe('Did: add “Buy milk”, “Ring Sam”, “Bread” to Shopping’s list');
  });
});
