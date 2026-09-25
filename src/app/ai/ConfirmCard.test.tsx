import { describe, expect, it, vi } from 'vitest';
import { listTitle } from '../capture/instructionMutation.ts';
import type { Offer } from '../capture/take.ts';
import type { Note } from '../core/store.ts';
import { makeNote } from '../../test/notes.ts';
import { button, press, show, unmount } from '../../test/render.tsx';
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

  it('heads each kind of command with what it will do, and names its button for it', () => {
    const span = { startMs: 0, endMs: 0 };
    const note = makeNote('n', '# Groceries');
    const cases: [Offer<Note>, string, string, string | null][] = [
      [{ kind: 'place', note, title: 'Groceries', text: 'eggs', placement: { target: 'dairy' }, added: ['- eggs'], into: 'paragraph', span } as unknown as Offer<Note>, 'Add to Groceries', 'Add', 'As a new paragraph, then to Dairy'],
      [{ kind: 'change', note, title: 'Groceries', heading: 'Tick eggs', action: 'Tick', lines: ['- [x] eggs'], change: () => null, span }, 'Tick eggs in Groceries', 'Tick', null],
      [{ kind: 'board', title: 'Launch', span }, 'Make this note a board', 'Make it', 'Its list items become cards'],
      [{ kind: 'book', title: 'Field guide', pages: ['Trees', 'Birds'], span }, 'Make a book called Field guide', 'Make it', 'Its pages, in this order'],
      [{ kind: 'book', title: 'Field guide', pages: [], span }, 'Make a book called Field guide', 'Make it', 'Empty, with its index ready'],
      [{ kind: 'move', note, title: 'Groceries', span }, 'Move this recording to Groceries', 'Move', null],
      [{ kind: 'new', title: 'comic books', lines: ['- Saga'], span }, `Create ${listTitle('comic books')}`, 'Create', 'As a new list'],
      [{ kind: 'new', span }, 'Start a new note from here', 'Start', null],
      [{ kind: 'table', note, title: 'Groceries', columns: ['What'], rows: [['eggs']], markdown: '', span }, 'Add this table to Groceries', 'Add', '1 row, at the end of the note'],
    ];
    for (const [offer, heading, action, detail] of cases) {
      unmount();
      const el = showCard(offer);
      expect(el.querySelector('section')?.getAttribute('aria-label'), heading).toBe(heading);
      expect(el.querySelector('.app-pill')?.textContent, heading).toBe(action);
      if (detail) expect(el.textContent, heading).toContain(detail);
    }
  });

  it('confirms or cancels, and says a yes or a no will do when the recorder asks', () => {
    const onConfirm = vi.fn();
    const onCancel = vi.fn();
    const offer = { kind: 'board', title: 'Launch', span: { startMs: 0, endMs: 0 } } as Offer<Note>;
    const el = show(<ConfirmCard offer={offer} onConfirm={onConfirm} onCancel={onCancel} hint="Say yes or no." />);
    press(button('Make it', el));
    press(button('Cancel', el));
    expect(onConfirm).toHaveBeenCalledTimes(1);
    expect(onCancel).toHaveBeenCalledTimes(1);
    expect(el.textContent).toContain('Say yes or no.');
  });
});
