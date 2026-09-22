import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

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
  listNotes: vi.fn(async () => [{ id: 'mine', body: '# Cabin trip\n', createdAt: 0, updatedAt: 0, source: 'editor' }]),
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

let root: Root | null = null;
let host: HTMLDivElement | null = null;
afterEach(() => {
  act(() => root?.unmount());
  host?.remove();
});

describe('the list of shared links', () => {
  it('lists each share by its note, and offers to take down only the ones no device lists that have settled', async () => {
    setPreferences({
      shares: {
        mine: { id: 'AAAAAAAAAAAAAAAAAAAAAA', key: 'KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK', sent: '' },
        elsewhere: { id: 'EEEEEEEEEEEEEEEEEEEEEE', key: 'KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK', sent: '' },
      },
    });
    host = document.createElement('div');
    document.body.appendChild(host);
    root = createRoot(host);
    await act(async () => {
      root!.render(<SharedLinks />);
      await new Promise((resolve) => setTimeout(resolve, 20));
    });
    const text = host.textContent ?? '';
    expect(text).toContain('Cabin trip');
    expect(text).toContain('A note not on this device');
    expect(text).toContain('A link no device lists');
    const takeDown = [...host.querySelectorAll('button')].find((b) => b.textContent?.trim() === 'Take down')!;
    await act(async () => {
      takeDown.click();
      await new Promise((resolve) => setTimeout(resolve, 20));
    });
    expect(deleted).toEqual(['shares/OOOOOOOOOOOOOOOOOOOOOO']);
  });
});
