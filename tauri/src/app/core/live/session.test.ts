import { describe, expect, it } from 'vitest';
import { newAccountKey, settle } from '../sync/crypto.ts';
import { LiveSession, type SessionDeps } from './session.ts';
import type { LiveTransport } from './transport.ts';

/** How many rounds of messages a room may trade before settling is given up on as a room that never goes quiet. */
const ROUNDS = 100;

/**
 * A relay in memory that keeps the real one's promises (server/src/live.rs): rooms per account, the first into a room
 * told so, a count of the others on every join and leave, messages to everyone else or to one device - and delivered
 * a turn later, as a network would, never in the same breath they were sent.
 */
class Relay {
  private rooms = new Map<string, Device[]>();
  private next = 1;
  private devices: Device[] = [];
  /** Every delivery scheduled and not yet done, the opening of the message included. */
  private deliveries = new Set<Promise<void>>();
  device(): Device {
    const device = new Device(this, this.next++);
    this.devices.push(device);
    return device;
  }
  join(device: Device, room: string) {
    const members = this.rooms.get(room) ?? [];
    const first = members.length === 0;
    members.push(device);
    this.rooms.set(room, members);
    this.later(() => device.session?.joined(first, members.length - 1));
    for (const other of members) if (other !== device) this.later(() => other.session?.peersChanged(members.length - 1));
  }
  leave(device: Device, room: string) {
    const members = (this.rooms.get(room) ?? []).filter((m) => m !== device);
    this.rooms.set(room, members);
    for (const other of members) this.later(() => other.session?.peersChanged(members.length - 1));
  }
  send(device: Device, room: string, data: string, to?: number) {
    for (const other of this.rooms.get(room) ?? []) {
      if (other === device || (to !== undefined && other.id !== to)) continue;
      this.later(() => other.session?.message(device.id, data));
    }
  }

  /**
   * Lets every message in flight arrive, and every answer to one be sealed and sent, until the room has nothing
   * left to say - asked of the relay and the sessions, never timed. The 60ms this once slept was less than the
   * WebCrypto work took on a loaded machine; the quiet window that replaced it (six empty 15ms ticks, then give up
   * at five seconds without a word) was still a guess, since a session seals its answer off the relay's books and a
   * slow enough seal outlasted the window. So a round here waits for the deliveries, then for each session's seal
   * chain (LiveSession.sent), and the room is settled when a round ends with nothing new sent. A room still talking
   * after ROUNDS rounds throws, rather than letting a test go on to assert against a room mid-sentence.
   */
  async settled(): Promise<void> {
    for (let round = 0; round < ROUNDS; round += 1) {
      await Promise.all(this.deliveries);
      if (this.deliveries.size > 0) continue;
      await Promise.all(this.devices.map((device) => device.session?.sent()));
      if (this.deliveries.size === 0) return;
    }
    throw new Error(`The room was still talking after ${ROUNDS} rounds of messages, ${this.deliveries.size} of them in flight.`);
  }

  private later(run: () => void | Promise<void>) {
    const delivery: Promise<void> = new Promise<void>((arrive) => setTimeout(arrive, 0))
      .then(run)
      .finally(() => this.deliveries.delete(delivery));
    this.deliveries.add(delivery);
  }
}

class Device implements LiveTransport {
  session: LiveSession | null = null;
  constructor(
    private relay: Relay,
    readonly id: number,
  ) {}
  join(room: string) {
    this.relay.join(this, room);
  }
  leave(room: string) {
    this.relay.leave(this, room);
  }
  send(room: string, data: string, to?: number) {
    this.relay.send(this, room, data, to);
  }
  close() {}
}

/** An account key as a device holds one: made, then settled into a non-extractable key. */
async function accountKey(): Promise<CryptoKey> {
  return settle(await newAccountKey());
}

interface Opened {
  session: LiveSession;
  ready: string | null;
  copies: string[];
}

function open(relay: Relay, key: CryptoKey, words: string, unsynced = false): Opened {
  const device = relay.device();
  const opened: Opened = { session: null as unknown as LiveSession, ready: null, copies: [] };
  const deps: SessionDeps = {
    transport: device,
    key,
    hasUnsynced: () => unsynced,
    keepCopy: async (_id, kept) => void opened.copies.push(kept),
    schedule: () => null,
  };
  opened.session = new LiveSession('note-1', words, deps, {
    ready: (shown) => (opened.ready = shown),
    peers: () => {},
  });
  device.session = opened.session;
  return opened;
}

describe('a note live on two devices', () => {
  it('is made by the first device and adopted by the second, never built twice', async () => {
    const relay = new Relay();
    const key = await accountKey();
    const phone = open(relay, key, 'Groceries\n- milk');
    await relay.settled();
    const mac = open(relay, key, 'Groceries\n- milk');
    await relay.settled();
    expect(phone.ready).toBe('Groceries\n- milk');
    expect(mac.ready).toBe('Groceries\n- milk');
    // The trap this avoids: two documents each built from the same words, merged, hold the words twice.
    expect(mac.session.text.toString()).toBe('Groceries\n- milk');
    expect(mac.session.seed).toBe(phone.session.seed);
  });

  it('carries typing both ways, a character at a time', async () => {
    const relay = new Relay();
    const key = await accountKey();
    const phone = open(relay, key, 'Plan');
    await relay.settled();
    const mac = open(relay, key, 'Plan');
    await relay.settled();
    for (const letter of ' for Friday') {
      phone.session.text.insert(phone.session.text.length, letter);
    }
    await relay.settled();
    expect(mac.session.text.toString()).toBe('Plan for Friday');
    mac.session.text.insert(0, '# ');
    await relay.settled();
    expect(phone.session.text.toString()).toBe('# Plan for Friday');
  });

  it('keeps both people typing into the same spot at the same moment', async () => {
    const relay = new Relay();
    const key = await accountKey();
    const phone = open(relay, key, 'ab');
    await relay.settled();
    const mac = open(relay, key, 'ab');
    await relay.settled();
    // Both insert between a and b before either hears of the other.
    phone.session.text.insert(1, 'PHONE');
    mac.session.text.insert(1, 'MAC');
    await relay.settled();
    const words = phone.session.text.toString();
    expect(mac.session.text.toString()).toBe(words);
    expect(words).toContain('PHONE');
    expect(words).toContain('MAC');
    expect(words.startsWith('a') && words.endsWith('b')).toBe(true);
  });

  it('adopts the room when this device was only behind, and keeps no copy', async () => {
    const relay = new Relay();
    const key = await accountKey();
    open(relay, key, 'Newer words from the phone');
    await relay.settled();
    const mac = open(relay, key, 'Older words', false);
    await relay.settled();
    expect(mac.ready).toBe('Newer words from the phone');
    expect(mac.copies).toEqual([]);
  });

  it('keeps this device’s own unsent changes as a copy, rather than losing them or undoing the room', async () => {
    const relay = new Relay();
    const key = await accountKey();
    open(relay, key, 'What the phone has');
    await relay.settled();
    const mac = open(relay, key, 'What the Mac typed offline', true);
    await relay.settled();
    // The room's words stand, untouched...
    expect(mac.ready).toBe('What the phone has');
    // ...and the Mac's are kept beside them, not replayed over the phone's.
    expect(mac.copies).toEqual(['What the Mac typed offline']);
  });

  it('makes the document itself when everyone else left before answering', async () => {
    const relay = new Relay();
    const key = await accountKey();
    const phone = open(relay, key, 'x');
    await relay.settled();
    const mac = open(relay, key, 'Mac words');
    // The phone goes before the Mac's question reaches it.
    phone.session.close();
    await relay.settled();
    expect(mac.ready).toBe('Mac words');
    expect(mac.session.state).toBe('ready');
  });

  it('ignores a message it cannot open', async () => {
    const relay = new Relay();
    const phone = open(relay, await accountKey(), 'Mine');
    await relay.settled();
    await phone.session.message(99, 'not-a-sealed-message');
    expect(phone.session.text.toString()).toBe('Mine');
  });
});
