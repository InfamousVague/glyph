import { frontMatterEnd } from './frontMatter.ts';
import { mathsIn } from './maths.ts';

/**
 * Blanks the AI fills: a question in curly brackets where its answer belongs (docs/DESIGN.md §145).
 *
 * Matt: "Add an option as well for the users to be able to put special syntax in a note that allows the AI to fill
 * context make a few different scenarios like "flights are cheapest to Tokyo on [[what day / time?]]" Then the AI fills
 * in the squares with the factual response using the phones local AI model". He chose `{?question}` over his own
 * `[[…]]`, which is a note link today (editor/wikiLinks.ts) and a tap on it makes a note.
 *
 *   Flights are cheapest to Tokyo on {?what day / time?}
 *   The capital of Australia is {?}.          an empty blank reads the sentence it sits in
 *   \{?not a blank}                           written about, not asked: a backslash before the bracket
 *
 * The characters are plain text everywhere else: Obsidian, GitHub and Pandoc show them as typed. The editor draws one
 * as a square (editor/blanks.ts), and this module is the part with no editor: the pattern, the reader for places that
 * have no parser (the title, the gist, home's to-dos, the item text sent to Notion and GitHub, search, the MCP), the
 * words a blank asks with, and the form an answer takes in the file.
 *
 * An answer from the model is an Unsure mark whose bracket says where it came from, which the app hides and a tap
 * shows (editor/markNotes.ts, editor/fillPanel.ts):
 *
 *   ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)
 *
 * Imports only the front matter rule and maths, so the MCP server bundles the same code the app runs.
 */

/**
 * `{?what day}`: not `{{?…}}` (the journal's and the templates' family), not after a backslash, not after a `$`
 * (`${?HOME}`, a config file's optional value), not `{??…` (an Unsure mark someone put in braces), no `|` in the
 * question (a table's cell edge), at most 160 characters, one line.
 */
export const BLANK = /(?<![{\\$])\{\?(?!\?)([^{}|\n]{0,160})\}(?!\})/g;

/** What the setup and the Guide show a blank as, so a change of syntax reaches them. */
export const BLANK_SAMPLE = '{?a question}';

/** One blank in a note's text. */
export interface Blank {
  /** The opening `{`. */
  from: number;
  /** Just after the closing `}`. */
  to: number;
  /** The question inside, spaces either side taken off; empty for `{?}`. */
  question: string;
}

/** Every match of the pattern in `text`, with no regard to where it sits: the editor filters these by its own parse. */
export function blankMatches(text: string, offset = 0): Blank[] {
  const found: Blank[] = [];
  const pattern = new RegExp(BLANK.source, 'g');
  for (let match = pattern.exec(text); match; match = pattern.exec(text)) {
    found.push({ from: offset + match.index, to: offset + match.index + match[0].length, question: (match[1] ?? '').trim() });
  }
  return found;
}

// ---- the pure reader ---------------------------------------------------------------------------------------

/** A code fence's opening or closing line, three backticks or tildes, as editor/lines.ts reads one. */
const CODE_FENCE = /^\s*(```|~~~)/;
/** An HTML comment, over any number of lines. */
const COMMENT = /<!--[\s\S]*?-->/g;
/** An HTML tag's own text: `<span title="…">`, `</div>`. */
const TAG = /<\/?[A-Za-z][^<>\n]*>/g;
/** A link's or a picture's address, and an autolink. */
const ADDRESS = /\]\([^)\n]*\)|<(?:https?:|mailto:|geo:)[^<>\s]*>/g;
/** A note link's title: a blank there would be filled into the link's target (`[[Trip to {?capital}]]`), so it is text. */
export const WIKI_LINK = /\[\[[^\]\n]*\]\]/g;

/**
 * Where the words are quiet for a blank, away from the editor: front matter, fenced code, code spans, comments, HTML
 * tags, maths and link addresses. The editor asks its parser instead (editor/blanks.ts `editorBlanks`), and a test runs
 * both over one corpus and names where they differ (an indented code block, an HTML block over several lines), where
 * the only cost is a word in a title or a gist, since a fill is only ever started from the editor's list.
 */
export function quietRanges(text: string): { from: number; to: number }[] {
  const quiet: { from: number; to: number }[] = [];
  const lines = text.split('\n');
  let at = 0;
  const front = frontMatterEnd(lines);
  let fence: string | null = null;
  lines.forEach((line, index) => {
    const start = at;
    at += line.length + 1;
    if (index < front) {
      quiet.push({ from: start, to: start + line.length });
      return;
    }
    const marker = CODE_FENCE.exec(line)?.[1];
    if (marker) {
      fence = fence === null ? marker : fence === marker ? null : fence;
      quiet.push({ from: start, to: start + line.length });
      return;
    }
    if (fence) {
      quiet.push({ from: start, to: start + line.length });
      return;
    }
    quiet.push(...codeSpans(line, start));
    for (const pattern of [TAG, ADDRESS, WIKI_LINK]) {
      const found = new RegExp(pattern.source, 'g');
      for (let match = found.exec(line); match; match = found.exec(line)) quiet.push({ from: start + match.index, to: start + match.index + match[0].length });
    }
    quiet.push(...mathsIn(line, start));
  });
  for (let match = COMMENT.exec(text); match; match = COMMENT.exec(text)) quiet.push({ from: match.index, to: match.index + match[0].length });
  COMMENT.lastIndex = 0;
  return quiet;
}

/** A line's code spans: a run of backticks, then the next run of exactly as many, as CommonMark pairs them. */
function codeSpans(line: string, offset: number): { from: number; to: number }[] {
  const spans: { from: number; to: number }[] = [];
  const runs = [...line.matchAll(/`+/g)].map((m) => ({ at: m.index, size: m[0].length }));
  for (let i = 0; i < runs.length; i += 1) {
    const open = runs[i]!;
    const close = runs.findIndex((run, j) => j > i && run.size === open.size);
    if (close < 0) continue;
    spans.push({ from: offset + open.at, to: offset + runs[close]!.at + open.size });
    i = close;
  }
  return spans;
}

/**
 * The blanks in a note's text, as the places with no editor read them: every match of the pattern that does not
 * start in quiet words (`quietRanges`). The front matter's own lines are quiet, so its keys never hold a blank.
 */
export function blanksIn(text: string, offset = 0): Blank[] {
  const quiet = quietRanges(text);
  return blankMatches(text).filter((blank) => !quiet.some((q) => blank.from >= q.from && blank.from < q.to)).map((b) => ({ ...b, from: b.from + offset, to: b.to + offset }));
}

/** Whether `text` has a blank anywhere a reader would find one. Cheap when it has no `{?` at all. */
export function hasBlank(text: string): boolean {
  return text.includes('{?') && blanksIn(text).length > 0;
}

/**
 * A blank's identity across the note being closed and opened: its question and its order among the blanks with that
 * same question, counted in the note's order (docs/DESIGN.md §145, 1.6).
 */
export function orderOf(blanks: readonly Blank[], blank: Blank): number {
  return blanks.filter((b) => b.question === blank.question && b.from < blank.from).length;
}

/** The blank with this question and order, as `orderOf` counts them, or null. */
export function findBlank(blanks: readonly Blank[], question: string, order: number): Blank | null {
  return blanks.filter((b) => b.question === question)[order] ?? null;
}

// ---- the words a blank asks with ------------------------------------------------------------------------------

/** What a blank asks, as the solvers, the live screen and the shapes read it. */
export interface Asking {
  /** The question in the braces. */
  question: string;
  /** The blank's own sentence with the blank taken out, on its line only. */
  sentence: string;
  /** The words of that sentence straight before the blank: at most five words. */
  label: string;
  /** Every word of that sentence before the blank. */
  before: string;
  /** The words of that sentence straight after it. */
  after: string;
  /**
   * The sentence before, read only when the blank's own sentence is the blank alone or a label (`A: {?}`): before it
   * on its line, else the last sentence of the line above, one empty line between passed over. Empty otherwise.
   */
  prior: string;
  /** All of the above that count, as one run of words: what the word screens read. */
  text: string;
}

/** A sentence ends at `.`, `?` or `!` before a space or the line's end. */
const SENTENCE_END = /[.?!]+(?=\s|$)/g;

/** The sentences of a line, as spans; blanks must already be masked so their question marks end nothing. */
function sentences(line: string): { from: number; to: number }[] {
  const spans: { from: number; to: number }[] = [];
  let start = 0;
  const pattern = new RegExp(SENTENCE_END.source, 'g');
  for (let match = pattern.exec(line); match; match = pattern.exec(line)) {
    const end = match.index + match[0].length;
    spans.push({ from: start, to: end });
    start = end;
  }
  if (start < line.length) spans.push({ from: start, to: line.length });
  return spans;
}

/** Words that are letters or digits: a label's `→` or a list's dash is not a word. */
function wordsOf(text: string): string[] {
  return text.split(/\s+/).filter((w) => /[\p{L}\p{N}]/u.test(w));
}

/** A sentence that is only a label: at most two words, the last ending in a colon (`A:`, `Answer:`). */
function isLabel(text: string): boolean {
  const words = wordsOf(text);
  if (!words.length) return true;
  return words.length <= 2 && /:$/.test(text.trim());
}

/** The line with every blank in it masked, so a question's `?` ends no sentence. Offsets are kept. */
function masked(line: string): string {
  return line.replace(new RegExp(BLANK.source, 'g'), (whole) => '\uE000'.repeat(whole.length));
}

/** Words for reading: masks gone, list leads and quote marks off, spaces closed. */
function tidyWords(text: string): string {
  return text
    .replace(/\uE000+/g, ' ')
    .replace(/^\s*(?:>\s*)*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?/, '')
    .replace(/^\s*#{1,6}\s+/, '')
    .replace(/\s+/g, ' ')
    .replace(/\s+([.,;:!?])/g, '$1')
    .trim();
}

/**
 * The words a blank asks with (docs/DESIGN.md §145, 2.1): its question, its own sentence, and, when that sentence is
 * the blank alone or a label, the sentence before it. So `How many days until Christmas? {?}` is read as that
 * question, and the note idiom `Q: Who won the 2026 World Cup?` then `A: {?}` is read as its Q.
 */
export function askingWords(blank: Blank, text: string): Asking {
  const lineStart = text.lastIndexOf('\n', blank.from - 1) + 1;
  const lineEndAt = text.indexOf('\n', blank.to);
  const line = text.slice(lineStart, lineEndAt === -1 ? text.length : lineEndAt);
  const mask = masked(line);
  const at = blank.from - lineStart;
  const spans = sentences(mask);
  const own = spans.find((s) => at >= s.from && at < s.to) ?? { from: 0, to: mask.length };
  const beforeBlank = mask.slice(own.from, at);
  const afterBlank = mask.slice(at + (blank.to - blank.from), own.to);
  const sentence = tidyWords(`${beforeBlank} ${afterBlank}`);
  const label = wordsOf(tidyWords(beforeBlank)).slice(-5).join(' ');
  const after = tidyWords(afterBlank);
  let prior = '';
  if (isLabel(tidyWords(beforeBlank)) && !wordsOf(after).length) {
    const earlier = spans.filter((s) => s.to <= own.from && wordsOf(tidyWords(mask.slice(s.from, s.to))).length);
    const last = earlier[earlier.length - 1];
    if (last) prior = tidyWords(mask.slice(last.from, last.to));
    else prior = lastSentenceAbove(text, lineStart);
  }
  const words = [blank.question, sentence, prior].filter(Boolean).join(' ');
  return { question: blank.question, sentence, label, before: tidyWords(beforeBlank), after, prior, text: words };
}

/** The last sentence of the line above `lineStart`, one empty line between passed over. */
function lastSentenceAbove(text: string, lineStart: number): string {
  if (lineStart === 0) return '';
  const lines = text.slice(0, lineStart - 1).split('\n');
  let above = lines[lines.length - 1] ?? '';
  if (!above.trim() && lines.length > 1) above = lines[lines.length - 2] ?? '';
  if (!above.trim()) return '';
  const mask = masked(above);
  const spans = sentences(mask).filter((s) => wordsOf(tidyWords(mask.slice(s.from, s.to))).length);
  const last = spans[spans.length - 1];
  return last ? tidyWords(mask.slice(last.from, last.to)) : '';
}

// ---- the answer in the file --------------------------------------------------------------------------------

/**
 * A filled blank's bracket: whose answer, from where, when, what was asked, and an item's place. "From the web" names
 * its source: `Qwen3.5 4B from Open-Meteo, 2026-09-28`, the page having asked that source (ai/fills/web.ts).
 */
export const FILLED = /^(.+?) from (memory|this note|[A-Z][\w.-]*(?: and [A-Z][\w.-]*)?), (\d{4}-\d{2}-\d{2})(?:\. Asked: (.+?))?(?:\. (\d) of (\d))?$/;

/** Where an answer came from. */
export type FillSource = { kind: 'memory' } | { kind: 'note' } | { kind: 'web'; name: string };

export interface Filled {
  /** The model's name as the app shows it, or Claude's. */
  model: string;
  source: FillSource;
  /** ISO, `2026-09-28`. */
  date: string;
  /** What was asked, or null for an empty blank. */
  question: string | null;
  /** An item's place among the items of one fill: `2 of 3`. */
  place: { n: number; of: number } | null;
}

/** A bracket read as a fill's, or null for a person's own note on an Unsure mark. */
export function readFilled(bracket: string): Filled | null {
  const found = FILLED.exec(bracket.trim());
  if (!found) return null;
  const from = found[2] ?? '';
  const source: FillSource = from === 'memory' ? { kind: 'memory' } : from === 'this note' ? { kind: 'note' } : { kind: 'web', name: from };
  return {
    model: found[1] ?? '',
    source,
    date: found[3] ?? '',
    question: found[4] ?? null,
    place: found[5] && found[6] ? { n: Number(found[5]), of: Number(found[6]) } : null,
  };
}

/** The words a source is written as in the bracket. */
function sourceWords(source: FillSource): string {
  if (source.kind === 'memory') return 'from memory';
  if (source.kind === 'note') return 'from this note';
  return `from ${source.name}`;
}

/** A question as a bracket may hold it: no brackets of its own, no `??`, and no ending the place pattern would read. */
function bracketQuestion(question: string): string {
  return question
    .replace(/\(/g, '[')
    .replace(/\)/g, ']')
    .replace(/\?{2,}/g, '?')
    .replace(/\n/g, ' ')
    .replace(/\.(\s*\d of \d)$/, ',$1')
    .trim();
}

/**
 * An answer written as the mark the parser really reads (docs/DESIGN.md §145, 6.1). The parser refuses a delimiter
 * with another piece of itself either side (editor/language.ts), and a mark's note ends at its first `)`
 * (editor/markNotes.ts). So a trailing `?` goes after the bracket, a `??` inside becomes `?`, a question's brackets
 * are square, and a `?` straight before the blank (`before`) gets a space after it.
 */
export function filledMark(
  answer: string,
  meta: { model: string; source: FillSource; date: string },
  question: string,
  before = '',
  place: { n: number; of: number } | null = null,
): string {
  let words = answer.replace(/\s+/g, ' ').trim().replace(/\?{2,}/g, '?').replace(/^\?+\s*/, '');
  let trail = '';
  const ending = /\?+$/.exec(words);
  if (ending) {
    trail = '?';
    words = words.slice(0, ending.index).trimEnd();
  }
  const asked = bracketQuestion(question);
  const bracket = `${meta.model} ${sourceWords(meta.source)}, ${meta.date}${asked ? `. Asked: ${asked}` : ''}${place && place.of > 1 ? `. ${place.n} of ${place.of}` : ''}`;
  const lead = before.endsWith('?') ? ' ' : '';
  return `${lead}??${words}??(${bracket})${trail}`;
}

/** An Unsure mark with a note: `??words??(note)`. The words need a word against each `??`, as the parser's rule does. */
const NOTED = /\?\?(?=\S)((?:(?!\?\?).)*?\S)\?\?\(([^)\n]+)\)/g;

/** Every filled answer in `text`: the mark's span, its words, and its bracket read. */
export function fillsIn(text: string, offset = 0): { from: number; to: number; words: string; filled: Filled; bracket: string }[] {
  if (!text.includes('??(')) return [];
  const found: { from: number; to: number; words: string; filled: Filled; bracket: string }[] = [];
  const pattern = new RegExp(NOTED.source, 'g');
  for (let match = pattern.exec(text); match; match = pattern.exec(text)) {
    const filled = readFilled(match[2] ?? '');
    if (filled) found.push({ from: offset + match.index, to: offset + match.index + match[0].length, words: match[1] ?? '', filled, bracket: match[2] ?? '' });
  }
  return found;
}

/**
 * The text with every filled answer read as its words alone: what every reader but the editor sees (the title,
 * home's to-dos, the item text sent to Notion and GitHub, search, the gist). A person's own note on an Unsure mark is
 * left as it is. Costs nothing on text with no `??(` in it.
 */
export function plainFills(text: string): string {
  if (!text.includes('??(')) return text;
  return text.replace(new RegExp(NOTED.source, 'g'), (whole, words: string, bracket: string) => (readFilled(bracket) ? words : whole));
}

// ---- titles -------------------------------------------------------------------------------------------------

/** A question that asks for a title: `title`, `a name`, `name this`, `what to call this`. */
const ASKS_TITLE = /^(?:a |the )?(?:title|name|heading)(?: (?:this|it|for this|for it))?$|^(?:title|name) (?:this|it)$|^what to call (?:this|it)$/i;

/** Whether a blank's question asks for a title: empty, or one of the few ways people ask for one. */
export function asksForTitle(question: string): boolean {
  const words = question.trim().replace(/[?.!]+$/, '').trim();
  return words === '' || ASKS_TITLE.test(words);
}

/**
 * A note's first line as its title reads it (docs/DESIGN.md §145, 8): a filled answer as its words, a blank that is
 * the whole line as nothing when it asks for a title (the note is untitled until it fills) or as its question's words
 * otherwise, and a blank among other words left out with the spaces closed up. The heading's `#` stays for the title
 * rule to take off (core/noteTitle.ts).
 */
export function titleWords(line: string): string {
  let text = plainFills(line);
  if (!text.includes('{?')) return text;
  const lead = /^\s*(?:#{1,6}\s+)?/.exec(text)?.[0] ?? '';
  const rest = text.slice(lead.length);
  const whole = new RegExp(`^${BLANK.source}\\s*$`).exec(rest.trim());
  if (whole) {
    const question = (whole[1] ?? '').trim();
    return asksForTitle(question) ? lead.replace(/#{1,6}\s+$/, '').trimEnd() : `${lead}${question}`;
  }
  text = text.replace(new RegExp(BLANK.source, 'g'), '');
  return text.replace(/[ \t]{2,}/g, ' ').replace(/\s+$/, '');
}

/**
 * The text with its blanks taken out and its fills read as words: what the gist gives the smallest model
 * (format/gist.ts), which is never handed a blank to answer, and whose one line never shows braces or a bracket.
 */
export function withoutBlanks(text: string): string {
  const plain = plainFills(text);
  if (!plain.includes('{?')) return plain;
  return plain.replace(new RegExp(BLANK.source, 'g'), '').replace(/[ \t]{2,}/g, ' ');
}

/**
 * An item's or a card's words as a reader shows them: filled answers as their words, and a blank as its question's
 * words, since a to-do holding a blank is a question and is shown as one (home's To do).
 */
export function readableWords(text: string): string {
  const plain = plainFills(text);
  if (!plain.includes('{?')) return plain;
  return plain.replace(new RegExp(BLANK.source, 'g'), (_, question: string) => question.trim()).replace(/\s{2,}/g, ' ');
}
