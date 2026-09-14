import { describe, expect, it } from 'vitest';
import { parseSend, parseTaskNote } from './voice.ts';

describe('Notion by voice', () => {
  it('hears "send that to Notion" on its own and at the end of a phrase', () => {
    expect(parseSend('Send that to Notion.')).toEqual({ rest: '' });
    expect(parseSend('Book the cabin, send this to Notion')).toEqual({ rest: 'Book the cabin' });
    expect(parseSend('Make it a task in Notion.')).toEqual({ rest: '' });
  });

  it('hears a note for a Notion task', () => {
    expect(parseTaskNote('Add a note for the Notion task for fix the login bug.')).toEqual({ name: 'fix the login bug' });
    expect(parseTaskNote('Notes on the Notion task called dark mode.')).toEqual({ name: 'dark mode' });
    expect(parseTaskNote('Add a note for the Notion task for fix login.')).toEqual({ name: 'fix login' });
  });

  it('leaves sentences about Notion alone', () => {
    expect(parseSend('I used Notion for the backlog last year.')).toBeNull();
    expect(parseTaskNote('I used Notion for the backlog last year.')).toBeNull();
    expect(parseSend('We should send the invoice to Sam.')).toBeNull();
  });
});
