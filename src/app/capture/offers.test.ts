import { describe, expect, it } from 'vitest';
import { bookNoteBody } from '../book/book.ts';
import type { Placement } from './command.ts';
import { offerFor, type OfferContext } from './offers.ts';
import type { TakeNote } from './takeTypes.ts';

/** What each plan comes to before its yes (capture/offers.ts): the card's offer, a reason said instead, or nothing. */

const named = (id: string, title: string, body: string) => ({ id, title, note: { id, body } as TakeNote });
const span = { startMs: 1000, endMs: 2400 };
const leave: Placement = { how: 'leave', task: false, many: false, target: null };
const onNewNote: OfferContext = { ownTitle: () => null, targetId: () => null };

describe('a plan to put words in a note', () => {
  it('offers the lines as they would land in its list', () => {
    const work = named('w', 'Work', '# Work\n\n- Email Jo');
    const made = offerFor({ kind: 'place', note: work, text: 'call Sam', ...leave }, span, onNewNote);
    expect(made).toEqual({ offer: { kind: 'place', note: work.note, title: 'Work', text: 'call Sam', placement: { kind: 'place', note: work, text: 'call Sam', ...leave }, added: ['- Call Sam'], into: 'list', span } });
  });

  it('offers nothing for words that would add nothing', () => {
    expect(offerFor({ kind: 'place', note: named('w', 'Work', '# Work'), text: '  ', ...leave }, span, onNewNote)).toBeNull();
  });

  it('offers nothing for a plan still waiting, or a name that matched no note', () => {
    expect(offerFor({ kind: 'no-note', name: 'oven' }, span, onNewNote)).toBeNull();
    expect(offerFor({ kind: 'await', note: named('w', 'Work', '# Work'), ...leave }, span, onNewNote)).toBeNull();
    expect(offerFor({ kind: 'table', note: null, columns: [] }, span, onNewNote)).toBeNull();
  });
});

describe('a plan for a board’s lane', () => {
  const board = named('b', 'Launch', '# Launch');
  it('offers the change it will make, headed by the lane', () => {
    const change = (body: string) => `${body}\n- Fix login`;
    expect(offerFor({ kind: 'lane', note: board, lane: 'Doing', words: 'Fix login', change }, span, onNewNote)).toMatchObject({
      offer: { kind: 'change', title: 'Launch', heading: 'Add to Doing', action: 'Add', lines: ['Fix login'] },
    });
    expect(offerFor({ kind: 'card', note: board, lane: 'Done', words: 'pricing page', change }, span, onNewNote)).toMatchObject({
      offer: { heading: 'Move to Done', action: 'Move' },
    });
  });

  it('says why when there is nothing to move or add', () => {
    const nothing = () => null;
    expect(offerFor({ kind: 'card', note: board, lane: 'Done', words: 'pricing page', change: nothing }, span, onNewNote)).toEqual({ refused: 'No item like “pricing page” in Launch.' });
    expect(offerFor({ kind: 'lane', note: board, lane: 'Doing', words: '', change: nothing }, span, onNewNote)).toEqual({ refused: 'Nothing to add to Doing.' });
  });
});

describe('a plan for a book’s chapter', () => {
  const guide = named('g', 'Field guide', bookNoteBody('Field guide', ['Trees']));

  it('offers a named chapter as one more line of the index, and the change adds it once', () => {
    const made = offerFor({ kind: 'chapter', note: guide, title: 'Rivers' }, span, onNewNote);
    expect(made).toMatchObject({ offer: { kind: 'change', heading: 'New chapter', lines: ['Rivers'] } });
    if (!made || !('offer' in made) || made.offer.kind !== 'change') throw new Error('expected a change');
    const once = made.offer.change(guide.note.body);
    expect(once).toContain('Rivers');
    expect(made.offer.change(once ?? '')).toBeNull();
  });

  it('takes the note being recorded as the chapter when none is named, and refuses one with no name yet', () => {
    const onBirds: OfferContext = { ownTitle: () => 'Birds', targetId: () => 'birds' };
    expect(offerFor({ kind: 'chapter', note: guide, title: null }, span, onBirds)).toMatchObject({ offer: { lines: ['Birds'] } });
    expect(offerFor({ kind: 'chapter', note: guide, title: null }, span, onNewNote)).toEqual({ refused: 'This note has no name yet, so it can’t be a chapter.' });
  });

  it('refuses the book as its own chapter, and one it already has', () => {
    expect(offerFor({ kind: 'chapter', note: guide, title: 'field guide' }, span, onNewNote)).toEqual({ refused: 'Field guide can’t be a chapter of itself.' });
    const insideIt: OfferContext = { ownTitle: () => 'Notes', targetId: () => 'g' };
    expect(offerFor({ kind: 'chapter', note: guide, title: null }, span, insideIt)).toEqual({ refused: 'Field guide can’t be a chapter of itself.' });
    expect(offerFor({ kind: 'chapter', note: guide, title: 'trees' }, span, onNewNote)).toEqual({ refused: 'trees is already in Field guide.' });
  });

  it('asks the take for the note’s title only when it needs it', () => {
    let asked = 0;
    const counting: OfferContext = { ownTitle: () => (asked += 1, 'Birds'), targetId: () => null };
    offerFor({ kind: 'move', note: guide }, span, counting);
    expect(asked).toBe(0);
  });
});

describe('the other plans', () => {
  it('offer what they name, with the span they were said in', () => {
    const work = named('w', 'Work', '# Work');
    expect(offerFor({ kind: 'move', note: work }, span, onNewNote)).toEqual({ offer: { kind: 'move', note: work.note, title: 'Work', span } });
    expect(offerFor({ kind: 'board' }, span, onNewNote)).toEqual({ offer: { kind: 'board', title: 'this note', span } });
    expect(offerFor({ kind: 'book', title: 'Trip', pages: ['Maps'] }, span, onNewNote)).toEqual({ offer: { kind: 'book', title: 'Trip', pages: ['Maps'], span } });
    expect(offerFor({ kind: 'new' }, span, onNewNote)).toEqual({ offer: { kind: 'new', span } });
  });

  it('offer a new list with its items when some were said, and without lines when none were', () => {
    expect(offerFor({ kind: 'create-list', title: 'Comic books', items: ['Batman', 'Superman'] }, span, onNewNote)).toEqual({ offer: { kind: 'new', title: 'Comic books', lines: ['Batman', 'Superman'], span } });
    expect(offerFor({ kind: 'create-list', title: 'Comic books', items: [] }, span, onNewNote)).toEqual({ offer: { kind: 'new', title: 'Comic books', span } });
  });
});
