import { frontMatterValue } from '../core/frontMatter.ts';
import { noteTitle } from '../core/noteTitle.ts';
import {
  issueKeyOf,
  nextIssueId,
  notebookKey,
  PROJECT_KEY,
  statusCategory,
  statusesOf,
  ticketIdOf,
  ticketOf,
  withProperty,
  type StatusCategory,
  type Ticket,
} from '../core/properties.ts';
import type { Note } from '../core/store.ts';
import { fieldsIn, personKey } from '../core/taskFields.ts';
import { titleKey } from '../core/titleKey.ts';
import { bookIndex, isBookBody, placeOf } from './book.ts';

/**
 * A notebook's tickets: the library-wide half of tickets as notes (Matt asked what Notion- and Jira-like features custom
 * Markdown could give the app, "like tickets and such", and then "Do 1, 2 and 3 in parallel"; docs/DESIGN.md §157,
 * docs/TICKETS.md). What one ticket's front matter says is core/properties.ts, the grammar the three features share
 * (§156); this is what needs the other notes: which notebook a ticket is in and so which workflow its status moves
 * through, the key the next one gets, the people the library already names, which tickets a ticket waits on, and the
 * ticket a `[[GHO-12]]` means.
 *
 * A notebook gives its tickets a key, `key: GHO`, and every new ticket in it is `GHO-` and the next number, as Jira
 * numbers a project's issues. Nothing stores the number: it is one more than the highest any note still names
 * (core/properties.ts `nextIssueId`), read across the whole library and the Trash, so a ticket deleted and restored
 * never meets a second of its number. The notebook may name its own workflow, `statuses: [Ideas, Building, Live]`, and
 * a ticket's status is placed in it; a ticket in no notebook, or in one that names none, moves through the default.
 *
 * A ticket is in a notebook as any page is, by a line of its index; one made elsewhere with a notebook's key (a Bug
 * report from the blank page, a ticket Claude wrote) is that notebook's by its key, so its status still reads by that
 * notebook's workflow.
 *
 * Pure: it imports nothing that draws or stores, so the MCP server can find a ticket by its key as the app does, and
 * every rule here is a test (book/tickets.test.ts).
 */

// ---- the notebook's key --------------------------------------------------------------------------

/**
 * What is wrong with a key as typed in the notebook's settings, in a sentence; null for a key that will do, or for
 * nothing typed, which takes the key off.
 */
export function keyProblem(typed: string): string | null {
  const key = typed.trim().toUpperCase();
  if (!key || PROJECT_KEY.test(key)) return null;
  if (!/^[A-Z]/.test(key)) return 'A key starts with a letter, like GHO.';
  if (/[^A-Z0-9]/.test(key)) return 'Only letters and digits, like GHO or WEB2.';
  return key.length < 2 ? 'Two letters at least, like GHO.' : 'Ten letters and digits at most.';
}

/** The notebook with its key set, upper case, or taken off for nothing typed; a key that will not do leaves it as it was. */
export function withNotebookKey(body: string, typed: string): string {
  const key = typed.trim().toUpperCase();
  if (!key) return withProperty(body, 'key', null);
  return PROJECT_KEY.test(key) ? withProperty(body, 'key', key) : body;
}

/**
 * The key the notebook's next ticket gets, `GHO-13`, among `bodies`: every note there is, archived and in the Trash
 * too, so no number is given twice. Null for a notebook with no key.
 */
export function nextTicketId(notebook: string, bodies: readonly string[]): string | null {
  const key = notebookKey(notebook);
  return key ? nextIssueId(key, bodies) : null;
}

// ---- statuses ------------------------------------------------------------------------------------

/** Statuses a new ticket waits in rather than starts in: a backlog is where a ticket goes when it is not yet to do. */
const WAITING = new Set(['backlog', 'icebox', 'triage', 'inbox', 'later', 'someday']);

/**
 * The status a new ticket starts in: the workflow's first that is not started and not a waiting room, To do in the
 * default, after Backlog; `[Ideas, Building, Live]` starts in Ideas. A workflow whose open statuses are all waiting
 * rooms starts in its first.
 */
export function firstOpenStatus(statuses: readonly string[]): string {
  const open = statuses.find((status) => statusCategory(status, statuses) === 'todo' && !WAITING.has(status.trim().toLowerCase()));
  return open ?? statuses[0] ?? 'To do';
}

/** Whether `status` is one of the workflow's, compared as a person would say it. */
function inWorkflow(status: string, statuses: readonly string[]): boolean {
  return statuses.some((each) => each.trim().toLowerCase() === status.trim().toLowerCase());
}

/**
 * A new ticket's body as it is written: `type: ticket`, its id where there is one to give, and a status in the
 * workflow it is made in. `words` is what it starts with: a ticket's template, filled (notes/noteTemplates.ts), whose
 * status stands where the workflow has it and is the workflow's first open one where it has not; or, absent, the title
 * as its heading. Keys the template wrote stay as it wrote them.
 */
export function newTicketBody(title: string, { id, statuses, words }: { id: string | null; statuses: readonly string[]; words?: string }): string {
  let body = words ?? `# ${title.trim()}\n\n`;
  if (frontMatterValue(body, 'type')?.trim().toLowerCase() !== 'ticket') body = withProperty(body, 'type', 'ticket');
  if (id && !ticketIdOf(body)) body = withProperty(body, 'id', id);
  const status = frontMatterValue(body, 'status')?.trim() ?? '';
  if (!status || !inWorkflow(status, statuses)) body = withProperty(body, 'status', firstOpenStatus(statuses));
  return body;
}

// ---- the library's tickets -------------------------------------------------------------------------

/** A ticket in the library: its note, its title, what its front matter says, and the notebook whose workflow it moves through. */
export interface TicketEntry {
  note: Note;
  title: string;
  ticket: Ticket;
  /** Its notebook's workflow, or the default. */
  statuses: string[];
  /** The notebook it is a page of, or whose key it carries; null for neither. */
  notebook: Note | null;
}

/**
 * The notebook a note is in, by the notes it is among: the one whose index lists it (book/book.ts `placeOf`), else, for
 * a ticket, the one whose key its id carries. Built once for a library, asked once per note.
 */
export function notebookFinder(notes: readonly Note[]): (note: Note) => Note | null {
  const index = bookIndex(notes);
  const keyed = new Map<string, Note>();
  for (const note of notes) {
    if (!isBookBody(note.body)) continue;
    const key = notebookKey(note.body);
    if (key && !keyed.has(key)) keyed.set(key, note);
  }
  return (note) => {
    const place = placeOf(index, note);
    if (place) return place.book;
    const id = ticketIdOf(note.body);
    return id ? (keyed.get(id.slice(0, id.lastIndexOf('-'))) ?? null) : null;
  };
}

/**
 * Every ticket among `notes`, in the order given, each read in its notebook's workflow. `skip` leaves notes out that
 * are tickets in shape only: a ticket's template page (notes/ownTemplates.ts) makes tickets and is not one.
 */
export function ticketsIn(notes: readonly Note[], skip: (note: Note) => boolean = () => false): TicketEntry[] {
  const notebookOf = notebookFinder(notes);
  const entries: TicketEntry[] = [];
  for (const note of notes) {
    if (skip(note) || isBookBody(note.body) || !ticketOf(note.body)) continue;
    const notebook = notebookOf(note);
    const statuses = statusesOf(notebook?.body);
    entries.push({ note, title: noteTitle(note.body), ticket: ticketOf(note.body, statuses)!, statuses, notebook });
  }
  return entries;
}

/** A ticket as a picker and a key's title show it: its key, its title, and where its status stands. */
export interface TicketChoice {
  key: string | null;
  title: string;
  status: string | null;
  category: StatusCategory;
}

/** An entry as a picker shows it. */
export function ticketChoice(entry: TicketEntry): TicketChoice {
  return { key: entry.ticket.id, title: entry.title, status: entry.ticket.status, category: entry.ticket.category };
}

/**
 * What a `[[link]]` or a `blocked-by:` names, found: the ticket with that key in any case (`[[gho-12]]`), else the
 * ticket with that title as a link matches it. Undefined for neither. The first of two with one key, as a list reads.
 */
export function ticketFinder(entries: readonly TicketEntry[]): (target: string) => TicketEntry | undefined {
  const byKey = new Map<string, TicketEntry>();
  const byTitle = new Map<string, TicketEntry>();
  for (const entry of entries) {
    if (entry.ticket.id && !byKey.has(entry.ticket.id)) byKey.set(entry.ticket.id, entry);
    const key = titleKey(entry.title);
    if (key && !byTitle.has(key)) byTitle.set(key, entry);
  }
  return (target) => {
    const key = issueKeyOf(target);
    return (key ? byKey.get(key) : undefined) ?? byTitle.get(titleKey(target));
  };
}

/** One ticket's wait on another: what its `blocked-by:` names, and the ticket that is. */
export interface Wait<T> {
  target: string;
  found: T;
}

/**
 * What a ticket waits on that is not finished: each `blocked-by:` that names a ticket whose status is not done, by
 * `find` (`ticketFinder`, or the screen's own lookup). A target that names no ticket is not a wait, since nothing can
 * say it is done; the panel still lists it under Blocked by.
 */
export function waitingOn<T extends { category: StatusCategory }>(ticket: Ticket, find: (target: string) => T | null | undefined): Wait<T>[] {
  const waits: Wait<T>[] = [];
  for (const target of ticket.blockedBy) {
    const found = find(target);
    if (found && found.category !== 'done') waits.push({ target, found });
  }
  return waits;
}

// ---- people --------------------------------------------------------------------------------------

/**
 * The people the library already names, the most named first: every ticket's `assignee:` and every `@person` in the
 * words of a note (core/taskFields.ts), each person once however they are written (`@sam`, "Sam"). A name is shown
 * as it was written most, an assignee's spelling before a handle's, so "Sam Ortiz" rather than `Sam-Ortiz`. What the
 * Assignee picker offers before anything is typed.
 */
export function peopleIn(notes: readonly Pick<Note, 'body'>[]): string[] {
  const counts = new Map<string, { count: number; names: Map<string, number> }>();
  const meet = (name: string, weight: number) => {
    const clean = name.trim().replace(/^@+/, '');
    const key = personKey(clean);
    if (!key) return;
    const person = counts.get(key) ?? { count: 0, names: new Map<string, number>() };
    person.count += 1;
    person.names.set(clean, (person.names.get(clean) ?? 0) + weight);
    counts.set(key, person);
  };
  for (const note of notes) {
    const assignee = frontMatterValue(note.body, 'assignee');
    if (assignee) meet(assignee, 2);
    if (!note.body.includes('@')) continue;
    for (const field of fieldsIn(note.body)) if (field.kind === 'person') meet(field.value, 1);
  }
  return [...counts.values()]
    .map(({ count, names }) => ({ count, name: [...names.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]![0] }))
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name))
    .map((person) => person.name);
}
