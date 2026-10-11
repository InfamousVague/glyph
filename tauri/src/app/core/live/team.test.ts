import { describe, expect, it } from 'vitest';
import { Awareness, encodeAwarenessUpdate } from 'y-protocols/awareness';
import * as Y from 'yjs';
import { newAccountKey, settle } from '../sync/crypto.ts';
import type { RoomListener } from './hub.ts';
import { REMOTE } from './session.ts';
import { TeamRoom, caretIndexes, lacks, type LiveDoc, type Me } from './team.ts';
import type { LiveTransport } from './transport.ts';
import { Kind, sealTeamEnvelope } from './wire.ts';

/**
 * A team's rooms (core/live/team.ts; docs/SHARED.md, S6) against a relay in memory that keeps the real one's
 * promises for an organization's rooms (server/src/live.rs): rooms per organization, the first in told so, every
 * join and leave told to the others with who left, messages to everyone else or to one connection, and all of it
 * delivered a turn later, never in the same breath. The rooms are real, sealing under a real key.
 */

const ROUNDS = 100;
const ORG = 'org-1';

class Relay {
  private rooms = new Map<string, Device[]>();
  private next = 1;
  private devices: Device[] = [];
  private deliveries = new Set<Promise<void>>();

  device(): Device {
    const device = new Device(this, this.next++);
    this.devices.push(device);
    return device;
  }

  hold(device: Device, room: string, listener: RoomListener, org: string): LiveTransport {
    const key = `${org}/${room}`;
    device.listeners.set(key, listener);
    const members = this.rooms.get(key) ?? [];
    const first = members.length === 0;
    members.push(device);
    this.rooms.set(key, members);
    this.later(() => listener.joined(first, members.length - 1));
    for (const other of members) if (other !== device) this.later(() => other.listeners.get(key)?.peersChanged(members.length - 1));
    return device;
  }

  release(device: Device, room: string, org: string): void {
    const key = `${org}/${room}`;
    device.listeners.delete(key);
    const members = (this.rooms.get(key) ?? []).filter((m) => m !== device);
    this.rooms.set(key, members);
    for (const other of members) this.later(() => other.listeners.get(key)?.peersChanged(members.length - 1, device.id));
  }

  send(device: Device, room: string, data: string, to: number | undefined, org: string): void {
    const key = `${org}/${room}`;
    for (const other of this.rooms.get(key) ?? []) {
      if (other === device || (to !== undefined && other.id !== to)) continue;
      this.later(() => other.listeners.get(key)?.message(device.id, data));
    }
  }

  /** Every message in flight delivered and every answer sealed, round after round, until nobody has more to say. */
  async settled(): Promise<void> {
    for (let round = 0; round < ROUNDS; round += 1) {
      await Promise.all(this.deliveries);
      if (this.deliveries.size > 0) continue;
      await Promise.all(this.devices.flatMap((device) => [...device.listeners.values()].map((held) => (held instanceof TeamRoom ? held.sent() : undefined))));
      if (this.deliveries.size === 0) return;
    }
    throw new Error(`The rooms were still talking after ${ROUNDS} rounds, ${this.deliveries.size} messages in flight.`);
  }

  private later(run: () => void | Promise<void>) {
    const delivery: Promise<void> = new Promise<void>((arrive) => setTimeout(arrive, 0))
      .then(run)
      .finally(() => this.deliveries.delete(delivery));
    this.deliveries.add(delivery);
  }
}

class Device implements LiveTransport {
  readonly listeners = new Map<string, RoomListener>();
  constructor(
    private relay: Relay,
    readonly id: number,
  ) {}
  join() {}
  leave() {}
  send(room: string, data: string, to?: number, org?: string) {
    this.relay.send(this, room, data, to, org ?? '');
  }
  close() {}
}

/** A team note's document as a device holds it (core/team/doc.ts), the part a room reads: from a state, or seeded. */
function document(from: Uint8Array | string): LiveDoc & { words(): string } {
  const doc = new Y.Doc();
  const text = doc.getText('body');
  if (typeof from === 'string') text.insert(0, from);
  else Y.applyUpdate(doc, from, REMOTE);
  return {
    doc,
    text,
    applyRemote(updates) {
      doc.transact(() => updates.forEach((update) => Y.applyUpdate(doc, update, REMOTE)), REMOTE);
      return text.toString();
    },
    words: () => text.toString(),
  };
}

const me = (name: string, hue: string | null = null): Me => ({ name, hue, color: `caret-${hue ?? 'ink'}`, colorLight: `wash-${hue ?? 'ink'}` });

async function orgKey(): Promise<CryptoKey> {
  return settle(await newAccountKey());
}

function open(relay: Relay, key: CryptoKey, room: string, who: Me, doc?: LiveDoc): TeamRoom {
  const device = relay.device();
  return new TeamRoom(ORG, room, who, { key, doc, hold: (r, listener, org) => relay.hold(device, r, listener, org), release: (r, org) => relay.release(device, r, org) });
}

/** The other devices' states in a room, by handle. */
function others(room: TeamRoom): Record<string, { hue: string | null; cursor?: unknown; at?: unknown }> {
  const out: Record<string, { hue: string | null; cursor?: unknown; at?: unknown }> = {};
  for (const [client, state] of room.awareness.getStates()) {
    if (client === room.awareness.clientID) continue;
    const user = state.user as Me;
    out[user.name] = { hue: user.hue, cursor: state.cursor, at: state.at };
  }
  return out;
}

describe('a team note live between members', () => {
  it('carries typing as it is made, and catches a device up both ways when it joins', async () => {
    const relay = new Relay();
    const key = await orgKey();
    const a = document('Hello');
    // The note as the organization's row first had it: what every member's device adopted.
    const original = Y.encodeStateAsUpdate(a.doc);
    const roomA = open(relay, key, 'n1', me('matt', 'rose'), a);
    await relay.settled();
    const b = document(original);
    const roomB = open(relay, key, 'n1', me('sam', 'sea'), b);
    await relay.settled();
    expect(roomA.others).toBe(1);
    expect(roomB.others).toBe(1);

    a.text.insert(5, ' world');
    await relay.settled();
    expect(b.words()).toBe('Hello world');
    b.text.insert(0, 'Oh. ');
    await relay.settled();
    expect(a.words()).toBe('Oh. Hello world');

    // lee's device was away with the note as it first was, and typed into it offline. Joining, it asks for what it
    // lacks and is asked for what the others lack, and all three agree without a pass.
    const c = document(original);
    c.text.insert(2, '-');
    const roomC = open(relay, key, 'n1', me('lee'), c);
    await relay.settled();
    expect(c.words()).toBe('Oh. He-llo world');
    expect(a.words()).toBe('Oh. He-llo world');
    expect(b.words()).toBe('Oh. He-llo world');
    expect(roomA.others).toBe(2);
    roomA.close();
    roomB.close();
    roomC.close();
  });

  it('shows each member’s caret in their colour with their handle, and drops it the moment their connection leaves', async () => {
    const relay = new Relay();
    const key = await orgKey();
    const a = document('Hello world');
    const roomA = open(relay, key, 'n1', me('matt', 'rose'), a);
    const b = document(Y.encodeStateAsUpdate(a.doc));
    const roomB = open(relay, key, 'n1', me('sam', 'sea'), b);
    const c = document(Y.encodeStateAsUpdate(a.doc));
    const roomC = open(relay, key, 'n1', me('lee'), c);
    await relay.settled();
    expect(Object.keys(others(roomA)).sort()).toEqual(['lee', 'sam']);
    expect(others(roomB).matt).toEqual({ hue: 'rose', cursor: undefined, at: undefined });

    // matt's caret after "Hello", as the binding would say it: relative to the document, so it holds as words change.
    const at = Y.createRelativePositionFromTypeIndex(a.text, 5);
    roomA.awareness.setLocalStateField('cursor', { anchor: Y.relativePositionToJSON(at), head: Y.relativePositionToJSON(at) });
    await relay.settled();
    const seen = others(roomB).matt?.cursor as { anchor: unknown; head: unknown };
    expect(seen).toBeDefined();
    expect(caretIndexes(b, seen)).toEqual({ anchor: 5, head: 5 });
    // Words typed before it on sam's device move it along.
    b.text.insert(0, 'Oh. ');
    await relay.settled();
    expect(caretIndexes(b, seen)).toEqual({ anchor: 9, head: 9 });

    roomA.close();
    await relay.settled();
    expect(Object.keys(others(roomB))).toEqual(['lee']);
    expect(Object.keys(others(roomC))).toEqual(['sam']);
    expect(roomB.others).toBe(1);
    roomB.close();
    roomC.close();
  });

  it('ignores a message it cannot open: sealed for another room, or under another key', async () => {
    const relay = new Relay();
    const key = await orgKey();
    const a = document('Hello');
    const roomA = open(relay, key, 'n1', me('matt'), a);
    const b = document(Y.encodeStateAsUpdate(a.doc));
    const roomB = open(relay, key, 'n1', me('sam'), b);
    await relay.settled();
    // A device that somehow sends into n1 what it sealed for n2, and one with another organization's key.
    const stray = new Awareness(new Y.Doc());
    stray.setLocalStateField('user', me('stranger'));
    const presence = { kind: Kind.Presence, payload: encodeAwarenessUpdate(stray, [stray.clientID]) } as const;
    const forN2 = await sealTeamEnvelope(key, ORG, 'n2', presence);
    const otherKey = await sealTeamEnvelope(await orgKey(), ORG, 'n1', presence);
    const update = Y.encodeStateAsUpdate(document('Not this').doc);
    const forN2Update = await sealTeamEnvelope(key, ORG, 'n2', { kind: Kind.Update, payload: update });
    await Promise.all([roomB.message(9, forN2), roomB.message(9, otherKey), roomB.message(9, forN2Update)]);
    await relay.settled();
    expect(Object.keys(others(roomB))).toEqual(['matt']);
    expect(b.words()).toBe('Hello');
    stray.destroy();
    roomA.close();
    roomB.close();
  });
});

describe('an organization’s own room', () => {
  it('says where each device is, and forgets a device with its connection', async () => {
    const relay = new Relay();
    const key = await orgKey();
    const roomA = open(relay, key, 'presence', me('matt', 'rose'));
    const roomB = open(relay, key, 'presence', me('sam', 'sea'));
    await relay.settled();
    roomA.awareness.setLocalStateField('at', { note: 'n1', title: 'Roadmap', kind: 'note', cursor: null, pointer: null });
    await relay.settled();
    expect(others(roomB).matt?.at).toEqual({ note: 'n1', title: 'Roadmap', kind: 'note', cursor: null, pointer: null });
    expect(others(roomA).sam).toEqual({ hue: 'sea', cursor: undefined, at: undefined });
    // A colour picked while the room is open.
    roomA.setMe(me('matt', 'moss'));
    await relay.settled();
    expect(others(roomB).matt?.hue).toBe('moss');
    roomA.close();
    await relay.settled();
    expect(others(roomB)).toEqual({});
    roomB.close();
  });
});

describe('what a room reads', () => {
  it('knows when another device’s state vector holds something this one lacks', () => {
    const a = new Y.Doc();
    a.getText('body').insert(0, 'a');
    const b = new Y.Doc();
    Y.applyUpdate(b, Y.encodeStateAsUpdate(a));
    expect(lacks(Y.encodeStateVector(a), Y.encodeStateVector(b))).toBe(false);
    b.getText('body').insert(1, 'b');
    expect(lacks(Y.encodeStateVector(a), Y.encodeStateVector(b))).toBe(true);
    expect(lacks(Y.encodeStateVector(b), Y.encodeStateVector(a))).toBe(false);
  });

  it('places a caret from the same lineage, and not one from another document', () => {
    const a = document('Hello world');
    const at = Y.createRelativePositionFromTypeIndex(a.text, 6);
    const caret = { anchor: Y.relativePositionToJSON(at), head: Y.relativePositionToJSON(Y.createRelativePositionFromTypeIndex(a.text, 11)) };
    expect(caretIndexes(a, caret)).toEqual({ anchor: 6, head: 11 });
    const b = document(Y.encodeStateAsUpdate(a.doc));
    expect(caretIndexes(b, caret)).toEqual({ anchor: 6, head: 11 });
    const stranger = document('Hello world');
    expect(caretIndexes(stranger, caret)).toBeNull();
    expect(caretIndexes(a, { anchor: 'nonsense', head: null })).toBeNull();
  });
});
