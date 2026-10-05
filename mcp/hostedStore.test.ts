// @vitest-environment node
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { OAuthClientInformationFull } from '@modelcontextprotocol/sdk/shared/auth.js';
import { afterAll, describe, expect, it, vi } from 'vitest';
import type { GlyphAccount } from './glyph.ts';
import { newSealKey, open, seal, tokenId, unwrapWith, wrapFor } from './hostedSeal.ts';
import { CODE_MS, hostedStore, newToken } from './hostedStore.ts';

/**
 * What the hosted server keeps across a restart (mcp/hostedStore.ts) and how it is sealed (mcp/hostedSeal.ts), without
 * the server around it: a store, its file, and a second store made from that file as a restarted process makes one.
 * hosted.test.ts restarts the server itself, with Claude connected.
 */

const DAY = 24 * 60 * 60 * 1000;
const ACCOUNT_KEY = Buffer.alloc(32, 7).toString('base64url');
const dir = mkdtempSync(join(tmpdir(), 'glyph-mcp-store-'));
let files = 0;
const aFile = () => join(dir, `sessions-${++files}.json`);
const account = {} as GlyphAccount;

afterAll(() => rmSync(dir, { recursive: true, force: true }));

/** A store on a clock the test moves, with a registered client and a way to sign a person in to it. */
function aStore(file?: string, clock = { now: 1_800_000_000_000 }) {
  const store = hostedStore(() => clock.now, file);
  const register = () => store.clientsStore.registerClient!({ redirect_uris: ['http://localhost/cb'], client_name: 'Claude' } as OAuthClientInformationFull) as OAuthClientInformationFull;
  const signIn = (id: string, clientId: string, handle = 'matt') => store.signIn({ id, handle, clientId, account, accountKey: ACCOUNT_KEY, token: `sync-${id}`, client: { name: 'Claude' } });
  return { store, clock, register, signIn };
}

describe('the sealing', () => {
  it('opens what it sealed, and nothing with another key, another label, or a byte changed', () => {
    const key = newSealKey();
    const sealed = seal(key, 'the account key', 's1:key');
    expect(sealed).not.toContain('the account key');
    expect(open(key, sealed, 's1:key').toString()).toBe('the account key');
    expect(() => open(newSealKey(), sealed, 's1:key')).toThrow();
    expect(() => open(key, sealed, 's2:key')).toThrow();
    const bytes = Buffer.from(sealed, 'base64url');
    bytes[bytes.length - 1]! ^= 1;
    expect(() => open(key, bytes.toString('base64url'), 's1:key')).toThrow();
    // A fresh nonce each time: the same words sealed twice do not read alike.
    expect(seal(key, 'the account key', 's1:key')).not.toBe(sealed);
  });

  it('wraps a seal key for one token, and names that token one way', () => {
    const token = newToken();
    const key = newSealKey();
    const wrap = wrapFor(token, key, 's1:wrap');
    expect(unwrapWith(token, wrap, 's1:wrap').equals(key)).toBe(true);
    expect(() => unwrapWith(newToken(), wrap, 's1:wrap')).toThrow();
    expect(tokenId(token)).toBe(tokenId(token));
    expect(tokenId(token)).not.toBe(token);
    // The id is not the wrap key: knowing what the file calls a token does not open what the token wraps.
    expect(() => open(Buffer.from(tokenId(token), 'base64url'), wrap, 's1:wrap')).toThrow();
  });
});

describe('the store across a restart', () => {
  it('writes nothing without a file, and with one, a file only its owner reads, holding no key and no token', () => {
    const none = aStore();
    none.store.issue(none.signIn('s0', none.register().client_id), 'c');

    const file = aFile();
    const { store, register, signIn } = aStore(file);
    const client = register();
    const tokens = store.issue(signIn('s1', client.client_id), client.client_id);
    expect(statSync(file).mode & 0o777).toBe(0o600);
    const written = readFileSync(file, 'utf8');
    for (const secret of [ACCOUNT_KEY, 'sync-s1', tokens.access_token, tokens.refresh_token!]) expect(written).not.toContain(secret);
    expect(written).toContain(tokenId(tokens.access_token));
    // What it does say in the clear: who, which client, and when.
    expect(JSON.parse(written).sessions).toMatchObject([{ id: 's1', handle: 'matt', clientId: client.client_id, client: { name: 'Claude' } }]);
  });

  it('comes back with every session closed, and a session opens with its own tokens and no others', () => {
    const file = aFile();
    const before = aStore(file);
    const client = before.register();
    const one = before.store.issue(before.signIn('s1', client.client_id), client.client_id);
    const two = before.store.issue(before.signIn('s2', client.client_id, 'ada'), client.client_id);

    const { store } = aStore(file);
    expect(store.clientsStore.getClient(client.client_id)).toMatchObject({ client_name: 'Claude' });
    expect([...store.sessions.keys()]).toEqual(['s1', 's2']);
    const session = store.sessions.get('s1')!;
    expect(session.account).toBeUndefined();
    expect(session.sealKey).toBeUndefined();
    expect(() => store.issue(session, client.client_id)).toThrow('closed');

    // The other session's token, presented against this session's record: nothing.
    expect(() => store.unseal(session, two.access_token, store.access(two.access_token)!)).toThrow();
    expect(() => store.unseal(session, two.access_token, store.access(one.access_token)!)).toThrow();
    expect(session.sealKey).toBeUndefined();
    // Its own access token opens it, and so would its refresh token.
    expect(store.unseal(session, one.access_token, store.access(one.access_token)!)).toEqual({ accountKey: ACCOUNT_KEY, token: 'sync-s1' });
    expect(store.unseal(session, one.refresh_token!, store.refresh(one.refresh_token!)!)).toEqual({ accountKey: ACCOUNT_KEY, token: 'sync-s1' });
    // Open, it can be issued tokens again, and those open it after the next restart.
    const next = store.issue(session, client.client_id);
    const again = aStore(file).store;
    expect(again.unseal(again.sessions.get('s1')!, next.refresh_token!, again.refresh(next.refresh_token!)!).token).toBe('sync-s1');
  });

  it('keeps the sync service’s renewed token in the old one’s place', () => {
    const file = aFile();
    const before = aStore(file);
    const client = before.register();
    const session = before.signIn('s1', client.client_id);
    const tokens = before.store.issue(session, client.client_id);
    before.store.keepToken(session, 'sync-renewed');
    expect(readFileSync(file, 'utf8')).not.toContain('sync-renewed');
    const { store } = aStore(file);
    expect(store.unseal(store.sessions.get('s1')!, tokens.access_token, store.access(tokens.access_token)!).token).toBe('sync-renewed');
  });

  it('keeps the lifetimes across it: an hour, thirty days, a week unused, and a spent or ended token stays so', () => {
    const file = aFile();
    const clock = { now: 1_800_000_000_000 };
    const before = aStore(file, clock);
    const client = before.register();
    const kept = before.store.issue(before.signIn('s1', client.client_id), client.client_id);
    const spent = before.store.issue(before.store.sessions.get('s1')!, client.client_id);
    before.store.forget(spent.refresh_token!);
    const ended = before.store.issue(before.signIn('s2', client.client_id), client.client_id);
    before.store.endSession('s2');
    before.store.flush();

    // Two hours on: the access token has run out, the refresh token has not.
    clock.now += 2 * 60 * 60 * 1000;
    let store = aStore(file, clock).store;
    expect(store.access(kept.access_token)).toBeUndefined();
    expect(store.refresh(kept.refresh_token!)).toBeTruthy();
    expect(store.refresh(spent.refresh_token!)).toBeUndefined();
    expect(store.sessions.has('s2')).toBe(false);
    expect(store.refresh(ended.refresh_token!)).toBeUndefined();

    // Used on the sixth day, it is there on the twelfth; unused for a week after that, it is gone, tokens and all.
    clock.now += 6 * DAY;
    store.touch(store.sessions.get('s1')!);
    store.sweep();
    clock.now += 6 * DAY;
    store = aStore(file, clock).store;
    expect(store.sessions.has('s1')).toBe(true);
    clock.now += 2 * DAY;
    store = aStore(file, clock).store;
    expect(store.sessions.size).toBe(0);
    expect(store.refresh(kept.refresh_token!)).toBeUndefined();
    expect(JSON.parse(readFileSync(file, 'utf8'))).toMatchObject({ sessions: [], access: {}, refresh: {} });
  });

  it('forgets a client nobody is behind after thirty days, and not one a session is still its own', () => {
    const file = aFile();
    const clock = { now: 1_800_000_000_000 };
    const { store, register, signIn } = aStore(file, clock);
    const idle = register();
    const used = register();
    const session = signIn('s1', used.client_id);
    for (let day = 0; day < 31; day += 1) {
      clock.now += DAY;
      // In use: its refresh token traded for the next, as Claude does.
      store.issue(session, used.client_id);
      store.touch(session);
      store.sweep();
    }
    expect(store.clientsStore.getClient(idle.client_id)).toBeUndefined();
    expect(store.clientsStore.getClient(used.client_id)).toBeTruthy();
    expect(JSON.parse(readFileSync(file, 'utf8')).clients).toHaveLength(1);
  });

  it('does not sweep away a session whose code Claude has not traded yet', () => {
    const { store, clock, register, signIn } = aStore();
    const client = register();
    signIn('s1', client.client_id);
    store.codes.set('code', { clientId: client.client_id, codeChallenge: 'c', redirectUri: 'http://localhost/cb', sessionId: 's1', expiresAt: clock.now + CODE_MS });
    store.sweep();
    expect(store.sessions.has('s1')).toBe(true);
    // The code ran out untraded: nothing names the session, so it goes.
    clock.now += CODE_MS + 1;
    store.sweep();
    expect(store.sessions.has('s1')).toBe(false);
  });

  it('starts with nobody signed in, and says why, when the file cannot be read; and carries on when it cannot be written', () => {
    const said = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    try {
      const file = aFile();
      writeFileSync(file, '{"v":1,"clients":[{"cli');
      const { store, register, signIn } = aStore(file);
      expect(store.sessions.size).toBe(0);
      expect(String(said.mock.calls[0]![0])).toContain('could not be read, so everyone signs in again');
      // And it is a working store from there: the next sign-in is written over the wreck.
      const client = register();
      const tokens = store.issue(signIn('s1', client.client_id), client.client_id);
      expect(aStore(file).store.access(tokens.access_token)).toBeTruthy();

      said.mockClear();
      const nowhere = aStore(join(dir, 'no-such-directory', 'sessions.json'));
      const stays = nowhere.store.issue(nowhere.signIn('s1', nowhere.register().client_id), 'c');
      expect(nowhere.store.access(stays.access_token)).toBeTruthy();
      expect(String(said.mock.calls[0]![0])).toContain('could not be written');
    } finally {
      said.mockRestore();
    }
  });
});
