import { describe, expect, it } from 'vitest';
import {
  BOARD_HEIGHT,
  boardCopy,
  boardsIn,
  clampHeight,
  itemsIn,
  readBoard,
  withBoardHeight,
  writeBoard,
} from '../boards.ts';
import { LAUNCH_WEEK as note } from '../../../test/boards.ts';

/**
 * The ```board fence: columns read and written, ids read against the note's anchors, the lanes' height, and a board
 * taken away as words.
 *
 * core/boards/fence.ts, reached as every caller reaches it: through the room’s door, core/boards.ts.
 */

describe('a board in markdown', () => {
  it('reads the columns and the cards in them', () => {
    const columns = readBoard('To do: ship-page, email-list\nIn progress: fix-login\nDone: pick-date');
    expect(columns.map((c) => c.name)).toEqual(['To do', 'In progress', 'Done']);
    expect(columns[0]?.cards).toEqual(['ship-page', 'email-list']);
    expect(columns[2]?.cards).toEqual(['pick-date']);
  });

  it('gives an id in two lanes to the first of them, so a card is never drawn twice', () => {
    const doc = '```board\nTo do: alpha, beta\nDoing: alpha\nDone:\n```\n\n- [ ] Alpha ^alpha\n- [ ] Beta ^beta\n';
    const columns = boardsIn(doc)[0]!.columns;
    expect(columns.map((column) => column.cards)).toEqual([['alpha', 'beta'], [], []]);
    // Written back, the note says what the board shows: the second mention is gone, not drawn in a lane of its own.
    expect(writeBoard(columns)).toBe('To do: alpha, beta\nDoing:\nDone:');
  });

  it('reads a lane id written as words when the note has that anchor, and leaves other words alone', () => {
    const doc = '```board\nTo do: Fix Login, ^Add Controls To\nDoing: Sam to reply\n```\n\n- [ ] Fix login ^fix-login\n- [ ] Add controls ^add-controls-to\n';
    const columns = boardsIn(doc)[0]!.columns;
    expect(columns.map((column) => column.cards)).toEqual([['fix-login', 'add-controls-to'], []]);
    // An id no item answers is not made up out of words after the colon; a plain anchor still is, and shows as missing.
    expect(boardsIn('```board\nTo do: ship-page\n```\n')[0]?.columns[0]?.cards).toEqual(['ship-page']);
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

describe('how tall a board is', () => {
  it('is read from the fence, and is the board\u2019s own height when the fence says nothing', () => {
    expect(boardsIn(note)[0]?.height).toBeNull();
    expect(boardsIn('```board height=18\nTo do: a\n```')[0]).toMatchObject({ height: 18, columns: [{ name: 'To do', cards: ['a'] }] });
    expect(boardsIn('~~~ board height=12.5em\nTo do:\n~~~')[0]?.height).toBe(12.5);
    // Junk after the word is a setting nobody reads, and the board is still a board.
    expect(boardsIn('```board wide\nTo do:\n```')[0]).toMatchObject({ height: null, columns: [{ name: 'To do', cards: [] }] });
    // A word that only starts with "board" is not a board.
    expect(boardsIn('```boards\nTo do:\n```')).toEqual([]);
  });

  it('is kept between a card and a half and a long screen, to the half em', () => {
    expect(boardsIn('```board height=1\nTo do:\n```')[0]?.height).toBe(BOARD_HEIGHT.min);
    expect(boardsIn('```board height=900\nTo do:\n```')[0]?.height).toBe(BOARD_HEIGHT.max);
    expect(clampHeight(17.3)).toBe(17.5);
  });

  it('is written into the fence and taken out again, the rest of the line as it was', () => {
    expect(withBoardHeight('```board', 18)).toBe('```board height=18');
    expect(withBoardHeight('```board height=18', 24.2)).toBe('```board height=24');
    expect(withBoardHeight('  ~~~~ Board wide height=18 ', 9)).toBe('  ~~~~ Board height=9 wide');
    expect(withBoardHeight('```board height=18 wide', null)).toBe('```board wide');
    expect(withBoardHeight('```board height=18', null)).toBe('```board');
    expect(withBoardHeight('```js', 18)).toBe('```js');
    // What it writes, it reads back.
    expect(boardsIn(`${withBoardHeight('```board', 21.5)}\nTo do:\n\`\`\``)[0]?.height).toBe(21.5);
  });
});
