/**
 * Where each ```query fence in a note is, and what it says (docs/QUERIES.md, docs/DESIGN.md §159): the editor draws
 * each as its result (editor/queries.ts), and nothing else in a note is a query. A fence is ```query or ~~~query and
 * nothing more on its line, closed by a fence of the same character at least as long; one never closed is not drawn,
 * since everything after it is still being typed. Found as a diagram's fence is (editor/mermaid.ts `diagramsIn`), so
 * the two never disagree about where a fence ends. Pure.
 */

export interface QueryFence {
  /** The line the opening fence is on, counting from 1. */
  from: number;
  /** The line the closing fence is on. */
  to: number;
  /** The lines between: the query itself. */
  body: string;
}

const OPEN = /^\s*(`{3,}|~{3,})\s*query\s*$/i;

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
    found.push({ from: i + 1, to: end + 1, body: lines.slice(i + 1, end).join('\n') });
    i = end;
  }
  return found;
}

/** A query fence with `body` in it, as the + writes one: three backticks, the word, the lines, three backticks. */
export function queryFence(body: string): string {
  return ['```query', body.trimEnd(), '```'].join('\n');
}
