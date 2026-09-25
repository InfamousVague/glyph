/**
 * The hash a kept thing is written against: the home page's gist
 * (format/gist.ts), the AI's marks on a note (ai/marks.ts), and the body a run
 * was written from (format/pipeline.ts `noteHash`).
 *
 * A thing is kept with a hash of the exact body it came from, not the body's
 * time: the editor saves on a debounce, so "the time the body last changed"
 * and "the body the model read" can name different texts inside the same
 * second. A hash of the text itself cannot.
 *
 * Named for what it holds; it was format/formatter.ts.
 */

/**
 * FNV-1a over the UTF-16 code units, folded to 52 bits so it survives JSON and
 * an i64 column unchanged. Not cryptographic: it only has to tell two texts
 * apart, and a collision costs one missing "changed since" hint.
 */
export function bodyHash(text: string): number {
  let hash = 0xcbf29ce484222325n;
  const prime = 0x100000001b3n;
  const mask = 0xffffffffffffffffn;
  for (let i = 0; i < text.length; i += 1) {
    hash ^= BigInt(text.charCodeAt(i));
    hash = (hash * prime) & mask;
  }
  return Number(hash & 0xfffffffffffffn);
}
