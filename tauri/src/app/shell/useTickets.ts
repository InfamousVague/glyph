import { useMemo, useRef } from 'react';
import { nextTicketId, notebookFinder, peopleIn, ticketChoice, ticketFinder, ticketsIn, type TicketEntry } from '../book/tickets.ts';
import { isTicket, statusesOf } from '../core/properties.ts';
import type { Note } from '../core/store.ts';
import type { TicketOptions } from '../editor/tickets.ts';
import { BUILT_INS, type NoteTemplate } from '../notes/noteTemplates.ts';
import { isTemplatePageBody } from '../notes/ownTemplates.ts';

/**
 * The library's tickets as the app hands them round (docs/DESIGN.md §157; Matt picked tickets as notes, "Do 1, 2 and 3
 * in parallel"): read once per change to the notes, as the titles a link finds are (App.tsx `byTitle`), and not once a
 * draw. What the open note's panel and its `[[GHO-12]]`s are drawn with (editor/tickets.ts `TicketOptions`): the
 * workflow of the notebook it is in, the people the library names (read the first time the Assignee picker asks), the
 * other tickets, the ticket a key or a title names, and the key a ticket with none would get from its notebook, read
 * across `all`, the Trash's notes too, so no number is given twice. And the templates New ticket offers
 * (`ticketTemplatesOf`).
 *
 * A ticket's template page makes tickets and is not one, so it is no ticket here: no key resolves to it, no picker
 * offers it.
 */
export interface Tickets {
  /** Every ticket in the library, each in its notebook's workflow. */
  entries: TicketEntry[];
  /** For the note on screen; absent with none. */
  options: TicketOptions | undefined;
}

/**
 * `notes` are the library a screen sees, `all` every note the store has; `shown` the open note's id; `open` opens a
 * ticket by its key or title.
 */
export function useTickets(notes: readonly Note[], all: readonly Note[], shown: string | null, open: (target: string) => void): Tickets {
  const entries = useMemo(() => ticketsIn(notes, (note) => isTemplatePageBody(note.body)), [notes]);
  const find = useMemo(() => ticketFinder(entries), [entries]);
  const notebookOf = useMemo(() => notebookFinder(notes), [notes]);
  // Read the first time a picker asks, and again only after the notes change.
  const people = useMemo(() => {
    let read: string[] | null = null;
    return () => (read ??= peopleIn(notes));
  }, [notes]);
  // Opening is App's and changes with every draw; the options keep one identity while the notes do.
  const opening = useRef(open);
  opening.current = open;
  const options = useMemo((): TicketOptions | undefined => {
    if (!shown) return undefined;
    const note = notes.find((each) => each.id === shown);
    const notebook = note ? notebookOf(note) : null;
    const statuses = statusesOf(notebook?.body);
    return {
      statuses: () => statuses,
      nextId: () => (notebook ? nextTicketId(notebook.body, all.map((each) => each.body)) : null),
      people,
      choices: () => entries.filter((entry) => entry.note.id !== shown).map(ticketChoice),
      find: (target) => {
        const entry = find(target);
        return entry ? ticketChoice(entry) : null;
      },
      open: (target) => opening.current(target),
    };
  }, [shown, notes, all, notebookOf, people, entries, find]);
  return { entries, options };
}

/** What New ticket can start from: the templates that make a ticket, your own where you keep them, else Bug report and Feature. */
export function ticketTemplatesOf(own: readonly NoteTemplate[] | null): NoteTemplate[] {
  return (own ?? BUILT_INS).filter((template) => isTicket(template.words));
}
