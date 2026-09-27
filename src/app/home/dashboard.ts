import { isBookBody } from '../book/book.ts';
import { itemOnLine, itemWords } from '../core/boards.ts';
import { taskBox } from '../core/itemSyntax.ts';
import type { SummariesState, SummaryKind } from '../ai/summaries.ts';
import type { Note } from '../core/store.ts';
import { guidePages, isGuideBook } from '../guidebook/guidebook.ts';
import { hasTape } from '../notes/allNotes.ts';

/**
 * What the home page gathers from the notes (home/HomeScreen.tsx): the pinned ones, the tapes on the shelf, the ones
 * touched last, every to-do not yet ticked, wherever it was written, and the digest line under the date that says
 * what is waiting (docs/DESIGN.md §132). Pure, so each rule is a test rather than a page to look at.
 */

/** Pinned notes, newest first. The archive is never on the home page. */
export function pinnedNotes(notes: readonly Note[]): Note[] {
  return notes.filter((n) => n.starred && !n.archivedAt).sort((a, b) => b.updatedAt - a.updatedAt);
}

/** The books (docs/BOOKS.md), newest change first, for the home page's Library. The archive stays out. */
export function bookNotes(notes: readonly Note[]): Note[] {
  return notes.filter((n) => !n.archivedAt && isBookBody(n.body)).sort((a, b) => b.updatedAt - a.updatedAt);
}

/** The meetings, by note id, from the preferences (core/preferences.ts `meetings`): which notes are meetings. */
export type Meetings = Readonly<Record<string, number>>;

/**
 * A tape: a note with a recording that the recorder made (`source: 'capture'`), or a meeting (docs/DESIGN.md §127).
 * A note that was written and then talked into is a note, not a tape: it keeps its card in Recent, with the tape's
 * counter in its foot (notes/NoteCard.tsx). The one predicate for the shelf and for Recent, so nothing shows twice;
 * whether a note has a tape at all is All notes' `hasTape`, the one way that is written.
 */
export function isTape(note: Note, meetings: Meetings): boolean {
  return !note.archivedAt && hasTape(note) && (note.source === 'capture' || note.id in meetings);
}

/**
 * Which write-up the queue is asked for from the home page's Summarize (home/TapeShelf.tsx, ai/summaries.ts): a
 * meeting's for a note in the meetings map, a recording's otherwise. The kind is the prompt's, so the page asks for
 * the tape's real one rather than calling every tape a recording.
 */
export function summaryKindOf(note: Note, meetings: Meetings): SummaryKind {
  return note.id in meetings ? 'meeting' : 'recording';
}

/**
 * The shelf of tapes on the home page (home/TapeShelf.tsx; Matt: "display them in a cassette shelf on the home
 * page"): every tape, the Guide's pages out, the last recorded first. By `createdAt`, which is how a shelf of tapes
 * reads: a summary or the better words landing later bumps `updatedAt` and must not move a tape along the row. A
 * pinned tape is here as well as in Pinned, since pinning is a deliberate act.
 */
export function tapedNotes(notes: readonly Note[], meetings: Meetings): Note[] {
  const guide = guidePages(notes);
  return notes.filter((n) => isTape(n, meetings) && !guide.has(n.id)).sort((a, b) => b.createdAt - a.createdAt);
}

/**
 * The notes touched last: pinned ones, books and tapes left to their own rows so nothing shows twice, and the Guide's
 * pages out. What the shelf takes is exactly what this leaves out (`isTape`).
 */
export function recentNotes(notes: readonly Note[], count: number, meetings: Meetings): Note[] {
  const guide = guidePages(notes);
  return notes
    .filter((n) => !n.starred && !n.archivedAt && !isBookBody(n.body) && !guide.has(n.id) && !isTape(n, meetings))
    .sort((a, b) => b.updatedAt - a.updatedAt)
    .slice(0, count);
}

export interface OpenTask {
  noteId: string;
  /** The line it is on, counting from 0, which is what ticking it rewrites. */
  line: number;
  text: string;
  /** Its anchor (core/boards.ts), when it has one: opening the note lands on it. */
  at?: string;
  /** When its note was touched, which orders the list: what was being worked on comes first. */
  touched: number;
}

/** A to-do with its box still empty: `- [ ] words`, `* [ ]`, `1. [ ]` (core/itemSyntax.ts `taskBox`). */
function isOpen(line: string): boolean {
  return taskBox(line)?.done === false;
}
/** A to-do with its box ticked and words after it: `- [x] words`. */
function isTicked(line: string): boolean {
  const box = taskBox(line);
  return box?.done === true && /\S/.test(line.slice(box.at + 3));
}
/** A code fence opening or closing: a to-do inside one is an example of a to-do, not one. */
const FENCE = /^\s*(`{3,}|~{3,})/;

/** Every unticked to-do in the notes, the most recently touched note's first, in the order each note has them. */
export function openTasks(notes: readonly Note[]): OpenTask[] {
  const tasks: OpenTask[] = [];
  const guide = guidePages(notes);
  for (const note of [...notes].filter((n) => !n.archivedAt && !guide.has(n.id)).sort((a, b) => b.updatedAt - a.updatedAt)) {
    let fenced = false;
    note.body.split('\n').forEach((line, index) => {
      if (FENCE.test(line)) {
        fenced = !fenced;
        return;
      }
      if (fenced || !isOpen(line)) return;
      const text = itemWords(line)?.trim();
      if (!text) return;
      tasks.push({ noteId: note.id, line: index, text, at: itemOnLine(line)?.id, touched: note.updatedAt });
    });
  }
  return tasks;
}

/** Midnight at the start of the local day `now` is in. */
export function startOfToday(now = Date.now()): number {
  const day = new Date(now);
  day.setHours(0, 0, 0, 0);
  return day.getTime();
}

/**
 * How many of the notes were touched since the local day began, out of the archive and the Guide, its pages and its
 * book alike (the day the manual is added it is the newest note there is, and not one the person touched): the
 * digest's "N notes touched today". Every kind of note counts, pinned, tape and book as much as a plain one, which is
 * why the phrase is said and goes nowhere: the notes it counts are all over the page, and Recent holds four of one kind.
 */
export function touchedToday(notes: readonly Note[], now = Date.now()): number {
  const since = startOfToday(now);
  const guide = guidePages(notes);
  return notes.filter((n) => !n.archivedAt && !guide.has(n.id) && !isGuideBook(n) && n.updatedAt >= since).length;
}

/** What is waiting on the tapes, from the queues the shelf already reads (home/tapeCaption.ts). */
export interface Waiting {
  /** The better words or a summary on their way, on the page or natively. */
  working: number;
  /** Jobs that wait for a language model not on the phone. */
  needsModel: number;
  /** Summaries the queue gave up on. */
  failed: number;
}

/**
 * The tapes something is happening to, counted once each in the caption's own order: working before needing a model
 * before failed, so a tape that is both is counted where its caption says it is.
 */
export function tapesWaiting(tapes: readonly Note[], sources: { refining: ReadonlySet<string>; summaries: SummariesState }): Waiting {
  const { refining, summaries } = sources;
  const waiting: Waiting = { working: 0, needsModel: 0, failed: 0 };
  for (const { id } of tapes) {
    if (refining.has(id) || summaries.native.has(id) || summaries.pending.has(id)) waiting.working += 1;
    else if (summaries.needsModel.has(id)) waiting.needsModel += 1;
    else if (summaries.failed.has(id)) waiting.failed += 1;
  }
  return waiting;
}

/** Where a digest phrase goes: a group on the page, or Settings › Formatting for a missing model. */
export type DigestGo = 'tasks' | 'tapes' | 'model';

export interface DigestPhrase {
  text: string;
  /** Null for a phrase that is only said: the quiet one, and the day's count, whose notes are all over the page. */
  go: DigestGo | null;
}

/**
 * The digest's phrases in order, each with where it goes, so the copy is a test and not a page to read: only the
 * phrases that are true, and "Nothing waiting on you" first when none of the waiting ones are. No full stops: the
 * digest is a row of fragments, like "All notes · 41".
 */
export function digest(facts: { open: number; waiting: Waiting; touched: number }): DigestPhrase[] {
  const { open, waiting, touched } = facts;
  const phrases: DigestPhrase[] = [];
  if (open) phrases.push({ text: `${open} to-do${open === 1 ? '' : 's'} open`, go: 'tasks' });
  if (waiting.working) phrases.push({ text: `Working on ${waiting.working} tape${waiting.working === 1 ? '' : 's'}`, go: 'tapes' });
  if (waiting.needsModel) phrases.push({ text: waiting.needsModel === 1 ? '1 tape needs a model' : `${waiting.needsModel} tapes need a model`, go: 'model' });
  if (waiting.failed) phrases.push({ text: waiting.failed === 1 ? '1 summary didn’t come' : `${waiting.failed} summaries didn’t come`, go: 'tapes' });
  if (!phrases.length) phrases.push({ text: 'Nothing waiting on you', go: null });
  if (touched) phrases.push({ text: `${touched} note${touched === 1 ? '' : 's'} touched today`, go: null });
  return phrases;
}

/**
 * How many to-dos are ticked in the notes, outside code fences, the archive and the Guide's pages: with none left open, a page that had
 * to-dos says they are all done (the ghost on the home page), and a page that never had any says nothing.
 */
export function tickedTasks(notes: readonly Note[]): number {
  let count = 0;
  const guide = guidePages(notes);
  for (const note of notes) {
    if (note.archivedAt || guide.has(note.id)) continue;
    let fenced = false;
    for (const line of note.body.split('\n')) {
      if (FENCE.test(line)) fenced = !fenced;
      else if (!fenced && isTicked(line)) count += 1;
    }
  }
  return count;
}
