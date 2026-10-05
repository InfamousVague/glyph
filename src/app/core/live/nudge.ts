import { accountState } from '../account/account.ts';
import { onOrgKeys, orgKeyOf } from '../orgs/orgKeys.ts';
import { onOrgs, orgsState } from '../orgs/orgs.ts';
import { onPreferences, preferences } from '../preferences.ts';
import { holdRoom, releaseRoom } from './hub.ts';
import type { LiveTransport } from './transport.ts';

/**
 * A word between an organization's devices that there is something to fetch (Matt: "when users first go to an
 * organization it takes a while for the notes to sync locally ... make this instantaneous syncing should be
 * real-time"). The sync itself is passes (docs/SYNC.md, SHARED.md S4): a device wrote, and the others heard at their
 * next pass, five minutes apart - so a member who had just joined waited a pass for someone to wrap the key for
 * them, a pass to read it, and a pass for the notes. Every member's device now holds the organization's `sync` room
 * on the relay while the app is open, and says three things in it, none of them a secret and none of them sealed -
 * a device without the key yet must be able to say and hear them:
 *
 * - **need**: this device is in the organization and has no key. Said on joining the room and whenever someone
 *   else comes into it. A device that holds the key wraps for whoever lacks one at once, then says **keys**.
 * - **keys**: a wrap was just made. A device without the key reads its wrap and fetches the team's notes.
 * - **changed**: this device just wrote to the organization (a note, an update, a file). The others sync now.
 *
 * What is fetched is still the sealed rows, by the pass; this only says when. No Yjs here: the hub and a few bytes.
 */

const ROOM = 'sync';
/** The three words, as the base64url the relay insists on. */
const NEED = 'bmVlZA';
const KEYS = 'a2V5cw';
const CHANGED = 'Y2hhbmdlZA';
/** Several words in a breath are one fetch. */
const SETTLE_MS = 400;

export interface NudgeHooks {
  /** The keys step: the list read and whoever lacks a wrap wrapped for, or this device's wrap read (engine `syncNotificationsNow`). */
  keys(): Promise<unknown>;
  /** A whole pass now (engine `syncNow`). */
  notes(): Promise<unknown>;
}

const held = new Map<string, LiveTransport>();
let hooks: NudgeHooks | null = null;
let fetching: ReturnType<typeof setTimeout> | null = null;

function say(orgId: string, word: string): void {
  held.get(orgId)?.send(ROOM, word, undefined, orgId);
}

/** This device just wrote to the organization: the others fetch now. Nothing when its room is not held. */
export function tellChanged(orgId: string): void {
  say(orgId, CHANGED);
}

function fetchSoon(): void {
  if (fetching) return;
  fetching = setTimeout(() => {
    fetching = null;
    void hooks?.notes();
  }, SETTLE_MS);
}

/** The key seen to, and what follows from it said: wrapped for someone, or read here and the notes fetched. */
async function seeToKeys(orgId: string): Promise<void> {
  const had = orgKeyOf(orgId) !== null;
  await hooks?.keys();
  const has = orgKeyOf(orgId) !== null;
  if (has && had) say(orgId, KEYS);
  if (has && !had) fetchSoon();
}

function hold(orgId: string): void {
  // Without the key: this account's key pair is registered and any wrap already there read first (the keys step), so
  // that whoever answers finds a public key to wrap for; then, still without it, the room is asked.
  const needs = () => {
    if (orgKeyOf(orgId) !== null) return;
    void (async () => {
      await hooks?.keys();
      if (orgKeyOf(orgId) === null) say(orgId, NEED);
      else fetchSoon();
    })();
  };
  const transport = holdRoom(
    ROOM,
    {
      joined: (_first, peers) => {
        if (peers > 0) needs();
        // Back in the room, first time or after a drop: whatever was written meanwhile is fetched.
        fetchSoon();
      },
      peersChanged: (peers, left) => {
        if (left === undefined && peers > 0) needs();
      },
      message: (_from, data) => {
        if (data === NEED && orgKeyOf(orgId) !== null) void seeToKeys(orgId);
        else if (data === KEYS && orgKeyOf(orgId) === null) void seeToKeys(orgId);
        else if (data === CHANGED) fetchSoon();
      },
    },
    orgId,
  );
  held.set(orgId, transport);
}

/** The organizations whose `sync` room this device holds, for tests. */
export function heldNudges(): string[] {
  return [...held.keys()];
}

/**
 * Holds every joined organization's `sync` room while signed in and not local-only, key or no key, and lets each go
 * when that stops being so. A key newly in hand here is told to the room, since it may be the wrap someone waits to
 * hear was made. Answers the way to stop.
 */
export function watchNudges(with_: NudgeHooks): () => void {
  hooks = with_;
  const keyed = new Set<string>();
  const settle = () => {
    const session = accountState().session;
    const wanted = session && !preferences().localOnly ? orgsState().list.filter((row) => row.state === 'member').map((row) => row.id) : [];
    for (const id of [...held.keys()]) {
      if (wanted.includes(id)) continue;
      held.delete(id);
      keyed.delete(id);
      releaseRoom(ROOM, id);
    }
    for (const id of wanted) {
      if (!held.has(id)) hold(id);
      const has = orgKeyOf(id) !== null;
      // The key just came to this device: its notes are fetched now, not at the next pass.
      if (has && !keyed.has(id)) fetchSoon();
      if (has) keyed.add(id);
      else keyed.delete(id);
    }
  };
  settle();
  const stops = [onOrgs(settle), onOrgKeys(settle), onPreferences(settle)];
  return () => {
    stops.forEach((stop) => stop());
    for (const id of [...held.keys()]) releaseRoom(ROOM, id);
    held.clear();
    hooks = null;
    if (fetching) clearTimeout(fetching);
    fetching = null;
  };
}
