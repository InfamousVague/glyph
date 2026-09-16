import { describe, expect, it } from 'vitest';
import {
  addToBoard,
  anchorFor,
  boardCopy,
  boardFrom,
  boardsIn,
  cardText,
  cardsOf,
  columnFor,
  columnOf,
  doneColumn,
  isItemLine,
  itemAt,
  itemOnLine,
  itemsIn,
  moveCard,
  newCard,
  putCard,
  putCardAt,
  readBoard,
  refFor,
  refsIn,
  setItemDone,
  withAnchor,
  writeBoard,
} from './boards.ts';

const note = `# Launch week

\`\`\`board
To do: ship-page, email-list
In progress: fix-login
Done: pick-date
\`\`\`

- [ ] Ship the pricing page ^ship-page
- [ ] Email the beta list ^email-list
- [ ] Fix the login button ^fix-login
- [x] Pick a launch date ^pick-date
- [ ] Something not on the board
`;

describe('a board in markdown', () => {
  it('reads the columns and the cards in them', () => {
    const columns = readBoard('To do: ship-page, email-list\nIn progress: fix-login\nDone: pick-date');
    expect(columns.map((c) => c.name)).toEqual(['To do', 'In progress', 'Done']);
    expect(columns[0]?.cards).toEqual(['ship-page', 'email-list']);
    expect(columns[2]?.cards).toEqual(['pick-date']);
  });

  it('keeps an empty column, joins a name said twice, and ignores what is not an anchor', () => {
    const columns = readBoard('Blocked:\nTo do: a, Not An Anchor, b\nto do: c\n\n   \n: nothing');
    expect(columns.map((c) => c.name)).toEqual(['Blocked', 'To do']);
    expect(columns[0]?.cards).toEqual([]);
    expect(columns[1]?.cards).toEqual(['a', 'b', 'c']);
  });

  it('takes an anchor written with its caret, and drops a card named twice', () => {
    expect(readBoard('To do: ^a, a, ^b')[0]?.cards).toEqual(['a', 'b']);
  });

  it('writes the columns back the way a person types them', () => {
    const columns = readBoard('To do: a, b\nBlocked:\nDone: c');
    expect(writeBoard(columns)).toBe('To do: a, b\nBlocked:\nDone: c');
  });

  it('finds the boards in a note, with the lines their fences are on', () => {
    const boards = boardsIn(note);
    expect(boards).toHaveLength(1);
    expect(boards[0]?.from).toBe(3);
    expect(boards[0]?.to).toBe(7);
    expect(boards[0]?.columns).toHaveLength(3);
  });

  it('reads an unclosed fence as a board that has not been finished', () => {
    const boards = boardsIn('```board\nTo do: a\n');
    expect(boards[0]?.from).toBe(1);
    expect(boards[0]?.to).toBe(1);
    expect(boards[0]?.columns).toEqual([]);
  });
});

describe('the items a board points at', () => {
  it('finds every anchored item, with its words and its box', () => {
    const items = itemsIn(note);
    expect(items.map((t) => t.id)).toEqual(['ship-page', 'email-list', 'fix-login', 'pick-date']);
    expect(items[0]).toMatchObject({ text: 'Ship the pricing page', done: false, line: 9 });
    expect(items[3]?.done).toBe(true);
  });

  it('anchors any kind of list item, not only a to-do', () => {
    const items = itemsIn('- Ask Sam about the copy ^ask-sam\n1. Unplug it ^unplug\n* A star ^star\n- [x] Ticked ^ticked');
    expect(items.map((item) => item.id)).toEqual(['ask-sam', 'unplug', 'star', 'ticked']);
    // An item with no box has nothing to tick, which is not the same as being unticked.
    expect(items.map((item) => item.done)).toEqual([null, null, null, true]);
    expect(items[1]?.text).toBe('Unplug it');
  });

  it('leaves a superscript alone: an anchor needs a space before it and the line to end after it', () => {
    expect(itemOnLine('- E = mc^2^')).toBeNull();
    expect(itemOnLine('- the 2 ^nd^ of June')).toBeNull();
    expect(itemOnLine('- a fact ^unsure^ and more')).toBeNull();
    // The boundary: a closing caret makes it a superscript, and nothing else does.
    expect(itemOnLine('- item ^a^')).toBeNull();
    expect(itemOnLine('- Ship it ^ship-page')).toMatchObject({ id: 'ship-page', text: 'Ship it' });
  });

  it('reads an item whose words are not written yet, which is what the + on a column leaves behind', () => {
    expect(itemOnLine('- [ ] ^item')).toMatchObject({ id: 'item', text: '', done: false });
    expect(isItemLine('- [ ] ^item')).toBe(true);
    expect(setItemDone('- [ ] ^item', true)).toBe('- [x] ^item');
  });

  it('takes the first item of a repeated anchor', () => {
    expect(itemsIn('- [ ] One ^a\n- [ ] Two ^a')).toHaveLength(1);
  });

  it('knows a list item from a line of words, and finds an item by its anchor', () => {
    expect(isItemLine('- [ ] Ship it')).toBe(true);
    expect(isItemLine('  1. Unplug it')).toBe(true);
    expect(isItemLine('Just a line')).toBe(false);
    expect(isItemLine('- ')).toBe(false);
    expect(itemAt(note, 'fix-login')).toMatchObject({ text: 'Fix the login button', line: 11 });
    expect(itemAt(note, 'nowhere')).toBeNull();
  });

  it('reads one line, and ticks or clears it keeping its words and anchor', () => {
    expect(itemOnLine('  - [ ] Ship it ^ship-page')).toMatchObject({ id: 'ship-page', text: 'Ship it', done: false });
    expect(itemOnLine('- [ ] no anchor here')).toBeNull();
    expect(setItemDone('  - [ ] Ship it ^ship-page', true)).toBe('  - [x] Ship it ^ship-page');
    expect(setItemDone('- [X] Ship it ^ship-page', false)).toBe('- [ ] Ship it ^ship-page');
    expect(setItemDone('- [ ] No anchor', true)).toBe('- [x] No anchor');
    // A bullet has no box: ticking it would have to write one, and the note is the person's.
    expect(setItemDone('- Ask Sam ^ask-sam', true)).toBe('- Ask Sam ^ask-sam');
  });

  it('gives a line its anchor once', () => {
    expect(withAnchor('- Ask Sam  ', 'ask-sam')).toBe('- Ask Sam ^ask-sam');
    expect(withAnchor('- Ask Sam ^mine', 'ask-sam')).toBe('- Ask Sam ^mine');
  });

  it('pairs cards with their items, and says when one is gone', () => {
    const board = boardsIn(note)[0]!;
    const cards = cardsOf(board.columns, itemsIn(note));
    expect(cards).toHaveLength(4);
    expect(cards[0]).toMatchObject({ id: 'ship-page', column: 0 });
    expect(cards[0]?.item?.text).toBe('Ship the pricing page');
    const gone = cardsOf(readBoard('To do: nowhere'), itemsIn(note));
    expect(gone[0]).toMatchObject({ id: 'nowhere', item: null });
  });
});

describe('an anchor pointed at from the words', () => {
  it('is found anywhere in a line, and reads as the item it names', () => {
    const line = 'the copy is waiting on [[#^ask-sam]] and [[#^ship-page]]';
    expect(refsIn(line).map((ref) => ref.id)).toEqual(['ask-sam', 'ship-page']);
    expect(refsIn(line, 10)[0]?.from).toBe(33);
    expect(refFor('ask-sam')).toBe('[[#^ask-sam]]');
  });

  it('is not a link to another note, and takes only an anchor between the brackets', () => {
    expect(refsIn('[[The cabin trip]]')).toEqual([]);
    expect(refsIn('[[#^Not An Anchor]]')).toEqual([]);
    expect(refsIn('[[#^ok]]')).toHaveLength(1);
  });

  it('is said by a card as the anchor, not as its brackets', () => {
    expect(cardText('waiting on [[#^ask-sam]]')).toBe('waiting on ^ask-sam');
  });
});

describe('moving a card', () => {
  const columns = readBoard('To do: a, b\nDoing: c\nDone: d');

  it('goes one column along, and stops at either end', () => {
    expect(writeBoard(moveCard(columns, 'a', 1))).toBe('To do: b\nDoing: c, a\nDone: d');
    expect(writeBoard(moveCard(columns, 'a', -1))).toBe('To do: a, b\nDoing: c\nDone: d');
    expect(writeBoard(moveCard(columns, 'd', 1))).toBe('To do: a, b\nDoing: c\nDone: d');
    expect(writeBoard(moveCard(columns, 'nothing', 1))).toBe(writeBoard(columns));
  });

  it('is put in a column outright, and leaves the one it was in', () => {
    expect(writeBoard(putCard(columns, 'a', 2))).toBe('To do: b\nDoing: c\nDone: d, a');
    expect(writeBoard(putCard(columns, 'a', 0))).toBe('To do: b, a\nDoing: c\nDone: d');
    expect(writeBoard(putCard(columns, 'a', 9))).toBe(writeBoard(columns));
  });

  it('is dropped between two cards, at the place the gap was shown', () => {
    expect(writeBoard(putCardAt(columns, 'c', 0, 0))).toBe('To do: c, a, b\nDoing:\nDone: d');
    expect(writeBoard(putCardAt(columns, 'c', 0, 1))).toBe('To do: a, c, b\nDoing:\nDone: d');
    expect(writeBoard(putCardAt(columns, 'c', 0, 99))).toBe('To do: a, b, c\nDoing:\nDone: d');
  });

  it('is reordered inside its own column, counting the places without itself', () => {
    expect(writeBoard(putCardAt(columns, 'a', 0, 1))).toBe('To do: b, a\nDoing: c\nDone: d');
    expect(writeBoard(putCardAt(columns, 'b', 0, 0))).toBe('To do: b, a\nDoing: c\nDone: d');
    expect(writeBoard(putCardAt(columns, 'a', 0, 0))).toBe(writeBoard(columns));
    // The columns given are never changed, only answered anew.
    expect(columns[0]?.cards).toEqual(['a', 'b']);
  });

  it('knows which column is Done, and where a ticked item belongs', () => {
    expect(doneColumn(columns)).toBe(2);
    expect(doneColumn(readBoard('To do: a\nWaiting: b'))).toBe(-1);
    expect(columnOf(columns, 'c')).toBe(1);
    expect(columnFor(columns, { id: 'a', text: 'A', done: true, line: 1 })).toBe(2);
    expect(columnFor(columns, { id: 'a', text: 'A', done: false, line: 1 })).toBe(0);
    // An item with no box is wherever the board has it, ticks being nothing to do with it.
    expect(columnFor(columns, { id: 'c', text: 'C', done: null, line: 1 })).toBe(1);
    // With no Done column, a ticked item stays where the board has it.
    const plain = readBoard('To do: a\nWaiting: b');
    expect(columnFor(plain, { id: 'a', text: 'A', done: true, line: 1 })).toBe(0);
  });
});

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

describe('what a card says', () => {
  it('says a link by its words and drops the marks around them', () => {
    expect(cardText('Fix the [login button](https://example.com/a/very/long/url) *today*')).toBe('Fix the login button today');
    expect(cardText('Read <https://example.com/x>')).toBe('Read https://example.com/x');
    expect(cardText('  lots   of   room  ')).toBe('lots of room');
  });
});

describe('a board taken away as words', () => {
  it('gives the fence and the items it names, in the order the note has them', () => {
    expect(boardCopy(note, 4)).toBe(
      [
        '```board',
        'To do: ship-page, email-list',
        'In progress: fix-login',
        'Done: pick-date',
        '```',
        '',
        '- [ ] Ship the pricing page ^ship-page',
        '- [ ] Email the beta list ^email-list',
        '- [ ] Fix the login button ^fix-login',
        '- [x] Pick a launch date ^pick-date',
        '',
      ].join('\n'),
    );
  });

  it('is the same board again when it is pasted into an empty note', () => {
    const again = boardCopy(note, 3)!;
    expect(boardsIn(again)[0]?.columns).toEqual(boardsIn(note)[0]?.columns);
    expect(itemsIn(again).map((item) => item.id)).toEqual(['ship-page', 'email-list', 'fix-login', 'pick-date']);
  });

  it('takes a board with no items yet, and answers nothing off a board', () => {
    expect(boardCopy('```board\nTo do:\n```', 2)).toBe('```board\nTo do:\n```\n');
    expect(boardCopy(note, 9)).toBeNull();
    expect(boardCopy('- [ ] Alone', 1)).toBeNull();
  });
});
