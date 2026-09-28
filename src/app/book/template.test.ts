import { describe, expect, it } from 'vitest';
import { inLocale } from '../../test/locale.ts';
import { placeTake } from '../capture/place.ts';
import { PRESETS } from './journal.ts';
import { fillTemplate, formatStamp, openEnd } from './template.ts';

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

  it('puts the words at the end of a morning page, whose last line is already closed', () => {
    const words = fill(PRESETS[2]!.text);
    expect(openEnd(words)).toEqual({ base: words, placing: { kind: 'end' } });
    expect(openEnd('Words.')).toEqual({ base: 'Words.', placing: { kind: 'end' } });
  });
});
