// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { WebSocketServer } from 'ws';
import { Awareness, applyAwarenessUpdate } from 'y-protocols/awareness';
import * as Y from 'yjs';
import type { RoomListener } from '../tauri/src/app/core/live/hub.ts';
import { LiveSession } from '../tauri/src/app/core/live/session.ts';
import { TeamRoom, type Me } from '../tauri/src/app/core/live/teamRoom.ts';
import { roomKey, WebSocketTransport, type WebSocketTransportOptions } from '../tauri/src/app/core/live/transport.ts';
import { Kind, openEnvelope, openTeamEnvelope } from '../tauri/src/app/core/live/wire.ts';
import { newAccountKey, settle } from '../tauri/src/app/core/sync/crypto.ts';
import { forgetTeamDocs, looseTeamDoc } from '../tauri/src/app/core/team/doc.ts';
import { fromBase64Url, open } from '../tauri/src/app/core/sync/crypto.ts';
import { chunksOf, hunksOf, LiveClient, type LivePace } from './live.ts';
import { aNote, anOrganization, connected, teamDevice } from './testKit.ts';

/**
 * Claude, live (mcp/live.ts; docs/CLAUDE_LIVE.md) against a relay in memory that keeps server/src/live.rs's
 * promises: the first frame signs in or the socket is closed with 4401, `ready` with the connection's id, rooms per
 * account and per organization, `joined` saying whether this socket opened the room and how many others are there,
 * every join and leave told to the others with who left, and messages to everyone else or to one connection, all of
 * it a turn later. The devices on the other side are the app's own code (transport.ts, teamRoom.ts, session.ts),
 * and the connector is reached through its tools, as Claude reaches it.
 */

type Socket = InstanceType<NonNullable<WebSocketTransportOptions['socket']>>;
type SocketMaker = NonNullable<WebSocketTransportOptions['socket']>;

interface Connection {
  id: number;
  url: string;
  socket: Socket & { closed: boolean };
  account: string | null;
}

/** What passed through the relay: each `msg`, by whom, to which room. */
interface Passed {
  from: number;
  url: string;
  room: string;
  org?: string;
  data: string;
}

/** A turn later, as a socket delivers: after whatever the sender does next in the same breath. */
const later = (run: () => void) => void Promise.resolve().then(run);

class Relay {
  readonly passed: Passed[] = [];
  /** Tokens the relay will not take, as an expired one is not. */
  readonly refused = new Set<string>();
  readonly connections = new Set<Connection>();
  private readonly rooms = new Map<string, Set<Connection>>();
  private next = 1;
  readonly Socket: SocketMaker;

  constructor() {
    const relay = this;
    this.Socket = class {
      closed = false;
      onopen: ((event: Event) => void) | null = null;
      onmessage: ((event: MessageEvent) => void) | null = null;
      onclose: ((event: CloseEvent) => void) | null = null;
      onerror: ((event: Event) => void) | null = null;
      private readonly connection: Connection;
      constructor(url: string) {
        this.connection = { id: relay.next++, url, socket: this as unknown as Connection['socket'], account: null };
        relay.connections.add(this.connection);
        later(() => this.onopen?.({} as Event));
      }
      send(data: string): void {
        if (this.closed) return;
        later(() => relay.receive(this.connection, data));
      }
      close(): void {
        relay.drop(this.connection, 1000);
      }
    } as unknown as SocketMaker;
  }

  /** Who is in a room now: the account's own room by its name, or an organization's as `org/room`. */
  members(key: string): string[] {
    return [...(this.rooms.get(key) ?? [])].map((c) => c.url);
  }

  /** The connector's own sockets, open now. */
  connector(): Connection[] {
    return [...this.connections].filter((c) => c.url.includes('/v1/live') && !c.socket.closed);
  }

  private key(connection: Connection, room: string, org?: string): string {
    return org ? `${org}/${room}` : `${connection.account}:${room}`;
  }

  private say(connection: Connection, frame: object): void {
    later(() => {
      if (!connection.socket.closed) connection.socket.onmessage?.({ data: JSON.stringify(frame) } as MessageEvent);
    });
  }

  private receive(connection: Connection, raw: string): void {
    if (connection.socket.closed) return;
    const frame = JSON.parse(raw) as { t: string; token?: string; room?: string; org?: string; data?: string; to?: number };
    if (connection.account === null) {
      if (frame.t !== 'auth' || !frame.token || this.refused.has(frame.token)) {
        this.drop(connection, 4401);
        return;
      }
      connection.account = 'matt';
      this.say(connection, { t: 'ready', id: connection.id });
      return;
    }
    const { room, org } = frame;
    if (!room) return;
    const key = this.key(connection, room, org);
    const members = this.rooms.get(key) ?? new Set<Connection>();
    const others = () => [...members].filter((c) => c !== connection);
    const where = org ? { room, org } : { room };
    switch (frame.t) {
      case 'join': {
        const first = members.size === 0;
        members.add(connection);
        this.rooms.set(key, members);
        this.say(connection, { t: 'joined', ...where, first, peers: members.size - 1 });
        for (const other of others()) this.say(other, { t: 'peers', ...where, peers: members.size - 1 });
        return;
      }
      case 'leave':
        if (!members.delete(connection)) return;
        for (const other of others()) this.say(other, { t: 'peers', ...where, peers: members.size - 1, left: connection.id });
        return;
      case 'msg':
        if (!members.has(connection) || !frame.data) return;
        this.passed.push({ from: connection.id, url: connection.url, ...where, data: frame.data });
        for (const other of others()) if (frame.to === undefined || other.id === frame.to) this.say(other, { t: 'msg', ...where, from: connection.id, data: frame.data });
        return;
    }
  }

  /** A socket gone, by its own close or the relay's: out of every room, the others told. */
  drop(connection: Connection, code: number): void {
    if (connection.socket.closed) return;
    connection.socket.closed = true;
    for (const [key, members] of this.rooms) {
      if (!members.delete(connection)) continue;
      const [org, room] = key.includes('/') ? key.split('/') : [undefined, key.split(':')[1]!];
      for (const other of members) this.say(other, { t: 'peers', room, ...(org ? { org } : {}), peers: members.size - 1, left: connection.id });
    }
    later(() => connection.socket.onclose?.({ code } as CloseEvent));
  }
}

/** A device of the app's on the relay: the transport the app uses, and its rooms handed to whoever holds them. */
class Device {
  readonly transport: WebSocketTransport;
  private readonly listeners = new Map<string, RoomListener>();

  constructor(relay: Relay) {
    this.transport = new WebSocketTransport({
      url: 'ws://device',
      token: () => 'device-token',
      socket: relay.Socket,
      events: {
        ready: () => undefined,
        joined: (room, first, peers, org) => this.listeners.get(roomKey(room, org))?.joined(first, peers),
        peers: (room, peers, org, left) => this.listeners.get(roomKey(room, org))?.peersChanged(peers, left),
        message: (room, from, data, org) => void this.listeners.get(roomKey(room, org))?.message(from, data),
        down: () => undefined,
      },
    });
  }

  readonly hold = (room: string, listener: RoomListener, org?: string) => {
    this.listeners.set(roomKey(room, org), listener);
    this.transport.join(room, org);
    return this.transport;
  };

  readonly release = (room: string, org?: string) => {
    this.listeners.delete(roomKey(room, org));
    this.transport.leave(room, org);
  };

  /** A note of the account's own open here, as the note screen opens one (core/live/session.ts). */
  open(noteId: string, words: string, key: CryptoKey): LiveSession {
    const session = new LiveSession(noteId, words, { transport: this.transport, key, hasUnsynced: () => false, keepCopy: async () => undefined }, { ready: () => undefined, peers: () => undefined });
    this.listeners.set(roomKey(noteId), session);
    return session;
  }

  /**
   * The account's own presence room as a device holds it (docs/CLAUDE_LIVE.md, "Presence rooms"): the others' states,
   * opened under the account key with `live:presence`.
   */
  watchAccount(key: CryptoKey): Awareness {
    const awareness = new Awareness(new Y.Doc());
    this.hold('presence', {
      joined: () => undefined,
      peersChanged: () => undefined,
      message: async (from, data) => {
        const envelope = await openEnvelope(key, 'presence', data).catch(() => null);
        if (envelope?.kind === Kind.Presence) applyAwarenessUpdate(awareness, envelope.payload, from);
      },
    });
    return awareness;
  }

  close(): void {
    this.transport.close();
  }
}

/** Until `check` holds: what the relay and the devices do is waited on, never slept for, so a loaded machine is only slower. */
const until = (check: () => void) => vi.waitFor(check, { timeout: 10_000, interval: 10 });

const MEMBER: Me ={ name: 'ada', hue: 'rose', color: 'red', colorLight: 'pink' };
const FAST: Partial<LivePace> = { every: 1 };

/** The AI's state among an awareness's, as the app picks it out: `ai: true`. */
function claudeIn(awareness: Awareness): { user: Record<string, unknown>; at?: unknown; cursor?: unknown } | null {
  for (const [client, state] of awareness.getStates()) {
    if (client === awareness.clientID) continue;
    if ((state.user as { ai?: boolean } | undefined)?.ai) return state as { user: Record<string, unknown> };
  }
  return null;
}

/** What the connector said in a room, opened: the kinds of its messages, in order. */
async function kindsFrom(relay: Relay, room: string, open: (data: string) => Promise<{ kind: number; payload: Uint8Array }>) {
  const said = relay.passed.filter((p) => p.room === room && p.url.includes('/v1/live'));
  return Promise.all(said.map(async (p) => open(p.data)));
}

let relay: Relay;
const devices: Device[] = [];
const device = () => {
  const made = new Device(relay);
  devices.push(made);
  return made;
};

beforeEach(() => {
  relay = new Relay();
  forgetTeamDocs();
});

afterEach(() => {
  vi.useRealTimers();
  devices.splice(0).forEach((d) => d.close());
});

describe('Claude online', () => {
  it('is in its organizations’ presence rooms and the account’s own, as an AI, saying the note it is on in that note’s room alone', async () => {
    const { service, call, account } = await connected({ hooks: { live: { socket: relay.Socket, pace: FAST } } });
    const org = await anOrganization(service, 'Ghost');
    const phone = teamDevice(service, org);
    phone.put('t1', '# Roadmap\n\n- ship it');
    await phone.sync();
    await service.deviceWrites(aNote('p1', '# Groceries\n\n- eggs'));
    // A member's device in the organization's room, and one of the account's in its own, before Claude comes.
    const member = device();
    const orgRoom = new TeamRoom(org.id, 'presence', MEMBER, { key: org.key, hold: member.hold, release: member.release });
    const own = device().watchAccount(service.accountKey);
    await until(() => expect(relay.members(`${org.id}/presence`)).toHaveLength(1));
    await until(() => expect(relay.members('matt:presence')).toHaveLength(1));

    await call('read_note', { id: 't1' });
    const where = (note: string, title: string, doing: string) => ({ note, title, kind: 'note', doing, cursor: null, pointer: null });
    await until(() => expect(claudeIn(orgRoom.awareness)?.at).toEqual(where('t1', 'Roadmap', 'reading')));
    expect(claudeIn(orgRoom.awareness)!.user).toMatchObject({ name: 'Claude', hue: 'violet', ai: true, via: 'matt' });
    await until(() => expect(claudeIn(own)).not.toBeNull());
    expect(claudeIn(own)!.user).toMatchObject({ name: 'Claude', ai: true, via: 'matt' });
    expect(claudeIn(own)!.at).toBeNull();

    // A note of the account's own: said in the account's room, and nowhere in the organization's.
    await call('append_to_note', { id: 'p1', text: 'milk', as: 'item' });
    await until(() => expect(claudeIn(own)?.at).toEqual(where('p1', 'Groceries', 'editing')));
    await until(() => expect(claudeIn(orgRoom.awareness)?.at).toBeNull());

    // Listing is on no note in particular.
    await call('list_notes');
    await until(() => expect(claudeIn(own)?.at).toBeNull());
    expect(account.live()!.online).toBe(true);
    // One socket for the account, however many calls.
    expect(relay.connector()).toHaveLength(1);
    orgRoom.close();
    account.letGo();
  });

  it('goes five minutes after its last call, each call renewing the five', async () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'setInterval', 'clearInterval', 'Date'] });
    const key = await settle(await newAccountKey());
    const client = new LiveClient({ url: 'wss://fake.test/api/v1/live', token: () => 'token', resume: async () => undefined, handle: () => 'matt', accountKey: async () => key, orgKeys: () => [], socket: relay.Socket });
    await client.touch(null);
    await until(() => expect(relay.members('matt:presence')).toHaveLength(1));
    await vi.advanceTimersByTimeAsync(4 * 60_000);
    await client.touch({ note: 'p1', title: 'Groceries', doing: 'reading' });
    await vi.advanceTimersByTimeAsync(4 * 60_000);
    expect(client.online).toBe(true);
    expect(relay.connector()).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(60_000 + 1);
    expect(client.online).toBe(false);
    expect(relay.connector()).toHaveLength(0);
    expect(relay.members('matt:presence')).toEqual([]);
    // And the next call is online again.
    await client.touch(null);
    await until(() => expect(relay.members('matt:presence')).toHaveLength(1));
    client.close();
  });

  it('renews its session when the relay refuses the token, and comes back in once', async () => {
    const key = await settle(await newAccountKey());
    let token = 'expired';
    relay.refused.add('expired');
    const resume = vi.fn(async () => {
      token = 'fresh';
    });
    const client = new LiveClient({ url: 'wss://fake.test/api/v1/live', token: () => token, resume, handle: () => 'matt', accountKey: async () => key, orgKeys: () => [], socket: relay.Socket });
    await client.touch(null);
    await until(() => expect(relay.members('matt:presence')).toHaveLength(1));
    expect(resume).toHaveBeenCalledTimes(1);
    expect(relay.connector()).toHaveLength(1);
    client.close();
    expect(relay.connector()).toHaveLength(0);
  });
});

describe('over a real socket', () => {
  it('signs in with its first frame and joins the account’s presence room through the ws package, as on the box’s Node 18', async () => {
    const server = new WebSocketServer({ port: 0, host: '127.0.0.1' });
    await new Promise<void>((listening) => server.on('listening', listening));
    const frames: { t: string; token?: string; room?: string }[] = [];
    let closed = false;
    server.on('connection', (socket) => {
      socket.on('message', (raw) => {
        const frame = JSON.parse(raw.toString()) as { t: string; room?: string };
        frames.push(frame);
        if (frame.t === 'auth') socket.send(JSON.stringify({ t: 'ready', id: 1 }));
        if (frame.t === 'join') socket.send(JSON.stringify({ t: 'joined', room: frame.room, first: true, peers: 0 }));
      });
      socket.on('close', () => {
        closed = true;
      });
    });
    const key = await settle(await newAccountKey());
    // No `socket`: the ws package's own, as the connector runs.
    const client = new LiveClient({ url: `ws://127.0.0.1:${server.address().port}/api/v1/live`, token: () => 'token', resume: async () => undefined, handle: () => 'matt', accountKey: async () => key, orgKeys: () => [] });
    await client.touch(null);
    await until(() => expect(frames.map((f) => f.t)).toEqual(['auth', 'join']));
    expect(frames[0]).toEqual({ t: 'auth', token: 'token' });
    expect(frames[1]).toEqual({ t: 'join', room: 'presence' });
    client.close();
    await until(() => expect(closed).toBe(true));
    await new Promise<void>((done) => server.close(() => done()));
  });
});

describe('typing into an organization’s note', () => {
  async function aTeamNote() {
    const made = await connected({ hooks: { live: { socket: relay.Socket, pace: FAST } } });
    const org = await anOrganization(made.service, 'Ghost');
    const phone = teamDevice(made.service, org);
    phone.put('t1', '# Roadmap\n\n- ship the connector\n- old line');
    await phone.sync();
    return { ...made, org, phone };
  }

  it('streams the change to a member who has the note open, a few words at a time with its caret, and posts it to the log', async () => {
    const { service, call, org, phone } = await aTeamNote();
    // The member's device with the note open: its document of the note's lineage, from the row.
    const row = service.teamNotes(org.id).get('t1')!;
    const payload = await open<{ state: string; seq: number }>(org.key, row.blob!, `org:${org.id}:note:t1`);
    const theirs = looseTeamDoc('t1', { state: fromBase64Url(payload.state), seq: payload.seq, snapshotSeq: payload.seq, pending: [] });
    const member = device();
    const room = new TeamRoom(org.id, 't1', MEMBER, { key: org.key, doc: theirs, hold: member.hold, release: member.release });
    await until(() => expect(relay.members(`${org.id}/t1`)).toHaveLength(1));
    const carets: { anchor: number; head: number }[] = [];
    room.awareness.on('change', () => {
      const cursor = claudeIn(room.awareness)?.cursor as { anchor: unknown; head: unknown } | null | undefined;
      const at = cursor ? Y.createAbsolutePositionFromRelativePosition(Y.createRelativePositionFromJSON(cursor.anchor), theirs.doc) : null;
      if (at) carets.push({ anchor: at.index, head: at.index });
    });

    const added = 'The connector types what it is handed into the open note at a reading pace, a few words at a time, so a person watching sees it come.';
    const answer = JSON.parse((await call('update_note', { id: 't1', body: `# Roadmap\n\n- ship the connector\n\n${added}` })).text) as { updated: { body: string } };

    // The member's document ends where the note does: nothing doubled, the old line gone.
    expect(theirs.words()).toBe(answer.updated.body);
    expect(theirs.words()).not.toContain('old line');
    const kinds = (await kindsFrom(relay, 't1', (data) => openTeamEnvelope(org.key, org.id, 't1', data))).map((e) => e.kind);
    expect(kinds.filter((k) => k === Kind.Update).length).toBeGreaterThanOrEqual(chunksOf(added, 150).length);
    // The caret led the words: seen, each further on than the last, never past what had arrived.
    expect(carets.length).toBeGreaterThan(3);
    for (let i = 1; i < carets.length; i += 1) expect(carets[i]!.anchor).toBeGreaterThanOrEqual(carets[i - 1]!.anchor);
    // Cleared at the end, and Claude out of the note's room.
    await until(() => expect(relay.members(`${org.id}/t1`)).toEqual(['ws://device']));
    // The log of record holds the same words: the phone, which was not in the room, reads them on its pass.
    await phone.sync();
    expect(phone.notes.get('t1')!.body).toBe(answer.updated.body);
    room.close();
  });

  it('writes at once, as ever, with nobody in the note', async () => {
    const { service, call, org, phone } = await aTeamNote();
    void service;
    const answer = JSON.parse((await call('update_note', { id: 't1', body: '# Roadmap\n\n- ship the connector\n- a new line' })).text) as { updated: { body: string } };
    expect(relay.passed.filter((p) => p.room === 't1')).toEqual([]);
    expect(relay.members(`${org.id}/t1`)).toEqual([]);
    await phone.sync();
    expect(phone.notes.get('t1')!.body).toBe(answer.updated.body);
  });
});

describe('typing into a personal note', () => {
  it('leaves a room it was first into without making a document, and writes as ever', async () => {
    const { service, call } = await connected({ hooks: { live: { socket: relay.Socket, pace: FAST } } });
    await service.deviceWrites(aNote('p1', '# Groceries\n\n- eggs'));
    const answer = JSON.parse((await call('update_note', { id: 'p1', body: '# Groceries\n\n- eggs\n- milk' })).text) as { updated: { body: string } };
    // It joined, was first, and said nothing in the room: no state, no question, nothing a device would take for a seed.
    expect(relay.passed.filter((p) => p.room === 'p1')).toEqual([]);
    expect(relay.members('matt:p1')).toEqual([]);
    expect((await service.stored('p1'))?.note.body).toBe(answer.updated.body);
  });

  it('adopts the document of a device that has the note open, types the change into it, and puts the same words to the account', async () => {
    const { service, call } = await connected({ hooks: { live: { socket: relay.Socket, pace: FAST } } });
    const body = '# Groceries\n\n- eggs';
    await service.deviceWrites(aNote('p1', body));
    const phone = device().open('p1', body, service.accountKey);
    await until(() => expect(phone.state).toBe('ready'));

    const answer = JSON.parse((await call('update_note', { id: 'p1', body: '# Groceries\n\n- eggs\n- milk, and the good bread from the bakery on the corner' })).text) as { updated: { body: string } };

    expect(phone.text.toString()).toBe(answer.updated.body);
    expect((await service.stored('p1'))?.note.body).toBe(answer.updated.body);
    const said = await kindsFrom(relay, 'p1', (data) => openEnvelope(service.accountKey, 'p1', data));
    // Asked for the document, never offered one of its own, then the words in several changes and its caret among them.
    expect(said[0]!.kind).toBe(Kind.Query);
    expect(said.some((e) => e.kind === Kind.State)).toBe(false);
    expect(said.filter((e) => e.kind === Kind.Update).length).toBeGreaterThan(2);
    const scratch = new Awareness(new Y.Doc());
    const carets = said.filter((e) => e.kind === Kind.Presence).map((e) => {
      applyAwarenessUpdate(scratch, e.payload, 'relay');
      return claudeIn(scratch)?.cursor ?? null;
    });
    expect(carets.some((c) => c !== null)).toBe(true);
    expect(carets[carets.length - 1]).toBeNull();
    expect(claudeIn(scratch)!.user).toMatchObject({ ai: true, via: 'matt' });
    await until(() => expect(relay.members('matt:p1')).toEqual(['ws://device']));
    phone.close();
  });
});

describe('the chunks', () => {
  it('are a few words each, whole characters, and fewer than the cap however long the words', () => {
    expect(chunksOf('one two three four five six seven', 150)).toEqual(['one two three ', 'four five six ', 'seven']);
    const long = Array.from({ length: 1000 }, (_, i) => `w${i}`).join(' ');
    const chunks = chunksOf(long, 150);
    expect(chunks.length).toBeLessThanOrEqual(150);
    expect(chunks.join('')).toBe(long);
    // A run with no space is cut, and never between the halves of a character.
    const unspaced = '😀'.repeat(1000);
    const cut = chunksOf(unspaced, 150);
    expect(cut.length).toBeGreaterThan(1);
    expect(cut.join('')).toBe(unspaced);
    for (const chunk of cut) expect(chunk.length % 2).toBe(0);
  });

  it('are typed where the note changed, each stretch alone: a line at the top and a paragraph at the end are two', () => {
    const from = '# Plan\n\nThe first part.\n\n- old line\n';
    const to = '---\nauthors: matt, Claude\n---\n# Plan\n\nThe first part.\n\nA new paragraph.\n';
    const hunks = hunksOf(from, to);
    expect(hunks).toEqual([
      { head: 0, gone: 0, came: '---\nauthors: matt, Claude\n---\n' },
      { head: from.indexOf('- old'), gone: '- old line'.length, came: 'A new paragraph.' },
    ]);
    // Applied from the last, they make `to`.
    let made = from;
    for (const { head, gone, came } of [...hunks].reverse()) made = made.slice(0, head) + came + made.slice(head + gone);
    expect(made).toBe(to);
    expect(hunksOf(to, to)).toEqual([]);
  });
});
