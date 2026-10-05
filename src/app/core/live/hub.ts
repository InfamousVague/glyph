import { accountKey, accountState } from '../account/account.ts';
import { API_BASE } from '../account/api.ts';
import { liveEnabled } from './enabled.ts';
import { LiveSession, type SessionDeps, type SessionListener } from './session.ts';
import { roomKey, WebSocketTransport, liveUrl, type LiveTransport } from './transport.ts';

/**
 * Live sync's one connection on this device, shared by every room that is live on it (docs/LIVE.md): made when the
 * first room opens, closed when the last one does, and the relay's messages handed to whoever has the room - a note
 * of the account's own (`LiveSession`), or a team's note or an organization's presence (core/live/team.ts;
 * docs/SHARED.md, S6), which have rooms of the organization's.
 */

/** What the pass sync knows that a joining note needs: whether it has unsent changes, and how to keep a copy. */
export type SyncHooks = Pick<SessionDeps, 'hasUnsynced' | 'keepCopy'>;

/** Whoever holds a room: told when it is joined, when the others come and go, and each sealed message. */
export interface RoomListener {
  joined(first: boolean, peers: number): void;
  /** How many others are in the room now; `left`, the connection that just went, when one did. */
  peersChanged(peers: number, left?: number): void;
  message(from: number, data: string): void | Promise<void>;
}

let transport: LiveTransport | null = null;
const rooms = new Map<string, RoomListener>();

function connect(): LiveTransport {
  if (transport) return transport;
  transport = new WebSocketTransport({
    url: liveUrl(API_BASE),
    token: () => accountState().session?.token ?? null,
    events: {
      ready: () => {
        // The connection id means something to the relay, which stamps it on messages; nothing here needs it.
      },
      joined: (room, first, peers, org) => rooms.get(roomKey(room, org))?.joined(first, peers),
      peers: (room, peers, org, left) => rooms.get(roomKey(room, org))?.peersChanged(peers, left),
      message: (room, from, data, org) => void rooms.get(roomKey(room, org))?.message(from, data),
      down: () => {
        // Nothing to do: the transport comes back by itself and rejoins, and each room catches up on `joined`.
      },
    },
  });
  return transport;
}

/**
 * A room held by `listener`, on the one connection: the account's own, or an organization's with `org`. Answers the
 * transport to send through. The connection goes with the last room, so a device with nothing open holds no socket.
 */
export function holdRoom(room: string, listener: RoomListener, org?: string): LiveTransport {
  const key = roomKey(room, org);
  rooms.set(key, listener);
  const over = connect();
  over.join(room, org);
  return over;
}

export function releaseRoom(room: string, org?: string): void {
  const key = roomKey(room, org);
  if (!rooms.delete(key)) return;
  transport?.leave(room, org);
  if (rooms.size === 0) {
    transport?.close();
    transport = null;
  }
}

/** The rooms held right now, for tests. */
export function heldRooms(): string[] {
  return [...rooms.keys()];
}

/**
 * Makes a note live on this device, or answers null when it will not be: the switch is off, the device is signed out,
 * or it does not hold the account key (it could not seal a word). `words` is the note as the editor has it now.
 */
export async function openLive(noteId: string, words: string, listener: SessionListener, hooks: SyncHooks): Promise<LiveSession | null> {
  if (!liveEnabled() || !accountState().session) return null;
  const key = await accountKey();
  if (!key) return null;
  closeLive(noteId);
  // The session joins the room itself as it is made, through the transport it is handed.
  const session = new LiveSession(noteId, words, { transport: roomTransport(noteId), key, ...hooks }, listener);
  rooms.set(roomKey(noteId), session);
  return session;
}

/**
 * The connection, for a session that joins its own room: held open until the room is released, and the room's
 * listener set by the caller.
 */
function roomTransport(noteId: string): LiveTransport {
  const over = connect();
  // A LiveSession joins in its constructor; the hub must know the room by then, so the entry is made first and
  // replaced by the session itself in `openLive`.
  rooms.set(roomKey(noteId), { joined: () => undefined, peersChanged: () => undefined, message: () => undefined });
  return over;
}

/** Takes a note out of live sync. The connection goes with the last room, so a device with nothing open holds no socket. */
export function closeLive(noteId: string): void {
  const held = rooms.get(roomKey(noteId));
  if (held instanceof LiveSession) held.close();
  rooms.delete(roomKey(noteId));
  if (rooms.size === 0) {
    transport?.close();
    transport = null;
  }
}
