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
// Your colour goes to the service (docs/SHARED.md, S7); here the call is watched and the list's colour is a variable.
const colour = vi.hoisted(() => ({ account: null as string | null, set: vi.fn(async (_hue: string | null) => undefined) }));
vi.mock('../core/orgs/orgs.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/orgs/orgs.ts')>()),
  useOrgs: () => ({ list: [], at: null, colour: colour.account }),
  setAccountColour: (hue: string | null) => colour.set(hue),
}));

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

/** The cards' titles on the page, in its order. */
const titles = (host: HTMLElement) => [...host.querySelectorAll('.setk__title')].map((title) => title.textContent);

/** Where each of `things` first shows in the page's text, in order: -1 for one that is not there. */
const placesOf = (host: HTMLElement, things: string[]) => things.map((thing) => host.textContent!.indexOf(thing));

describe('Signed out', () => {
  // Changed on purpose (docs/DESIGN.md §138): Privacy and Location are Account's cards, after the ways in. Privacy first
  // put Sign in on the second screen at 412 × 915, and off the Fold's opened screen.
  // Export joined them last (docs/DESIGN.md §167): everything as one zip, signed in or out.
  it('opens on the ghost and the way in, then Privacy, Location and Export', () => {
    session = null;
    const host = show(<AccountPane />);
    expect(titles(host)).toEqual(['Sign in', 'Privacy', 'Location', 'Export']);
    // The ghost heads the page, and the form comes before either privacy card, ways in and footnote with it.
    const ghost = host.querySelector('[data-scene="signed-out"]');
    expect(ghost).not.toBeNull();
    expect(ghost!.compareDocumentPosition(host.querySelector('form')!) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    const places = placesOf(host, ['Sign in', 'Create an account', 'Your password never leaves this device', 'Privacy', 'Location']);
    expect(places.every((place) => place >= 0)).toBe(true);
    expect([...places].sort((a, b) => a - b)).toEqual(places);
  });

  it('says Local only holds the sync off, and the words go to its card on this page', () => {
    session = null;
    setPreferences({ localOnly: true });
    const onOpen = vi.fn();
    const host = show(<AccountPane onOpen={onOpen} />);
    expect(host.querySelector('.setk-callout')?.textContent).toBe('Local only is on, so nothing syncs until it is off.');
    expect(host.querySelector<HTMLInputElement>('[aria-label="Local only"]')?.checked).toBe(true);
    act(() => host.querySelector<HTMLButtonElement>('.setk-callout .setk-go')!.click());
    expect(onOpen).toHaveBeenCalledWith({ id: 'account', setting: 'Privacy' });
  });
});

describe('Signed in', () => {
  it('has Sync, then Your colour, Privacy, Location and Export, then Delete account', () => {
    const host = show(<AccountPane />);
    expect(titles(host)).toEqual(['Sync', 'Your colour', 'Privacy', 'Location', 'Export']);
    const places = placesOf(host, ['Sync now', 'Local only', 'Map on a tagged note', 'Export everything', 'Delete account']);
    expect(places.every((place) => place >= 0)).toBe(true);
    expect([...places].sort((a, b) => a - b)).toEqual(places);
  });

  // Matt: "add the ability for users to pick and change their color" (docs/SHARED.md, S7).
  it('picks your colour from the seven, ink being none, and sends it to the service', () => {
    colour.account = 'sea';
    colour.set.mockClear();
    const host = show(<AccountPane />);
    const swatch = host.querySelector('[role="radiogroup"][aria-label="Colour"]')!;
    expect(swatch.querySelector('[aria-checked="true"]')?.getAttribute('aria-label')).toBe('Sea');
    act(() => (swatch.querySelector('[aria-label="Rose"]') as HTMLButtonElement).click());
    expect(colour.set).toHaveBeenCalledWith('rose');
    act(() => (swatch.querySelector('[aria-label="Ink"]') as HTMLButtonElement).click());
    expect(colour.set).toHaveBeenCalledWith(null);
    colour.account = null;
  });

  // Organizations are a row of their own in Settings' list now, not on this page.
  it('has no Organizations row', () => {
    expect(buttonSaying(show(<AccountPane />), 'Organizations')).toBeUndefined();
  });

  it('says Local only holds the sync off, and the words go to its card', () => {
    setPreferences({ localOnly: true });
    const onOpen = vi.fn();
    const host = show(<AccountPane onOpen={onOpen} />);
    expect(host.querySelector('.setk-callout')?.textContent).toBe('Local only is on, so nothing syncs until it is off.');
    act(() => host.querySelector<HTMLButtonElement>('.setk-callout .setk-go')!.click());
    expect(onOpen).toHaveBeenCalledWith({ id: 'account', setting: 'Privacy' });
  });

  it('keeps the words Local only as a plain word while a form has the Privacy card off the page', () => {
    setPreferences({ localOnly: true });
    const onOpen = vi.fn();
    for (const form of ['Delete account', 'Password and recovery codes']) {
      const host = show(<AccountPane onOpen={onOpen} />);
      act(() => buttonSaying(host, form)!.click());
      expect(titles(host)).not.toContain('Privacy');
      expect(host.querySelector('.setk-callout')?.textContent).toBe('Local only is on, so nothing syncs until it is off.');
      expect(host.querySelector('.setk-callout .setk-go')).toBeNull();
      act(() => buttonSaying(host, 'Cancel')!.click());
      expect(host.querySelector('.setk-callout .setk-go')).not.toBeNull();
      host.remove();
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
