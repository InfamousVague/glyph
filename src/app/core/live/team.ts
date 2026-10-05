import * as Y from 'yjs';
import { Awareness, applyAwarenessUpdate, encodeAwarenessUpdate, removeAwarenessStates } from 'y-protocols/awareness';
import { accountState } from '../account/account.ts';
import { orgKeyOf } from '../orgs/orgKeys.ts';
import type { TeamDoc } from '../team/doc.ts';
import { holdRoom, releaseRoom, type RoomListener } from './hub.ts';
import { meIn, PRESENCE_ROOM } from './presence.ts';
import { REMOTE } from './session.ts';
import type { LiveTransport } from './transport.ts';
import { Kind, openTeamEnvelope, sealTeamEnvelope, type Envelope } from './wire.ts';

/**
 * A room of an organization's on this device (docs/SHARED.md, S6; docs/LIVE.md, "The team's rooms"): a team note's,
 * carrying its document's changes between the members who have it open, or the organization's own, carrying only
 * who is in the app and where. Both carry the awareness protocol (y-protocols): each device's state - who it is, and
 * its caret or its pointer - sent as it changes, and dropped the moment its connection leaves the room.
 *
 * Unlike an account's note (session.ts), a team note's document is never made in the room: it is the document of
 * record (core/team/doc.ts), one lineage on every member's devices since the organization channel adopted it, so the
 * devices in a room trade only what each lacks - a state vector asked, the difference answered - and the merge is
 * exact. What arrives here is applied as the channel applies a log, and what is typed here goes out as it is made;
 * the channel still posts it to the log, so a member who was not in the room reads it on their next pass.
 */

/** What a device says of itself in a room's awareness; y-codemirror's carets read `name`, `color` and `colorLight`. */
export interface Me {
  name: string;
  /** One of the app's hues, or null for ink: what the member rows and the profile card read. */
  hue: string | null;
  /** The hue as CSS, for the caret and the selection's wash (presence.ts `caretColours`). */
  color: string;
  colorLight: string;
}

/** What a room reads of a team note's document (core/team/doc.ts): the Yjs document, its text, and how to apply what arrives. */
export type LiveDoc = Pick<TeamDoc, 'doc' | 'text' | 'applyRemote'>;

export interface RoomDeps {
  key: CryptoKey;
  /** The document carried over this room; none for the organization's own room. */
  doc?: LiveDoc;
  /** The rooms, for tests: the hub's by default. */
  hold?: (room: string, listener: RoomListener, org: string) => LiveTransport;
  release?: (room: string, org: string) => void;
}

/** How long a device that asked waits for an answer before it goes on without one. */
const CATCH_UP_MS = 2500;

interface AwarenessChange {
  added: number[];
  updated: number[];
  removed: number[];
}

export class TeamRoom implements RoomListener {
  readonly awareness: Awareness;
  /** How many other devices are in the room. */
  others = 0;
  private closed = false;
  /** Outgoing messages, one after another: sealing is asynchronous, and the order they were made in is kept. */
  private sending: Promise<void> = Promise.resolve();
  /** Incoming ones the same, so an answer to a query is never read before the state it follows. */
  private receiving: Promise<void> = Promise.resolve();
  private readonly transport: LiveTransport;
  /** Which awareness clients each connection in the room spoke for: dropped with the connection when it leaves. */
  private readonly spokeFor = new Map<number, Set<number>>();
  /** Settled once the room has nothing to catch this device up on: alone in it, a state arrived, or long enough waited. */
  private readonly settled: Promise<void>;
  private settle: () => void = () => undefined;
  private settleTimer: ReturnType<typeof setTimeout> | null = null;

  private readonly onDocUpdate = (update: Uint8Array, origin: unknown): void => {
    if (origin !== REMOTE) this.post({ kind: Kind.Update, payload: update });
  };

  private readonly onAwareness = ({ added, updated, removed }: AwarenessChange, origin: unknown): void => {
    if (origin === 'local') {
      this.post({ kind: Kind.Presence, payload: encodeAwarenessUpdate(this.awareness, [...added, ...updated, ...removed]) });
      return;
    }
    // Applied from a connection in the room (`take`): remembered as its, to drop the moment it leaves.
    if (typeof origin === 'number') for (const id of [...added, ...updated]) this.spoken(origin).add(id);
  };

  constructor(
    readonly orgId: string,
    readonly room: string,
    me: Me,
    private readonly deps: RoomDeps,
  ) {
    this.settled = new Promise<void>((settle) => {
      this.settle = settle;
    });
    this.awareness = new Awareness(deps.doc?.doc ?? new Y.Doc());
    this.awareness.setLocalStateField('user', me);
    this.transport = (deps.hold ?? holdRoom)(room, this, orgId);
    this.awareness.on('update', this.onAwareness);
    deps.doc?.doc.on('update', this.onDocUpdate);
  }

  /** Who this device is, said again: a colour picked while the room is open. */
  setMe(me: Me): void {
    this.awareness.setLocalStateField('user', me);
  }

  /** Settles once every message posted so far is sealed and handed to the transport: what a test of a room waits on. */
  sent(): Promise<void> {
    return this.sending;
  }

  /**
   * Settles once the others have had their say: alone in the room, or the first answer to this device's query
   * applied, or CATCH_UP_MS gone by without one - and at once when the room is closed. What a canvas waits on before
   * seeding its structure from the words, so it does not seed over a structure about to arrive (core/team/canvas.ts).
   */
  caughtUp(): Promise<void> {
    return this.settled;
  }

  /** In the room, first or not, and again after a drop: say who this device is, and ask what the others have. */
  joined(_first: boolean, peers: number): void {
    this.others = peers;
    if (peers === 0) {
      this.forget();
      this.settle();
      return;
    }
    this.say();
    this.post({ kind: Kind.Query, payload: this.vector() });
    if (!this.settleTimer) this.settleTimer = setTimeout(() => this.settle(), CATCH_UP_MS);
  }

  peersChanged(peers: number, left?: number): void {
    this.others = peers;
    if (left !== undefined) this.forget(left);
    if (peers === 0) this.forget();
  }

  message(from: number, data: string): Promise<void> {
    this.receiving = this.receiving.then(() => this.take(from, data)).catch(() => undefined);
    return this.receiving;
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    if (this.settleTimer) clearTimeout(this.settleTimer);
    this.settle();
    this.awareness.off('update', this.onAwareness);
    this.deps.doc?.doc.off('update', this.onDocUpdate);
    this.awareness.destroy();
    (this.deps.release ?? releaseRoom)(this.room, this.orgId);
  }

  private async take(from: number, data: string): Promise<void> {
    if (this.closed) return;
    let envelope: Envelope;
    try {
      envelope = await openTeamEnvelope(this.deps.key, this.orgId, this.room, data);
    } catch {
      // A message this device cannot read is one it should not act on: the wrong key, or sealed for another room.
      return;
    }
    if (this.closed) return;
    const doc = this.deps.doc;
    switch (envelope.kind) {
      case Kind.Query:
        this.say(from);
        if (!doc) return;
        this.post({ kind: Kind.State, payload: Y.encodeStateAsUpdate(doc.doc, envelope.payload) }, from);
        // Their vector says they hold something this device lacks: ask them, now, rather than wait for a pass.
        if (lacks(this.vector(), envelope.payload)) this.post({ kind: Kind.Query, payload: this.vector() }, from);
        return;
      case Kind.State:
        doc?.applyRemote([envelope.payload]);
        this.settle();
        return;
      case Kind.Update:
        doc?.applyRemote([envelope.payload]);
        return;
      case Kind.Presence:
        applyAwarenessUpdate(this.awareness, envelope.payload, from);
        return;
    }
  }

  /** This device's own state, to everyone, or to the one connection that asked. */
  private say(to?: number): void {
    this.post({ kind: Kind.Presence, payload: encodeAwarenessUpdate(this.awareness, [this.awareness.clientID]) }, to);
  }

  private vector(): Uint8Array {
    return this.deps.doc ? Y.encodeStateVector(this.deps.doc.doc) : new Uint8Array();
  }

  private spoken(connection: number): Set<number> {
    let set = this.spokeFor.get(connection);
    if (!set) {
      set = new Set();
      this.spokeFor.set(connection, set);
    }
    return set;
  }

  /** The states a connection spoke for, dropped - or, with no connection named, every other device's. */
  private forget(left?: number): void {
    const gone = left === undefined ? [...this.awareness.getStates().keys()].filter((id) => id !== this.awareness.clientID) : [...(this.spokeFor.get(left) ?? [])];
    if (left === undefined) this.spokeFor.clear();
    else this.spokeFor.delete(left);
    if (gone.length) removeAwarenessStates(this.awareness, gone, 'left');
  }

  private post(envelope: Envelope, to?: number): void {
    if (this.closed) return;
    this.sending = this.sending
      .then(async () => {
        const data = await sealTeamEnvelope(this.deps.key, this.orgId, this.room, envelope);
        if (!this.closed) this.transport.send(this.room, data, to, this.orgId);
      })
      .catch(() => undefined);
  }
}

/** Whether `theirs`, a state vector, holds anything `mine` lacks. */
export function lacks(mine: Uint8Array, theirs: Uint8Array): boolean {
  const have = Y.decodeStateVector(mine);
  for (const [client, clock] of Y.decodeStateVector(theirs)) if ((have.get(client) ?? 0) < clock) return true;
  return false;
}

/**
 * A team note's room, for its editor: the document's changes and the carets of the members who have it open. Null
 * when this device cannot seal a word in it - signed out, or without the organization key yet.
 */
export function openTeamRoom(orgId: string, noteId: string, doc: LiveDoc): TeamRoom | null {
  const key = orgKeyOf(orgId);
  if (!key || !accountState().session) return null;
  return new TeamRoom(orgId, noteId, meIn(orgId), { key, doc });
}

/** The organization's own room: who is in the app and where (presence.ts holds one per organization). */
export function openPresenceRoom(orgId: string): TeamRoom | null {
  const key = orgKeyOf(orgId);
  if (!key || !accountState().session) return null;
  return new TeamRoom(orgId, PRESENCE_ROOM, meIn(orgId), { key });
}

/**
 * A caret from a member's presence (presence.ts `Caret`) as indexes in this device's copy of the document, or null
 * when it cannot be placed: the words it sat in are gone, or it was never in this document.
 */
export function caretIndexes(doc: Pick<TeamDoc, 'doc' | 'text'>, caret: { anchor: unknown; head: unknown }): { anchor: number; head: number } | null {
  const index = (at: unknown): number | null => {
    try {
      const absolute = Y.createAbsolutePositionFromRelativePosition(Y.createRelativePositionFromJSON(at), doc.doc);
      return absolute && absolute.type === doc.text ? absolute.index : null;
    } catch {
      return null;
    }
  };
  const anchor = index(caret.anchor);
  if (anchor === null) return null;
  return { anchor, head: index(caret.head) ?? anchor };
}
