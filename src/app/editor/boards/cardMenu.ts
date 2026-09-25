import { Facet } from '@codemirror/state';
import type { EditorView } from '@codemirror/view';
import { itemWords, type BoardColumn, type Card, type Item } from '../../core/boards.ts';
import { icon, type IconName } from './icons.ts';
import { goToLine } from './navigate.ts';
import { press } from './press.ts';

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

/**
 * A card's own menu (Matt: "Add context menu to board items for moving lanes and adding to notion etc.").
 *
 * It opens from the card's **more** button rather than a press and hold, because a press and hold is already how a
 * card is picked up to drag. It sits in the lane right under its card, the way the + field sits at the top of a
 * column: no floating panel to place, and it scrolls with the board it belongs to.
 *
 * What it offers: each other lane to move to, the item's tick, the line in the note, whatever a plugin offers this
 * item (its own line's offer first, then the one a swipe would run), and the card off the board. Nothing that cannot
 * be done is shown, so a card whose item is gone offers only to take itself off.
 */
export function openCardMenu(view: EditorView, card: Card, at: HTMLElement, does: CardMoves): void {
  const stack = at.closest<HTMLElement>('.cm-boardStack');
  if (!stack) return;
  // A second press on the button closes it again, and only one is ever open.
  const already = stack.querySelector('.cm-boardMenu');
  const mine = already?.previousElementSibling === at;
  for (const open of at.closest('.cm-board')?.querySelectorAll('.cm-boardMenu') ?? []) open.remove();
  if (mine) return;

  const menu = document.createElement('div');
  menu.className = 'cm-boardMenu';
  menu.setAttribute('role', 'menu');
  menu.setAttribute('aria-label', 'Card');

  const row = (label: string, glyph: IconName, run: () => void) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'cm-boardMenuRow';
    button.setAttribute('role', 'menuitem');
    button.append(icon(glyph, '1em'));
    const words = document.createElement('span');
    words.textContent = label;
    button.append(words);
    press(button, () => {
      close();
      run();
    });
    menu.append(button);
    return button;
  };

  const close = () => {
    menu.remove();
    window.removeEventListener('pointerdown', away, true);
    window.removeEventListener('keydown', escape, true);
  };
  const away = (event: PointerEvent) => {
    if (!(event.target instanceof Node) || (!menu.contains(event.target) && event.target !== at)) close();
  };
  const escape = (event: KeyboardEvent) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      close();
    }
  };

  const item = card.item;
  // Every other lane, in the board's own order.
  does.columns.forEach((column, index) => {
    if (index === card.column) return;
    row(`Move to ${column.name}`, index < card.column ? 'left' : 'right', () => does.land(index));
  });
  if (item && item.done !== null) {
    row(item.done ? 'Untick' : 'Tick', 'check', () => does.tick());
  }
  if (item) {
    row('Go to the line', 'words', () => goToLine(view, item.line));
    const offer = pluginOffer(view, item);
    if (offer) row(offer.label, 'link', () => void offer.run());
  }
  row('Take off the board', 'off', () => does.takeOff());

  at.after(menu);
  menu.querySelector('button')?.focus();
  menu.scrollIntoView({ block: 'nearest' });
  window.addEventListener('pointerdown', away, true);
  window.addEventListener('keydown', escape, true);
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
