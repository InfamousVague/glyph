/**
 * How a line the model has finished finds its place in the note: the pure
 * rules behind editor/aiChanges.ts and ai/land.ts.
 *
 * Matt: lines land as they finish, and the note shows what changed as
 * tracked changes - struck words in faint ink, added words tinted. A model
 * rewriting a note writes it top to bottom, and most lines of a tidy-up come
 * back as they were, so the rules are a reader's, not a diff's: each new
 * line is looked for among the next few old lines. Found, the old lines it
 * passed over are what the model dropped; a line that is nearly the same is
 * that line rewritten, and only the words that differ are marked; anything
 * else is a line the model added. The decisions are made once, in order, and
 * never revisited, which is what lets a line land the moment it arrives and
 * stay where it landed.
 */

/** How far ahead an old line is looked for. Past this a match is more likely a coincidence than the same line. */
export const LOOKAHEAD = 8;

export interface Token {
  /** The whitespace before the word. */
  lead: string;
  word: string;
}

/** A line as its words, each with the space before it; trailing whitespace is nobody's. */
export function tokens(line: string): Token[] {
  const out: Token[] = [];
  const re = /(\s*)(\S+)/g;
  for (let m = re.exec(line); m; m = re.exec(line)) out.push({ lead: m[1] ?? '', word: m[2] ?? '' });
  return out;
}

export type Segment = { kind: 'same' | 'added' | 'removed'; text: string };

/** A word for comparing: its case kept (a capital is a change), the punctuation on its end not (a comma is not). */
const sameWord = (a: string, b: string) => a.replace(/[.,;:!?]+$/, '') === b.replace(/[.,;:!?]+$/, '');

/**
 * Two lines, word by word: what stayed, what came, what went. Words are
 * compared with their case, since a rewrite that changes a capital changed a
 * word, and without the punctuation on their end, since a comma added after
 * one is not worth striking the word for. The new line's trailing whitespace
 * rides on its last piece, so the pieces that are not `removed` join back to
 * exactly the new line.
 */
export function wordDiff(oldLine: string, newLine: string): Segment[] {
  const a = tokens(oldLine);
  const b = tokens(newLine);
  const cols = b.length + 1;
  const table = new Uint16Array((a.length + 1) * cols);
  for (let i = a.length - 1; i >= 0; i -= 1) {
    for (let j = b.length - 1; j >= 0; j -= 1) {
      table[i * cols + j] = sameWord(a[i]!.word, b[j]!.word) ? table[(i + 1) * cols + j + 1]! + 1 : Math.max(table[(i + 1) * cols + j]!, table[i * cols + j + 1]!);
    }
  }
  const out: Segment[] = [];
  const push = (kind: Segment['kind'], text: string) => {
    const last = out[out.length - 1];
    if (last && last.kind === kind) last.text += text;
    else out.push({ kind, text });
  };
  let i = 0;
  let j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && sameWord(a[i]!.word, b[j]!.word)) {
      push('same', b[j]!.lead + b[j]!.word);
      i += 1;
      j += 1;
    } else if (j >= b.length || (i < a.length && table[(i + 1) * cols + j]! >= table[i * cols + j + 1]!)) {
      push('removed', a[i]!.lead + a[i]!.word);
      i += 1;
    } else {
      push('added', b[j]!.lead + b[j]!.word);
      j += 1;
    }
  }
  const covered = b.reduce((n, t) => n + t.lead.length + t.word.length, 0);
  const tail = newLine.slice(covered);
  if (tail) {
    const last = [...out].reverse().find((s) => s.kind !== 'removed');
    if (last) last.text += tail;
    else push('added', tail);
  }
  return out;
}

const bare = (word: string) => word.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');

/**
 * Whether a new line is an old line rewritten rather than a different line:
 * half its words or more are the old line's (the words themselves, not their
 * marks or punctuation), and at least two of them - or the one word each
 * line has, for a title made a heading.
 */
export function similar(oldLine: string, newLine: string): boolean {
  const a = new Set(tokens(oldLine).map((t) => bare(t.word)).filter(Boolean));
  const b = new Set(tokens(newLine).map((t) => bare(t.word)).filter(Boolean));
  if (!a.size || !b.size) return false;
  let shared = 0;
  for (const word of b) if (a.has(word)) shared += 1;
  const score = shared / Math.max(a.size, b.size);
  return score >= 0.5 && (shared >= 2 || (a.size === 1 && b.size === 1 && shared === 1));
}

export type Match =
  /** The old line `at` is this line: the lines before it were dropped. */
  | { kind: 'keep'; at: number }
  /** The old line `at` rewritten: the lines before it were dropped, and only the words that differ are marked. */
  | { kind: 'replace'; at: number }
  /** A line the model added. */
  | { kind: 'insert' };

const trimEnd = (line: string) => line.replace(/\s+$/, '');

/**
 * Where a finished line belongs among the old lines still ahead. A blank line
 * is looked for only at the very next line, since blank lines are everywhere
 * and matching one further on would drop the words between for nothing.
 */
export function matchLine(oldLines: readonly string[], line: string): Match {
  const look = Math.min(line.trim() ? LOOKAHEAD : 1, oldLines.length);
  const wanted = trimEnd(line);
  for (let i = 0; i < look; i += 1) if (trimEnd(oldLines[i]!) === wanted) return { kind: 'keep', at: i };
  if (line.trim()) {
    for (let i = 0; i < look; i += 1) if (similar(oldLines[i]!, line)) return { kind: 'replace', at: i };
  }
  return { kind: 'insert' };
}

/** Where a note's front matter ends - the offset after its closing fence's newline - or 0 for a note without one. */
export function frontMatterEnd(body: string): number {
  if (!/^(---|\+\+\+)\s*(\n|$)/.test(body)) return 0;
  const lines = body.split('\n');
  for (let n = 1; n < Math.min(lines.length, 40); n += 1) {
    if (/^(---|\+\+\+)\s*$/.test(lines[n]!)) {
      const end = lines.slice(0, n + 1).join('\n').length;
      return Math.min(body.length, end + 1);
    }
  }
  return 0;
}
