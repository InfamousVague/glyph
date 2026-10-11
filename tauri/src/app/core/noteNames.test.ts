import { describe, expect, it } from 'vitest';
import { inLocale } from '../../test/locale.ts';
import { keysTheDay, minuteName, nameOffers } from './noteNames.ts';
import { titleKey } from './titleKey.ts';

/**
 * The names a new note is offered (noteNames.ts): four in a fixed order, the day in words first, a taken one left out
 * with the rest in their places, and the words' own key trusted only where it keeps the month. Monday 28 September
 * 2026, 14:05, in the device's own zone.
 */

const AT = () => new Date(2026, 8, 28, 14, 5);
const offers = (locale = 'en-GB', taken: string[] = [], at = AT()) => inLocale(locale, () => nameOffers(at, new Set(taken.map(titleKey))));
const names = (locale = 'en-GB', taken: string[] = [], at = AT()) => offers(locale, taken, at).map((offer) => offer.name);

describe('the names on offer', () => {
  it('are four, in a fixed order, the day in words first', () => {
    expect(names()).toEqual(['Monday, 28 September 2026', '2026-09-28', '2026-09-28 14.05', '2026-W40']);
    expect(offers().map((offer) => offer.kind)).toEqual(['words', 'day', 'minute', 'week']);
    expect(offers().map((offer) => offer.label)).toEqual([
      'Name it for today, in words.',
      'Name it for today, 2026-09-28.',
      'Name it for this minute, 2026-09-28 14.05.',
      'Name it for this week, 2026-W40.',
    ]);
    expect(names('en-US')[0]).toBe('Monday, September 28, 2026');
    expect(names('de-DE')[0]).toBe('Montag, 28. September 2026');
  });

  it('keep their ISO names in ASCII digits in every language, and none has a colon', () => {
    for (const locale of ['ar-EG', 'fa-IR', 'hi-IN', 'th-TH']) expect(names(locale).slice(1)).toEqual(['2026-09-28', '2026-09-28 14.05', '2026-W40']);
    for (const name of names()) expect(name).not.toContain(':');
  });

  it('leave out a name another note has, the rest keeping their order', () => {
    expect(names('en-GB', ['2026-09-28'])).toEqual(['Monday, 28 September 2026', '2026-09-28 14.05', '2026-W40']);
    expect(names('en-GB', ['2026-09-28 14.05'])).toEqual(['Monday, 28 September 2026', '2026-09-28', '2026-W40']);
    expect(names('en-GB', ['2026-W40'])).toEqual(['Monday, 28 September 2026', '2026-09-28', '2026-09-28 14.05']);
    // Matched as a title is matched, not letter for letter.
    expect(names('en-GB', ['monday 28 September, 2026!'])).toEqual(['2026-09-28', '2026-09-28 14.05', '2026-W40']);
    // The next minute's name is free again.
    expect(names('en-GB', ['2026-09-28 14.05'], new Date(2026, 8, 28, 14, 6))).toContain('2026-09-28 14.06');
  });

  it('asks whether today is taken of its ISO name where the words’ key loses the month', () => {
    // Russian keys the words as "28 2026", like every 28th that year: another month's words do not take today's.
    const ru = names('ru-RU', ['28 2026']);
    expect(ru[0]).toBe('понедельник, 28 сентября 2026 г.');
    expect(names('ru-RU', ['2026-09-28'])).toEqual(['2026-09-28 14.05', '2026-W40']);
  });
});

describe('a key that tells one day from another', () => {
  it('is kept in English, German, Japanese and Chinese, and not where the month or everything is lost', () => {
    for (const locale of ['en-GB', 'en-US', 'de-DE', 'fr-FR', 'es-ES', 'ja-JP', 'zh-CN', 'ko-KR']) expect([locale, inLocale(locale, () => keysTheDay(AT()))]).toEqual([locale, true]);
    for (const locale of ['ru-RU', 'el-GR', 'ar-EG', 'th-TH', 'he-IL', 'hi-IN']) expect([locale, inLocale(locale, () => keysTheDay(AT()))]).toEqual([locale, false]);
  });

  it('holds on the last days of a month, read at the 28th', () => {
    expect(inLocale('en-GB', () => keysTheDay(new Date(2026, 0, 31)))).toBe(true);
    expect(inLocale('ru-RU', () => keysTheDay(new Date(2026, 0, 31)))).toBe(false);
  });

  it('differs from the same day a month on and a year on for every name offered', () => {
    for (const locale of ['en-GB', 'de-DE', 'ja-JP']) {
      const now = offers(locale);
      const later = [offers(locale, [], new Date(2026, 9, 28, 14, 5)), offers(locale, [], new Date(2027, 8, 28, 14, 5))];
      for (const other of later) for (const [i, offer] of now.entries()) expect(titleKey(offer.name)).not.toBe(titleKey(other[i]!.name));
    }
  });
});

describe('the minute’s name', () => {
  it('is the journal’s name for an entry, and the third chip', () => {
    expect(minuteName(AT())).toBe('2026-09-28 14.05');
    expect(minuteName(new Date(2026, 0, 2, 9, 7))).toBe('2026-01-02 09.07');
    expect(names()[2]).toBe(minuteName(AT()));
  });
});
