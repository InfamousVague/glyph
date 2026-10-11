import { setItemDone, settleTicks } from '../boards.ts';
import { taskBox } from '../itemSyntax.ts';

/**
 * A to-do ticked from a query, in a note that is not the one on screen (editor/queries.ts; the open note's own are
 * ticked in its editor, editor/taskToggle.ts `toggleBox`). The same change a tap on its box makes there: the box
 * turned, and every board in that note brought into step with it, the card into Done or back out of it, in the one
 * write (core/boards.ts `settleTicks`), so a board never drifts from a tick made somewhere else.
 *
 * The line is found where the query read it, or, where the note has moved since, by its words as the query read them;
 * a line that is gone, or is no longer a to-do, is left alone (null), rather than the wrong line ticked. Pure.
 */
export function tickedBody(body: string, line: number, source: string, done: boolean): string | null {
  const lines = body.split('\n');
  const at = lines[line] === source ? line : lines.indexOf(source);
  const text = lines[at];
  if (at < 0 || text === undefined || !taskBox(text)) return null;
  if (taskBox(text)!.done === done) return body;
  const settled = settleTicks(body, new Map([[at + 1, done]]));
  lines[at] = setItemDone(text, done);
  // The anchors first, on lines outside every fence, which a fence's new body can then not move.
  for (const joined of settled.lines) lines[joined.number - 1] = `${lines[joined.number - 1] ?? ''} ^${joined.anchor}`;
  // Each fence's lines from the last up, so the line numbers of the ones above still hold.
  for (const fence of [...settled.fences].sort((a, b) => b.from - a.from)) {
    lines.splice(fence.from, fence.to - fence.from - 1, ...fence.body.split('\n'));
  }
  return lines.join('\n');
}
