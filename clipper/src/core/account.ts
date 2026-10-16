import type { SignedIn } from '../../../tauri/src/app/core/account/account.ts';
import { ApiError, API_BASE, call } from '../../../tauri/src/app/core/account/api.ts';
import { derive, newDeviceKey, open, passwordSalt, publicKeyOf, ROUNDS, seal, signNonce, unwrap, type Bytes } from '../../../tauri/src/app/core/sync/crypto.ts';
import { sendFile, type FeedItem, type NotePayload } from '../../../tauri/src/app/core/sync/notes.ts';
import type { Note } from '../../../tauri/src/app/core/store.ts';
import type { Keeper, SessionInfo } from './keep.ts';

/**
 * The Ghost.md account as the clipper holds it: a device of the account, like a phone or the web app, made of the
 * web app's own code (tauri/src/app/core): the password split by `derive`, the login half sent to `login`, the
 * account key unwrapped here with the other half, every call through `call` (core/account/api.ts, whose base is the
 * build's `VITE_GLYPH_API`), each note sealed under the account key as `note:<id>` and put to the account's feed,
 * and each picture sealed and sent by the sync's own `sendFile` (core/sync/notes.ts). The service sees what it sees
 * from any device: sealed blobs, and the login half.
 *
 * It mirrors the connector's `GlyphAccount` (mcp/glyph.ts), which is the other client of the account outside the
 * app, with what a browser extension needs instead of a file: the session kept by a `Keeper` (core/keep.ts), and a
 * signing key registered only when the person asked to stay signed in, since a session that ends with the browser
 * never needs renewing without the password, and would otherwise add a device to the account at every sign-in.
 */

/** What the clipper calls itself on the account's list of devices. */
export const DEVICE_LABEL = 'Web clipper';

/** A note another device changed first: the service kept theirs. */
export class Conflict extends Error {
  constructor(readonly theirs: FeedItem | null) {
    super('Another device changed this note first.');
  }
}

export interface Deps {
  keeper: Keeper;
  fetcher?: typeof fetch;
  rounds?: number;
}

export class ClipperAccount {
  private constructor(
    private info: SessionInfo,
    private readonly key: CryptoKey,
    private readonly deps: Deps,
  ) {}

  /** The account the keeper holds, or null when the clipper is signed out. */
  static async kept(deps: Deps): Promise<ClipperAccount | null> {
    const held = await deps.keeper.load();
    return held ? new ClipperAccount(held.info, held.key, deps) : null;
  }

  /** In with the handle and password, as the app signs in (core/account/account.ts `signIn`). */
  static async signIn(handle: string, password: string, { stay, ...deps }: Deps & { stay: boolean }): Promise<ClipperAccount> {
    const { login, wrapKey } = await derive(password, passwordSalt(handle), deps.rounds ?? ROUNDS);
    const answer = await call<SignedIn>('POST', 'login', { fetcher: deps.fetcher, body: { handle: handle.trim(), loginSecret: login } });
    if (!answer.wrapped) throw new ApiError(500, 'The service answered without this account’s key.');
    // Readable once, so a session that ends with the browser can keep its bytes in memory (core/keep.ts); a session
    // that stays keeps a copy no script can read.
    const key = await unwrap(answer.wrapped, wrapKey, true).catch(() => {
      throw new ApiError(401, 'This account’s key would not open with that password.');
    });
    const info: SessionInfo = { v: 1, api: API_BASE, handle: answer.account.handle, accountId: answer.account.id, token: answer.token, stay };
    await deps.keeper.clear();
    if (stay) {
      const pair = await newDeviceKey();
      try {
        await call('POST', 'device', { token: answer.token, fetcher: deps.fetcher, body: { devicePublicKey: await publicKeyOf(pair), label: DEVICE_LABEL } });
        await deps.keeper.setDeviceKey(pair);
      } catch {
        // No signing key: the session still lasts as long as its token, a week, and then the password is asked again.
      }
    }
    await deps.keeper.save(info, key);
    const held = await deps.keeper.load();
    return new ClipperAccount(info, held?.key ?? key, deps);
  }

  get handle(): string {
    return this.info.handle;
  }

  get accountId(): number {
    return this.info.accountId;
  }

  get stays(): boolean {
    return this.info.stay;
  }

  /** Off this browser: the session and the keys. The notes it saved are the account's and stay. */
  async signOut(): Promise<void> {
    await this.deps.keeper.clear();
  }

  /**
   * The session renewed: by its token while that is good, then by the clipper's own signing key where it has one.
   * Neither, and the keeper is emptied: the popup asks for the password again.
   */
  async resume(): Promise<void> {
    const { token, handle } = this.info;
    try {
      const answer = await call<SignedIn>('POST', 'refresh', { token, fetcher: this.deps.fetcher });
      return await this.renewed(answer);
    } catch (failure) {
      if (!(failure instanceof ApiError) || failure.status !== 401) throw failure;
    }
    const pair = await this.deps.keeper.deviceKey();
    if (pair) {
      const { nonce } = await call<{ nonce: string }>('POST', 'login/challenge', { fetcher: this.deps.fetcher, body: { handle } });
      const signature = await signNonce(pair, nonce);
      const answer = await call<SignedIn>('POST', 'login/device', { fetcher: this.deps.fetcher, body: { handle, nonce, signature } }).catch(async (failure: unknown) => {
        if (failure instanceof ApiError && failure.status === 401) await this.deps.keeper.clear();
        throw failure;
      });
      return this.renewed(answer);
    }
    await this.deps.keeper.clear();
    throw new ApiError(401, 'Your session has ended. Sign in again.');
  }

  private async renewed(answer: SignedIn): Promise<void> {
    this.info = { ...this.info, token: answer.token, handle: answer.account.handle, accountId: answer.account.id };
    await this.deps.keeper.save(this.info);
  }

  /** A call as the account, renewed once on a lapsed token. */
  private async call<T>(method: string, path: string, body?: unknown, renewed = false): Promise<T> {
    try {
      return await call<T>(method, path, { token: this.info.token, body, fetcher: this.deps.fetcher });
    } catch (failure) {
      if (failure instanceof ApiError && failure.status === 401 && !renewed) {
        await this.resume();
        return this.call<T>(method, path, body, true);
      }
      throw failure;
    }
  }

  /** The account's feed of notes from `since`, a page at a time, each item as the service holds it (sealed). */
  async feed(since: number): Promise<{ rev: number; items: FeedItem[]; more: boolean }> {
    return this.call('GET', `notes?since=${since}`);
  }

  /** A note out of its feed item; null for a deletion. */
  async openNote(item: FeedItem): Promise<NotePayload | null> {
    if (item.deleted || !item.blob) return null;
    return open<NotePayload>(this.key, item.blob, `note:${item.id}`);
  }

  /**
   * A note written to the account from revision `base` (0 for a new one), sealed as the app seals one, with the
   * pictures its words show named beside it so every device fetches them. Answers the revision it now has; a write
   * another device beat is a `Conflict` carrying theirs.
   */
  async putNote(note: Note, images: readonly string[], base: number, recording?: string): Promise<number> {
    const payload: NotePayload = { v: 1, note, ...(recording ? { recording } : {}), ...(images.length ? { images: [...images] } : {}) };
    const blob = await seal(this.key, payload, `note:${note.id}`);
    try {
      return (await this.call<{ rev: number }>('PUT', `notes/${encodeURIComponent(note.id)}`, { base, blob })).rev;
    } catch (failure) {
      if (failure instanceof ApiError && failure.status === 409) throw new Conflict((failure.body as FeedItem | null) ?? null);
      throw failure;
    }
  }

  /** A picture sealed and sent as the app sends one (`sendFile`): `recordings/i-jpg-<stem>`, sealed as `file:<id>`. */
  async putPicture(name: string, bytes: Bytes, renewed = false): Promise<void> {
    try {
      await sendFile({ token: this.info.token, key: this.key, fetcher: this.deps.fetcher, files: { read: async () => null, write: async () => undefined }, state: { files: {} } }, 'image', name, bytes);
    } catch (failure) {
      if (failure instanceof ApiError && failure.status === 401 && !renewed) {
        await this.resume();
        return this.putPicture(name, bytes, true);
      }
      throw failure;
    }
  }

  /** The account's synced settings (core/sync/prefs.ts): one object sealed as `prefs`, and its revision. */
  async readPrefs(): Promise<{ rev: number; prefs: Record<string, unknown> }> {
    const { rev, blob } = await this.call<{ rev: number; blob: string | null }>('GET', 'prefs');
    const opened = blob ? await open<unknown>(this.key, blob, 'prefs') : null;
    return { rev, prefs: opened && typeof opened === 'object' && !Array.isArray(opened) ? (opened as Record<string, unknown>) : {} };
  }

  /**
   * The settings changed by `change` and written from the revision just read, every key kept as it came, as the
   * connector writes them (mcp/glyph.ts `changePrefs`). Another device writing in between is read again, once.
   */
  async changePrefs(change: (prefs: Record<string, unknown>) => Record<string, unknown>): Promise<void> {
    for (let attempt = 0; ; attempt += 1) {
      const { rev, prefs } = await this.readPrefs();
      const blob = await seal(this.key, change(structuredClone(prefs)), 'prefs');
      try {
        await this.call<{ rev: number }>('PUT', 'prefs', { base: rev, blob });
        return;
      } catch (failure) {
        if (attempt === 0 && failure instanceof ApiError && failure.status === 409) continue;
        throw failure;
      }
    }
  }
}
