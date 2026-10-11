import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Session } from '../account/keystore.ts';
import type { OrgRow } from '../orgs/types.ts';
import type { RoomListener } from './hub.ts';

/**
 * Who is in each organization and where (core/live/presence.ts; docs/SHARED.md, S6): the organization's own room held
 * for every organization this account is in and holds the key to, let go on signing out or going local-only, this
 * device's whereabouts said in it, and the others' read from it. The rooms are real (team.ts); the hub is a stand-in
 * that records what was held and lets the test speak as the relay.
 */

let session: Session | null = { token: 't1', handle: 'matt', accountId: 7 };
vi.mock('../account/account.ts', () => ({
  accountState: () => ({ session, unlocked: session !== null }),
  onAccount: () => () => undefined,
}));
const orgs = vi.hoisted(() => ({ list: [] as OrgRow[], listeners: new Set<() => void>() }));
vi.mock('../orgs/orgs.ts', () => ({
  orgsState: () => ({ list: orgs.list, at: null, colour: null }),
  orgRow: (id: string) => orgs.list.find((row) => row.id === id) ?? null,
  onOrgs: (listener: () => void) => {
    orgs.listeners.add(listener);
    return () => orgs.listeners.delete(listener);
  },
}));
const keys = vi.hoisted(() => ({ held: new Map<string, CryptoKey>(), listeners: new Set<() => void>() }));
vi.mock('../orgs/orgKeys.ts', () => ({
  orgKeyOf: (id: string) => keys.held.get(id) ?? null,
  onOrgKeys: (listener: () => void) => {
    keys.listeners.add(listener);
    return () => keys.listeners.delete(listener);
  },
}));
const prefs = vi.hoisted(() => ({ localOnly: false, listeners: new Set<() => void>() }));
vi.mock('../preferences.ts', () => ({
  preferences: () => ({ localOnly: prefs.localOnly }),
  onPreferences: (listener: () => void) => {
    prefs.listeners.add(listener);
    return () => prefs.listeners.delete(listener);
  },
}));
/** The rooms held through the hub: by key, with the listener each was given, and what was sent into each. */
const hub = vi.hoisted(() => ({ rooms: new Map<string, RoomListener>(), sent: [] as { room: string; org?: string; data: string; to?: number }[] }));
vi.mock('./hub.ts', () => ({
  holdRoom: (room: string, listener: RoomListener, org?: string) => {
    hub.rooms.set(`${org}/${room}`, listener);
    return { join: () => undefined, leave: () => undefined, send: (r: string, data: string, to?: number, o?: string) => void hub.sent.push({ room: r, org: o, data, to }), close: () => undefined };
  },
  releaseRoom: (room: string, org?: string) => void hub.rooms.delete(`${org}/${room}`),
}));

let presence: typeof import('./presence.ts');
const { newAccountKey, settle } = await import('../sync/crypto.ts');
const { Kind, sealTeamEnvelope, openTeamEnvelope } = await import('./wire.ts');
const { Awareness, encodeAwarenessUpdate, applyAwarenessUpdate } = await import('y-protocols/awareness');
const Y = await import('yjs');

const row = (id: string, colour: string | null = null, state: OrgRow['state'] = 'member'): OrgRow => ({ id, name: id, hue: null, role: 'member', state, members: 2, createdAt: 1, colour });
const tick = () => new Promise((settled) => setTimeout(settled, 0));
/** Lets the watcher settle: the rooms module loads on demand, so a change takes a few turns to show. */
async function settled() {
  for (let i = 0; i < 10; i += 1) await tick();
}
const fire = (listeners: Set<() => void>) => listeners.forEach((listener) => listener());

beforeEach(async () => {
  vi.resetModules();
  session = { token: 't1', handle: 'matt', accountId: 7 };
  orgs.list = [];
  keys.held.clear();
  prefs.localOnly = false;
  hub.rooms.clear();
  hub.sent.length = 0;
  presence = await import('./presence.ts');
});

describe('presence in an organization', () => {
  it('holds the organization’s own room for each organization joined with a key in hand, and lets it go when that stops', async () => {
    const key = await settle(await newAccountKey());
    orgs.list = [row('org-1', 'rose'), row('org-2'), row('org-3', null, 'invited')];
    keys.held.set('org-1', key);
    const stop = presence.watchPresence();
    await settled();
    // org-2 has no key yet, and org-3 is only an invitation.
    expect(presence.heldPresence()).toEqual(['org-1']);
    expect([...hub.rooms.keys()]).toEqual(['org-1/presence']);
    keys.held.set('org-2', key);
    fire(keys.listeners);
    await settled();
    expect(presence.heldPresence()).toEqual(['org-1', 'org-2']);
    prefs.localOnly = true;
    fire(prefs.listeners);
    await settled();
    expect(presence.heldPresence()).toEqual([]);
    prefs.localOnly = false;
    fire(prefs.listeners);
    await settled();
    expect(presence.heldPresence()).toEqual(['org-1', 'org-2']);
    session = null;
    fire(orgs.listeners);
    await settled();
    expect(presence.heldPresence()).toEqual([]);
    stop();
  });

  it('says where this device is, even when said before the room came, and reads where the others are', async () => {
    const key = await settle(await newAccountKey());
    orgs.list = [row('org-1', 'rose')];
    keys.held.set('org-1', key);
    const stop = presence.watchPresence();
    presence.announce('org-1', { note: 'n1', title: 'Roadmap', kind: 'note', cursor: null, pointer: null });
    await settled();
    const room = hub.rooms.get('org-1/presence')!;
    expect(room).toBeDefined();
    // In the room: this device said who and where it is, sealed, in the organization's room.
    room.joined(false, 1);
    await settled();
    const said = hub.sent.filter((frame) => frame.room === 'presence' && frame.org === 'org-1');
    expect(said.length).toBeGreaterThan(0);
    const opened = await openTeamEnvelope(key, 'org-1', 'presence', said[0]!.data);
    expect(opened.kind).toBe(Kind.Presence);
    const heard = new Awareness(new Y.Doc());
    applyAwarenessUpdate(heard, opened.payload, 'test');
    const mine = [...heard.getStates().entries()].find(([client]) => client !== heard.clientID)![1] as { user: { name: string; hue: string | null; color: string }; at: unknown };
    expect(mine.user.name).toBe('matt');
    expect(mine.user.hue).toBe('rose');
    expect(mine.user.color).toContain('355');
    expect(mine.at).toEqual({ note: 'n1', title: 'Roadmap', kind: 'note', cursor: null, pointer: null });
    heard.destroy();

    // sam's device, heard from the relay: in the list, with where it is; gone when its connection leaves.
    const sam = new Awareness(new Y.Doc());
    sam.setLocalState({ user: { name: 'sam', hue: 'sea', color: 'c', colorLight: 'w' }, at: { note: 'n2', title: 'Budget', kind: 'note', cursor: null, pointer: null } });
    await room.message(4, await sealTeamEnvelope(key, 'org-1', 'presence', { kind: Kind.Presence, payload: encodeAwarenessUpdate(sam, [sam.clientID]) }));
    expect(presence.presenceIn('org-1')).toEqual([{ handle: 'sam', hue: 'sea', at: { note: 'n2', title: 'Budget', kind: 'note', cursor: null, pointer: null }, client: sam.clientID }]);
    room.peersChanged(0, 4);
    expect(presence.presenceIn('org-1')).toEqual([]);
    sam.destroy();
    stop();
    expect(presence.heldPresence()).toEqual([]);
  });

  it('turns a hue into a caret’s colours, and ink into the page’s', () => {
    expect(presence.caretColours('rose').color).toBe('oklch(var(--app-hue-lift) var(--app-hue-chroma) 355)');
    expect(presence.caretColours('rose').colorLight).toContain('/ 0.24');
    expect(presence.caretColours(null).color).toBe('var(--app-ink)');
    expect(presence.caretColours('ink').color).toBe('var(--app-ink)');
  });
});
