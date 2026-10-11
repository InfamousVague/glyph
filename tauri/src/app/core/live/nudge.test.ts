import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Session } from '../account/keystore.ts';
import type { RoomListener } from './hub.ts';

/**
 * The word between an organization's devices that there is something to fetch (core/live/nudge.ts; Matt: "make this
 * instantaneous syncing should be real-time"): a device without the key asks, one with it wraps and says so, the
 * asker reads its wrap and fetches; and a device that wrote says so, and the others fetch.
 */
let session: Session | null = { token: 't', handle: 'matt', accountId: 7 };
vi.mock('../account/account.ts', () => ({ accountState: () => ({ session }), onAccount: () => () => undefined }));
const orgs = vi.hoisted(() => ({ list: [] as { id: string; state: string }[], listeners: new Set<() => void>() }));
vi.mock('../orgs/orgs.ts', () => ({ orgsState: () => ({ list: orgs.list }), onOrgs: (l: () => void) => (orgs.listeners.add(l), () => orgs.listeners.delete(l)) }));
const keys = vi.hoisted(() => ({ held: new Set<string>(), listeners: new Set<() => void>() }));
vi.mock('../orgs/orgKeys.ts', () => ({ orgKeyOf: (id: string) => (keys.held.has(id) ? ({} as CryptoKey) : null), onOrgKeys: (l: () => void) => (keys.listeners.add(l), () => keys.listeners.delete(l)) }));
vi.mock('../preferences.ts', () => ({ preferences: () => ({ localOnly: false }), onPreferences: () => () => undefined }));
const hub = vi.hoisted(() => ({ rooms: new Map<string, RoomListener>(), sent: [] as string[] }));
vi.mock('./hub.ts', () => ({
  holdRoom: (room: string, listener: RoomListener, org?: string) => {
    hub.rooms.set(`${org}/${room}`, listener);
    return { join: () => undefined, leave: () => undefined, close: () => undefined, send: (r: string, data: string, _to?: number, o?: string) => void hub.sent.push(`${o}/${r}:${atob(data)}`) };
  },
  releaseRoom: (room: string, org?: string) => void hub.rooms.delete(`${org}/${room}`),
}));

let nudge: typeof import('./nudge.ts');
const calls = { keys: 0, notes: 0 };
let onKeys: () => void = () => undefined;
const hooks = { keys: async () => void ((calls.keys += 1), onKeys()), notes: async () => void (calls.notes += 1) };
const settled = () => new Promise((done) => setTimeout(done, 450));

beforeEach(async () => {
  vi.resetModules();
  session = { token: 't', handle: 'matt', accountId: 7 };
  orgs.list = [{ id: 'o1', state: 'member' }, { id: 'o2', state: 'invited' }];
  keys.held.clear();
  hub.rooms.clear();
  hub.sent.length = 0;
  calls.keys = 0;
  calls.notes = 0;
  onKeys = () => undefined;
  nudge = await import('./nudge.ts');
});

describe('the word that there is something to fetch', () => {
  it('holds each joined organization’s room, key or no key, and asks for the key when someone is there to give it', async () => {
    const stop = nudge.watchNudges(hooks);
    expect(nudge.heldNudges()).toEqual(['o1']);
    const room = hub.rooms.get('o1/sync')!;
    room.joined(false, 1);
    await settled();
    // Its own keys step first (the key pair registered, a wrap read if one is there), then the question.
    expect(calls.keys).toBe(1);
    expect(hub.sent).toEqual(['o1/sync:need']);
    // A wrap was made: the keys step again, which brings the key, and the team's notes are fetched.
    onKeys = () => keys.held.add('o1');
    await room.message(4, btoa('keys').replace(/=+$/, ''));
    await settled();
    expect(calls.keys).toBe(2);
    expect(calls.notes).toBeGreaterThanOrEqual(1);
    stop();
    expect(nudge.heldNudges()).toEqual([]);
  });

  it('wraps for whoever asks when it holds the key and says so, fetches when told something changed, and tells when it wrote', async () => {
    keys.held.add('o1');
    const stop = nudge.watchNudges(hooks);
    const room = hub.rooms.get('o1/sync')!;
    await settled();
    const fetched = calls.notes;
    await room.message(9, btoa('need').replace(/=+$/, ''));
    await settled();
    expect(calls.keys).toBe(1);
    expect(hub.sent).toEqual(['o1/sync:keys']);
    await room.message(9, btoa('changed').replace(/=+$/, ''));
    await room.message(9, btoa('changed').replace(/=+$/, ''));
    await settled();
    expect(calls.notes).toBe(fetched + 1);
    nudge.tellChanged('o1');
    nudge.tellChanged('o9');
    expect(hub.sent).toEqual(['o1/sync:keys', 'o1/sync:changed']);
    stop();
  });
});
