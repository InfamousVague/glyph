import type * as Y from 'yjs';

/** A change made on this device, whether by the editor or by reconciling words written elsewhere in the app. */
export const LOCAL = Symbol('team: from this device');

/**
 * The lines that differ between `from` and `to`, as one change to `text`: the common head and foot are kept, and
 * what lies between goes and comes. A change made elsewhere in the same stretch at the same moment merges by the
 * CRDT's rule, both sides' words kept.
 */
export function applyTextDiff(text: Y.Text, from: string, to: string): void {
  let head = 0;
  const most = Math.min(from.length, to.length);
  while (head < most && from[head] === to[head]) head += 1;
  let foot = 0;
  while (foot < most - head && from[from.length - 1 - foot] === to[to.length - 1 - foot]) foot += 1;
  text.doc?.transact(() => {
    const gone = from.length - head - foot;
    if (gone > 0) text.delete(head, gone);
    const came = to.slice(head, to.length - foot);
    if (came) text.insert(head, came);
  }, LOCAL);
}
