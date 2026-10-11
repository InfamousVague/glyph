import { lanesOf } from '../core/boards.ts';
import { frontMatterEnd } from '../core/frontMatter.ts';
import { listLead } from '../core/itemSyntax.ts';
import { dice, type Candidate } from './route.ts';

/**
 * The note a spoken name means, read by its words: "house to do's", "the house list", "house chores" and "house" are
 * all House TODOs.
 *
 * Matt, after "add a note to house to do's" made a new note: "The AI should first step try to find a note that the
 * person is talking about … house to do's, house list items, house chores." The letters-first matcher before this
 * (route.ts `similarity`) scored "house chores" 0.5 against House TODOs and "house list items" 0.4, so a command that
 * named a note plainly found none. Here a name is read as two kinds of word:
 *
 * - The distinctive words say which note: "house", "hello trade", "weekend". Every one of them must be in the title
 *   (or begin one of its words, "household" for "house"), and the score is how much of the title they cover.
 * - The kind words say what sort of note it is: to-do, task, chore and job, which are specific, and list, item, stuff,
 *   thing, note and page, which are generic. They never decide which note. A specific one the title shares, or a
 *   generic one where the title or the note's body has a list, backs the match up.
 *
 * One spelling of to-do before anything is compared: "to do's", "to-dos", "todos", "2 dos" and "two dos" are "todo".
 * A name made only of kind words ("my to-do list", "tasks") can only mean a title made only of them too. Letter pairs
 * are the fallback for words run together or split ("hello trade" and HelloTrade), and only between strings of about
 * the same length, so "groceries and eggs" is not Groceries.
 *
 * The answer says how sure it is: `resolved` (one clear note), `current` (the note being written to: "the list",
 * "here", or one of its headings), `unsure` (a few close titles, for a card to choose between) or `missing` (with any
 * titles that come near). Both readers use it: the one that reads a phrase as it is said (liveRoute.ts) and the one
 * that reads the finished recording (command.ts, finalInstruction.ts). Pure, so every name is a test.
 */

/** The bars a name has to clear, in one place (docs/DESIGN.md §126). */
export const FIND = {
  /** The best score this high, and clear of the next by `margin`, is the note. */
  resolved: 0.72,
  margin: 0.08,
  /** Two titles this close to perfect are a tie, whatever the margin. */
  exact: 0.99,
  /** Below `resolved` but this high: unsure, with the titles within `within` of the best. */
  unsure: 0.6,
  within: 0.15,
  /** A title this near a name that matched nothing is offered beside it. */
  near: 0.4,
  /**
   * A note this sure is the one meant with no keyword said, or after a mishearing of it (liveCommand.ts `bareCommand`):
   * the whole of the title's distinctive words. A name that is only the start of a title scores 0.85 (`covered`),
   * which is not clear: "bank" is not Bank statements, "weekend" is not Weekend trip.
   */
  clear: 0.9,
} as const;

/** Kind words that name a kind of list: a to-do list and a chore list are both lists of things to do. */
const SPECIFIC = new Set(['todo', 'task', 'chore', 'job']);
/** Kind words that say only that it is a list, or a note. */
const GENERIC = new Set(['list', 'item', 'stuff', 'thing', 'note', 'page']);
/** Words that carry nothing of a name. */
const STOP = new Set(['the', 'my', 'a', 'an', 'our', 'your', 'and', 'of', 'around']);

/** A name or a title, as its words: all of them, the distinctive ones, and the kind words by kind. */
export interface NameWords {
  words: string[];
  distinctive: string[];
  specific: string[];
  generic: string[];
}

/** Lowercase words, one spelling of to-do, apostrophes and punctuation gone. */
function normalised(text: string): string {
  return text
    .toLowerCase()
    .replace(/[’‘`]/g, "'")
    .replace(/\b(?:to|two|2)[\s-]*do(?:'?s|es)\b/g, ' todos ')
    .replace(/\b(?:to|2)[\s-]*do\b/g, ' todo ')
    .replace(/'/g, '')
    .replace(/[^\p{L}\p{N}\s]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** A plural's s dropped, so "chores" is "chore" and "todos" is "todo". */
function single(word: string): string {
  return word.length > 3 && word.endsWith('s') && !word.endsWith('ss') ? word.slice(0, -1) : word;
}

/** The words of a name or a title, sorted by what they say. */
export function nameWords(text: string): NameWords {
  const words = normalised(text)
    .split(' ')
    .filter((word) => word && !STOP.has(word))
    .map(single);
  return {
    words,
    distinctive: words.filter((word) => !SPECIFIC.has(word) && !GENERIC.has(word)),
    specific: words.filter((word) => SPECIFIC.has(word)),
    generic: words.filter((word) => GENERIC.has(word)),
  };
}

/**
 * The kind of list a title says a note is, by the word it ends on: a to-do list ("House TODOs", "Chores", "Task list"),
 * a plain list ("Groceries", "Packing list"), or neither. Only its last word, which is what a title names: "Task
 * Management" is about tasks, not a list of them.
 */
export function titleKind(title: string): 'task' | 'bullet' | null {
  const { words } = nameWords(title);
  const head = words.at(-1);
  if (head === undefined) return null;
  if (SPECIFIC.has(head)) return 'task';
  if (head === 'list' || head === 'item') return words.slice(0, -1).some((word) => SPECIFIC.has(word)) ? 'task' : 'bullet';
  if (/^(?:grocer(?:y|ie)|shopping)$/.test(head)) return 'bullet';
  return null;
}

/** Whether two words are one: the same, or one the start of the other when both are long ("household", "house"). */
function same(said: string, titled: string): boolean {
  if (said === titled) return true;
  if (Math.min(said.length, titled.length) < 5) return false;
  return titled.startsWith(said) || said.startsWith(titled);
}

/** `words` with any two in a row joined where the other side has them as one word: "hello trade" for HelloTrade. */
function joined(words: readonly string[], other: readonly string[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < words.length; i += 1) {
    const word = words[i] ?? '';
    const next = words[i + 1];
    if (next !== undefined && !other.includes(word) && other.includes(word + next)) {
      out.push(word + next);
      i += 1;
    } else {
      out.push(word);
    }
  }
  return out;
}

/** Letter pairs, spaces gone, only between strings of about the same length. */
function letters(name: NameWords, title: NameWords): number {
  const a = name.words.join('');
  const b = title.words.join('');
  if (!a || !b) return 0;
  const ratio = a.length / b.length;
  if (ratio < 0.8 || ratio > 1.25) return 0;
  return dice(a, b);
}

/** How well the distinctive words `said` cover `titled`, or null when one of them is not in it. */
function covered(said: readonly string[], titled: readonly string[]): { score: number; prefix: boolean } | null {
  const saidWords = joined(said, titled);
  const titleWords = [...new Set(joined(titled, saidWords))];
  if (!saidWords.every((word) => titleWords.some((title) => same(word, title)))) return null;
  const share = titleWords.filter((title) => saidWords.some((word) => same(word, title))).length / titleWords.length;
  // The whole start of the title ("weekend" for Weekend trip to the lake) is a fair pick, a little below an exact one.
  const prefix = saidWords.every((word, i) => titleWords[i] !== undefined && same(word, titleWords[i]!));
  return { score: 0.6 + 0.3 * share, prefix };
}

/**
 * How well a spoken name fits a title, 0 to 1. `hasList` says the note's body keeps a list, which backs up a name
 * that said "list".
 */
export function nameScore(name: NameWords, title: NameWords, { hasList = false }: { hasList?: boolean } = {}): number {
  if (!name.words.length || !title.words.length) return 0;
  if (name.words.join(' ') === title.words.join(' ')) return 1;
  const sharesKind = name.specific.some((kind) => title.specific.includes(kind));
  if (!name.distinctive.length) {
    // Kind words alone: only a title of kind words alone, and a different kind of list is at most a maybe.
    if (title.distinctive.length) return 0;
    if (sharesKind) return 0.9;
    return name.generic.length && (title.specific.length || title.generic.length) ? 0.65 : 0;
  }
  const words = covered(name.distinctive, title.distinctive);
  if (!words) return letters(name, title);
  let score = words.prefix ? Math.max(words.score, 0.85) : words.score;
  if (sharesKind) score += 0.1;
  else if (name.generic.length && (title.specific.length || title.generic.length || hasList)) score += 0.05;
  // Rounded, so a sum of tenths that is 1 compares as 1.
  return Math.min(1, Math.round(score * 1000) / 1000);
}

/** How near a title comes to a name that matched nothing, kind words counted as words: for "No note called …" to offer it. */
function nearScore(name: NameWords, title: NameWords): number {
  const words = covered(name.words, title.words);
  const a = name.words.join('');
  const b = title.words.join('');
  return Math.max(words?.score ?? 0, a && b ? dice(a, b) : 0);
}

/** A list in `body`, after its front matter: any list, or a to-do one. */
function listIn(body: string, todo = false): boolean {
  const lines = body.split('\n');
  return lines.slice(frontMatterEnd(lines)).some((line) => {
    const lead = listLead(line);
    return lead !== null && (!todo || lead.done !== null);
  });
}

/**
 * The headings of a note, fence-aware and after its front matter, with its "Label:" lines and its board's lanes: the
 * places inside it a name can mean. Not the note's own title, which names the note.
 */
export function headingsOf(body: string): string[] {
  const lines = body.split('\n');
  const start = frontMatterEnd(lines);
  const out: string[] = [];
  let fence: string | null = null;
  let titled = false;
  for (let i = start; i < lines.length; i += 1) {
    const line = lines[i] ?? '';
    const marker = /^\s*(`{3,}|~{3,})/.exec(line)?.[1] ?? null;
    if (marker) {
      if (!fence) fence = marker.charAt(0);
      else if (marker.charAt(0) === fence) fence = null;
      continue;
    }
    if (fence || !line.trim()) continue;
    const heading = /^#{1,6}\s+(.+?)\s*#*\s*$/.exec(line);
    if (heading) {
      if (!titled && out.length === 0 && /^#\s/.test(line)) {
        titled = true;
        continue;
      }
      out.push(heading[1]!);
    } else if (/^[^\s:][^:]{0,40}:\s*$/.test(line) && !listLead(line)) {
      out.push(line.trim().replace(/:\s*$/, ''));
    }
    titled = true;
  }
  return [...out, ...lanesOf(body).map((lane) => lane.name)];
}

/**
 * Whether `body` has a heading, a "Label:" line or a lane that `heading` names (`headingsOf`), as surely as a note is
 * found (`FIND.resolved`): "under the sofa" in House TODOs names none, so it is words of the thing, not a place.
 */
export function headingIn(body: string, heading: string): boolean {
  const said = nameWords(heading);
  return headingsOf(body).some((text) => nameScore(said, nameWords(text)) >= FIND.resolved);
}

export type Found<N> =
  /** One clear note. */
  | { status: 'resolved'; note: N; score: number }
  /** The note being written to: "the list", "here", or one of its own headings (`heading`). */
  | { status: 'current'; heading: string | null }
  /** A few titles close together: a card chooses. */
  | { status: 'unsure'; candidates: N[]; score: number }
  /** Nothing clear: `near` are the titles that came closest, if any came near at all. */
  | { status: 'missing'; near: N[] };

/** A name that means the note being written to, whatever it is called. */
const HERE = /^(?:(?:the|this|my)\s+(?:list|note|page)|here|in\s+here|this\s+one)$/i;

/** A spoken name, cleaned for reading: quotes, punctuation and a leading "the", "my" or "our" gone. */
export function spokenName(raw: string): string {
  return raw
    .replace(/[“”"]/g, '')
    .replace(/[.,;:!?]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * The note `raw` names, and how sure that is. `notes` are the candidates, newest first; `aim` is the note being
 * written to, whose own lists and headings a name can mean.
 */
export function findNote<N extends Candidate & { note?: { body: string } }>(
  raw: string,
  notes: readonly N[],
  { aim = null }: { aim?: { id: string; body: string } | null } = {},
): Found<N> {
  const said = spokenName(raw);
  if (HERE.test(said)) return { status: 'current', heading: null };
  const name = nameWords(said);
  if (!name.words.length) return { status: 'missing', near: [] };
  // "My to-do list", "the tasks", said with a note open that has such a list: that note.
  if (aim && !name.distinctive.length && (name.specific.length ? listIn(aim.body, true) : listIn(aim.body))) return { status: 'current', heading: null };

  const ranked = notes
    .filter((note) => note.title.trim())
    .map((note) => ({ note, score: nameScore(name, nameWords(note.title), { hasList: note.note ? listIn(note.note.body) : false }) }))
    .sort((a, b) => b.score - a.score);
  const best = ranked[0];

  // A heading or a lane of the note being written to, named better than any other note: that note, under it.
  if (aim) {
    const heading = headingsOf(aim.body)
      .map((text) => ({ text, score: nameScore(name, nameWords(text)) }))
      .sort((a, b) => b.score - a.score)[0];
    const other = ranked.find((candidate) => candidate.note.id !== aim.id);
    if (heading && heading.score >= FIND.resolved && heading.score > (other?.score ?? 0)) return { status: 'current', heading: heading.text };
  }

  if (!best || best.score < FIND.unsure) {
    const near = notes
      .filter((note) => note.title.trim())
      .map((note) => ({ note, score: nearScore(name, nameWords(note.title)) }))
      .filter((candidate) => candidate.score >= FIND.near)
      .sort((a, b) => b.score - a.score)
      .slice(0, 5)
      .map((candidate) => candidate.note);
    return { status: 'missing', near };
  }
  const exact = ranked.filter((candidate) => candidate.score >= FIND.exact);
  if (exact.length > 1) return { status: 'unsure', candidates: exact.slice(0, 3).map((candidate) => candidate.note), score: best.score };
  const close = ranked.filter((candidate) => best.score - candidate.score < FIND.margin);
  if (best.score >= FIND.resolved && close.length === 1) return { status: 'resolved', note: best.note, score: best.score };
  const within = ranked.filter((candidate) => candidate.score >= FIND.unsure && best.score - candidate.score <= FIND.within);
  return { status: 'unsure', candidates: within.slice(0, 3).map((candidate) => candidate.note), score: best.score };
}
