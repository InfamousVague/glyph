import { describe, expect, it } from 'vitest';
import type { Placement } from './command.ts';
import { describeOffer, offerFor } from './offers.ts';
import type { TakeNote } from './takeTypes.ts';

/** What each plan read at Done comes to before its tap (capture/offers.ts): the card's offer, or nothing. */

const named = (id: string, title: string, body: string) => ({ id, title, note: { id, body } as TakeNote });
const leave: Placement = { how: 'leave', task: false, many: false, target: null };

describe('a plan to put words in a note', () => {
  it('offers the lines as they would land in its list', () => {
    const work = named('w', 'Work', '# Work\n\n- Email Jo');
    const made = offerFor({ kind: 'place', note: work, text: 'call Sam', ...leave });
    expect(made).toEqual({ kind: 'place', note: work.note, title: 'Work', text: 'call Sam', placement: { kind: 'place', note: work, text: 'call Sam', ...leave }, added: ['- Call Sam'], into: 'list' });
  });

  it('offers nothing for words that would add nothing', () => {
    expect(offerFor({ kind: 'place', note: named('w', 'Work', '# Work'), text: '  ', ...leave })).toBeNull();
  });
});

describe('a plan for a new list', () => {
  it('offers the list with its items when some were said, and without lines when none were', () => {
    expect(offerFor({ kind: 'create-list', title: 'Comic books', items: ['Batman', 'Superman'] })).toEqual({ kind: 'new', title: 'Comic books', lines: ['Batman', 'Superman'] });
    expect(offerFor({ kind: 'create-list', title: 'Comic books', items: [] })).toEqual({ kind: 'new', title: 'Comic books' });
  });
});

describe('what came of an offer, in words', () => {
  it('says what it did, or that the person said no', () => {
    const offer = offerFor({ kind: 'create-list', title: 'Comic books' })!;
    expect(describeOffer(offer, 'done')).toBe('Did: create Comic books');
    expect(describeOffer(offer, 'declined')).toBe('Offered to create Comic books; the person said no');
  });
});
