import { planCommand } from '../capture/command.ts';
import { matchNote, type Candidate } from '../capture/route.ts';
import { readArray, locate } from '../review/findings.ts';

/**
 * Where a memo's words go: the pure half of sorting (sort/useSort.ts runs it).
 *
 * Matt: "when I tell it to add a note to a list by a given title I want it to add to that list, but it just gets left
 * on whichever note was last open. Change memo mode to write to a scratch file that's not real until the memo is done,
 * then the AI can figure out how to sort." So a memo is written to a scratch page while it is said, and when it is
 * done each part that belongs in another note is proposed as a placement: what to add, to which note, and the words
 * of the memo it came from. The person keeps or skips each one; whatever isn't placed becomes a new note.
 *
 * Every proposal has to earn its place, as the review's findings do: a note that exists, words that are really in
 * the memo, something to add. A model that invents a note or a quote can't move anything.
 */

export interface Placement {
  id: string;
  noteId: string;
  noteTitle: string;
  /** What goes into the note. */
  text: string;
  /** "leave": into the list it fits, or as a paragraph. "item": always list items. */
  how: 'leave' | 'item';
  task: boolean;
  /** The memo's own words this came from, exactly as they are in it: taken out of what becomes the new note. */
  from: string;
}

const text = (value: unknown) => (typeof value === 'string' ? value.trim() : '');

/**
 * The model's answer as placements. Each item names a note by its title, what to add, and the memo's words it came
 * from. A note that isn't there, words that aren't in the memo, or nothing to add: dropped.
 */
export function readPlacements<N extends Candidate>(answer: string, memo: string, notes: readonly N[]): Placement[] {
  const out: Placement[] = [];
  const seen = new Set<string>();
  readArray(answer).forEach((item, index) => {
    if (!item || typeof item !== 'object') return;
    const raw = item as Record<string, unknown>;
    const named = text(raw.note);
    const add = text(raw.add);
    const quoted = typeof raw.from === 'string' ? raw.from : '';
    if (!named || !add) return;
    const match = matchNote(named, notes, { threshold: 0.72, margin: 0.05 });
    if (!match) return;
    const from = quoted ? locate(memo, quoted) : null;
    if (!from) return;
    const key = `${match.note.id}|${add.toLowerCase()}`;
    if (seen.has(key)) return;
    seen.add(key);
    const how = text(raw.as).toLowerCase() === 'item' || text(raw.as).toLowerCase() === 'task' ? 'item' : 'leave';
    out.push({ id: `p${index}`, noteId: match.note.id, noteTitle: match.note.title, text: add, how, task: text(raw.as).toLowerCase() === 'task', from });
  });
  return out;
}

/** The memo in sentences and lines, each kept exactly as it is written, for the rules to read one at a time. */
export function pieces(memo: string): string[] {
  return memo
    .split('\n')
    .flatMap((line) => line.match(/[^.!?]+[.!?]*/g) ?? [])
    .map((piece) => piece.trim())
    .filter(Boolean);
}

/**
 * Without a model: the commands the rules already understand ("add eggs to groceries", "put call Sam on the work
 * list"), one sentence at a time. Everything else stays for the new note.
 */
export function rulePlacements<N extends Candidate>(memo: string, notes: readonly N[]): Placement[] {
  const out: Placement[] = [];
  pieces(memo).forEach((piece, index) => {
    const words = piece.replace(/^\s*(?:[-*+]\s+(?:\[[ xX]\]\s+)?|#{1,6}\s+|\d+[.)]\s+)/, '');
    const plan = planCommand(words, { notes });
    if (!plan || plan.kind !== 'place' || !plan.text.trim()) return;
    out.push({ id: `r${index}`, noteId: plan.note.id, noteTitle: plan.note.title, text: plan.text.trim(), how: plan.how, task: plan.task, from: piece });
  });
  return out;
}

/**
 * What becomes the new note: the memo with the words of every kept placement taken out, and whatever that leaves
 * empty (a bullet with nothing after it, a run of blank lines) tidied away. Empty when everything was placed.
 */
export function leftover(memo: string, kept: readonly Placement[]): string {
  let body = memo;
  for (const placement of kept) {
    const found = locate(body, placement.from);
    if (!found) continue;
    const at = body.lastIndexOf(found);
    if (at >= 0) body = body.slice(0, at) + body.slice(at + found.length);
  }
  return body
    .split('\n')
    .map((line) => line.replace(/[ \t]+$/, ''))
    .filter((line) => !/^\s*(?:[-*+]|\d+[.)]|[-*+]\s+\[[ xX]\]|#{1,6}|>)\s*$/.test(line))
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}
