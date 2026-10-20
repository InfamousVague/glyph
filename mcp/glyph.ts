import type { SignedIn } from '../tauri/src/app/core/account/account.ts';
import { notYet } from '../tauri/src/app/core/account/notYet.ts';
import { failureText } from '../tauri/src/app/core/failure.ts';
import { randomId, shortId } from '../tauri/src/app/core/ids.ts';
import { imageNames } from '../tauri/src/app/core/imageRefs.ts';
import type { Details, DetailsOf, SelfKind } from '../tauri/src/app/core/notifications/kinds.ts';
import { noteTitle } from '../tauri/src/app/core/noteTitle.ts';
import type { Note } from '../tauri/src/app/core/store.ts';
import { derive, fromBase64Url, open, passwordSalt, ROUNDS, seal, sealBytes, toBase64Url, unwrap } from '../tauri/src/app/core/sync/crypto.ts';
import type { Bytes } from '../tauri/src/app/core/sync/crypto.ts';
import type { FeedItem, NotePayload } from '../tauri/src/app/core/sync/notes.ts';
import { liveUrl } from '../tauri/src/app/core/live/transport.ts';
import { LiveClient, type LiveDeps } from './live.ts';
import { pictureId, TeamNotes, type OrgName } from './team.ts';

/**
 * A Glyph account from outside the app: the sync service (docs/SYNC.md) as a client that signs in, reads the
 * account's notes and writes them, for the MCP server (mcp/server.ts, docs/MCP.md).
 *
 * The notes are end-to-end encrypted, so this is a device like any other: it signs in with the password once, keeps
 * the account key it unwraps, and seals and opens every note with it. The service sees nothing it did not already
 * see from a phone. What it keeps between runs (`StoredSession`) is what a signed-in phone keeps: the session token,
 * the account key, and a signing key of its own that renews a lapsed session without the password.
 *
 * It mirrors core/sync/notes.ts on the wire - the same sealed payload under the same associated data, the same feed
 * and the same `base` on every write - and it never overwrites what it has not read: a write another device beat is
 * refused by the service, and comes back here as a `Conflict` carrying that device's note. A note is never lost to a
 * race, which is the rule the app lives by too.
 *
 * What Claude wrote is told to the account as well (docs/TEAMS.md; Matt: "wire up existing features to notifications
 * where it makes sense so that we see things like claude creating a new note or making edits"): after a write lands,
 * `postNotification` seals a notification under the same account key, as the app seals its own
 * (core/notifications/record.ts), and posts it. Best effort, every time: a notification that does not land - a
 * service from before the route, a limit, a bad answer - is a line on stderr and nothing else, since the note was
 * written and that is what the tool answers about.
 *
 * The account's organizations are read and written with it (mcp/team.ts; docs/SHARED.md): `pull` reads each team's
 * notes after the account's own, `list` and `get` answer a team's note as they answer the account's, with the
 * organization it is in (`NoteRecord.org`), and `edit` and `create` write one through the team's own channel. A note
 * a team holds is the team's: a row of the same id left in the account's own feed is a leftover, and is passed over.
 */

export interface StoredSession {
  v: 1;
  /** The service, `https://attack.fm/glyph/api` unless told otherwise. */
  api: string;
  handle: string;
  accountId: number;
  token: string;
  /** The account key, raw, as base64url: what opens every note. Kept the way a signed-in device keeps it. */
  accountKey: string;
  /** This client's own Ed25519 signing key, a private JWK, for renewing a lapsed session without the password. */
  deviceKey: JsonWebKey | null;
}

/** A refusal from the service, with its status and its own words. */
export class GlyphApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly body: unknown = null,
  ) {
    super(message);
  }
}

/** A write another device beat: the service kept theirs, and here it is. */
export class Conflict extends Error {
  constructor(readonly theirs: NoteRecord | null) {
    super(theirs ? 'Another device changed this note first; read it again before writing.' : 'Another device deleted this note.');
  }
}

/** A note as the account holds it: its words, and the revision this client last saw. */
export interface NoteRecord {
  rev: number;
  note: Note;
  /** The hash of the note's recording on the service, if it has one; sent back unchanged with every write. */
  recording?: string;
  /** The pictures the note's body uses, by name; sent back with every write, minus any the body no longer names. */
  images?: string[];
  /** The organization the note is the team's in (docs/SHARED.md, S1); absent for one of the account's own. */
  org?: OrgName;
}

export const DEFAULT_API = 'https://attack.fm/glyph/api';
const TIMEOUT_MS = 30_000;
const encoder = new TextEncoder();

export interface Hooks {
  fetcher?: typeof fetch;
  /** Called whenever the session changes (a renewed token), so what is kept between runs keeps up. */
  save?: (session: StoredSession) => void;
  /** The account key as a key object, in place of the session's bytes: the hosted server holds it this way in memory (docs/MCP.md). */
  key?: CryptoKey;
  /** The session could not be renewed and needs the password again. */
  lapsed?: () => void;
  /**
   * Claude online and typing in the notes a person has open (mcp/live.ts, docs/CLAUDE_LIVE.md): on unless `false`,
   * and off by default when a `fetcher` is given, since a service in memory has no relay. A test's own socket and
   * pace go here.
   */
  live?: false | Pick<LiveDeps, 'socket' | 'pace'>;
}

/** One JSON call to `<api>/v1/<path>`. */
async function callApi<T>(api: string, method: string, path: string, { token, body, fetcher = fetch }: { token?: string; body?: unknown; fetcher?: typeof fetch }): Promise<T> {
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetcher(`${api}/v1/${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), signal: controller.signal });
  } catch (failure) {
    if (controller.signal.aborted) throw new GlyphApiError(0, 'The sync service took too long to answer.');
    throw new GlyphApiError(0, `The sync service could not be reached (${failureText(failure)}).`);
  } finally {
    clearTimeout(timer);
  }
  const text = await response.text();
  const answer = text ? (JSON.parse(text) as unknown) : null;
  if (!response.ok) {
    const words = answer && typeof answer === 'object' && typeof (answer as { error?: unknown }).error === 'string' ? (answer as { error: string }).error : null;
    throw new GlyphApiError(response.status, words ?? `The sync service answered ${response.status}.`, answer);
  }
  return answer as T;
}

/**
 * The account key from its raw bytes as base64url, as a key this process can use and never read out: the kept
 * session's (`StoredSession.accountKey`), or what the hosted sign-in page unwrapped in the person's browser
 * (mcp/hosted.ts). Given `length`, a key of any other length is refused before it is imported: the hosted route asks
 * for 32 bytes, since what it is handed comes from a browser, while a kept session's key is imported as it was kept.
 * The bytes are zeroed once the key is made, or refused.
 */
export async function importAccountKey(raw: string, { length }: { length?: number } = {}): Promise<CryptoKey> {
  const bytes = fromBase64Url(raw);
  try {
    if (length !== undefined && bytes.length !== length) throw new Error(`not ${length} bytes`);
    return await crypto.subtle.importKey('raw', bytes, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
  } finally {
    bytes.fill(0);
  }
}

export class GlyphAccount {
  private key: CryptoKey | null = null;
  private cursor = 0;
  private readonly cache = new Map<string, NoteRecord>();
  private pulled = false;
  private readonly teams: TeamNotes;
  /** Why the organizations could not be read at the last pull; null when they were. */
  private teamsFault: string | null = null;
  /** The AI this client is working for, by the name its app gave (`actsAs`); null until it is known. */
  private ai: string | null = null;
  /** The relay client, made the first time it is asked for (`live`); null when this account has none. */
  private relay: LiveClient | null | undefined;

  constructor(
    private session: StoredSession,
    private readonly hooks: Hooks = {},
  ) {
    this.key = hooks.key ?? null;
    this.teams = new TeamNotes({
      call: (method, path, body) => this.call(method, path, body),
      bytes: (method, path, body) => this.bytes(method, path, body),
      accountKey: () => this.accountKey(),
      // A team note's change typed into its room while a member has it open; nothing is typed while Claude is not online.
      type: async (orgId, noteId, doc, words) => Boolean(this.relay?.online && (await this.relay.typeTeam(orgId, noteId, doc, words))),
    });
  }

  /**
   * The account's client on the live relay (mcp/live.ts): Claude seen online by the account's devices and its
   * organizations', and typing in the notes they have open. Made the first time it is asked for, and null when the
   * hooks turned it off.
   */
  live(): LiveClient | null {
    if (this.relay !== undefined) return this.relay;
    const options = this.hooks.live ?? (this.hooks.fetcher ? false : {});
    this.relay =
      options === false
        ? null
        : new LiveClient({
            url: liveUrl(this.session.api),
            token: () => this.session.token,
            resume: () => this.resume(),
            handle: () => this.session.handle,
            accountKey: () => this.accountKey(),
            orgKeys: () => this.teams.keys(),
            ...options,
          });
    return this.relay;
  }

  /** The relay let go of, for good: the session holding this account is over (mcp/hostedStore.ts). */
  letGo(): void {
    this.relay?.close();
  }

  /**
   * In with the password: the two halves are derived as the app derives them, the login half goes to the service, and
   * the wrap half opens the account key here. This client's own signing key is registered on the account, so the
   * session can be renewed later without the password, as a phone's is.
   */
  static async signIn(
    api: string,
    handle: string,
    password: string,
    { rounds = ROUNDS, fetcher = fetch, label = 'Claude' }: { rounds?: number; fetcher?: typeof fetch; label?: string } = {},
  ): Promise<StoredSession> {
    const base = api.replace(/\/+$/, '');
    const { login, wrapKey } = await derive(password, passwordSalt(handle), rounds);
    const answer = await callApi<SignedIn>(base, 'POST', 'login', { fetcher, body: { handle: handle.trim(), loginSecret: login } });
    if (!answer.wrapped) throw new GlyphApiError(500, 'The service answered without this account’s key.');
    const accountKey = await unwrap(answer.wrapped, wrapKey, true).catch(() => {
      throw new GlyphApiError(401, 'This account’s key would not open with that password.');
    });
    const raw = toBase64Url(new Uint8Array(await crypto.subtle.exportKey('raw', accountKey)));
    // Extractable, unlike the app's, because this client has to keep it between runs in a file rather than in a browser's key store.
    const pair = (await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify'])) as CryptoKeyPair;
    let deviceKey: JsonWebKey | null = null;
    try {
      const devicePublicKey = toBase64Url(new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey)));
      await callApi(base, 'POST', 'device', { token: answer.token, fetcher, body: { devicePublicKey, label } });
      deviceKey = await crypto.subtle.exportKey('jwk', pair.privateKey);
    } catch {
      // No device key: the session still works for as long as its token does, and then the password is asked for again.
    }
    return { v: 1, api: base, handle: answer.account.handle, accountId: answer.account.id, token: answer.token, accountKey: raw, deviceKey };
  }

  get handle(): string {
    return this.session.handle;
  }

  get api(): string {
    return this.session.api;
  }

  private async accountKey(): Promise<CryptoKey> {
    this.key ??= await importAccountKey(this.session.accountKey);
    return this.key;
  }

  private update(session: StoredSession): void {
    this.session = session;
    this.hooks.save?.(session);
  }

  /**
   * The session renewed: with its token while that is good, and, once it has lapsed, with this client's own key. A
   * session that can be renewed neither way needs the password again (`signIn`).
   */
  async resume(): Promise<void> {
    const { api, token, handle } = this.session;
    try {
      const answer = await callApi<SignedIn>(api, 'POST', 'refresh', { token, fetcher: this.hooks.fetcher });
      this.update({ ...this.session, token: answer.token, accountId: answer.account.id, handle: answer.account.handle });
      return;
    } catch (failure) {
      if (!(failure instanceof GlyphApiError) || failure.status !== 401) throw failure;
    }
    const jwk = this.session.deviceKey;
    if (!jwk) {
      this.hooks.lapsed?.();
      throw new GlyphApiError(401, 'This session has lapsed. Sign in again with `login`.');
    }
    const privateKey = await crypto.subtle.importKey('jwk', jwk, { name: 'Ed25519' }, false, ['sign']);
    const { nonce } = await callApi<{ nonce: string }>(api, 'POST', 'login/challenge', { fetcher: this.hooks.fetcher, body: { handle } });
    const signature = toBase64Url(new Uint8Array(await crypto.subtle.sign({ name: 'Ed25519' }, privateKey, encoder.encode(nonce))));
    const answer = await callApi<SignedIn>(api, 'POST', 'login/device', { fetcher: this.hooks.fetcher, body: { handle, nonce, signature } }).catch((failure: unknown) => {
      if (failure instanceof GlyphApiError && failure.status === 401) {
        this.hooks.lapsed?.();
        throw new GlyphApiError(401, 'This session has lapsed and could not be renewed. Sign in again with `login`.');
      }
      throw failure;
    });
    this.update({ ...this.session, token: answer.token, accountId: answer.account.id, handle: answer.account.handle });
  }

  /** A call as the account; a lapsed token is renewed once and the call made again. */
  private async call<T>(method: string, path: string, body?: unknown, renewed = false): Promise<T> {
    try {
      return await callApi<T>(this.session.api, method, path, { token: this.session.token, body, fetcher: this.hooks.fetcher });
    } catch (failure) {
      if (failure instanceof GlyphApiError && failure.status === 401 && !renewed) {
        await this.resume();
        return this.call<T>(method, path, body, true);
      }
      throw failure;
    }
  }

  /** A file's bytes fetched or sent as the account (`recordings/<id>`, `orgs/<id>/files/<id>`); a lapsed token is renewed once. */
  private async bytes(method: 'GET' | 'PUT', path: string, body?: Bytes, renewed = false): Promise<Bytes> {
    const headers: Record<string, string> = { Authorization: `Bearer ${this.session.token}` };
    if (body) headers['Content-Type'] = 'application/octet-stream';
    let response: Response;
    try {
      response = await (this.hooks.fetcher ?? fetch)(`${this.session.api}/v1/${path}`, { method, headers, body: body as unknown as BodyInit | undefined, signal: AbortSignal.timeout(300_000) });
    } catch (failure) {
      throw new GlyphApiError(0, `The sync service could not be reached (${failureText(failure)}).`);
    }
    if (response.status === 401 && !renewed) {
      await this.resume();
      return this.bytes(method, path, body, true);
    }
    if (!response.ok) {
      const text = await response.text();
      let answer: unknown = null;
      try {
        answer = text ? JSON.parse(text) : null;
      } catch {
        // Not the service's own words.
      }
      throw new GlyphApiError(response.status, `The sync service answered ${response.status}.`, answer);
    }
    return new Uint8Array(await response.arrayBuffer());
  }

  private async record(item: FeedItem): Promise<NoteRecord | null> {
    if (item.deleted || !item.blob) return null;
    const payload = await open<NotePayload>(await this.accountKey(), item.blob, `note:${item.id}`);
    const record: NoteRecord = { rev: item.rev, note: { ...payload.note, id: item.id } };
    if (payload.recording) record.recording = payload.recording;
    if (payload.images?.length) record.images = payload.images;
    return record;
  }

  /** Everything written since the last pull, opened and kept. */
  async pull(): Promise<{ changed: number }> {
    let changed = 0;
    for (;;) {
      const page = await this.call<{ rev: number; items: FeedItem[]; more: boolean }>('GET', `notes?since=${this.cursor}`);
      for (const item of page.items) {
        const known = this.cache.get(item.id);
        if (known && known.rev === item.rev) continue;
        const record = await this.record(item);
        if (record) this.cache.set(item.id, record);
        else this.cache.delete(item.id);
        changed += 1;
      }
      this.cursor = Math.max(this.cursor, page.rev);
      if (!page.more) break;
    }
    this.pulled = true;
    // The organizations after the account's own. Theirs failing is not the account's: said (`notices`), and the
    // account's notes are answered all the same. A lapsed session is everyone's.
    try {
      changed += await this.teams.refresh();
      this.teamsFault = null;
      // And each organization read told which AI read it, so its members see it listed (mcp/team.ts `announce`).
      if (this.ai) await this.teams.announce(this.ai);
    } catch (failure) {
      if (failure instanceof GlyphApiError && failure.status === 401) throw failure;
      this.teamsFault = failureText(failure);
    }
    return { changed };
  }

  /**
   * The account's own notes: the ones no team holds. A row of the account's with the id of a note a team holds is
   * what was left when the note went to the team, and is not the note any more.
   */
  private own(): NoteRecord[] {
    return [...this.cache.values()].filter((r) => !this.teams.holds(r.note.id));
  }

  /**
   * The notes, newest change first: the account's own and its organizations', archived ones included when asked;
   * `own` for the account's alone. Pulls first if nothing has been.
   */
  async list({ archived = false, own = false }: { archived?: boolean; own?: boolean } = {}): Promise<NoteRecord[]> {
    if (!this.pulled) await this.pull();
    return [...this.own(), ...(own ? [] : this.teams.list())].filter((r) => archived || !r.note.archivedAt).sort((a, b) => b.note.updatedAt - a.note.updatedAt);
  }

  async get(id: string): Promise<NoteRecord | null> {
    if (!this.pulled) await this.pull();
    return this.teams.get(id) ?? (this.teams.holds(id) ? null : (this.cache.get(id) ?? null));
  }

  /**
   * Whose hands this client is: the AI's name, as its app gave it when it connected (core/authors.ts `aiName`). An
   * organization whose notes are read is told this name, and only this, so its members see the AI listed.
   */
  actsAs(name: string): void {
    this.ai = name.trim().slice(0, 40) || null;
  }

  /** The organizations the account is a member of, with how many notes of each were read and how many were not. */
  organizations(): ReturnType<TeamNotes['organizations']> {
    return this.teams.organizations();
  }

  /** What of the organizations could not be read, in sentences: nothing is left silently missing. */
  notices(): string[] {
    return [...this.teams.notices(), ...(this.teamsFault ? [`This account’s organizations could not be read just now (${this.teamsFault}); their notes are missing from this answer.`] : [])];
  }

  /** The organization holding a note this connector cannot read, and why; null for a note it knows nothing of. */
  whereabouts(id: string): ReturnType<TeamNotes['whereabouts']> {
    return this.teams.whereabouts(id);
  }

  /** The note whose title is `title`, exactly or ignoring case; null when none or several. */
  async byTitle(title: string): Promise<NoteRecord | null> {
    const want = title.trim().toLowerCase();
    const found = (await this.list({ archived: true })).filter((r) => noteTitle(r.note.body).toLowerCase() === want);
    return found.length === 1 ? found[0]! : null;
  }

  /** `record` written to the service from the revision it was read at; the answer is the revision it now has. */
  private async write(record: NoteRecord, base: number, over = false): Promise<NoteRecord> {
    const { note } = record;
    const payload: NotePayload = { v: 1, note };
    if (record.recording) payload.recording = record.recording;
    if (record.images?.length) payload.images = record.images;
    const blob = await seal(await this.accountKey(), payload, `note:${note.id}`);
    try {
      const { rev } = await this.call<{ rev: number }>('PUT', `notes/${encodeURIComponent(note.id)}`, { base, blob });
      const written = { ...record, rev };
      this.cache.set(note.id, written);
      return written;
    } catch (failure) {
      if (!(failure instanceof GlyphApiError) || failure.status !== 409 || !failure.body) throw failure;
      // Another device wrote first: theirs is the note now, and it is what the caller reads next.
      const winner = failure.body as FeedItem;
      // `over`: whatever stands at that id is written over, once - a leftover, or a deletion (`move`).
      if (over) return this.write(record, winner.rev);
      const theirs = await this.record(winner);
      if (theirs) this.cache.set(note.id, theirs);
      else this.cache.delete(note.id);
      throw new Conflict(theirs);
    }
  }

  /** A new note of `body`, as the app would make one typed in; in organization `org`, the team's from its first word. */
  async create(body: string, { pinned = false, org, path }: { pinned?: boolean; org?: string; path?: string } = {}): Promise<NoteRecord> {
    if (org) return this.teams.create(org, body, { pinned, ...(path ? { path } : {}) });
    const now = Date.now();
    const note: Note = { id: randomId(), body, createdAt: now, updatedAt: now, source: 'editor', starred: pinned, archivedAt: null };
    const images = imageNames(body);
    return this.write({ rev: 0, note, ...(images.length ? { images } : {}) }, 0);
  }

  /**
   * A picture's bytes kept where `record`'s readers fetch it from, sealed as a device seals one: the account's files
   * for one of its own notes, the organization's for a team's. Done before the note names it, so no device reads a
   * name with nothing behind it. One there already is left, as a name is never reused.
   */
  async putPicture(record: NoteRecord, name: string, plain: Bytes): Promise<void> {
    if (record.org) return this.teams.putPicture(record.org.id, name, plain);
    const id = pictureId(name);
    if (!id) throw new GlyphApiError(400, `${name} is not a picture’s name.`);
    try {
      await this.bytes('PUT', `recordings/${id}?base=0`, await sealBytes(await this.accountKey(), plain, `file:${id}`));
    } catch (failure) {
      if (failure instanceof GlyphApiError && failure.status === 409) return;
      throw failure;
    }
  }

  /**
   * `id` changed by `change`, written from the revision last read. The words are the caller's; everything else the
   * note carried - when it was made, its pin, its folder, its recording - stays. A body that changed drops the
   * on-device model's formatted copy, which the app writes again for the new words.
   */
  async edit(id: string, change: (note: Note) => Note): Promise<NoteRecord> {
    const current = await this.get(id);
    if (!current) throw new GlyphApiError(404, `No note ${id}.`);
    // A team's note is written through its document (mcp/team.ts): an update to its log, merged, never refused.
    if (current.org) return this.teams.edit(id, change);
    const before = current.note;
    const next = change({ ...before });
    const note: Note = { ...before, ...next, id, createdAt: before.createdAt, updatedAt: Math.max(Date.now(), before.updatedAt + 1) };
    // Typed into the note's room while a device of the account has it open; the words the room ends with are the
    // ones written, so that device's next pass reads its own words back and has nothing to copy.
    if (note.body !== before.body && this.relay?.online) note.body = (await this.relay.typeOwn(id, before.body, note.body)) ?? note.body;
    if (note.body !== before.body) {
      note.formatted = null;
      note.formattedFor = null;
      note.formattedModel = null;
    }
    // Every picture the words show, as a device writing the note would name them: a picture added here, whose file is
    // on some device, is then fetched by every other one (app core/sync/notes.ts), and one the words dropped goes.
    const images = imageNames(note.body);
    return this.write({ rev: current.rev, note, recording: current.recording, images }, current.rev);
  }

  /**
   * A note moved to organization `org`, or - null - back to the account's own, as filing it does on a device
   * (docs/SHARED.md, S1; core/sync/notes.ts, core/team/sync.ts): into an organization it is put to the team and its
   * row in the account's feed deleted, so the account's devices take it from the team; out of one it is written to
   * the account and its row deleted from the team. From one organization to another it goes to the second, then
   * from the first. Answers the note where it now is, and the pictures that could not be carried to a team. With
   * `path`, a note going to a team goes at that path: a folder of the organization's (GHST-108).
   */
  async move(id: string, org: string | null, { path }: { path?: string } = {}): Promise<{ record: NoteRecord; left: string[] }> {
    const current = await this.get(id);
    if (!current) throw new GlyphApiError(404, `No note ${id}.`);
    if ((current.org?.id ?? null) === org) return { record: current, left: [] };
    if (org) {
      const placed = await this.teams.adopt(org, current.note, path);
      if (current.org) await this.teams.remove(current.org.id, id);
      const mine = this.cache.get(id);
      if (mine) {
        // The account's own row goes; one that will not (another device wrote it meanwhile) is a leftover, passed over.
        await this.call('DELETE', `notes/${encodeURIComponent(id)}`, { base: mine.rev }).catch((failure: unknown) => {
          if (!(failure instanceof GlyphApiError) || failure.status !== 409) throw failure;
        });
        this.cache.delete(id);
      }
      return placed;
    }
    const from = current.org!;
    const record: NoteRecord = { rev: 0, note: current.note, ...(current.images?.length ? { images: current.images } : {}) };
    // Over whatever the account's feed holds at that id: a leftover, or the deletion from when it went to the team.
    const written = await this.write(record, this.cache.get(id)?.rev ?? 0, true);
    await this.teams.remove(from.id, id);
    return { record: written, left: [] };
  }

  /**
   * A team note's path changed, and only its path (GHST-108): a folder of its organization's to another, the row put
   * so every member's device files it there. Not for one of the account's own, whose file the person's devices move
   * by its filing in the settings.
   */
  async repath(id: string, path: string): Promise<NoteRecord> {
    const current = await this.get(id);
    if (!current) throw new GlyphApiError(404, `No note ${id}.`);
    if (!current.org) throw new Error(`The note ${id} is not an organization’s: its folder is its filing.`);
    return this.teams.repath(id, path);
  }

  /**
   * The account's synced settings (core/sync/prefs.ts, docs/SYNC.md): one object sealed under the account key with
   * `prefs` as its context, and the revision it was written at. Every key is kept as it came, known to this client or
   * not, so a write here never drops a setting a newer app added.
   */
  async readPrefs(): Promise<{ rev: number; prefs: Record<string, unknown> }> {
    const { rev, blob } = await this.call<{ rev: number; blob: string | null }>('GET', 'prefs');
    const opened = blob ? await open<unknown>(await this.accountKey(), blob, 'prefs') : null;
    return { rev, prefs: opened && typeof opened === 'object' && !Array.isArray(opened) ? (opened as Record<string, unknown>) : {} };
  }

  /**
   * The settings changed by `change` and written from the revision just read, as a device writes them. Another device
   * writing in between is refused by the service (409); the settings are read again and `change` applied to theirs,
   * once. Settings are last-writer-wins as a whole object, so this reads, changes one thing and writes straight back.
   */
  async changePrefs(change: (prefs: Record<string, unknown>) => Record<string, unknown>): Promise<Record<string, unknown>> {
    for (let attempt = 0; ; attempt += 1) {
      const { rev, prefs } = await this.readPrefs();
      const next = change(structuredClone(prefs));
      const blob = await seal(await this.accountKey(), next, 'prefs');
      try {
        await this.call<{ rev: number }>('PUT', 'prefs', { base: rev, blob });
        return next;
      } catch (failure) {
        if (attempt === 0 && failure instanceof GlyphApiError && failure.status === 409) continue;
        throw failure;
      }
    }
  }

  /**
   * One notification of what was just written, to the account's own feed: `{ kind, ...details }` sealed under the
   * account key as `notification:<id>` - the id a short one, as the service asks (core/ids.ts `shortId`) - and posted
   * as the app posts its own (core/notifications/feed.ts `postSelfRow`; the service takes the same id twice as once).
   * Never throws: the write it tells of has landed, so a post that does not is written to stderr as a `glyph-mcp:`
   * line, one per failure, and the tool's answer is unchanged. A service without the route yet (docs/TEAMS.md,
   * "Not yet") says so in that line rather than reading as a fault.
   */
  async postNotification<K extends SelfKind>(kind: K, details: DetailsOf<K>): Promise<void> {
    const id = shortId();
    try {
      const payload = { kind, ...details } as Details;
      const blob = await seal(await this.accountKey(), payload, `notification:${id}`);
      await this.call<{ rev: number }>('POST', 'notifications', { id, kind, blob });
    } catch (failure) {
      process.stderr.write(`glyph-mcp: ${notYet(failure) ? `the sync service has no notifications yet; ${kind} not told` : `the ${kind} notification was not posted: ${failureText(failure)}`}\n`);
    }
  }
}
