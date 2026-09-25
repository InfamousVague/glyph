import { WidgetType, type EditorView } from '@codemirror/view';
import { cardText, type Card } from '../../core/boards.ts';
import { markOf, unmarked } from '../../core/itemLinks.ts';
import { openCardMenu } from './cardMenu.ts';
import { landCard, stepCard, takeOffCard, tickCard } from './cardEdits.ts';
import { openComposer } from './composer.ts';
import { heightSplit, sized } from './divider.ts';
import { holdToDrag } from './drag.ts';
import type { DrawnBoard } from './drawn.ts';
import { estimatedHeight, laneFoot, unwatch, watch } from './height.ts';
import { emptyLook, icon } from './icons.ts';
import { goToLine, hushed } from './navigate.ts';
import { press } from './press.ts';

/**
 * A board drawn in place of its fence: a row of columns, each a heading, its cards and an empty place, with the line
 * under it that sets its height. Every control on it is pressed through `press`, and what a control does to the note
 * is editor/boards/cardEdits.ts; this draws, and redraws in place when the same board changes.
 */

export class BoardWidget extends WidgetType {
  constructor(
    readonly board: DrawnBoard,
    readonly face: string,
  ) {
    super();
  }

  eq(other: BoardWidget): boolean {
    return other.face === this.face;
  }

  /** How tall the board is before it is drawn (editor/boards/height.ts). */
  get estimatedHeight(): number {
    return estimatedHeight(this.board, this.face);
  }

  toDOM(view: EditorView): HTMLElement {
    const wrap = document.createElement('div');
    wrap.className = 'cm-boardWrap';
    const board = document.createElement('div');
    board.className = 'cm-board';
    board.setAttribute('role', 'group');
    board.setAttribute('aria-label', 'Board');
    for (const index of this.board.columns.keys()) {
      const pane = document.createElement('section');
      pane.className = 'cm-boardColumn';
      pane.dataset.column = String(index);
      this.fill(view, pane, index);
      board.append(pane);
    }
    const split = heightSplit(view, wrap);
    wrap.append(board, split);
    sized(board, split, this.board.height);
    watch(view, wrap, board, this.face);
    return wrap;
  }

  destroy(dom: HTMLElement): void {
    unwatch(dom);
  }

  /**
   * The same board changed - a card added, moved or ticked - is redrawn in place, column by column, rather than
   * built again. What that keeps is the field a card is being typed into (`openComposer`): built again, it would
   * lose its focus and the phone its keyboard after every card. A board whose columns changed is built again.
   */
  updateDOM(dom: HTMLElement, view: EditorView): boolean {
    const board = dom.querySelector<HTMLElement>(':scope > .cm-board');
    const split = dom.querySelector<HTMLElement>(':scope > .cm-boardSplit');
    if (!board || !split) return false;
    const panes = [...board.children].filter((child): child is HTMLElement => child instanceof HTMLElement && child.classList.contains('cm-boardColumn'));
    if (panes.length !== this.board.columns.length) return false;
    panes.forEach((pane, index) => this.fill(view, pane, index));
    sized(board, split, this.board.height);
    watch(view, dom, board, this.face);
    return true;
  }

  /** A column's heading and cards, put in its pane or put in place of the ones it had; a field being typed in stays. */
  private fill(view: EditorView, pane: HTMLElement, index: number): void {
    const column = this.board.columns[index]!;
    const held = this.board.cards.filter((card) => card.column === index);
    pane.setAttribute('aria-label', `${column.name}, ${held.length} ${held.length === 1 ? 'card' : 'cards'}`);

    const head = document.createElement('p');
    head.className = 'cm-boardName';
    const name = document.createElement('span');
    name.className = 'cm-boardNameWords';
    name.textContent = column.name;
    const count = document.createElement('span');
    count.className = 'cm-boardCount';
    count.textContent = String(held.length);
    // A card is added where the eye already is, at the top of the column it belongs in.
    const add = document.createElement('button');
    add.type = 'button';
    add.className = 'cm-boardAdd';
    add.append(icon('plus', '1.05em'));
    add.setAttribute('aria-label', `Add a card to ${column.name}`);
    press(add, () => openComposer(view, pane, column.name));
    head.append(name, count, add);

    const stack = document.createElement('div');
    stack.className = 'cm-boardStack';
    stack.dataset.column = String(index);
    stack.addEventListener('scroll', () => laneFoot(stack), { passive: true });
    for (const card of held) stack.append(this.drawCard(view, card, index));
    // An empty column is a place, not a blank: at rest it shows what it would hold and says it holds nothing, and
    // while a card is held it is a target, in this column and every other.
    const empty = document.createElement('div');
    empty.className = 'cm-boardEmpty';
    if (!held.length) empty.dataset.none = '';
    const look = emptyLook(column.name);
    const rest = document.createElement('span');
    rest.className = 'cm-boardEmptyRest';
    const picture = icon(look.icon, '1.5em');
    picture.classList.add('cm-boardEmptyIcon');
    const words = document.createElement('span');
    words.textContent = look.words;
    rest.append(picture, words);
    const drop = document.createElement('span');
    drop.className = 'cm-boardEmptyDrop';
    drop.textContent = 'Drop a card here';
    empty.append(rest, drop);
    stack.append(empty);

    const hadHead = pane.querySelector(':scope > .cm-boardName');
    if (hadHead) hadHead.replaceWith(head);
    else pane.prepend(head);
    const hadStack = pane.querySelector(':scope > .cm-boardStack');
    if (hadStack) hadStack.replaceWith(stack);
    else pane.append(stack);
  }

  private drawCard(view: EditorView, card: Card, column: number): HTMLElement {
    const box = document.createElement('div');
    box.className = 'cm-boardCard';
    box.dataset.card = card.id;
    if (!card.item) box.dataset.gone = '';
    else if (card.item.done) box.dataset.done = '';

    // What the item is linked to rides at the end of its line as `[notion](…)`, and read as words the card said
    // "notion" after every single item (Matt: "every item has a notion link each of the items has the literal
    // notion text"). The link is taken off the words and shown as its plugin's mark instead.
    const mark = card.item ? markOf(card.item.text) : null;
    // A card the + has just written has no words yet: it says so until they are typed, rather than sitting blank.
    const written = card.item ? cardText(mark ? unmarked(card.item.text) : card.item.text) : '';
    const said = card.item ? written || 'New card' : `^${card.id}`;
    if (card.item && !written) box.dataset.empty = '';

    // A to-do's box is the card's. An item with no box - a bullet, a step - is a card with nothing to tick.
    if (card.item?.done !== null || !card.item) {
      const tick = document.createElement('button');
      tick.type = 'button';
      tick.className = 'cm-boardTick';
      tick.append(icon('check', '0.85em'));
      tick.setAttribute('aria-label', card.item?.done ? `Untick ${said}` : `Tick ${said}`);
      tick.disabled = !card.item;
      press(tick, () => tickCard(view, this.board, card));
      box.append(tick);
    } else {
      const dot = document.createElement('span');
      dot.className = 'cm-boardDot';
      dot.setAttribute('aria-hidden', 'true');
      box.append(dot);
    }

    const words = document.createElement('button');
    words.type = 'button';
    words.className = 'cm-boardWords';
    // What the card says: the words without their markdown, and a few lines of them at most (core/boards.ts).
    words.textContent = said;
    words.title = said;
    words.setAttribute('aria-label', card.item ? `Go to ${said} in the note` : `${card.id}: this item is not in the note`);
    press(words, () => this.goTo(view, card));

    const moves = document.createElement('span');
    moves.className = 'cm-boardMoves';
    for (const [by, label, glyph] of [
      [-1, 'Move left', 'left'],
      [1, 'Move right', 'right'],
    ] as const) {
      const move = document.createElement('button');
      move.type = 'button';
      move.className = 'cm-boardMove';
      move.append(icon(glyph, '1em'));
      move.setAttribute('aria-label', `${label}: ${said}`);
      move.disabled = (by < 0 && column === 0) || (by > 0 && column === this.board.columns.length - 1);
      press(move, () => stepCard(view, this.board, card, by));
      moves.append(move);
    }

    // The card's own menu: lanes to move to, the line in the note, what a plugin offers, and off the board. A press
    // and hold is already the drag, so the menu needs a button of its own.
    const menu = document.createElement('button');
    menu.type = 'button';
    menu.className = 'cm-boardMore';
    menu.append(icon('more', '1.1em'));
    menu.setAttribute('aria-label', `More for ${said}`);
    menu.setAttribute('aria-haspopup', 'menu');
    press(menu, () =>
      openCardMenu(view, card, box, {
        columns: this.board.columns,
        land: (column) => landCard(view, this.board, card, column, Number.MAX_SAFE_INTEGER),
        tick: () => tickCard(view, this.board, card),
        takeOff: () => takeOffCard(view, this.board, card),
      }),
    );
    moves.prepend(menu);

    const badge = mark ? document.createElement('span') : null;
    if (badge && mark) {
      badge.className = 'cm-boardLinked';
      badge.title = `Linked to ${mark.name}`;
      badge.setAttribute('aria-label', `Linked to ${mark.name}`);
      badge.append(icon(mark.name === 'notion' ? 'notion' : 'link', '0.95em'));
    }

    box.append(words, ...(badge ? [badge] : []), moves);
    holdToDrag(box, card, (column, index) => landCard(view, this.board, card, column, index));
    return box;
  }

  /** The words are a way into the note: the caret lands on the item, and the note scrolls to it. */
  private goTo(view: EditorView, card: Card): void {
    if (!card.item || hushed()) return;
    goToLine(view, card.item.line);
  }

  /** The field a card is typed into is the page's own input: the editor leaves its keys and taps alone. */
  ignoreEvent(event: Event): boolean {
    return event.target instanceof Element && event.target.closest('.cm-boardCompose, .cm-boardSplit, .cm-boardMenu') !== null;
  }
}
