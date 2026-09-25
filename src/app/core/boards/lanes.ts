import { similarity } from '../../capture/route.ts';
import { isDoneName, listLead } from '../itemSyntax.ts';
import { doneColumn, putCard } from './columns.ts';
import { boardAt, boardsIn, fencedLines, writeBoard, type Board, type BoardColumn } from './fence.ts';
import { anchorFor, isItemLine, itemOnLine, itemWords, itemsIn, setItemDone, withAnchor } from './items.ts';
import { newCard } from './make.ts';

/**
 * Lanes, by voice: a board's columns found by the name a person says, and a card added to one or moved into one.
 *
 * A lane is weighed the way the recorder weighs a note's name (capture/route.ts `similarity`, and the same bar to
 * clear), so a lane and a note called the same are judged fairly against each other. Moving by voice does what a drag
 * would: the item named if it has no anchor, its box ticked going into Done and cleared coming out.
 */

/**
 * A board's columns as a voice command names them (Matt: "add voice commands and cues for adding to swimlanes on the
 * board"). The recorder reads "Glyph, add call Sam to Doing" and "move fix login to the Done column"
 * (capture/command.ts); these find the lane and make the change, in the note's own markdown.
 */
export interface Lane {
  name: string;
  /** The line the lane's board opens on, counting from 1. */
  board: number;
  /** Which of that board's columns. */
  column: number;
}

/** Every lane of every board in the note, in order. */
export function lanesOf(body: string): Lane[] {
  return boardsIn(body)
    .filter((board) => board.to > board.from)
    .flatMap((board) => board.columns.map((column, index) => ({ name: column.name, board: board.from, column: index })));
}

/** A lane's name as it is said: no "the" in front, and no "lane", "column" or "swimlane" after it. */
function spokenLane(text: string): string {
  return text
    .replace(/[.,;:!?"“”]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/^(?:(?:the|my|our)\s+)+/i, '')
    .replace(/\s+(?:swim\s?lanes?|lanes?|columns?)$/i, '')
    .trim();
}

const FINISHED = /^(?:done|finished|complete|completed)$/i;

/**
 * The lane `spoken` names, and how well, 0 to 1, on the same footing as a note's name (capture/route.ts
 * `similarity`), so the recorder can weigh a lane against a note of the same name. Null when no lane is a clear
 * match: the best must reach 0.72 and beat the next by 0.08, as a note's name must. "Finished" and "complete" find
 * the board's Done lane.
 */
export function matchLane(spoken: string, lanes: readonly Lane[]): { lane: Lane; score: number } | null {
  const said = spokenLane(spoken);
  if (said.length < 2) return null;
  let best: { lane: Lane; score: number } | null = null;
  let second = 0;
  for (const lane of lanes) {
    let score = similarity(said, lane.name);
    if (FINISHED.test(said) && isDoneName(lane.name)) score = Math.max(score, 0.95);
    if (!best || score > best.score) {
      second = best?.score ?? second;
      best = { lane, score };
    } else if (score > second) {
      second = score;
    }
  }
  if (!best || best.score < 0.72) return null;
  if (best.score - second < 0.08 && best.score < 0.99) return null;
  return best;
}

/** The board a lane belongs to in `body` as it is now, or null when that board or column is not there any more. */
function boardOfLane(body: string, lane: Lane): Board | null {
  const board = boardAt(body, lane.board);
  if (!board || board.from !== lane.board) return null;
  const column = board.columns[lane.column];
  return column && column.name === lane.name ? board : null;
}

/** `body` with a board's fence body rewritten: the lines between its two fence lines. */
function withFence(lines: string[], board: Board, columns: readonly BoardColumn[]): void {
  lines.splice(board.from, board.to - board.from - 1, ...writeBoard(columns).split('\n'));
}

/**
 * A new to-do with `words`, on the lane: the line written under the board's last item (make.ts `newCard`)
 * and its card put at the top of the lane. Null for no words, or a lane that is not in `body`.
 */
export function addToLane(body: string, lane: Lane, words: string): { body: string; line: string } | null {
  if (!boardOfLane(body, lane)) return null;
  const made = newCard(body, lane.board, lane.column, words);
  if (!made) return null;
  const lines = body.split('\n');
  // The item first, since it goes in below the board and so moves none of the board's lines.
  lines.splice(Math.min(made.at - 1, lines.length), 0, made.text);
  lines.splice(made.fence.from, made.fence.to - made.fence.from - 1, ...made.fence.body.split('\n'));
  return { body: lines.join('\n'), line: made.text };
}

/** The words worth matching an item on: lower case, letters and digits, three characters or more. */
function tokensOf(text: string): string[] {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .split(' ')
    .filter((token) => token.length >= 3);
}

/**
 * The list item `itemWords` names, moved to the lane: named with an anchor if it has none, its card taken from
 * wherever it was on that board and put at the end of the lane. Moved into the Done lane its box is ticked, and out of
 * it unticked, as a card dragged there would be; `ticked` says which happened, or null when the box was left alone.
 *
 * The item is the note's list item whose words best match - three words in five, as a lost mark is found again
 * (format/links.ts) - anywhere in the note but a block of code. Null when none matches that well, or the lane is not
 * in `body`.
 */
export function moveToLane(
  body: string,
  itemWords: string,
  lane: Lane,
): { body: string; item: { id: string; text: string; line: number }; ticked: boolean | null } | null {
  const board = boardOfLane(body, lane);
  if (!board) return null;
  const wanted = tokensOf(itemWords);
  if (!wanted.length) return null;
  const lines = body.split('\n');
  const inside = fencedLines(lines);
  let best = -1;
  let bestScore = 0;
  lines.forEach((text, index) => {
    if (inside.has(index + 1) || !isItemLine(text)) return;
    const have = new Set(tokensOf(wordsOn(text)));
    const score = wanted.filter((token) => have.has(token)).length / wanted.length;
    if (score > bestScore) {
      bestScore = score;
      best = index;
    }
  });
  if (best < 0 || bestScore < 0.6) return null;

  const original = lines[best] ?? '';
  const already = itemOnLine(original);
  const id = already?.id ?? anchorFor(wordsOn(original), itemsIn(body).map((item) => item.id));
  let line = withAnchor(original, id);
  const columns = putCard(board.columns, id, lane.column);
  const done = doneColumn(columns);
  const box = listLead(line)?.done ?? null;
  let ticked: boolean | null = null;
  if (box !== null && done >= 0) {
    const into = lane.column === done;
    if (into !== box) {
      line = setItemDone(line, into);
      ticked = into;
    }
  }
  lines[best] = line;
  withFence(lines, board, columns);
  return { body: lines.join('\n'), item: { id, text: wordsOn(line), line: best + 1 }, ticked };
}

/** A list item's words, box and anchor off; '' for a line that is not one. */
function wordsOn(line: string): string {
  return itemWords(line) ?? '';
}
