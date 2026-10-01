import { clampHeight } from '../boards/fence.ts';

/**
 * Where each ```query fence in a note is, and what it says (docs/QUERIES.md, docs/DESIGN.md §159): the editor draws
 * each as its result (editor/queries.ts), and nothing else in a note is a query. A fence is ```query or ~~~query and
 * nothing more on its line but its settings (`height=18`, as a board's), closed by a fence of the same character at
 * least as long; one never closed is not drawn, since everything after it is still being typed. Found as a diagram's fence is (editor/mermaid.ts `diagramsIn`), so
 * the two never disagree about where a fence ends. Pure.
 */

export interface QueryFence {
  /** The line the opening fence is on, counting from 1. */
  from: number;
  /** The line the closing fence is on. */
  to: number;
  /** The lines between: the query itself. */
  body: string;
  /** How tall a board's lanes are set, in their own ems; null for the board's own height. */
  height: number | null;
}

/**
 * The fence that opens a query, and its settings: `name=value` words after the word, which any other renderer takes
 * as part of the block's info string. Other words after it are another kind of block.
 */
const OPEN = /^\s*(`{3,}|~{3,})\s*query((?:\s+[a-z]+=\S+)*)\s*$/i;
/**
 * `height=18`: how tall a query drawn as a board is, in its lanes' ems, set by the line under it as a ```board's is
 * (Matt: "The swimlanes are maximum height on the query instead of acting like board view with the split view handle").
 */
const HEIGHT = /(?:^|\s)height=(\d+(?:\.\d+)?)(?:em)?(?=\s|$)/i;

/** Every closed query fence in `doc`, in order. */
export function queryFencesIn(doc: string): QueryFence[] {
  const lines = doc.split('\n');
  const found: QueryFence[] = [];
  for (let i = 0; i < lines.length; i += 1) {
    const open = OPEN.exec(lines[i] ?? '');
    if (!open) continue;
    const fence = open[1] ?? '```';
    const close = new RegExp(`^\\s*${fence[0] === '~' ? '~' : '`'}{${fence.length},}\\s*$`);
    let end = -1;
    for (let j = i + 1; j < lines.length; j += 1) {
      if (close.test(lines[j] ?? '')) {
        end = j;
        break;
      }
    }
    if (end < 0) break;
    const height = Number(HEIGHT.exec(open[2] ?? '')?.[1] ?? NaN);
    found.push({ from: i + 1, to: end + 1, body: lines.slice(i + 1, end).join('\n'), height: Number.isFinite(height) ? clampHeight(height) : null });
    i = end;
  }
  return found;
}

/**
 * A query's opening fence with its board's height set, or taken off with null: the fence, the word and any other
 * settings as they were. A line that does not open a query comes back as it is.
 */
export function withQueryHeight(openLine: string, height: number | null): string {
  const open = OPEN.exec(openLine);
  if (!open) return openLine;
  const start = /^\s*(?:`{3,}|~{3,})\s*query/i.exec(openLine)?.[0] ?? `${open[1]}query`;
  const rest = (open[2] ?? '').replace(HEIGHT, ' ').replace(/\s+/g, ' ').trim();
  const settings = [height === null ? '' : `height=${clampHeight(height)}`, rest].filter(Boolean).join(' ');
  return `${start}${settings ? ` ${settings}` : ''}`;
}

/** A query fence with `body` in it, as the + writes one: three backticks, the word, the lines, three backticks. */
export function queryFence(body: string): string {
  return ['```query', body.trimEnd(), '```'].join('\n');
}
