import { describe, expect, it } from 'vitest';
import { fieldsOf } from '../../core/taskFields.ts';
import { onlyFields, spokenFields, withSpokenFields } from './fields.ts';

/**
 * A to-do's fields said at its end (capture/spoken/fields.ts): what is read as a due day, a priority or a person, and,
 * as much, what stays words, since a false field takes words out of what someone said. Counted from Thursday 1
 * October 2026.
 */

const TODAY = '2026-10-01';
const read = (words: string) => spokenFields(words, TODAY);
const line = (item: string) => withSpokenFields(item, TODAY);

describe('cues read at the end of an item', () => {
  it('reads a due day after "due"', () => {
    expect(read('Call the plumber due Friday')).toEqual({ words: 'Call the plumber', due: '2026-10-02', priority: null, people: [] });
    expect(read('Send the invoice, due tomorrow.').due).toBe('2026-10-02');
    expect(read('The report is due next week').words).toBe('The report');
    expect(read('Book the venue due the third of October').due).toBe('2026-10-03');
    expect(read('Pay the deposit, due on the 15th').due).toBe('2026-10-15');
  });

  it('reads a priority by its name, by "urgent", and either way round', () => {
    expect(read('Fix the login loop, high priority')).toMatchObject({ words: 'Fix the login loop', priority: 'high' });
    expect(read('Ship the patch top priority').priority).toBe('highest');
    expect(read('Ship the patch, highest priority').priority).toBe('highest');
    expect(read('Tidy the drive, low priority').priority).toBe('low');
    expect(read('Archive the old boards lowest priority').priority).toBe('lowest');
    expect(read('Answer the auditor, it’s a medium-priority')).toMatchObject({ words: 'Answer the auditor', priority: 'medium' });
    expect(read('Answer the auditor, medium priority').priority).toBe('medium');
    expect(read('Renew the passport, priority high').priority).toBe('high');
    expect(read('Renew the passport, urgent')).toMatchObject({ words: 'Renew the passport', priority: 'high' });
    expect(read("Call the bank, it's urgent").priority).toBe('high');
  });

  it('reads a person after "for" or "assigned to"', () => {
    expect(read('Book the venue for Sam')).toMatchObject({ words: 'Book the venue', people: ['Sam'] });
    expect(read('Renew the passport, assigned to Matt').people).toEqual(['Matt']);
    expect(read('Plan the offsite assign it to Sam Ortiz').people).toEqual(['Sam Ortiz']);
    expect(read('Plan the offsite. Assigned to Sam').people).toEqual(['Sam']);
    expect(read('Plan the offsite for sam').people).toEqual([]);
  });

  it('reads them in any order, each kind once', () => {
    expect(read('Fix the login loop, due tomorrow, high priority, for Sam')).toEqual({
      words: 'Fix the login loop',
      due: '2026-10-02',
      priority: 'high',
      people: ['Sam'],
    });
    expect(read('Fix the login loop for Sam, urgent, due Friday')).toEqual({ words: 'Fix the login loop', due: '2026-10-02', priority: 'high', people: ['Sam'] });
    // The second "due" at the end is the field; the first is the item's words.
    expect(read('Move the meeting due Friday due Monday')).toMatchObject({ words: 'Move the meeting due Friday', due: '2026-10-05' });
  });
});

describe('what stays words', () => {
  it('keeps a "due" with no day it can read after it', () => {
    for (const words of ['The rent is due', 'The rent is due soon', 'Check what is due at the end of the month', 'Due Friday the deck is ready'])
      expect(read(words), words).toEqual({ words, due: null, priority: null, people: [] });
  });

  it('keeps a priority said in the middle of an item', () => {
    expect(read('High priority work on the deck').priority).toBeNull();
    expect(read('Ask why it was urgent yesterday').priority).toBeNull();
  });

  it('keeps a "for" that is not who does it', () => {
    for (const words of [
      'Buy a present for Sam',
      'Book flights for Lisbon',
      'Bake a cake for Friday',
      'Set it up for now',
      'Hold the table for Christmas',
      'Talk to Jo for an hour',
      'Plan the budget for Q3',
      'Ask about it for October',
    ])
      expect(read(words).people, words).toEqual([]);
  });

  it('keeps an item that is nothing but a cue', () => {
    expect(line('- [ ] Urgent')).toBe('- [ ] Urgent');
    expect(line('Due tomorrow')).toBe('Due tomorrow');
  });
});

describe('written as the item’s fields', () => {
  it('writes them where Obsidian Tasks reads them, a person before the run', () => {
    expect(line('- [ ] Fix the login loop, due tomorrow, high priority, for Sam')).toBe('- [ ] Fix the login loop @Sam ⏫ 📅 2026-10-02');
    expect(line('- Renew the passport, urgent, assigned to Matt')).toBe('- Renew the passport @Matt ⏫');
    expect(line('- [ ] Plan the offsite for Sam Ortiz')).toBe('- [ ] Plan the offsite @Sam-Ortiz');
  });

  it('writes them on the words alone too, and leaves an item with no cue as it is', () => {
    expect(line('Call the plumber due Friday')).toBe('Call the plumber 📅 2026-10-02');
    expect(line('- [ ] Call the plumber')).toBe('- [ ] Call the plumber');
  });

  it('keeps what the item already has', () => {
    const written = line('- [ ] Call the plumber @matt #home due Friday');
    expect(written).toBe('- [ ] Call the plumber @matt #home 📅 2026-10-02');
    expect(fieldsOf(written)).toMatchObject({ due: '2026-10-02', assignees: ['matt'] });
  });
});

describe('a sentence that is only a field', () => {
  it('is a due day or a priority, but never a person on their own', () => {
    expect(onlyFields('Due Friday.', TODAY)).toBe(true);
    expect(onlyFields('High priority.', TODAY)).toBe(true);
    expect(onlyFields('Urgent, due tomorrow.', TODAY)).toBe(true);
    expect(onlyFields('For Sam.', TODAY)).toBe(false);
    expect(onlyFields('The rent is due.', TODAY)).toBe(false);
    expect(onlyFields('Due soon.', TODAY)).toBe(false);
  });
});
