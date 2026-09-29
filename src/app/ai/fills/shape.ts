import { askingWords, asksForTitle, BLANK, type Blank, withoutBlanks } from '../../core/blanks.ts';
import { frontMatterEnd } from '../../core/frontMatter.ts';
import { listLead } from '../../core/itemSyntax.ts';

/**
 * The shape of a blank, read by code from where it sits and a few plain words (docs/DESIGN.md §145, 2.6), and the
 * check an answer must pass before it is written (5.7).
 *
 * The kinds probes gave a small model a worked example per shape and took fifteen blanks from 3 right to 12. Rather than
 * ask a person to write kind words, the shape comes from what they already write: a blank as a note's whole first line
 * is a title, as a whole list item it adds items, in a table cell it answers for that row and column, `{?in Japanese}`
 * is a translation. The shape picks the hint line the model is given, its budget, the check and where it lands.
 *
 * The page cannot send the engine a grammar (src-tauri/src/ai_commands.rs maps a page's request to none), so the check
 * does that work after: an echo of the line taken off, a title or a summary naming something the note lacks refused,
 * a translation into Japanese without Japanese script refused, and a cap on every shape. A refused answer writes
 * nothing. Each rule's cases are the probes' own answers.
 */

export type Shape = 'title' | 'language' | 'items' | 'cell' | 'summary' | 'number' | 'line' | 'phrase';

export interface Language {
  name: string;
  /** Whether it is written in a script of its own, which the check looks for. */
  script: RegExp | null;
}

export interface ShapeInfo {
  shape: Shape;
  /** How many items, for an items blank; one otherwise. */
  count: number;
  /** The language asked for, for a language blank. */
  language: Language | null;
  /** A cell's column header and its row's first cell, for a cell (and a language cell). */
  cell: { header: string; row: string } | null;
  /** The blank sits on the note's first line of words, which never holds a mark (6.2). */
  titleLine: boolean;
  /** The blank is the whole of its line, a heading's `#` or a list's lead aside. */
  wholeLine: boolean;
  /** A title blank over too few words to be named from: nothing runs. */
  tooShort: boolean;
}

/** The tokens each shape may write, before the three for its `[N] `. */
export const SHAPE_BUDGET: Record<Shape, number> = { title: 24, language: 64, items: 32, cell: 24, summary: 64, number: 16, line: 64, phrase: 32 };

/** A blank's whole budget: its shape's, an items blank's times its count, and three for `[N] `. */
export function budgetOf(info: ShapeInfo): number {
  return SHAPE_BUDGET[info.shape] * (info.shape === 'items' ? info.count : 1) + 3;
}

// ---- languages ------------------------------------------------------------------------------------------------

/** Scripts of their own, by language code: the check wants one of these in a translation. */
const SCRIPTS: Record<string, RegExp> = {
  ja: /[\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}]/u,
  zh: /\p{Script=Han}/u,
  ko: /\p{Script=Hangul}/u,
  ru: /\p{Script=Cyrillic}/u,
  uk: /\p{Script=Cyrillic}/u,
  el: /\p{Script=Greek}/u,
  ar: /\p{Script=Arabic}/u,
  he: /\p{Script=Hebrew}/u,
  th: /\p{Script=Thai}/u,
  hi: /\p{Script=Devanagari}/u,
};

const CODES = ['ja', 'zh', 'ko', 'ru', 'uk', 'el', 'ar', 'he', 'th', 'hi', 'fr', 'de', 'es', 'it', 'pt', 'nl', 'sv', 'no', 'da', 'fi', 'pl', 'cs', 'tr', 'vi', 'id', 'ms', 'hu', 'ro', 'ga', 'cy', 'is', 'ca', 'eu', 'hr', 'sr', 'bg', 'sk', 'sl', 'et', 'lv', 'lt', 'tl', 'sw', 'fa', 'ur', 'bn', 'ta', 'la'];

/** Every language by its English name, lower-cased, found with `Intl.DisplayNames` over a fixed list of codes. */
const LANGUAGES: Map<string, Language> = (() => {
  const names = new Intl.DisplayNames(['en'], { type: 'language' });
  const map = new Map<string, Language>();
  for (const code of CODES) {
    const name = names.of(code);
    if (name) map.set(name.toLowerCase(), { name, script: SCRIPTS[code] ?? null });
  }
  map.set('mandarin', { name: 'Chinese', script: SCRIPTS.zh! });
  map.set('farsi', { name: 'Persian', script: null });
  return map;
})();

/** The language a question asks for: `in Japanese`, `Japanese`, `in which year` names none. */
export function languageAsked(words: string): Language | null {
  const found = /^(?:in\s+)?([a-z]+(?:\s+[a-z]+)?)[?.!]*$/i.exec(words.trim());
  return found ? (LANGUAGES.get(found[1]!.toLowerCase()) ?? null) : null;
}

// ---- where the blank sits -------------------------------------------------------------------------------------

/** The line a blank sits on, and where it starts. */
function lineOf(text: string, blank: Blank): { line: string; start: number; index: number } {
  const start = text.lastIndexOf('\n', blank.from - 1) + 1;
  const end = text.indexOf('\n', blank.to);
  return { line: text.slice(start, end === -1 ? text.length : end), start, index: text.slice(0, start).split('\n').length - 1 };
}

/** The index of the note's first line of words, as its title reads it: after the front matter, not a picture. */
export function titleLineIndex(text: string): number {
  const lines = text.split('\n');
  for (let at = frontMatterEnd(lines); at < lines.length; at += 1) {
    const line = lines[at]!;
    if (line.trim() && !/^!\[[^\]]*\]\([^)]*\)\s*$/.test(line)) return at;
  }
  return -1;
}

/** The cells of a table line, pipes as the reader splits them. */
export function tableCells(line: string): string[] {
  return line
    .trim()
    .replace(/^\|/, '')
    .replace(/(?<!\\)\|$/, '')
    .split(/(?<!\\)\|/)
    .map((c) => c.trim());
}

/** For a blank that is a table body cell's whole words: its column's header and its row's first cell. */
function cellOf(text: string, blank: Blank): { header: string; row: string; column: number } | null {
  const { line, start, index } = lineOf(text, blank);
  if (!/^\s*\|/.test(line)) return null;
  const column = (line.slice(0, blank.from - start).match(/(?<!\\)\|/g)?.length ?? 1) - 1;
  const cells = tableCells(line);
  if ((cells[column] ?? '') !== text.slice(blank.from, blank.to)) return null;
  const lines = text.split('\n');
  let top = index;
  while (top > 0 && /^\s*\|/.test(lines[top - 1]!)) top -= 1;
  // A body row: the header, then the delimiter, then this row somewhere below.
  if (index < top + 2 || !/^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/.test(lines[top + 1] ?? '')) return null;
  const header = tableCells(lines[top]!)[column] ?? '';
  return { header, row: cells[0] ?? '', column };
}

const SUMMARY = /^(?:a |the )?(?:summary|in one line|sum up|sum it up|gist|the gist|tl;?dr|the point|one line)$/i;
/** A unit straight after the blank makes it a number: never the one-letter names or "in", which are words too. */
const UNIT_AFTER = /^(?:grams?|kg|kilos?|kilograms?|mg|ml|litres?|liters?|minutes?|mins?|hours?|seconds?|secs?|days?|weeks?|months?|years?|km|kilometres?|kilometers?|miles?|metres?|meters?|cm|mm|feet|foot|ft|inches|°c|°f|degrees?|calories|kcal|percent|pounds?|lbs?|oz|ounces?|cups?|tsp|tbsp|people|times|steps|pages)\b|^%/i;
const NUMBER_QUESTION = /^(?:how many|how much|how long|how far|how old|how tall|how big|how heavy)\b/i;
const COUNT_WORDS: Record<string, number> = { one: 1, two: 2, three: 3, four: 4, five: 5, 'a few': 3, 'a couple of': 2, 'a couple': 2 };

/** The number of items a question asks for, one to five, or null where it names none. */
function itemsAsked(question: string): number | null {
  const digits = /\b([1-5])\b/.exec(question);
  if (digits) return Number(digits[1]);
  const words = /\b(one|two|three|four|five|a few|a couple of|a couple)\b/i.exec(question);
  return words ? COUNT_WORDS[words[1]!.toLowerCase()]! : null;
}

/** The shape of a blank, the first that applies (docs/DESIGN.md §145, 2.6). */
export function shapeOf(blank: Blank, text: string): ShapeInfo {
  const { line, index } = lineOf(text, blank);
  const own = text.slice(blank.from, blank.to);
  const titleLine = index === titleLineIndex(text);
  const bare = line.replace(/^\s*#{1,6}\s+/, '').trim();
  const lead = listLead(line);
  const wholeLine = bare === own || (lead !== null && line.slice(lead.wordsAt).trim() === own);
  const base: ShapeInfo = { shape: 'phrase', count: 1, language: null, cell: null, titleLine, wholeLine, tooShort: false };
  const question = blank.question;

  if (titleLine && bare === own && asksForTitle(question)) {
    const below = withoutBlanks(text.split('\n').slice(index + 1).join('\n'));
    const words = below.split(/\s+/).filter((w) => /[\p{L}\p{N}]/u.test(w)).length;
    return { ...base, shape: 'title', tooShort: words < 20 };
  }
  const cell = cellOf(text, blank);
  const language = languageAsked(question) ?? (cell && !question ? languageAsked(cell.header) : null);
  if (language) return { ...base, shape: 'language', language, cell: cell ? { header: cell.header, row: cell.row } : null };
  if (lead && line.slice(lead.wordsAt).trim() === own) {
    const todo = lead.done !== null;
    return { ...base, shape: 'items', count: itemsAsked(question) ?? (todo ? 1 : 3) };
  }
  if (cell) return { ...base, shape: 'cell', cell: { header: cell.header, row: cell.row } };
  if (SUMMARY.test(question.replace(/[?.!:]+$/, '').trim())) return { ...base, shape: 'summary' };
  // A whole line is a line, whatever its question starts with: `{?how long to boil an egg}` as a first line wants its
  // answer said, not a bare number.
  if (wholeLine) return { ...base, shape: 'line' };
  const asking = askingWords(blank, text);
  if (UNIT_AFTER.test(asking.after) || NUMBER_QUESTION.test(question)) return { ...base, shape: 'number' };
  return base;
}

/** The hint line a message gives a blank, numbered: none for a phrase, which needs none. */
export function hintFor(n: number, info: ShapeInfo): string | null {
  switch (info.shape) {
    case 'title':
      return `Blank ${n} is the note's title.`;
    case 'language':
      return info.cell ? `Blank ${n} is ${info.cell.row} in ${info.language!.name}.` : `Blank ${n} asks for ${info.language!.name}.`;
    case 'items':
      return info.count > 1 ? `Blanks ${n} to ${n + info.count - 1} are whole items of the list they are in, each one new.` : `Blank ${n} is a whole item of the list it is in.`;
    case 'cell':
      return `Blank ${n} is the ${info.cell!.header} of ${info.cell!.row}.`;
    case 'summary':
      return `Blank ${n} is one sentence saying what the lines above it say.`;
    case 'number':
      return `Blank ${n} is a number.`;
    case 'line':
      return `Blank ${n} is a whole line.`;
    default:
      return null;
  }
}

// ---- the check ------------------------------------------------------------------------------------------------

export type Checked = { ok: true; text: string; items: string[] } | { ok: false; why: 'unknown' | 'none' | 'didnt-fit' };

/** Each shape's caps: words and characters. */
const CAPS: Record<Shape, { words: number; chars: number }> = {
  phrase: { words: 20, chars: 160 },
  number: { words: 8, chars: 40 },
  cell: { words: 10, chars: 80 },
  title: { words: 8, chars: 60 },
  summary: { words: 30, chars: 240 },
  line: { words: 40, chars: 320 },
  items: { words: 12, chars: 120 },
  language: { words: 30, chars: 200 },
};

const UNKNOWN = /^(?:unknown\b|not sure\b|i don['’]t know\b|i do not know\b|n\/a\b)/i;
const MONTH_OR_DAY = /^(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|monday|tuesday|wednesday|thursday|friday|saturday|sunday)$/i;

/** An answer's first line tidied: quotes, backticks, bold, `Answer:`, a list mark and a blank's braces off. */
function tidied(line: string): string {
  let out = line.trim();
  for (let pass = 0; pass < 3; pass += 1) {
    out = out
      .replace(/^answer\s*:\s*/i, '')
      .replace(/^(?:[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)/, '')
      .replace(/^\{\?\d*\s*/, '')
      .replace(/\}$/, '')
      .replace(/^\*\*(.*)\*\*$/, '$1')
      .replace(/^`+([^`]*)`+$/, '$1')
      .replace(/^["“”'‘’](.*)["“”'‘’]$/, '$1')
      .trim();
  }
  return out.replace(/\s+/g, ' ');
}

const wordCount = (text: string) => text.split(/\s+/).filter(Boolean).length;
const lowerWords = (text: string) => text.toLowerCase().normalize('NFD').replace(/\p{Diacritic}/gu, '').match(/[\p{L}\p{N}]+/gu) ?? [];

/**
 * Whether an answer holds a number, a date or a capitalised name the note does not (5.7): a title or a summary is made
 * of the note's own words, so one naming something else is refused. The note is read without its blanks and fills.
 */
function namesWhatNoteLacks(answer: string, note: string): boolean {
  const plain = withoutBlanks(note);
  const known = new Set(lowerWords(plain));
  const digits = new Set(plain.match(/\d+/g) ?? []);
  for (const run of answer.match(/\d+/g) ?? []) if (!digits.has(run)) return true;
  const words = answer.split(/\s+/);
  return words.some((raw, i) => {
    const word = raw.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, '');
    if (!word) return false;
    const lower = lowerWords(word)[0] ?? '';
    if (MONTH_OR_DAY.test(word) && !known.has(lower)) return true;
    if (i === 0 || word === 'I' || !/^\p{Lu}/u.test(word)) return false;
    return !known.has(lower);
  });
}

/** The words just before a blank, for taking an echo of them off an answer. */
function wordsBefore(text: string, blank: Blank): string[] {
  const start = text.lastIndexOf('\n', blank.from - 1) + 1;
  return lowerWords(text.slice(start, blank.from).replace(new RegExp(BLANK.source, 'g'), ' '));
}

/** An answer that begins by saying three or more of the words just before the blank has them taken off. */
function withoutEcho(answer: string, before: string[]): string {
  const words = answer.split(/\s+/);
  const lower = words.map((w) => lowerWords(w)[0] ?? '');
  for (let size = Math.min(before.length, lower.length - 1); size >= 3; size -= 1) {
    const tail = before.slice(-size);
    if (tail.every((w, i) => w === lower[i])) return words.slice(size).join(' ');
  }
  // The echo may start mid-sentence: "the newest Pixel is the Pixel 10" after "The newest Pixel is the".
  for (let start = 0; start < before.length - 2; start += 1) {
    const tail = before.slice(start);
    if (tail.length >= 3 && tail.length < lower.length && tail.every((w, i) => w === lower[i])) return words.slice(tail.length).join(' ');
  }
  return answer;
}

/** The character after a blank, and whether the blank ends its sentence. */
function endsSentence(text: string, blank: Blank): { next: string; ends: boolean } {
  const next = text.slice(blank.to, blank.to + 1);
  const rest = text.slice(blank.to).split('\n', 1)[0] ?? '';
  return { next, ends: !rest.trim() || /^\s*[|]/.test(rest) };
}

/**
 * The answer checked against its blank's shape (5.7). `lines` are the answer lines for this blank as the reader found
 * them (several for an items blank), `truncated` whether the budget cut the last of them, `note` the note's text.
 */
export function checkShape(lines: readonly string[], blank: Blank, info: ShapeInfo, note: string, truncated = false): Checked {
  const table = /^\s*\|/.test(note.slice(note.lastIndexOf('\n', blank.from - 1) + 1, blank.from));
  if (info.shape === 'items') return checkItems(lines, blank, info, note, truncated);
  const first = lines.find((l) => l.trim()) ?? '';
  let text = tidied(first);
  if (UNKNOWN.test(text)) return { ok: false, why: 'unknown' };
  text = withoutEcho(text, wordsBefore(note, blank));
  const { next, ends } = endsSentence(note, blank);
  if (/\.$/.test(text) && !/\.\.$/.test(text) && (!ends || /^[.,:?!]/.test(next))) text = text.slice(0, -1).trimEnd();
  if (info.shape === 'title') text = text.replace(/^#+\s*/, '').replace(/\.$/, '');
  if (info.shape === 'number') {
    const after = /^\s*([\p{L}°%]+)/u.exec(note.slice(blank.to))?.[1];
    if (after) text = text.replace(new RegExp(`\\s*${after.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i'), '');
  }
  if (info.shape === 'language' && !info.language?.script) text = text.replace(/\s*\([^)]*\)$/, '');
  if (table) text = text.replace(/\|/g, '/');
  if (!text || text.toLowerCase() === blank.question.toLowerCase()) return { ok: false, why: 'none' };
  if (UNKNOWN.test(text)) return { ok: false, why: 'unknown' };
  const caps = CAPS[info.shape];
  const cut = truncated && lines.filter((l) => l.trim()).length <= 1;
  if (cut || wordCount(text) > caps.words || text.length > caps.chars) return { ok: false, why: 'didnt-fit' };
  if (info.shape === 'number' && !/\d/.test(text)) return { ok: false, why: 'didnt-fit' };
  if ((info.shape === 'title' || info.shape === 'summary') && namesWhatNoteLacks(text, note)) return { ok: false, why: 'didnt-fit' };
  if (info.shape === 'language' && info.language?.script && !info.language.script.test(text)) return { ok: false, why: 'didnt-fit' };
  return { ok: true, text, items: [text] };
}

/** An items blank's lines: each tidied, those the list already has dropped, at most its count. */
function checkItems(lines: readonly string[], blank: Blank, info: ShapeInfo, note: string, truncated: boolean): Checked {
  const nonEmpty = lines.filter((l) => l.trim());
  // A half line cut by the budget goes.
  const whole = truncated ? nonEmpty.slice(0, -1) : nonEmpty;
  const listed = new Set(
    note
      .split('\n')
      .map((l) => {
        const lead = listLead(l);
        return lead ? (lowerWords(l.slice(lead.wordsAt)).join(' ') ?? '') : '';
      })
      .filter(Boolean),
  );
  const items: string[] = [];
  let unknown = 0;
  for (const raw of whole) {
    const text = tidied(raw).replace(/\.$/, '');
    if (!text) continue;
    if (UNKNOWN.test(text)) {
      unknown += 1;
      continue;
    }
    const key = lowerWords(text).join(' ');
    if (listed.has(key) || items.some((i) => lowerWords(i).join(' ') === key)) continue;
    if (wordCount(text) > CAPS.items.words || text.length > CAPS.items.chars) continue;
    if (text.toLowerCase() === blank.question.toLowerCase()) continue;
    items.push(text);
    if (items.length === info.count) break;
  }
  if (!items.length) return { ok: false, why: unknown ? 'unknown' : nonEmpty.length ? 'didnt-fit' : 'none' };
  return { ok: true, text: items[0]!, items };
}
