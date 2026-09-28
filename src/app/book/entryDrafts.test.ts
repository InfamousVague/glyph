import { beforeEach, describe, expect, it } from 'vitest';
import { withGeoTag } from '../core/geotag.ts';
import { entryBody } from './journal.ts';
import { entryRecord, entryRecords, forgetEntry, rememberEntry, setEntryWords, untouchedEntry, wordsOf } from './entryDrafts.ts';

/**
 * The entries this device made and nobody has written in: kept on the device, read back as untouched while their words
 * are still the ones they were made with, and forgotten once they are someone's.
 */

const WORDS = '# Monday 28 September\n\n**14:05** ';
const BODY = entryBody('2026-09-28 14.05', '2026-09-28T14:05', WORDS);
const record = (at = Date.now()) => ({ journalId: 'diary', title: '2026-09-28 14.05', words: WORDS, at });

beforeEach(() => localStorage.clear());

describe('an entry’s record', () => {
  it('is untouched while its words are the ones it was made with, a place in its front matter included', () => {
    rememberEntry('e1', record());
    expect(untouchedEntry('e1', BODY)).toBe(true);
    expect(untouchedEntry('e1', withGeoTag(BODY, { lat: 51.5, lon: -0.12, place: 'London', rough: false }))).toBe(true);
    // Trailing space typed or trimmed is not a word.
    expect(untouchedEntry('e1', `${BODY.trimEnd()}\n`)).toBe(true);
    expect(untouchedEntry('e1', `${BODY}Walked.`)).toBe(false);
    expect(untouchedEntry('other', BODY)).toBe(false);
  });

  it('is touched by a recording, a pin or the archive, each a person’s doing', () => {
    rememberEntry('e1', record());
    expect(untouchedEntry('e1', BODY, { recordingMs: 4000 })).toBe(false);
    expect(untouchedEntry('e1', BODY, { starred: true })).toBe(false);
    expect(untouchedEntry('e1', BODY, { archivedAt: 1 })).toBe(false);
    expect(untouchedEntry('e1', BODY, { recordingMs: null, starred: false, archivedAt: null })).toBe(true);
  });

  it('takes new words for a spoken entry, and is forgotten', () => {
    rememberEntry('e1', record());
    setEntryWords('e1', '# Monday 28 September\n');
    expect(entryRecord('e1')?.words).toBe('# Monday 28 September\n');
    expect(untouchedEntry('e1', entryBody('2026-09-28 14.05', '2026-09-28T14:05', '# Monday 28 September\n'))).toBe(true);
    forgetEntry('e1');
    expect(entryRecord('e1')).toBeNull();
    expect(localStorage.getItem('glyph-entry-drafts')).toBeNull();
  });

  it('keeps twenty at most, the newest, and none older than a week, nor another build’s shape', () => {
    const now = Date.now();
    for (let i = 0; i < 25; i += 1) rememberEntry(`e${i}`, record(now - i * 1000));
    const kept = Object.keys(entryRecords());
    expect(kept).toHaveLength(20);
    expect(kept).toContain('e0');
    expect(kept).not.toContain('e24');
    localStorage.setItem('glyph-entry-drafts', JSON.stringify({ old: record(now - 8 * 24 * 60 * 60_000), odd: { words: 1 }, fine: record(now) }));
    expect(Object.keys(entryRecords())).toEqual(['fine']);
    localStorage.setItem('glyph-entry-drafts', 'not json');
    expect(entryRecords()).toEqual({});
  });

  it('reads a note’s words after its front matter', () => {
    expect(wordsOf(BODY)).toBe(WORDS);
    expect(wordsOf('No front matter.')).toBe('No front matter.');
  });
});
