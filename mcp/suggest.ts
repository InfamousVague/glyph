import { frontMatterEnd } from '../tauri/src/app/core/frontMatter.ts';

/**
 * Suggest mode (docs/CLAUDE_LIVE.md, "Suggest mode"): Claude's change to a note written as CriticMarkup rather than
 * made, so the person keeps or reverts each part in the app (lib/editor/suggestions/) and any other markdown app
 * reads it too:
 *
 * - an insertion `{++new words++}`
 * - a deletion `{--old words--}`
 * - a replacement `{~~old~>new~~}`
 *
 * each followed by `{>>Claude<<}`, the author. The note's lines are matched first, so what both sides share is
 * written as it was; the lines that changed are paired by the words they share and diffed word by word, an inline
 * code span, a link and a blank each one word, and changes with only spaces between are one change, so a sentence
 * reworded reads as one replacement rather than a mark a word.
 *
 * A mark never crosses a line: a line added or taken out whole is marked after its list bullet, task box, heading
 * marks or quote, which are the line's structure and stay outside; a changed bullet or box is written as the new
 * one, its words diffed. What is not prose is written directly, as the change itself, never marked: front matter
 * (the authors line the connector signs with among it), anything inside a fenced block or its fence lines (code, a
 * board, the comments fence), a table's delimiter row, a table row whose cells moved, and the note's title, its
 * first heading, by which links find it. Words that would close a mark early are written directly too.
 *
 * Pure, so the connector's tools (mcp/server.ts update_note and append_to_note) and the tests read it alike.
 */

/** What a suggestion pass wrote: the body with the marks in it, and how many marks. */
export interface Suggested {
  body: string;
  count: number;
}

type Op<T> = { kind: 'same' | 'gone' | 'came'; value: T };

/** Past this many differences a diff gives up matching and answers everything replaced: the trace is D squared. */
const MOST = 2000;

/**
 * Myers' difference of two lists (An O(ND) Difference Algorithm, 1986): the shortest edit script, as runs of the
 * same, gone and came, in order. The shared head and tail are taken off first, which is most of any real edit.
 */
export function diff<T>(a: readonly T[], b: readonly T[]): Op<T>[] {
  let head = 0;
  while (head < a.length && head < b.length && a[head] === b[head]) head += 1;
  let tail = 0;
  while (tail < a.length - head && tail < b.length - head && a[a.length - 1 - tail] === b[b.length - 1 - tail]) tail += 1;
  const x0 = a.slice(head, a.length - tail);
  const y0 = b.slice(head, b.length - tail);
  const ops: Op<T>[] = a.slice(0, head).map((value) => ({ kind: 'same' as const, value }));
  ops.push(...middle(x0, y0));
  ops.push(...a.slice(a.length - tail).map((value) => ({ kind: 'same' as const, value })));
  return ops;
}

function middle<T>(a: readonly T[], b: readonly T[]): Op<T>[] {
  const n = a.length;
  const m = b.length;
  const replaced = (): Op<T>[] => [...a.map((value) => ({ kind: 'gone' as const, value })), ...b.map((value) => ({ kind: 'came' as const, value }))];
  if (!n || !m) return replaced();
  const max = Math.min(n + m, MOST);
  const off = max + 1;
  const v = new Int32Array(2 * max + 3);
  // Each round's furthest reaches, kept to walk back: only the diagonals that round could touch.
  const trace: Int32Array[] = [];
  for (let d = 0; d <= max; d += 1) {
    trace.push(v.slice(off - d - 1, off + d + 2));
    for (let k = -d; k <= d; k += 2) {
      let x = k === -d || (k !== d && v[off + k - 1]! < v[off + k + 1]!) ? v[off + k + 1]! : v[off + k - 1]! + 1;
      let y = x - k;
      while (x < n && y < m && a[x] === b[y]) {
        x += 1;
        y += 1;
      }
      v[off + k] = x;
      if (x >= n && y >= m) return walkBack(a, b, trace);
    }
  }
  return replaced();
}

function walkBack<T>(a: readonly T[], b: readonly T[], trace: readonly Int32Array[]): Op<T>[] {
  const ops: Op<T>[] = [];
  let x = a.length;
  let y = b.length;
  for (let d = trace.length - 1; d >= 0; d -= 1) {
    const row = trace[d]!;
    // `row` holds diagonals -d-1 to d+1.
    const at = (k: number) => row[k + d + 1]!;
    const k = x - y;
    const prevK = k === -d || (k !== d && at(k - 1) < at(k + 1)) ? k + 1 : k - 1;
    const prevX = at(prevK);
    const prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      ops.push({ kind: 'same', value: a[x - 1]! });
      x -= 1;
      y -= 1;
    }
    if (d > 0) {
      if (x === prevX) ops.push({ kind: 'came', value: b[y - 1]! });
      else ops.push({ kind: 'gone', value: a[x - 1]! });
    }
    x = prevX;
    y = prevY;
  }
  return ops.reverse();
}

const FENCE = /^\s{0,3}(`{3,}|~{3,})/;
const TABLE_RULE = /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/;

/**
 * Which of a body's lines are not prose, counting from 0: its front matter, every fenced block with its fence lines
 * (one never closed runs to the end, as CommonMark has it), a table's delimiter row, and the title heading.
 */
export function structureLines(lines: readonly string[]): boolean[] {
  const fixed = lines.map(() => false);
  const top = frontMatterEnd(lines);
  for (let i = 0; i < top; i += 1) fixed[i] = true;
  for (let i = top; i < lines.length; i += 1) {
    const open = FENCE.exec(lines[i] ?? '');
    if (open) {
      const mark = open[1]!;
      const close = new RegExp(`^\\s{0,3}${mark[0] === '~' ? '~' : '`'}{${mark.length},}\\s*$`);
      let j = i + 1;
      while (j < lines.length && !close.test(lines[j] ?? '')) j += 1;
      for (let n = i; n <= Math.min(j, lines.length - 1); n += 1) fixed[n] = true;
      i = j;
      continue;
    }
    if (TABLE_RULE.test(lines[i] ?? '') && (lines[i] ?? '').includes('|')) fixed[i] = true;
  }
  const title = lines.findIndex((line, i) => i >= top && line.trim());
  if (title >= 0 && /^\s{0,3}#{1,6}\s/.test(lines[title]!) && !fixed[title]) fixed[title] = true;
  return fixed;
}

/** A line's structure: its indent, quote marks, bullet or number with a task box, or heading marks. */
const LEAD = /^\s*(?:>\s?)*\s*(?:(?:[-*+]|\d{1,9}[.)])\s+(?:\[[ xX-]\]\s+)?|#{1,6}\s+)?/;

function leadOf(line: string): string {
  return LEAD.exec(line)?.[0] ?? '';
}

/** A line's words as the diff counts them: a link, a note link, a code span or a blank is one word. */
const WORD = /!?\[[^\]\n]*\]\([^)\n]*\)|\[\[[^\]\n]*\]\]|`[^`\n]*`|\{\?[^}\n]*\}|\s+|[^\s`[]+|./g;

export function wordsOf(text: string): string[] {
  return text.match(WORD) ?? [];
}

/** Whether a stretch of text can sit inside a mark without closing it early. */
const markable = (text: string) => !/\+\+\}|--\}|~~\}|~>|<<\}|\{>>/.test(text);

/** The marks a stretch of words writes, the author after each. */
class Marker {
  count = 0;
  private readonly note: string;
  constructor(name: string) {
    this.note = `{>>${name.replace(/<<\}/g, '').replace(/\s+/g, ' ').trim() || 'Claude'}<<}`;
  }
  /** `old` becoming `now`, either empty. */
  mark(old: string, now: string): string {
    if (old === now) return now;
    if (!markable(old) || !markable(now)) return now;
    this.count += 1;
    if (!old) return `{++${now}++}${this.note}`;
    if (!now) return `{--${old}--}${this.note}`;
    return `{~~${old}~>${now}~~}${this.note}`;
  }
}

/**
 * The words of one line changed into another's, marked: the runs the two share written as they are, each change
 * between marked, and changes with only spaces between them made one.
 */
function markWords(old: string, now: string, marker: Marker): string {
  const ops = diff(wordsOf(old), wordsOf(now));
  // Runs: what is the same, and each change as what went and what came.
  type Run = { same: string } | { gone: string; came: string };
  const runs: Run[] = [];
  for (const op of ops) {
    const last = runs[runs.length - 1];
    if (op.kind === 'same') {
      if (last && 'same' in last) last.same += op.value;
      else runs.push({ same: op.value });
    } else {
      const change = last && !('same' in last) ? last : (runs.push({ gone: '', came: '' }), runs[runs.length - 1] as { gone: string; came: string });
      if (op.kind === 'gone') change.gone += op.value;
      else change.came += op.value;
    }
  }
  // Two changes with only spaces between: one change, the spaces on both sides of it.
  for (let i = 1; i < runs.length - 1; i += 1) {
    const run = runs[i]!;
    const before = runs[i - 1]!;
    const after = runs[i + 1]!;
    if ('same' in run && !run.same.trim() && !('same' in before) && !('same' in after)) {
      before.gone += run.same + after.gone;
      before.came += run.same + after.came;
      runs.splice(i, 2);
      i -= 1;
    }
  }
  let out = '';
  for (const run of runs) {
    if ('same' in run) out += run.same;
    // Only spaces changed: written as the new line has them. Otherwise the spaces at a change's edge go inside its
    // mark, so keeping it or reverting it leaves the words spaced as one side had them.
    else if (!run.gone.trim() && !run.came.trim()) out += run.came;
    // Spaces become words, or words spaces: an insertion or a deletion, not a replacement of a space.
    else if (!run.gone.trim()) out += marker.mark('', run.came);
    else if (!run.came.trim()) out += marker.mark(run.gone, '');
    else out += marker.mark(run.gone, run.came);
  }
  return out;
}

/** A line added or taken out whole, marked after its structure. */
function markLine(line: string, gone: boolean, marker: Marker): string {
  const lead = leadOf(line);
  const words = line.slice(lead.length);
  const trail = /\s*$/.exec(words)![0];
  const core = words.slice(0, words.length - trail.length);
  if (!core) return line;
  return lead + (gone ? marker.mark(core, '') : marker.mark('', core)) + trail;
}

/** One line changed into another: its structure as the new line has it, its words diffed. */
function markChanged(old: string, now: string, marker: Marker): string {
  const oldLead = leadOf(old);
  const nowLead = leadOf(now);
  const before = marker.count;
  const words = markWords(old.slice(oldLead.length), now.slice(nowLead.length), marker);
  // A table row is cells: a change that moved a pipe would break the row, so the row is written as it now is.
  if (now.trim().startsWith('|') && hasPipeChange(old.slice(oldLead.length), now.slice(nowLead.length))) {
    marker.count = before;
    return now;
  }
  return nowLead + words;
}

function hasPipeChange(old: string, now: string): boolean {
  return diff(wordsOf(old), wordsOf(now)).some((op) => op.kind !== 'same' && op.value.includes('|'));
}

/** How alike two lines' words are, 0 to 1: the share of words they have in common. */
function likeness(a: string, b: string): number {
  const wa = a.toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? [];
  const wb = b.toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? [];
  if (!wa.length || !wb.length) return 0;
  const counts = new Map<string, number>();
  for (const w of wa) counts.set(w, (counts.get(w) ?? 0) + 1);
  let shared = 0;
  for (const w of wb) {
    const left = counts.get(w) ?? 0;
    if (left > 0) {
      shared += 1;
      counts.set(w, left - 1);
    }
  }
  return (2 * shared) / (wa.length + wb.length);
}

/** Below this, two lines are one taken out and another put in, not one changed. */
const ALIKE = 0.34;

/**
 * Which of the lines that went became which of those that came: the pairing in order that shares the most words,
 * each pair alike enough (a small alignment, as Needleman and Wunsch's), and a line for a line always. Unpaired lines
 * went or came whole. In order:
 * `[old, new]`, `[old, null]` or `[null, new]`.
 */
function pairLines(gone: readonly string[], came: readonly string[]): [string | null, string | null][] {
  const n = gone.length;
  const m = came.length;
  // One line for one: that line changed, however much.
  if (n === 1 && m === 1) return [[gone[0]!, came[0]!]];
  if (n * m > 40_000) {
    // Too many to weigh: paired in order, the rest whole.
    const out: [string | null, string | null][] = [];
    for (let i = 0; i < Math.max(n, m); i += 1) out.push([gone[i] ?? null, came[i] ?? null]);
    return out;
  }
  const score = Array.from({ length: n + 1 }, () => new Float64Array(m + 1));
  const like = (i: number, j: number) => {
    const s = likeness(gone[i]!, came[j]!);
    return s >= ALIKE ? s : -1;
  };
  for (let i = n - 1; i >= 0; i -= 1) {
    for (let j = m - 1; j >= 0; j -= 1) {
      const s = like(i, j);
      score[i]![j] = Math.max(score[i + 1]![j]!, score[i]![j + 1]!, s >= 0 ? s + score[i + 1]![j + 1]! : -Infinity);
    }
  }
  const out: [string | null, string | null][] = [];
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    const s = like(i, j);
    if (s >= 0 && score[i]![j] === s + score[i + 1]![j + 1]!) {
      out.push([gone[i]!, came[j]!]);
      i += 1;
      j += 1;
    } else if (score[i]![j] === score[i + 1]![j]) {
      out.push([gone[i]!, null]);
      i += 1;
    } else {
      out.push([null, came[j]!]);
      j += 1;
    }
  }
  for (; i < n; i += 1) out.push([gone[i]!, null]);
  for (; j < m; j += 1) out.push([null, came[j]!]);
  return out;
}

/**
 * `after` written as suggestions against `before`: what changed between them in CriticMarkup, each mark signed with
 * `name`, and what is not prose written as `after` has it. The same bodies answer `after` with no marks.
 */
export function suggestBody(before: string, after: string, name: string): Suggested {
  if (before === after) return { body: after, count: 0 };
  const a = before.split('\n');
  const b = after.split('\n');
  const fixedA = structureLines(a);
  const fixedB = structureLines(b);
  const lineOps = lineDiff(a, b);
  const marker = new Marker(name);
  const out: string[] = [];
  let gone: number[] = [];
  let came: number[] = [];
  const flush = () => {
    if (!gone.length && !came.length) return;
    if (gone.some((i) => fixedA[i]) || came.some((j) => fixedB[j])) {
      // Structure: written as the change itself.
      out.push(...came.map((j) => b[j]!));
    } else {
      for (const [old, now] of pairLines(
        gone.map((i) => a[i]!),
        came.map((j) => b[j]!),
      )) {
        if (old !== null && now !== null) out.push(markChanged(old, now, marker));
        // A blank line that went stays, so the paragraphs either side stay apart until the person keeps the change.
        else if (old !== null) out.push(old.trim() ? markLine(old, true, marker) : old);
        else out.push(now!.trim() ? markLine(now!, false, marker) : now!);
      }
    }
    gone = [];
    came = [];
  };
  for (const op of lineOps) {
    if (op.kind === 'same') {
      flush();
      out.push(b[op.j]!);
    } else if (op.kind === 'gone') gone.push(op.i);
    else came.push(op.j);
  }
  flush();
  return { body: out.join('\n'), count: marker.count };
}

/** The lines' diff with each line's place on its side. */
function lineDiff(a: readonly string[], b: readonly string[]): ({ kind: 'same'; i: number; j: number } | { kind: 'gone'; i: number } | { kind: 'came'; j: number })[] {
  const out: ({ kind: 'same'; i: number; j: number } | { kind: 'gone'; i: number } | { kind: 'came'; j: number })[] = [];
  let i = 0;
  let j = 0;
  for (const op of diff(a, b)) {
    if (op.kind === 'same') out.push({ kind: 'same', i: i++, j: j++ });
    else if (op.kind === 'gone') out.push({ kind: 'gone', i: i++ });
    else out.push({ kind: 'came', j: j++ });
  }
  return out;
}
