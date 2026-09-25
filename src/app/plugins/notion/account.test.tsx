import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show, waitUntil } from '../../../test/render.tsx';

/**
 * The Notion account as Settings > Notion reads it (client.ts `useNotionAccount`): asked of the binary when the page
 * is drawn, and again each time Ghost.md comes back to the front, which is how a sign-in finished in the phone's
 * browser, or a disconnect made elsewhere, shows without leaving the page. The binary is stood in for.
 */

let account: { connected: boolean; workspaceName?: string } = { connected: true, workspaceName: 'Glyph HQ' };
const invoke = vi.fn(async (command: string): Promise<unknown> => {
  if (command === 'ota_status') return { nativeGeneration: 12 };
  if (command === 'notion_account') return account;
  throw new Error(`no command ${command}`);
});
vi.mock('../../core/tauri.ts', () => ({ isTauri: () => true, invoke: (command: string) => invoke(command) }));

const { useNotionAccount } = await import('./client.ts');

/** The page's reading of the account: the workspace, or that there is none. */
function Account() {
  const { account: shown } = useNotionAccount();
  return <p>{shown === null ? 'asking' : shown.connected ? shown.workspaceName : 'signed out'}</p>;
}

/** The page going behind another app, or coming back to the front. */
function seen(state: DocumentVisibilityState) {
  vi.spyOn(document, 'visibilityState', 'get').mockReturnValue(state);
  act(() => {
    document.dispatchEvent(new Event('visibilitychange'));
  });
}

const asked = () => invoke.mock.calls.filter(([command]) => command === 'notion_account').length;

afterEach(() => {
  vi.restoreAllMocks();
  invoke.mockClear();
  account = { connected: true, workspaceName: 'Glyph HQ' };
});

describe('useNotionAccount', () => {
  it('reads the account when drawn, and again when Ghost.md comes back to the front, not when it goes', async () => {
    const host = show(<Account />);
    await waitUntil(() => expect(host.textContent).toBe('Glyph HQ'));
    expect(asked()).toBe(1);
    // Disconnected elsewhere while the page was away.
    account = { connected: false };
    seen('hidden');
    expect(asked()).toBe(1);
    seen('visible');
    await waitUntil(() => expect(host.textContent).toBe('signed out'));
    expect(asked()).toBe(2);
  });
});
