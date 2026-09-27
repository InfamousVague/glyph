import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { buttonSaying, show, typeInto, waitUntil } from '../../test/render.tsx';
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
/** Where sync stands, as the page reads it; a test moves it. */
const sync = vi.hoisted(() => ({ status: { phase: 'idle' as const, lastAt: null, message: null, conflicts: 0, unsent: 0, unsentReason: null as string | null } }));
vi.mock('../core/sync/engine.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/sync/engine.ts')>()),
  deleteAccountHere: (password: string) => deleteAccountHere(password),
  useSyncStatus: () => sync.status,
}));
vi.mock('./SharedLinks.tsx', () => ({ SharedLinks: () => null }));

const { AccountPane } = await import('./AccountPane.tsx');
const { createNote, setNoteRecording } = await import('../core/store.ts');
const { preferences, setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');

beforeEach(() => {
  localStorage.clear();
  setPreferences(DEFAULT_PREFERENCES);
  session = { handle: 'sam', token: 't', accountId: 1 };
  sync.status = { phase: 'idle', lastAt: null, message: null, conflicts: 0, unsent: 0, unsentReason: null };
});

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

describe('Signed out', () => {
  it('says where Local only is when it is holding the sync off', async () => {
    const { setPreferences } = await import('../core/preferences.ts');
    session = null;
    setPreferences({ localOnly: true });
    try {
      const host = show(<AccountPane />);
      // The switch is under Formatting: the page used to send people to a Developer page that has none.
      expect(host.textContent).toContain('“Local only” is on in Formatting, so nothing syncs until it is off.');
    } finally {
      setPreferences({ localOnly: false });
    }
  });
});

describe('Sync', () => {
  it('offers to sync meeting recordings, off by default, and writes the choice', () => {
    const host = show(<AccountPane />);
    expect(host.textContent).toContain('A meeting is other people\'s voices. Off, the words sync and the audio stays on the device it was made on.');
    expect(preferences().syncMeetingRecordings).toBe(false);
    act(() => host.querySelector<HTMLElement>('[aria-label="Sync meeting recordings"]')!.click());
    expect(preferences().syncMeetingRecordings).toBe(true);
  });

  it('counts the recordings that stayed on this phone: a meeting’s while those stay, and any over the service’s limit', async () => {
    await createNote('m', '# Meeting, 26 Sep 14:05', 'capture');
    await setNoteRecording('m', 60_000, []);
    await createNote('big', '# Long', 'capture');
    await setNoteRecording('big', 40 * 60_000, []);
    await createNote('ok', '# Short', 'capture');
    await setNoteRecording('ok', 60_000, []);
    setPreferences({ meetings: { m: 1 } });
    const host = show(<AccountPane />);
    await waitUntil(() => expect(host.textContent).toContain('2 recordings stayed on this phone.'));
    act(() => setPreferences({ syncMeetingRecordings: true }));
    await waitUntil(() => expect(host.textContent).toContain('1 recording stayed on this phone.'));
  });

  it('says how many notes the last sync could not send, and why', () => {
    sync.status = { ...sync.status, unsent: 2, unsentReason: 'The sync service could not be reached.' };
    const host = show(<AccountPane />);
    expect(host.textContent).toContain('2 notes not synced. The sync service could not be reached.');
  });
});
