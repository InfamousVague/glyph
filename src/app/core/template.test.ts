import { describe, expect, it } from 'vitest';
import { inLocale } from '../../test/locale.ts';
import { placeTake } from '../capture/place.ts';
import { PRESETS } from '../book/journal.ts';
import { fillTemplate, firstOpenAt, formatStamp, openEnd } from './template.ts';

/**
 * A journal's template filled for an entry: Obsidian's placeholders, Moment's tokens, names in the device's language,
 * and where a spoken entry's words go. Monday 28 September 2026, 14:05, in the device's own zone.
 */

const AT = () => new Date(2026, 8, 28, 14, 5);
const fill = (text: string, locale = 'en-GB') => inLocale(locale, () => fillTemplate(text, { at: AT(), title: '2026-09-28 14.05', journal: 'Diary' }));

describe('the placeholders', () => {
  it('fills each one in the device’s language and order, the time on a 24-hour clock everywhere', () => {
    const all = '{{date}} | {{time}} | {{weekday}} | {{title}} | {{journal}}';
    expect(fill(all, 'en-GB')).toBe('Monday 28 September | 14:05 | Monday | 2026-09-28 14.05 | Diary');
    expect(fill(all, 'en-US')).toBe('Monday, September 28 | 14:05 | Monday | 2026-09-28 14.05 | Diary');
    expect(fill(all, 'de-DE')).toBe('Montag, 28. September | 14:05 | Montag | 2026-09-28 14.05 | Diary');
  });

  it('fills every preset as a person would start an entry', () => {
    expect(fill(PRESETS[0]!.text)).toBe('# Monday 28 September\n\n**14:05** ');
    expect(fill(PRESETS[1]!.text)).toBe('**14:05** ');
    expect(fill(PRESETS[2]!.text)).toBe('# Monday 28 September\n\n> What is on your mind this morning?\n\n');
    expect(fill(PRESETS[3]!.text)).toBe('# Monday 28 September\n\n## To do\n\n- [ ] ');
  });

  it('leaves anything it does not know as it was typed, a name an object has of its own included', () => {
    expect(fill('{{x}} {{Date}} {{date:}} {{title:YYYY}}')).toBe('{{x}} {{Date}} Monday 28 September {{title:YYYY}}');
    expect(fill('{{__proto__}} {{constructor}} {{toString}} {{hasOwnProperty}}')).toBe('{{__proto__}} {{constructor}} {{toString}} {{hasOwnProperty}}');
    expect(fill('{ {date} } {{date')).toBe('{ {date} } {{date');
    // Spaces inside the braces, as Obsidian allows them.
    expect(fill('{{ time }} {{ date:YYYY }}')).toBe('14:05 2026');
  });
});

describe('the next ticket’s id (docs/DESIGN.md §157)', () => {
  const at = AT();
  const TICKET = '---\ntype: ticket\nid: "{{next-id}}"\nstatus: To do\n---\n# {{title}}\n\nSee {{next-id}}.';

  it('fills the id’s own line bare, its quotes gone, and the placeholder anywhere else as it is', () => {
    expect(fillTemplate(TICKET, { at, nextId: 'GHO-13', title: 'Login' })).toBe('---\ntype: ticket\nid: GHO-13\nstatus: To do\n---\n# Login\n\nSee GHO-13.');
    expect(fillTemplate("---\nid: '{{ next-id }}'\n---\n", { at, nextId: 'GHO-1' })).toBe('---\nid: GHO-1\n---\n');
    expect(fillTemplate('---\nid: {{next-id}}\n---\n', { at, nextId: 'GHO-1' })).toBe('---\nid: GHO-1\n---\n');
  });

  it('leaves the id’s line out where there is no key, and fills the placeholder in the words with nothing', () => {
    expect(fillTemplate(TICKET, { at, title: 'Login' })).toBe('---\ntype: ticket\nstatus: To do\n---\n# Login\n\nSee .');
    expect(fillTemplate(TICKET, { at, nextId: null })).toBe('---\ntype: ticket\nstatus: To do\n---\n# \n\nSee .');
    // A line of the words that looks like a key is words, not front matter, and is kept.
    expect(fillTemplate('# Notes\n\nid: {{next-id}}', { at })).toBe('# Notes\n\nid: ');
  });
});

describe('a format', () => {
  const format = (text: string, locale = 'en-GB', at = AT()) => inLocale(locale, () => formatStamp(at, text));

  it('reads every token Moment reads, the names in the device’s language', () => {
    expect(format('YYYY YY MMMM MMM MM M DD D dddd ddd HH H hh h mm A a')).toBe('2026 26 September Sept 09 9 28 28 Monday Mon 14 14 02 2 05 PM pm');
    // A name alone is the name as it stands alone in the language: German's "Sep" and "Mo", where a date writes "Sept.".
    expect(format('YYYY YY MMMM MMM MM M DD D dddd ddd HH H hh h mm A a', 'de-DE')).toBe('2026 26 September Sep 09 9 28 28 Montag Mo 14 14 02 2 05 PM pm');
    const morning = new Date(2026, 0, 2, 0, 7);
    expect(format('DD/MM/YY h:mm a, H:mm', 'en-US', morning)).toBe('02/01/26 12:07 am, 0:07');
    // One figure or two, as the token says, for a day and an hour under ten.
    expect(format('D DD M MM H HH h hh', 'en-GB', new Date(2026, 0, 2, 7, 9))).toBe('2 02 1 01 7 07 7 07');
  });

  it('writes the day as an ordinal in English, and as a number and a full stop elsewhere', () => {
    const on = (day: number) => format('Do', 'en-GB', new Date(2026, 9, day));
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31].map(on)).toEqual(['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '23rd', '31st']);
    expect(format('Do MMMM', 'de-DE')).toBe('28. September');
  });

  it('keeps words in square brackets, and reads letters outside them as Moment does', () => {
    expect(fill('{{date:dddd [at] HH:mm}}.')).toBe('Monday at 14:05.');
    expect(fill('{{date:D MMMM at HH:mm}}')).toBe('28 September pmt 14:05');
    expect(fill('{{date:YYYY-MM-DD}} {{time:HH.mm}}')).toBe('2026-09-28 14.05');
    expect(fill('{{date:[Week of] D MMM}}', 'en-US')).toBe('Week of 28 Sep');
  });
});

describe('the ISO week', () => {
  const week = (at: Date, text = 'GGGG-[W]WW') => inLocale('en-US', () => formatStamp(at, text));

  it('names the week its Thursday is in, the same in every language', () => {
    expect(week(AT())).toBe('2026-W40');
    // A Friday in 2021 is in 2020's last week, and the last days of a year can be the next year's first week.
    expect(week(new Date(2021, 0, 1))).toBe('2020-W53');
    expect(week(new Date(2026, 11, 31))).toBe('2026-W53');
    expect(week(new Date(2027, 0, 1))).toBe('2026-W53');
    expect(week(new Date(2024, 11, 30))).toBe('2025-W01');
    // A Sunday is the end of its week, not the start of the next, as it would be in en-US's own week.
    expect(week(new Date(2026, 9, 4))).toBe('2026-W40');
    expect(week(new Date(2026, 9, 5))).toBe('2026-W41');
    expect(inLocale('de-DE', () => formatStamp(AT(), 'GGGG-[W]WW'))).toBe('2026-W40');
  });

  it('writes W with no leading nought, keeps [W] a letter, and leaves Moment’s own week as it was typed', () => {
    expect(week(new Date(2026, 0, 5), 'W WW [W]')).toBe('2 02 W');
    expect(week(AT(), 'gggg-[W]ww')).toBe('gggg-Www');
    expect(fill('{{date:GGGG-[W]WW}}')).toBe('2026-W40');
  });
});

describe('where a new note’s caret goes', () => {
  it('is the end of the first line left open: an empty heading, an empty lead, or words ending in a space', () => {
    expect(firstOpenAt('# \n\n- [ ] ')).toBe(2);
    expect(firstOpenAt('# 2026-09-28\n\nMonday 28 September\n\n- [ ] ')).toBe('# 2026-09-28\n\nMonday 28 September\n\n- [ ] '.length);
    expect(firstOpenAt('# Meeting 2026-09-28 14.05\n\nWith \n\n## Notes\n\n- ')).toBe('# Meeting 2026-09-28 14.05\n\nWith '.length);
    expect(firstOpenAt('# Title\n\n> ')).toBe('# Title\n\n> '.length);
    expect(firstOpenAt('# Title\n\n1. ')).toBe('# Title\n\n1. '.length);
    expect(firstOpenAt('## \n')).toBe(3);
  });

  it('is never a blank line, and is the end of the words when nothing is left open', () => {
    expect(firstOpenAt('# Title\n\nWords.\n')).toBe('# Title\n\nWords.\n'.length);
    expect(firstOpenAt('\n\n')).toBe(2);
    expect(firstOpenAt('')).toBe(0);
  });
});

describe('where a spoken entry’s words go', () => {
  it('goes on from the time the default leaves open, so the entry still starts with it', () => {
    const { base, placing } = openEnd(fill(PRESETS[0]!.text));
    expect(base).toBe('# Monday 28 September\n');
    expect(placing).toEqual({ kind: 'end', lead: '**14:05** ' });
    expect(placeTake(base, 'Walked along the river.', placing).body).toBe('# Monday 28 September\n\n**14:05** Walked along the river.');
    expect(openEnd(fill(PRESETS[1]!.text))).toEqual({ base: '', placing: { kind: 'end', lead: '**14:05** ' } });
  });

  it('makes a day’s to-dos said aloud into to-dos, the empty box gone', () => {
    const { base, placing } = openEnd(fill(PRESETS[3]!.text));
    expect(base).toBe('# Monday 28 September\n\n## To do\n');
    expect(placing).toEqual({ kind: 'lists', task: true, heading: null, fresh: 'task' });
    expect(placeTake(base, 'Call Sam. Buy milk.', placing).body).toBe('# Monday 28 September\n\n## To do\n\n- [ ] Call Sam\n- [ ] Buy milk\n');
    expect(openEnd('- ').placing).toEqual({ kind: 'lists', task: false, heading: null, fresh: 'bullet' });
  });

  it('numbers what is said for a template of your own that ends in an empty numbered item', () => {
    const { base, placing } = openEnd('# Steps\n\n1. ');
    expect(placing).toEqual({ kind: 'lists', task: false, heading: null, fresh: 'number' });
    expect(placeTake(base, 'Buy milk. Call Sam.', placing).body).toBe('# Steps\n\n1. Buy milk\n2. Call Sam\n');
  });

  it('puts the words at the end of a morning page, whose last line is already closed', () => {
    const words = fill(PRESETS[2]!.text);
    expect(openEnd(words)).toEqual({ base: words, placing: { kind: 'end' } });
    expect(openEnd('Words.')).toEqual({ base: 'Words.', placing: { kind: 'end' } });
  });
});
