import { uniqueTitle } from '../book/journal.ts';
import { frontMatterOffset } from '../core/frontMatter.ts';
import { withLook, type Look } from '../core/look.ts';
import { fillTemplate, firstOpenAt } from '../core/template.ts';

/**
 * The templates a new note can start from (docs/DESIGN.md §144). Matt: "When making a new note also offer a few
 * templates to chose from with cards showing how they look (map header, typography focus, etc)", and then where: "cards
 * on the blank page". So a new note's blank page draws a card for each under its names (notes/TemplateCards.tsx), and a
 * card's tap turns the blank note into that template.
 *
 * Six, in code, filled by the journal's own engine (core/template.ts) and nothing else: A day, A meeting, A checklist,
 * Notes on a book, A map at the top (`look: map`) and A page to read (`look: reading`). Each one's shape shows in its
 * first five lines, since a card shows about that many. None writes words in a to-do (an empty box is not a to-do on
 * the home page or under a heading's count), emphasis over a whole line (only Maple Mono has true italics, the others
 * would slant a fake), a spoiler or a text effect (both move, and a card is still), or `{{journal}}`, which is empty in
 * a plain note. `{{title}}` is empty too, since a new note has no name yet: `# {{title}}` is an open heading, where the
 * caret goes, and the editor says `A name` in it (editor/openHeading.ts).
 *
 * A name that is taken gets " (2)", as a journal's entry does: a second A day on a day that has one is
 * `2026-09-28 (2)`, and its card says so before the press. A template never opens another note. And the one rule for
 * the caret and the note's untouched record (core/untouched.ts): fill, settle the name, and only then measure, so the
 * caret after `With ` in a second meeting of a minute lands after it and not four characters early. Pure.
 *
 * And two that make a ticket (docs/DESIGN.md §157, docs/TICKETS.md): a Bug report and a Feature. Their words open with
 * the ticket's own front matter, `type: ticket`, a status, and `id: "{{next-id}}"`, which is the next key of the
 * notebook the note is made in, or no line at all where there is none (core/template.ts). Front matter is not words: the
 * card draws the words after it, the record keeps them, and the caret is measured in them, as a look's key always was.
 */

export type TemplateId = 'day' | 'meeting' | 'checklist' | 'book' | 'map' | 'reading' | 'bug' | 'feature';

export interface NoteTemplate {
  /** A built-in's name for itself, or your own template's page's note id (notes/ownTemplates.ts). */
  id: string;
  /** Which built-in it is, or is still word for word, whose rules it keeps: A day's taken name, a map's place. */
  kind?: TemplateId;
  /** The card's name. */
  name: string;
  /** What it makes, in one fixed sentence, under the name. */
  sentence: string;
  /** Its words, with the placeholders a journal's template takes. */
  words: string;
  /** How a note made from it looks, written into its front matter; null for the usual look. */
  look: Look | null;
}

/**
 * A ticket's front matter as its template writes it: what a new ticket in a notebook starts with (book/tickets.ts
 * `newTicketBody`), the id the notebook's next, and its status the workflow's first open one where the notebook's
 * workflow has no To do (book/tickets.ts `settledStatus`).
 */
const TICKET_KEYS = '---\ntype: ticket\nid: "{{next-id}}"\nstatus: To do\n---\n';

export const BUILT_INS: readonly NoteTemplate[] = [
  { id: 'day', kind: 'day', name: 'A day', sentence: 'Named for today, with a to-do to start.', words: '# {{date:YYYY-MM-DD}}\n\n{{date}}\n\n- [ ] ', look: null },
  {
    id: 'meeting',
    kind: 'meeting',
    name: 'A meeting',
    sentence: 'Named for this minute, with who was there, notes and to-dos.',
    // "Meeting" outside the braces, so its M is not read as a month.
    words: '# Meeting {{date:YYYY-MM-DD HH.mm}}\n\nWith \n\n## Notes\n\n- \n\n## To do\n\n- [ ] ',
    look: null,
  },
  { id: 'checklist', kind: 'checklist', name: 'A checklist', sentence: 'A name to type, then a to-do.', words: '# {{title}}\n\n- [ ] ', look: null },
  { id: 'book', kind: 'book', name: 'Notes on a book', sentence: 'Its title, who wrote it, notes and quotes.', words: '# {{title}}\n\nBy \n\n## Notes\n\n- \n\n## Quotes\n\n> ', look: null },
  { id: 'map', kind: 'map', name: 'A map at the top', sentence: 'Where you are, drawn large above the words.', words: '# {{title}}\n\n{{date}}, {{time}}.\n', look: 'map' },
  { id: 'reading', kind: 'reading', name: 'A page to read', sentence: 'A large title, a lead line and a column set for reading.', words: '# {{title}}\n', look: 'reading' },
  {
    id: 'bug',
    kind: 'bug',
    name: 'Bug report',
    sentence: 'A ticket: how to make it happen, what should, and what did.',
    words: `${TICKET_KEYS}# {{title}}\n\n## Steps to reproduce\n\n1. \n\n## Expected\n\n## Actual\n`,
    look: null,
  },
  {
    id: 'feature',
    kind: 'feature',
    name: 'Feature',
    sentence: 'A ticket: the problem, the proposal, and when it is done.',
    words: `${TICKET_KEYS}# {{title}}\n\n## Problem\n\n## Proposal\n\n## Done when\n\n- [ ] `,
    look: null,
  },
];

/** A day's sentence on a day that already has a note by its name. */
export const DAY_TAKEN_SENTENCE = 'Today has a note by this name. This makes a second.';

/** A template filled for a note made now. */
export interface FilledTemplate {
  /** The words after the front matter, the name settled: what the note's untouched record keeps. */
  words: string;
  /** The whole note, its look in a front matter block of its own where it has one. */
  body: string;
  /** Its name: its heading's words, or empty for an open heading. */
  title: string;
  /** Where the caret goes in `body`: the first line left open. */
  caret: number;
  /** Its name was taken, and it was given " (2)" or the next number free. */
  renamed: boolean;
}

/** The heading a note's words start with, and its words, or null for words that start another way. */
const FIRST_HEADING = /^(#{1,6} +)(.*)$/;

/**
 * `template` filled for a note made at `at`, among notes whose title keys are `taken`: filled, then its name settled,
 * then measured, so the caret and the record are both the final words'. `nextId` is the next ticket key where the note
 * is made (`{{next-id}}`), and `title` the name it is made with, where it has one already (a notebook's new ticket).
 * A template's own front matter is kept in front of the words, never counted among them.
 */
export function fillNoteTemplate(template: NoteTemplate, at: Date, taken: ReadonlySet<string>, { nextId = null, title: given = '' }: { nextId?: string | null; title?: string } = {}): FilledTemplate {
  const filled = fillTemplate(template.words, { at, nextId, title: given });
  const start = frontMatterOffset(filled);
  const front = filled.slice(0, start);
  let words = filled.slice(start);
  const newline = words.indexOf('\n');
  const first = newline < 0 ? words : words.slice(0, newline);
  const heading = FIRST_HEADING.exec(first);
  const named = heading?.[2]?.trim() ?? '';
  let title = named;
  if (heading && named) {
    title = uniqueTitle(named, taken);
    if (title !== named) words = `${heading[1]}${title}${newline < 0 ? '' : words.slice(newline)}`;
  }
  const body = template.look ? withLook(front + words, template.look) : front + words;
  return { words, body, title, caret: frontMatterOffset(body) + firstOpenAt(words), renamed: title !== named };
}
