import { describe, expect, it } from 'vitest';
import { inLocale } from '../../test/locale.ts';
import { makeNote } from '../../test/notes.ts';
import { withGeoTag } from '../core/geotag.ts';
import { DEFAULT_TEMPLATE, entryBody, PRESETS } from './journal.ts';
import { firstWords, monthsOf, type JournalPage } from './journalMonths.ts';

/**
 * A journal's entries in months, newest first by when each was written, whatever order its index is in; what a row
 * says; and the lines with no note, dropped or listed apart.
 */

const entry = (title: string, date: string | null, words: string, createdAt = 0) =>
  makeNote(title, date ? entryBody(title, date, words) : `---\ntitle: "${title}"\n---\n${words}`, { createdAt });
const pages = (...notes: (ReturnType<typeof entry> | string)[]): JournalPage[] =>
  notes.map((note, line) => (typeof note === 'string' ? { title: note, line, note: null } : { title: note.id, line, note }));
const titles = (months: ReturnType<typeof monthsOf>['months']) => months.map((m) => [m.label, m.entries.map((e) => e.title)]);

describe('a journal’s months', () => {
  it('draws the entries newest first by their date, in one run a month, whatever the index’s order', () => {
    const a = entry('2026-08-30 10.00', '2026-08-30T10:00', 'August.');
    const b = entry('2026-09-28 14.05', '2026-09-28T14:05', 'Afternoon.');
    const c = entry('2026-09-28 08.10', '2026-09-28T08:10', 'Morning.');
    const d = entry('2026-07-01 07.00', '2026-07-01T07:00', 'July.');
    // Out of time order, as a notebook kept as a journal or one merged from two devices would be.
    const { months } = inLocale('en-GB', () => monthsOf(pages(b, a, d, c)));
    expect(titles(months)).toEqual([
      ['September 2026', ['2026-09-28 14.05', '2026-09-28 08.10']],
      ['August 2026', ['2026-08-30 10.00']],
      ['July 2026', ['2026-07-01 07.00']],
    ]);
  });

  it('reads when the note was made where an entry says no date, and the later line where two say the same minute', () => {
    const dated = entry('2026-09-10 09.00', '2026-09-10T09:00', 'Dated.');
    const undated = entry('Planned page', null, 'Written later.', new Date(2026, 8, 12, 18, 0).getTime());
    const first = entry('2026-09-12 18.00', '2026-09-12T18:00', 'One.');
    const second = entry('2026-09-12 18.00 (2)', '2026-09-12T18:00', 'Two.');
    const { months } = monthsOf(pages(dated, second, undated, first));
    expect(months[0]!.entries.map((e) => e.title)).toEqual(['2026-09-12 18.00', 'Planned page', '2026-09-12 18.00 (2)', '2026-09-10 09.00']);
  });

  it('drops an entry’s line with no note, and lists any other name with no note apart, in the index’s order', () => {
    const kept = entry('2026-09-28 14.05', '2026-09-28T14:05', 'Kept.');
    const { months, unwritten } = monthsOf(pages('2026-09-27 21.40', kept, 'Packing list', '2026-09-26 08.00 (2)', 'The route'));
    expect(titles(months).flatMap(([, list]) => list)).toEqual(['2026-09-28 14.05']);
    expect(unwritten).toEqual(['Packing list', 'The route']);
  });

  it('keeps a travelling entry on the day its clock said, wherever it is read', () => {
    const late = entry('2026-09-28 23.30', '2026-09-28T23:30', 'Written in New York.');
    const next = entry('2026-09-29 00.10', '2026-09-29T00:10', 'Just after midnight.');
    const { months } = inLocale('en-GB', () => monthsOf(pages(late, next)));
    expect(months[0]!.entries.map((e) => [e.day, e.weekday, e.time])).toEqual([
      ['29', 'Tue', '00:10'],
      ['28', 'Mon', '23:30'],
    ]);
  });

  it('says a row whole: the day, the time, where, and how it starts', () => {
    const tagged = entry('2026-09-28 14.05', '2026-09-28T14:05', '# Monday 28 September\n\n**14:05** Walked along the river after lunch.');
    const placed = { ...tagged, body: withGeoTag(tagged.body, { lat: 51.508, lon: -0.1281, place: 'Trafalgar Square', rough: false }) };
    const coords = entry('2026-09-28 08.10', '2026-09-28T08:10', 'Coffee.');
    const unnamed = { ...coords, body: withGeoTag(coords.body, { lat: 51.5, lon: -0.12, place: null, rough: true }) };
    const { months } = inLocale('en-GB', () => monthsOf(pages(placed, unnamed), DEFAULT_TEMPLATE));
    const [one, two] = months[0]!.entries;
    expect(one).toMatchObject({ day: '28', weekday: 'Mon', time: '14:05', place: 'Trafalgar Square', first: 'Walked along the river after lunch.' });
    expect(one!.label).toBe('Monday 28 September, 14:05, Trafalgar Square. Walked along the river after lunch.');
    expect(two!.place).toBe('Roughly 51.50, -0.12');
  });
});

describe('an entry’s first line', () => {
  it('skips its front matter, headings, the template’s own lines and the time that leads a line', () => {
    expect(firstWords(entryBody('t', '2026-09-28T14:05', '# Monday 28 September\n\n**14:05** '), DEFAULT_TEMPLATE)).toBe('');
    expect(firstWords(entryBody('t', '2026-09-28T14:05', '# Monday\n\n> What is on your mind this morning?\n\nThe garden, mostly.'), PRESETS[2]!.text)).toBe('The garden, mostly.');
    expect(firstWords(entryBody('t', '2026-09-28T14:05', '# Monday\n\n## To do\n\n- [ ] \n- [ ] Call **Sam**'), PRESETS[3]!.text)).toBe('Call Sam');
    expect(firstWords('---\ntitle: "x"\n---\n![](image/a.jpg)\n14:05 Tea.')).toBe('Tea.');
  });
});
