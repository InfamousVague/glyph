import { frontMatterEnd } from '../core/frontMatter.ts';
import { noteTitle, withoutFrontMatter } from '../core/noteTitle.ts';

/**
 * The summary section a note carries in its body, as the page reads and writes it (docs/DESIGN.md §127 section 2).
 * Pure: every rule here is a test.
 *
 * Matt: "add summaries to them, I'm going to start recording meetings and stuff and letting the audio be transcribed
 * then summarized by AI so I get summarized recording notes automatically". The summary is words in the body, under
 * the title, so it syncs, shares, is in the `.md` file and in To do. It has a SHAPE THE PAGE OWNS (`shapeSummary`):
 * the heading `## Summary`, one prose line, then only item lines, with blanks between groups. That shape is how the
 * section is found again (`summarySection`), by its shape and not by any marker: from the heading through the one
 * prose line and every following blank or item line, ending at the first line that is none of those, or a heading,
 * or a rule, or the end. A dictated note's paragraphs end it at their first line; a meeting's `## Transcript` ends
 * it too.
 *
 * Its PLACE (`summaryPlace`) is after the front matter and after the first line of words, whatever its marks: never
 * above them, since `noteTitle` takes the first line and `## Summary` on top would title every card, tab and toast
 * "Summary".
 *
 * Two writers place and shape it, the queue for a closed note (`withSummary`, here) and the editor for an open one
 * (ai/start.ts, through the lander), so the rules live here once. `withoutSummary` is the note with the app's own
 * section taken off, for the better words' compare (capture/refine.ts) and a sync merge that must not see the
 * section as an edit. `carryTicked` keeps every `- [x]` line of an old section in the new one, so a to-do he ticked
 * never comes back open in To do, however the model rephrases. `summaryLine` is the prose line, for the shelf, the
 * toast and the notification. `transcriptPieces` cuts a long transcript for the pieces pass.
 */

/** The heading the section is known by. */
export const SUMMARY_HEADING = '## Summary';

/** A line of the section past the heading and the prose line: an item, a to-do, or a ticked to-do. */
const ITEM = /^\s*-\s+(?:\[[ xX]\]\s+)?\S/;
/** A bullet the model wrote with another mark: made a dash. */
const OTHER_BULLET = /^(\s*)[*+]\s+/;
/** A to-do that has been ticked. */
const TICKED = /^\s*-\s+\[[xX]\]\s+/;
/** A to-do, ticked or not. */
const TODO = /^\s*-\s+\[[ xX]\]\s+/;
/** A heading of any level. */
const HEADING = /^#{1,6}\s+/;
/** A horizontal rule. */
const RULE = /^(?:-{3,}|\*{3,}|_{3,})\s*$/;
/** A picture on a line of its own, which the title steps over. */
const PICTURE = /^!\[[^\]]*\]\([^)]*\)\s*$/;
/** A code fence, which the model sometimes puts round its answer. */
const FENCE = /^```/;
/** A mark still under the pen as the model streams: a heading's hashes, an item's dash, a box not yet closed. */
const UNDER_PEN = /^(?:#{1,6}|-|-\s+\[[ xX]?\]?)\s*$/;

/** A transcript up to this many characters goes to the model in one pass. */
export const ONE_PASS_CHARS = 20_000;
/** About how many characters a piece of a longer transcript holds: about 3,000 tokens. */
export const PIECE_CHARS = 12_000;

// ---- the shape -------------------------------------------------------------------------------

export interface ShapedSummary {
  /** The model's `# heading`, for a note still wearing its date title; null when it gave none. */
  title: string | null;
  /** The section, in its shape: the heading, the prose line, the items. Empty when the model gave nothing to keep. */
  section: string;
}

/**
 * The model's answer as the section the page writes: `## Summary`, one prose line, then only item lines, blanks
 * collapsed to one between groups. The model's `# heading` first line is taken for the title and never written into
 * the section; a second prose line, a heading, a rule and a closing remark are dropped. Works on the answer so far as
 * well as the finished one, so a run's lines only ever grow as it streams (ai/runs.ts `restore`).
 */
export function shapeSummary(modelText: string): ShapedSummary {
  let title: string | null = null;
  let prose: string | null = null;
  const items: string[] = [];
  let seenItem = false;
  for (const raw of modelText.split('\n')) {
    const line = raw.trimEnd().replace(OTHER_BULLET, '$1- ');
    const bare = line.trim();
    if (!bare) {
      // A blank between groups, once; none before the first item.
      if (items.length && items[items.length - 1] !== '') items.push('');
      continue;
    }
    if (FENCE.test(bare) || UNDER_PEN.test(bare)) continue;
    if (ITEM.test(line)) {
      items.push(bare);
      seenItem = true;
      continue;
    }
    if (HEADING.test(bare)) {
      const words = bare.replace(HEADING, '').trim();
      // The first heading names the recording; the section's own heading, echoed, is not a title.
      if (title === null && prose === null && !seenItem && words && words.toLowerCase() !== 'summary') title = words;
      continue;
    }
    if (RULE.test(bare)) continue;
    // The one prose line, before any item; every other line of prose is dropped.
    if (prose === null && !seenItem) prose = bare.replace(/^\*\*summary\*\*:?\s*/i, '').replace(/^summary:\s*/i, '');
  }
  while (items.length && items[items.length - 1] === '') items.pop();
  if (prose === null && !items.length) return { title, section: '' };
  const lines = [SUMMARY_HEADING, ...(prose !== null ? [prose] : []), ...(items.length ? ['', ...items] : [])];
  return { title, section: lines.join('\n') };
}

// ---- finding it -----------------------------------------------------------------------------

export interface SummarySpan {
  /** The offset of `## Summary` in the body. */
  start: number;
  /** The offset after the section's last line, before its newline. */
  end: number;
  /** The section's lines, joined: what `withSummary` compares against what it kept. */
  text: string;
}

/** Whether a line is the section's heading. */
const isHeading = (line: string) => line.trim() === SUMMARY_HEADING;

/**
 * The section's lines from the heading at `at`: the heading, then the one prose line if it comes before any item,
 * then every blank or item line, up to the first line that is none of those, a heading, a rule, or the end. Trailing
 * blanks are not the section's. Answers how many lines it takes.
 */
function sectionLength(lines: readonly string[], at: number): number {
  let n = at + 1;
  let prosePending = true;
  let last = at;
  while (n < lines.length) {
    const line = lines[n]!;
    const bare = line.trim();
    if (!bare) {
      n += 1;
      continue;
    }
    if (HEADING.test(bare) || RULE.test(bare)) break;
    if (ITEM.test(line)) {
      prosePending = false;
      last = n;
      n += 1;
      continue;
    }
    if (prosePending) {
      prosePending = false;
      last = n;
      n += 1;
      continue;
    }
    break;
  }
  return last - at + 1;
}

/** The lines the section takes, as [first line, count], or null without one. Front matter is never searched. */
function findSection(lines: readonly string[]): [number, number] | null {
  const from = frontMatterEnd(lines);
  for (let n = from; n < lines.length; n += 1) {
    if (isHeading(lines[n]!)) return [n, sectionLength(lines, n)];
  }
  return null;
}

/** Where line `n` starts in a body split into `lines`. */
function offsetOfLine(lines: readonly string[], n: number): number {
  let at = 0;
  for (let i = 0; i < n; i += 1) at += lines[i]!.length + 1;
  return at;
}

/** The section in `body`, found by its shape, or null. */
export function summarySection(body: string): SummarySpan | null {
  const lines = body.split('\n');
  const found = findSection(lines);
  if (!found) return null;
  const [first, count] = found;
  const start = offsetOfLine(lines, first);
  const text = lines.slice(first, first + count).join('\n');
  return { start, end: start + text.length, text };
}

/** The summary's first prose line, under `## Summary`, for the shelf, the toast and the notification; null without one. */
export function summaryLine(body: string): string | null {
  const section = summarySection(body);
  if (!section) return null;
  const second = section.text.split('\n')[1] ?? '';
  const bare = second.trim();
  if (!bare || ITEM.test(second)) return null;
  return bare;
}

// ---- its place ------------------------------------------------------------------------------

/**
 * Where a fresh section goes, as the index of the line it starts on: after the front matter and after the first line
 * of words, whatever its marks. After a `# title` line; after a plain first paragraph, through its last line; after
 * a to-do first line and the list it opens; a picture first line is stepped over, as `noteTitle` steps over it. A
 * body with no words at all puts it at the end.
 */
function placeLine(lines: readonly string[]): number {
  let n = frontMatterEnd(lines);
  // Blank lines and pictures before the first words.
  while (n < lines.length && (!lines[n]!.trim() || PICTURE.test(lines[n]!))) n += 1;
  if (n >= lines.length) return lines.length;
  if (HEADING.test(lines[n]!.trim())) return n + 1;
  // A paragraph, or a list: through its last line.
  while (n < lines.length && lines[n]!.trim() && !PICTURE.test(lines[n]!)) n += 1;
  return n;
}

/** The offset a fresh section is written at: the start of the line after the first line of words. */
export function summaryPlace(body: string): number {
  const lines = body.split('\n');
  const n = placeLine(lines);
  return n >= lines.length ? body.length : offsetOfLine(lines, n);
}

// ---- writing it -----------------------------------------------------------------------------

/**
 * The body with the section written: over the one it has, or fresh at its place with a blank line either side. With
 * `title`, a note still wearing its date title (`dateTitled`) takes the model's heading as its first line.
 */
export function withSummary(body: string, section: string, { title = null }: { title?: string | null } = {}): string {
  const lines = body.split('\n');
  const found = findSection(lines);
  let out: string[];
  if (lines.every((l) => !l.trim())) out = section.split('\n');
  else if (found) {
    const [first, count] = found;
    out = [...lines.slice(0, first), ...section.split('\n'), ...lines.slice(first + count)];
  } else {
    const n = placeLine(lines);
    const before = n > 0 && lines[n - 1]!.trim() !== '' ? [''] : [];
    const after = n < lines.length && lines[n]!.trim() !== '' ? [''] : [];
    out = [...lines.slice(0, n), ...before, ...section.split('\n'), ...after, ...lines.slice(n)];
  }
  return title ? retitled(out.join('\n'), title) : out.join('\n');
}

/** The body with the app's section taken off, and the blank line that went with it. */
export function withoutSummary(body: string): string {
  const lines = body.split('\n');
  const found = findSection(lines);
  if (!found) return body;
  const [first, count] = found;
  const rest = [...lines.slice(0, first), ...lines.slice(first + count)];
  // The blank that separated the section from what follows is one blank too many now.
  if (first > 0 && first < rest.length && rest[first]!.trim() === '' && rest[first - 1]!.trim() === '') rest.splice(first, 1);
  else if (first === rest.length && first > 0 && rest[first - 1]!.trim() === '') rest.pop();
  return rest.join('\n');
}

/**
 * The new section with every ticked to-do of the old one carried in verbatim, after the new to-dos: a to-do he ticked
 * does not come back open, however the model rephrases it. Un-ticked old to-dos are not carried: the new list is the
 * new list. A ticked line the new section already has is not doubled.
 */
export function carryTicked(old: string, next: string): string {
  const nextLines = next.split('\n');
  const have = new Set(nextLines.map((l) => l.trim()));
  const ticked = old
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => TICKED.test(l) && !have.has(l));
  if (!ticked.length) return next;
  let at = -1;
  for (let n = 0; n < nextLines.length; n += 1) if (TODO.test(nextLines[n]!)) at = n;
  if (at >= 0) nextLines.splice(at + 1, 0, ...ticked);
  else nextLines.push('', ...ticked);
  return nextLines.join('\n');
}

// ---- the title -----------------------------------------------------------------------------

/** A meeting's title as it is made: "Meeting, 26 Sep 14:05", the day and the month in the device's own order. */
const DATE_TITLE = /^Meeting, (?:\d{1,2} [A-Za-z]{3,}\.?|[A-Za-z]{3,}\.? \d{1,2}) \d{1,2}:\d{2}$/;

/** Whether the note's title is still the date title a meeting is made with (§127 section 3). */
export function dateTitled(body: string): boolean {
  return DATE_TITLE.test(noteTitle(body));
}

/** The body with the model's heading as its title, only while it still wears its date title; else as it was. */
export function retitled(body: string, title: string): string {
  if (!title || !dateTitled(body)) return body;
  const lines = body.split('\n');
  const at = firstWordsLine(lines);
  if (at === null) return body;
  lines[at] = `# ${title}`;
  return lines.join('\n');
}

/** The index of the first line of words in `lines`, past the front matter and any picture; null with none. */
function firstWordsLine(lines: readonly string[]): number | null {
  const words = withoutFrontMatter(lines);
  const skipped = lines.length - words.length;
  for (let n = 0; n < words.length; n += 1) {
    const line = words[n]!;
    if (line.trim() && !PICTURE.test(line)) return n + skipped;
  }
  return null;
}

// ---- long recordings ----------------------------------------------------------------------

/** A sentence's end, for cutting a paragraph that is longer than a piece. */
const SENTENCE_END = /(?<=[.!?]["”’)]?)\s+/;

/**
 * The transcript in pieces of about `size` characters, cut at paragraph breaks; a paragraph longer than a piece is
 * cut at sentence ends. Up to `ONE_PASS_CHARS` goes in one piece. Nothing is dropped: the pieces joined by paragraph
 * breaks are the transcript's paragraphs again.
 */
export function transcriptPieces(plain: string, size = PIECE_CHARS): string[] {
  const text = plain.trim();
  if (!text) return [];
  if (text.length <= ONE_PASS_CHARS) return [text];
  const units = text
    .split(/\n\s*\n/)
    .map((p) => p.trim())
    .filter(Boolean)
    .flatMap((paragraph) => (paragraph.length <= size ? [paragraph] : sentencesUnder(paragraph, size)));
  const pieces: string[] = [];
  let piece = '';
  for (const unit of units) {
    if (piece && piece.length + 2 + unit.length > size) {
      pieces.push(piece);
      piece = unit;
    } else piece = piece ? `${piece}\n\n${unit}` : unit;
  }
  if (piece) pieces.push(piece);
  return pieces;
}

/** A long paragraph as runs of sentences each under `size`, a sentence longer than that cut where it must be. */
function sentencesUnder(paragraph: string, size: number): string[] {
  const out: string[] = [];
  let run = '';
  for (const sentence of paragraph.split(SENTENCE_END)) {
    const parts: string[] = [];
    for (let at = 0; at < sentence.length; at += size) parts.push(sentence.slice(at, at + size));
    for (const part of parts) {
      if (run && run.length + 1 + part.length > size) {
        out.push(run);
        run = part;
      } else run = run ? `${run} ${part}` : part;
    }
  }
  if (run) out.push(run);
  return out;
}
