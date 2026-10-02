import { describe, expect, it } from 'vitest';
import { chaptersOf, isBookBody, isJournalBody } from '../book/book.ts';
import { notebookKey, ticketOf } from './properties.ts';
import { exampleJournal, exampleNotebookBody, exampleTicketBodies } from './starterNotes.ts';

/* The notes a new library starts with (core/starterNotes.ts; docs/DESIGN.md §172): written as the app writes its own. */

describe('the starter examples', () => {
  it('makes a notebook with a ticket key whose index names its three tickets', () => {
    const body = exampleNotebookBody();
    expect(isBookBody(body)).toBe(true);
    expect(notebookKey(body)).toBe('EX');
    expect(chaptersOf(body).map((c) => c.title)).toEqual(['Plan the first release', 'Fix the sign-in loop', 'Write the welcome page']);
    expect(body).toContain('Tap a ticket');
  });

  it('makes three tickets, one in each kind of status, the due days counted from today', () => {
    const tickets = exampleTicketBodies('2026-10-05').map((t) => ticketOf(t.body)!);
    expect(tickets.map((t) => [t.id, t.status, t.category])).toEqual([
      ['EX-1', 'Done', 'done'],
      ['EX-2', 'In progress', 'doing'],
      ['EX-3', 'To do', 'todo'],
    ]);
    expect(tickets.map((t) => t.due)).toEqual([null, '2026-10-07', '2026-10-12']);
    expect(tickets[1]!.assignee).toBe('Sam');
    expect(tickets[2]!.blockedBy).toEqual(['EX-2']);
  });

  it('makes a journal whose index names its first entry, filled from its template', () => {
    const at = new Date(2026, 9, 5, 9, 30);
    const { journal, entry, entryTitle } = exampleJournal(at);
    expect(isJournalBody(journal)).toBe(true);
    expect(chaptersOf(journal).map((c) => c.title)).toEqual([entryTitle]);
    expect(entryTitle).toBe('2026-10-05 09.30');
    expect(entry).toContain('date: 2026-10-05T09:30');
    expect(entry).toContain('The first entry.');
  });
});
