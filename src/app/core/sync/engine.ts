import { convertFileSrc } from '@tauri-apps/api/core';
import { MEETING_GENERATION } from '../../capture/meeting.ts';
import { accountKey, accountState, deleteAccount, onAccount, resume, signOut } from '../account/account.ts';
import { ApiError } from '../account/api.ts';
import { ensureEncryptionKey } from '../account/encKey.ts';
import { deviceKeys } from '../account/keystore.ts';
import { toBase64 } from '../bytes.ts';
import { externalStore } from '../externalStore.ts';
import { failureText } from '../failure.ts';
import { imageBytes, keepImage } from '../images.ts';
import { hasNativeGeneration } from '../nativeGeneration.ts';
import { tellArrived } from '../notifications/arrived.ts';
import { feedState, forgetNotifications, listed, syncNotifications, updateFeed } from '../notifications/feed.ts';
import { postNewRows, syncPhoneWatch } from '../notifications/phone.ts';
import { record } from '../notifications/record.ts';
import { forgetOrgKeys, orgKeyOf, syncOrgKeys } from '../orgs/orgKeys.ts';
import { forgetOrgs, orgRowsOf, saveOrgs, syncOrgs } from '../orgs/orgs.ts';
import type { OrgRow } from '../orgs/types.ts';
import { isIOS } from '../platform.ts';
import { onPreferences, preferences, setPreferences } from '../preferences.ts';
import { recordingDigest } from '../recordings.ts';
import { announceNotesChanged, applyNote, deleteNote, getNote, listNotes, NOTE_SAVED, type Note } from '../store.ts';
import { readStored, writeStored } from '../stored.ts';
import { invoke, isTauri } from '../tauri.ts';
import { forgetTeamDocs } from '../team/doc.ts';
import { deviceDocs } from '../team/docs.ts';
import { emptyTeamState, syncTeamNotes, type TeamSyncState } from '../team/sync.ts';
import { fileNote, isOrgWorkspace, orgWorkspaceId, workspaceOf } from '../workspaces.ts';
import { readVersionsFile, sentVersions, unsentVersions, writeVersionsFile } from '../versions/store.ts';
import type { Bytes } from './crypto.ts';
import { emptyState, mark, syncNotes, type FileKind, type LocalFiles, type LocalNotes, type SyncState } from './notes.ts';
import { syncPrefs, type PrefsState } from './prefs.ts';

/**
 * Sync as the app runs it: when, against which of this device's stores, and what the Account page shows about it.
 *
 * A sync runs when the app starts signed in, when it comes back to the front, a moment after a note or a setting
 * changes, and every few minutes while it is open. One runs at a time; a request while one is running queues exactly
 * one more. Nothing runs without an account key on the device, or with "Nothing leaves the phone" on.
 *
 * A pass is four steps in this order: the notifications, the notes, the settings, the organizations (docs/TEAMS.md,
 * D4). Notifications before notes, so that a note a notification names has arrived by the time its row is drawn;
 * organizations after the settings and outside `applyingRemote`, so the workspace the list makes or drops is pushed
 * a moment later rather than on the next pass. The two new steps are quiet against a service that does not have
 * their routes yet (core/account/api.ts `notYet`), and leave the status to the notes.
 */

/** Native generation that has `store_apply` and `sync_put_file`. */
const SYNC_GENERATION = 16;
const QUIET_MS = 4_000;
const EVERY_MS = 5 * 60_000;

// --- status ------------------------------------------------------------------------------

export interface SyncStatus {
  phase: 'off' | 'idle' | 'syncing' | 'error';
  /** When the last sync finished cleanly, in ms. */
  lastAt: number | null;
  message: string | null;
  /** Notes kept twice by the last sync because both sides had changed them. */
  conflicts: number;
  /** Notes the last sync could not send, and the first reason why: sent again next time (docs/DESIGN.md §127 section 6). */
  unsent: number;
  unsentReason: string | null;
}

const status = externalStore<SyncStatus>({ phase: 'off', lastAt: null, message: null, conflicts: 0, unsent: 0, unsentReason: null });

function setStatus(next: Partial<SyncStatus>): void {
  status.update((was) => ({ ...was, ...next }));
}

export const useSyncStatus = status.use;

/** Where the sync stands now, read once: for what runs a pass and then asks how it went (settings/InviteActions.tsx). */
export const syncStatusNow = status.get;

/** How long ago a sync finished, as the Account page says it. */
export function syncedWhen(ms: number): string {
  const minutes = Math.round((Date.now() - ms) / 60_000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes} min ago`;
  return new Date(ms).toLocaleString(undefined, { hour: 'numeric', minute: '2-digit', day: 'numeric', month: 'short' });
}

/** The Account row's second line. */
export function syncSummary(signedIn: string | null, status: SyncStatus): string {
  if (!signedIn) return 'Not signed in';
  if (status.phase === 'syncing') return `${signedIn} · syncing`;
  if (status.phase === 'error') return `${signedIn} · not synced`;
  if (status.unsent) return `${signedIn} · ${unsentLine(status.unsent)}`;
  return status.lastAt ? `${signedIn} · synced ${syncedWhen(status.lastAt)}` : signedIn;
}

/** "3 notes not synced": what the last pass could not send. */
export function unsentLine(unsent: number): string {
  return unsent === 1 ? '1 note not synced' : `${unsent} notes not synced`;
}

// --- what this device remembers -----------------------------------------------------------

function stateKey(accountId: number, part: string): string {
  return `glyph-sync-${accountId}-${part}`;
}

function load<T>(key: string, fallback: T): T {
  return readStored(key, fallback, (raw) => ({ ...fallback, ...(raw as T) }) as T);
}

/** Full or private, it is not kept: the next sync starts from what was last kept, which only costs a longer sync. */
function store(key: string, value: unknown): void {
  writeStored(key, value);
}

/**
 * Whether this device's copy of a note has changes the pass sync has not sent: its fingerprint against the one kept at
 * its last sync, or no record of it at all. Live sync asks when a device joins a note another device already has open
 * (docs/LIVE.md, Seeding): a device that was only behind adopts the room's words; one with changes of its own keeps
 * them as a copy. Signed out, nothing is pending.
 */
export function hasUnsyncedChanges(note: Note): boolean {
  const session = accountState().session;
  if (!session) return false;
  const known = load<SyncState>(stateKey(session.accountId, 'notes'), emptyState()).notes[note.id];
  return !known || known.mark !== mark(note);
}

/** Forgets what this device knew of an account's sync: for signing out. The feed and the organizations are theirs to forget. */
function forgetSync(accountId: number): void {
  for (const part of ['notes', 'prefs']) writeStored(stateKey(accountId, part), null);
  // And each organization's channel (core/team/sync.ts), kept under `team-<org id>`: read before the organizations go.
  for (const row of orgRowsOf(accountId)) writeStored(stateKey(accountId, `team-${row.id}`), null);
  forgetTeamDocs();
  forgetNotifications(accountId);
  forgetOrgs(accountId);
  forgetOrgKeys();
  // Signed out: the phone stops reading the feed, and forgets the session it read it with.
  syncPhoneWatch();
}

/** Signs out and forgets this device's sync bookkeeping for the account. The notes stay. */
export async function signOutHere(): Promise<void> {
  const session = accountState().session;
  await signOut();
  if (session) forgetSync(session.accountId);
  setStatus({ phase: 'off', message: null, lastAt: null, conflicts: 0, unsent: 0, unsentReason: null });
}

/**
 * Deletes the account (account.ts `deleteAccount`), then forgets it here as signing out does, and the links shared
 * from it too, which read nothing now. The notes stay.
 */
export async function deleteAccountHere(password: string): Promise<void> {
  const session = accountState().session;
  await deleteAccount(password);
  if (session) forgetSync(session.accountId);
  setPreferences({ shares: {} });
  setStatus({ phase: 'off', message: null, lastAt: null, conflicts: 0, unsent: 0, unsentReason: null });
}

// --- this device's stores -------------------------------------------------------------------

const deviceNotes: LocalNotes = {
  list: listNotes,
  get: getNote,
  apply: applyNote,
  remove: deleteNote,
};

async function fetchLocal(url: string): Promise<Bytes | null> {
  try {
    const response = await fetch(url);
    return response.ok ? new Uint8Array(await response.arrayBuffer()) : null;
  } catch {
    return null;
  }
}

const deviceFiles: LocalFiles = {
  async read(kind: FileKind, name: string) {
    if (kind === 'image') return imageBytes(name);
    if (kind === 'versions') {
      const text = await readVersionsFile(name);
      return text === null ? null : new TextEncoder().encode(text);
    }
    // A browser keeps no recordings.
    return isTauri() ? fetchLocal(convertFileSrc(`${name}.wav`, 'rec')) : null;
  },
  async write(kind: FileKind, name: string, bytes: Bytes) {
    // A picture is drawn at once wherever a page was waiting for it (core/images.ts).
    if (kind === 'image') return keepImage(name, bytes);
    // A versions file from the account is not owed back to it; what this device adds to it is, when it adds it.
    if (kind === 'versions') return writeVersionsFile(name, new TextDecoder().decode(bytes), { owed: false });
    if (!isTauri()) return;
    // Standard base64, which is what Rust reads.
    await invoke('sync_put_file', { kind, name, base64: toBase64(bytes) });
  },
  owed: unsentVersions,
  settled: sentVersions,
  // A recording's fingerprint from the phone rather than from its bytes read into the page (native generation 20):
  // the same first sixteen bytes of the SHA-256 the pass would take itself. Undefined where the binary cannot say,
  // so the pass reads the file as it always did: an older binary, iOS (whose command answers null for every tape,
  // since it hashes nothing there), and a call that failed, which is not "no tape" and must not be remembered as one.
  async digest(name: string) {
    if (!isTauri() || isIOS || !(await hasNativeGeneration(MEETING_GENERATION))) return undefined;
    const answer = await recordingDigest(name).catch(() => undefined);
    if (answer === undefined) return undefined;
    return answer ? answer.sha256.slice(0, 32) : null;
  },
};

/** Whether this device's store can take a sync: always in a browser, where the store is the page's own. */
async function nativeReady(): Promise<boolean> {
  if (!isTauri()) return true;
  return hasNativeGeneration(SYNC_GENERATION);
}

// --- running ----------------------------------------------------------------------------------

/** What a pass covers: everything, or only the notifications and the organizations, which an inline answer changes. */
type Parts = 'all' | 'notifications';

let running: Promise<void> | null = null;
/** The pass asked for while one was running, if any: one more, covering the most anybody asked. */
let queued: Parts | null = null;

function widen(was: Parts | null, asked: Parts): Parts {
  return was === 'all' || asked === 'all' ? 'all' : 'notifications';
}

/** One pass of `parts` now, or right after the pass already running. */
function run(parts: Parts): Promise<void> {
  if (running) {
    queued = widen(queued, parts);
    return running;
  }
  running = (async () => {
    try {
      let next: Parts | null = parts;
      while (next) {
        await once(next);
        next = queued;
        queued = null;
      }
    } catch (failure) {
      setStatus({ phase: 'error', message: failureText(failure) });
    } finally {
      running = null;
      queued = null;
    }
  })();
  return running;
}

/** Syncs now, or right after the sync already running. */
export function syncNow(): Promise<void> {
  return run('all');
}

/**
 * The notifications and the organizations now, through the same one-at-a-time door: after an invitation is answered
 * inline, and when the Notifications page opens. The notes are not swept, which on a phone with a thousand of them
 * is the cost of a pass.
 */
export function syncNotificationsNow(): Promise<void> {
  return run('notifications');
}

/**
 * A sync, waited for `ms` at most: a pull to refresh (notes/PullToRefresh.tsx, docs/DESIGN.md §152) holds its ring
 * that long and no longer, on a slow connection too. The sync goes on after it, and its notes arrive as it lands.
 */
export function syncWithin(ms = 5000): Promise<void> {
  return Promise.race([syncNow(), new Promise<void>((done) => setTimeout(done, ms))]);
}

/**
 * The sync running now, finished, and the one it queued; at once when none is. For a reset (core/reset.ts), which
 * signs out first and then waits here: a sync already under way holds the session it began with and the bookkeeping
 * it read, and would send every note wiped under it as a deletion. Signed out, a queued one ends as it starts.
 */
export function syncSettled(): Promise<void> {
  return running ?? Promise.resolve();
}

async function once(parts: Parts): Promise<void> {
  const session = accountState().session;
  const key = session ? await accountKey().catch(() => null) : null;
  if (!session || !key || preferences().localOnly) {
    setStatus({ phase: 'off', message: null });
    return;
  }
  const { token, accountId } = session;
  // And after each look at the feed, what it brought to the phone while the app is in the background, and the phone's
  // watch for while it is closed, moved on to the new cursor (core/notifications/phone.ts).
  const feed = async () => {
    const before = feedState(accountId).cursor;
    const fed = await syncNotifications({ token, read: () => feedState(accountId), update: (fn) => updateFeed(accountId, fn) });
    const rows = listed(feedState(accountId));
    void postNewRows(before, rows).catch(() => undefined);
    // And to whatever else listens for new rows: the switched-on plugins, through the registry (core/notifications/arrived.ts).
    tellArrived(before, rows);
    syncPhoneWatch();
    return fed;
  };
  const orgs = () => syncOrgs({ token, save: (state) => saveOrgs(accountId, state) });
  // And the keys the organizations need (docs/SHARED.md, S2, S3): this account's pair, and each organization's key read,
  // made or filled. Best effort: a failure here is the next pass's, and never the sync's status.
  const teamKeys = async (list: readonly OrgRow[]) => {
    try {
      const { pair } = await ensureEncryptionKey({ token, accountKey: key, keys: deviceKeys() });
      await syncOrgKeys({ token, pair, list });
    } catch {
      // Left for the next pass.
    }
  };
  if (parts === 'notifications') {
    // The notes' status stands: this is the feed and the list, and says nothing on the Account row unless it fails.
    try {
      await feed();
      await orgs();
    } catch (failure) {
      if (failure instanceof ApiError && failure.status === 401) await resume().catch(() => undefined);
      setStatus({ phase: 'error', message: failureText(failure) });
    }
    return;
  }
  if (!(await nativeReady())) {
    setStatus({ phase: 'error', message: 'Sync needs the newest Ghost.md. Install it from attack.fm/glyph.' });
    return;
  }
  setStatus({ phase: 'syncing', message: null });
  // Each step stands on its own (Matt: "i don't see an org i created on another computer and when i load the app it
  // says Syncing will try again"): a note that will not go no longer keeps the preferences, the organizations and
  // the team's notes from theirs. The first failure is the status's, named by its step; a lapsed session still ends
  // the pass, as every step after it would be refused too.
  let failed: string | null = null;
  const step = async <T>(name: string, run: () => Promise<T>): Promise<T | undefined> => {
    try {
      return await run();
    } catch (failure) {
      if (failure instanceof ApiError && failure.status === 401) throw failure;
      console.warn(`[sync] ${name} failed`, failure);
      failed ??= `${name}: ${failureText(failure)}`;
      return undefined;
    }
  };
  try {
    await step('Notifications', feed);
    // The list before the notes: an organization made on another device shows here even while a note will not sync.
    const list = await step('Organizations', orgs);

    const notesKey = stateKey(session.accountId, 'notes');
    const synced = await step('Notes', () => syncNotes({
      token: session.token,
      key,
      notes: deviceNotes,
      files: deviceFiles,
      state: load<SyncState>(notesKey, emptyState()),
      save: (state) => store(notesKey, state),
      // Which notes are meetings, and whether their audio may go: their words go regardless (docs/DESIGN.md §127 section 6).
      // Read when each recording is decided, not when the pass began: a meeting finished on the Mac during a pass is
      // listed in `meetings` as it is made, and a snapshot from before it would send its audio.
      get meetings() {
        return preferences().meetings;
      },
      get syncMeetingRecordings() {
        return preferences().syncMeetingRecordings;
      },
      // A note kept twice is worth a row in the feed: the person has two copies to look at (docs/TEAMS.md, "Kinds").
      onConflict: (copy) => void record('sync-conflict', copy),
      // A note filed in an organization's workspace is the team's (docs/SHARED.md, S1): the organization channel's below.
      teamNote: (id) => {
        const space = workspaceOf(id);
        return space !== null && isOrgWorkspace(space);
      },
    }));
    if (synced?.changed) announceNotesChanged();
    const outcome = { conflicts: synced?.conflicts ?? 0, unsent: synced?.unsent ?? 0, reason: synced?.reason ?? null };

    const prefsKey = stateKey(session.accountId, 'prefs');
    await step('Preferences', async () => {
      applyingRemote = true;
      try {
        await syncPrefs({
          token: session.token,
          key,
          read: preferences,
          write: setPreferences,
          state: load<PrefsState>(prefsKey, { rev: 0, seen: null }),
          save: (state) => store(prefsKey, state),
        });
      } finally {
        applyingRemote = false;
      }
    });
    if (list) {
      await teamKeys(list);
      // The organization channel (core/team/sync.ts), for each organization joined whose key this device holds.
      for (const row of list) {
        if (row.state !== 'member') continue;
        const orgKey = orgKeyOf(row.id);
        if (!orgKey) continue;
        const teamKey = stateKey(session.accountId, `team-${row.id}`);
        const workspace = orgWorkspaceId(row.id);
        const team = await syncTeamNotes({
          token: session.token,
          orgId: row.id,
          key: orgKey,
          notes: deviceNotes,
          files: deviceFiles,
          docs: deviceDocs(),
          state: load<TeamSyncState>(teamKey, emptyTeamState()),
          save: (state) => store(teamKey, state),
          isTeamNote: (id) => workspaceOf(id)?.id === workspace,
          file: (id) => fileNote(id, workspace),
        });
        if (team.changed) announceNotesChanged();
        outcome.unsent += team.unsent;
        outcome.reason ??= team.reason;
      }
    }
    if (failed) setStatus({ phase: 'error', message: failed, conflicts: outcome.conflicts, unsent: outcome.unsent, unsentReason: outcome.reason });
    else setStatus({ phase: 'idle', lastAt: Date.now(), message: null, conflicts: outcome.conflicts, unsent: outcome.unsent, unsentReason: outcome.reason });
  } catch (failure) {
    if (failure instanceof ApiError && failure.status === 401) {
      // The session lapsed mid-sync: renew it (with this device's key if need be) and go again next time.
      await resume().catch(() => undefined);
    }
    setStatus({ phase: 'error', message: failureText(failure) });
  }
}

let quiet: ReturnType<typeof setTimeout> | null = null;
let applyingRemote = false;

/** A sync a moment from now, pushed back by every change in between. */
function syncSoon(): void {
  if (quiet) clearTimeout(quiet);
  quiet = setTimeout(() => {
    quiet = null;
    void syncNow();
  }, QUIET_MS);
}

let started = false;

/**
 * Starts syncing for the life of the page: renews the session, syncs, and then syncs on the triggers above. Safe to
 * call more than once.
 */
export function startSync(): () => void {
  if (started) return () => undefined;
  started = true;
  // Nothing at all for a device that was never signed in; for one that was, all of it after first render, and
  // nothing it does can throw into the launch.
  const signedIn = accountState().session !== null;
  if (signedIn) {
    setTimeout(() => {
      void resume()
        .then(() => syncNow())
        .catch(() => undefined);
    }, 0);
  }
  const active = () => accountState().session !== null;
  const onVisible = () => {
    if (active() && document.visibilityState === 'visible') void syncNow();
  };
  const onChanged = () => {
    if (active()) syncSoon();
  };
  document.addEventListener('visibilitychange', onVisible);
  window.addEventListener(NOTE_SAVED, onChanged);
  const unprefs = onPreferences(() => {
    // The switches and mutes the phone reads with, as they are now, whoever changed them.
    syncPhoneWatch();
    if (active() && !applyingRemote) syncSoon();
  });
  const unaccount = onAccount(syncPhoneWatch);
  const timer = setInterval(() => {
    if (active()) void syncNow();
  }, EVERY_MS);
  return () => {
    started = false;
    document.removeEventListener('visibilitychange', onVisible);
    window.removeEventListener(NOTE_SAVED, onChanged);
    unprefs();
    unaccount();
    clearInterval(timer);
  };
}
