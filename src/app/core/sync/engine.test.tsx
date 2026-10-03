import { act } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { makeNote } from '../../../test/notes.ts';
import { show, unmount } from '../../../test/render.tsx';
import type { Session } from '../account/keystore.ts';
import type { NotificationsContext } from '../notifications/feed.ts';
import type { OrgsContext } from '../orgs/orgs.ts';
import type { Outcome, SyncContext } from './notes.ts';
import type { PrefsContext } from './prefs.ts';

/*
 * Sync as the app runs it (engine.ts): when a pass runs, that only one runs at a time with exactly one queued behind
 * it, what stops it running at all, what the Account page is told, and what signing out forgets. A pass itself -
 * notes.ts and prefs.ts - is proved against the service in memory elsewhere; here each is a stand-in the test
 * drives, and the account is a session the test hands out. The engine keeps its schedule in module state, so every
 * test imports it fresh.
 */

const SESSION: Session = { token: 't1', handle: 'matt', accountId: 7 };
let session: Session | null = null;
let key: CryptoKey | null = null;
const resume = vi.fn(async () => undefined);
const signOut = vi.fn(async () => {
  session = null;
});
const deleteAccount = vi.fn(async (_password: string) => {
  session = null;
});

vi.mock('../account/account.ts', () => ({
  accountState: () => ({ session, unlocked: Boolean(session && key) }),
  accountKey: async () => key,
  resume: () => resume(),
  signOut: () => signOut(),
  deleteAccount: (password: string) => deleteAccount(password),
  // The phone's watch follows the account (core/notifications/phone.ts); nothing here signs in or out by event.
  onAccount: () => () => undefined,
}));

/** Every notes pass the engine ran, with what it was given. */
const passes: SyncContext[] = [];
/** How a notes pass goes: at once and changing nothing, unless a test says otherwise. */
let notesPass: (ctx: SyncContext) => Promise<Outcome> = async () => ({ changed: 0, conflicts: 0, unsent: 0, reason: null });
vi.mock('./notes.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./notes.ts')>()),
  syncNotes: (ctx: SyncContext) => {
    passes.push(ctx);
    return notesPass(ctx);
  },
}));
let prefsPass: (ctx: PrefsContext) => Promise<boolean> = async () => false;
vi.mock('./prefs.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./prefs.ts')>()),
  syncPrefs: (ctx: PrefsContext) => prefsPass(ctx),
}));
/** The notifications and organizations steps, likewise stand-ins; what each forgets on signing out is the real thing. */
let feedPass: (ctx: NotificationsContext) => Promise<boolean> = async () => true;
vi.mock('../notifications/feed.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../notifications/feed.ts')>()),
  syncNotifications: (ctx: NotificationsContext) => feedPass(ctx),
}));
let orgsPass: (ctx: OrgsContext) => Promise<null> = async () => null;
vi.mock('../orgs/orgs.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../orgs/orgs.ts')>()),
  syncOrgs: (ctx: OrgsContext) => orgsPass(ctx),
}));
const recorded: { kind: string; details: unknown }[] = [];
vi.mock('../notifications/record.ts', () => ({
  record: async (kind: string, details: unknown) => {
    recorded.push({ kind, details });
  },
}));

let native = false;
let generation = 16;
let ios = false;
/** What `recording_digest` answers, or throws. */
let digestAnswer: () => unknown = () => null;
const invoked: { command: string; args: unknown }[] = [];
vi.mock('../tauri.ts', () => ({
  isTauri: () => native,
  invoke: async (command: string, args?: unknown) => {
    invoked.push({ command, args });
    if (command === 'recording_digest') return digestAnswer();
  },
}));
vi.mock('../platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../platform.ts')>()),
  get isIOS() {
    return ios;
  },
}));
vi.mock('../nativeGeneration.ts', () => ({ hasNativeGeneration: async (wanted: number) => generation >= wanted }));

let engine: typeof import('./engine.ts');
let prefs: typeof import('../preferences.ts');
let store: typeof import('../store.ts');
/** The engine's own ApiError: a fresh import of the engine brings a fresh class, and a refusal is told apart by it. */
let ApiError: typeof import('../account/api.ts').ApiError;

/** The status as the Account page has it, kept current by a component that follows it. */
let status: ReturnType<typeof engine.useSyncStatus> | null = null;
function Status() {
  status = engine.useSyncStatus();
  return null;
}

/** A pass that waits until the test lets it finish. */
function heldPass(): { release: (outcome?: Outcome) => void } {
  let release: (outcome?: Outcome) => void = () => undefined;
  notesPass = () =>
    new Promise<Outcome>((resolve) => {
      release = (outcome = { changed: 0, conflicts: 0, unsent: 0, reason: null }) => resolve(outcome);
    });
  return { release: (outcome) => release(outcome) };
}

/** Lets what is queued run, inside act since the status follows it. */
async function flush(): Promise<void> {
  await act(async () => {
    for (let i = 0; i < 10; i += 1) await Promise.resolve();
  });
}

beforeEach(async () => {
  vi.resetModules();
  localStorage.clear();
  session = { ...SESSION };
  key = {} as CryptoKey;
  native = false;
  generation = 16;
  ios = false;
  digestAnswer = () => null;
  passes.length = 0;
  invoked.length = 0;
  notesPass = async () => ({ changed: 0, conflicts: 0, unsent: 0, reason: null });
  prefsPass = async () => false;
  feedPass = async () => true;
  orgsPass = async () => null;
  recorded.length = 0;
  resume.mockClear();
  signOut.mockClear();
  deleteAccount.mockClear();
  engine = await import('./engine.ts');
  prefs = await import('../preferences.ts');
  store = await import('../store.ts');
  ({ ApiError } = await import('../account/api.ts'));
  status = null;
  show(<Status />);
});

afterEach(() => {
  unmount();
  vi.useRealTimers();
});

describe('a pass', () => {
  it('syncs the notes and then the settings, and says when it finished and how many notes were kept twice', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(50_000);
    let order = '';
    notesPass = async () => {
      order += 'notes ';
      return { changed: 0, conflicts: 2, unsent: 0, reason: null };
    };
    prefsPass = async () => {
      order += 'prefs';
      return false;
    };
    await act(() => engine.syncNow());
    expect(order).toBe('notes prefs');
    expect(status).toEqual({ phase: 'idle', lastAt: 50_000, message: null, conflicts: 2, unsent: 0, unsentReason: null });
    expect(passes[0]).toMatchObject({ token: 't1', key });
  });

  it('takes the notifications before the notes, and the organizations after the settings', async () => {
    const order: string[] = [];
    feedPass = async (ctx) => {
      order.push('notifications');
      expect(ctx.token).toBe('t1');
      return true;
    };
    notesPass = async () => {
      order.push('notes');
      return { changed: 0, conflicts: 0, unsent: 0, reason: null };
    };
    prefsPass = async () => {
      order.push('prefs');
      return false;
    };
    orgsPass = async (ctx) => {
      order.push('orgs');
      expect(ctx.token).toBe('t1');
      return null;
    };
    await act(() => engine.syncNow());
    expect(order).toEqual(['notifications', 'notes', 'prefs', 'orgs']);
    expect(status?.phase).toBe('idle');
  });

  it('hands the notifications step the feed as it is at each step, kept under the account', async () => {
    feedPass = async (ctx) => {
      ctx.update((state) => ({ ...state, cursor: 12 }));
      expect(ctx.read().cursor).toBe(12);
      return true;
    };
    await act(() => engine.syncNow());
    expect(JSON.parse(localStorage.getItem('glyph-sync-7-notifications') ?? 'null')).toMatchObject({ cursor: 12 });
  });

  it('records a note kept twice as a notification, with the copy’s id and title', async () => {
    notesPass = async (ctx) => {
      ctx.onConflict?.({ noteId: 'n-copy', title: 'Trip to Lisbon' });
      return { changed: 1, conflicts: 1, unsent: 0, reason: null };
    };
    await act(() => engine.syncNow());
    expect(recorded).toEqual([{ kind: 'sync-conflict', details: { noteId: 'n-copy', title: 'Trip to Lisbon' } }]);
  });

  it('runs the notifications and the organizations alone when asked, leaving the notes’ status as it was', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(50_000);
    await act(() => engine.syncNow());
    const order: string[] = [];
    feedPass = async () => {
      order.push('notifications');
      return true;
    };
    orgsPass = async () => {
      order.push('orgs');
      return null;
    };
    await act(() => engine.syncNotificationsNow());
    expect(order).toEqual(['notifications', 'orgs']);
    expect(passes).toHaveLength(1);
    expect(status).toMatchObject({ phase: 'idle', lastAt: 50_000 });
    // A failure there is still said.
    feedPass = async () => {
      throw new ApiError(500, 'The service is down.');
    };
    await act(() => engine.syncNotificationsNow());
    expect(status).toMatchObject({ phase: 'error', message: 'The service is down.' });
  });

  it('runs a full pass when both kinds were asked for while one was running', async () => {
    const held = heldPass();
    const first = engine.syncNow();
    await flush();
    const light = engine.syncNotificationsNow();
    const full = engine.syncNow();
    expect(light).toBe(first);
    expect(full).toBe(first);
    notesPass = async () => ({ changed: 0, conflicts: 0, unsent: 0, reason: null });
    held.release();
    await act(() => first);
    // The queued pass covered the most anybody asked: the notes ran twice.
    expect(passes).toHaveLength(2);
  });

  it('says how many notes it could not send and why, and hands the pass which notes are meetings and whether their audio goes', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(50_000);
    prefs.setPreferences({ meetings: { m1: 40 }, syncMeetingRecordings: true });
    notesPass = async () => ({ changed: 0, conflicts: 0, unsent: 2, reason: 'The recording is too big for the service.' });
    await act(() => engine.syncNow());
    expect(status).toMatchObject({ phase: 'idle', unsent: 2, unsentReason: 'The recording is too big for the service.' });
    expect(engine.syncSummary('matt', status!)).toBe('matt · 2 notes not synced');
    expect(passes[0]).toMatchObject({ meetings: { m1: 40 }, syncMeetingRecordings: true });
    // The next pass that sends everything clears the count.
    notesPass = async () => ({ changed: 0, conflicts: 0, unsent: 0, reason: null });
    await act(() => engine.syncNow());
    expect(status).toMatchObject({ unsent: 0, unsentReason: null });
    expect(engine.syncSummary('matt', status!)).toBe('matt · synced just now');
  });

  it('says it is syncing while it runs', async () => {
    const held = heldPass();
    const running = engine.syncNow();
    await flush();
    expect(status?.phase).toBe('syncing');
    held.release();
    await act(() => running);
    expect(status?.phase).toBe('idle');
  });

  it('tells the list to read again only when the pass changed notes here', async () => {
    let told = 0;
    const onChanged = () => {
      told += 1;
    };
    window.addEventListener(store.NOTES_CHANGED, onChanged);
    await act(() => engine.syncNow());
    expect(told).toBe(0);
    notesPass = async () => ({ changed: 1, conflicts: 0, unsent: 0, reason: null });
    await act(() => engine.syncNow());
    expect(told).toBe(1);
    window.removeEventListener(store.NOTES_CHANGED, onChanged);
  });

  it('keeps what it learned under the account, and starts the next pass from it', async () => {
    notesPass = async (ctx) => {
      ctx.save({ ...ctx.state, cursor: ctx.state.cursor + 5 });
      return { changed: 0, conflicts: 0, unsent: 0, reason: null };
    };
    await act(() => engine.syncNow());
    expect(JSON.parse(localStorage.getItem('glyph-sync-7-notes') ?? 'null')).toMatchObject({ cursor: 5 });
    await act(() => engine.syncNow());
    expect(passes[1]?.state.cursor).toBe(5);
  });
});

describe('what stops a pass', () => {
  it('does nothing signed out, or without the account key, and says sync is off', async () => {
    session = null;
    await act(() => engine.syncNow());
    key = null;
    session = { ...SESSION };
    await act(() => engine.syncNow());
    expect(passes).toHaveLength(0);
    expect(status?.phase).toBe('off');
  });

  it('does nothing with "Nothing leaves the phone" on', async () => {
    prefs.setPreferences({ localOnly: true });
    await act(() => engine.syncNow());
    expect(passes).toHaveLength(0);
    expect(status?.phase).toBe('off');
  });

  it('asks for the newest app on a binary without the store sync needs, and runs on one that has it', async () => {
    native = true;
    generation = 15;
    await act(() => engine.syncNow());
    expect(passes).toHaveLength(0);
    expect(status).toMatchObject({ phase: 'error', message: 'Sync needs the newest Ghost.md. Install it from attack.fm/glyph.' });
    generation = 16;
    await act(() => engine.syncNow());
    expect(passes).toHaveLength(1);
  });

  it('says what went wrong, and renews a session that lapsed mid-pass', async () => {
    notesPass = async () => {
      throw new ApiError(500, 'The service is down.');
    };
    await act(() => engine.syncNow());
    expect(status).toMatchObject({ phase: 'error', message: 'The service is down.' });
    expect(resume).not.toHaveBeenCalled();
    notesPass = async () => {
      throw new ApiError(401, 'Sign in again.');
    };
    await act(() => engine.syncNow());
    expect(resume).toHaveBeenCalledTimes(1);
  });
});

describe('one pass at a time', () => {
  it('queues exactly one more pass behind the one running, however many are asked for', async () => {
    const held = heldPass();
    const first = engine.syncNow();
    await flush();
    const second = engine.syncNow();
    const third = engine.syncNow();
    // Every request during a pass is answered with the pass that ends after the queued one.
    expect(second).toBe(first);
    expect(third).toBe(first);
    notesPass = async () => ({ changed: 0, conflicts: 0, unsent: 0, reason: null });
    held.release();
    await act(() => first);
    expect(passes).toHaveLength(2);
  });

  it('lets a reset wait for the pass running and the one it queued, and answers at once when none is', async () => {
    let settled = false;
    await engine.syncSettled();
    const held = heldPass();
    void engine.syncNow();
    await flush();
    void engine.syncNow();
    const waiting = engine.syncSettled().then(() => {
      settled = true;
    });
    await flush();
    expect(settled).toBe(false);
    notesPass = async () => ({ changed: 0, conflicts: 0, unsent: 0, reason: null });
    held.release();
    await act(() => waiting);
    expect(settled).toBe(true);
    expect(passes).toHaveLength(2);
  });
});

describe('when sync runs by itself', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  it('renews the session and syncs just after launch, signed in, and never for a device that was not', async () => {
    const stop = engine.startSync();
    expect(passes).toHaveLength(0);
    await act(() => vi.advanceTimersByTimeAsync(0));
    expect(resume).toHaveBeenCalledTimes(1);
    expect(passes).toHaveLength(1);
    stop();

    vi.resetModules();
    session = null;
    const fresh = await import('./engine.ts');
    const stopFresh = fresh.startSync();
    await act(() => vi.advanceTimersByTimeAsync(10 * 60_000));
    expect(resume).toHaveBeenCalledTimes(1);
    expect(passes).toHaveLength(1);
    stopFresh();
  });

  it('syncs four seconds after the last of a run of saves, not after each', async () => {
    const stop = engine.startSync();
    await act(() => vi.advanceTimersByTimeAsync(0));
    passes.length = 0;
    for (let i = 0; i < 3; i += 1) {
      window.dispatchEvent(new Event(store.NOTE_SAVED));
      await act(() => vi.advanceTimersByTimeAsync(3_000));
    }
    expect(passes).toHaveLength(0);
    await act(() => vi.advanceTimersByTimeAsync(1_000));
    expect(passes).toHaveLength(1);
    stop();
  });

  it('syncs when the app comes back, and on a five-minute beat while it is open', async () => {
    const stop = engine.startSync();
    await act(() => vi.advanceTimersByTimeAsync(0));
    passes.length = 0;
    document.dispatchEvent(new Event('visibilitychange'));
    await act(() => vi.advanceTimersByTimeAsync(0));
    expect(passes).toHaveLength(1);
    await act(() => vi.advanceTimersByTimeAsync(5 * 60_000));
    expect(passes).toHaveLength(2);
    stop();
    await act(() => vi.advanceTimersByTimeAsync(5 * 60_000));
    expect(passes).toHaveLength(2);
  });

  it('syncs after a setting changes here, but not after the settings another device sent', async () => {
    prefsPass = async (ctx) => {
      ctx.write({ theme: 'light' });
      return true;
    };
    const stop = engine.startSync();
    await act(() => vi.advanceTimersByTimeAsync(0));
    // The settings the first pass wrote were the account's: no pass follows them.
    await act(() => vi.advanceTimersByTimeAsync(4_000));
    expect(passes).toHaveLength(1);
    prefsPass = async () => false;
    act(() => prefs.setPreferences({ accent: 'red' }));
    await act(() => vi.advanceTimersByTimeAsync(4_000));
    expect(passes).toHaveLength(2);
    stop();
  });

  it('starts once, however many times it is asked', async () => {
    const stop = engine.startSync();
    const again = engine.startSync();
    await act(() => vi.advanceTimersByTimeAsync(0));
    expect(passes).toHaveLength(1);
    again();
    stop();
  });
});

describe('this device and the account', () => {
  it('knows a note has changes the pass has not sent, and that nothing is pending signed out', async () => {
    const note = makeNote('a', 'words');
    expect(engine.hasUnsyncedChanges(note)).toBe(true);
    notesPass = async (ctx) => {
      const { mark } = await import('./notes.ts');
      ctx.save({ ...ctx.state, notes: { a: { rev: 3, mark: mark(note) } } });
      return { changed: 0, conflicts: 0, unsent: 0, reason: null };
    };
    await act(() => engine.syncNow());
    expect(engine.hasUnsyncedChanges(note)).toBe(false);
    expect(engine.hasUnsyncedChanges({ ...note, body: 'more words' })).toBe(true);
    session = null;
    expect(engine.hasUnsyncedChanges({ ...note, body: 'more words' })).toBe(false);
  });

  it('forgets what it knew of the account when signing out, and keeps the notes', async () => {
    localStorage.setItem('glyph-sync-7-notes', '{"cursor":9}');
    localStorage.setItem('glyph-sync-7-prefs', '{"rev":2}');
    localStorage.setItem('glyph-sync-7-notifications', '{"cursor":3,"items":{},"marks":[],"unsent":[]}');
    localStorage.setItem('glyph-sync-7-orgs', '{"list":[],"at":1}');
    localStorage.setItem('glyph-sync-8-notes', '{"cursor":1}');
    await store.createNote('kept', '# Kept');
    await act(() => engine.syncNow());
    await act(() => engine.signOutHere());
    expect(signOut).toHaveBeenCalledTimes(1);
    expect(localStorage.getItem('glyph-sync-7-notes')).toBeNull();
    expect(localStorage.getItem('glyph-sync-7-prefs')).toBeNull();
    expect(localStorage.getItem('glyph-sync-7-notifications')).toBeNull();
    expect(localStorage.getItem('glyph-sync-7-orgs')).toBeNull();
    expect(localStorage.getItem('glyph-sync-8-notes')).not.toBeNull();
    expect(status).toEqual({ phase: 'off', lastAt: null, message: null, conflicts: 0, unsent: 0, unsentReason: null });
    expect(await store.getNote('kept')).not.toBeNull();
  });

  it('empties the list of shares when the account is deleted, since the links read nothing now', async () => {
    prefs.setPreferences({ shares: { a: { id: 'i'.repeat(22), key: 'k'.repeat(43), sent: 'p2:1' } } });
    localStorage.setItem('glyph-sync-7-notes', '{"cursor":9}');
    await act(() => engine.deleteAccountHere('correct horse'));
    expect(deleteAccount).toHaveBeenCalledWith('correct horse');
    expect(prefs.preferences().shares).toEqual({});
    expect(localStorage.getItem('glyph-sync-7-notes')).toBeNull();
  });

  it('asks the phone for a tape’s fingerprint, and reads the file where the phone cannot say rather than calling it gone', async () => {
    await act(() => engine.syncNow());
    const files = passes[0]!.files;
    native = true;
    generation = 20;
    digestAnswer = () => ({ sha256: 'ab'.repeat(32), bytes: 10 });
    expect(await files.digest!('n1')).toBe('ab'.repeat(16));
    digestAnswer = () => null;
    expect(await files.digest!('n1')).toBeNull();
    // A call that failed is not "no tape": remembered as one, the note would travel without its tape's fingerprint for good.
    digestAnswer = () => {
      throw new Error('the phone was busy');
    };
    expect(await files.digest!('n1')).toBeUndefined();
    // iOS keeps synced tapes and hashes none: its command answers null for every tape, which is not the truth.
    digestAnswer = () => null;
    ios = true;
    expect(await files.digest!('n1')).toBeUndefined();
    generation = 19;
    ios = false;
    expect(await files.digest!('n1')).toBeUndefined();
  });

  it('reads which notes are meetings when it decides about a recording, not when the pass began', async () => {
    const pass = heldPass();
    const running = engine.syncNow();
    await flush();
    expect(passes[0]!.meetings).toEqual({});
    // Done on the Mac's meeting while the pass is out: its note is listed as a meeting before its audio is kept.
    prefs.setPreferences({ meetings: { m2: 1 } });
    expect(passes[0]!.meetings).toEqual({ m2: 1 });
    pass.release();
    await act(() => running);
  });

  it('files a recording that arrived by sync with Rust as standard base64, and keeps none in a browser', async () => {
    await act(() => engine.syncNow());
    const files = passes[0]!.files;
    await files.write('recording', 'n1', new Uint8Array([0xfb, 0xff]));
    expect(invoked).toEqual([]);
    expect(await files.read('recording', 'n1')).toBeNull();
    native = true;
    await files.write('recording', 'n1', new Uint8Array([0xfb, 0xff]));
    expect(invoked).toEqual([{ command: 'sync_put_file', args: { kind: 'recording', name: 'n1', base64: '+/8=' } }]);
  });
});

describe('what the Account page says', () => {
  it('says how long ago a sync finished', () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(10 * 60 * 60_000);
    const now = Date.now();
    expect(engine.syncedWhen(now - 20_000)).toBe('just now');
    expect(engine.syncedWhen(now - 5 * 60_000)).toBe('5 min ago');
    expect(engine.syncedWhen(now - 3 * 60 * 60_000)).not.toMatch(/ago|just now/);
  });

  it('gives the Account row the handle and where sync stands', () => {
    const idle = { phase: 'idle' as const, lastAt: null, message: null, conflicts: 0, unsent: 0, unsentReason: null };
    expect(engine.syncSummary(null, idle)).toBe('Not signed in');
    expect(engine.syncSummary('matt', idle)).toBe('matt');
    expect(engine.syncSummary('matt', { ...idle, phase: 'syncing' })).toBe('matt · syncing');
    expect(engine.syncSummary('matt', { ...idle, phase: 'error' })).toBe('matt · not synced');
    expect(engine.syncSummary('matt', { ...idle, lastAt: Date.now() })).toBe('matt · synced just now');
    expect(engine.syncSummary('matt', { ...idle, lastAt: Date.now(), unsent: 1 })).toBe('matt · 1 note not synced');
  });
});
