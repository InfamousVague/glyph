import { describe, expect, it } from 'vitest';
import type { Offer } from '../capture/take.ts';
import type { Note } from '../core/store.ts';
import { show } from '../../test/render.tsx';
import { ConfirmCard } from './ConfirmCard.tsx';

/**
 * The confirm card's lines: what a command is about to add, said by its words the way every list line is read
 * (core/itemSyntax.ts), whichever list it goes into and however the list is marked.
 */

const showCard = (offer: Offer<Note>) => show(<ConfirmCard offer={offer} onConfirm={() => undefined} onCancel={() => undefined} />);

describe('the confirm card', () => {
  it('shows each line it will add by its words, a starred or numbered to-do too (core/itemSyntax.ts)', () => {
    // A `* [ ]` or numbered to-do list grows by lines like these (capture/listAppend.ts); the card said "[ ] Buy milk".
    const offer = {
      kind: 'place',
      title: 'Shopping',
      text: 'buy milk, ring Sam, bread',
      placement: { how: 'item', task: false, many: true, target: null },
      added: ['* [ ] Buy milk', '2. [ ] Ring Sam', '-  Bread'],
      into: 'list',
    } as unknown as Offer<Note>;
    const el = showCard(offer);
    const lines = [...el.querySelectorAll('p')].map((p) => p.textContent);
    expect(lines).toContain('Buy milk');
    expect(lines).toContain('Ring Sam');
    expect(lines).toContain('Bread');
    expect(el.textContent).not.toContain('[ ]');
  });
});
