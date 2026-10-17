import WebSocket from 'ws';
import { Awareness, encodeAwarenessUpdate } from 'y-protocols/awareness';
import * as Y from 'yjs';
import type { RoomListener } from '../tauri/src/app/core/live/hub.ts';
import { REMOTE } from '../tauri/src/app/core/live/session.ts';
import { TeamRoom, type Me } from '../tauri/src/app/core/live/teamRoom.ts';
import { roomKey, WebSocketTransport, type LiveTransport, type WebSocketTransportOptions } from '../tauri/src/app/core/live/transport.ts';
import { Kind, openEnvelope, packState, sealEnvelope, unpackState, type Envelope } from '../tauri/src/app/core/live/wire.ts';
import { hasTeamCanvas } from '../tauri/src/app/core/team/canvas.ts';
import type { TeamDoc } from '../tauri/src/app/core/team/doc.ts';
import { LOCAL, textSpan, type TextSpan } from '../tauri/src/app/core/team/textDiff.ts';

/**
 * Claude, live (docs/CLAUDE_LIVE.md): the connector on the relay (`/api/v1/live`, tauri/docs/LIVE.md) as one more
 * device of the account, so a person sees Claude online while it works, where it is, and its words arriving in a
 * note they have open. Matt, 2026-10-17: "I'd like to have notes streamed in real time and see claude typing as it is
 * typing, i want it to show online while connected as well and be able to go view what it's editing".
 *
 * One client per account: the hosted server keeps it with the account in the session store (mcp/hosted.ts), the
 * local one has one for its process. It opens its socket on the first tool call (`touch`) and closes it five minutes
 * after the last, so "online" means "made a request in the last five minutes" for claude.ai, which keeps no
 * connection between requests, and for Claude Code alike.
 *
 * While open it holds the `presence` room of every organization whose key it has (sealed as the app seals one,
 * core/live/teamRoom.ts) and the account's own `presence` room (sealed under the account key, `live:presence`), and
 * says in each who it is - `user` with `ai: true` and the member it works through as `via` - and `at`, the note it is
 * reading or editing, in that room's notes only.
 *
 * A write to a note someone has open is typed into it: the connector joins the note's room, and if a device is there
 * it applies the change as a device would, deletions at once and the new words a few at a time, each its own Yjs
 * transaction, its caret at the end of what it has typed. An organization's note is joined with the document of
 * its lineage (mcp/team.ts), so what is typed is also what is posted to the log; a personal note is joined as a
 * device that never seeds, adopting the room's document. With nobody there it writes at once, as it always has.
 * The tool's arguments arrive whole, so this is a reading pace, not the model's: at most a few seconds a write.
 */

/** What a tool call is doing, for `at`: reading or editing one note, the account's own or an organization's. */
export interface Doing {
  note: string;
  title: string;
  doing: 'reading' | 'editing';
  /** The organization the note is the team's in; absent for one of the account's own. */
  org?: string;
}

/** `at` as the app reads it (docs/CLAUDE_LIVE.md, "Presence rooms"). */
interface Whereabouts {
  note: string;
  title: string;
  kind: 'note';
  doing: 'reading' | 'editing';
  cursor: null;
  pointer: null;
}

/** Who Claude is in awareness: the room's `Me`, marked as an AI and as the member's. */
type Claude = Me & { ai: true; via: string };

type SocketMaker = NonNullable<WebSocketTransportOptions['socket']>;

export interface LivePace {
  /** Between one chunk of words and the next. */
  every: number;
  /** The whole of one write's typing, however long it is. */
  within: number;
  /** For `joined`, and for a personal note's document from the room. */
  wait: number;
  /** After the last tool call, before the socket goes. */
  idle: number;
}

const PACE: LivePace = { every: 40, within: 6000, wait: 2500, idle: 5 * 60_000 };

export interface LiveDeps {
  /** The relay, `wss://…/api/v1/live` (transport.ts `liveUrl`). */
  url: string;
  /** The session token now: read at every connect, so a renewed one is used. */
  token(): string | null;
  /** The session renewed (`GlyphAccount.resume`), after the relay refused the token. */
  resume(): Promise<void>;
  /** The account's handle, Claude's `via`. */
  handle(): string;
  accountKey(): Promise<CryptoKey>;
  /** The organizations whose key in force is in hand (mcp/team.ts `keys`). */
  orgKeys(): { id: string; key: CryptoKey }[];
  /** A WebSocket constructor: the `ws` package's, since the box's Node 18 has none of its own; a relay in memory in tests. */
  socket?: SocketMaker;
  pace?: Partial<LivePace>;
}

/** The room every device of the account, and of each organization, says where it is in (core/live/presence.ts). */
const PRESENCE = 'presence';

/** Words a chunk is made of, at least; and the longest run of letters without a space put in at once. */
const WORDS = 3;
const LONGEST = 24;

/**
 * Claude's colour, violet, as CSS for a caret drawn by y-codemirror in the web app: the angle and lightness
 * core/live/presence.ts `caretColours` gives it (it is not imported, being the browser's). The app's own drawing
 * reads `hue`.
 */
const VIOLET = { color: 'oklch(var(--app-hue-lift) var(--app-hue-chroma) 295)', colorLight: 'oklch(var(--app-hue-lift) var(--app-hue-chroma) 295 / 0.24)' };

/**
 * Lines compared one by one, at most this many pairs of them: past it, the change is one stretch from the first
 * difference to the last, as the app's reconcile writes it.
 */
const MOST_PAIRS = 4_000_000;

/**
 * The stretches that differ between `from` and `to`, in order, each as `textSpan` gives one (core/team/textDiff.ts):
 * the lines compared first, so an `authors:` line added at the top and a paragraph at the end are two small changes
 * and not one that takes the whole note out and types it again, then each changed run of lines narrowed to the
 * characters that differ. `head` is a place in `from`.
 */
export function hunksOf(from: string, to: string): TextSpan[] {
  const lines = (words: string) => words.match(/[^\n]*\n|[^\n]+$/g) ?? [];
  const a = lines(from);
  const b = lines(to);
  let top = 0;
  while (top < a.length && top < b.length && a[top] === b[top]) top += 1;
  let bottom = 0;
  while (bottom < a.length - top && bottom < b.length - top && a[a.length - 1 - bottom] === b[b.length - 1 - bottom]) bottom += 1;
  const n = a.length - top - bottom;
  const m = b.length - top - bottom;
  if (n * m > MOST_PAIRS) {
    const span = textSpan(from, to);
    return span.gone || span.came ? [span] : [];
  }
  // The longest run of lines both keep, by the usual table, read from the end so the walk below goes forwards.
  const keep: Uint32Array[] = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
  for (let i = n - 1; i >= 0; i -= 1) {
    for (let j = m - 1; j >= 0; j -= 1) keep[i]![j] = a[top + i] === b[top + j] ? keep[i + 1]![j + 1]! + 1 : Math.max(keep[i + 1]![j]!, keep[i]![j + 1]!);
  }
  const out: TextSpan[] = [];
  let at = a.slice(0, top).join('').length;
  let i = 0;
  let j = 0;
  let gone = '';
  let came = '';
  let start = at;
  const flush = () => {
    if (gone || came) {
      const span = textSpan(gone, came);
      if (span.gone || span.came) out.push({ ...span, head: start + span.head });
    }
    gone = '';
    came = '';
  };
  while (i < n || j < m) {
    if (i < n && j < m && a[top + i] === b[top + j]) {
      flush();
      at += a[top + i]!.length;
      i += 1;
      j += 1;
      start = at;
    } else if (j < m && (i === n || keep[i]![j + 1]! >= keep[i + 1]![j]!)) {
      came += b[top + j]!;
      j += 1;
    } else {
      gone += a[top + i]!;
      at += a[top + i]!.length;
      i += 1;
    }
  }
  flush();
  return out;
}

/** One stretch of a change, placed so it still lands right after other devices' words have merged in around it. */
interface Hunk {
  /** The first character to go, and the first to stay after them: the new words go in before the second. */
  start: Y.RelativePosition;
  end: Y.RelativePosition;
  gone: number;
  came: string;
}

/** The change from `from` (what `text` holds now) to `to`, as places in `text` that outlive edits around them. */
function planOf(text: Y.Text, from: string, to: string): Hunk[] {
  return hunksOf(from, to).map(({ head, gone, came }) => ({
    start: Y.createRelativePositionFromTypeIndex(text, head),
    end: Y.createRelativePositionFromTypeIndex(text, head + gone),
    gone,
    came,
  }));
}

/**
 * New words cut where they are typed: a word with the space after it, and a run of letters with no space in it (a
 * link, words in a script without spaces) cut into pieces of whole characters.
 */
function piecesOf(came: string): string[] {
  const bits: string[] = [];
  for (const word of came.match(/\s*\S+\s*|\s+/g) ?? []) {
    const letters = Array.from(word);
    for (let at = 0; at < letters.length; at += LONGEST) bits.push(letters.slice(at, at + LONGEST).join(''));
  }
  return bits;
}

/** Pieces gathered `per` to a chunk. */
function gathered(bits: readonly string[], per: number): string[] {
  const out: string[] = [];
  for (let at = 0; at < bits.length; at += per) out.push(bits.slice(at, at + per).join(''));
  return out;
}

/** How many pieces go in a chunk: a few words, and more when there are more than `most` chunks' worth. */
const perChunk = (pieces: number, most: number) => Math.max(WORDS, Math.ceil(pieces / Math.max(1, most)));

/**
 * The new words in the chunks they are typed in: a few words each, and each longer when there would be more than
 * `most`, so the whole is typed within its time however long it is.
 */
export function chunksOf(came: string, most: number): string[] {
  const bits = piecesOf(came);
  return gathered(bits, perChunk(bits.length, most));
}

const sleep = (ms: number) => new Promise<void>((done) => setTimeout(done, ms));

/** A relative position's index in its document now: where it points, or the end when it points at nothing left. */
function indexOf(doc: Y.Doc, text: Y.Text, at: Y.RelativePosition): number {
  return Y.createAbsolutePositionFromRelativePosition(at, doc)?.index ?? text.length;
}

/**
 * A caret at `index` as y-codemirror writes one: Yjs relative positions, as JSON. Held to the character before it,
 * the last one typed, so it says a new place with every chunk rather than the same one, and a device that redraws
 * carets only when a state changes still sees it move.
 */
function caretAt(text: Y.Text, index: number): { anchor: unknown; head: unknown } {
  const at = Y.relativePositionToJSON(Y.createRelativePositionFromTypeIndex(text, index, -1));
  return { anchor: at, head: at };
}

/**
 * A room of the account's own: its `presence` room, or a personal note's (docs/LIVE.md, "Seeding"). Sealed under the
 * account key with the room as the context, as core/live/session.ts seals a note's. A note's room never makes a
 * document: it adopts the room's, from a device that has the note open, and answers a device that asks with it.
 */
class OwnRoom implements RoomListener {
  readonly doc = new Y.Doc();
  readonly text = this.doc.getText('body');
  readonly awareness = new Awareness(this.doc);
  /** The room's document's seed id, once it is adopted. */
  seed: string | null = null;
  private others = 0;
  private closed = false;
  private sending: Promise<void> = Promise.resolve();
  private receiving: Promise<void> = Promise.resolve();
  private adopted: ((done: boolean) => void) | null = null;
  private readonly transport: LiveTransport;

  constructor(
    private readonly client: LiveClient,
    readonly room: string,
    me: Claude,
    private readonly key: CryptoKey,
    /** A note's room, carrying its document; else the presence room, carrying awareness alone. */
    private readonly note: boolean,
  ) {
    this.awareness.setLocalStateField('user', me);
    this.awareness.on('update', ({ added, updated, removed }: { added: number[]; updated: number[]; removed: number[] }, origin: unknown) => {
      if (origin === 'local') this.post({ kind: Kind.Presence, payload: encodeAwarenessUpdate(this.awareness, [...added, ...updated, ...removed]) });
    });
    this.doc.on('update', (update: Uint8Array, origin: unknown) => {
      if (origin !== REMOTE && this.seed) this.post({ kind: Kind.Update, payload: update });
    });
    this.transport = client.hold(room, this);
  }

  joined(_first: boolean, peers: number): void {
    this.others = peers;
    // In the presence room, the others are asked who they are, as an organization's presence room asks.
    if (!this.note && peers > 0) {
      this.say();
      this.post({ kind: Kind.Query, payload: new Uint8Array() });
    }
  }

  peersChanged(peers: number): void {
    this.others = peers;
    if (peers === 0) this.adopted?.(false);
  }

  message(from: number, data: string): Promise<void> {
    this.receiving = this.receiving.then(() => this.take(from, data)).catch(() => undefined);
    return this.receiving;
  }

  /** The room's document asked for and adopted, whole, its seed kept: false when none came in `ms`, or everyone left. */
  adopt(ms: number): Promise<boolean> {
    if (this.seed) return Promise.resolve(true);
    if (this.others === 0) return Promise.resolve(false);
    return new Promise<boolean>((done) => {
      const timer = setTimeout(() => finish(false), ms);
      const finish = (ok: boolean) => {
        clearTimeout(timer);
        this.adopted = null;
        done(ok);
      };
      this.adopted = finish;
      this.post({ kind: Kind.Query, payload: new Uint8Array() });
    });
  }

  sent(): Promise<void> {
    return this.sending;
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    this.adopted?.(false);
    this.awareness.destroy();
    this.doc.destroy();
    this.client.release(this.room);
  }

  private async take(from: number, data: string): Promise<void> {
    if (this.closed) return;
    let envelope: Envelope;
    try {
      envelope = await openEnvelope(this.key, this.room, data);
    } catch {
      // Not ours to read: sealed for another room or under another key.
      return;
    }
    if (this.closed) return;
    switch (envelope.kind) {
      case Kind.Query:
        if (!this.note) this.say(from);
        // A device that joined after this one asks for the document: the room's, adopted, is the one to give.
        else if (this.seed) this.post({ kind: Kind.State, payload: packState(this.seed, Y.encodeStateAsUpdate(this.doc)) }, from);
        return;
      case Kind.State: {
        if (!this.note) return;
        const { seed, state } = unpackState(envelope.payload);
        if (this.seed && seed !== this.seed) return;
        Y.applyUpdate(this.doc, state, REMOTE);
        if (!this.seed) {
          this.seed = seed;
          this.adopted?.(true);
        }
        return;
      }
      case Kind.Update:
        // Safe before the document has come: Yjs holds a change whose history it has not seen until it arrives.
        if (this.note) Y.applyUpdate(this.doc, envelope.payload, REMOTE);
        return;
      default:
        // The others' carets and places: nothing the connector reads.
        return;
    }
  }

  private say(to?: number): void {
    this.post({ kind: Kind.Presence, payload: encodeAwarenessUpdate(this.awareness, [this.awareness.clientID]) }, to);
  }

  private post(envelope: Envelope, to?: number): void {
    if (this.closed) return;
    this.sending = this.sending
      .then(async () => {
        const data = await sealEnvelope(this.key, this.room, envelope);
        if (!this.closed) this.transport.send(this.room, data, to);
      })
      .catch(() => undefined);
  }
}

interface Held {
  room: string;
  org?: string;
  listener: RoomListener;
  /** Settled with the first `joined`: whether this socket opened the room, and how many others are in it. */
  entered: Promise<{ first: boolean; peers: number }>;
  enter: (value: { first: boolean; peers: number }) => void;
}

export class LiveClient implements LiveTransport {
  private transport: WebSocketTransport | null = null;
  private readonly rooms = new Map<string, Held>();
  private own: OwnRoom | null = null;
  private readonly orgRooms = new Map<string, { room: TeamRoom; key: CryptoKey }>();
  private doing: Doing | null = null;
  private name = 'Claude';
  /** A 4401 has been met with a renewed session since the socket was last let in: once, then it waits for a touch. */
  private renewed = false;
  private idle: ReturnType<typeof setTimeout> | null = null;
  private settling: Promise<void> = Promise.resolve();
  private over = false;
  private readonly pace: LivePace;

  constructor(private readonly deps: LiveDeps) {
    this.pace = { ...PACE, ...deps.pace };
  }

  /** Whether the socket is open (or opening): between a tool call and five minutes after the last. */
  get online(): boolean {
    return this.transport !== null;
  }

  /**
   * A tool call: online for five minutes more, and where it is - reading or editing a note, or nothing in
   * particular - said in the presence rooms. `name` is the AI's, as the connector knows it. Settles once the rooms
   * are held and the state is said; a tool never waits on it.
   */
  touch(doing: Doing | null, name?: string): Promise<void> {
    if (this.over) return Promise.resolve();
    if (name?.trim()) this.name = name.trim().slice(0, 40);
    this.doing = doing;
    // The socket at once, so a write this same call makes finds Claude online; the rooms follow (`settle`).
    this.connect();
    if (this.idle) clearTimeout(this.idle);
    this.idle = setTimeout(() => this.stop(), this.pace.idle);
    (this.idle as { unref?: () => void }).unref?.();
    this.settling = this.settling.then(() => this.settle()).catch(() => undefined);
    return this.settling;
  }

  /**
   * `words` typed into a team note's document (`doc`, its lineage, mcp/team.ts) while a member who has it open
   * watches: true once they are in, false when nobody is in the note's room - or the connector is not online, or
   * the note is a canvas, whose structure is not words - and the caller reconciles them at once instead.
   */
  async typeTeam(orgId: string, noteId: string, doc: TeamDoc, words: string): Promise<boolean> {
    const key = this.deps.orgKeys().find((org) => org.id === orgId)?.key;
    if (!this.transport || !key || hasTeamCanvas(doc.doc) || this.rooms.has(roomKey(noteId, orgId))) return false;
    const from = doc.text.toString();
    if (from === words) return false;
    // Placed now, before the room's words merge in: the change is from the words it was made from.
    const plan = planOf(doc.text, from, words);
    const room = new TeamRoom(orgId, noteId, this.me(), { key, doc, hold: (r, listener, org) => this.hold(r, listener, org), release: (r, org) => this.release(r, org) });
    try {
      const entered = await this.entered(noteId, orgId);
      if (!entered || entered.peers === 0) return false;
      await room.caughtUp();
      await this.typeOut(doc.doc, doc.text, plan, (caret) => room.awareness.setLocalStateField('cursor', caret));
      room.awareness.setLocalStateField('cursor', null);
      await room.sent();
      return true;
    } finally {
      room.close();
    }
  }

  /**
   * A personal note's change from `from` to `to` typed into its room while a device of the account has it open, as
   * a device that never seeds (docs/LIVE.md, "Seeding"): first into the room, it leaves; otherwise it adopts the
   * room's document and types the change into it. Answers the words the room ends with - `to`, and anything the
   * device typed meanwhile - or null where it typed nothing and the caller writes `to` as it always has: nobody
   * there, no document given, or the room's words not the ones the change was made from.
   */
  async typeOwn(noteId: string, from: string, to: string): Promise<string | null> {
    if (!this.transport || from === to || this.rooms.has(roomKey(noteId))) return null;
    const room = new OwnRoom(this, noteId, this.me(), await this.deps.accountKey(), true);
    try {
      const entered = await this.entered(noteId);
      if (!entered || entered.first || entered.peers === 0) return null;
      if (!(await room.adopt(this.pace.wait))) return null;
      // The device's words are newer than the ones read (typed and not yet synced): the change is written as ever,
      // and the pass sync's conflict rule keeps both.
      if (room.text.toString() !== from) return null;
      await this.typeOut(room.doc, room.text, planOf(room.text, from, to), (caret) => room.awareness.setLocalStateField('cursor', caret));
      room.awareness.setLocalStateField('cursor', null);
      await room.sent();
      return room.text.toString();
    } finally {
      room.close();
    }
  }

  /** Every room left and the socket closed, for good: the hosted session is over. */
  close(): void {
    this.over = true;
    this.stop();
  }

  // --- the rooms' transport ---------------------------------------------------------------

  /** A room held on this socket by `listener`; the connector itself is the transport it sends through. */
  hold(room: string, listener: RoomListener, org?: string): LiveTransport {
    let enter: Held['enter'] = () => undefined;
    const entered = new Promise<{ first: boolean; peers: number }>((done) => {
      enter = done;
    });
    this.rooms.set(roomKey(room, org), { room, ...(org ? { org } : {}), listener, entered, enter });
    this.transport?.join(room, org);
    return this;
  }

  release(room: string, org?: string): void {
    if (this.rooms.delete(roomKey(room, org))) this.transport?.leave(room, org);
  }

  join(room: string, org?: string): void {
    this.transport?.join(room, org);
  }

  leave(room: string, org?: string): void {
    this.transport?.leave(room, org);
  }

  send(room: string, data: string, to?: number, org?: string): void {
    this.transport?.send(room, data, to, org);
  }

  // --- inside -----------------------------------------------------------------------------

  private me(): Claude {
    return { name: this.name, hue: 'violet', ...VIOLET, ai: true, via: this.deps.handle() };
  }

  /** The first `joined` for a room, or null when the relay has not said in time (it is down, or the socket is). */
  private entered(room: string, org?: string): Promise<{ first: boolean; peers: number } | null> {
    const held = this.rooms.get(roomKey(room, org));
    if (!held) return Promise.resolve(null);
    return Promise.race([held.entered, sleep(this.pace.wait).then(() => null)]);
  }

  /**
   * The plan's change made in `text`: what goes, at once, in one transaction; what comes, stretch by stretch from the
   * top, a chunk at a time, `every` apart, each chunk its own transaction, the caret said before each at the end of
   * what has been typed so far.
   */
  private async typeOut(doc: Y.Doc, text: Y.Text, plan: readonly Hunk[], caret: (at: { anchor: unknown; head: unknown }) => void): Promise<void> {
    if (plan.some((hunk) => hunk.gone > 0)) {
      // Every stretch found before any goes, then taken out from the last, so none moves another.
      const ranges = plan.map((hunk) => [indexOf(doc, text, hunk.start), indexOf(doc, text, hunk.end)] as const);
      doc.transact(() => {
        for (const [start, end] of [...ranges].reverse()) if (end > start) text.delete(start, end - start);
      }, LOCAL);
    }
    const pieces = plan.map((hunk) => piecesOf(hunk.came));
    const per = perChunk(pieces.reduce((n, bits) => n + bits.length, 0), Math.floor(this.pace.within / Math.max(1, this.pace.every)));
    let first = true;
    for (const [n, hunk] of plan.entries()) {
      for (const chunk of gathered(pieces[n]!, per)) {
        if (!first) await sleep(this.pace.every);
        first = false;
        caret(caretAt(text, indexOf(doc, text, hunk.end)));
        doc.transact(() => text.insert(indexOf(doc, text, hunk.end), chunk), LOCAL);
      }
    }
  }

  private connect(): void {
    if (this.transport) return;
    this.transport = this.socket();
  }

  private socket(): WebSocketTransport {
    return new WebSocketTransport({
      url: this.deps.url,
      token: () => this.deps.token(),
      socket: this.deps.socket ?? (WebSocket as unknown as SocketMaker),
      events: {
        ready: () => {
          this.renewed = false;
        },
        joined: (room, first, peers, org) => {
          const held = this.rooms.get(roomKey(room, org));
          held?.listener.joined(first, peers);
          held?.enter({ first, peers });
        },
        peers: (room, peers, org, left) => this.rooms.get(roomKey(room, org))?.listener.peersChanged(peers, left),
        message: (room, from, data, org) => void this.rooms.get(roomKey(room, org))?.listener.message(from, data),
        down: (why) => {
          // Told from inside the transport's own constructor when there is no token: a turn later, it is in hand.
          if (why === 'signIn') queueMicrotask(() => this.renew());
        },
      },
    });
  }

  /** The relay refused the token (4401): the session renewed and the socket made again, once, with every room rejoined. */
  private renew(): void {
    if (this.renewed || !this.transport) return;
    this.renewed = true;
    this.deps
      .resume()
      .then(() => {
        if (!this.transport) return;
        this.transport.close();
        this.transport = this.socket();
        for (const { room, org } of this.rooms.values()) this.transport.join(room, org);
      })
      .catch(() => undefined);
  }

  /** The presence rooms held, as many as there are keys for, and Claude's state said in each. */
  private async settle(): Promise<void> {
    if (this.over) return;
    this.connect();
    const me = this.me();
    if (!this.own) {
      const key = await this.deps.accountKey();
      if (!this.transport || this.own) return;
      this.own = new OwnRoom(this, PRESENCE, me, key, false);
    }
    const keys = this.deps.orgKeys();
    for (const [id, held] of this.orgRooms) {
      // Left the organization, or its key turned: the room goes, and with a new key comes back.
      if (keys.some((org) => org.id === id && org.key === held.key)) continue;
      held.room.close();
      this.orgRooms.delete(id);
    }
    for (const { id, key } of keys) {
      if (this.orgRooms.has(id)) continue;
      const room = new TeamRoom(id, PRESENCE, me, { key, hold: (r, listener, org) => this.hold(r, listener, org), release: (r, org) => this.release(r, org) });
      this.orgRooms.set(id, { room, key });
    }
    const where = (org: string | undefined): Whereabouts | null => {
      const doing = this.doing;
      if (!doing || doing.org !== org) return null;
      return { note: doing.note, title: doing.title, kind: 'note', doing: doing.doing, cursor: null, pointer: null };
    };
    const say = (awareness: Awareness, org: string | undefined) => {
      if (JSON.stringify(awareness.getLocalState()?.user) !== JSON.stringify(me)) awareness.setLocalStateField('user', me);
      // Said every call, changed or not: it is also what keeps the state fresh in the others' awareness.
      awareness.setLocalStateField('at', where(org));
    };
    say(this.own.awareness, undefined);
    for (const [id, { room }] of this.orgRooms) say(room.awareness, id);
  }

  /** Every room left and the socket closed: five minutes without a call. The next call opens them again. */
  private stop(): void {
    if (this.idle) clearTimeout(this.idle);
    this.idle = null;
    this.own?.close();
    this.own = null;
    for (const { room } of this.orgRooms.values()) room.close();
    this.orgRooms.clear();
    this.transport?.close();
    this.transport = null;
    this.rooms.clear();
    this.renewed = false;
  }
}
