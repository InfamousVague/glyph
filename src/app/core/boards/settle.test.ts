import { describe, expect, it } from 'vitest';
import {
  boardsIn,
  itemsIn,
  putCard,
  settleBoards,
  settleColumns,
  settleTicks,
  writeBoard,
} from '../boards.ts';

/**
 * A tick carried to the fences: ticked cards into Done, cleared ones out, and an unanchored item joining its list’s
 * board.
 *
 * core/boards/settle.ts, reached as every caller reaches it: through the room’s door, core/boards.ts.
 */

describe('ticking an item that is not a card', () => {
  const note = [
    '```board',
    'To do: milk, eggs',
    'Done:',
    '```',
    '',
    '- [ ] Milk ^milk',
    '- [ ] Eggs ^eggs',
    '- [ ] Bread',
    '',
    '## Later',
    '',
    '- [ ] Something else entirely',
    '',
  ].join('\n');

  it('puts it on its list\u2019s board, in Done, and names its line', () => {
    // From Matt's note: three ticked items had no anchor, so ticking them moved nothing while 57 others worked.
    const settled = settleTicks(note, new Map([[8, true]]));
    expect(settled.lines).toEqual([{ number: 8, anchor: 'bread' }]);
    expect(settled.fences[0]?.body).toBe('To do: milk, eggs\nDone: bread');
  });

  it('leaves a list that is not on a board alone', () => {
    // The item under a heading of its own belongs to no board: a board never has to hold every item in the note.
    expect(settleTicks(note, new Map([[12, true]]))).toEqual({ fences: [], lines: [] });
  });

  it('still just moves an item that is already a card', () => {
    const settled = settleTicks(note, new Map([[6, true]]));
    expect(settled.lines).toEqual([]);
    expect(settled.fences[0]?.body).toBe('To do: eggs\nDone: milk');
  });

  it('takes a batch, as a set of tasks arriving from Notion does', () => {
    const settled = settleTicks(note, new Map([[6, true], [8, true]]));
    expect(settled.lines).toEqual([{ number: 8, anchor: 'bread' }]);
    expect(settled.fences[0]?.body).toBe('To do: eggs\nDone: milk, bread');
  });

  it('does nothing for a box being cleared, or a line that is not an item', () => {
    expect(settleTicks(note, new Map([[8, false]]))).toEqual({ fences: [], lines: [] });
    expect(settleTicks(note, new Map([[10, true]]))).toEqual({ fences: [], lines: [] });
  });
});

describe('the ticks and the lanes', () => {
  const note = ['```board', 'To do: milk, eggs, bread', 'Doing:', 'Done:', '```', '', '- [ ] Milk ^milk', '- [x] Eggs ^eggs', '- [x] Bread ^bread', ''].join('\n');

  it('writes the ticked cards where the board draws them: in Done', () => {
    expect(settleBoards(note)).toEqual([{ from: 1, to: 5, body: 'To do: milk\nDoing:\nDone: eggs, bread' }]);
  });

  it('moves a box being ticked, and takes a box being cleared out of Done', () => {
    expect(settleBoards(note, new Map([[7, true]]))[0]?.body).toBe('To do:\nDoing:\nDone: milk, eggs, bread');
    const settled = '```board\nTo do: milk\nDoing:\nDone: eggs, bread\n```\n\n- [ ] Milk ^milk\n- [x] Eggs ^eggs\n- [x] Bread ^bread\n';
    expect(settleBoards(settled, new Map([[8, false]]))[0]?.body).toBe('To do: milk, eggs\nDoing:\nDone: bread');
    // A batch, the way a set of tasks arrives from Notion at once.
    expect(
      settleBoards(
        settled,
        new Map([
          [8, false],
          [9, false],
        ]),
      )[0]?.body,
    ).toBe('To do: milk, eggs, bread\nDoing:\nDone:');
  });

  it('says nothing when there is nothing to move, and leaves a board with no Done lane alone', () => {
    const settled = '```board\nTo do: milk\nDone: eggs\n```\n\n- [ ] Milk ^milk\n- [x] Eggs ^eggs\n';
    expect(settleBoards(settled)).toEqual([]);
    expect(settleBoards('```board\nTo do: milk\nNext: eggs\n```\n\n- [ ] Milk ^milk\n- [x] Eggs ^eggs\n')).toEqual([]);
  });

  it('leaves the card a person has just moved where they put it', () => {
    const board = boardsIn(note)[0]!;
    const items = itemsIn(note);
    // Bread dragged into Doing: it stays there, and the other ticked card still settles into Done.
    const moved = putCard(board.columns, 'bread', 1);
    expect(writeBoard(settleColumns(moved, items, 'bread'))).toBe('To do: milk\nDoing: bread\nDone: eggs');
    expect(writeBoard(settleColumns(moved, items))).toBe('To do: milk\nDoing:\nDone: eggs, bread');
  });
});
