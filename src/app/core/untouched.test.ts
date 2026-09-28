import { beforeEach, describe, expect, it, vi } from 'vitest';
import { withGeoTag } from './geotag.ts';
import { entryBody } from '../book/journal.ts';
import { forgetUntouched, isFresh, isUntouched, keepFresh, markFresh, rememberUntouched, setUntouchedWords, spoilFresh, untouchedRecord, untouchedRecords, wordsOf } from './untouched.ts';

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
    rememberUntouched('e1', record());
    expect(isUntouched('e1', BODY)).toBe(true);
    expect(isUntouched('e1', withGeoTag(BODY, { lat: 51.5, lon: -0.12, place: 'London', rough: false }))).toBe(true);
    // Trailing space typed or trimmed is not a word.
    expect(isUntouched('e1', `${BODY.trimEnd()}\n`)).toBe(true);
    expect(isUntouched('e1', `${BODY}Walked.`)).toBe(false);
    expect(isUntouched('other', BODY)).toBe(false);
  });

  it('is touched by a recording, a pin or the archive, each a person’s doing', () => {
    rememberUntouched('e1', record());
    expect(isUntouched('e1', BODY, { recordingMs: 4000 })).toBe(false);
    expect(isUntouched('e1', BODY, { starred: true })).toBe(false);
    expect(isUntouched('e1', BODY, { archivedAt: 1 })).toBe(false);
    expect(isUntouched('e1', BODY, { recordingMs: null, starred: false, archivedAt: null })).toBe(true);
  });

  it('takes new words for a spoken entry, and is forgotten', () => {
    rememberUntouched('e1', record());
    setUntouchedWords('e1', '# Monday 28 September\n');
    expect(untouchedRecord('e1')?.words).toBe('# Monday 28 September\n');
    expect(isUntouched('e1', entryBody('2026-09-28 14.05', '2026-09-28T14:05', '# Monday 28 September\n'))).toBe(true);
    forgetUntouched('e1');
    expect(untouchedRecord('e1')).toBeNull();
    expect(localStorage.getItem('glyph-entry-drafts')).toBeNull();
  });

  it('keeps twenty at most, the newest, and none older than a week, nor another build’s shape', () => {
    const now = Date.now();
    for (let i = 0; i < 25; i += 1) rememberUntouched(`e${i}`, record(now - i * 1000));
    const kept = Object.keys(untouchedRecords());
    expect(kept).toHaveLength(20);
    expect(kept).toContain('e0');
    expect(kept).not.toContain('e24');
    localStorage.setItem('glyph-entry-drafts', JSON.stringify({ old: record(now - 8 * 24 * 60 * 60_000), odd: { words: 1 }, fine: record(now) }));
    expect(Object.keys(untouchedRecords())).toEqual(['fine']);
    localStorage.setItem('glyph-entry-drafts', 'not json');
    expect(untouchedRecords()).toEqual({});
  });

  it('keeps a new note’s record, which has no journal, and still reads one a 1.10.0 build kept', () => {
    rememberUntouched('n1', { title: '2026-09-28', words: '# 2026-09-28\n\n', at: Date.now() });
    expect(untouchedRecord('n1')).toEqual({ title: '2026-09-28', words: '# 2026-09-28\n\n', at: expect.any(Number) });
    expect(isUntouched('n1', '# 2026-09-28\n\n')).toBe(true);
    expect(isUntouched('n1', '---\nlook: map\n---\n# 2026-09-28\n')).toBe(true);
    expect(isUntouched('n1', '# 2026-09-28\n\nA word.')).toBe(false);
    localStorage.setItem('glyph-entry-drafts', JSON.stringify({ e1: record(), bad: { journalId: 7, title: 'x', words: '', at: Date.now() } }));
    expect(Object.keys(untouchedRecords())).toEqual(['e1']);
    expect(untouchedRecord('e1')?.journalId).toBe('diary');
  });

  it('reads a note’s words after its front matter', () => {
    expect(wordsOf(BODY)).toBe(WORDS);
    expect(wordsOf('No front matter.')).toBe('No front matter.');
  });
});

describe('a fresh note', () => {
  it('is one made in this run, fresh while its words are empty or the app’s own, and spoiled by any of the person’s', () => {
    expect(isFresh('f1')).toBe(false);
    markFresh('f1');
    expect(isFresh('f1')).toBe(true);
    keepFresh('f1', '\n\n');
    expect(isFresh('f1')).toBe(true);
    // A name tapped: its record first, then its words, which are the app's.
    rememberUntouched('f1', { title: '2026-09-28', words: '# 2026-09-28\n\n', at: Date.now() });
    keepFresh('f1', '# 2026-09-28\n\n');
    expect(isFresh('f1')).toBe(true);
    // Undone to a blank page, still fresh; a letter of the person's is not.
    keepFresh('f1', '');
    expect(isFresh('f1')).toBe(true);
    keepFresh('f1', 'T');
    expect(isFresh('f1')).toBe(false);
    // Emptied again, it stays spoiled: an old note emptied by hand is never offered a name.
    keepFresh('f1', '');
    expect(isFresh('f1')).toBe(false);
    markFresh('f2');
    spoilFresh('f2');
    expect(isFresh('f2')).toBe(false);
  });

  it('is kept in memory only, so a note from before this run never is', async () => {
    markFresh('f3');
    vi.resetModules();
    const again = await import('./untouched.ts');
    expect(again.isFresh('f3')).toBe(false);
  });
});
