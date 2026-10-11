import { describe, expect, it } from 'vitest';
import {
  boardsIn,
  cardsOf,
  columnFor,
  columnOf,
  doneColumn,
  itemsIn,
  moveCard,
  nearAnchor,
  putCard,
  putCardAt,
  readBoard,
  withoutCard,
  writeBoard,
} from '../boards.ts';

/**
 * Columns as data: a card moved, dropped and taken off, and a card whose anchor slipped still finding its item.
 *
 * core/boards/columns.ts, reached as every caller reaches it: through the room’s door, core/boards.ts.
 */

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

describe('a card whose anchor has slipped', () => {
  // Matt's board named `blur-bottom-swimlanes`, and the line had become `^blur-bottom-swimlaness`.
  const url = 'https://app.notion.com/p/the-blur-3de5';
  const doc = [
    '```board height=19',
    'To do: we-should-show, blur-bottom-swimlanes',
    'Done: switching',
    '```',
    '',
    '- [x] Switching workspaces scrolls smoothly ^switching',
    '- [ ] we should show the bookmark as a physical symbol ^we-should-show',
    `- [ ] the blur at the bottom of the swimlanes should be the wisp effect [notion](${url}) ^blur-bottom-swimlaness`,
  ].join('\n');

  it('shows the item it meant, when exactly one item no board names is a slip of it', () => {
    const board = boardsIn(doc)[0]!;
    const cards = cardsOf(board.columns, itemsIn(doc));
    expect(cards.map((card) => [card.id, card.item?.id ?? null])).toEqual([
      ['we-should-show', 'we-should-show'],
      ['blur-bottom-swimlanes', 'blur-bottom-swimlaness'],
      ['switching', 'switching'],
    ]);
    expect(cards[1]?.item?.text).toBe(`the blur at the bottom of the swimlanes should be the wisp effect [notion](${url})`);
  });

  it('takes nothing a board already names, nothing when two items could be it, and nothing for a short anchor', () => {
    const named = doc.replace('Done: switching', 'Done: switching, blur-bottom-swimlaness');
    const board = boardsIn(named)[0]!;
    expect(cardsOf(board.columns, itemsIn(named)).find((card) => card.id === 'blur-bottom-swimlanes')?.item).toBeNull();

    const twice = `${doc}\n- [ ] another ^blur-bottom-swimlanez`;
    expect(cardsOf(boardsIn(twice)[0]!.columns, itemsIn(twice))[1]?.item).toBeNull();

    const short = '```board\nTo do: abc\n```\n\n- [ ] Thing ^abcd';
    expect(cardsOf(boardsIn(short)[0]!.columns, itemsIn(short))[0]?.item).toBeNull();
  });

  it('counts one letter added, dropped or changed, or up to two more at the end, as a slip', () => {
    expect(nearAnchor('blur-bottom-swimlanes', 'blur-bottom-swimlaness')).toBe(true);
    expect(nearAnchor('ship-page', 'ship-pages-')).toBe(true);
    expect(nearAnchor('ship-page', 'shp-page')).toBe(true);
    expect(nearAnchor('ship-page', 'ship-paje')).toBe(true);
    expect(nearAnchor('ship-page', 'ship-page')).toBe(false);
    expect(nearAnchor('ship-page', 'ship-pages-now')).toBe(false);
    expect(nearAnchor('ship-page', 'shop-paje')).toBe(false);
  });
});

describe('a card taken off the board', () => {
  it('goes from every lane and leaves the item where it is', () => {
    const doc = '```board\nTo do: milk, eggs\nDone:\n```\n\n- [ ] Milk ^milk\n- [ ] Eggs ^eggs\n';
    const columns = boardsIn(doc)[0]!.columns;
    expect(writeBoard(withoutCard(columns, 'milk'))).toBe('To do: eggs\nDone:');
    // An id the board does not have changes nothing.
    expect(writeBoard(withoutCard(columns, 'bread'))).toBe(writeBoard(columns));
    expect(itemsIn(doc).map((item) => item.id)).toEqual(['milk', 'eggs']);
  });
});
