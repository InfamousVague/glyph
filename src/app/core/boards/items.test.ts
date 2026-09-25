import { describe, expect, it } from 'vitest';
import {
  anchorFor,
  boardFrom,
  boardsIn,
  cardsOf,
  cardText,
  isItemLine,
  itemAt,
  itemOnLine,
  itemsIn,
  itemWords,
  readBoard,
  refFor,
  refsIn,
  setItemDone,
  withAnchor,
} from '../boards.ts';
import { wordsEnd } from '../itemSyntax.ts';
import { LAUNCH_WEEK as note } from '../../../test/boards.ts';

/**
 * The items a board points at: anchors, words and boxes, choices and counters, and an anchor pointed at from prose.
 *
 * core/boards/items.ts, reached as every caller reaches it: through the room’s door, core/boards.ts.
 */

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

  it('finds an item whose Notion mark was written after its anchor, and keeps the mark with its words', () => {
    // Matt: "the last two items show up weird on the board as only their label no title".
    const doc = [
      '```board',
      'To do: add-task-input, make-board-height',
      '```',
      '',
      '- [ ] Add task input and button dont match up ^add-task-input [notion](https://app.notion.com/p/Add-task-input-3dd5)',
      '- [ ] make board height configurable with glacierUI split view ^make-board-height [notion](https://app.notion.com/p/make-board-height-3dd5)',
      '- [ ] ',
    ].join('\n');
    const cards = cardsOf(boardsIn(doc)[0]!.columns, itemsIn(doc));
    expect(cards.map((card) => card.item?.text)).toEqual([
      'Add task input and button dont match up [notion](https://app.notion.com/p/Add-task-input-3dd5)',
      'make board height configurable with glacierUI split view [notion](https://app.notion.com/p/make-board-height-3dd5)',
    ]);
    // Ticking it leaves the line as it was written, anchor and mark both where they were.
    expect(setItemDone(doc.split('\n')[4]!, true)).toBe(
      '- [x] Add task input and button dont match up ^add-task-input [notion](https://app.notion.com/p/Add-task-input-3dd5)',
    );
    // Only a mark may follow the anchor: anything else, and the caret is words.
    expect(itemOnLine('- [ ] Ship ^ship-it and then more')).toBeNull();
    expect(itemOnLine('- [ ] Ship ^ship-it [a link](not-a-url)')).toBeNull();
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

describe('what a card says', () => {
  it('says a link by its words and drops the marks around them', () => {
    expect(cardText('Fix the [login button](https://example.com/a/very/long/url) *today*')).toBe('Fix the login button today');
    expect(cardText('Read <https://example.com/x>')).toBe('Read https://example.com/x');
    expect(cardText('  lots   of   room  ')).toBe('lots of room');
  });
});

describe('choices and counters on a board', () => {
  it('reads a choice as an item with no box, its words after the choice\u2019s own', () => {
    expect(itemOnLine('- ( ) Pick the red one ^red')).toEqual({ id: 'red', text: 'Pick the red one', done: null, line: 0 });
    expect(itemOnLine('- (x) Pick the blue one ^blue')).toMatchObject({ text: 'Pick the blue one', done: null });
    // Only after a bullet, and only the exact box: a numbered line and a spaced box are words.
    expect(itemOnLine('1. ( ) Not a choice ^one')?.text).toBe('( ) Not a choice');
    expect(itemOnLine('- ( x ) Not a choice ^two')?.text).toBe('( x ) Not a choice');
    // A picked choice is not a done item: dragging it into Done does not touch its line.
    expect(setItemDone('- (x) Pick the blue one ^blue', false)).toBe('- (x) Pick the blue one ^blue');
  });

  it('makes a list of choices into cards named after their words', () => {
    const made = boardFrom('- ( ) Pick red\n- (x) Pick blue')!;
    expect(made.done).toBe(0);
    expect(made.doc.split('\n').slice(6)).toEqual(['- ( ) Pick red ^pick-red', '- (x) Pick blue ^pick-blue']);
  });

  it('finds an item whose counter was typed after its anchor, and keeps the counter with its words', () => {
    // Typed at the end of the line, the counter lands after the anchor.
    expect(itemOnLine('- [ ] Pack socks ^pack-socks [3/8]')).toMatchObject({ id: 'pack-socks', text: 'Pack socks [3/8]' });
    expect(itemOnLine('- [ ] Pack socks ^pack-socks [3/8] [notion](https://app.notion.com/p/x)')).toMatchObject({
      id: 'pack-socks',
      text: 'Pack socks [3/8] [notion](https://app.notion.com/p/x)',
    });
    expect(itemOnLine('- [ ] Pack socks [3/8] ^pack-socks')).toMatchObject({ id: 'pack-socks', text: 'Pack socks [3/8]' });
    // A link after the anchor is still not allowed: only marks and counters.
    expect(itemOnLine('- [ ] Pack ^pack [3/8](https://x.y)')).toBeNull();
  });

  it('leaves a counter out of an anchor it makes', () => {
    expect(anchorFor('Pack socks [3/8]', [])).toBe('pack-socks');
    expect(withAnchor('- [ ] Pack socks [3/8]', 'pack-socks')).toBe('- [ ] Pack socks [3/8] ^pack-socks');
  });
});

describe('where an item\u2019s words end', () => {
  it('is before its mark, counters and anchor, so a caret there types on the words', () => {
    const url = 'https://app.notion.com/p/x';
    const line = `- [ ] Pack socks [3/8] [notion](${url}) ^pack-socks`;
    expect(line.slice(0, wordsEnd(line))).toBe('- [ ] Pack socks');
    expect(wordsEnd('- [ ] Ship it ^ship-it  ')).toBe('- [ ] Ship it'.length);
    expect(wordsEnd(`- [ ] Old order ^old [notion](${url})`)).toBe('- [ ] Old order'.length);
    // A superscript at the end is words, and so is a line that is not an item.
    expect(wordsEnd('- E = mc^2^')).toBe('- E = mc^2^'.length);
    expect(wordsEnd('Just words ^not-an-item')).toBe('Just words ^not-an-item'.length);
    // An item with no words yet: the caret goes after its box.
    expect(wordsEnd('- [ ] ^item')).toBe('- [ ] '.length);
  });

  it('is before the bookmark too, which no card, anchor or lane match says', () => {
    const url = 'https://app.notion.com/p/x';
    const line = `- [ ] Ship it §§ [notion](${url}) ^ship-it`;
    expect(line.slice(0, wordsEnd(line))).toBe('- [ ] Ship it');
    expect(wordsEnd('- [ ] §§')).toBe('- [ ] '.length);
    expect(itemOnLine(line)?.text).toBe(`Ship it [notion](${url})`);
    expect(itemWords('- [ ] Ship it §§ ^ship-it')).toBe('Ship it');
    expect(cardText('Ship it §§')).toBe('Ship it');
    expect(anchorFor('Ship the page §§', [])).toBe('ship-page');
    // Two section signs in the middle of words are words.
    expect(itemWords('- See §§12 ^see')).toBe('See §§12');
  });
});

describe('a card’s box is the box the note draws (core/itemSyntax.ts)', () => {
  it('has no box when the brackets are glued to the words, since the editor draws none there to tick', () => {
    expect(itemOnLine('- [ ]Ship it ^ship')).toEqual({ id: 'ship', text: '[ ]Ship it', done: null, line: 0 });
    expect(setItemDone('- [ ]Ship it ^ship', true)).toBe('- [ ]Ship it ^ship');
  });

  it('reads a link whose words are "x" as the link it is, not as a ticked box', () => {
    expect(itemOnLine('- [x](https://example.com/x) ^x-link')).toEqual({ id: 'x-link', text: '[x](https://example.com/x)', done: null, line: 0 });
  });

  it('is no item at all for an empty choice, as an empty to-do is none', () => {
    expect(isItemLine('- ( )')).toBe(false);
    expect(isItemLine('- [ ]')).toBe(false);
    expect(isItemLine('- ( ) Tent')).toBe(true);
  });

  it('puts the caret after an empty choice’s box, as it does after a to-do’s', () => {
    expect(wordsEnd('- ( ) ^pick')).toBe('- ( ) '.length);
  });
});
