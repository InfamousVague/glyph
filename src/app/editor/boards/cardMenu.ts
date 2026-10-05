import { Facet } from '@codemirror/state';
import type { EditorView } from '@codemirror/view';
import { createElement } from 'react';
import { itemWords, type BoardColumn, type Card, type Item } from '../../core/boards.ts';
import { mountReact } from '../reactMount.ts';
import type { IconName } from './icons.ts';
import { goToLine } from './navigate.ts';

/**
 * What a plugin offers a card, given the item's line and its words (Matt: "Add context menu to board items for moving
 * lanes and adding to notion etc.").
 *
 * The line comes first and the words second on purpose: a card names an exact line, and two items that read the same
 * way are told apart by nothing else. `suggest` is the per-line offer the note already shows quietly under a line
 * (editor/suggestions.ts); `action` is the one a swipe on a list item runs (editor/swipeItems.ts), by text, and is
 * only reached for when there is no offer for that line. Neither goes near a plugin: both are the registry's.
 */
export interface CardActions {
  suggest: (body: string) => { line: number; label: string; run: () => Promise<void> }[];
  action: () => { label: string; run: (text: string) => Promise<void> } | null;
}

/** What this editor's plugins offer a card, or nothing where the note is not one a plugin acts on. */
export const cardActions = Facet.define<CardActions, CardActions | null>({ combine: (values) => values[0] ?? null });

/** What the menu's rows do to the card: the board's own edits (editor/boards/cardEdits.ts), bound to this card. */
export interface CardMoves {
  /** The board's lanes, in its own order. */
  columns: readonly BoardColumn[];
  /** Into lane `column`, at its foot. */
  land(column: number): void;
  tick(): void;
  takeOff(): void;
}

/** A row of a card's menu: what it says, the board's icon beside it, and what it does to the card. */
export interface CardRow {
  label: string;
  icon: IconName;
  run: () => void;
}

/**
 * What a card's menu offers (Matt: "Add context menu to board items for moving lanes and adding to notion etc."): each
 * other lane to move to, the item's tick, the line in the note, whatever a plugin offers this item (its own line's
 * offer first, then the one a swipe would run), and the card off the board. Nothing that cannot be done is offered,
 * so a card whose item is gone offers only to take itself off. The rows are the card as it is when the menu opens.
 */
export function cardRows(view: EditorView, card: Card, does: CardMoves): CardRow[] {
  const rows: CardRow[] = [];
  const item = card.item;
  // Every other lane, in the board's own order.
  does.columns.forEach((column, index) => {
    if (index === card.column) return;
    rows.push({ label: `Move to ${column.name}`, icon: index < card.column ? 'left' : 'right', run: () => does.land(index) });
  });
  if (item && item.done !== null) {
    rows.push({ label: item.done ? 'Untick' : 'Tick', icon: 'check', run: () => does.tick() });
  }
  if (item) {
    rows.push({ label: 'Go to the line', icon: 'words', run: () => goToLine(view, item.line) });
    const offer = pluginOffer(view, item);
    if (offer) rows.push({ label: offer.label, icon: 'link', run: () => void offer.run() });
  }
  rows.push({ label: 'Take off the board', icon: 'off', run: () => does.takeOff() });
  return rows;
}

/**
 * A card's own menu, hung from its **more** button over the page (editor/boards/CardMenu.tsx).
 *
 * It opens from a button rather than a press and hold, because a press and hold is already how a card is picked up to
 * drag. It is the kit's menu (Matt: "Allow the header to be overlapped by the popup menus use the glacierUI context
 * menus"): it sat in the lane right under its card, where the lane cut its last rows off and, near the top of the
 * note, the header covered it; now it is drawn at the body, whole, over the header where it must be.
 *
 * One is open at a time, and a second press on the same button closes it. It closes on a row, on Escape (the focus
 * going back to the button), on a press anywhere else and on the back gesture (editor/PopMenu.tsx), and on any change
 * to the note or a redraw that takes its button away (boards.ts): its rows are the card as it was when it opened.
 *
 * The kit is loaded when a card's menu first opens, never imported here: the kit asks `matchMedia` as its module
 * loads, which jsdom has not got, and this module is reached through boards.ts by the editor, doneSync.ts,
 * taskToggle.ts and their tests. In the app the shell has loaded the kit long before.
 */
let open: { view: EditorView; more: HTMLElement; close: () => void } | null = null;

export function openCardMenu(view: EditorView, card: Card, more: HTMLElement, does: CardMoves): void {
  const again = open?.more === more;
  closeCardMenu();
  if (again) return;
  const rows = cardRows(view, card, does);
  const host = document.createElement('div');
  host.className = 'cm-cardMenuHost';
  let unmount: (() => void) | null = null;
  let closed = false;
  const mine = {
    view,
    more,
    close: () => {
      if (closed) return;
      closed = true;
      unmount?.();
      host.remove();
      if (open === mine) open = null;
    },
  };
  // Open from the press, before the kit has loaded, so a second press while it loads closes it again.
  open = mine;
  void import('./CardMenu.tsx').then(({ CardMenu }) => {
    if (closed) return;
    document.body.append(host);
    // A React root of its own, over the page (editor/reactMount.ts), taken down a microtask after it is closed.
    unmount = mountReact(host, createElement(CardMenu, { more, rows, onDismiss: mine.close }));
  });
}

/** Closes the card menu that is open, or only the one `view` opened; safe whether or not one is. */
export function closeCardMenu(view?: EditorView): void {
  if (open && (!view || open.view === view)) open.close();
}

/** Whether `view` has a card's menu open. */
export function cardMenuIn(view: EditorView): boolean {
  return open?.view === view;
}

/** Closes `view`'s card menu if the more button it hangs from has left the page: the board was drawn again. */
export function closeCardMenuIfGone(view: EditorView): void {
  if (open?.view === view && !open.more.isConnected) open.close();
}

/** What a plugin offers this item: its own line's offer, else the one a swipe on the line would run. Null for none. */
function pluginOffer(view: EditorView, item: Item): { label: string; run: () => Promise<void> } | null {
  const actions = view.state.facet(cardActions);
  if (!actions) return null;
  // The line first: a card names an exact line, and two items that read the same way are told apart by nothing else.
  const here = actions.suggest(view.state.doc.toString()).find((offer) => offer.line === item.line);
  if (here) return { label: here.label, run: here.run };
  const action = actions.action();
  return action ? { label: action.label, run: () => action.run(itemWords(view.state.doc.line(item.line).text) ?? item.text) } : null;
}
