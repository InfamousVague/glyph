import { afterEach, describe, expect, it } from 'vitest';
import { fieldsIn } from '../core/taskFields.ts';
import { iconsSettled } from './iconDom.ts';
import { chipElement, chipLook, dayLabel, daySaid, dueTone, personShown, sameLook } from './fieldChips.ts';

/**
 * How each field looks as a chip (editor/fieldChips.ts): a day named from today, its colour by where it stands, the
 * other days with their words, a priority's mark and name, a person, a recurrence and a named field; and what is not
 * drawn at all. Counted from Thursday 1 October 2026, in British.
 */

const TODAY = '2026-10-01';
const look = (text: string, done = false) => {
  const span = fieldsIn(text)[0];
  return span ? chipLook(span, { today: TODAY, done, locale: 'en-GB' }) : null;
};

afterEach(async () => {
  await iconsSettled();
});

describe('a day, named from today', () => {
  it('says today, tomorrow and yesterday, and the weekday and date otherwise', () => {
    expect(dayLabel('2026-10-01', TODAY)).toBe('Today');
    expect(dayLabel('2026-10-02', TODAY)).toBe('Tomorrow');
    expect(dayLabel('2026-09-30', TODAY)).toBe('Yesterday');
    expect(dayLabel('2026-10-03', TODAY, 'en-GB')).toBe('Sat 3 Oct');
    expect(dayLabel('2026-09-29', TODAY, 'en-GB')).toBe('Tue 29 Sept');
  });

  it('adds the year only when it is not this one', () => {
    expect(dayLabel('2027-01-15', TODAY, 'en-GB')).toBe('Fri, 15 Jan 2027');
    expect(daySaid('2026-10-03', TODAY, 'en-GB')).toBe('Saturday 3 October');
    expect(daySaid('2025-12-24', TODAY, 'en-GB')).toBe('Wednesday, 24 December 2025');
  });

  it('leaves words that are not a day as they are', () => {
    expect(dayLabel('2026-02-30', TODAY)).toBe('2026-02-30');
  });

  it('stands overdue once it has passed, today on the day, and done once the box is ticked', () => {
    expect(dueTone('2026-09-29', TODAY, false)).toBe('overdue');
    expect(dueTone('2026-10-01', TODAY, false)).toBe('today');
    expect(dueTone('2026-10-02', TODAY, false)).toBe('plain');
    expect(dueTone('2026-09-29', TODAY, true)).toBe('done');
  });
});

describe('each field’s chip', () => {
  it('draws the due day with its calendar, and says when it is', () => {
    expect(look('📅 2026-09-29')).toMatchObject({ text: 'Tue 29 Sept', tone: 'overdue', label: 'Due Tuesday 29 September, overdue', menu: 'date', key: 'due' });
    expect(look('📅 2026-10-01')).toMatchObject({ text: 'Today', tone: 'today', label: 'Due Thursday 1 October, today' });
    expect(look('📅 2026-10-03')).toMatchObject({ text: 'Sat 3 Oct', tone: 'plain' });
    expect(look('📅 2026-09-29', true)).toMatchObject({ tone: 'done', label: 'Due Tuesday 29 September' });
  });

  it('draws the other days quieter, each with its word', () => {
    expect(look('🛫 2026-10-02')).toMatchObject({ text: 'Starts tomorrow', tone: 'quiet', menu: 'date', key: 'start' });
    expect(look('⏳ 2026-10-05')).toMatchObject({ text: 'Scheduled Mon 5 Oct', menu: 'date', key: 'scheduled' });
    expect(look('✅ 2026-09-30')).toMatchObject({ text: 'Done yesterday', menu: null });
    expect(look('➕ 2026-09-28')).toMatchObject({ text: 'Added Mon 28 Sept', menu: null });
    expect(look('❌ 2026-09-28')).toMatchObject({ text: 'Cancelled Mon 28 Sept', menu: null });
  });

  it('draws a priority as its mark, with its name for a screen reader', () => {
    expect(look('⏫')).toMatchObject({ text: '', tone: 'high', label: 'High priority', menu: 'priority' });
    expect(look('🔺')).toMatchObject({ tone: 'highest', label: 'Highest priority' });
    expect(look('⏬', true)).toMatchObject({ tone: 'done', label: 'Lowest priority' });
  });

  it('draws a person with their initial, a recurrence with its words, and a named field with its key', () => {
    expect(look('@sam-ortiz')).toMatchObject({ text: 'sam ortiz', initial: 'S', label: 'Assigned to sam ortiz', menu: 'person', key: 'sam-ortiz' });
    expect(look('🔁 every week')).toMatchObject({ text: 'every week', label: 'Repeats every week', menu: null });
    expect(look('[effort:: 3]')).toMatchObject({ text: '3', name: 'effort', label: 'effort: 3', menu: null });
  });

  it('draws Dataview’s own days and priority as the emoji’s are', () => {
    expect(look('[due:: 2026-10-02]')).toMatchObject({ text: 'Tomorrow', menu: 'date', key: 'due' });
    expect(look('[completion:: 2026-09-30]')).toMatchObject({ text: 'Done yesterday' });
    expect(look('[priority:: high]')).toMatchObject({ tone: 'high', menu: 'priority' });
  });

  it('draws nothing it cannot read as what it says, and nothing for Tasks’ ids', () => {
    expect(look('📅 2026-02-30')).toBeNull();
    expect(look('[priority:: soon]')).toBeNull();
    expect(look('🆔 abc123')).toBeNull();
    expect(look('⛔ abc123')).toBeNull();
  });

  it('names the day in the device’s language', () => {
    const span = fieldsIn('📅 2026-10-03')[0]!;
    expect(chipLook(span, { today: TODAY, done: false, locale: 'en-US' })?.text).toBe('Sat, Oct 3');
  });

  it('knows one look from another', () => {
    expect(sameLook(look('⏫')!, look('⏫')!)).toBe(true);
    expect(sameLook(look('⏫')!, look('🔺')!)).toBe(false);
    expect(personShown('Sam_Ortiz')).toBe('Sam Ortiz');
  });
});

describe('a chip’s element', () => {
  it('carries its tone and its label, and its words, initial and key in order', () => {
    const person = chipElement(look('@sam')!);
    expect(person.tagName).toBe('SPAN');
    expect(person.dataset.tone).toBe('plain');
    expect(person.dataset.person).toBe('');
    expect(person.getAttribute('aria-label')).toBe('Assigned to sam');
    expect(person.querySelector('.cm-fieldInitial')?.textContent).toBe('S');
    expect(person.querySelector('.cm-fieldWords')?.textContent).toBe('sam');

    const priority = chipElement(look('⏫')!, 'button');
    expect(priority.tagName).toBe('BUTTON');
    expect(priority.dataset.mark).toBe('');
    expect(priority.querySelector('.cm-fieldWords')).toBeNull();
    expect(priority.querySelector(':scope > svg')).not.toBeNull();

    const named = chipElement(look('[effort:: 3]')!);
    expect([...named.children].map((child) => child.className)).toEqual(['cm-fieldName', 'cm-fieldWords']);
  });
});
