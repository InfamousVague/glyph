import type * as Y from 'yjs';

/** A change made on this device, whether by the editor or by reconciling words written elsewhere in the app. */
export const LOCAL = Symbol('team: from this device');

const isHigh = (unit: number) => unit >= 0xd800 && unit <= 0xdbff;
const isLow = (unit: number) => unit >= 0xdc00 && unit <= 0xdfff;

/** Whether `at` in `words` lies between the two halves of one character: a high surrogate, then its low one. */
const splitsPair = (words: string, at: number) =>
  at > 0 && at < words.length && isHigh(words.charCodeAt(at - 1)) && isLow(words.charCodeAt(at));

/**
 * The lines that differ between `from` and `to`, as one change to `text`: the common head and foot are kept, and
 * what lies between goes and comes. A change made elsewhere in the same stretch at the same moment merges by the
 * CRDT's rule, both sides' words kept.
 *
 * The head and foot are drawn back to whole characters. Two that share a half (😀 and 😁 share their first) would
 * otherwise be changed by the other half alone, and Yjs, cutting the pair, writes U+FFFD in its place for everyone.
 */
export function applyTextDiff(text: Y.Text, from: string, to: string): void {
  let head = 0;
  const most = Math.min(from.length, to.length);
  while (head < most && from[head] === to[head]) head += 1;
  if (splitsPair(from, head) || splitsPair(to, head)) head -= 1;
  let foot = 0;
  while (foot < most - head && from[from.length - 1 - foot] === to[to.length - 1 - foot]) foot += 1;
  if (splitsPair(from, from.length - foot) || splitsPair(to, to.length - foot)) foot -= 1;
  text.doc?.transact(() => {
    const gone = from.length - head - foot;
    if (gone > 0) text.delete(head, gone);
    const came = to.slice(head, to.length - foot);
    if (came) text.insert(head, came);
  }, LOCAL);
}
