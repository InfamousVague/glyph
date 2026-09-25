import { describe, expect, it } from 'vitest';
import {
  addToBoard,
  anchorFor,
  boardFrom,
  boardFromList,
  boardsIn,
  cardsOf,
  itemOnLine,
  itemsIn,
  listAround,
  newCard,
} from '../boards.ts';
import { LAUNCH_WEEK as note } from '../../../test/boards.ts';

/**
 * Boards and cards made from a note's lists: an item put on its list's board, a card added from the board, and a
 * note or one list made into a board.
 *
 * core/boards/make.ts, reached as every caller reaches it: through the room’s door, core/boards.ts.
 */

describe('putting a list item on a board', () => {
  it('names an item that has no anchor, from its own words', () => {
    expect(anchorFor('Book the ferry before Friday', [])).toBe('book-ferry-before');
    expect(anchorFor('Book the ferry', ['book-ferry'])).toBe('book-ferry-2');
    expect(anchorFor('!!!', [])).toBe('item');
  });

  it('leaves the filler out, so two items that start alike are not named alike', () => {
    expect(anchorFor('Add ability to auto-tag notes', [])).toBe('add-ability-auto');
    expect(anchorFor('Add ability to add tags', [])).toBe('add-ability-add');
    expect(anchorFor('Git icon is messed up', [])).toBe('git-icon-messed');
    expect(anchorFor('The fade in is too slow', [])).toBe('fade-too-slow');
    // Words that are all filler keep them, rather than come out as nothing.
    expect(anchorFor('Is it on', [])).toBe('is-it-on');
  });

  it('adds the card to the first column, and gives the line its anchor', () => {
    const added = addToBoard(note, 13)!;
    expect(added.id).toBe('something-not-board');
    expect(added.line).toEqual({ number: 13, text: '- [ ] Something not on the board ^something-not-board' });
    expect(added.fence).toMatchObject({ from: 3, to: 7 });
    expect(added.fence.body.split('\n')[0]).toBe('To do: ship-page, email-list, something-not-board');
    expect(added.column).toBe('To do');
  });

  it('takes a bullet as readily as a to-do', () => {
    const doc = note.replace('- [ ] Something not on the board', '- Ask Sam about the copy');
    const added = addToBoard(doc, 13)!;
    expect(added.id).toBe('ask-sam-about');
    expect(added.line?.text).toBe('- Ask Sam about the copy ^ask-sam-about');
    expect(added.column).toBe('To do');
  });

  it('uses the board its own list is already on, not the nearest one above', () => {
    // Two boards: the list at the foot belongs to the second, though the first is also above it.
    const doc = [
      '```board',
      'To do: alpha',
      'Done:',
      '```',
      '',
      '- [ ] Alpha ^alpha',
      '',
      '## Later',
      '',
      '```board',
      'Next: beta',
      'Done:',
      '```',
      '',
      '- [ ] Beta ^beta',
      '- [ ] Gamma',
      '',
    ].join('\n');
    const added = addToBoard(doc, 16)!;
    expect(added.fence).toMatchObject({ from: 10, to: 13 });
    expect(added.fence.body).toBe('Next: beta, gamma\nDone:');
    expect(added.column).toBe('Next');
  });

  it('goes in beside the neighbour it follows in the list, keeping the list\u2019s order', () => {
    const doc = ['```board', 'To do: one, three', 'Done:', '```', '', '- [ ] One ^one', '- [ ] Two', '- [ ] Three ^three', ''].join('\n');
    // Two sits between one and three in the list, so its card goes between theirs.
    expect(addToBoard(doc, 7)?.fence.body).toBe('To do: one, two, three\nDone:');
  });

  it('is not offered for an item already on the board', () => {
    expect(addToBoard(note, 9)).toBeNull();
    expect(addToBoard(note, 1)).toBeNull();
  });

  it('puts a ticked item straight in Done, and keeps the anchor it has', () => {
    const doc = note.replace('- [ ] Something not on the board', '- [x] Something not on the board ^later');
    const added = addToBoard(doc, 13)!;
    expect(added.id).toBe('later');
    expect(added.line).toBeNull();
    expect(added.column).toBe('Done');
    expect(added.fence.body).toContain('Done: pick-date, later');
  });

  it('answers nothing for a line that is no list item, a note with no board, or an item already on one', () => {
    expect(addToBoard(note, 1)).toBeNull();
    expect(addToBoard('- [ ] Alone in the world', 1)).toBeNull();
    expect(addToBoard(note, 9)).toBeNull();
  });
});

describe('a card added from the board itself', () => {
  it('writes a to-do with its words under the last item the board names, named after them', () => {
    const made = newCard(note, 3, 1, 'Rename the weak anchors')!;
    expect(made.id).toBe('rename-weak-anchors');
    expect(made.at).toBe(13);
    // A real task list item anywhere: a space after the box, the words, then the anchor.
    expect(made.text).toBe('- [ ] Rename the weak anchors ^rename-weak-anchors');
    expect(itemOnLine(made.text)).toMatchObject({ id: 'rename-weak-anchors', text: 'Rename the weak anchors', done: false });
  });

  it('puts the card at the top of the column tapped, or where it is told', () => {
    expect(newCard(note, 3, 1, 'Book the ferry')!.fence.body).toBe('To do: ship-page, email-list\nIn progress: book-ferry, fix-login\nDone: pick-date');
    expect(newCard(note, 3, 0, 'Book the ferry', 99)!.fence.body.split('\n')[0]).toBe('To do: ship-page, email-list, book-ferry');
  });

  it('makes nothing without words, so no card is ever named after nothing', () => {
    expect(newCard(note, 3, 0, '')).toBeNull();
    expect(newCard(note, 3, 0, '   ')).toBeNull();
  });

  it('keeps each name its own, and tidies the words it is given', () => {
    const made = newCard(note, 3, 0, '  Ship   the page  ')!;
    expect(made.text).toBe('- [ ] Ship the page ^ship-page-2');
  });

  it('goes under the fence when the board names nothing yet, and answers nothing off a board', () => {
    const empty = '```board\nTo do:\nDone:\n```\n';
    expect(newCard(empty, 1, 0, 'First')).toMatchObject({ at: 5, text: '- [ ] First ^first' });
    expect(newCard(note, 9, 0, 'Words')).toBeNull();
    expect(newCard(note, 3, 7, 'Words')).toBeNull();
  });
});

describe('a list made into a board', () => {
  const list = [
    '# Task Management',
    '',
    '- [ ] Ship the pricing page',
    '- [x] Pick a launch date',
    '- [ ] Email the [beta list](https://example.com/list)',
    '',
  ].join('\n');

  it('anchors every item and lays the columns out under the title', () => {
    const made = boardFrom(list)!;
    expect(made.cards).toBe(3);
    expect(made.done).toBe(1);
    expect(made.doc.split('\n')).toEqual([
      '# Task Management',
      '',
      '```board',
      'To do: ship-pricing-page, email-beta-list',
      'Doing:',
      'Done: pick-launch-date',
      '```',
      '',
      '- [ ] Ship the pricing page ^ship-pricing-page',
      '- [x] Pick a launch date ^pick-launch-date',
      '- [ ] Email the [beta list](https://example.com/list) ^email-beta-list',
      '',
    ]);
  });

  it('reads back as the board it looks like', () => {
    const made = boardFrom(list)!;
    const board = boardsIn(made.doc)[0]!;
    const cards = cardsOf(board.columns, itemsIn(made.doc));
    expect(cards.map((card) => card.item?.text)).toEqual(['Ship the pricing page', 'Email the [beta list](https://example.com/list)', 'Pick a launch date']);
  });

  it('takes a plain list as well, whose cards have no box to tick', () => {
    const made = boardFrom('- Oat milk\n- Rye bread')!;
    expect(made.cards).toBe(2);
    expect(made.done).toBe(0);
    expect(made.doc.split('\n').slice(6)).toEqual(['- Oat milk ^oat-milk', '- Rye bread ^rye-bread']);
    expect(itemsIn(made.doc).map((item) => item.done)).toEqual([null, null]);
  });

  it('leaves a list inside a block of code exactly as it is', () => {
    const made = boardFrom('- Real item\n\n```md\n- [ ] not a task, an example\n```\n')!;
    expect(made.cards).toBe(1);
    expect(made.doc).toContain('- [ ] not a task, an example\n');
    expect(made.doc).not.toContain('example ^');
  });

  it('keeps an anchor an item already has, and leaves the words alone', () => {
    const made = boardFrom('- [ ] Already named ^mine\n- [ ] The other one')!;
    expect(made.doc.split('\n').slice(6)).toEqual(['- [ ] Already named ^mine', '- [ ] The other one ^other-one']);
    expect(made.doc.split('\n')[1]).toBe('To do: mine, other-one');
  });

  it('takes the columns it is given, and puts what is ticked in the one called Done', () => {
    const made = boardFrom('- [x] One\n- [ ] Two', ['Later', 'Done now'])!;
    expect(made.doc.split('\n').slice(0, 4)).toEqual(['```board', 'Later: two', 'Done now: one', '```']);
  });

  it('answers nothing for a note with no list, or one that is a board already', () => {
    expect(boardFrom('# Notes\n\nJust words.')).toBeNull();
    expect(boardFrom(note)).toBeNull();
  });
});

describe('one list made into a board', () => {
  // Matt: "add ability to auto list a section of list items into a board".
  const doc = [
    '# Trip',
    '',
    'Packing:',
    '- [ ] Tent',
    '- [x] Stove',
    '  bring the spare gas',
    '',
    '- [ ] Maps',
    '',
    '',
    '- Not this list',
    '',
    '## Errands',
    '1. Post office',
    '2. Bank',
    '',
    '```md',
    '- [ ] an example, not a list',
    '```',
  ].join('\n');

  it('finds the list a line is in, blank line and indented lines included, and stops at two blank lines', () => {
    expect(listAround(doc, 4)).toEqual({ from: 4, to: 8 });
    expect(listAround(doc, 6)).toEqual({ from: 4, to: 8 });
    expect(listAround(doc, 8)).toEqual({ from: 4, to: 8 });
    expect(listAround(doc, 11)).toEqual({ from: 11, to: 11 });
    expect(listAround(doc, 15)).toEqual({ from: 14, to: 15 });
  });

  it('finds no list on a line of words, a heading, a blank line, or inside a block of code', () => {
    expect(listAround(doc, 3)).toBeNull();
    expect(listAround(doc, 13)).toBeNull();
    expect(listAround(doc, 9)).toBeNull();
    expect(listAround(doc, 18)).toBeNull();
  });

  it('makes that list a board set in just above it, and leaves everything else alone', () => {
    const made = boardFromList(doc, 4, 8)!;
    expect(made).toMatchObject({ cards: 3, done: 1, open: 5 });
    expect(made.doc.split('\n').slice(2, 14)).toEqual([
      'Packing:',
      '',
      '```board',
      'To do: tent, maps',
      'Doing:',
      'Done: stove',
      '```',
      '',
      '- [ ] Tent ^tent',
      '- [x] Stove ^stove',
      '  bring the spare gas',
      '',
    ]);
    // The other lists are untouched.
    expect(made.doc).toContain('- Not this list\n');
    expect(made.doc).toContain('1. Post office\n2. Bank\n');
  });

  it('says what to change in the note as it was: the item lines, and the fence to put in above the list', () => {
    const made = boardFromList(doc, 4, 8)!;
    expect(made.lines).toEqual([
      { number: 4, text: '- [ ] Tent ^tent' },
      { number: 5, text: '- [x] Stove ^stove' },
      { number: 8, text: '- [ ] Maps ^maps' },
    ]);
    expect(made.fence).toEqual({ before: 4, text: '\n```board\nTo do: tent, maps\nDoing:\nDone: stove\n```\n\n' });
    // Applied that way round, the note is the one `doc` says.
    const lines = doc.split('\n');
    for (const line of made.lines) lines[line.number - 1] = line.text;
    lines[made.fence.before - 1] = `${made.fence.text}${lines[made.fence.before - 1]}`;
    expect(lines.join('\n')).toBe(made.doc);
  });

  it('can be done while the note has another board, and not twice to the same list', () => {
    const first = boardFromList(doc, 14, 15)!;
    // Straight under a heading, the board keeps a blank line from it.
    expect(first.open).toBe(15);
    expect(first.doc.split('\n').slice(12, 21)).toEqual(['## Errands', '', '```board', 'To do: post-office, bank', 'Doing:', 'Done:', '```', '', '1. Post office ^post-office']);
    expect(boardsIn(first.doc)).toHaveLength(1);
    const again = boardFromList(first.doc, 4, 8)!;
    expect(boardsIn(again.doc)).toHaveLength(2);
    // The list under the new board is already a board.
    const list = listAround(first.doc, 21)!;
    expect(list).toEqual({ from: 21, to: 22 });
    expect(boardFromList(first.doc, list.from, list.to)).toBeNull();
  });

  it('keeps anchors an item has, and makes nothing of lines with no items', () => {
    const made = boardFromList('- [ ] Tent ^mine\n- Stove', 1, 2)!;
    expect(made.doc).toBe('```board\nTo do: mine, stove\nDoing:\nDone:\n```\n\n- [ ] Tent ^mine\n- Stove ^stove');
    expect(made.lines).toEqual([{ number: 2, text: '- Stove ^stove' }]);
    expect(boardFromList(doc, 1, 3)).toBeNull();
  });
});
