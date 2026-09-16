import { EditorSelection, RangeSetBuilder, StateEffect, StateField, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { fireNativeHaptic } from '../core/haptics.ts';
import { markOf, unmarked } from '../core/itemLinks.ts';
import {
  boardsIn,
  cardText,
  cardsOf,
  columnFor,
  doneColumn,
  itemAt,
  itemsIn,
  moveCard,
  newCard,
  putCard,
  putCardAt,
  refsIn,
  setItemDone,
  writeBoard,
  type BoardColumn,
  type Card,
  type Item,
} from '../core/boards.ts';

/**
 * Boards, shown as boards (docs/BOARDS.md, core/boards.ts).
 *
 * A ```board fence is columns; the items it names are anywhere in the note, each with its anchor. The fence is drawn
 * as a board of cards, the way a table is drawn as a table (editor/tables.ts): the markdown is what is kept and what
 * is edited, and the caret in the fence steps the drawing aside so the lines can be typed.
 *
 * A card IS its item, which is what Matt asked for ("linking the tasks in the board to a task on the page"):
 *
 * - Its tick box is the item's box. Ticking it ticks the line in the note, and moves the card to Done when the board
 *   has such a column. An item with no box - a bullet, a numbered step - is drawn as a card with no box.
 * - Its words are the item's words. Tapping them puts the caret on that line, so the board is a way around the note.
 * - Press and hold picks the card up and it is dragged to where it goes, in its own column or another (Matt: "add a
 *   way to tap and drag to re organize items in lanes"). The chevrons do the same a tap at a time, for a hand that
 *   would rather not drag and for anything driving the app by keyboard.
 * - A card whose item is gone is drawn with its anchor and nothing else, so it can be seen and taken out.
 *
 * The rest is the phone it is used on (Matt: "make the UI / UX of these boards friendlier on mobile"): columns that
 * snap as they scroll, a heading that stays while the cards go by, an empty column that says it will take a card, a
 * + that writes a new item into the note, and targets big enough for a thumb.
 */

const setFocus = StateEffect.define<boolean>();

const focusField = StateField.define<boolean>({
  create: () => false,
  update(focused, tr) {
    for (const effect of tr.effects) if (effect.is(setFocus)) return effect.value;
    return focused;
  },
});

/** Where a board is in the document, and what it holds. */
interface Drawn {
  /** The whole fence, from the first backtick to the last. */
  from: number;
  to: number;
  /** The line the opening fence is on, which is how core/boards.ts is asked about this board. */
  open: number;
  columns: BoardColumn[];
  items: Item[];
  cards: Card[];
}

function boards(state: EditorState): Drawn[] {
  const doc = state.doc.toString();
  const items = itemsIn(doc);
  return boardsIn(doc)
    .filter((board) => board.to > board.from)
    .map((board) => {
      const columns = board.columns;
      // A ticked item sits in Done wherever the fence has it, so the board never disagrees with the note.
      const cards = cardsOf(columns, items).map((card) => (card.item ? { ...card, column: Math.max(0, columnFor(columns, card.item)) } : card));
      return { from: state.doc.line(board.from).from, to: state.doc.line(board.to).to, open: board.from, columns, items, cards };
    });
}

/**
 * The board's icons, drawn in the same strokes as the rest of the app's (lucide's paths, 24-unit box, round caps), so
 * the controls are icons rather than the characters `‹ › +` set in whatever face the phone falls back to.
 */
const ICONS = {
  plus: ['M5 12h14', 'M12 5v14'],
  // A page with an N on it, as the Notion plugin draws its own mark (plugins/notion/marks.tsx).
  notion: ['M5 4h10l4 4v12H5z', 'M9 16V9l6 7V9'],
  // Any other plugin's link: two rings of a chain.
  link: ['M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71', 'M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71'],
  left: ['m15 18-6-6 6-6'],
  right: ['m9 18 6-6-6-6'],
  check: ['M20 6 9 17l-5-5'],
} as const;

function icon(name: keyof typeof ICONS, size = '1em'): SVGSVGElement {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('fill', 'none');
  svg.setAttribute('stroke', 'currentColor');
  svg.setAttribute('stroke-width', '2.4');
  svg.setAttribute('stroke-linecap', 'round');
  svg.setAttribute('stroke-linejoin', 'round');
  svg.style.inlineSize = size;
  svg.style.blockSize = size;
  for (const d of ICONS[name]) {
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('d', d);
    svg.append(path);
  }
  return svg;
}

/** How long a finger rests on a card before it is picked up, and how far it may stray first. */
const HOLD = 220;
const SLOP = 10;
/** How near the edge of the board a held card scrolls it along, and how fast. */
const EDGE = 44;
const EDGE_STEP = 14;

class BoardWidget extends WidgetType {
  constructor(
    readonly board: Drawn,
    readonly face: string,
  ) {
    super();
  }

  eq(other: BoardWidget): boolean {
    return other.face === this.face;
  }

  toDOM(view: EditorView): HTMLElement {
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
    return board;
  }

  /**
   * The same board changed - a card added, moved or ticked - is redrawn in place, column by column, rather than
   * built again. What that keeps is the field a card is being typed into (`openComposer`): built again, it would
   * lose its focus and the phone its keyboard after every card. A board whose columns changed is built again.
   */
  updateDOM(dom: HTMLElement, view: EditorView): boolean {
    const panes = [...dom.children].filter((child): child is HTMLElement => child instanceof HTMLElement && child.classList.contains('cm-boardColumn'));
    if (panes.length !== this.board.columns.length) return false;
    panes.forEach((pane, index) => this.fill(view, pane, index));
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
    for (const card of held) stack.append(this.drawCard(view, card, index));
    // An empty column is a place, not a blank: it says what it is for, and it is a target while a card is held.
    const empty = document.createElement('p');
    empty.className = 'cm-boardEmpty';
    empty.textContent = 'Drop a card here';
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
      press(tick, () => this.tick(view, card));
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
      press(move, () => this.move(view, card, by));
      moves.append(move);
    }

    const badge = mark ? document.createElement('span') : null;
    if (badge && mark) {
      badge.className = 'cm-boardLinked';
      badge.title = `Linked to ${mark.name}`;
      badge.setAttribute('aria-label', `Linked to ${mark.name}`);
      badge.append(icon(mark.name === 'notion' ? 'notion' : 'link', '0.95em'));
    }

    box.append(words, ...(badge ? [badge] : []), moves);
    this.hold(view, box, card);
    return box;
  }

  /** The card's tick box is the item's: the line is ticked, and a Done column takes the card. */
  private tick(view: EditorView, card: Card): void {
    const item = card.item;
    if (!item || item.done === null) return;
    const line = view.state.doc.line(item.line);
    const done = !item.done;
    const changes = [{ from: line.from, to: line.to, insert: setItemDone(line.text, done) }];
    const put = done ? doneColumn(this.board.columns) : 0;
    const columns = put >= 0 ? putCard(this.board.columns, card.id, put) : null;
    hushGoTo();
    view.dispatch({ changes: columns ? [...changes, this.fence(view, columns)] : changes, userEvent: 'input.board' });
    fireNativeHaptic('selection');
    if (columns) reveal(view, card.id);
  }

  private move(view: EditorView, card: Card, by: number): void {
    view.dispatch({ changes: this.fence(view, moveCard(this.board.columns, card.id, by)), userEvent: 'input.board' });
    fireNativeHaptic('selection');
  }

  /** The fence rewritten: the columns as a person would have typed them, between the two ``` lines. */
  private fence(view: EditorView, columns: readonly BoardColumn[]) {
    const open = view.state.doc.lineAt(this.board.from);
    const close = view.state.doc.lineAt(this.board.to);
    return { from: open.to + 1, to: close.from - 1, insert: writeBoard(columns) };
  }

  /** The words are a way into the note: the caret lands on the item, and the note scrolls to it. */
  private goTo(view: EditorView, card: Card): void {
    if (!card.item || Date.now() < quietUntil) return;
    goToLine(view, card.item.line);
  }

  /**
   * Press and hold, then drag: the card is lifted under the finger, a gap opens where it would land, and letting go
   * writes it there. Before the hold is up the finger still scrolls the board, which is why nothing is taken over
   * until the card is actually lifted.
   */
  private hold(view: EditorView, card: HTMLElement, held: Card): void {
    card.addEventListener('pointerdown', (event: PointerEvent) => {
      if (event.button !== 0 && event.pointerType === 'mouse') return;
      // A press on one of the card's controls is that control's: a finger resting on the tick box a little past the
      // hold used to lift the card instead of ticking it, so a slow tap did nothing and the next landed on the words.
      if ((event.target as Element | null)?.closest?.('.cm-boardTick, .cm-boardMove, .cm-boardAdd')) return;
      const board = card.closest('.cm-board') as HTMLElement | null;
      if (!board) return;
      // The card answers its own press and hold: the note's long-press menu is for the words, not for a card.
      event.stopPropagation();
      const startX = event.clientX;
      const startY = event.clientY;
      let lift: Lift | null = null;
      let timer = window.setTimeout(() => {
        timer = 0;
        lift = pickUp(board, card, held, startX, startY);
      }, HOLD);

      const move = (moving: PointerEvent) => {
        if (moving.pointerId !== event.pointerId) return;
        if (!lift) {
          // Moved before the hold was up: the finger is scrolling the board, so the card is left alone.
          if (Math.hypot(moving.clientX - startX, moving.clientY - startY) > SLOP && timer) {
            window.clearTimeout(timer);
            timer = 0;
            done();
          }
          return;
        }
        moving.preventDefault();
        dragTo(lift, moving.clientX, moving.clientY);
      };
      const up = (lifting: PointerEvent) => {
        if (lifting.pointerId !== event.pointerId) return;
        const landed = lift;
        const column = landed?.column ?? 0;
        const index = Math.max(0, landed?.index ?? 0);
        done();
        if (landed) this.land(view, held, column, index);
      };
      const cancel = (cancelling: PointerEvent) => {
        if (cancelling.pointerId === event.pointerId) done();
      };
      // Held, a finger's movement is the drag and not a scroll. `touch-action` is read when the finger goes down, so
      // setting it at pick-up is too late for this touch: the browser would take the next move as a pan and cancel
      // the pointer. A touchmove that is not passive can still refuse the pan, as long as the card is held.
      const still = (touching: TouchEvent) => {
        if (lift && touching.cancelable) touching.preventDefault();
      };
      const done = () => {
        if (timer) window.clearTimeout(timer);
        timer = 0;
        if (lift) putDown(lift);
        lift = null;
        window.removeEventListener('pointermove', move);
        window.removeEventListener('pointerup', up);
        window.removeEventListener('pointercancel', cancel);
        window.removeEventListener('touchmove', still);
      };

      // The moves are heard on the window, not the card. The drag moves the card to where it would land, and a node
      // moved in the page loses the pointer it had captured: from then on the moves, the lift and the cancel went to
      // whatever was under the finger, the card never heard them, and it was left held with its copy on the screen.
      // Nor is the pointer captured at all: captured, a mouse's click went to the card instead of the tick box in it.
      window.addEventListener('pointermove', move);
      window.addEventListener('pointerup', up);
      window.addEventListener('pointercancel', cancel);
      window.addEventListener('touchmove', still, { passive: false });
    });
  }

  /** Where the card was let go: the fence rewritten, and the tick box brought with it where a Done column is crossed. */
  private land(view: EditorView, card: Card, column: number, index: number): void {
    const was = card.column;
    if (was === column && index === this.board.cards.filter((other) => other.column === column).findIndex((other) => other.id === card.id)) return;
    const changes = [this.fence(view, putCardAt(this.board.columns, card.id, column, index))];
    // Dragged into Done, the item is done; dragged out of it, it is not. The note says so, not only the board.
    const done = doneColumn(this.board.columns);
    const item = card.item;
    if (item && item.done !== null && done >= 0 && (was === done) !== (column === done)) {
      const line = view.state.doc.line(item.line);
      changes.push({ from: line.from, to: line.to, insert: setItemDone(line.text, column === done) });
    }
    hushGoTo();
    view.dispatch({ changes, userEvent: 'input.board' });
    fireNativeHaptic('success');
    reveal(view, card.id);
  }

  /** The field a card is typed into is the page's own input: the editor leaves its keys and taps alone. */
  ignoreEvent(event: Event): boolean {
    return event.target instanceof Element && event.target.closest('.cm-boardCompose') !== null;
  }
}

/**
 * The + on a column: a field at the top of it, for the new card's words (Matt: "a button on each board to add an
 * item, it should add the item to the list the board is derived from").
 *
 * The words are asked for before anything is written, and Enter writes the item under the board's last one with an
 * anchor named after them, and the card at the top of this column (core/boards.ts `newCard`). The field stays open
 * and empty for the next card; Escape, or leaving it empty, closes it. Nothing goes into the note's own lines by
 * the caret, so the line is always a proper task item, `- [ ] words ^anchor`.
 */
function openComposer(view: EditorView, pane: HTMLElement, name: string): void {
  const already = pane.querySelector<HTMLInputElement>(':scope > .cm-boardCompose input');
  if (already) {
    already.focus();
    return;
  }
  const form = document.createElement('form');
  form.className = 'cm-boardCompose';
  const field = document.createElement('input');
  field.type = 'text';
  field.className = 'cm-boardComposeField';
  field.placeholder = 'New card';
  field.enterKeyHint = 'done';
  field.autocapitalize = 'sentences';
  field.setAttribute('aria-label', `New card in ${name}`);
  const add = document.createElement('button');
  add.type = 'submit';
  add.className = 'cm-boardComposeAdd';
  add.textContent = 'Add';
  // Pressing Add must not take the focus from the field first, or the phone's keyboard drops between cards.
  add.addEventListener('mousedown', (event) => event.preventDefault());
  form.append(field, add);

  const close = () => form.remove();
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const board = pane.closest('.cm-board');
    if (!board || !field.value.trim()) return;
    // Read where the board is now, not where it was when the field opened: the note may have changed above it.
    const open = view.state.doc.lineAt(view.posAtDOM(board)).number;
    if (!addCard(view, open, Number(pane.dataset.column ?? 0), field.value)) return;
    field.value = '';
    fireNativeHaptic('selection');
  });
  field.addEventListener('keydown', (event) => {
    // Enter adds the card itself: a form inside the note's editable page is not sent by Enter on every browser, and
    // a keyboard still composing a word is left to finish it.
    if (event.key === 'Enter' && !event.isComposing) {
      event.preventDefault();
      form.requestSubmit();
    } else if (event.key === 'Escape') {
      event.preventDefault();
      close();
    }
  });
  field.addEventListener('blur', () => {
    if (field.value.trim()) return;
    window.setTimeout(() => {
      if (document.activeElement !== field) close();
    }, 150);
  });

  pane.querySelector(':scope > .cm-boardName')?.after(form);
  field.focus();
}

/** A card with these words in column `column` of the board that opens on line `open`: the fence and the new line together. */
function addCard(view: EditorView, open: number, column: number, words: string): boolean {
  const made = newCard(view.state.doc.toString(), open, column, words);
  if (!made) return false;
  const doc = view.state.doc;
  const top = doc.line(made.fence.from);
  const bottom = doc.line(made.fence.to);
  const end = made.at > doc.lines;
  const at = end ? doc.length : doc.line(made.at).from;
  // At the end of a note that does not end in a newline, the line needs one of its own in front of it.
  const tail = doc.length ? view.state.sliceDoc(doc.length - 1) : '\n';
  const insert = end ? `${tail === '\n' ? '' : '\n'}${made.text}` : `${made.text}\n`;
  view.dispatch({
    changes: [
      { from: top.to + 1, to: bottom.from - 1, insert: made.fence.body },
      { from: at, insert },
    ],
    userEvent: 'input.board',
  });
  return true;
}

/**
 * A card in the air: what was picked up, and where it would land.
 *
 * The card itself stays in the page as the gap it would leave, emptied out and outlined, and it is that element
 * which moves from place to place as the finger goes: the space under the finger is always the space the card will
 * take. A copy of it follows the finger overhead.
 */
interface Lift {
  board: HTMLElement;
  card: HTMLElement;
  ghost: HTMLElement;
  dx: number;
  dy: number;
  column: number;
  index: number;
  /** The board scrolling itself while a card is held against its edge. */
  scroll: number;
  /** A column scrolling itself while a card is held against its top or foot, now that a column has a height. */
  rise: number;
  /** The column that is rising, so the roll can be stopped when the finger moves to another. */
  rising: HTMLElement | null;
}

function pickUp(board: HTMLElement, card: HTMLElement, held: Card, x: number, y: number): Lift {
  const box = card.getBoundingClientRect();
  const ghost = card.cloneNode(true) as HTMLElement;
  ghost.classList.add('cm-boardGhost');
  ghost.style.inlineSize = `${box.width}px`;
  ghost.style.transform = `translate(${box.left}px, ${box.top}px)`;
  // The copy is drawn over the whole page, so it lives outside the note - but the board's look is written under the
  // editor's own classes (EditorView.baseTheme), so it goes in a layer that carries them. Straight on the body it had
  // no look at all, and was drawn a screen below the finger.
  const editor = board.closest<HTMLElement>('.cm-editor');
  const layer = document.createElement('div');
  layer.className = editor?.className ?? '';
  layer.style.cssText = 'position:fixed;inset:0;z-index:40;pointer-events:none;background:none;border:none;outline:none;display:block';
  // The board's type, since the copy is no longer inside the board that sets it.
  const face = window.getComputedStyle(board);
  layer.style.font = face.font;
  layer.style.color = face.color;
  layer.append(ghost);
  document.body.append(layer);

  card.dataset.lifted = '';
  card.style.blockSize = `${box.height}px`;
  // Held, the finger drags rather than scrolls; the board is scrolled for it at the edges instead.
  card.style.touchAction = 'none';
  board.dataset.holding = '';

  fireNativeHaptic('selection');
  const lift: Lift = { board, card, ghost, dx: x - box.left, dy: y - box.top, column: held.column, index: 0, scroll: 0, rise: 0, rising: null };
  dragTo(lift, x, y);
  return lift;
}

/** The held card follows the finger, the gap goes where it would land, and the board scrolls at its edges. */
function dragTo(lift: Lift, x: number, y: number): void {
  lift.ghost.style.transform = `translate(${x - lift.dx}px, ${y - lift.dy}px)`;

  const box = lift.board.getBoundingClientRect();
  const edge = x < box.left + EDGE ? -EDGE_STEP : x > box.right - EDGE ? EDGE_STEP : 0;
  if (edge && !lift.scroll) {
    const roll = () => {
      lift.board.scrollLeft += edge;
      lift.scroll = requestAnimationFrame(roll);
    };
    lift.scroll = requestAnimationFrame(roll);
  } else if (!edge && lift.scroll) {
    cancelAnimationFrame(lift.scroll);
    lift.scroll = 0;
  }

  const stacks = [...lift.board.querySelectorAll<HTMLElement>('.cm-boardStack')];
  if (!stacks.length) return;
  // The column under the finger, or the nearest one when the finger is past the end of the board.
  const stack =
    stacks.find((pane) => {
      const at = pane.getBoundingClientRect();
      return x >= at.left && x <= at.right;
    }) ??
    stacks.reduce((near, pane) => {
      const gap = (rect: DOMRect) => (x < rect.left ? rect.left - x : x - rect.right);
      return gap(pane.getBoundingClientRect()) < gap(near.getBoundingClientRect()) ? pane : near;
    }, stacks[0]!);

  for (const pane of stacks) delete pane.dataset.over;
  stack.dataset.over = '';

  // A column is only so tall and scrolls inside itself, so a card held near its top or foot rolls it, the way the
  // board rolls sideways at its edges: otherwise a card could never be dropped below what the column shows.
  const shown = stack.getBoundingClientRect();
  const lean = y < shown.top + EDGE ? -EDGE_STEP : y > shown.bottom - EDGE ? EDGE_STEP : 0;
  if (lift.rise && (lift.rising !== stack || !lean)) {
    cancelAnimationFrame(lift.rise);
    lift.rise = 0;
    lift.rising = null;
  }
  if (lean && !lift.rise) {
    lift.rising = stack;
    const roll = () => {
      stack.scrollTop += lean;
      lift.rise = requestAnimationFrame(roll);
    };
    lift.rise = requestAnimationFrame(roll);
  }

  // Where in the column the gap belongs: above the first card whose middle the finger is over.
  const cards = [...stack.querySelectorAll<HTMLElement>('.cm-boardCard')].filter((other) => other !== lift.card);
  const before = cards.find((other) => {
    const at = other.getBoundingClientRect();
    return y < at.top + at.height / 2;
  });
  stack.insertBefore(lift.card, before ?? stack.querySelector('.cm-boardEmpty'));

  lift.column = Number(stack.dataset.column ?? 0);
  lift.index = [...stack.querySelectorAll<HTMLElement>('.cm-boardCard')].indexOf(lift.card);
}

/** The card set down: the copy overhead goes, and the card is a card again, wherever it ended up. */
function putDown(lift: Lift): void {
  if (lift.scroll) cancelAnimationFrame(lift.scroll);
  if (lift.rise) cancelAnimationFrame(lift.rise);
  // The layer the copy was drawn in goes with it.
  (lift.ghost.parentElement ?? lift.ghost).remove();
  delete lift.card.dataset.lifted;
  lift.card.style.removeProperty('block-size');
  lift.card.style.removeProperty('touch-action');
  delete lift.board.dataset.holding;
  for (const pane of lift.board.querySelectorAll<HTMLElement>('.cm-boardStack')) delete pane.dataset.over;
}

/** The caret put on a line of the note, and the note scrolled to it. */
function goToLine(view: EditorView, line: number): void {
  if (line < 1 || line > view.state.doc.lines) return;
  const at = view.state.doc.line(line);
  view.dispatch({ selection: EditorSelection.cursor(at.to), effects: EditorView.scrollIntoView(at.from, { y: 'center' }), scrollIntoView: true });
  view.focus();
}

/** A button that answers a tap without the editor taking the press as a caret move. */
/**
 * A status changed on the board - a card ticked, or dropped in another lane - keeps the person on the board (Matt:
 * "when changing the status of a ticket to done it jumps me way down to the item in the list instead of moving me to
 * view the task on the board"). For a moment after one, a press on a card's words is not taken as "go to the line":
 * on a phone the tick box sits beside the words, and a finger a little off, or the click a drop leaves behind, landed
 * on them and scrolled the note away.
 */
const QUIET_MS = 700;
let quietUntil = 0;

function hushGoTo(): void {
  quietUntil = Date.now() + QUIET_MS;
}

/**
 * The card where it landed, shown: its lane brought across the board and the card brought into its lane, then a short
 * flash so the eye finds it. Only the board and the lane are scrolled; the note stays where it is.
 */
function reveal(view: EditorView, id: string): void {
  // Twice over a frame: the board is redrawn by the change that moved the card, and the card is in its lane after that.
  requestAnimationFrame(() =>
    requestAnimationFrame(() => {
      const card = view.dom.querySelector<HTMLElement>(`.cm-boardCard[data-card="${CSS.escape(id)}"]`);
      const board = card?.closest<HTMLElement>('.cm-board');
      const lane = card?.closest<HTMLElement>('.cm-boardColumn');
      const stack = card?.closest<HTMLElement>('.cm-boardStack');
      if (!card || !board || !lane || !stack) return;
      const boardBox = board.getBoundingClientRect();
      const laneBox = lane.getBoundingClientRect();
      if (laneBox.left < boardBox.left || laneBox.right > boardBox.right) {
        board.scrollTo({ left: board.scrollLeft + laneBox.left - boardBox.left, behavior: 'smooth' });
      }
      const stackBox = stack.getBoundingClientRect();
      const cardBox = card.getBoundingClientRect();
      if (cardBox.top < stackBox.top || cardBox.bottom > stackBox.bottom) {
        stack.scrollTo({ top: stack.scrollTop + cardBox.top - stackBox.top - 8, behavior: 'smooth' });
      }
      card.dataset.arrived = '';
      window.setTimeout(() => delete card.dataset.arrived, 900);
    }),
  );
}

function press(button: HTMLElement, run: () => void): void {
  button.addEventListener('mousedown', (event) => event.preventDefault());
  button.addEventListener('click', (event) => {
    event.preventDefault();
    event.stopPropagation();
    run();
  });
}

/** What a board looks like now, so the widget is rebuilt only when something on it changed. */
function faceOf(board: Drawn): string {
  return [
    board.columns.map((column) => `${column.name}:${column.cards.join(',')}`).join('|'),
    board.cards
      .map((card) => `${card.id}@${card.column}:${card.item ? `${card.item.done === null ? '-' : card.item.done ? 'x' : ' '}${card.item.text}` : 'gone'}`)
      .join('|'),
  ].join('||');
}

function decorate(state: EditorState, focused: boolean): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  for (const board of boards(state)) {
    // The caret in the fence: the lines themselves, to edit. Elsewhere, and in a view with no caret, the board.
    const inside = focused && state.selection.ranges.some((range) => range.from <= board.to && range.to >= board.from);
    if (inside) continue;
    builder.add(board.from, board.to, Decoration.replace({ widget: new BoardWidget(board, faceOf(board)), block: true }));
  }
  return builder.finish();
}

const boardField = StateField.define<DecorationSet>({
  create: (state) => decorate(state, false),
  update(value, tr) {
    const focused = tr.state.field(focusField);
    return tr.docChanged || tr.selection || tr.startState.field(focusField) !== focused ? decorate(tr.state, focused) : value;
  },
  provide: (field) => EditorView.decorations.from(field),
});

/**
 * The anchor on a line, and a pointer at one from the words (core/boards.ts).
 *
 * `^ship-page` at the end of an item is a name, not something to read: it is drawn small and faint, so the line
 * reads as its words. `[[#^ship-page]]` in the middle of a line is the other end of the same thing - a tap on it
 * goes to the item it names, wherever in the note that is.
 */
const anchorMark = Decoration.mark({ class: 'cm-itemAnchor' });
const refMark = Decoration.mark({ class: 'cm-itemRef' });
const goneMark = Decoration.mark({ class: 'cm-itemRef cm-itemRefGone' });

function anchors(state: EditorState): DecorationSet {
  const doc = state.doc.toString();
  const builder = new RangeSetBuilder<Decoration>();
  const named = new Set(itemsIn(doc).map((item) => item.id));
  for (let line = 1; line <= state.doc.lines; line += 1) {
    const at = state.doc.line(line);
    const marks: { from: number; to: number; mark: Decoration }[] = [];
    const item = itemOnLineAt(at.text);
    if (item) marks.push({ from: at.to - item.length, to: at.to, mark: anchorMark });
    for (const ref of refsIn(at.text, at.from)) marks.push({ from: ref.from, to: ref.to, mark: named.has(ref.id) ? refMark : goneMark });
    for (const mark of marks.sort((one, two) => one.from - two.from)) builder.add(mark.from, mark.to, mark.mark);
  }
  return builder.finish();
}

/** The `^anchor` at the end of a line, as it is written there, or null. */
function itemOnLineAt(text: string): string | null {
  const found = /\s(\^[a-z0-9][a-z0-9_-]*)\s*$/.exec(text);
  return found && itemsIn(text).length ? (found[1] ?? null) : null;
}

const anchorField = StateField.define<DecorationSet>({
  create: (state) => anchors(state),
  update: (value, tr) => (tr.docChanged ? anchors(tr.state) : value.map(tr.changes)),
  provide: (field) => EditorView.decorations.from(field),
});

/** A tap on `[[#^anchor]]`: the caret goes to the item it names. */
const refTaps = EditorView.domEventHandlers({
  mousedown(event, view) {
    const target = event.target as HTMLElement | null;
    if (!target?.classList.contains('cm-itemRef')) return false;
    const at = view.posAtDOM(target);
    const line = view.state.doc.lineAt(at);
    const ref = refsIn(line.text, line.from).find((found) => found.from <= at + 2 && found.to >= at);
    const item = ref ? itemAt(view.state.doc.toString(), ref.id) : null;
    if (!item) return false;
    event.preventDefault();
    goToLine(view, item.line);
    return true;
  },
});

/**
 * How much room a board has, and how far the page's own margin reaches (`--cm-board-room`, `--cm-board-bleed`).
 *
 * A board is a row of columns wider than a phone, and a block widget's width is what decides how wide the editor's
 * content is: left to itself the board made every line of the note as wide as the board, and the words ran off the
 * screen. So the board is told what it may take - the width the note scrolls in - and scrolls its columns inside
 * that. The bleed is the note's own indent, given back so the columns run edge to edge and still line up with the
 * words when the board is scrolled home.
 */
const boardRoom = ViewPlugin.fromClass(
  class {
    constructor(readonly view: EditorView) {
      this.measure();
    }

    update(update: ViewUpdate): void {
      if (update.geometryChanged || update.docChanged) this.measure();
    }

    measure(): void {
      this.view.requestMeasure({
        read: (view) => {
          const line = view.contentDOM.querySelector('.cm-line');
          const style = line ? window.getComputedStyle(line) : null;
          const bleed = style ? parseFloat(style.paddingInlineStart || '0') || 0 : 0;
          // The whole width the note scrolls in: the board starts where the page's indent does and ends at its edge.
          return { room: Math.max(160, view.scrollDOM.clientWidth || view.dom.clientWidth), bleed };
        },
        write: ({ room, bleed }, view) => {
          view.dom.style.setProperty('--cm-board-room', `${room}px`);
          view.dom.style.setProperty('--cm-board-bleed', `${bleed}px`);
        },
      });
    }
  },
);

const boardTheme = EditorView.baseTheme({
  '.cm-board': {
    display: 'flex',
    gap: '0.7em',
    // As wide as the note is, never as wide as its columns: the columns scroll inside it (`boardRoom`).
    inlineSize: 'var(--cm-board-room, 100%)',
    // A block widget sits outside the note's own indent, so the indent is put back as padding: the first column
    // lines up with the words, and a column scrolled along runs to the edge of the screen.
    paddingInline: 'var(--cm-board-bleed, 0px)',
    scrollPaddingInline: 'var(--cm-board-bleed, 0px)',
    overflowX: 'auto',
    overscrollBehaviorX: 'contain',
    // One column at a time on a phone: a swipe settles on a column rather than between two.
    scrollSnapType: 'x mandatory',
    marginBlock: '0.4em 0.9em',
    paddingBlock: '0.1em 0.5em',
    scrollbarWidth: 'none',
    fontSize: '0.86em',
    textIndent: '0',
  },
  '.cm-board[data-holding]': { scrollSnapType: 'none', cursor: 'grabbing' },
  '.cm-boardColumn': {
    flex: '0 0 auto',
    inlineSize: 'min(78vw, 16rem)',
    scrollSnapAlign: 'start',
    display: 'flex',
    flexDirection: 'column',
    gap: '0.4em',
    padding: '0.5em 0.45em 0.2em',
    borderRadius: 'var(--glacier-radius-lg, 0.75rem)',
    background: 'color-mix(in oklch, currentColor 4%, transparent)',
  },
  '.cm-boardName': {
    display: 'flex',
    alignItems: 'center',
    gap: '0.45em',
    margin: '0',
    padding: '0 0.15em',
    minBlockSize: '1.9em',
    fontSize: '0.78em',
    fontWeight: '700',
    letterSpacing: '0.07em',
    textTransform: 'uppercase',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
  },
  '.cm-boardNameWords': { overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' },
  '.cm-boardCount': {
    flex: 'none',
    minInlineSize: '1.6em',
    padding: '0.05em 0.45em',
    borderRadius: '999px',
    background: 'color-mix(in oklch, currentColor 10%, transparent)',
    textAlign: 'center',
    letterSpacing: '0',
    fontWeight: '600',
  },
  '.cm-boardAdd': {
    flex: 'none',
    display: 'grid',
    placeItems: 'center',
    marginInlineStart: 'auto',
    inlineSize: '2em',
    blockSize: '2em',
    padding: '0',
    border: 'none',
    borderRadius: '999px',
    background: 'color-mix(in oklch, currentColor 8%, transparent)',
    color: 'var(--app-ink-2, inherit)',
    cursor: 'pointer',
  },
  /* The field a new card is typed into, under the column's name. */
  '.cm-boardCompose': {
    display: 'flex',
    gap: '0.4em',
    alignItems: 'center',
    padding: '0.3em',
    borderRadius: 'var(--glacier-radius-lg, 0.75rem)',
    border: '1px solid var(--app-ink-3, var(--glacier-border-strong))',
    background: 'var(--app-paper-2, var(--glacier-surface))',
  },
  '.cm-boardComposeField': {
    flex: '1 1 auto',
    minInlineSize: '0',
    minBlockSize: '2.2em',
    padding: '0 0.4em',
    border: 'none',
    background: 'none',
    color: 'inherit',
    font: 'inherit',
    outline: 'none',
  },
  '.cm-boardComposeAdd': {
    flex: 'none',
    minBlockSize: '2.2em',
    padding: '0 0.8em',
    border: 'none',
    borderRadius: '0.5em',
    background: 'var(--app-ink, currentColor)',
    color: 'var(--app-paper, var(--glacier-bg))',
    font: 'inherit',
    fontWeight: '600',
    cursor: 'pointer',
  },
  '.cm-boardStack': {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.4em',
    minBlockSize: '2.5em',
    maxBlockSize: 'min(42vh, 19rem)',
    overflowY: 'auto',
    overscrollBehaviorY: 'contain',
    scrollbarWidth: 'none',
    paddingBlockEnd: '0.9em',
    WebkitMaskImage: 'linear-gradient(to bottom, #000 calc(100% - 1.1em), transparent)',
    maskImage: 'linear-gradient(to bottom, #000 calc(100% - 1.1em), transparent)',
  },
  /*
   * A card is a small grid (Matt: "the cards themselves can have the text go full width and we can move the notion icon
   * to the right more"): the tick and the words on the first row, the words taking every bit of width the card has,
   * and under them a footer that sits right - the plugin's mark, then the two arrows.
   */
  '.cm-boardCard': {
    display: 'grid',
    gridTemplateColumns: 'auto 1fr auto auto',
    gridTemplateAreas: '"tick words words words" ". . linked moves"',
    alignItems: 'start',
    columnGap: '0.55em',
    rowGap: '0.15em',
    flex: 'none',
    minBlockSize: '2.6em',
    padding: '0.6em 0.4em 0.3em 0.65em',
    borderRadius: '0.7em',
    background: 'var(--app-paper, var(--glacier-bg))',
    boxShadow: 'inset 0 0 0 1px color-mix(in oklch, currentColor 9%, transparent), 0 1px 2px rgba(0, 0, 0, 0.12)',
    // The finger scrolls until the card is picked up, and then the drag takes over.
    touchAction: 'pan-x pan-y',
    userSelect: 'none',
    WebkitUserSelect: 'none',
    WebkitTapHighlightColor: 'transparent',
    transition: 'opacity 120ms ease',
  },
  '.cm-boardCard[data-done]': { opacity: '0.62' },
  /* The card where it would land: its own shape, emptied out, so the column opens exactly the space it takes. */
  '.cm-boardCard[data-lifted]': {
    background: 'color-mix(in oklch, currentColor 4%, transparent)',
    borderStyle: 'dashed',
    overflow: 'hidden',
  },
  '.cm-boardCard[data-lifted] > *': { visibility: 'hidden' },
  '.cm-boardCard[data-done] .cm-boardWords': { textDecoration: 'line-through', color: 'var(--app-ink-3, var(--glacier-text-muted))' },
  '.cm-boardCard[data-gone] .cm-boardWords': { fontStyle: 'italic', color: 'var(--app-ink-3, var(--glacier-text-muted))' },
  '.cm-boardCard[data-empty] .cm-boardWords': { fontStyle: 'italic', color: 'var(--app-ink-3, var(--glacier-text-muted))' },
  /* The card in the air, under the finger: the same card, lifted off the page. */
  '.cm-boardGhost': {
    position: 'fixed',
    insetBlockStart: '0',
    insetInlineStart: '0',
    zIndex: '40',
    margin: '0',
    pointerEvents: 'none',
    boxShadow: '0 10px 24px rgba(0, 0, 0, 0.28)',
    transform: 'translate(0, 0)',
    opacity: '0.96',
  },
  '.cm-boardEmpty': {
    display: 'none',
    margin: '0',
    padding: '0.8em 0.6em',
    borderRadius: 'var(--glacier-radius-lg, 0.75rem)',
    border: '1px dashed var(--app-rule, var(--glacier-border-subtle))',
    textAlign: 'center',
    fontSize: '0.9em',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
  },
  '.cm-board[data-holding] .cm-boardEmpty': { display: 'block' },
  '.cm-boardStack[data-over] .cm-boardEmpty': { borderStyle: 'solid' },
  // Sized from the card's own text rather than a button's default font, and set on the first line's centre, so every
  // box sits level with the words beside it (Matt: "the checkboxes also dont look like they line up nice").
  '.cm-boardTick': {
    gridArea: 'tick',
    position: 'relative',
    display: 'grid',
    placeItems: 'center',
    fontSize: 'inherit',
    lineHeight: '1',
    inlineSize: '1.15em',
    blockSize: '1.15em',
    marginBlockStart: 'calc((1.35em - 1.15em) / 2)',
    padding: '0',
    borderRadius: '0.32em',
    // The box's edge is named in ink, not `currentColor`: the tick's own colour is paper, for the check drawn on ink.
    border: '1.5px solid color-mix(in oklch, var(--app-ink, var(--glacier-text)) 45%, transparent)',
    background: 'none',
    color: 'var(--app-paper, var(--glacier-bg))',
    cursor: 'pointer',
  },
  '.cm-boardTick svg': { visibility: 'hidden' },
  // The box is small; the place to tap it is not. An invisible margin around it takes a finger that lands a little off,
  // which otherwise hit the words beside it and went to the line.
  '.cm-boardTick::before': { content: '""', position: 'absolute', inset: '-0.6em -0.45em -0.6em -0.6em' },
  // A card that has just arrived in its lane, lit for a moment so the eye finds it.
  '.cm-boardCard[data-arrived]': {
    boxShadow: 'inset 0 0 0 1.5px color-mix(in oklch, var(--app-ink, currentColor) 55%, transparent), 0 1px 2px rgba(0, 0, 0, 0.12)',
  },
  '.cm-boardCard[data-done] .cm-boardTick': {
    background: 'var(--app-ink, currentColor)',
    borderColor: 'var(--app-ink, currentColor)',
  },
  '.cm-boardCard[data-done] .cm-boardTick svg': { visibility: 'visible' },
  '.cm-boardTick:disabled': { opacity: '0.4', cursor: 'default' },
  /* An item with no box: a bullet, kept so every card's words start in the same place. */
  '.cm-boardDot': {
    gridArea: 'tick',
    justifySelf: 'center',
    flex: 'none',
    inlineSize: '0.4em',
    blockSize: '0.4em',
    marginBlockStart: '0.55em',
    marginInline: '0.45em',
    borderRadius: '50%',
    background: 'var(--app-ink-3, currentColor)',
  },
  '.cm-boardWords': {
    gridArea: 'words',
    minInlineSize: '0',
    // Three lines at most: one long item must not take the whole board. The words are whole in the note below.
    display: '-webkit-box',
    WebkitLineClamp: '3',
    WebkitBoxOrient: 'vertical',
    overflow: 'hidden',
    padding: '0',
    border: 'none',
    background: 'none',
    font: 'inherit',
    lineHeight: '1.35',
    textAlign: 'start',
    color: 'inherit',
    cursor: 'pointer',
  },
  // The plugin a card's item is linked to, as its mark: quiet, beside the words, never read as one of them.
  '.cm-boardLinked': {
    gridArea: 'linked',
    alignSelf: 'center',
    display: 'grid',
    placeItems: 'center',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
    opacity: '0.8',
  },
  '.cm-boardMoves': { gridArea: 'moves', display: 'flex', gap: '0', marginInlineEnd: '-0.1em' },
  '.cm-boardMove': {
    display: 'grid',
    placeItems: 'center',
    inlineSize: '1.7em',
    blockSize: '1.7em',
    padding: '0',
    border: 'none',
    borderRadius: '999px',
    background: 'none',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
    opacity: '0.7',
    cursor: 'pointer',
  },
  '.cm-boardMove:disabled': { opacity: '0.25', cursor: 'default' },
  /* The anchor on the line, and a pointer at one from the words. */
  '.cm-itemAnchor': { fontSize: '0.82em', opacity: '0.45' },
  '.cm-itemRef': {
    textDecoration: 'underline',
    textUnderlineOffset: '0.2em',
    textDecorationThickness: '0.06em',
    textDecorationColor: 'color-mix(in oklch, currentColor 45%, transparent)',
    cursor: 'pointer',
  },
  '.cm-itemRefGone': { opacity: '0.55', textDecorationStyle: 'dotted' },
});

/** Boards drawn in a note, the fence still there to edit. */
export function drawnBoards(): Extension {
  return [focusField, boardField, anchorField, refTaps, boardRoom, boardTheme, EditorView.focusChangeEffect.of((_state, focusing) => setFocus.of(focusing))];
}
