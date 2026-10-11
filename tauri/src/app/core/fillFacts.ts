import { answer as sumAnswer } from './sums.ts';
import { askingWords, type Asking, type Blank, plainFills } from './blanks.ts';
import { frontMatterEnd } from './frontMatter.ts';
import { listLead, taskBox } from './itemSyntax.ts';
import { longDate } from './stamp.ts';
import { escapeRegExp } from './text.ts';
import { CITIES, cityOf, zoneOf } from './timeZones.ts';

/**
 * Blanks the app works out itself, before any model is asked (docs/DESIGN.md §145, 2.2 and 2.3).
 *
 * Measured on the 4B: asked the days to Christmas it said 12 and 13 (the answer was 88), and it added a note's costs
 * right one time and answered the bare word KNOWN the next. Sums and calendars are code's. So a total or an average of
 * the note's own amounts, a count of its to-dos, days until or since a date, a weekday, a date some days on, a unit
 * conversion, and the time in a city or between two are worked out here, drawn after the blank like a sum
 * (editor/sums.ts) with the working a tap away, and never written into the note unless asked.
 *
 * Each solver reads the words a blank asks with (core/blanks.ts `askingWords`): its question, its sentence, and the
 * question just before an empty blank. They are drawn narrow: a word anywhere in a sentence is not enough, since "What
 * is the average lifespan of a cat?" is not a sum. A solver that recognises its material and cannot finish says Can't
 * work out in its own words (two currencies, a line with two amounts, Easter, no date to count to), and the person can
 * ask the model anyway. It never hands the blank to the model on its own.
 *
 * Pure, and the clock is passed in, so every date here is a test.
 */

export type FactIcon = 'calculator' | 'calendar' | 'globe';
export type Solver = 'total' | 'average' | 'count' | 'days' | 'weekday' | 'dateOn' | 'units' | 'time';

export interface WorkedAnswer {
  kind: 'answer';
  solver: Solver;
  icon: FactIcon;
  /** What is drawn after the blank: `$325`, `88 days`, `Saturday`. */
  answer: string;
  /** How it was reached, for the panel: `$200 + $45 + $80 = $325.` */
  working: string;
  /** Whether it changes with the day or the minute, so the panel says so and the editor redraws it. */
  changes: 'day' | 'minute' | null;
}

export interface CannotWork {
  kind: 'cannot';
  solver: Solver;
  icon: FactIcon;
  /** The panel's sentence, in the app's words. */
  words: string;
}

export type Worked = WorkedAnswer | CannotWork;

/** The moment the answers are for, and the device's own zone (for "Tokyo is 8 hours ahead of London"). */
export interface FactClock {
  now: Date;
  zone?: string;
}

const ICONS: Record<Solver, FactIcon> = {
  total: 'calculator',
  average: 'calculator',
  count: 'calculator',
  units: 'calculator',
  days: 'calendar',
  weekday: 'calendar',
  dateOn: 'calendar',
  time: 'globe',
};

const answered = (solver: Solver, answer: string, working: string, changes: WorkedAnswer['changes'] = null): WorkedAnswer => ({ kind: 'answer', solver, icon: ICONS[solver], answer, working, changes });
const cannot = (solver: Solver, words: string): CannotWork => ({ kind: 'cannot', solver, icon: ICONS[solver], words });

/** What the app works out for a blank, why it cannot, or null where it is not the app's to answer. */
export function workOut(blank: Blank, text: string, clock: FactClock): Worked | null {
  const asking = askingWords(blank, text);
  return sum(blank, text, asking) ?? count(blank, text, asking) ?? dateOn(asking, clock) ?? days(asking, clock) ?? weekday(asking, clock) ?? units(asking) ?? time(asking, clock);
}

// ---- totals and averages -------------------------------------------------------------------------------------

const TOTAL_QUESTION = /^(?:the |a )?(?:total|sum|altogether|in all|grand total)$/i;
const TOTAL_WORDS = /\b(?:total|sum|altogether|in all|adds up to|comes to)\b/i;
const AVERAGE_WORDS = /\b(?:average|mean)\b/i;

/** Whether the blank asks for a total or an average, read only where the rule says (2.2): never a word elsewhere. */
function sumAsked(asking: Asking): 'total' | 'average' | null {
  const question = asking.question.replace(/[?.!]+$/, '').trim();
  if (AVERAGE_WORDS.test(question) || AVERAGE_WORDS.test(asking.label)) return 'average';
  if (TOTAL_QUESTION.test(question) || TOTAL_WORDS.test(asking.label)) return 'total';
  if (asking.prior && AVERAGE_WORDS.test(asking.prior)) return 'average';
  if (asking.prior && TOTAL_WORDS.test(asking.prior)) return 'total';
  return null;
}

/** An amount on a line: its value, what kind it is, and how it was written. */
interface Amount {
  value: number;
  /** `$` or `EUR` for money, a unit's symbol, or '' for a plain number. */
  kind: string;
  money: boolean;
  written: string;
}

const MONTH = String.raw`(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)`;
/** What is not an amount, taken out of a line before its amounts are read. */
const NOT_AMOUNTS = [
  /\[[^\]\n]*\]\([^)\n]*\)/g, // a link, words and all
  /`[^`\n]*`/g, // a code span
  /\{\?[^{}\n]*\}/g, // a blank
  /\b\d{4}-\d{2}-\d{2}\b/g, // an ISO date
  new RegExp(String.raw`\b\d{1,2}(?:st|nd|rd|th)?\s+${MONTH}\b\.?`, 'gi'), // 3 Oct
  new RegExp(String.raw`\b${MONTH}\.?\s+\d{1,2}(?:st|nd|rd|th)?\b`, 'gi'), // Oct 3
  /\b\d{1,2}\/\d{1,2}(?:\/\d{2,4})?\b/g, // 3/10
  /\b\d{1,2}[:.]\d{2}\s*(?:am|pm)?\b/gi, // 14:05, 9.30pm
  /\b\d{1,2}\s*(?:am|pm)\b/gi, // 9am
  /\b\d+(?:st|nd|rd|th)\b/gi, // 3rd
  /\d+(?:\.\d+)?\s*%/g, // 20%
  /\b\d+\.\d+\.\d+(?:\.\d+)*\b/g, // a version
  /\+\d[\d\s-]{5,}/g, // a phone number
];

const CURRENCY_CODES = 'USD|EUR|GBP|JPY|CHF|CAD|AUD|NZD|CNY|INR|SEK|NOK|DKK|PLN|CZK|HKD|SGD|KRW|MXN|BRL|ZAR';
const UNIT_SYMBOLS = ['kg', 'g', 'lb', 'oz', 'km', 'm', 'cm', 'mm', 'mi', 'ml', 'l'];

/** The amounts a line holds, as the solver reads them. */
function amountsOf(line: string): Amount[] {
  // The list's lead goes first: a numbered item's own number is not an amount.
  const lead = listLead(line);
  let rest = plainFills(lead ? line.slice(lead.wordsAt) : line).replace(/^\s*(?:>\s*)+/, '');
  for (const pattern of NOT_AMOUNTS) rest = rest.replace(pattern, ' ');
  const found: Amount[] = [];
  const pattern = new RegExp(String.raw`([$€£¥₹])\s?(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?|(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?\s?(${CURRENCY_CODES}|${UNIT_SYMBOLS.join('|')})?\b`, 'g');
  for (let match = pattern.exec(rest); match; match = pattern.exec(rest)) {
    const sign = match[1];
    if (sign) {
      found.push({ value: Number(`${match[2]!.replace(/,/g, '')}${match[3] ?? ''}`), kind: sign, money: true, written: match[0].replace(/\s/g, '') });
      continue;
    }
    const digits = match[4]!;
    const decimal = match[5] ?? '';
    const suffix = match[6];
    // A year: four figures from 1000 to 2999, with no sign, unit or comma.
    if (!suffix && !decimal && /^[12]\d{3}$/.test(digits)) continue;
    // The number a numbered list starts its line with has gone with the lead; a number glued to a letter is a name.
    if (/[\p{L}]/u.test(rest[match.index - 1] ?? '')) continue;
    const value = Number(`${digits.replace(/,/g, '')}${decimal}`);
    if (suffix && new RegExp(`^(?:${CURRENCY_CODES})$`).test(suffix)) found.push({ value, kind: suffix, money: true, written: `${digits}${decimal} ${suffix}` });
    else if (suffix) found.push({ value, kind: suffix, money: false, written: `${digits}${decimal} ${suffix}` });
    else found.push({ value, kind: '', money: false, written: `${digits}${decimal}` });
  }
  return found;
}

/** A line's words, as the working names one: the list's lead off, and filled answers as words. */
function lineSaid(line: string): string {
  const lead = listLead(line);
  return plainFills(lead ? line.slice(lead.wordsAt) : line)
    .replace(/^\s*>\s*/, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/** The block directly above the blank's line: blank lines just above passed over, then up to a heading, a blank line or the start. */
function blockAbove(text: string, blank: Blank): string[] {
  const lines = text.slice(0, text.lastIndexOf('\n', blank.from - 1) + 1).split('\n');
  lines.pop();
  const front = frontMatterEnd(text.split('\n'));
  let at = lines.length - 1;
  while (at >= front && at >= 0 && !lines[at]!.trim()) at -= 1;
  const block: string[] = [];
  for (; at >= front && at >= 0; at -= 1) {
    const line = lines[at]!;
    if (!line.trim() || /^\s*#{1,6}\s/.test(line)) break;
    block.unshift(line);
  }
  return block;
}

/** The cells of a table line, outer pipes off. */
function cells(line: string): string[] {
  return line
    .trim()
    .replace(/^\||\|$/g, '')
    .split(/(?<!\\)\|/)
    .map((c) => c.trim());
}

/** For a cell whose row starts `Total` or `Sum`: the column above it, as lines of one cell each. */
function columnAbove(text: string, blank: Blank): string[] | null {
  const lineStart = text.lastIndexOf('\n', blank.from - 1) + 1;
  const lineEnd = text.indexOf('\n', blank.to);
  const line = text.slice(lineStart, lineEnd === -1 ? text.length : lineEnd);
  if (!/^\s*\|/.test(line)) return null;
  const row = cells(line);
  if (!/^(?:\*\*)?(?:total|sum|average|mean)(?:\*\*)?:?$/i.test(row[0] ?? '')) return null;
  // The blank's column: the unescaped pipes before it, less the one that opens the row.
  const column = (line.slice(0, blank.from - lineStart).match(/(?<!\\)\|/g)?.length ?? 1) - 1;
  const above = text.slice(0, lineStart).split('\n');
  above.pop();
  const rows: string[] = [];
  for (let at = above.length - 1; at >= 0 && /^\s*\|/.test(above[at]!); at -= 1) rows.unshift(above[at]!);
  // The header and the delimiter row are not amounts.
  return rows
    .slice(2)
    .map((r) => cells(r)[column] ?? '')
    .filter((c) => c.trim());
}

/** A total's figure as it should read: the sum's own evaluator for signs and plain numbers, a code or a unit after. */
function figure(values: number[], kind: string, average: boolean): string {
  const total = values.reduce((a, b) => a + b, 0);
  const value = average ? total / values.length : total;
  if (kind === '' || /^[$€£¥₹]$/.test(kind)) {
    const expression = values.map((v) => `${kind}${v}`).join(' + ');
    const worked = sumAnswer(average ? `(${expression}) / ${values.length}` : expression);
    if (worked) return worked;
  }
  const rounded = Math.round(value * 100) / 100;
  return `${rounded.toLocaleString('en-US', { maximumFractionDigits: 2 })} ${kind}`.trim();
}

function sum(blank: Blank, text: string, asking: Asking): Worked | null {
  const asked = sumAsked(asking);
  if (!asked) return null;
  const column = columnAbove(text, blank);
  const lines = column ?? blockAbove(text, blank);
  const amounts: Amount[] = [];
  const passed: string[] = [];
  for (const line of lines) {
    const here = amountsOf(line);
    if (here.length > 1) return cannot(asked, `The app adds these up itself, and one line has two amounts: ${lineSaid(line)}. Keep one to a line.`);
    if (here.length === 1) amounts.push(here[0]!);
    else if (lineSaid(line)) passed.push(lineSaid(line));
  }
  if (amounts.length < 2) return null;
  const first = amounts[0]!;
  const other = amounts.find((a) => a.kind !== first.kind);
  if (other) {
    const money = first.money && other.money;
    return cannot(asked, money ? `The app adds these up itself, and ${first.written} and ${other.written} are different money.` : `The app adds these up itself, and ${first.written} and ${other.written} are not the same kind of number.`);
  }
  const result = figure(
    amounts.map((a) => a.value),
    first.kind,
    asked === 'average',
  );
  const joined = amounts.map((a) => a.written).join(' + ');
  const working = asked === 'average' ? `(${joined}) ÷ ${amounts.length} = ${result}.` : `${joined} = ${result}.`;
  const skipped = passed.map((line) => ` ${capitalFirst(line.replace(/[.:]$/, ''))} has no amount.`).join('');
  return answered(asked, result, `${working}${skipped}`);
}

const capitalFirst = (text: string) => text.charAt(0).toUpperCase() + text.slice(1);

// ---- counts ---------------------------------------------------------------------------------------------------

const COUNT_NOUN = /\b(to-?dos?|tasks?|items?|things?)\b/i;
const COUNT_WHICH = /\b(left|done|ticked|open|to go|still|above|on this list|in this note)\b/i;

function count(blank: Blank, text: string, asking: Asking): Worked | null {
  const noun = COUNT_NOUN.exec(asking.text)?.[1]?.toLowerCase();
  const which = COUNT_WHICH.exec(asking.text)?.[1]?.toLowerCase();
  if (!noun || !which) return null;
  const left = ['left', 'open', 'to go', 'still'].includes(which);
  const done = which === 'done' || which === 'ticked';
  if (/^(?:to-?dos?|tasks?)$/.test(noun)) {
    const lines = text.split('\n');
    const front = frontMatterEnd(lines);
    let fenced = false;
    let open = 0;
    let ticked = 0;
    lines.forEach((line, index) => {
      if (index < front) return;
      if (/^\s*(```|~~~)/.test(line)) fenced = !fenced;
      if (fenced) return;
      const box = taskBox(line);
      if (box?.done) ticked += 1;
      else if (box) open += 1;
    });
    const all = open + ticked;
    if (left) return answered('count', `${open} left`, `${open} of ${all} ${all === 1 ? 'to-do' : 'to-dos'} in this note ${open === 1 ? 'is' : 'are'} not ticked.`);
    if (done) return answered('count', `${ticked} done`, `${ticked} of ${all} ${all === 1 ? 'to-do' : 'to-dos'} in this note ${ticked === 1 ? 'is' : 'are'} ticked.`);
    return answered('count', `${all} ${all === 1 ? 'to-do' : 'to-dos'}`, `This note has ${all} ${all === 1 ? 'to-do' : 'to-dos'}.`);
  }
  const items = blockAbove(text, blank).filter((line) => {
    const lead = listLead(line);
    return lead && line.slice(lead.wordsAt).trim();
  });
  if (!items.length) return null;
  const word = noun.startsWith('thing') ? 'thing' : 'item';
  return answered('count', `${items.length} ${items.length === 1 ? word : `${word}s`}`, `The list above has ${items.length} ${items.length === 1 ? 'item' : 'items'}.`);
}

// ---- dates ----------------------------------------------------------------------------------------------------

interface Day {
  y: number;
  m: number;
  d: number;
}

const MONTHS: Record<string, number> = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 };
const monthOf = (word: string) => MONTHS[word.slice(0, 3).toLowerCase()];
const WEEKDAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];

/** Fixed days, by what people call them. */
const FIXED: { pattern: RegExp; m: number; d: number }[] = [
  { pattern: /\bchristmas eve\b/i, m: 11, d: 24 },
  { pattern: /\bchristmas(?: day)?\b|\bxmas\b/i, m: 11, d: 25 },
  { pattern: /\bboxing day\b/i, m: 11, d: 26 },
  { pattern: /\bnew year'?s eve\b/i, m: 11, d: 31 },
  { pattern: /\bnew year'?s(?: day)?\b/i, m: 0, d: 1 },
  { pattern: /\bvalentine'?s(?: day)?\b/i, m: 1, d: 14 },
  { pattern: /\bhalloween\b/i, m: 9, d: 31 },
  { pattern: /\bbonfire night\b|\bguy fawkes\b/i, m: 10, d: 5 },
];

/** Days that move from year to year, which the app does not reckon. */
const MOVING = /\b(easter|thanksgiving|mother'?s day|father'?s day|diwali|eid|hanukkah|chanukah|lunar new year|chinese new year|ramadan|passover|good friday)\b/i;

type Found = { day: Day; year: boolean } | { refuse: string } | null;

const dayNumber = (day: Day) => Date.UTC(day.y, day.m, day.d) / 86_400_000;
const fromNumber = (n: number): Day => {
  const date = new Date(n * 86_400_000);
  return { y: date.getUTCFullYear(), m: date.getUTCMonth(), d: date.getUTCDate() };
};
const localDate = (day: Day) => new Date(day.y, day.m, day.d, 12);
const todayOf = (now: Date): Day => ({ y: now.getFullYear(), m: now.getMonth(), d: now.getDate() });

/** The date a blank's words name, the year left open where none is written; a refusal for a date the app cannot place. */
function findDate(words: string, today: Day): Found {
  const moving = MOVING.exec(words);
  if (moving) {
    const name = moving[1]!.replace(/\b\w/g, (c) => c.toUpperCase()).replace(/'S\b/, "'s");
    return { refuse: `${name} moves each year, and the app does not know when it falls.` };
  }
  const slashed = /\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b/.exec(words);
  if (slashed) {
    const a = Number(slashed[1]);
    const b = Number(slashed[2]);
    const name = (n: number) => new Date(2000, n - 1, 1).toLocaleString('en-GB', { month: 'long' });
    if (a <= 12 && b <= 12 && a !== b) return { refuse: `${slashed[0]} is a different day in London and in New York. Write it as ${b} ${name(a)} or ${a} ${name(b)}.` };
    if (b <= 12) return { day: { y: slashed[3] ? fullYear(slashed[3]) : today.y, m: b - 1, d: a }, year: Boolean(slashed[3]) };
    return { refuse: `${slashed[0]} could be read two ways. Write the month as a word.` };
  }
  const iso = /\b(\d{4})-(\d{2})-(\d{2})\b/.exec(words);
  if (iso) return { day: { y: Number(iso[1]), m: Number(iso[2]) - 1, d: Number(iso[3]) }, year: true };
  const dm = new RegExp(String.raw`\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(${MONTH})\b\.?(?:,?\s+(\d{4}))?`, 'i').exec(words);
  if (dm) return { day: { y: dm[3] ? Number(dm[3]) : today.y, m: monthOf(dm[2]!)!, d: Number(dm[1]) }, year: Boolean(dm[3]) };
  const md = new RegExp(String.raw`\b(${MONTH})\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s+(\d{4}))?`, 'i').exec(words);
  if (md) return { day: { y: md[3] ? Number(md[3]) : today.y, m: monthOf(md[1]!)!, d: Number(md[2]) }, year: Boolean(md[3]) };
  if (/\btoday\b/i.test(words)) return { day: today, year: true };
  if (/\btomorrow\b/i.test(words)) return { day: fromNumber(dayNumber(today) + 1), year: true };
  if (/\byesterday\b/i.test(words)) return { day: fromNumber(dayNumber(today) - 1), year: true };
  for (const fixed of FIXED) if (fixed.pattern.test(words)) return { day: { y: today.y, m: fixed.m, d: fixed.d }, year: false };
  const weekday = new RegExp(String.raw`\b(this|next|last)?\s*(${WEEKDAYS.join('|')})\b`, 'i').exec(words);
  if (weekday) {
    const want = WEEKDAYS.indexOf(weekday[2]!.toLowerCase());
    const now = new Date(Date.UTC(today.y, today.m, today.d)).getUTCDay();
    const which = (weekday[1] ?? '').toLowerCase();
    let ahead = (want - now + 7) % 7;
    if (which === 'last') ahead = ahead === 0 ? -7 : ahead - 7;
    else if (which === 'next' && ahead === 0) ahead = 7;
    return { day: fromNumber(dayNumber(today) + ahead), year: true };
  }
  return null;
}

const fullYear = (text: string) => (text.length === 2 ? 2000 + Number(text) : Number(text));

/** A date with no year: the next time it comes round, or the last, today counting either way. */
function placed(found: { day: Day; year: boolean }, today: Day, back: boolean): Day {
  if (found.year) return found.day;
  const t = dayNumber(today);
  let day = { ...found.day, y: today.y };
  if (!back && dayNumber(day) < t) day = { ...day, y: today.y + 1 };
  if (back && dayNumber(day) > t) day = { ...day, y: today.y - 1 };
  return day;
}

const plural = (n: number, word: string) => `${n} ${n === 1 ? word : `${word}s`}`;

/** Days, weeks and days, or months and days between two dates, as the question asked for them. */
function span(from: Day, to: Day, unit: 'day' | 'week' | 'month'): string {
  const days = Math.abs(dayNumber(to) - dayNumber(from));
  if (unit === 'week') {
    const weeks = Math.floor(days / 7);
    const rest = days % 7;
    return rest ? `${plural(weeks, 'week')} and ${plural(rest, 'day')}` : plural(weeks, 'week');
  }
  if (unit === 'month') {
    const [start, end] = dayNumber(from) <= dayNumber(to) ? [from, to] : [to, from];
    let months = (end.y - start.y) * 12 + (end.m - start.m);
    if (end.d < start.d) months -= 1;
    const landed = dayNumber(addMonths(start, months));
    const rest = dayNumber(end) - landed;
    return rest ? `${plural(months, 'month')} and ${plural(rest, 'day')}` : plural(months, 'month');
  }
  return plural(days, 'day');
}

function addMonths(day: Day, months: number): Day {
  const target = new Date(Date.UTC(day.y, day.m + months, 1));
  const last = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
  return { y: target.getUTCFullYear(), m: target.getUTCMonth(), d: Math.min(day.d, last) };
}

/** A count of days, weeks or months asked for: the plural, as "Days until" and "how many weeks" ask. "What day" asks which. */
const UNIT_WORD = /\b(days|weeks|months)\b/i;
const FORWARD = /\b(until|till|til|to go|to|before|left)\b/i;
const BACKWARD = /\b(since|ago)\b/i;

/** A count of days stated rather than asked: "3 days until my exam" says how many, so it is not a question for the app. */
const STATED = /\b(?:\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|few|several)\s+(?:days?|weeks?|months?)\b/i;

function days(asking: Asking, clock: FactClock): Worked | null {
  const words = asking.text;
  if (STATED.test(words)) return null;
  const unitWord = UNIT_WORD.exec(words)?.[1]?.toLowerCase();
  const howLong = /\bhow long (?:until|till|since|ago)\b|\bhow long ago\b/i.test(words);
  const back = BACKWARD.test(words);
  const forward = FORWARD.test(words);
  if (!((unitWord && (back || forward)) || howLong)) return null;
  const today = todayOf(clock.now);
  const found = findDate(words, today);
  if (!found) return unitWord ? cannot('days', 'The app counts days itself, and there is no date here to count to.') : null;
  if ('refuse' in found) return cannot('days', found.refuse);
  const target = placed(found, today, back);
  const unit = unitWord?.startsWith('week') ? 'week' : unitWord?.startsWith('month') ? 'month' : 'day';
  const past = dayNumber(target) < dayNumber(today);
  const working = past ? `From ${longDate(localDate(target))} to today, ${longDate(localDate(today))}. It changes each day.` : `From today, ${longDate(localDate(today))}, to ${longDate(localDate(target))}. It changes each day.`;
  return answered('days', span(today, target, unit), working, 'day');
}

function weekday(asking: Asking, clock: FactClock): Worked | null {
  const words = asking.text;
  const asked = /\b(?:weekday|day of the week|what day)\b/i.test(words) || /\b(?:is|was|falls on) an?\s*$/i.test(asking.label) || /^(?:is|was) an?$/i.test(asking.label);
  if (!asked) return null;
  const today = todayOf(clock.now);
  const found = findDate(words, today);
  if (!found) return null;
  if ('refuse' in found) return cannot('weekday', found.refuse);
  const back = /\bwas\b/i.test(asking.label) && !found.year;
  const day = placed(found, today, back);
  const name = new Intl.DateTimeFormat(undefined, { weekday: 'long' }).format(localDate(day));
  return answered('weekday', name, `${longDate(localDate(day))}.`);
}

const NUMBER_WORDS: Record<string, number> = { a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12 };

function dateOn(asking: Asking, clock: FactClock): Worked | null {
  // Only what is asked: the question, the words before the blank, or the question before an empty one. "I fly out in two
  // days, so pack {?what}" asks what to pack.
  const words = [asking.question, asking.before, asking.prior].filter(Boolean).join(' ');
  const on = /\b(\d{1,4}|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(days?|weeks?|months?|years?)\s+(from|after|before)\s+(.+)$/i.exec(words);
  // "In 3 weeks:" asks for a date only straight before the blank: "I fly out in two days, so pack {?what}" does not.
  const inside = /\bin\s+(\d{1,4}|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(days?|weeks?|months?|years?)(?:'?\s*time)?(?:\s+(?:is|will be|it will be|it is))?\s*:?\s*$/i.exec(`${asking.question} ${asking.before}`.trim());
  const match = on ?? inside;
  if (!match) return null;
  const n = /^\d+$/.test(match[1]!) ? Number(match[1]) : NUMBER_WORDS[match[1]!.toLowerCase()]!;
  const unit = match[2]!.toLowerCase().replace(/s$/, '');
  const today = todayOf(clock.now);
  let base = today;
  let baseWords = `today, ${longDate(localDate(today))}`;
  const sign = on && /before/i.test(on[3]!) ? -1 : 1;
  if (on && !/^(?:today|now)\b/i.test(on[4]!.trim())) {
    const found = findDate(on[4]!, today);
    if (!found) return null;
    if ('refuse' in found) return cannot('dateOn', found.refuse);
    base = placed(found, today, false);
    baseWords = longDate(localDate(base));
  }
  const day = unit === 'day' ? fromNumber(dayNumber(base) + sign * n) : unit === 'week' ? fromNumber(dayNumber(base) + sign * n * 7) : unit === 'month' ? addMonths(base, sign * n) : addMonths(base, sign * n * 12);
  const dayWords = `${n} ${n === 1 ? unit : `${unit}s`}`;
  return answered('dateOn', longDate(localDate(day)), `${capitalFirst(dayWords)} ${sign < 0 ? 'before' : 'from'} ${baseWords}.${base === today ? ' It changes each day.' : ''}`, base === today ? 'day' : null);
}

// ---- units ----------------------------------------------------------------------------------------------------

interface Unit {
  symbol: string;
  kind: 'length' | 'mass' | 'volume' | 'speed' | 'temperature';
  /** How many of the kind's base (a metre, a gram, a millilitre, a km/h) one of it is. */
  factor: number;
  names: string[];
}

const UNITS: Unit[] = [
  { symbol: '°C', kind: 'temperature', factor: 1, names: ['°c', 'celsius', 'centigrade', 'degrees celsius'] },
  { symbol: '°F', kind: 'temperature', factor: 1, names: ['°f', 'fahrenheit', 'degrees fahrenheit'] },
  { symbol: 'mm', kind: 'length', factor: 0.001, names: ['mm', 'millimetre', 'millimetres', 'millimeter', 'millimeters'] },
  { symbol: 'cm', kind: 'length', factor: 0.01, names: ['cm', 'centimetre', 'centimetres', 'centimeter', 'centimeters'] },
  { symbol: 'm', kind: 'length', factor: 1, names: ['m', 'metre', 'metres', 'meter', 'meters'] },
  { symbol: 'km', kind: 'length', factor: 1000, names: ['km', 'kms', 'kilometre', 'kilometres', 'kilometer', 'kilometers'] },
  { symbol: 'in', kind: 'length', factor: 0.0254, names: ['in', 'inch', 'inches'] },
  { symbol: 'ft', kind: 'length', factor: 0.3048, names: ['ft', 'foot', 'feet'] },
  { symbol: 'yd', kind: 'length', factor: 0.9144, names: ['yd', 'yard', 'yards'] },
  { symbol: 'mi', kind: 'length', factor: 1609.344, names: ['mi', 'mile', 'miles'] },
  { symbol: 'g', kind: 'mass', factor: 1, names: ['g', 'gram', 'grams', 'gramme', 'grammes'] },
  { symbol: 'kg', kind: 'mass', factor: 1000, names: ['kg', 'kilo', 'kilos', 'kilogram', 'kilograms'] },
  { symbol: 'oz', kind: 'mass', factor: 28.349523125, names: ['oz', 'ounce', 'ounces'] },
  { symbol: 'lb', kind: 'mass', factor: 453.59237, names: ['lb', 'lbs', 'pound', 'pounds'] },
  { symbol: 'st', kind: 'mass', factor: 6350.29318, names: ['st', 'stone', 'stones'] },
  { symbol: 'ml', kind: 'volume', factor: 1, names: ['ml', 'millilitre', 'millilitres', 'milliliter', 'milliliters'] },
  { symbol: 'l', kind: 'volume', factor: 1000, names: ['l', 'litre', 'litres', 'liter', 'liters'] },
  { symbol: 'tsp', kind: 'volume', factor: 5, names: ['tsp', 'teaspoon', 'teaspoons'] },
  { symbol: 'tbsp', kind: 'volume', factor: 15, names: ['tbsp', 'tablespoon', 'tablespoons'] },
  { symbol: 'km/h', kind: 'speed', factor: 1, names: ['km/h', 'kph', 'kmh', 'kilometres per hour', 'kilometers per hour'] },
  { symbol: 'mph', kind: 'speed', factor: 1.609344, names: ['mph', 'miles per hour'] },
];

/** Names that are everyday words too ("in", "st", "mi"), a unit only straight after a number. */
const AMBIGUOUS = new Set(['in', 'm', 'g', 'l', 'st', 'mi']);

/** A unit by any of its names; `short` also for the names that need a number before them. */
function unitNamed(word: string, short: boolean): Unit | undefined {
  const w = word.toLowerCase().trim();
  return UNITS.find((u) => u.names.includes(w) && (short || !AMBIGUOUS.has(w)));
}

/** Every unit name as one alternation, longest first. */
const UNIT_NAMES = UNITS.flatMap((u) => u.names)
  .sort((a, b) => b.length - a.length)
  .map(escapeRegExp)
  .join('|');

/** A number and a unit straight after it: `180 °C`, `10km`, `2.5 kilos`. */
const MEASURE = new RegExp(String.raw`(\d+(?:[.,]\d+)?)\s*(${UNIT_NAMES})(?![\p{L}])`, 'giu');

function units(asking: Asking): Worked | null {
  const question = asking.question.replace(/[?.!]+$/, '').trim();
  let target = unitNamed(question, true) ?? unitNamed(question.replace(/^(?:in|how many)\s+/i, ''), false);
  if (!target) {
    const afterWord = /^([^\s.,;:!?]+(?:\s+per\s+hour)?)/.exec(asking.after)?.[1] ?? '';
    target = unitNamed(afterWord, false);
  }
  if (!target) {
    const inWords = new RegExp(String.raw`\bin\s+(${UNIT_NAMES})(?![\p{L}])`, 'iu').exec(`${asking.sentence} ${asking.prior}`);
    if (inWords) target = unitNamed(inWords[1]!, false);
  }
  if (!target) return null;
  const source = [...`${asking.sentence} ${asking.prior}`.matchAll(new RegExp(MEASURE.source, 'giu'))]
    .map((m) => ({ value: Number(m[1]!.replace(',', '.')), unit: unitNamed(m[2]!, true) }))
    .find((m) => m.unit && m.unit.symbol !== target!.symbol);
  if (!source?.unit || source.unit.kind !== target.kind) return null;
  const from = source.unit;
  let value: number;
  let working: string;
  if (from.kind === 'temperature') {
    value = from.symbol === '°C' ? (source.value * 9) / 5 + 32 : ((source.value - 32) * 5) / 9;
    working = from.symbol === '°C' ? `${source.value} × 9 ÷ 5 + 32 = ${round(value)}.` : `(${source.value} − 32) × 5 ÷ 9 = ${round(value)}.`;
  } else {
    value = (source.value * from.factor) / target.factor;
    const rate = from.factor / target.factor;
    working = `${source.value} ${from.symbol} × ${round(rate, 4)} = ${round(value)} ${target.symbol}.`;
  }
  return answered('units', `${round(value)} ${target.symbol}`, working);
}

/** A figure worth reading: whole where it is near whole, else to a tenth, or to `places` for a rate. */
function round(value: number, places = 1): string {
  const whole = Math.round(value);
  if (Math.abs(value - whole) < 0.05 && places === 1) return whole.toLocaleString('en-US');
  return (Math.round(value * 10 ** places) / 10 ** places).toLocaleString('en-US', { maximumFractionDigits: places });
}

// ---- the time -------------------------------------------------------------------------------------------------

/** A zone's offset from UTC at a moment, in minutes, as `Intl` reports it: `GMT+9`, `GMT-4`, `GMT+5:30`, `GMT`. */
export function offsetMinutes(zone: string, at: Date): number {
  const name = new Intl.DateTimeFormat('en-US', { timeZone: zone, timeZoneName: 'shortOffset' }).formatToParts(at).find((p) => p.type === 'timeZoneName')?.value ?? 'GMT';
  const found = /GMT([+-])(\d{1,2})(?::(\d{2}))?/.exec(name);
  if (!found) return 0;
  return (found[1] === '-' ? -1 : 1) * (Number(found[2]) * 60 + Number(found[3] ?? 0));
}

/** The known cities a text names, in the order it names them. */
function citiesIn(text: string): string[] {
  const found: { at: number; city: string }[] = [];
  let rest = text;
  for (const city of CITIES) {
    const pattern = new RegExp(String.raw`\b${city.replace(/ /g, '\\s+')}\b`, 'i');
    const match = pattern.exec(rest);
    if (match) {
      found.push({ at: match.index, city });
      rest = `${rest.slice(0, match.index)}${' '.repeat(match[0].length)}${rest.slice(match.index + match[0].length)}`;
    }
  }
  return found.sort((a, b) => a.at - b.at).map((f) => f.city);
}

/** Hours and minutes as a person says them: `8 hours`, `5 hours 30 minutes`. */
function hoursWords(minutes: number): string {
  const whole = Math.floor(Math.abs(minutes) / 60);
  const rest = Math.abs(minutes) % 60;
  return rest ? `${plural(whole, 'hour')} ${plural(rest, 'minute')}` : plural(whole, 'hour');
}

const clockIn = (zone: string, at: Date) => new Intl.DateTimeFormat(undefined, { timeZone: zone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(at);
const weekdayIn = (zone: string, at: Date) => new Intl.DateTimeFormat(undefined, { timeZone: zone, weekday: 'long' }).format(at);
const dayMonth = (at: Date) => new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'long', timeZone: 'UTC' }).format(at);

function time(asking: Asking, clock: FactClock): Worked | null {
  const words = asking.text;
  const clockTime = /\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b/i.exec(words.replace(/\b\d{4}\b/g, ' '));
  const stated = Boolean(clockTime && (clockTime[2] || clockTime[3]));
  if (!stated && !/\b(time|hours?|ahead|behind)\b/i.test(words)) return null;
  const here = clock.zone ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
  const cities = citiesIn(words);
  const difference = /\b(ahead of|behind|difference|hours between|time difference)\b/i.test(words);
  const named = /\btime\s+(?:is\s+it\s+)?in\s+([A-Z][\p{L}'.-]+(?:\s+[A-Z][\p{L}'.-]+)?)/u.exec(words);
  if (named && !cities.length) return cannot('time', `The app knows the time in about sixty cities, and ${named[1]} is not one.`);
  if (difference && cities.length >= 2) {
    const [a, b] = [zoneOf(cities[0]!)!, zoneOf(cities[1]!)!];
    const month = new RegExp(String.raw`\bin\s+(${MONTH})\b`, 'i').exec(words);
    const today = todayOf(clock.now);
    let start = Date.UTC(today.y, today.m, today.d, 12);
    let days = 1;
    if (month) {
      const m = monthOf(month[1]!)!;
      const y = m < today.m ? today.y + 1 : today.y;
      start = Date.UTC(y, m, 1, 12);
      days = new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
    }
    const diffOn = (ms: number) => offsetMinutes(a, new Date(ms)) - offsetMinutes(b, new Date(ms));
    const first = diffOn(start);
    let change: { at: number; diff: number } | null = null;
    for (let d = 1; d < days; d += 1) {
      const at = start + d * 86_400_000;
      if (diffOn(at) !== first) {
        change = { at, diff: diffOn(at) };
        break;
      }
    }
    const ahead = /\bahead of\b/i.test(words);
    const behind = /\bbehind\b/i.test(words);
    const say = (diff: number) => {
      if (!ahead && !behind) return hoursWords(diff);
      const wrongWay = (ahead && diff < 0) || (behind && diff > 0);
      return wrongWay ? `${hoursWords(diff)} ${diff < 0 ? 'behind' : 'ahead'}` : hoursWords(diff);
    };
    const direction = (diff: number) => (diff >= 0 ? 'ahead of' : 'behind');
    if (change) {
      const later = Math.abs(change.diff) / 60;
      const answer = `${say(first)}, ${Number.isInteger(later) ? later : hoursWords(change.diff)} from ${dayMonth(new Date(change.at))}`;
      return answered('time', answer, `${cities[0]} is ${hoursWords(first)} ${direction(first)} ${cities[1]} until ${dayMonth(new Date(change.at))}, then ${hoursWords(change.diff)}. The clocks change then.`);
    }
    return answered('time', say(first), `${cities[0]} is ${hoursWords(first)} ${direction(first)} ${cities[1]}${month ? ` all through ${capitalFirst(month[1]!.toLowerCase())}` : ' today'}.`);
  }
  if (clockTime && stated && cities.length >= 2) {
    let hour = Number(clockTime[1]) % 24;
    if (clockTime[3]?.toLowerCase() === 'pm' && hour < 12) hour += 12;
    if (clockTime[3]?.toLowerCase() === 'am' && hour === 12) hour = 0;
    const minute = Number(clockTime[2] ?? 0);
    const [from, to] = [zoneOf(cities[0]!)!, zoneOf(cities[1]!)!];
    const today = todayOf(clock.now);
    const guess = Date.UTC(today.y, today.m, today.d, hour, minute);
    const at = new Date(guess - offsetMinutes(from, new Date(guess)) * 60_000);
    const there = clockIn(to, at);
    const sameDay = weekdayIn(from, at) === weekdayIn(to, at);
    return answered('time', sameDay ? there : `${there} ${weekdayIn(to, at)}`, `${clockIn(from, at)} in ${cities[0]} is ${there}${sameDay ? '' : ` on ${weekdayIn(to, at)}`} in ${cities[1]}, today.`);
  }
  if (cities.length === 1 && /\b(what time|the time|time in|time is it)\b/i.test(words)) {
    const zone = zoneOf(cities[0]!)!;
    const diff = offsetMinutes(zone, clock.now) - offsetMinutes(here, clock.now);
    const hereName = cityOf(here) ?? 'here';
    const relation = diff === 0 ? `${cities[0]} keeps the same time as ${hereName} today.` : `${cities[0]} is ${hoursWords(diff)} ${diff > 0 ? 'ahead of' : 'behind'} ${hereName} today.`;
    return answered('time', `${clockIn(zone, clock.now)} ${weekdayIn(zone, clock.now)}`, `${relation} It changes each minute.`, 'minute');
  }
  return null;
}
