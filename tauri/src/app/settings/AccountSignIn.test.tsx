import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { buttonSaying, show, typeInto } from '../../test/render.tsx';
import { stubMatchMedia } from '../../test/stubs.ts';

// The component kit asks the window's resolution as it loads, before the pane's own import below reaches it.
stubMatchMedia();

// Signed out, with each way in stood in for: what the account module would answer, and what it was asked.
const signIn = vi.fn(async (_handle: string, _password: string) => undefined);
const signUp = vi.fn(async (_handle: string, _password: string) => ({ codes: ['AAAA-1111', 'BBBB-2222'] }));
const recover = vi.fn(async (_handle: string, _code: string, _password: string) => ({ codes: ['CCCC-3333'] }));
vi.mock('../core/account/account.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/account/account.ts')>()),
  useAccount: () => ({ session: null, unlocked: false }),
  signIn: (handle: string, password: string) => signIn(handle, password),
  signUp: (handle: string, password: string) => signUp(handle, password),
  recover: (handle: string, code: string, password: string) => recover(handle, code, password),
}));
const syncNow = vi.fn(async () => undefined);
vi.mock('../core/sync/engine.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/sync/engine.ts')>()),
  syncNow: () => syncNow(),
  useSyncStatus: () => ({ phase: 'idle', lastAt: null, message: null, conflicts: 0 }),
}));

const { AccountPane } = await import('./AccountPane.tsx');

/**
 * The Account page signed out: the three ways in and the checks made before the service is asked, and the recovery
 * codes a new account (or a recovered one) is shown once. Deleting an account, signed in, is AccountPane.test.tsx.
 */

const field = (host: HTMLElement, label: string) => host.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`)!;
const submit = (host: HTMLElement) => host.querySelector<HTMLButtonElement>('button[type="submit"]')!;

beforeEach(() => {
  signIn.mockClear();
  signUp.mockClear();
  recover.mockClear();
  syncNow.mockClear();
});

describe('signing in', () => {
  it('holds the button until there is a handle and a password, then signs in and syncs', async () => {
    const host = show(<AccountPane />);
    expect(submit(host).textContent).toBe('Sign in');
    expect(submit(host).disabled).toBe(true);
    typeInto(field(host, 'Handle'), 'sam');
    typeInto(field(host, 'Password'), 'long enough password');
    await act(async () => submit(host).form!.requestSubmit());
    expect(signIn).toHaveBeenCalledWith('sam', 'long enough password');
    expect(syncNow).toHaveBeenCalledOnce();
  });

  it('says what is wrong with a handle before asking the service anything', async () => {
    const host = show(<AccountPane />);
    typeInto(field(host, 'Handle'), 'x!');
    typeInto(field(host, 'Password'), 'long enough password');
    await act(async () => submit(host).form!.requestSubmit());
    expect(host.querySelector('[role="alert"]')?.textContent).toBe('A handle is 3 to 24 letters, digits, . _ or -, starting with a letter or digit.');
    expect(signIn).not.toHaveBeenCalled();
  });

  it('says the service’s refusal, and lets the person try again', async () => {
    signIn.mockRejectedValueOnce(new Error('Wrong handle or password.'));
    const host = show(<AccountPane />);
    typeInto(field(host, 'Handle'), 'sam');
    typeInto(field(host, 'Password'), 'not the password');
    await act(async () => submit(host).form!.requestSubmit());
    expect(host.querySelector('[role="alert"]')?.textContent).toBe('Wrong handle or password.');
    expect(submit(host).disabled).toBe(false);
  });
});

describe('a new account', () => {
  it('asks for a longer password, and then shows the recovery codes once', async () => {
    const host = show(<AccountPane />);
    act(() => buttonSaying(host, 'Create an account')!.click());
    expect(submit(host).textContent).toBe('Create account');
    typeInto(field(host, 'Handle'), 'sam');
    typeInto(field(host, 'Password'), 'short');
    await act(async () => submit(host).form!.requestSubmit());
    expect(host.querySelector('[role="alert"]')?.textContent).toBe('A password is at least 8 characters.');
    expect(signUp).not.toHaveBeenCalled();
    typeInto(field(host, 'Password'), 'long enough password');
    await act(async () => submit(host).form!.requestSubmit());
    expect(signUp).toHaveBeenCalledWith('sam', 'long enough password');
    expect([...host.querySelectorAll('[data-testid="recovery-codes"] code')].map((code) => code.textContent)).toEqual(['AAAA-1111', 'BBBB-2222']);
    act(() => buttonSaying(host, "I've kept them")!.click());
    expect(host.querySelector('[data-testid="recovery-codes"]')).toBeNull();
  });
});

describe('a lost password', () => {
  it('takes a recovery code and a new password, and shows the new codes', async () => {
    const host = show(<AccountPane />);
    act(() => buttonSaying(host, 'Lost the password')!.click());
    expect(submit(host).textContent).toBe('Recover and set password');
    typeInto(field(host, 'Handle'), 'sam');
    typeInto(field(host, 'New password'), 'a new long password');
    // Not without the code.
    expect(submit(host).disabled).toBe(true);
    typeInto(field(host, 'Recovery code'), 'ZZZZ-9999');
    await act(async () => submit(host).form!.requestSubmit());
    expect(recover).toHaveBeenCalledWith('sam', 'ZZZZ-9999', 'a new long password');
    expect(host.querySelector('[data-testid="recovery-codes"]')?.textContent).toContain('CCCC-3333');
  });
});
