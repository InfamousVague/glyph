import { ANCHOR_NAME } from '../itemSyntax.ts';
import { itemsIn } from './items.ts';

/**
 * The ```board fence: a board's columns read from its body and written back, its settings (`height=18`), where each
 * board in a note is, and a board taken away as words.
 *
 * A fence's lines are its columns, `To do: ship-page, ask-sam`, each naming anchors. The ids are read against the
 * note's own anchors (items.ts), so a lane written or dictated by hand still finds its cards, and written back the one
 * way a person would type them. The fence is known here and nowhere else (docs/BOARDS.md). So is the question every
 * reader of a note's lists asks first, which lines sit inside a fenced block at all and are code rather than a list.
 */

export interface BoardColumn {
  name: string;
  /** The anchors of the cards in it, in the order they sit. */
  cards: string[];
}

/** An anchor name alone: what a lane's id must be to be read as it is written. */
const NAMED = new RegExp(`^${ANCHOR_NAME}$`);
/**
 * The fence that opens a board, and what follows the word: `board`, or `board height=18`. What follows is the
 * board's settings as `name=value` words, which any other renderer takes as part of the block's info string.
 */
const OPEN = /^\s*(`{3,}|~{3,})\s*board(?:\s+([^\n]*?))?\s*$/i;
/** `height=18`: how tall a board's lanes are, in the lanes' own ems (Matt: "make board height configurable"). */
const HEIGHT = /(?:^|\s)height=(\d+(?:\.\d+)?)(?:em)?(?=\s|$)/i;
/** The shortest and tallest a board's lanes can be set, in ems: a card and a half, and a long screen. */
export const BOARD_HEIGHT = { min: 5, max: 60 };

/** The columns a board fence's body lays out. A line with no colon is a column with no cards. */
export function readBoard(body: string, known: ReadonlySet<string> = new Set()): BoardColumn[] {
  const columns: BoardColumn[] = [];
  // An anchor names one item, and a card is one card: an id is read into the first lane that has it, and a second
  // mention of it, in that lane or another, is dropped. Written by hand into two lanes, it used to be drawn twice in
  // the first of them, and the lane a person had put it in showed nothing at all.
  const taken = new Set<string>();
  for (const line of body.split('\n')) {
    const text = line.trim();
    if (!text) continue;
    const at = text.indexOf(':');
    const name = (at >= 0 ? text.slice(0, at) : text).trim();
    if (!name) continue;
    const cards: string[] = [];
    for (const said of (at >= 0 ? text.slice(at + 1) : '').split(',')) {
      const id = anchorRead(said, known);
      if (!id || taken.has(id)) continue;
      taken.add(id);
      cards.push(id);
    }
    const already = columns.find((column) => column.name.toLowerCase() === name.toLowerCase());
    if (already) already.cards.push(...cards);
    else columns.push({ name, cards });
  }
  return columns;
}

/**
 * An id in a fence read as the anchor it means: the caret a person may write in front of it taken off, and then, for
 * anything that is not an anchor already, upper case down and everything an anchor cannot hold turned into the hyphen
 * it would have been. `Fix Login` is `fix-login`.
 *
 * That second reading is only taken when the note really has an item with that anchor (`known`), so a lane written or
 * dictated by hand still finds its cards, while words after a colon that name nothing are left alone rather than
 * drawn as a card of their own. Read loosely, written back the one way (`writeBoard`), as an item's own anchor is
 * (docs/BOARDS.md). Empty for an id this board cannot use.
 */
function anchorRead(said: string, known: ReadonlySet<string>): string {
  const plain = said.trim().replace(/^\^/, '');
  if (NAMED.test(plain)) return plain;
  const id = plain
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/^[-_]+|[-_]+$/g, '');
  return NAMED.test(id) && known.has(id) ? id : '';
}

/** The columns written back as a fence's body, exactly as a person would type them. */
export function writeBoard(columns: readonly BoardColumn[]): string {
  return columns.map((column) => `${column.name}: ${column.cards.join(', ')}`.replace(/:\s+$/, ':')).join('\n');
}

export interface Board {
  /** The line the opening fence is on, counting from 1. */
  from: number;
  /** The line the closing fence is on; the same as `from` when the fence never closes. */
  to: number;
  /** The fence's body: the lines between. */
  body: string;
  columns: BoardColumn[];
  /** How tall the lanes are set, in ems, or null for the board's own height. */
  height: number | null;
}

/** The lanes' height a fence's settings name, held between the shortest and tallest a board can be; or null. */
function heightOf(settings: string): number | null {
  const found = HEIGHT.exec(settings);
  const value = found ? Number(found[1]) : NaN;
  return Number.isFinite(value) ? clampHeight(value) : null;
}

/** A height kept within what a board can be, to the half em. */
export function clampHeight(ems: number): number {
  return Math.round(Math.min(BOARD_HEIGHT.max, Math.max(BOARD_HEIGHT.min, ems)) * 2) / 2;
}

/**
 * A board's opening fence with its lanes' height set, or taken off with null: the rest of the line - the fence, the
 * word, any other settings - as it was. A line that does not open a board comes back as it is.
 */
export function withBoardHeight(openLine: string, height: number | null): string {
  const open = OPEN.exec(openLine);
  if (!open) return openLine;
  const start = /^\s*(?:`{3,}|~{3,})\s*board/i.exec(openLine)?.[0] ?? `${open[1]}board`;
  const rest = (open[2] ?? '').replace(HEIGHT, ' ').replace(/\s+/g, ' ').trim();
  const settings = [height === null ? '' : `height=${clampHeight(height)}`, rest].filter(Boolean).join(' ');
  return `${start}${settings ? ` ${settings}` : ''}`;
}

/** Every board in the note, in order. */
export function boardsIn(doc: string): Board[] {
  const lines = doc.split('\n');
  const boards: Board[] = [];
  // The note's own anchors, read once and only when a board is found: what a lane's ids are read against.
  let anchors: Set<string> | null = null;
  for (let i = 0; i < lines.length; i += 1) {
    const open = OPEN.exec(lines[i] ?? '');
    if (!open) continue;
    const fence = open[1] ?? '```';
    let end = i;
    for (let j = i + 1; j < lines.length; j += 1) {
      if (new RegExp(`^\\s*${fence[0] === '~' ? '~' : '`'}{${fence.length},}\\s*$`).test(lines[j] ?? '')) {
        end = j;
        break;
      }
    }
    const body = end > i ? lines.slice(i + 1, end).join('\n') : '';
    boards.push({ from: i + 1, to: end + 1, body, columns: readBoard(body, anchors ?? (anchors = new Set(itemsIn(doc).map((item) => item.id)))), height: heightOf(open[2] ?? '') });
    i = end;
  }
  return boards;
}

/** The board `line` is inside, fence lines included, or null. */
export function boardAt(doc: string, line: number): Board | null {
  return boardsIn(doc).find((board) => board.to > board.from && line >= board.from && line <= board.to) ?? null;
}

/**
 * A whole board as words to take away (Matt: "the task management board needs to be copyable but formatting is
 * splitting it up"). Drawn as columns, a board cannot be dragged over and copied a piece at a time, and its fence and
 * its items sit apart in the note anyway. This is both together, in the note's own markdown: the fence, then every
 * item it names in the order the note has them. Pasted into another note it is the same working board; pasted
 * anywhere else it reads as a list under its columns.
 *
 * Null when `line` is not inside a board.
 */
export function boardCopy(doc: string, line: number): string | null {
  const lines = doc.split('\n');
  const board = boardAt(doc, line);
  if (!board) return null;
  const named = new Set(board.columns.flatMap((column) => column.cards));
  const items = itemsIn(doc)
    .filter((item) => named.has(item.id))
    .map((item) => lines[item.line - 1] ?? '');
  const fence = lines.slice(board.from - 1, board.to).join('\n');
  return items.length ? `${fence}\n\n${items.join('\n')}\n` : `${fence}\n`;
}

/** Every line inside a fenced block, counting from 1: what is code and not markdown. */
export function fencedLines(lines: readonly string[]): Set<number> {
  const inside = new Set<number>();
  let fence = '';
  lines.forEach((text, index) => {
    const edge = /^\s*(`{3,}|~{3,})/.exec(text);
    if (fence) {
      inside.add(index + 1);
      if (edge && edge[1]!.startsWith(fence[0]!) && edge[1]!.length >= fence.length && !text.trim().slice(edge[1]!.length).trim()) fence = '';
      return;
    }
    if (edge) {
      fence = edge[1]!;
      inside.add(index + 1);
    }
  });
  return inside;
}
