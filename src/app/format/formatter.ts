/**
 * The hash a kept text is written against, and the tidy-up of a model's
 * answer at the edges.
 *
 * The hook that watched a mode's text stream into the robot's own view went
 * with that view: the model's lines land in the note itself now
 * (ai/useLanding.ts). What stayed here is what the preparation, the gist and
 * the marks still share.
 *
 * A text is kept with a hash of the exact body it was written from, not the
 * body's time: the editor saves on a debounce, so "the time the body last
 * changed" and "the body the model read" can name different texts inside
 * the same second. A hash of the text itself cannot.
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

/**
 * What a model still gets wrong at the edges: a code fence around the whole
 * note, and blank lines at either end. The words are left alone.
 */
export function tidy(text: string): string {
  let out = text.trim();
  const fenced = /^```[a-z]*\n([\s\S]*?)\n```$/i.exec(out);
  if (fenced?.[1]) out = fenced[1].trim();
  return `${out}\n`;
}
