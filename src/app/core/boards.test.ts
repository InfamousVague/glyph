import { describe, expect, it } from 'vitest';
import {
  addToBoard,
  boardFrom,
  cardText,
  anchorFor,
  boardsIn,
  cardsOf,
  columnFor,
  columnOf,
  doneColumn,
  moveCard,
  putCard,
  readBoard,
  setTaskDone,
  taskOnLine,
  tasksIn,
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

describe('the tasks a board points at', () => {
  it('finds every anchored to-do, with its words and its box', () => {
    const tasks = tasksIn(note);
    expect(tasks.map((t) => t.id)).toEqual(['ship-page', 'email-list', 'fix-login', 'pick-date']);
    expect(tasks[0]).toMatchObject({ text: 'Ship the pricing page', done: false, line: 9 });
    expect(tasks[3]?.done).toBe(true);
  });

  it('takes the first task of a repeated anchor', () => {
    expect(tasksIn('- [ ] One ^a\n- [ ] Two ^a')).toHaveLength(1);
  });

  it('reads one line, and ticks or clears it keeping its words and anchor', () => {
    expect(taskOnLine('  - [ ] Ship it ^ship-page')).toMatchObject({ id: 'ship-page', text: 'Ship it', done: false });
    expect(taskOnLine('- [ ] no anchor here')).toBeNull();
    expect(setTaskDone('  - [ ] Ship it ^ship-page', true)).toBe('  - [x] Ship it ^ship-page');
    expect(setTaskDone('- [X] Ship it ^ship-page', false)).toBe('- [ ] Ship it ^ship-page');
    expect(setTaskDone('- [ ] No anchor', true)).toBe('- [x] No anchor');
  });

  it('pairs cards with their tasks, and says when one is gone', () => {
    const board = boardsIn(note)[0]!;
    const cards = cardsOf(board.columns, tasksIn(note));
    expect(cards).toHaveLength(4);
    expect(cards[0]).toMatchObject({ id: 'ship-page', column: 0 });
    expect(cards[0]?.task?.text).toBe('Ship the pricing page');
    const gone = cardsOf(readBoard('To do: nowhere'), tasksIn(note));
    expect(gone[0]).toMatchObject({ id: 'nowhere', task: null });
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
    expect(writeBoard(putCard(columns, 'a', 0))).toBe(writeBoard(columns));
    expect(writeBoard(putCard(columns, 'a', 9))).toBe(writeBoard(columns));
  });

  it('knows which column is Done, and where a ticked task belongs', () => {
    expect(doneColumn(columns)).toBe(2);
    expect(doneColumn(readBoard('To do: a\nWaiting: b'))).toBe(-1);
    expect(columnOf(columns, 'c')).toBe(1);
    expect(columnFor(columns, { id: 'a', text: 'A', done: true, line: 1 })).toBe(2);
    expect(columnFor(columns, { id: 'a', text: 'A', done: false, line: 1 })).toBe(0);
    // With no Done column, a ticked task stays where the board has it.
    const plain = readBoard('To do: a\nWaiting: b');
    expect(columnFor(plain, { id: 'a', text: 'A', done: true, line: 1 })).toBe(0);
  });
});

describe('putting a to-do on a board', () => {
  it('names a task that has no anchor, from its own words', () => {
    expect(anchorFor('Book the ferry before Friday', [])).toBe('book-the-ferry');
    expect(anchorFor('Book the ferry', ['book-the-ferry'])).toBe('book-the-ferry-2');
    expect(anchorFor('!!!', [])).toBe('task');
  });

  it('adds the card to the first column, and gives the line its anchor', () => {
    const added = addToBoard(note, 13)!;
    expect(added.id).toBe('something-not-on');
    expect(added.line).toEqual({ number: 13, text: '- [ ] Something not on the board ^something-not-on' });
    expect(added.fence).toMatchObject({ from: 3, to: 7 });
    expect(added.fence.body.split('\n')[0]).toBe('To do: ship-page, email-list, something-not-on');
    expect(added.column).toBe('To do');
  });

  it('puts a ticked task straight in Done, and keeps the anchor it has', () => {
    const doc = note.replace('- [ ] Something not on the board', '- [x] Something not on the board ^later');
    const added = addToBoard(doc, 13)!;
    expect(added.id).toBe('later');
    expect(added.line).toBeNull();
    expect(added.column).toBe('Done');
    expect(added.fence.body).toContain('Done: pick-date, later');
  });

  it('answers nothing for a line that is not a to-do, a note with no board, or a task already on one', () => {
    expect(addToBoard(note, 1)).toBeNull();
    expect(addToBoard('- [ ] Alone in the world', 1)).toBeNull();
    expect(addToBoard(note, 9)).toBeNull();
  });
});

describe('a list of to-dos made into a board', () => {
  const list = [
    '# Task Management',
    '',
    '- [ ] Ship the pricing page',
    '- [x] Pick a launch date',
    '- [ ] Email the [beta list](https://example.com/list)',
    '',
  ].join('\n');

  it('anchors every to-do and lays the columns out under the title', () => {
    const made = boardFrom(list)!;
    expect(made.cards).toBe(3);
    expect(made.done).toBe(1);
    expect(made.doc.split('\n')).toEqual([
      '# Task Management',
      '',
      '```board',
      'To do: ship-the-pricing, email-the-beta',
      'Doing:',
      'Done: pick-a-launch',
      '```',
      '',
      '- [ ] Ship the pricing page ^ship-the-pricing',
      '- [x] Pick a launch date ^pick-a-launch',
      '- [ ] Email the [beta list](https://example.com/list) ^email-the-beta',
      '',
    ]);
  });

  it('reads back as the board it looks like', () => {
    const made = boardFrom(list)!;
    const board = boardsIn(made.doc)[0]!;
    const cards = cardsOf(board.columns, tasksIn(made.doc));
    expect(cards.map((card) => card.task?.text)).toEqual(['Ship the pricing page', 'Email the [beta list](https://example.com/list)', 'Pick a launch date']);
  });

  it('keeps an anchor a task already has, and leaves the words alone', () => {
    const made = boardFrom('- [ ] Already named ^mine\n- [ ] The other one')!;
    expect(made.doc.split('\n').slice(6)).toEqual(['- [ ] Already named ^mine', '- [ ] The other one ^the-other-one']);
    expect(made.doc.split('\n')[1]).toBe('To do: mine, the-other-one');
  });

  it('takes the columns it is given, and puts what is ticked in the one called Done', () => {
    const made = boardFrom('- [x] One\n- [ ] Two', ['Later', 'Done now'])!;
    expect(made.doc.split('\n').slice(0, 4)).toEqual(['```board', 'Later: two', 'Done now: one', '```']);
  });

  it('answers nothing for a note with no to-dos, or one that is a board already', () => {
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
