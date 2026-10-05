import { useSyncExternalStore } from 'react';
import { accountState } from '../account/account.ts';
import { externalStore } from '../externalStore.ts';
import { onOrgKeys, orgKeyOf } from '../orgs/orgKeys.ts';
import { onOrgs, orgRow, orgsState } from '../orgs/orgs.ts';
import { onPreferences, preferences } from '../preferences.ts';
import type { Me, TeamRoom } from './team.ts';

/**
 * Who is in each organization right now, and where (docs/SHARED.md, S6): every member's device holds the
 * organization's own room while the app is open and signed in, and says in it which note or canvas it has open and
 * where its caret or pointer is, so the dashboard reads "editing Roadmap" beside a member and Jump to cursor opens
 * that note at that place. Nothing of it is kept: a device that leaves is gone from the list the moment the relay
 * says so.
 *
 * The rooms themselves are core/live/team.ts, loaded on demand with Yjs the first time an organization needs one, so
 * an account in no organization downloads none of it; this module is the store the screens read, and the switch.
 */

/** The room name of an organization's own room: not a note id, which is what every other room is. */
export const PRESENCE_ROOM = 'presence';

/** A caret as Yjs relative positions (`Y.relativePositionToJSON`): good in every member's copy of the document. */
export interface Caret {
  anchor: unknown;
  head: unknown;
}

/** Where a device is in an organization: the note or canvas it has open, and the place in it. */
export interface Whereabouts {
  note: string;
  title: string;
  kind: 'note' | 'canvas';
  cursor: Caret | null;
  /** On a canvas: the pointer's place in canvas space (S9). */
  pointer: { x: number; y: number } | null;
}

/** One device of a member's, as the room has it. */
export interface Seen {
  handle: string;
  hue: string | null;
  at: Whereabouts | null;
  client: number;
}

/** The hues' angles, as ink.css sets them (`[data-hue]`, "the workspace hues"): kept in step by hand. */
const HUE_ANGLES: Record<string, number> = { ember: 32, amber: 75, moss: 150, sea: 230, violet: 295, rose: 355 };

/**
 * A hue as CSS for a caret and for its selection's wash, at the lightness this paper needs: `--app-hue-lift` and
 * `--app-hue-chroma` are read where the caret is drawn, so it reads on white, on black and on an inverted card.
 */
export function caretColours(hue: string | null): { color: string; colorLight: string } {
  const angle = hue ? HUE_ANGLES[hue] : undefined;
  if (angle === undefined) return { color: 'var(--app-ink)', colorLight: 'color-mix(in oklch, var(--app-ink) 20%, transparent)' };
  return { color: `oklch(var(--app-hue-lift) var(--app-hue-chroma) ${angle})`, colorLight: `oklch(var(--app-hue-lift) var(--app-hue-chroma) ${angle} / 0.24)` };
}

/** This account in an organization: its handle, and the colour it wears there (the override, else the account's). */
export function meIn(orgId: string): Me {
  const handle = accountState().session?.handle ?? '';
  const hue = orgRow(orgId)?.colour ?? null;
  return { name: handle, hue, ...caretColours(hue) };
}

const rooms = new Map<string, TeamRoom>();
const seen = new Map<string, readonly Seen[]>();
/** What this device last said of itself per organization, said again when the room comes. */
const announced = new Map<string, Whereabouts | null>();
const NONE: readonly Seen[] = [];
const changes = externalStore(0);

function refresh(orgId: string): void {
  const room = rooms.get(orgId);
  const list: Seen[] = [];
  if (room) {
    for (const [client, state] of room.awareness.getStates()) {
      if (client === room.awareness.clientID) continue;
      const user = state.user as Partial<Me> | undefined;
      if (!user?.name) continue;
      list.push({ handle: user.name, hue: user.hue ?? null, at: (state.at as Whereabouts | null | undefined) ?? null, client });
    }
  }
  seen.set(orgId, list);
  changes.update((n) => n + 1);
}

/** The other members' devices in an organization, as last heard; none while this device holds no room of it. */
export function presenceIn(orgId: string): readonly Seen[] {
  return seen.get(orgId) ?? NONE;
}

export const onPresence = changes.subscribe;

export function usePresence(orgId: string): readonly Seen[] {
  return useSyncExternalStore(
    onPresence,
    () => presenceIn(orgId),
    () => NONE,
  );
}

/** Where this device is in an organization - a note or a canvas open, and the caret or pointer in it - or nowhere. */
export function announce(orgId: string, at: Whereabouts | null): void {
  announced.set(orgId, at);
  rooms.get(orgId)?.awareness.setLocalStateField('at', at);
}

/** The organizations whose rooms this device holds, for tests. */
export function heldPresence(): string[] {
  return [...rooms.keys()];
}

function drop(orgId: string): void {
  rooms.get(orgId)?.close();
  rooms.delete(orgId);
  seen.delete(orgId);
  changes.update((n) => n + 1);
}

/**
 * Holds the organization's own room for every organization this account is a member of and holds the key to, while
 * signed in and not local-only, and lets each go when that stops being so; the colour worn is said again when it
 * changes. Answers the way to stop, which lets every room go.
 */
export function watchPresence(): () => void {
  let stopped = false;
  let settling: Promise<void> = Promise.resolve();
  const settleNow = async () => {
    if (stopped) return;
    const session = accountState().session;
    const wanted = session && !preferences().localOnly ? orgsState().list.filter((row) => row.state === 'member' && orgKeyOf(row.id) !== null).map((row) => row.id) : [];
    for (const id of [...rooms.keys()]) if (!wanted.includes(id)) drop(id);
    if (wanted.length === 0) return;
    const { openPresenceRoom } = await import('./team.ts');
    if (stopped) return;
    for (const id of wanted) {
      const held = rooms.get(id);
      if (held) {
        const me = meIn(id);
        if (JSON.stringify(held.awareness.getLocalState()?.user) !== JSON.stringify(me)) held.setMe(me);
        continue;
      }
      const room = openPresenceRoom(id);
      if (!room) continue;
      rooms.set(id, room);
      room.awareness.on('change', () => refresh(id));
      const at = announced.get(id);
      if (at !== undefined) room.awareness.setLocalStateField('at', at);
      refresh(id);
    }
  };
  const settle = () => {
    settling = settling.then(settleNow).catch(() => undefined);
  };
  settle();
  const stops = [onOrgs(settle), onOrgKeys(settle), onPreferences(settle)];
  return () => {
    stopped = true;
    stops.forEach((stop) => stop());
    for (const id of [...rooms.keys()]) drop(id);
  };
}
