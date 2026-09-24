import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
// The component kit asks the window's resolution as it loads; the test's DOM has no matchMedia of its own.
window.matchMedia ??= (() => ({ matches: false, addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {} })) as unknown as typeof window.matchMedia;

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

let root: Root;
let host: HTMLDivElement;
afterEach(() => {
  act(() => root.unmount());
  host.remove();
});

function type(field: HTMLInputElement, words: string) {
  const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  act(() => {
    set.call(field, words);
    field.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

const button = (words: string) => [...host.querySelectorAll('button')].find((b) => b.textContent?.includes(words))!;

describe('Delete account', () => {
  it('says what goes, asks for the password, and lands signed out with the notes kept', async () => {
    host = document.createElement('div');
    document.body.append(host);
    root = createRoot(host);
    act(() => root.render(<AccountPane />));
    act(() => button('Delete account').click());
    expect(host.textContent).toContain("every link you've shared");
    expect(host.textContent).toContain('The notes on this device stay here.');
    const submit = button('Delete my account');
    expect(submit.disabled).toBe(true);
    const field = host.querySelector<HTMLInputElement>('input[type="password"]')!;
    type(field, 'wrong');
    await act(async () => submit.form!.requestSubmit());
    expect(host.querySelector('[role="alert"]')?.textContent).toBe('That is not the password.');
    expect(session).not.toBeNull();
    type(field, 'right');
    await act(async () => submit.form!.requestSubmit());
    expect(deleteAccountHere).toHaveBeenLastCalledWith('right');
    expect(host.textContent).toContain('Your account is deleted. The notes on this device are still here.');
  });
});
