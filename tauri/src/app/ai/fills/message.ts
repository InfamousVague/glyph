import { type Blank, blanksIn, fillsIn } from '../../core/blanks.ts';
import { frontMatterEnd } from '../../core/frontMatter.ts';
import { listLead } from '../../core/itemSyntax.ts';
import { FILL_ANSWER, FILL_CELL, FILL_CORE, FILL_ITEMS, FILL_NUMBER, FILL_PROMPT, FILL_PROMPT_TOKENS, FILL_SUMMARY, FILL_TITLE, FILL_TRANSLATE, type Rung } from './prompts.ts';
import { budgetOf, hintFor, type Shape, type ShapeInfo, titleLineIndex } from './shape.ts';

/**
 * What the model reads for a fill, and how a press is split into generations (docs/DESIGN.md §145, 5.2 to 5.5). Pure,
 * and pinned by a fixture the page's tests and the Rust bar both read (src/app/ai/fills.fixture.json), so what the Mac
 * measures is what the phone sends.
 *
 * Smaller is faster on the phone, and reading the note is most of a fill's time, so a fill reads the note's title and
 * the part its blank needs: its section, a cell's header and its own row (probe C: with only those, the Year of The
 * Remains of the Day came back right, and with another row under it, wrong), a list and the line above it, a title's
 * first two thousand characters. Other blanks are `___`, worked-out ones their answers, earlier fills their words, and
 * links their words, so the only `{?` in the message are the numbered ones. The front matter, other notes and the
 * plugins' context are never read, so "from this note" means this note.
 *
 * Today's date is the first line, in fixed English: the probes whose examples the prompt carries ran with it, and a
 * phone in German still sends the string the Rust bar measured. The model is never trusted with it: dates are code's.
 */

/** One thing a generation asks: a blank, or a filled answer asked again, and its shape. */
export interface Ask {
  /** Its span in the note: the blank's braces, or the whole filled mark for Ask again. */
  blank: Blank;
  info: ShapeInfo;
  /** Asked again: the old answer's words, written back as the question with `It is not: …` (7.2). */
  again?: { words: string };
}

export interface Built {
  system: string;
  prompt: string;
  maxTokens: number;
  /** The numbers each ask is written with, in the asks' order: several for an items blank, one a new item. */
  numbers: number[][];
}

/** The most one generation may write, and the most it may read and write together: three quarters of the 8,192 window. */
export const ROOM = { output: 512, window: 6144 };

/**
 * The least a generation is given, whatever its blanks' budgets add up to. The engine makes a window of the prompt, the
 * budget and 16 more, rounded up to 512, and refuses a prompt with under 64 tokens of it left (src-tauri/src/llm/
 * generate.rs `window`): measured on the Mac, a one-blank fill of 969 prompt tokens and 35 to write was refused as too
 * long for a 1,024 window. With 48 the window always has the 64. The model stops when it has answered, so the floor
 * costs nothing.
 */
export const LEAST_BUDGET = 48;

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/** "Monday 28 September 2026" on every phone, from two fixed lists of English names. */
export function modelDay(date: Date): string {
  return `${WEEKDAYS[date.getDay()]} ${date.getDate()} ${MONTHS[date.getMonth()]} ${date.getFullYear()}`;
}

/**
 * Tokens, estimated on the high side by script: Latin letters, digits and punctuation one for every four characters,
 * Han, kana and Hangul one each, any other script one for every two. Twelve Japanese scopes would otherwise pass the
 * window that twelve English ones fit.
 */
export function estimateTokens(text: string): number {
  let latin = 0;
  let cjk = 0;
  let other = 0;
  for (const ch of text) {
    if (/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u.test(ch)) cjk += 1;
    else if (/[\p{Script=Latin}\p{N}\p{P}\p{S}\s]/u.test(ch) || ch.charCodeAt(0) < 128) latin += 1;
    else other += 1;
  }
  return Math.ceil(latin / 4) + cjk + Math.ceil(other / 2);
}

// ---- the scope ------------------------------------------------------------------------------------------------

const HEADING = /^\s*(#{1,6})\s/;
const isHeading = (line: string) => HEADING.test(line);
const levelOf = (line: string) => HEADING.exec(line)?.[1]?.length ?? 7;
/** A line the model is never shown: a picture, a place, a film. */
const DRAWN = /^\s*(?:!\[[^\]]*\]\([^)]*\)|\[[^\]]*\]\(geo:[^)]*\)|\[!\[[^\]]*\]\([^)]*\)\]\([^)]*\))\s*$/;

/** The line index each offset of the text is on. */
function lineIndexAt(text: string, offset: number): number {
  return text.slice(0, offset).split('\n').length - 1;
}

/** The headings above a line, nearest first and each a level higher than the last: the section's chain. */
function headingsAbove(lines: readonly string[], index: number, start: number): number[] {
  const chain: number[] = [];
  let level = 7;
  for (let at = index - 1; at >= start; at -= 1) {
    if (isHeading(lines[at]!) && levelOf(lines[at]!) < level) {
      chain.push(at);
      level = levelOf(lines[at]!);
      if (level === 1) break;
    }
  }
  return chain;
}

/** Lines around `index` within a span, up to `before` characters above it and `after` below, cut at line ends. */
function around(lines: readonly string[], index: number, from: number, to: number, before: number, after: number): number[] {
  const out = [index];
  let used = 0;
  for (let at = index - 1; at >= from; at -= 1) {
    used += lines[at]!.length + 1;
    if (used > before) break;
    out.push(at);
  }
  used = 0;
  for (let at = index + 1; at < to; at += 1) {
    used += lines[at]!.length + 1;
    if (used > after) break;
    out.push(at);
  }
  return out;
}

/** The lines a blank's shape reads (5.2), `tight` cutting it again for a blank that will not fit alone. */
function scopeOf(lines: readonly string[], index: number, info: ShapeInfo, start: number, tight: 0 | 1 | 2): number[] {
  if (tight === 2) return [index];
  const sectionStart = (() => {
    for (let at = index; at >= start; at -= 1) if (isHeading(lines[at]!)) return at;
    return start;
  })();
  const level = isHeading(lines[sectionStart]!) ? levelOf(lines[sectionStart]!) : 0;
  let sectionEnd = lines.length;
  for (let at = index + 1; at < lines.length; at += 1) {
    if (isHeading(lines[at]!) && levelOf(lines[at]!) <= level) {
      sectionEnd = at;
      break;
    }
    if (!level && isHeading(lines[at]!)) {
      sectionEnd = at;
      break;
    }
  }
  const section = (before: number, after: number) => {
    const size = lines.slice(sectionStart, sectionEnd).join('\n').length;
    if (size <= before + after && !tight) return Array.from({ length: sectionEnd - sectionStart }, (_, i) => sectionStart + i);
    return around(lines, index, sectionStart, sectionEnd, tight ? 400 : before, tight ? 200 : after);
  };
  switch (info.shape) {
    case 'title': {
      const out: number[] = [];
      let used = 0;
      for (let at = start; at < lines.length; at += 1) {
        used += lines[at]!.length + 1;
        if (used > (tight ? 600 : 2000) && out.length) break;
        out.push(at);
      }
      return out;
    }
    case 'summary':
      return section(1600, 400);
    case 'cell':
    case 'language': {
      if (!/^\s*\|/.test(lines[index]!)) return section(1000, 600);
      let top = index;
      while (top > start && /^\s*\|/.test(lines[top - 1]!)) top -= 1;
      return [...headingsAbove(lines, top, start), top, top + 1, index];
    }
    case 'items': {
      let top = index;
      while (top > start && listLead(lines[top - 1]!)) top -= 1;
      let bottom = index;
      while (bottom + 1 < lines.length && listLead(lines[bottom + 1]!)) bottom += 1;
      const out = [...headingsAbove(lines, top, start)];
      if (top - 1 >= start && lines[top - 1]!.trim()) out.push(top - 1);
      let used = 0;
      const list: number[] = [];
      for (let at = bottom; at >= top; at -= 1) {
        used += lines[at]!.length + 1;
        if (used > (tight ? 600 : 1600) && at < index) break;
        list.push(at);
      }
      return [...out, ...list];
    }
    default:
      return section(1000, 600);
  }
}

/** What the model is shown for one line: asked blanks numbered, the rest as words or `___`, links as their words. */
function renderLine(line: string, lineStart: number, marks: Map<number, { to: number; text: string }>): string {
  let out = '';
  let at = 0;
  const starts = [...marks.keys()].filter((k) => k >= lineStart && k < lineStart + line.length + 1).sort((a, b) => a - b);
  for (const start of starts) {
    const mark = marks.get(start)!;
    out += line.slice(at, start - lineStart) + mark.text;
    at = mark.to - lineStart;
  }
  out += line.slice(at);
  return out
    .replace(/(?<!!)\[([^\]\n]*)\]\((?:https?:|mailto:)[^)\s]*\)/g, '$1')
    .replace(/<(?:https?:|mailto:)[^<>\s]*>/g, '')
    .replace(/\bhttps?:\/\/[^\s<>()]+/g, '')
    .replace(/[ \t]+$/, '');
}

/**
 * The scope of every ask, merged in the note's order, rendered: the title line first, `(lines left out)` wherever words
 * were skipped. `write` says how an asked target is written: `{?1 question}` for the first two rungs, `{?question}`
 * for the third.
 */
export function scopeText(text: string, asks: readonly Ask[], write: (ask: Ask, index: number) => string, worked: (blank: Blank) => string | null = () => null, tight: 0 | 1 | 2 = 0): string {
  const lines = text.split('\n');
  const start = frontMatterEnd(lines);
  const chosen = new Set<number>();
  for (const ask of asks) for (const index of scopeOf(lines, lineIndexAt(text, ask.blank.from), ask.info, start, tight)) if (index >= start) chosen.add(index);
  const title = titleLineIndex(text);
  if (title >= 0) chosen.add(title);
  // What stands in for each blank and fill in the lines shown.
  const marks = new Map<number, { to: number; text: string }>();
  asks.forEach((ask, i) => marks.set(ask.blank.from, { to: ask.blank.to, text: write(ask, i) }));
  for (const fill of fillsIn(text)) if (!marks.has(fill.from)) marks.set(fill.from, { to: fill.to, text: fill.words });
  for (const blank of blanksIn(text)) if (!marks.has(blank.from)) marks.set(blank.from, { to: blank.to, text: worked(blank) ?? '___' });
  const offsets: number[] = [];
  let offset = 0;
  for (const line of lines) {
    offsets.push(offset);
    offset += line.length + 1;
  }
  const out: string[] = [];
  let last = -1;
  for (const index of [...chosen].sort((a, b) => a - b)) {
    if (DRAWN.test(lines[index]!)) continue;
    if (last >= 0 && index > last + 1) {
      const skipped = lines.slice(last + 1, index);
      if (skipped.some((l) => l.trim() && !DRAWN.test(l))) out.push('', '(lines left out)', '');
      else if (skipped.length) out.push('');
    }
    out.push(renderLine(lines[index]!, offsets[index]!, marks));
    last = index;
  }
  return out
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

// ---- the message ----------------------------------------------------------------------------------------------

/** The kinds probes' block for a shape, for the third rung. */
export const SHAPE_BLOCKS: Record<Shape, string> = {
  phrase: FILL_ANSWER,
  line: FILL_ANSWER,
  number: FILL_NUMBER,
  title: FILL_TITLE,
  summary: FILL_SUMMARY,
  items: FILL_ITEMS,
  cell: FILL_CELL,
  language: FILL_TRANSLATE,
};

/** The question an ask writes back: the blank's own, or an asked-again fill's from its bracket. */
const questionOf = (ask: Ask) => ask.blank.question;

/** The lead the next item of a list line takes: its indent, its mark or the next number, and an empty box for a to-do. */
export function nextLead(line: string, step = 1): string {
  const lead = listLead(line);
  if (!lead) return '- ';
  const number = /^(\d+)([.)])$/.exec(lead.marker);
  const marker = number ? `${Number(number[1]) + step}${number[2]}` : lead.marker;
  return `${lead.indent}${marker} ${lead.done !== null ? '[ ] ' : ''}`;
}

/**
 * An items blank asks one new item a numbered blank (docs/DESIGN.md §145, 5.8). Measured on the Mac, every model gave
 * one item where the first form asked for three under one number: the 4B "Sunglasses", the 9B "Cash, power bank, and
 * rain jacket" on one line. Asked as three blanks, one to a line, each is one item, as the models already answer
 * several blanks. The first carries the question, the rest are new lines of the list under it.
 */
function itemSlots(text: string, ask: Ask, numbers: readonly number[]): string {
  const [first, ...rest] = numbers;
  const lineStart = text.lastIndexOf('\n', ask.blank.from - 1) + 1;
  const lineEnd = text.indexOf('\n', ask.blank.to);
  const line = text.slice(lineStart, lineEnd === -1 ? text.length : lineEnd);
  // The blank is its item's whole words, so nothing on its line follows it but spaces.
  return [`{?${first} ${questionOf(ask)}}`, ...rest.map((n, i) => `${nextLead(line, i + 1)}{?${n} }`)].join('\n');
}

/** The hint for an items blank asked as `numbers`. */
function itemsHint(numbers: readonly number[]): string {
  if (numbers.length === 1) return `Blank ${numbers[0]} is a whole item of the list it is in.`;
  const which = numbers.length === 2 ? `${numbers[0]} and ${numbers[1]}` : `${numbers[0]} to ${numbers[numbers.length - 1]}`;
  return `Blanks ${which} are whole items of the list they are in, each one new.`;
}

/** The third rung's words after `Fill {?…}`: a cell named in words, and an items blank's count. */
function fillPhrase(info: ShapeInfo): string {
  if (info.shape === 'cell' && info.cell) return `, the ${info.cell.header} of ${info.cell.row}.`;
  if (info.shape === 'language' && info.cell) return `, ${info.cell.row} in ${info.language!.name}.`;
  if (info.shape === 'items') return `. Give ${info.count}.`;
  return '.';
}

/**
 * The generation for these asks at this rung: its system prompt, its message and its budget (5.3, 5.8). The first two
 * rungs number every blank and give each shape's hint; the third asks one blank the way the kinds probes did.
 */
export function buildFill(text: string, asks: readonly Ask[], options: { rung: Rung; today: Date; worked?: (blank: Blank) => string | null; tight?: 0 | 1 | 2 }): Built {
  const { rung, today } = options;
  const header = `Today is ${modelDay(today)}.`;
  const maxTokens = Math.max(LEAST_BUDGET, asks.reduce((sum, ask) => sum + budgetOf(ask.info), 0));
  const againLine = asks.filter((a) => a.again).map((a) => `It is not: ${a.again!.words}.`);
  if (rung === 3) {
    const ask = asks[0]!;
    const q = questionOf(ask);
    const written = `{?${q}}`;
    const scope = scopeText(text, [ask], () => written, options.worked, options.tight ?? 0);
    const last = [...againLine, `Fill ${written}${fillPhrase(ask.info)}`].join('\n');
    return { system: `${FILL_CORE}\n\n${SHAPE_BLOCKS[ask.info.shape]}`, prompt: `${header}\n\nThe note:\n${scope}\n\n${last}`, maxTokens, numbers: [[1]] };
  }
  // Each ask's numbers: one, or one an item for an items blank.
  const numbers: number[][] = [];
  let next = 1;
  for (const ask of asks) {
    const size = ask.info.shape === 'items' ? ask.info.count : 1;
    numbers.push(Array.from({ length: size }, (_, i) => next + i));
    next += size;
  }
  const scope = scopeText(text, asks, (ask, i) => (ask.info.shape === 'items' ? itemSlots(text, ask, numbers[i]!) : `{?${numbers[i]![0]} ${questionOf(ask)}}`), options.worked, options.tight ?? 0);
  const hints = asks.map((ask, i) => (ask.info.shape === 'items' ? itemsHint(numbers[i]!) : hintFor(numbers[i]![0]!, ask.info))).filter((h): h is string => h !== null);
  const total = next - 1;
  const answer = total === 1 ? 'Answer blank 1.' : `Answer blanks 1 to ${total}.`;
  const parts = [header, `The note:\n${scope}`];
  if (hints.length) parts.push(hints.join('\n'));
  parts.push([...againLine, answer].join('\n'));
  return { system: FILL_PROMPT, prompt: parts.join('\n\n'), maxTokens, numbers };
}

/** Whether a generation fits the room: its budget, and the prompt, the message and the budget in the window. */
export function fits(built: Built): boolean {
  return built.maxTokens <= ROOM.output && FILL_PROMPT_TOKENS + estimateTokens(built.prompt) + built.maxTokens <= ROOM.window;
}

/** One generation of a press: which asks, and how much of the note it reads. */
export interface Generation {
  asks: Ask[];
  tight: 0 | 1 | 2;
}

/**
 * A press split into generations by the rung and the room (5.5, 5.8): at rung 1 blanks share a generation in the
 * note's order while it fits, at rungs 2 and 3 each has its own, the third grouped by shape so each block's snapshot
 * stays warm. A blank that will not fit alone has its scope cut, then its line alone.
 */
export function fillPlan(text: string, asks: readonly Ask[], rung: Rung, today: Date): Generation[] {
  const sorted = [...asks].sort((a, b) => a.blank.from - b.blank.from);
  const alone = (ask: Ask): Generation => {
    for (const tight of [0, 1, 2] as const) if (fits(buildFill(text, [ask], { rung, today, tight }))) return { asks: [ask], tight };
    return { asks: [ask], tight: 2 };
  };
  if (rung === 2) return sorted.map(alone);
  if (rung === 3) {
    const order: Shape[] = [];
    for (const ask of sorted) if (!order.includes(ask.info.shape)) order.push(ask.info.shape);
    return order.flatMap((shape) => sorted.filter((a) => a.info.shape === shape).map(alone));
  }
  const plan: Generation[] = [];
  let group: Ask[] = [];
  for (const ask of sorted) {
    const next = [...group, ask];
    if (group.length && !fits(buildFill(text, next, { rung, today }))) {
      plan.push(group.length === 1 ? alone(group[0]!) : { asks: group, tight: 0 });
      group = [ask];
    } else group = next;
  }
  if (group.length) plan.push(group.length === 1 ? alone(group[0]!) : { asks: group, tight: 0 });
  return plan;
}
