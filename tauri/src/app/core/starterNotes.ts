import { bookNoteBody } from '../book/book.ts';
import { DEFAULT_TEMPLATE, entryBody, entryTitle, journalNoteBody, localStamp, withEntry } from '../book/journal.ts';
import { newTicketBody, withNotebookKey } from '../book/tickets.ts';
import { isoDay, isoDayAfter } from './days.ts';
import { DEFAULT_STATUSES, withProperty } from './properties.ts';
import { fillTemplate } from './template.ts';

/**
 * The notes a new library starts with, beside the sample note (core/sampleNote.ts) and the example board
 * (core/boardNote.ts): a notebook of three tickets and a journal with its first entry (docs/DESIGN.md §172). Matt: "pre
 * populate new accounts with an example board, example tickets (3) example journal and an example with all the
 * formatting". Each is what the app itself writes when a person makes one - a notebook with a ticket key, tickets with
 * their front matter, a journal and an entry named by the minute - so they open, change and sync like anything made by
 * hand, and deleting them takes nothing else with them. Pure: the moment is given.
 */

export const EXAMPLE_NOTEBOOK = 'Example project';
export const EXAMPLE_KEY = 'EX';
export const EXAMPLE_JOURNAL = 'Journal';

/** One of the example tickets: its title, where it stands, and the words under its heading. */
interface ExampleTicket {
  title: string;
  status: string;
  priority: string;
  assignee: string | null;
  /** Days from today to its due day; null for none. */
  due: number | null;
  /** Another ticket it waits on, by key. */
  blockedBy?: string;
  words: string;
}

const TICKETS: readonly ExampleTicket[] = [
  {
    title: 'Plan the first release',
    status: 'Done',
    priority: 'high',
    assignee: 'Alex',
    due: null,
    words: 'What goes in the first release, and what waits for the second.\n\n- [x] List what the release needs\n- [x] Cut what can wait\n',
  },
  {
    title: 'Fix the sign-in loop',
    status: 'In progress',
    priority: 'highest',
    assignee: 'Sam',
    due: 2,
    words:
      'Signing in on the phone sends you back to the sign-in page once the cookie has expired.\n\nA ticket is a note: its properties are the panel above, kept in the note’s front matter. Tap a value to change it.\n\n- [ ] Write the failing test\n- [ ] Refresh the token once, not twice\n',
  },
  {
    title: 'Write the welcome page',
    status: 'To do',
    priority: 'medium',
    assignee: null,
    due: 7,
    blockedBy: 'EX-2',
    words: 'The first page a new person sees. It waits on EX-2, and says so with a lock until that is done.\n\n- [ ] Draft the words\n- [ ] Pick a picture\n',
  },
];

/** The example notebook: a ticket key, so its pages are tickets numbered EX-1 to EX-3, and its index. */
export function exampleNotebookBody(): string {
  const body = withNotebookKey(
    bookNoteBody(
      EXAMPLE_NOTEBOOK,
      TICKETS.map((ticket) => ticket.title),
    ),
    EXAMPLE_KEY,
  );
  // A sentence over the index, where a notebook keeps its words (book/book.ts `bookWords`).
  const heading = `# ${EXAMPLE_NOTEBOOK}\n\n`;
  return body.replace(
    heading,
    `${heading}A notebook with a ticket key: every page made from New ticket is a ticket, numbered ${EXAMPLE_KEY}-1, ${EXAMPLE_KEY}-2 and on. Tap a ticket's status to move it along.\n\n`,
  );
}

/** The three example tickets, EX-1 to EX-3, as they are written, in the notebook's order. */
export function exampleTicketBodies(today: string): { title: string; body: string }[] {
  return TICKETS.map((ticket, i) => {
    let body = newTicketBody(ticket.title, { id: `${EXAMPLE_KEY}-${i + 1}`, statuses: DEFAULT_STATUSES, words: `# ${ticket.title}\n\n${ticket.words}` });
    body = withProperty(body, 'status', ticket.status);
    if (ticket.assignee) body = withProperty(body, 'assignee', ticket.assignee);
    body = withProperty(body, 'priority', ticket.priority);
    const due = ticket.due === null ? null : isoDayAfter(today, ticket.due);
    if (due) body = withProperty(body, 'due', due);
    if (ticket.blockedBy) body = withProperty(body, 'blocked-by', `[[${ticket.blockedBy}]]`);
    return { title: ticket.title, body };
  });
}

/** The example journal and its first entry, written at `at`, as New entry writes them (App.tsx `newEntry`). */
export function exampleJournal(at: Date): { journal: string; entry: string; entryTitle: string } {
  const title = entryTitle(at.getTime());
  const filled = fillTemplate(DEFAULT_TEMPLATE, { at, title, journal: EXAMPLE_JOURNAL });
  const words = `${filled}The first entry. A journal keeps one for each time you write, named by the minute, and its page lists them by day. New entry starts the next from the journal's template.\n`;
  return {
    journal: withEntry(journalNoteBody(EXAMPLE_JOURNAL, DEFAULT_TEMPLATE, false), title),
    entry: entryBody(title, localStamp(at.getTime()), words),
    entryTitle: title,
  };
}

/** Today, as the examples count due days from. */
export const todayFor = (at: Date) => isoDay(at);
