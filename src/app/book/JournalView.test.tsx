import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { makeNote } from '../../test/notes.ts';
import { button, rerender, show } from '../../test/render.tsx';
import { inLocale } from '../../test/locale.ts';
import type { Note } from '../core/store.ts';
import { titleKey } from '../core/titleKey.ts';
import { bookOf, chaptersOf } from './book.ts';
import { BookBar, BookFoot } from './BookNav.tsx';
import { DEFAULT_TEMPLATE, entryBody, journalNoteBody, PRESETS, withEntry } from './journal.ts';
import { inTimeOrder } from './journalMonths.ts';
import { JournalView } from './JournalView.tsx';
import { entryStarts, startLine } from './entryStarts.ts';

/**
 * A journal drawn: New entry, its entries newest first by month with the older months folded, a row said whole, the
 * pages planned and not written, and a year that draws a few months, not every day. And the bar and the foot an
 * entry wears, which walk the entries in the order they were written.
 */

/** An entry written at that wall clock, with those words, named by the minute. */
function entryAt(y: number, m: number, d: number, h: number, min: number, words = 'Words.'): Note {
  const two = (n: number) => String(n).padStart(2, '0');
  const title = `${y}-${two(m)}-${two(d)} ${two(h)}.${two(min)}`;
  return makeNote(`e-${title}`, entryBody(title, `${y}-${two(m)}-${two(d)}T${two(h)}:${two(min)}`, `# Day\n\n**${two(h)}:${two(min)}** ${words}`), { createdAt: Date.UTC(y, m - 1, d) });
}

/** A journal indexing these notes in the order given, and a lookup for them. */
function journalOf(entries: readonly Note[], extra: readonly string[] = []): { body: string; noteOf: (title: string) => Note | undefined } {
  let body = journalNoteBody('Diary', DEFAULT_TEMPLATE, false);
  const titles = entries.map((note) => chaptersOf(`---\nbook: true\n---\n- [[${note.body.match(/title: "([^"]+)"/)![1]}]]`)[0]!.title);
  for (const title of [...titles, ...extra]) body = withEntry(body, title);
  const map = new Map(entries.map((note, i) => [titleKey(titles[i]!), note]));
  return { body, noteOf: (title) => map.get(titleKey(title)) };
}

const monthNames = () => [...document.querySelectorAll('h2')].map((h) => h.textContent);
const entryLabels = () => [...document.querySelectorAll<HTMLButtonElement>('ol button[aria-label]')].map((b) => b.getAttribute('aria-label'));

describe('a journal drawn', () => {
  it('lists its entries newest first by when each was written, a month at a time, whatever the index’s order', () => {
    const { body, noteOf } = journalOf([entryAt(2026, 9, 27, 21, 40, 'Dinner with Sam.'), entryAt(2026, 8, 30, 10, 0), entryAt(2026, 9, 28, 14, 5, 'Walked along the river.'), entryAt(2026, 9, 28, 8, 10)]);
    const open = vi.fn();
    show(<JournalView body={body} noteOf={noteOf} known={() => true} open={open} onChange={() => {}} />);
    expect(monthNames()).toEqual(['September 2026', 'August 2026']);
    expect(entryLabels().map((label) => label!.split('.')[0])).toEqual(['Monday, September 28, 14:05', 'Monday, September 28, 08:10', 'Sunday, September 27, 21:40', 'Sunday, August 30, 10:00']);
    act(() => button(entryLabels()[0]!).click());
    expect(open).toHaveBeenCalledWith('2026-09-28 14.05');
  });

  it('says a row whole for a screen reader, and shows the day, the time and how the entry starts', () => {
    const { body, noteOf } = journalOf([entryAt(2026, 9, 28, 14, 5, 'Walked along the river after lunch.')]);
    show(<JournalView body={body} noteOf={noteOf} known={() => true} open={() => {}} onChange={() => {}} />);
    const row = document.querySelector('ol button')!;
    expect(row.getAttribute('aria-label')).toMatch(/^Monday, September 28, 14:05\. Walked along the river after lunch\.$/);
    expect(row.textContent).toBe('28Mon14:05Walked along the river after lunch.');
  });

  it('opens the three newest months and folds the rest to a row each, which a tap opens in place', () => {
    const entries = [1, 2, 3, 4, 5].map((month) => entryAt(2026, month, 15, 9, 0));
    const { body, noteOf } = journalOf(entries);
    show(<JournalView body={body} noteOf={noteOf} known={() => true} open={() => {}} onChange={() => {}} />);
    expect(monthNames()).toEqual(['May 2026', 'April 2026', 'March 2026']);
    const folded = [...document.querySelectorAll('button')].filter((b) => /2026 · \d/.test(b.textContent ?? ''));
    expect(folded.map((b) => b.textContent)).toEqual(['February 2026 · 1', 'January 2026 · 1']);
    act(() => folded[1]!.click());
    expect(monthNames()).toEqual(['May 2026', 'April 2026', 'March 2026', 'January 2026']);
  });

  it('draws a year of entries as a few months of rows, not a row a day', () => {
    const entries: Note[] = [];
    for (let day = 0; day < 365; day += 1) {
      const at = new Date(Date.UTC(2026, 0, 1 + day));
      entries.push(entryAt(at.getUTCFullYear(), at.getUTCMonth() + 1, at.getUTCDate(), 8, 0));
    }
    const { body, noteOf } = journalOf(entries);
    show(<JournalView body={body} noteOf={noteOf} known={() => true} open={() => {}} onChange={() => {}} />);
    expect(document.querySelectorAll('button').length).toBeLessThan(120);
    expect(monthNames()).toEqual(['December 2026', 'November 2026', 'October 2026']);
  });

  it('lists a page planned and not written apart, with its cross, and leaves out an entry’s line with no note', () => {
    const { body, noteOf } = journalOf([entryAt(2026, 9, 28, 14, 5)], ['Packing list', '2026-09-27 09.00']);
    const onChange = vi.fn();
    const open = vi.fn();
    show(<JournalView body={body} noteOf={noteOf} known={() => true} open={open} onChange={onChange} />);
    expect(monthNames()).toEqual(['September 2026', 'Not written yet']);
    expect(document.body.textContent).not.toContain('2026-09-27 09.00');
    act(() => button('Packing list, not written yet').click());
    expect(open).toHaveBeenCalledWith('Packing list');
    act(() => button('Take Packing list out of the journal').click());
    expect(chaptersOf(onChange.mock.calls[0]![0] as string).map((c) => c.title)).toEqual(['2026-09-28 14.05', '2026-09-27 09.00']);
  });

  it('draws a row again when its entry changes, though the journal’s own words did not', () => {
    const first = entryAt(2026, 9, 28, 14, 5, 'Walked.');
    const { body } = journalOf([first]);
    let now = first;
    const view = () => <JournalView body={body} noteOf={() => now} known={() => true} open={() => {}} onChange={() => {}} />;
    show(view());
    expect(document.querySelector('ol button')!.textContent).toContain('Walked.');
    now = { ...first, body: first.body.replace('Walked.', 'Walked along the river.'), updatedAt: first.updatedAt + 1 };
    rerender(view());
    expect(document.querySelector('ol button')!.textContent).toContain('Walked along the river.');
  });

  it('has one action, New entry, only where one can be made, and says what an entry starts with while it is empty', () => {
    const body = journalNoteBody('Log', PRESETS[3]!.text, false);
    const onNewEntry = vi.fn();
    show(<JournalView body={body} noteOf={() => undefined} known={() => false} open={() => {}} onChange={() => {}} onNewEntry={onNewEntry} />);
    expect(document.body.textContent).toContain('No entries yet.');
    expect(document.body.textContent).toContain('Starts with a to-do list.');
    expect([...document.querySelectorAll('button')].map((b) => b.textContent?.trim())).toEqual(['New entry']);
    // New entry shows the templates to start from, the journal's usual one first, and makes nothing yet.
    act(() => button('New entry').click());
    expect(onNewEntry).not.toHaveBeenCalled();
    const names = [...document.querySelectorAll('[aria-label="Start the entry with"] li button')].map((b) => b.firstElementChild?.textContent);
    expect(names).toEqual(['A day’s to-dosUsual', 'The date and the time', 'Just the time', 'A morning page', 'An empty page']);
    act(() => [...document.querySelectorAll<HTMLButtonElement>('[aria-label="Start the entry with"] li button')][3]!.click());
    expect(onNewEntry).toHaveBeenCalledTimes(1);
    expect(onNewEntry).toHaveBeenCalledWith(PRESETS[2]!.text);
    expect(document.querySelector('[aria-label="Start the entry with"]')).toBeNull();
    // No grips, moves or Add a page: time decides the order.
    expect(document.body.textContent).not.toContain('Add a page');
  });

  it('says how each template starts on one line, and lets the choice be put away', () => {
    expect(startLine('# {{journal}}\n\n## To do\n\n- [ ] ', 'Log')).toBe('Log · To do');
    expect(startLine('', 'Log')).toBe('Nothing, a blank page');
    expect(entryStarts('my own words').map((s) => s.name)).toEqual(['My own', ...PRESETS.map((p) => p.name), 'An empty page']);
    const onNewEntry = vi.fn();
    show(<JournalView body={journalNoteBody('Log', PRESETS[0]!.text, false)} noteOf={() => undefined} known={() => false} open={() => {}} onChange={() => {}} onNewEntry={onNewEntry} />);
    act(() => button('New entry').click());
    act(() => button('Cancel').click());
    expect(document.querySelector('[aria-label="Start the entry with"]')).toBeNull();
    expect(onNewEntry).not.toHaveBeenCalled();
  });
});

describe('the bar and the foot an entry wears', () => {
  it('walk the entries in the order they were written and say entries, the newest last', () => {
    const older = entryAt(2026, 9, 27, 21, 40);
    const newest = entryAt(2026, 9, 28, 14, 5);
    const middle = entryAt(2026, 9, 28, 8, 10);
    // Made in another order than written: a notebook kept as a journal.
    const { body, noteOf } = journalOf([newest, older, middle]);
    const journal = makeNote('diary', body);
    const place = inTimeOrder(bookOf([journal], '2026-09-28 08.10')!, noteOf);
    const open = vi.fn();
    inLocale('en-GB', () => show(<BookBar place={place} open={open} />));
    expect(document.querySelector('nav[aria-label="Journal"]')?.textContent).toContain('2 of 3');
    // Each side says what tells it apart: the day it was written, or its time on this one's day.
    expect([...document.querySelectorAll('nav[aria-label="Journal"] [data-next], nav[aria-label="Journal"] button:first-child')].map((b) => b.textContent)).toEqual(['27 Sept', '14:05']);
    act(() => button('Previous entry: 2026-09-27 21.40').click());
    act(() => button('Next entry: 2026-09-28 14.05').click());
    act(() => button('Open the journal Diary').click());
    expect(open.mock.calls.map((call) => call[0])).toEqual(['2026-09-27 21.40', '2026-09-28 14.05', 'Diary']);
    show(<BookFoot place={inTimeOrder(bookOf([journal], '2026-09-28 14.05')!, noteOf)} open={() => {}} />);
    expect(document.querySelector('nav[aria-label="Previous and next entry"]')).not.toBeNull();
    const last = inTimeOrder(bookOf([journal], '2026-09-28 14.05')!, noteOf);
    expect(last.at).toBe(2);
    show(<BookBar place={last} open={() => {}} />);
    expect(button('Last entry').disabled).toBe(true);
    show(<BookBar place={inTimeOrder(bookOf([journal], '2026-09-27 21.40')!, noteOf)} open={() => {}} />);
    expect(button('First entry').disabled).toBe(true);
  });
});
