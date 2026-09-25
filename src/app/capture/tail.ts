/**
 * The live note, laid out for Tail.tsx: the markdown a spoken note is
 * turning into, as lines with their structure read off them.
 *
 * Tail shows the note formatted as it is said - a heading set large, a
 * to-do behind its box, a bullet indented - with the markdown mark that made
 * each line kept, dimmed, in a gutter, so what the spoken cues produce is
 * visible without the note reading as source. Inline `**` around emphasis is
 * kept the same way. The tail whisper is still guessing is marked `pending`.
 * Pure, so it is tested without a screen.
 */

import { BOX, BULLET, NUMBER } from '../core/itemSyntax.ts';

export type LineKind = 'heading' | 'task' | 'bullet' | 'number' | 'quote' | 'para' | 'blank';

export type RunKind = 'text' | 'mark' | 'pending';

export interface Run {
  text: string;
  kind: RunKind;
}

export interface Line {
  kind: LineKind;
  /** The markdown mark at the start of the line (`#`, `- [ ]`, `-`, `1.`, `>`), without its trailing space. */
  mark: string;
  /** Heading depth, 1-6, for headings. */
  level?: number;
  /** The line's text after its mark, as runs. */
  runs: Run[];
  /** Whether the whole line is still a guess. */
  pending: boolean;
}

/**
 * A markdown mark at the start of a line, with its trailing space: a heading, a to-do, a bullet or a numbered step in
 * core/itemSyntax.ts's spelling, a quote.
 */
const LEADING = new RegExp(String.raw`^(?:(#{1,6}) |(${BULLET} ${BOX}) |(${BULLET}) |(${NUMBER}) |(>) )`);

/**
 * Lines for `markdown` from `start` on. `pendingFrom` is an offset into the
 * whole text; everything from it is `pending`, marks included.
 */
export function layout(markdown: string, pendingFrom: number | null, start = 0): Line[] {
  const lines: Line[] = [];
  const pendingAt = pendingFrom === null ? Infinity : pendingFrom;
  let offset = 0;
  for (const text of markdown.split('\n')) {
    const lineStart = offset;
    offset += text.length + 1;
    if (lineStart + text.length < start) continue;
    const visibleFrom = Math.max(0, start - lineStart);

    if (!text.trim()) {
      lines.push({ kind: 'blank', mark: '', runs: [], pending: lineStart >= pendingAt });
      continue;
    }

    const lead = visibleFrom === 0 ? LEADING.exec(text) : null;
    let kind: LineKind = 'para';
    let level: number | undefined;
    let mark = '';
    let cursor = 0;
    if (lead) {
      const [whole, heading, task, bullet, number, quote] = lead;
      mark = whole.trimEnd();
      cursor = whole.length;
      if (heading) {
        kind = 'heading';
        level = heading.length;
      } else if (task) kind = 'task';
      else if (bullet) kind = 'bullet';
      else if (number) kind = 'number';
      else if (quote) kind = 'quote';
    }

    // Runs: inline `**` pairs are marks, the words between them are text, and
    // anything at or past the pending offset is a guess.
    const runs: Run[] = [];
    const push = (from: number, to: number, run: RunKind) => {
      const a = Math.max(from, visibleFrom);
      if (a >= to) return;
      const cut = Math.min(to, Math.max(a, pendingAt - lineStart));
      const add = (s: string, k: RunKind) => {
        if (!s) return;
        const last = runs[runs.length - 1];
        if (last && last.kind === k) last.text += s;
        else runs.push({ text: s, kind: k });
      };
      add(text.slice(a, cut), run);
      add(text.slice(cut, to), 'pending');
    };
    let at = cursor;
    for (const m of text.slice(cursor).matchAll(/\*\*([^*\n]+?)\*\*/g)) {
      const i = cursor + (m.index ?? 0);
      push(at, i, 'text');
      push(i, i + 2, 'mark');
      push(i + 2, i + m[0].length - 2, 'text');
      push(i + m[0].length - 2, i + m[0].length, 'mark');
      at = i + m[0].length;
    }
    push(at, text.length, 'text');

    lines.push({ kind, mark, level, runs, pending: lineStart + cursor >= pendingAt });
  }
  return lines;
}

/**
 * Where the visible tail starts: the last `chars` characters, moved forward to
 * a line boundary so a line's mark is never cut off its text.
 */
export function tailStart(markdown: string, chars: number): number {
  if (markdown.length <= chars) return 0;
  const nl = markdown.indexOf('\n', markdown.length - chars);
  return nl < 0 ? markdown.lastIndexOf('\n') + 1 : nl + 1;
}
