import { dayOfWords } from '../../core/dayWords.ts';
import { listLead } from '../../core/itemSyntax.ts';
import { withAssignee, withField, type PriorityName } from '../../core/taskFields.ts';

/**
 * A to-do's fields, said (docs/DESIGN.md §158): "call the plumber due Friday", "fix the login loop, high priority",
 * "book the venue for Sam". While a list item is being spoken, the words that give it a due day, a priority or a
 * person are taken off its words and written as the field, through the one writer (core/taskFields.ts, §156), so the
 * item reads `- [ ] Call the plumber 📅 2026-10-02` and Obsidian Tasks has its due date:
 *
 *   due Friday, due tomorrow, due next week, due the third of October   📅 and the day (core/dayWords.ts)
 *   high priority, highest priority, top priority, low priority, urgent ⏫ 🔺 🔺 🔽 ⏫
 *   for Sam, assigned to Sam, assign it to Sam Ortiz                     @Sam, @Sam-Ortiz
 *
 * High precision, as every spoken rule is (capture/markdown.ts): a missed field is still words, and a false one
 * takes words away. So a cue is read only at the end of the item, where a field is said last, and any of them in any
 * order ("due Friday, high priority, for Sam"); in the middle of an item they are its words. "Due" needs a day it can
 * read after it, so "the rent is due" stays words. A person needs a capital - Whisper writes a name with one - so
 * "for now" and "for dinner" are words, and not a weekday, a month or a day ("for Friday" is words, since it is when,
 * not who), and "for" after a thing given ("a present for Sam", "flights for Lisbon") is who it is for or where, not
 * who does it. A person is never read from a sentence on its own, only from the end of an item.
 *
 * Pure. `today` is the person's day (core/days.ts), which the caller reads from the clock.
 */

export interface SpokenFields {
  /** The item's words with the cues taken off; '' when it was nothing but cues. */
  words: string;
  due: string | null;
  priority: PriorityName | null;
  /** The people, as said: "Sam", "Sam Ortiz". */
  people: string[];
}

/** What may come between the item's words and a cue: a comma, an "and", an "it's". */
const JOIN = String.raw`(?:^|[\s,;]+)(?:and\s+)?(?:(?:it['’]?s|it\s+is|is|that['’]?s|which\s+is|make\s+it|mark\s+it(?:\s+as)?)\s+)?(?:a\s+)?`;

/** A priority said at the end: "high priority", "priority high", "top priority", "urgent". */
const PRIORITY_WORDS: Record<string, PriorityName> = { highest: 'highest', top: 'highest', high: 'high', medium: 'medium', low: 'low', lowest: 'lowest' };
const PRIORITY_AFTER = new RegExp(String.raw`${JOIN}(highest|top|high|medium|lowest|low)(?:[\s-]+)priority$`, 'i');
const PRIORITY_BEFORE = new RegExp(String.raw`${JOIN}priority[\s,:]+(highest|top|high|medium|lowest|low)$`, 'i');
const URGENT = new RegExp(String.raw`${JOIN}urgent$`, 'i');

/**
 * "For Sam", "assigned to Sam Ortiz", "assign it to Sam": a name of one or two capitalised words at the end. The words
 * before it in either case, as Whisper starts a sentence with a capital; the name only with one.
 */
const PERSON = new RegExp(String.raw`(?:^|[\s,;]+)(?:([Ff]or)|[Aa]ssigned\s+to|[Aa]ssign(?:\s+(?:it|this))?\s+to)\s+(\p{Lu}[\p{L}'’-]+(?:\s+\p{Lu}[\p{L}'’-]+)?)$`, 'u');

/** Capitalised words that are not people: days and months, and what a "for" says about when. */
const NOT_PEOPLE = new Set(
  [
    'monday tuesday wednesday thursday friday saturday sunday',
    'january february march april may june july august september october november december',
    'today tomorrow tonight now later next this that the then me us them everyone everybody all',
    'christmas easter halloween thanksgiving',
  ]
    .join(' ')
    .split(' '),
);

/** Things given or booked: "a present for Sam" is Sam's present, not Sam's to do. */
const GIVEN = new Set(
  'gift gifts present presents card cards cake flowers something anything birthday party dinner lunch breakfast ticket tickets flight flights train trains trip hotel room table visa'.split(
    ' ',
  ),
);

/** The day after "due", at the end: the last "due" whose words after it are all a day. */
function dueAtEnd(text: string, today: string): { at: number; day: string } | null {
  const all = [...text.matchAll(new RegExp(String.raw`${JOIN}due\s+`, 'gi'))];
  for (const found of all.reverse()) {
    const day = dayOfWords(text.slice(found.index + found[0].length), today);
    if (day) return { at: found.index, day };
  }
  return null;
}

/** A priority said at the end, and where its words start. */
function priorityAtEnd(text: string): { at: number; priority: PriorityName } | null {
  const named = PRIORITY_AFTER.exec(text) ?? PRIORITY_BEFORE.exec(text);
  if (named) return { at: named.index, priority: PRIORITY_WORDS[(named[1] ?? '').toLowerCase()] ?? 'high' };
  const urgent = URGENT.exec(text);
  return urgent ? { at: urgent.index, priority: 'high' } : null;
}

/** A person said at the end, and where the words that give them start. */
function personAtEnd(text: string): { at: number; name: string } | null {
  const found = PERSON.exec(text);
  if (!found) return null;
  const name = found[2] ?? '';
  if (name.split(/\s+/).some((word) => NOT_PEOPLE.has(word.toLowerCase()))) return null;
  if (found[1]) {
    const before = /(\p{L}+)[\s,;]*$/u.exec(text.slice(0, found.index))?.[1]?.toLowerCase() ?? '';
    if (GIVEN.has(before)) return null;
  }
  return { at: found.index, name };
}

/**
 * The cues at the end of `said` read off it, last first, in whatever order they were said, each kind once: the item's
 * words before them, and what they set. Words with no cue at their end come back as they are.
 */
export function spokenFields(said: string, today: string): SpokenFields {
  let words = said.replace(/[\s.!?]+$/, '');
  const out: SpokenFields = { words, due: null, priority: null, people: [] };
  for (;;) {
    words = words.replace(/[\s,;:.]+$/, '');
    const due = out.due === null ? dueAtEnd(words, today) : null;
    if (due) {
      out.due = due.day;
      words = words.slice(0, due.at);
      continue;
    }
    const priority = out.priority === null ? priorityAtEnd(words) : null;
    if (priority) {
      out.priority = priority.priority;
      words = words.slice(0, priority.at);
      continue;
    }
    const person = out.people.length === 0 ? personAtEnd(words) : null;
    if (person) {
      out.people.push(person.name);
      words = words.slice(0, person.at);
      continue;
    }
    break;
  }
  out.words = words.replace(/[\s,;:]+$/, '').trim();
  return out;
}

/**
 * Whether a sentence said on its own is nothing but a due day or a priority - "Due Friday.", "High priority." - and
 * so belongs to the item said a breath before it. A person on their own is not: "For Sam." after an item may be who
 * it is for, or the start of something else.
 */
export function onlyFields(sentence: string, today: string): boolean {
  const read = spokenFields(sentence, today);
  return read.words === '' && read.people.length === 0 && (read.due !== null || read.priority !== null);
}

/**
 * An item - its words, or its whole line - with the cues at the end of its words written as its fields. An item that
 * is nothing but cues keeps its words: "Urgent." on its own is a thing said, not an empty to-do.
 */
export function withSpokenFields(item: string, today: string): string {
  const lead = listLead(item);
  const head = lead ? item.slice(0, lead.wordsAt) : '';
  const read = spokenFields(item.slice(head.length), today);
  if (!read.words || (read.due === null && read.priority === null && !read.people.length)) return item;
  let line = `${head}${read.words}`;
  for (const person of read.people) line = withAssignee(line, person);
  if (read.priority) line = withField(line, 'priority', read.priority);
  if (read.due) line = withField(line, 'due', read.due);
  return line;
}
