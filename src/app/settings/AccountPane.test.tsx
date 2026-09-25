import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { buttonSaying, show, typeInto } from '../../test/render.tsx';
import { stubMatchMedia } from '../../test/stubs.ts';

// The component kit asks the window's resolution as it loads; the test's DOM has no matchMedia of its own. Before
// the pane's own import below, which is the first to reach the kit.
stubMatchMedia();

// Signed in as sam until the account is deleted.
let session: { handle: string; token: string; accountId: number } | null = { handle: 'sam', token: 't', accountId: 1 };
const listeners = new Set<() => void>();
vi.mock('../core/account/account.ts', async (importOriginal) => {
  const { useSyncExternalStore } = await import('react');
  const read = () => session;
  return {
    ...(await importOriginal<typeof import('../core/account/account.ts')>()),
    useAccount: () => ({ session: useSyncExternalStore((l) => (listeners.add(l), () => listeners.delete(l)), read), unlocked: true }),
    accountState: () => ({ session, unlocked: true }),
  };
});
const deleteAccountHere = vi.fn(async (password: string) => {
  if (password !== 'right') throw new Error('That is not the password.');
  session = null;
  listeners.forEach((l) => l());
});
vi.mock('../core/sync/engine.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/sync/engine.ts')>()),
  deleteAccountHere: (password: string) => deleteAccountHere(password),
  useSyncStatus: () => ({ phase: 'idle', lastAt: null, message: null, conflicts: 0 }),
}));
vi.mock('./SharedLinks.tsx', () => ({ SharedLinks: () => null }));

const { AccountPane } = await import('./AccountPane.tsx');

describe('Delete account', () => {
  it('says what goes, asks for the password, and lands signed out with the notes kept', async () => {
    const host = show(<AccountPane />);
    act(() => buttonSaying(host, 'Delete account')!.click());
    expect(host.textContent).toContain("every link you've shared");
    expect(host.textContent).toContain('The notes on this device stay here.');
    const submit = buttonSaying(host, 'Delete my account')!;
    expect(submit.disabled).toBe(true);
    const field = host.querySelector<HTMLInputElement>('input[type="password"]')!;
    typeInto(field, 'wrong');
    await act(async () => submit.form!.requestSubmit());
    expect(host.querySelector('[role="alert"]')?.textContent).toBe('That is not the password.');
    expect(session).not.toBeNull();
    typeInto(field, 'right');
    await act(async () => submit.form!.requestSubmit());
    expect(deleteAccountHere).toHaveBeenLastCalledWith('right');
    expect(host.textContent).toContain('Your account is deleted. The notes on this device are still here.');
  });
});
