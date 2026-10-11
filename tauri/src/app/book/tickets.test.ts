import { describe, expect, it } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { DEFAULT_STATUSES, ticketOf } from '../core/properties.ts';
import { bookNoteBody } from './book.ts';
import { firstOpenStatus, keyProblem, newTicketBody, nextTicketId, peopleIn, ticketChoice, ticketFinder, ticketsIn, waitingOn, withNotebookKey } from './tickets.ts';

/**
 * A notebook's tickets across the library (book/tickets.ts; docs/DESIGN.md §157): the key a notebook gives, the next
 * number, the status a new ticket starts in, the notebook a ticket's workflow comes from, the people already named,
 * and what a ticket waits on.
 */

const NOTEBOOK = `---\ntitle: "Ghost.md"\nbook: true\nkey: GHO\n---\n# Ghost.md\n\n- [[Fix the login loop]]\n- [[Fix the session cookie]]\n`;
const ticket = (id: string, title: string, status: string, more = '') => `---\ntype: ticket\nid: ${id}\nstatus: ${status}\n${more}---\n# ${title}\n`;

describe('a notebook’s key', () => {
  it('is set upper case, taken off for nothing, and left alone where it will not do', () => {
    const plain = bookNoteBody('Ghost.md');
    expect(withNotebookKey(plain, ' gho ')).toBe(`---\ntitle: "Ghost.md"\nbook: true\nkey: GHO\n---\n# Ghost.md\n\n`);
    expect(withNotebookKey(withNotebookKey(plain, 'GHO'), 'WEB2')).toContain('key: WEB2');
    expect(withNotebookKey(withNotebookKey(plain, 'GHO'), '')).toBe(plain);
    expect(withNotebookKey(plain, 'G')).toBe(plain);
    expect(withNotebookKey(plain, '12')).toBe(plain);
  });

  it('says what is wrong with a key as it is typed, and nothing for one that will do or for none', () => {
    expect(keyProblem('')).toBeNull();
    expect(keyProblem('gho')).toBeNull();
    expect(keyProblem('WEB2')).toBeNull();
    expect(keyProblem('G')).toBe('Two letters at least, like GHO.');
    expect(keyProblem('2GO')).toBe('A key starts with a letter, like GHO.');
    expect(keyProblem('GH-O')).toBe('Only letters and digits, like GHO or WEB2.');
    expect(keyProblem('ABCDEFGHIJK')).toBe('Ten letters and digits at most.');
  });

  it('numbers the next ticket one past the highest any note names, the Trash’s too, and gives none without a key', () => {
    const bodies = [ticket('GHO-3', 'One', 'Done'), 'see [[GHO-12]] for that', ticket('WEB-40', 'Elsewhere', 'To do')];
    expect(nextTicketId(NOTEBOOK, bodies)).toBe('GHO-13');
    expect(nextTicketId(NOTEBOOK, [])).toBe('GHO-1');
    expect(nextTicketId(bookNoteBody('Plain'), bodies)).toBeNull();
  });
});

describe('a new ticket', () => {
  it('starts To do in the default workflow, after the backlog, and in a notebook’s own first open status', () => {
    expect(firstOpenStatus(DEFAULT_STATUSES)).toBe('To do');
    expect(firstOpenStatus(['Ideas', 'Building', 'Live'])).toBe('Ideas');
    expect(firstOpenStatus(['Backlog', 'Icebox', 'Doing', 'Done'])).toBe('Backlog');
    expect(firstOpenStatus([])).toBe('To do');
  });

  it('is written type, id and status first, then its title as its heading', () => {
    expect(newTicketBody('Fix the login loop', { id: 'GHO-13', statuses: DEFAULT_STATUSES })).toBe('---\ntype: ticket\nid: GHO-13\nstatus: To do\n---\n# Fix the login loop\n\n');
    expect(newTicketBody('No key', { id: null, statuses: ['Ideas', 'Live'] })).toBe('---\ntype: ticket\nstatus: Ideas\n---\n# No key\n\n');
  });

  it('keeps a template’s keys and status where the workflow has it, and moves the status into the workflow where not', () => {
    const words = '---\ntype: ticket\nid: GHO-13\nstatus: To do\npriority: high\n---\n# Login\n\n## Steps to reproduce\n';
    expect(newTicketBody('Login', { id: 'GHO-13', statuses: DEFAULT_STATUSES, words })).toBe(words);
    const moved = newTicketBody('Login', { id: 'GHO-13', statuses: ['Ideas', 'Building', 'Live'], words });
    expect(moved).toBe(words.replace('status: To do', 'status: Ideas'));
    // A template with no id line (it was filled where there was no key) is given the id it is made with.
    expect(newTicketBody('Login', { id: 'GHO-2', statuses: DEFAULT_STATUSES, words: '---\ntype: ticket\nstatus: To do\n---\n# Login\n' })).toContain('id: GHO-2');
  });
});

describe('the library’s tickets', () => {
  const notes = [
    makeNote('book', NOTEBOOK),
    makeNote('loop', ticket('GHO-12', 'Fix the login loop', 'In progress', 'assignee: Sam\nblocked-by: "[[GHO-9]]"\n')),
    makeNote('cookie', ticket('GHO-9', 'Fix the session cookie', 'Building')),
    makeNote('stray', ticket('GHO-20', 'Made from the blank page', 'To do')),
    makeNote('other', ticket('WEB-1', 'Somewhere else', 'Done')),
    makeNote('words', '# Standup\n\n- [ ] Ask @sam about the cookie\n- [ ] Pair with @Priya-Shah\n- email sam@example.com'),
  ];

  it('reads each in its notebook’s workflow, a page of it by its index and any other by its key', () => {
    const withWorkflow = notes.map((note) => (note.id === 'book' ? { ...note, body: NOTEBOOK.replace('key: GHO', 'key: GHO\nstatuses: [Ideas, Building, Live]') } : note));
    const entries = ticketsIn(withWorkflow);
    expect(entries.map((entry) => [entry.ticket.id, entry.notebook?.id ?? null, entry.ticket.category])).toEqual([
      ['GHO-12', 'book', 'doing'],
      ['GHO-9', 'book', 'doing'],
      ['GHO-20', 'book', 'todo'],
      ['WEB-1', null, 'done'],
    ]);
    expect(entries[1]!.statuses).toEqual(['Ideas', 'Building', 'Live']);
    expect(entries[3]!.statuses).toEqual(DEFAULT_STATUSES);
    // A ticket's template page makes tickets and is not one.
    expect(ticketsIn(notes, (note) => note.id === 'stray').map((entry) => entry.note.id)).not.toContain('stray');
  });

  it('finds a ticket by its key in any case, or by its title as a link matches it', () => {
    const find = ticketFinder(ticketsIn(notes));
    expect(find('GHO-9')?.note.id).toBe('cookie');
    expect(find('gho-9')?.note.id).toBe('cookie');
    expect(find('fix the session cookie!')?.note.id).toBe('cookie');
    expect(find('GHO-99')).toBeUndefined();
  });

  it('waits only on what names a ticket that is not done', () => {
    const choices = (from: typeof notes) => {
      const find = ticketFinder(ticketsIn(from));
      return (target: string) => {
        const entry = find(target);
        return entry ? ticketChoice(entry) : null;
      };
    };
    const loop = ticketsIn(notes).find((entry) => entry.note.id === 'loop')!.ticket;
    expect(waitingOn(loop, choices(notes))).toEqual([{ target: 'GHO-9', found: { key: 'GHO-9', title: 'Fix the session cookie', status: 'Building', category: 'doing' } }]);
    const done = notes.map((note) => (note.id === 'cookie' ? { ...note, body: ticket('GHO-9', 'Fix the session cookie', 'Done') } : note));
    expect(waitingOn(loop, choices(done))).toEqual([]);
    expect(waitingOn(ticketOf(ticket('GHO-1', 'A', 'To do', 'blocked-by: "[[GHO-404]]"\n'))!, choices(notes))).toEqual([]);
  });

  it('names the people the library already names, each once, the most named first and as they were written', () => {
    expect(peopleIn(notes)).toEqual(['Sam', 'Priya-Shah']);
    expect(peopleIn([makeNote('a', '---\ntype: ticket\nassignee: Sam Ortiz\n---\n# A'), makeNote('b', 'with @Sam-Ortiz and @sam-ortiz')])).toEqual(['Sam Ortiz']);
    expect(peopleIn([makeNote('c', '`@code` and sam@example.com')])).toEqual([]);
  });
});
