import { describe, expect, it, vi } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { button, press, show, waitUntil } from '../../test/render.tsx';

const now = Math.floor(Date.now() / 1000);
const server = [
  { id: 'AAAAAAAAAAAAAAAAAAAAAA', updated: now - 5000 },
  // Lost track of an hour ago, and one made a minute ago that may not have synced yet.
  { id: 'OOOOOOOOOOOOOOOOOOOOOO', updated: now - 3600 },
  { id: 'NNNNNNNNNNNNNNNNNNNNNN', updated: now - 60 },
];
const deleted: string[] = [];

vi.mock('../core/store.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/store.ts')>()),
  listNotes: vi.fn(async () => [makeNote('mine', '# Cabin trip\n')]),
}));
vi.mock('../core/account/account.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/account/account.ts')>()),
  accountState: () => ({ session: { token: 't', accountId: 1 } }),
}));
vi.mock('../core/account/api.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/account/api.ts')>()),
  call: vi.fn(async (method: string, path: string) => {
    if (method === 'GET' && path === 'shares') return { shares: server };
    if (method === 'DELETE') deleted.push(path);
    return {};
  }),
}));

const { setPreferences } = await import('../core/preferences.ts');
const { SharedLinks } = await import('./SharedLinks.tsx');

describe('the list of shared links', () => {
  it('lists each share by its note, and offers to take down only the ones no device lists that have settled', async () => {
    setPreferences({
      shares: {
        mine: { id: 'AAAAAAAAAAAAAAAAAAAAAA', key: 'KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK', sent: '' },
        elsewhere: { id: 'EEEEEEEEEEEEEEEEEEEEEE', key: 'KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK', sent: '' },
      },
    });
    const host = show(<SharedLinks />);
    // The notes' titles and the account's own list come from two reads the list fills in from: waited for, not slept on.
    await waitUntil(() => {
      const text = host.textContent ?? '';
      expect(text).toContain('Cabin trip');
      expect(text).toContain('A note not on this device');
      expect(text).toContain('A link no device lists');
    });
    press(button('Take down', host));
    await waitUntil(() => expect(deleted).toEqual(['shares/OOOOOOOOOOOOOOOOOOOOOO']));
  });
});
