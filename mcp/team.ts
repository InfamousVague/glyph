import { notYet } from '../tauri/src/app/core/account/notYet.ts';
import { failureText } from '../tauri/src/app/core/failure.ts';
import { randomId } from '../tauri/src/app/core/ids.ts';
import { imageNames } from '../tauri/src/app/core/imageRefs.ts';
import type { OrgRow } from '../tauri/src/app/core/orgs/types.ts';
import { importEncryptionKey, unwrapWith, wrapContext } from '../tauri/src/app/core/orgs/wrap.ts';
import type { Note } from '../tauri/src/app/core/store.ts';
import { fromBase64Url, open, openBytes, seal, sealBytes, toBase64Url, type Bytes } from '../tauri/src/app/core/sync/crypto.ts';
import { looseTeamDoc, type TeamDoc } from '../tauri/src/app/core/team/doc.ts';

/**
 * An account's organizations from outside the app (docs/SHARED.md; docs/MCP.md, "Organizations"): the team's notes
 * read and written by the MCP connector as the signed-in member, with that member's access and nothing more.
 *
 * A team's notes are sealed under the organization key, which every member holds wrapped under their account's
 * encryption key pair (S2, S3). So this does what a member's second device does: it reads the pair's private half
 * from the service, where the account's first device left it sealed under the account key (`GET account/key`,
 * core/account/encKey.ts), opens its own wrap of each organization's key with it (`GET orgs/:id/keys`,
 * core/orgs/wrap.ts), and from there reads the organization channel as core/team/sync.ts does: the feed of rows by
 * cursor, each row a snapshot of the note's CRDT document, and the log of updates since, fetched only for the notes
 * whose head moved (`GET orgs/:id/heads`).
 *
 * A write is the app's too. Words go into the note's document through the app's own reconcile (core/team/doc.ts,
 * `looseTeamDoc`), and what that changed is posted to the note's log as sealed updates, so two members who edited
 * apart still merge and a phone with the note open takes the change from the log. Particulars the row carries for
 * the whole team - the pin, the archive - are put as a row, from the revision last read, merged and put again when
 * another member's row got there first. Every write names the key's generation (S11); one refused because the key
 * turned reads this account's wrap at the new generation and goes once more.
 *
 * What it never does is a member device's own work: it makes no organization's first key, turns none, wraps for
 * nobody, and puts no row again merely because it read it under an older generation. Where it has no wrap it says
 * so (`notices`, `whereabouts`), and the notes wait on one of the member's devices.
 *
 * Nothing here is kept between runs. The pair and the organization keys are key objects in memory, not extractable,
 * read again from the service by whoever holds the account key; the notes held are the organizations' own, as the
 * account's are held beside them (mcp/glyph.ts), and go when the account is let go of or the organization is left.
 * No document is held between calls: each is made from the row's state, used and destroyed.
 */

/** How this reaches the service: as the account, by the account's own session (mcp/glyph.ts). */
export interface TeamService {
  call<T>(method: string, path: string, body?: unknown): Promise<T>;
  /** A file's bytes fetched, or sent; a refusal thrown as `call` throws one. */
  bytes(method: 'GET' | 'PUT', path: string, body?: Bytes): Promise<Bytes>;
  accountKey(): Promise<CryptoKey>;
  /**
   * `words` typed into a team note's document while a member who has the note open watches them come (mcp/live.ts):
   * true once they are in it, false when nobody is watching and the caller reconciles them at once, as ever.
   */
  type?(orgId: string, noteId: string, doc: TeamDoc, words: string): Promise<boolean>;
}

/** The organization a team note is in. */
export interface OrgName {
  id: string;
  name: string;
}

/** A team note as the tools hold one: the row's revision, the note with the document's words, and whose it is. */
export interface TeamRecord {
  rev: number;
  note: Note;
  images?: string[];
  org: OrgName;
}

/** A row's blob, opened (core/team/sync.ts `TeamPayload`). */
interface TeamPayload {
  v: 1;
  note: Note;
  state: string;
  seq: number;
  images?: string[];
  versions?: string;
}

interface TeamFeedItem {
  id: string;
  rev: number;
  deleted: boolean;
  blob: string | null;
  updatedAt: number;
}

interface UpdateItem {
  seq: number;
  blob: string;
  at: number;
}

interface Keys {
  generation: number;
  mine: string | null;
}

/** One team note held: the row as last read or put, and the document's state with the log applied as far as `seq`. */
interface Entry {
  rev: number;
  note: Note;
  state: Uint8Array;
  seq: number;
  versions?: string;
  /** Its particulars changed here, or its log is full: the row is still to be put. */
  owed?: boolean;
}

interface Held {
  row: OrgRow;
  /** The generation in force, and its key when this account has a wrap at it. */
  generation: number;
  key: CryptoKey | null;
  /** Earlier generations: held from before a turn, or read from this account's wrap at one; null for none. */
  older: Map<number, CryptoKey | null>;
  /** Why the key in force is not in hand, in words that finish "…: <why>". */
  keyWhy: string | null;
  /** The last read of it failed, and why; what is held is as it was. */
  fault: string | null;
  cursor: number;
  notes: Map<string, Entry>;
  /** Live rows that would not open. */
  unreadable: Set<string>;
  /** The AI names this organization was last told of, and when (`announce`). */
  told: Map<string, number>;
}

const noteContext = (orgId: string, id: string) => `org:${orgId}:note:${id}`;
const updateContext = (orgId: string, id: string) => `org:${orgId}:note:${id}:update`;
/** Updates in one post (server/src/org_notes.rs `UPDATES_PER_POST`). */
const POST_AT_MOST = 100;
/** The private half of the account's pair is sealed under the account key with this as its context (core/account/encKey.ts). */
const PAIR_CONTEXT = 'encryption-key';

/** A note's particulars, as the organization channel tells whether its row needs putting again (core/team/sync.ts). */
function particulars(note: Note): string {
  return JSON.stringify([note.createdAt, note.source, Boolean(note.starred), note.archivedAt ?? null, note.path ?? null, note.recordingMs ?? null]);
}

/** A picture's id among the service's files (core/sync/notes.ts `fileId`). */
export function pictureId(name: string): string | null {
  const match = /^([A-Za-z0-9_-]+)\.([A-Za-z]+)$/.exec(name);
  if (!match) return null;
  const id = `i-${match[2]!.toLowerCase()}-${match[1]!}`;
  return id.length <= 64 ? id : null;
}

const statusOf = (failure: unknown): number | null => (failure instanceof Error && typeof (failure as { status?: unknown }).status === 'number' ? (failure as unknown as { status: number }).status : null);
const bodyOf = (failure: unknown): Record<string, unknown> | null => {
  const body = failure instanceof Error ? (failure as { body?: unknown }).body : null;
  return body && typeof body === 'object' ? (body as Record<string, unknown>) : null;
};
/** The service refused a body sealed under a generation no longer in force (S11): a 409 naming the one that is. */
const turned = (failure: unknown): boolean => statusOf(failure) === 409 && typeof bodyOf(failure)?.error === 'string' && typeof bodyOf(failure)?.generation === 'number';
/** A row that won a race: a 409 carrying it. */
const winnerOf = (failure: unknown): TeamFeedItem | null => (statusOf(failure) === 409 && typeof bodyOf(failure)?.id === 'string' && typeof bodyOf(failure)?.rev === 'number' ? (bodyOf(failure) as unknown as TeamFeedItem) : null);

/** A document let go: its timer stopped and its types freed. */
async function release(doc: TeamDoc): Promise<void> {
  await doc.flush();
  doc.doc.destroy();
}

/** How long before an organization is told again that the same AI is still reading it: its last seen, kept fresh. */
const TELL_EVERY_MS = 6 * 60 * 60_000;

const WAITING = 'one of its members’ devices makes it at their next sync';

export class TeamNotes {
  private pair: CryptoKeyPair | null = null;
  private pairWhy: string | null = null;
  private readonly orgs = new Map<string, Held>();
  private refreshing: Promise<number> | null = null;

  constructor(private readonly service: TeamService) {}

  // --- keys --------------------------------------------------------------------------------

  /** The account's encryption key pair, as a second device gets it: sealed on the service, opened with the account key. */
  private async encryptionPair(): Promise<CryptoKeyPair | null> {
    if (this.pair) return this.pair;
    let registered: { sealed: string };
    try {
      registered = await this.service.call<{ pub: string; sealed: string }>('GET', 'account/key');
    } catch (failure) {
      if (statusOf(failure) !== 404) throw failure;
      this.pairWhy = notYet(failure) ? 'the sync service has no organization keys yet' : 'this account has no encryption key yet; opening Ghost.md on one of your devices makes it';
      return null;
    }
    const jwk = await open<JsonWebKey>(await this.service.accountKey(), registered.sealed, PAIR_CONTEXT).catch(() => null);
    if (!jwk) {
      this.pairWhy = 'this account’s encryption key would not open with its account key';
      return null;
    }
    this.pair = await importEncryptionKey(jwk);
    this.pairWhy = null;
    return this.pair;
  }

  /** An organization key out of this account's wrap of it, as a key that cannot be read back out. */
  private async unwrapped(pair: CryptoKeyPair, orgId: string, generation: number, wrapped: string): Promise<CryptoKey> {
    const raw = await unwrapWith(pair, wrapped, wrapContext(orgId, generation));
    try {
      return await crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
    } finally {
      raw.fill(0);
    }
  }

  /** The key in force is not in hand: what was held is one of the older ones now. */
  private without(held: Held, generation: number, why: string): void {
    if (held.key && held.generation !== generation) held.older.set(held.generation, held.key);
    if (held.generation !== generation) held.key = null;
    held.generation = generation;
    if (!held.key) held.keyWhy = why;
  }

  /**
   * The organization's key seen to, reading only: the generation the list names, opened from this account's wrap at
   * it. None made yet, or no wrap for this account, is a member device's to mend, and is said (`keyWhy`).
   */
  private async settleKey(held: Held, ask = false): Promise<void> {
    const needs = ask ? undefined : held.row.keys;
    const orgId = held.row.id;
    if (needs) {
      if (needs.generation === 0) return this.without(held, 0, `no key has been made for it yet; ${WAITING}`);
      if (held.key && held.generation === needs.generation) return;
      if (!needs.mine) return this.without(held, needs.generation, `this account has no wrap of its key at generation ${needs.generation} yet; ${WAITING}`);
    }
    const pair = await this.encryptionPair();
    if (!pair) return this.without(held, needs?.generation ?? held.generation, this.pairWhy ?? 'this account’s encryption key is not in hand');
    const keys = await this.service.call<Keys>('GET', `orgs/${encodeURIComponent(orgId)}/keys`);
    if (keys.generation === 0) return this.without(held, 0, `no key has been made for it yet; ${WAITING}`);
    if (held.key && held.generation === keys.generation) return;
    if (!keys.mine) return this.without(held, keys.generation, `this account has no wrap of its key at generation ${keys.generation} yet; ${WAITING}`);
    let key: CryptoKey;
    try {
      key = await this.unwrapped(pair, orgId, keys.generation, keys.mine);
    } catch {
      return this.without(held, keys.generation, `this account’s wrap of its key at generation ${keys.generation} would not open`);
    }
    if (held.key) held.older.set(held.generation, held.key);
    held.key = key;
    held.generation = keys.generation;
    held.keyWhy = null;
    // Rows that would not open may open under this one: the feed is read again from its start, once.
    if (held.unreadable.size) held.cursor = 0;
  }

  /** The key at an older generation (S11), from this account's wrap at it; null where it has none. */
  private async olderKey(held: Held, generation: number): Promise<CryptoKey | null> {
    if (held.older.has(generation)) return held.older.get(generation) ?? null;
    let key: CryptoKey | null = null;
    try {
      const pair = await this.encryptionPair();
      const keys = pair ? await this.service.call<Keys>('GET', `orgs/${encodeURIComponent(held.row.id)}/keys?generation=${generation}`) : null;
      if (pair && keys?.mine) key = await this.unwrapped(pair, held.row.id, generation, keys.mine);
    } catch {
      // Not readable now: asked again at the next read (`refresh` forgets the nulls).
    }
    held.older.set(generation, key);
    return key;
  }

  /** Sealed bytes opened under the key in force or, failing that, the generations before it (core/team/sync.ts `opened`). */
  private async opened<T>(held: Held, read: (key: CryptoKey) => Promise<T>): Promise<T> {
    let first: unknown = new Error('No key in hand.');
    if (held.key) {
      try {
        return await read(held.key);
      } catch (failure) {
        first = failure;
      }
    }
    for (let generation = held.generation - 1; generation >= 1; generation -= 1) {
      const key = await this.olderKey(held, generation);
      if (!key) continue;
      try {
        return await read(key);
      } catch {
        // Not that one either.
      }
    }
    throw first;
  }

  // --- reading -----------------------------------------------------------------------------

  private route(held: Held, tail: string): string {
    return `orgs/${encodeURIComponent(held.row.id)}/${tail}`;
  }

  /** A row taken: its document, merged with what the log had already brought here, and the note with its words. */
  private async take(held: Held, item: TeamFeedItem, payload: TeamPayload): Promise<void> {
    const was = held.notes.get(item.id);
    const doc = looseTeamDoc(item.id, { state: fromBase64Url(payload.state), seq: payload.seq, snapshotSeq: payload.seq, pending: [] });
    try {
      if (was) doc.applyRemote([was.state], was.seq);
      const words = doc.words();
      const entry: Entry = {
        rev: item.rev,
        note: { ...payload.note, id: item.id, body: words, updatedAt: Math.max(payload.note.updatedAt, was?.note.updatedAt ?? 0) },
        state: doc.snapshot(),
        seq: doc.seq,
      };
      if (payload.versions) entry.versions = payload.versions;
      held.notes.set(item.id, entry);
    } finally {
      await release(doc);
    }
  }

  /** Every row written since the cursor. One that will not open is counted, and tried again when it next changes. */
  private async pullRows(held: Held): Promise<number> {
    let changed = 0;
    for (;;) {
      const page = await this.service.call<{ rev: number; items: TeamFeedItem[]; more: boolean }>('GET', this.route(held, `notes?since=${held.cursor}`));
      for (const item of page.items) {
        if (item.deleted || !item.blob) {
          if (held.notes.delete(item.id)) changed += 1;
          held.unreadable.delete(item.id);
          continue;
        }
        if (held.notes.get(item.id)?.rev === item.rev) continue;
        try {
          const payload = await this.opened(held, (key) => open<TeamPayload>(key, item.blob!, noteContext(held.row.id, item.id)));
          await this.take(held, item, payload);
          held.unreadable.delete(item.id);
        } catch {
          held.notes.delete(item.id);
          held.unreadable.add(item.id);
        }
        changed += 1;
      }
      held.cursor = Math.max(held.cursor, page.rev);
      if (!page.more) return changed;
    }
  }

  /** A note's log since its seq, applied. True when its words changed. */
  private async takeUpdates(held: Held, id: string, entry: Entry): Promise<boolean> {
    let doc: TeamDoc | null = null;
    const before = entry.note.body;
    try {
      for (;;) {
        let page: { seq: number; items: UpdateItem[]; more: boolean };
        try {
          page = await this.service.call('GET', this.route(held, `notes/${encodeURIComponent(id)}/updates?since=${entry.seq}`));
        } catch (failure) {
          // The row is gone: the next read of the feed takes it.
          if (statusOf(failure) === 404) break;
          throw failure;
        }
        if (!page.items.length) {
          entry.seq = Math.max(entry.seq, page.seq);
          break;
        }
        const updates: Uint8Array[] = [];
        for (const item of page.items) {
          try {
            updates.push(await this.opened(held, (key) => openBytes(key, fromBase64Url(item.blob), updateContext(held.row.id, id))));
          } catch {
            // Sealed under a generation this account lacks: the row's next snapshot carries what it did.
          }
        }
        const last = page.items[page.items.length - 1]!;
        doc ??= looseTeamDoc(id, { state: entry.state, seq: entry.seq, snapshotSeq: entry.seq, pending: [] });
        const words = doc.applyRemote(updates, last.seq);
        entry.seq = doc.seq;
        entry.state = doc.snapshot();
        if (words !== null) entry.note = { ...entry.note, body: words, updatedAt: Math.max(entry.note.updatedAt, last.at) };
        if (!page.more) break;
      }
    } finally {
      if (doc) await release(doc);
    }
    return entry.note.body !== before;
  }

  /** The logs that moved past what is held, read: one request for the organization, then one for each note that moved. */
  private async pullLogs(held: Held): Promise<number> {
    if (!held.notes.size) return 0;
    let heads: Record<string, number> | null = null;
    try {
      ({ heads } = await this.service.call<{ heads: Record<string, number> }>('GET', this.route(held, 'heads')));
    } catch (failure) {
      // A service from before the route: every log is looked at.
      if (!notYet(failure)) throw failure;
    }
    let changed = 0;
    for (const [id, entry] of held.notes) {
      if (heads && (heads[id] ?? 0) <= entry.seq) continue;
      if (await this.takeUpdates(held, id, entry)) changed += 1;
    }
    return changed;
  }

  private async read(): Promise<number> {
    let rows: OrgRow[];
    try {
      rows = (await this.service.call<{ orgs: OrgRow[] }>('GET', 'orgs')).orgs;
    } catch (failure) {
      // A service from before organizations: there are none.
      if (!notYet(failure)) throw failure;
      this.orgs.clear();
      return 0;
    }
    const members = rows.filter((row) => row.state === 'member');
    // An organization the account has left takes its key and its notes with it.
    const ids = new Set(members.map((row) => row.id));
    for (const id of [...this.orgs.keys()]) if (!ids.has(id)) this.orgs.delete(id);
    let changed = 0;
    for (const row of members) {
      const held: Held = this.orgs.get(row.id) ?? { row, generation: 0, key: null, older: new Map(), keyWhy: null, fault: null, cursor: 0, notes: new Map(), unreadable: new Set(), told: new Map() };
      held.row = row;
      this.orgs.set(row.id, held);
      for (const [generation, key] of held.older) if (!key) held.older.delete(generation);
      try {
        await this.settleKey(held);
        changed += await this.pullRows(held);
        changed += await this.pullLogs(held);
        held.fault = null;
      } catch (failure) {
        // A lapsed session is everyone's; anything else is this organization's alone, and said.
        if (statusOf(failure) === 401) throw failure;
        held.fault = failureText(failure);
      }
    }
    return changed;
  }

  /** The organizations whose key in force is in hand: the ones whose rooms the connector can seal a word in (mcp/live.ts). */
  keys(): { id: string; key: CryptoKey }[] {
    return [...this.orgs.values()].filter((held) => held.key).map((held) => ({ id: held.row.id, key: held.key! }));
  }

  /** Every organization read fresh: the list, the keys, the rows since each cursor, the logs that moved. */
  refresh(): Promise<number> {
    this.refreshing ??= this.read().finally(() => {
      this.refreshing = null;
    });
    return this.refreshing;
  }

  /**
   * Each organization whose notes this can read told which AI is reading them through this member (`POST
   * orgs/:id/ais { name }`; server/src/store/org_ais.rs), so its members see it listed beside them: once when the
   * organization's key is first in hand, and again only after `TELL_EVERY_MS`. The name is what the AI's app called
   * itself and nothing else. Never a tool's failure: a service without the route, or any refusal, is nothing to do.
   */
  async announce(name: string, now = Date.now()): Promise<void> {
    for (const held of this.orgs.values()) {
      if (!held.key) continue;
      const at = held.told.get(name);
      if (at !== undefined && now - at < TELL_EVERY_MS) continue;
      held.told.set(name, now);
      await this.service.call('POST', this.route(held, 'ais'), { name }).catch(() => undefined);
    }
  }

  private record(held: Held, entry: Entry): TeamRecord {
    const images = imageNames(entry.note.body);
    return { rev: entry.rev, note: entry.note, org: { id: held.row.id, name: held.row.name }, ...(images.length ? { images } : {}) };
  }

  /** Every team note that opened. */
  list(): TeamRecord[] {
    const out: TeamRecord[] = [];
    const seen = new Set<string>();
    for (const held of this.orgs.values()) {
      for (const [id, entry] of held.notes) {
        if (seen.has(id)) continue;
        seen.add(id);
        out.push(this.record(held, entry));
      }
    }
    return out;
  }

  private find(id: string): { held: Held; entry: Entry } | null {
    for (const held of this.orgs.values()) {
      const entry = held.notes.get(id);
      if (entry) return { held, entry };
    }
    return null;
  }

  get(id: string): TeamRecord | null {
    const found = this.find(id);
    return found ? this.record(found.held, found.entry) : null;
  }

  /** The organizations the account is a member of, with what of each could be read. */
  organizations(): { id: string; name: string; notes: number; unreadable: number; why: string | null }[] {
    return [...this.orgs.values()].map((held) => ({ id: held.row.id, name: held.row.name, notes: held.notes.size, unreadable: held.unreadable.size, why: held.unreadable.size ? this.why(held) : null }));
  }

  private why(held: Held): string {
    return held.keyWhy ?? 'they are sealed under a generation of its key this account has no wrap at';
  }

  /** The organization holding a note this connector cannot read, and why; null for a note it knows nothing of. */
  whereabouts(id: string): { org: OrgName; why: string } | null {
    for (const held of this.orgs.values()) if (held.unreadable.has(id)) return { org: { id: held.row.id, name: held.row.name }, why: this.why(held) };
    return null;
  }

  /** Whether a team holds this note, read or not: the account's own row of it is then a leftover. */
  holds(id: string): boolean {
    for (const held of this.orgs.values()) if (held.notes.has(id) || held.unreadable.has(id)) return true;
    return false;
  }

  /** What could not be read, in words: never silently missing. */
  notices(): string[] {
    const out: string[] = [];
    for (const held of this.orgs.values()) {
      const n = held.unreadable.size;
      if (n) out.push(`${n} ${n === 1 ? 'note' : 'notes'} in ${held.row.name} ${n === 1 ? 'is' : 'are'} not readable by this connector: ${this.why(held)}.`);
      if (held.fault) out.push(`${held.row.name} could not be read just now (${held.fault}); what is shown of it is as it was last read.`);
    }
    return out;
  }

  // --- writing -----------------------------------------------------------------------------

  private org(orgId: string): Held {
    const held = this.orgs.get(orgId);
    if (!held) throw new Error('This account is not a member of that organization.');
    return held;
  }

  private keyOf(held: Held): CryptoKey {
    if (!held.key) throw new Error(`${held.row.name}’s notes cannot be written by this connector: ${held.keyWhy ?? 'its key is not in hand'}.`);
    return held.key;
  }

  /** `work` done; refused because the key turned (S11), this account's wrap at the new generation is read and it is done once more. */
  private async underKey<T>(held: Held, work: () => Promise<T>): Promise<T> {
    try {
      return await work();
    } catch (failure) {
      if (!turned(failure)) throw failure;
      await this.settleKey(held, true);
      this.keyOf(held);
      return work();
    }
  }

  /**
   * The note's row put: a snapshot of its document and its particulars, from the revision last read, cutting the log
   * to the seq the snapshot covers. A row another member put first is merged - their document into this one, their
   * note with the pin and the archive set here - and put again from theirs, once.
   */
  private async putRow(held: Held, id: string, { fresh = false, retry = true }: { fresh?: boolean; retry?: boolean } = {}): Promise<void> {
    const entry = held.notes.get(id)!;
    const key = this.keyOf(held);
    const images = imageNames(entry.note.body);
    const payload: TeamPayload = { v: 1, note: entry.note, state: toBase64Url(entry.state), seq: entry.seq, ...(images.length ? { images } : {}), ...(entry.versions ? { versions: entry.versions } : {}) };
    const blob = await seal(key, payload, noteContext(held.row.id, id));
    try {
      const { rev } = await this.service.call<{ rev: number }>('PUT', this.route(held, `notes/${encodeURIComponent(id)}`), { base: entry.rev, blob, upTo: entry.seq, generation: held.generation });
      entry.rev = rev;
      entry.owed = false;
    } catch (failure) {
      const winner = winnerOf(failure);
      if (!winner || !retry) throw failure;
      if (winner.deleted || !winner.blob) {
        // A note new to the team goes over a row of its id deleted before; one the team held is gone.
        if (!fresh) {
          held.notes.delete(id);
          throw new Error('Another member took this note out of the team first.', { cause: failure });
        }
        entry.rev = winner.rev;
        return this.putRow(held, id, { fresh, retry: false });
      }
      const theirs = await this.opened(held, (k) => open<TeamPayload>(k, winner.blob!, noteContext(held.row.id, id)));
      const doc = looseTeamDoc(id, { state: entry.state, seq: entry.seq, snapshotSeq: entry.seq, pending: [] });
      try {
        doc.applyRemote([fromBase64Url(theirs.state)], theirs.seq);
        entry.note = { ...theirs.note, id, starred: entry.note.starred, archivedAt: entry.note.archivedAt, body: doc.words(), updatedAt: Math.max(entry.note.updatedAt, theirs.note.updatedAt) };
        entry.state = doc.snapshot();
        entry.seq = doc.seq;
        entry.rev = winner.rev;
        if (theirs.versions) entry.versions = theirs.versions;
      } finally {
        await release(doc);
      }
      return this.putRow(held, id, { fresh, retry: false });
    }
  }

  /**
   * A team note changed by `change`. Its words are reconciled into its document as the app reconciles them, and what
   * that changed goes to the note's log as updates; a pin or an archive that changed is put as its row. A member with
   * the note open sees the words come as they are typed (`TeamService.type`, mcp/live.ts), and the log is written
   * the same either way.
   *
   * The change is made once, before the log is written: a post refused because the key turned (S11) is sealed again
   * and sent again, the same updates, never the change made a second time, which a member who watched it typed would
   * hold twice.
   */
  async edit(id: string, change: (note: Note) => Note, now = Date.now()): Promise<TeamRecord> {
    const found = this.find(id);
    if (!found) throw new Error(`No team note ${id}.`);
    const { held } = found;
    this.keyOf(held);
    const before = found.entry.note;
    const next: Note = { ...before, ...change({ ...before }), id, createdAt: before.createdAt };
    const doc = looseTeamDoc(id, { state: found.entry.state, seq: found.entry.seq, snapshotSeq: found.entry.seq, pending: [] });
    try {
      if (!(await this.service.type?.(held.row.id, id, doc, next.body))) doc.reconcile(next.body);
      let seq = found.entry.seq;
      await this.underKey(held, async () => {
        const key = this.keyOf(held);
        const entry = held.notes.get(id);
        if (!entry) throw new Error(`No team note ${id}.`);
        let cut = false;
        for (let pending = doc.pending(); pending.length && !cut; pending = doc.pending()) {
          const batch = pending.slice(0, POST_AT_MOST);
          const blobs: string[] = [];
          for (const update of batch) blobs.push(toBase64Url(await sealBytes(key, update as Bytes, updateContext(held.row.id, id))));
          try {
            const answer = await this.service.call<{ seq: number }>('POST', this.route(held, `notes/${encodeURIComponent(id)}/updates`), { blobs, generation: held.generation });
            // Exactly these went on the end of the log: nothing of the team's between, so nothing to read back.
            if (answer.seq - batch.length === seq) seq = answer.seq;
            doc.posted(batch.length);
          } catch (failure) {
            if (statusOf(failure) === 404 && !notYet(failure)) {
              held.notes.delete(id);
              throw new Error('That note is no longer the team’s: another member deleted it or took it out.', { cause: failure });
            }
            // The log is as long as the service keeps one (S11): the row, put, carries these and cuts it.
            if (statusOf(failure) === 409 && bodyOf(failure)?.error === 'snapshot') cut = true;
            else throw failure;
          }
        }
        const words = doc.words();
        const note: Note = { ...next, body: words };
        const moved = words !== before.body || particulars(note) !== particulars(before);
        note.updatedAt = moved ? Math.max(now, before.updatedAt + 1) : before.updatedAt;
        if (words !== before.body) {
          note.formatted = null;
          note.formattedFor = null;
          note.formattedModel = null;
        }
        entry.note = note;
        entry.state = doc.snapshot();
        entry.seq = seq;
        // A member's device fetches a note's pictures from its row (core/team/sync.ts), never from the log: a body
        // that names a picture the row does not list is put again, or the picture is a name with nothing behind it.
        const pictured = imageNames(words).join('\n') !== imageNames(before.body).join('\n');
        if (cut || pictured || particulars(note) !== particulars(before)) entry.owed = true;
        if (entry.owed) await this.putRow(held, id);
      });
    } finally {
      await release(doc);
    }
    return this.get(id)!;
  }

  /** A note put to the team for the first time: its document seeded with its words, the whole of it in the row. */
  private async place(held: Held, note: Note): Promise<TeamRecord> {
    this.keyOf(held);
    const doc = looseTeamDoc(note.id, null, note.body);
    try {
      held.notes.set(note.id, { rev: 0, note: { ...note, body: doc.words() }, state: doc.snapshot(), seq: 0, owed: true });
    } finally {
      await release(doc);
    }
    try {
      await this.underKey(held, () => this.putRow(held, note.id, { fresh: true }));
    } catch (failure) {
      if (held.notes.get(note.id)?.rev === 0) held.notes.delete(note.id);
      throw failure;
    }
    held.unreadable.delete(note.id);
    return this.get(note.id)!;
  }

  /** A new note in an organization, the team's from its first word. */
  create(orgId: string, body: string, { pinned = false, now = Date.now() }: { pinned?: boolean; now?: number } = {}): Promise<TeamRecord> {
    return this.place(this.org(orgId), { id: randomId(), body, createdAt: now, updatedAt: now, source: 'editor', starred: pinned, archivedAt: null });
  }

  /**
   * One of the account's own notes put to an organization, as filing it there on a device does: its pictures first,
   * read from the account's files and sealed again under the organization key, then its row. A note the team holds
   * already is left as the team has it. Answers the pictures that could not be carried.
   */
  async adopt(orgId: string, note: Note): Promise<{ record: TeamRecord; left: string[] }> {
    const held = this.org(orgId);
    const has = held.notes.get(note.id);
    if (has) return { record: this.record(held, has), left: [] };
    if (held.unreadable.has(note.id)) throw new Error(`${held.row.name} holds this note already, and it is not readable by this connector: ${this.why(held)}.`);
    const key = this.keyOf(held);
    const left: string[] = [];
    for (const name of imageNames(note.body)) {
      const id = pictureId(name);
      if (!id) continue;
      try {
        const plain = await openBytes(await this.service.accountKey(), await this.service.bytes('GET', `recordings/${id}`), `file:${id}`);
        await this.service.bytes('PUT', this.route(held, `files/${id}?base=0&generation=${held.generation}`), await sealBytes(key, plain, `file:${id}`));
      } catch (failure) {
        // There already (a picture's name is never reused) is carried; anything else is said.
        if (statusOf(failure) === 409 && !turned(failure)) continue;
        left.push(name);
      }
    }
    return { record: await this.place(held, note), left };
  }

  /**
   * A picture's bytes kept for organization `orgId`, sealed under its key as a member's device seals one, before the
   * note that names it is written: a member who reads the note fetches it then (core/team/sync.ts), and the team has
   * no settling pass that would fetch it later. One there already is left, as a name is never reused.
   */
  async putPicture(orgId: string, name: string, plain: Bytes): Promise<void> {
    const held = this.org(orgId);
    const id = pictureId(name);
    if (!id) throw new Error(`${name} is not a picture’s name.`);
    await this.underKey(held, async () => {
      try {
        await this.service.bytes('PUT', this.route(held, `files/${id}?base=0&generation=${held.generation}`), await sealBytes(this.keyOf(held), plain, `file:${id}`));
      } catch (failure) {
        if (statusOf(failure) === 409 && !turned(failure)) return;
        throw failure;
      }
    });
  }

  /** A note taken out of an organization: its row deleted, from the revision last read or the one that won. */
  async remove(orgId: string, id: string): Promise<void> {
    const held = this.org(orgId);
    const entry = held.notes.get(id);
    if (!entry) return;
    const path = this.route(held, `notes/${encodeURIComponent(id)}`);
    try {
      await this.service.call('DELETE', path, { base: entry.rev });
    } catch (failure) {
      const winner = winnerOf(failure);
      if (!winner) throw failure;
      if (!winner.deleted) await this.service.call('DELETE', path, { base: winner.rev });
    }
    held.notes.delete(id);
  }
}
