import { isDoneName } from '../itemSyntax.ts';
import type { BoardColumn } from './fence.ts';
import type { Item } from './items.ts';

/**
 * A board's columns as data: which one holds a card and which is Done, a card moved along, dropped between two
 * others or taken off, the columns as the board draws them with every ticked card in Done, and each card paired with
 * the item it names - or the one it meant, when its anchor slipped.
 *
 * Every write here answers new columns and never changes the ones it is given (`copy`): the editor hands over state
 * it must not see change, and columns.test.ts holds these to it.
 */

/** Which column holds `id`, or -1. */
export function columnOf(columns: readonly BoardColumn[], id: string): number {
  return columns.findIndex((column) => column.cards.includes(id));
}

/** The column a board calls Done, or -1: the one a ticked item belongs in. */
export function doneColumn(columns: readonly BoardColumn[]): number {
  return columns.findIndex((column) => isDoneName(column.name));
}

/** A copy nothing shares with the columns given: every write here answers new columns, never the ones passed in. */
function copy(columns: readonly BoardColumn[]): BoardColumn[] {
  return columns.map((column) => ({ ...column, cards: [...column.cards] }));
}

/** The columns with `id` moved `by` columns along, as far as there are columns to move it to. */
export function moveCard(columns: readonly BoardColumn[], id: string, by: number): BoardColumn[] {
  const from = columnOf(columns, id);
  if (from < 0) return copy(columns);
  const to = Math.min(columns.length - 1, Math.max(0, from + by));
  // Already at the end it was pushed against: nothing moves, and the card stays where it is.
  if (to === from) return copy(columns);
  return putCard(columns, id, to);
}

/** The columns with `id` at the end of `to`, wherever it was. */
export function putCard(columns: readonly BoardColumn[], id: string, to: number): BoardColumn[] {
  return putCardAt(columns, id, to, Number.MAX_SAFE_INTEGER);
}

/**
 * The columns with `id` in `to` at `index`, wherever it was: what a card dropped between two others becomes
 * (Matt: "add a way to tap and drag to re organize items in lanes").
 *
 * The index counts the column as it will be, the card taken out of wherever it was first, so dragging a card down
 * its own column lands it where the gap was shown and not one place short.
 */
export function putCardAt(columns: readonly BoardColumn[], id: string, to: number, index: number): BoardColumn[] {
  if (to < 0 || to >= columns.length) return copy(columns);
  const without = columns.map((column) => column.cards.filter((card) => card !== id));
  const target = without[to] ?? [];
  const at = Math.max(0, Math.min(target.length, index));
  target.splice(at, 0, id);
  return columns.map((column, i) => ({ ...column, cards: i === to ? target : (without[i] ?? []) }));
}

/**
 * The ticks and the lanes, brought back together.
 *
 * A column called Done means done, so an item ticked anywhere is DRAWN in the Done lane whatever its fence says
 * (`columnFor`). Ticking a box in the note's list, or a task going Done in Notion (editor/doneSync.ts), never moved
 * the id, so a note could drift until a lane held seventeen ids and drew two of them (Matt, of his Task Management
 * note: "items are in the Doing swimlane in the board code" while the lane drew nothing). The board was right and the
 * markdown was stale, which is the wrong way round: the markdown is the note.
 *
 * `settleColumns` gives the columns as the board draws them: every ticked item's card in Done. `moved` is a card the
 * person has just moved by hand, which is left exactly where they put it.
 */
export function settleColumns(columns: readonly BoardColumn[], items: readonly Item[], moved?: string): BoardColumn[] {
  const done = doneColumn(columns);
  if (done < 0) return copy(columns);
  let next = copy(columns);
  for (const item of items) {
    if (item.id === moved || item.done !== true) continue;
    const at = columnOf(next, item.id);
    if (at >= 0 && at !== done) next = putCard(next, item.id, done);
  }
  return next;
}

/**
 * The columns without `id`: the card taken off the board, its item left exactly where it is in the note (Matt: "Add
 * context menu to board items for moving lanes and adding to notion etc."). A board never has to hold every item.
 */
export function withoutCard(columns: readonly BoardColumn[], id: string): BoardColumn[] {
  return columns.map((column) => ({ ...column, cards: column.cards.filter((card) => card !== id) }));
}

/** A board's cards, each with the item it names: the ones whose item is gone are answered too, so nothing vanishes. */
export interface Card {
  id: string;
  column: number;
  item: Item | null;
}

export function cardsOf(
  columns: readonly BoardColumn[],
  items: readonly Item[],
  named: ReadonlySet<string> = new Set(columns.flatMap((column) => column.cards)),
): Card[] {
  const byId = new Map(items.map((item) => [item.id, item]));
  // Items no board names: where a card's anchor matches no item, one of these may be the item it meant.
  const loose = items.filter((item) => !named.has(item.id));
  return columns.flatMap((column, index) => column.cards.map((id) => ({ id, column: index, item: byId.get(id) ?? slipOf(id, loose) })));
}

/**
 * The item a card meant when its anchor matches none: the one item, named by no board, whose anchor is a slip of
 * the card's (Matt: "the second item got glitched out on the board" - the fence said `blur-bottom-swimlanes`, the
 * line `^blur-bottom-swimlaness`). Only a single such item counts, and only for an anchor long enough to be sure.
 */
function slipOf(id: string, loose: readonly Item[]): Item | null {
  if (id.length < 4) return null;
  const near = loose.filter((item) => nearAnchor(id, item.id));
  return near.length === 1 ? (near[0] ?? null) : null;
}

/** Two anchors a slip apart: one letter added, dropped or changed, or up to two letters more or fewer at the end. */
export function nearAnchor(one: string, two: string): boolean {
  if (one === two) return false;
  const [short, long] = one.length <= two.length ? [one, two] : [two, one];
  const more = long.length - short.length;
  if (more <= 2 && long.startsWith(short)) return true;
  if (more > 1) return false;
  let at = 0;
  while (at < short.length && short[at] === long[at]) at += 1;
  return more === 0 ? short.slice(at + 1) === long.slice(at + 1) : short.slice(at) === long.slice(at + 1);
}

/** An item's own column: the Done one when it is ticked, else where the board has it. */
export function columnFor(columns: readonly BoardColumn[], item: Item): number {
  const done = doneColumn(columns);
  if (item.done === true && done >= 0) return done;
  return columnOf(columns, item.id);
}
