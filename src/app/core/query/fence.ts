import { clampHeight } from '../boards/fence.ts';
import type { ShowAs } from './read.ts';

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

/** A query line for a clause, however it is spaced: `(indent)(name)(space):(space)(value)`. */
function clauseLine(clause: string): RegExp {
  return new RegExp(`^(\\s*)(${clause})(\\s*):(\\s*)(.*)$`, 'i');
}

/** A clause's value in the body (`from`, `where`, `group`, `show`…), trimmed; null where the clause has no line. */
export function clauseValue(body: string, clause: string): string | null {
  const re = clauseLine(clause);
  for (const line of body.split('\n')) {
    const found = re.exec(line);
    if (found) return (found[5] ?? '').trim();
  }
  return null;
}

/**
 * A query's body with one clause set, removed (null), or added: the first line for the clause has its value replaced
 * with its spacing left as it was, null takes the line out, and a clause with no line gets one at the end. The
 * keyword is written lower case, as docs/QUERIES.md teaches. Pure; this is how the view switcher and the builder change
 * a drawn query without the person learning the grammar (editor/QueryView.tsx, editor/QueryBuilder.tsx).
 */
export function withClause(body: string, clause: string, value: string | null): string {
  const re = clauseLine(clause);
  const next: string[] = [];
  let set = false;
  for (const line of body.split('\n')) {
    const found = set ? null : re.exec(line);
    if (!found) {
      next.push(line);
      continue;
    }
    set = true;
    if (value !== null) next.push(`${found[1]}${clause}${found[3]}:${found[4]}${value}`);
  }
  if (!set && value !== null) next.push(`${clause}: ${value}`);
  return next.join('\n');
}

/** A query's body with `show:` set, for the view switcher: a list becomes a board or a table with from: and where: kept. */
export function withShow(body: string, show: ShowAs): string {
  return withClause(body, 'show', show);
}

/** A query fence with `body` in it, as the + writes one: three backticks, the word, the lines, three backticks. */
export function queryFence(body: string): string {
  return ['```query', body.trimEnd(), '```'].join('\n');
}
