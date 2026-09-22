import { describe, expect, it } from 'vitest';

/**
 * Shares are kept in the synced settings (core/preferences.ts `shares`), so every device lists, follows and can stop
 * every share. A device that kept its shares in its own storage, as builds before this one did, brings them over once.
 */
describe('where shares are kept', () => {
  it('brings a device’s own list into the synced settings once, keeping what the settings already had', async () => {
    const ID = 'AAAAAAAAAAAAAAAAAAAAAA';
    const KEY = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
    localStorage.setItem('glyph-shares', JSON.stringify({ phoneNote: { id: ID, key: KEY, sent: 'x' } }));
    const { preferences, setPreferences } = await import('../core/preferences.ts');
    setPreferences({ shares: { macNote: { id: 'CCCCCCCCCCCCCCCCCCCCCC', key: KEY, sent: 'y' } } });
    const { linkFor, sharedLinks } = await import('./share.ts');
    expect(linkFor('phoneNote')).toContain(`#${ID}.${KEY}`);
    expect(sharedLinks().map((s) => s.noteId).sort()).toEqual(['macNote', 'phoneNote']);
    expect(localStorage.getItem('glyph-shares')).toBeNull();
    expect(Object.keys(preferences().shares).sort()).toEqual(['macNote', 'phoneNote']);
  });

  it('keeps only entries a link could carry, from a store another build wrote', async () => {
    const { preferences, reloadPreferences } = await import('../core/preferences.ts');
    const good = { id: 'DDDDDDDDDDDDDDDDDDDDDD', key: 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE', sent: 'z', lacked: ['a.jpg', 7] };
    localStorage.setItem('glyph-preferences', JSON.stringify({ ...preferences(), shares: { good, bad: { id: 'no', key: 'x' }, worse: null } }));
    reloadPreferences();
    expect(preferences().shares).toEqual({ good: { ...good, lacked: ['a.jpg'] } });
  });
});
