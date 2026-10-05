// @vitest-environment node
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import type { Server } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { UnauthorizedError } from '@modelcontextprotocol/sdk/client/auth.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { toBase64Url } from '../src/app/core/sync/crypto.ts';
import { fakeService, FAST } from '../src/test/fakeService.ts';
import { freePort } from './freePort.ts';
import { hostedApp } from './hosted.ts';
import { aNote, asText, ClaudeMemory, completeSignIn, playSignInPage, readSignInPage, told } from './testKit.ts';

/**
 * The hosted server, connected to as Claude connects: the client library's own OAuth flow (discovery from the 401,
 * registration, the sign-in page, the code, the tokens), then the tools, against the sync service stood in for in
 * memory (src/test/fakeService.ts). The browser's part - the sign-in page's script - is played with the same crypto
 * by testKit.ts's playSignInPage; loginPage.test.ts runs the page's own. And the server restarted under Claude: stopped,
 * and made again from the file it kept (hostedStore.test.ts has the file's own tests).
 */

const CALLBACK = 'http://localhost:9999/callback';

/**
 * The hosted server on a loopback port of its own, over Matt's account on a fresh service in memory, on a clock the
 * test moves. With the steps a person and Claude take through it. `state` is the file it keeps its sessions in, and
 * `after` the server it is a restart of: over the same sync service, though on a port of its own, since a connection
 * the test's `fetch` kept open to the stopped one would be reset under the next request. Nothing Claude holds names
 * the port.
 */
async function hostedOnAPort(clock: { now: number }, { state, after }: { state?: string; after?: { service: Awaited<ReturnType<typeof fakeService>> } } = {}) {
  const service = after?.service ?? (await fakeService({ handle: 'matt', password: 'correct horse' }));
  if (!after) await service.deviceWrites(aNote('n1', '# Groceries\n\nWe need:\n- eggs\n- milk'));
  // A port nobody is using, so the app can be made with its real address as the issuer.
  const port = await freePort();
  const origin = `http://127.0.0.1:${port}`;
  const url = new URL(`${origin}/glyph/api/mcp`);
  const hosted = hostedApp({ issuer: url.href, api: 'https://fake.test/glyph/api', apiPublic: 'https://fake.test/glyph/api', fetcher: service.fetcher, rateLimit: false, now: () => clock.now, state });
  const server = await new Promise<Server>((resolve) => {
    const listening = hosted.app.listen(port, '127.0.0.1', () => resolve(listening));
  });

  /** The sign-in page Claude sent the person to, as the server wrote it: found, and saying where the key is kept. */
  const signInPage = async (authorizeUrl: URL) => {
    const page = await readSignInPage(authorizeUrl);
    expect(page.status).toBe(200);
    expect(page.html).toContain('in memory, and on disk only sealed');
    expect(page.request && page.base).toBeTruthy();
    return page;
  };

  /** The person signing in on the page, its script played by the kit, and where the page sends them back to. */
  const signInOnThePage = async (authorizeUrl: URL, handle = 'matt', password = 'correct horse'): Promise<URL> => {
    const done = await playSignInPage(await signInPage(authorizeUrl), { handle, password, rounds: FAST, fetcher: service.fetcher });
    expect(done.status, done.body.error).toBe(200);
    return new URL(done.body.redirect!);
  };

  /** Claude's first contact: refused, registered, and sent to sign in. The memory holds where. */
  const firstContact = async () => {
    const memory = new ClaudeMemory(CALLBACK);
    const client = new Client({ name: 'claude', version: '0' });
    // The transport that was refused is the one that knows, from the refusal, where the sign-in is.
    const transport = new StreamableHTTPClientTransport(url, { authProvider: memory });
    await expect(client.connect(transport)).rejects.toBeInstanceOf(UnauthorizedError);
    return { memory, client, transport };
  };

  /** Claude connected all the way: first contact, the person's sign-in, the code into tokens, and connected again. */
  const connectAsClaude = async () => {
    const { memory, client, transport } = await firstContact();
    const back = await signInOnThePage(memory.sentTo!);
    await transport.finishAuth(back.searchParams.get('code')!);
    await client.connect(new StreamableHTTPClientTransport(url, { authProvider: memory }));
    return { memory, client };
  };

  /** Claude back after a restart, with what it held before: connected without the person, or refused. */
  const reconnect = async (memory: ClaudeMemory) => {
    const client = new Client({ name: 'claude', version: '0' });
    await client.connect(new StreamableHTTPClientTransport(url, { authProvider: memory }));
    return client;
  };

  const close = () => new Promise<void>((resolve) => server.close(() => resolve()));
  return { service, origin, url, hosted, signInPage, signInOnThePage, firstContact, connectAsClaude, reconnect, close };
}

describe('Claude connecting to the hosted server', () => {
  const clock = { now: 1_800_000_000_000 };
  let at: Awaited<ReturnType<typeof hostedOnAPort>>;

  beforeAll(async () => {
    at = await hostedOnAPort(clock);
  });

  afterAll(async () => {
    await at?.close();
  });

  it('is found from the 401, registers Claude, sends the person to sign in, and then serves the tools', async () => {
    const { url, hosted, service } = at;
    const memory = new ClaudeMemory(CALLBACK);
    let transport = new StreamableHTTPClientTransport(url, { authProvider: memory });
    const client = new Client({ name: 'claude', version: '0' });
    // First contact: refused, and the client library works out where to sign in and registers itself.
    await expect(client.connect(transport)).rejects.toBeInstanceOf(UnauthorizedError);
    expect(memory.info?.client_id).toBeTruthy();
    expect(memory.sentTo?.pathname).toBe('/glyph/api/mcp/authorize');
    expect(memory.sentTo?.searchParams.get('code_challenge_method')).toBe('S256');

    // The person signs in on the page; the page sends them back to Claude with a code.
    const back = await at.signInOnThePage(memory.sentTo!);
    expect(back.origin + back.pathname).toBe(CALLBACK);
    const code = back.searchParams.get('code')!;
    expect(code).toBeTruthy();
    expect(back.searchParams.get('state')).toBe(memory.sentTo!.searchParams.get('state'));
    expect(hosted.sessions.size).toBe(1);

    // The code becomes tokens, and the connection is made.
    await transport.finishAuth(code);
    expect(memory.saved?.access_token).toBeTruthy();
    expect(memory.saved?.refresh_token).toBeTruthy();
    transport = new StreamableHTTPClientTransport(url, { authProvider: memory });
    await client.connect(transport);
    const { tools } = await client.listTools();
    expect(tools.map((t) => t.name)).toContain('append_to_note');

    // The tools work on the account, through the key the page handed over. Connecting made the "Claude rules" note, so
    // it is there, newest, beside the account's own notes (mcp/server.ts ensureRulesNote).
    const listed = JSON.parse(asText(await client.callTool({ name: 'list_notes', arguments: {} }))) as { notes: { title: string }[] };
    expect(listed.notes.map((n) => n.title)).toEqual(['Claude rules', 'Groceries']);
    const added = JSON.parse(asText(await client.callTool({ name: 'append_to_note', arguments: { title: 'Groceries', text: 'bread', as: 'item' } }))) as { added: string[] };
    expect(added.added).toEqual(['- Bread']);
    // Written with Claude, so Claude is among its authors, after the account's own (core/authors.ts): the name its app
    // connected with, remembered from the connect though each request comes to a fresh server.
    expect((await service.stored('n1'))?.note.body).toBe('---\nauthors: matt, Claude\n---\n# Groceries\n\nWe need:\n- eggs\n- milk\n- Bread');
    // And the account is told of both writes (docs/TEAMS.md), sealed under the key the page handed over, with that
    // remembered name as the writer: the rules note made on connect, then the words added.
    const rows = await told(service);
    expect(rows.map((r) => [r.kind, r.details.kind])).toEqual([
      ['note-created', 'note-created'],
      ['note-appended', 'note-appended'],
    ]);
    expect(rows[0]!.details).toMatchObject({ title: 'Claude rules', by: 'Claude' });
    expect(rows[1]!.details).toEqual({ kind: 'note-appended', noteId: 'n1', title: 'Groceries', by: 'Claude', lines: 1, first: '- Bread' });
    expect(rows.every((r) => /^[A-Za-z0-9_-]{22}$/.test(r.id))).toBe(true);

    // An hour on, the access token has run out: the library refreshes it by itself and carries on.
    clock.now += 61 * 60 * 1000;
    const status = JSON.parse(asText(await client.callTool({ name: 'account_status', arguments: {} }))) as { handle: string; notes: number };
    expect(status).toMatchObject({ handle: 'matt', notes: 2 });
    expect(memory.saved?.access_token).toBeTruthy();
    await client.close();
  });

  it('refuses a token it never issued, a stale sign-in page, and a key that is not one', async () => {
    const { origin } = at;
    const refused = await fetch(`${origin}/glyph/api/mcp`, { method: 'POST', headers: { Authorization: 'Bearer nope', 'Content-Type': 'application/json' }, body: '{}' });
    expect(refused.status).toBe(401);
    expect(refused.headers.get('www-authenticate')).toContain(`resource_metadata="${origin}/glyph/api/mcp/.well-known/oauth-protected-resource"`);
    const stale = await fetch(`${origin}/glyph/api/mcp/authorize/complete`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ request: 'gone', handle: 'matt', token: 't', accountKey: 'x' }) });
    expect(stale.status).toBe(400);
    const metadata = (await (await fetch(`${origin}/glyph/api/mcp/.well-known/openid-configuration`)).json()) as { issuer: string; token_endpoint: string; code_challenge_methods_supported: string[] };
    expect(metadata.issuer).toBe(`${origin}/glyph/api/mcp`);
    expect(metadata.token_endpoint).toBe(`${origin}/glyph/api/mcp/token`);
    expect(metadata.code_challenge_methods_supported).toEqual(['S256']);
    const noGet = await fetch(`${origin}/glyph/api/mcp`);
    expect(noGet.status).toBe(405);
  });

  it('ends a session, key and all, when nobody has used it for a week', async () => {
    const { hosted } = at;
    expect(hosted.sessions.size).toBe(1);
    clock.now += 8 * 24 * 60 * 60 * 1000;
    hosted.sweep();
    expect(hosted.sessions.size).toBe(0);
  });

  it('counts the connections an account has, and one of them can end them all', async () => {
    const { hosted } = at;
    // Two Claudes on Matt's account: a second computer, or a second Claude account.
    const { client: one } = await at.connectAsClaude();
    const { client: two } = await at.connectAsClaude();
    const mine = () => [...hosted.sessions.values()].filter((s) => s.handle === 'matt').length;
    expect(mine()).toBeGreaterThanOrEqual(2);
    const status = JSON.parse(asText(await one.callTool({ name: 'account_status', arguments: {} }))) as { connections: number };
    expect(status.connections).toBe(mine());

    // One of them signs out everywhere: every session for the handle goes, the other's token with it.
    const ended = JSON.parse(asText(await two.callTool({ name: 'sign_out_everywhere', arguments: {} }))) as { endedConnections: number };
    expect(ended.endedConnections).toBe(status.connections);
    expect(mine()).toBe(0);
    await expect(one.callTool({ name: 'account_status', arguments: {} })).rejects.toBeTruthy();
    await one.close().catch(() => undefined);
    await two.close().catch(() => undefined);
  });
});

describe('what ends a sign-in, and what the server refuses', () => {
  const clock = { now: 1_800_000_000_000 };
  let at: Awaited<ReturnType<typeof hostedOnAPort>>;

  beforeAll(async () => {
    at = await hostedOnAPort(clock);
  });

  afterAll(async () => {
    await at?.close();
  });

  /** A token asked for by hand, as a client library would: the answer's status and its error. */
  const token = async (form: Record<string, string>) => {
    const answer = await fetch(`${at.url.href}/token`, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(form) });
    return { status: answer.status, body: (await answer.json()) as { error?: string; access_token?: string; refresh_token?: string } };
  };

  it('sends a person who cancels back to Claude, saying they did not sign in, with Claude’s own state', async () => {
    const { memory } = await at.firstContact();
    const deny = new URL((await at.signInPage(memory.sentTo!)).deny);
    expect(deny.origin + deny.pathname).toBe(CALLBACK);
    expect(deny.searchParams.get('error')).toBe('access_denied');
    expect(deny.searchParams.get('error_description')).toBe('The person did not sign in.');
    expect(deny.searchParams.get('state')).toBe(memory.sentTo!.searchParams.get('state'));
  });

  it('takes a code once, for the address it was made for, and with the verifier it was made with', async () => {
    const { memory } = await at.firstContact();
    const code = (await at.signInOnThePage(memory.sentTo!)).searchParams.get('code')!;
    const exchange = { grant_type: 'authorization_code', client_id: memory.info!.client_id, code, code_verifier: memory.verifier, redirect_uri: CALLBACK };
    expect(await token({ ...exchange, code_verifier: 'not-the-one-it-was-made-with-not-the-one-it-was-made-with' })).toMatchObject({ status: 400, body: { error: 'invalid_grant' } });
    const good = await token(exchange);
    expect(good.status).toBe(200);
    expect(good.body.access_token).toBeTruthy();
    // Used, it is gone.
    expect(await token(exchange)).toMatchObject({ status: 400, body: { error: 'invalid_grant' } });

    const again = await at.firstContact();
    const second = (await at.signInOnThePage(again.memory.sentTo!)).searchParams.get('code')!;
    const elsewhere = await token({ grant_type: 'authorization_code', client_id: again.memory.info!.client_id, code: second, code_verifier: again.memory.verifier, redirect_uri: 'http://localhost:9999/elsewhere' });
    expect(elsewhere).toMatchObject({ status: 400, body: { error: 'invalid_grant' } });
  });

  it('ends the session, key and all, when Claude is disconnected, and its tokens stop working', async () => {
    const { memory, client } = await at.connectAsClaude();
    const before = at.hosted.sessions.size;
    const revoked = await fetch(`${at.url.href}/revoke`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ token: memory.saved!.refresh_token!, client_id: memory.info!.client_id }),
    });
    expect(revoked.status).toBe(200);
    expect(at.hosted.sessions.size).toBe(before - 1);
    const refused = await fetch(at.url, { method: 'POST', headers: { Authorization: `Bearer ${memory.saved!.access_token}`, 'Content-Type': 'application/json' }, body: '{}' });
    expect(refused.status).toBe(401);
    await client.close().catch(() => undefined);
  });

  it('turns away a key that is not 32 bytes, and a token the sync service does not know, and makes no session', async () => {
    const said = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    try {
      const sessions = at.hosted.sessions.size;
      const { memory } = await at.firstContact();
      const page = await at.signInPage(memory.sentTo!);
      const short = await completeSignIn(page, { handle: 'matt', token: at.service.signedIn(), accountKey: toBase64Url(new Uint8Array(16).fill(7)) });
      expect(short).toEqual({ status: 400, body: { error: 'That is not an account key.' } });
      // The reason goes to the journal, for whoever runs the server; the page says what the person can act on.
      expect(said.mock.calls.map((c) => String(c[0]))).toContain('glyph-mcp: the account key was refused: not 32 bytes\n');
      const unknown = await completeSignIn(page, { handle: 'matt', token: 'tok-never', accountKey: toBase64Url(new Uint8Array(32).fill(7)) });
      expect(unknown.status).toBe(401);
      expect(unknown.body.error).toContain('Sign in again');
      expect(at.hosted.sessions.size).toBe(sessions);
    } finally {
      said.mockRestore();
    }
  });

  it('ends a session the sync service will no longer renew, at the next request, and Claude is asked to sign in again', async () => {
    const { client } = await at.connectAsClaude();
    const before = at.hosted.sessions.size;
    // The service forgets every token: the hosted session has no device key to renew with, so it has lapsed.
    at.service.expireAllTokens();
    const lapsed = await client.callTool({ name: 'list_notes', arguments: {} });
    expect(lapsed.isError).toBe(true);
    expect(asText(lapsed)).toContain('This session has lapsed');
    // The next request finds the session lapsed and ends it; refreshing cannot bring it back.
    await expect(client.callTool({ name: 'list_notes', arguments: {} })).rejects.toBeTruthy();
    expect(at.hosted.sessions.size).toBe(before - 1);
    await client.close().catch(() => undefined);
  });
});

describe('a restart of the server', () => {
  const dir = mkdtempSync(join(tmpdir(), 'glyph-mcp-hosted-'));
  let files = 0;
  const aFile = () => join(dir, `sessions-${++files}.json`);
  const bearer = (at: { url: URL }, token: string) => fetch(at.url, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: '{}' });

  afterAll(() => rmSync(dir, { recursive: true, force: true }));

  it('signs nobody out: the session comes back closed, and the tokens Claude holds open it, first the access token and then the refresh token', async () => {
    const clock = { now: 1_800_000_000_000 };
    const state = aFile();
    // What the page hands the server, caught on its way, to look for in the file afterwards.
    const posted = vi.spyOn(globalThis, 'fetch');
    const first = await hostedOnAPort(clock, { state });
    const { memory, client } = await first.connectAsClaude();
    const handed = JSON.parse(posted.mock.calls.map((c) => c[1]?.body).find((b): b is string => typeof b === 'string' && b.includes('accountKey'))!) as { accountKey: string; token: string };
    posted.mockRestore();
    await client.callTool({ name: 'append_to_note', arguments: { title: 'Groceries', text: 'bread', as: 'item' } });
    await client.close();
    await first.close();

    // The file: who is signed in, and no key and no token of anyone's.
    const written = readFileSync(state, 'utf8');
    expect(handed.accountKey).toHaveLength(43);
    for (const secret of [handed.accountKey, handed.token, memory.saved!.access_token, memory.saved!.refresh_token!]) expect(written).not.toContain(secret);
    expect((JSON.parse(written) as { sessions: { handle: string }[] }).sessions.map((s) => s.handle)).toEqual(['matt']);

    // Restarted. The session is there, closed: no account, nothing that opens one.
    const second = await hostedOnAPort(clock, { state, after: first });
    const kept = () => [...second.hosted.sessions.values()][0]!;
    expect(second.hosted.sessions.size).toBe(1);
    expect(kept().account).toBeUndefined();
    expect(kept().sealKey).toBeUndefined();
    // Claude carries on with the access token it holds, and is not sent to the sign-in page.
    const sentTo = memory.sentTo;
    const access = memory.saved!.access_token;
    const again = await second.reconnect(memory);
    const added = JSON.parse(asText(await again.callTool({ name: 'append_to_note', arguments: { title: 'Groceries', text: 'jam', as: 'item' } }))) as { added: string[] };
    expect(added.added).toEqual(['- Jam']);
    expect((await second.service.stored('n1'))?.note.body).toBe('---\nauthors: matt, Claude\n---\n# Groceries\n\nWe need:\n- eggs\n- milk\n- Bread\n- Jam');
    expect(kept().account).toBeDefined();
    expect(memory.sentTo).toBe(sentTo);
    expect(memory.saved!.access_token).toBe(access);
    await again.close();
    await second.close();

    // Restarted again, more than an hour on: the access token has run out, and the refresh token is what opens it.
    clock.now += 61 * 60 * 1000;
    const third = await hostedOnAPort(clock, { state, after: first });
    expect((await bearer(third, access)).status).toBe(401);
    const later = await third.reconnect(memory);
    const status = JSON.parse(asText(await later.callTool({ name: 'account_status', arguments: {} }))) as { handle: string; connections: number };
    expect(status).toMatchObject({ handle: 'matt', connections: 1 });
    expect(memory.sentTo).toBe(sentTo);
    expect(memory.saved!.access_token).not.toBe(access);
    await later.close();
    await third.close();
  });

  it('opens one account for a session, however many requests arrive for it at once', async () => {
    const clock = { now: 1_800_000_000_000 };
    const state = aFile();
    const first = await hostedOnAPort(clock, { state });
    const { memory, client } = await first.connectAsClaude();
    await client.close();
    await first.close();
    const second = await hostedOnAPort(clock, { state, after: first });
    const list = () =>
      fetch(second.url, {
        method: 'POST',
        headers: { Authorization: `Bearer ${memory.saved!.access_token}`, 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }),
      });
    const answers = await Promise.all([list(), list(), list()]);
    expect(answers.map((a) => a.status)).toEqual([200, 200, 200]);
    expect(second.hosted.sessions.size).toBe(1);
    await second.close();
  });

  it('keeps what ended ended: a disconnected Claude, everyone signed out everywhere, and a week unused', async () => {
    const clock = { now: 1_800_000_000_000 };
    const state = aFile();
    const first = await hostedOnAPort(clock, { state });
    const gone = await first.connectAsClaude();
    const one = await first.connectAsClaude();
    const two = await first.connectAsClaude();
    const revoked = await fetch(`${first.url.href}/revoke`, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ token: gone.memory.saved!.refresh_token!, client_id: gone.memory.info!.client_id }) });
    expect(revoked.status).toBe(200);
    for (const { client } of [gone, one, two]) await client.close().catch(() => undefined);
    await first.close();

    const second = await hostedOnAPort(clock, { state, after: first });
    expect(second.hosted.sessions.size).toBe(2);
    expect((await bearer(second, gone.memory.saved!.access_token)).status).toBe(401);
    await expect(second.reconnect(gone.memory)).rejects.toThrow('That refresh token is not one of ours');
    // One of the two left signs out everywhere: the other goes with it, though nothing has opened it since the restart.
    const back = await second.reconnect(one.memory);
    const ended = JSON.parse(asText(await back.callTool({ name: 'sign_out_everywhere', arguments: {} }))) as { endedConnections: number };
    expect(ended.endedConnections).toBe(2);
    await back.close().catch(() => undefined);
    await second.close();
    const third = await hostedOnAPort(clock, { state, after: first });
    expect(third.hosted.sessions.size).toBe(0);
    expect((await bearer(third, two.memory.saved!.access_token)).status).toBe(401);

    // And a session nobody used for a week is over, though the server was down for some of it.
    const idle = await third.connectAsClaude();
    await idle.client.close();
    await third.close();
    clock.now += 8 * 24 * 60 * 60 * 1000;
    const fourth = await hostedOnAPort(clock, { state, after: first });
    expect(fourth.hosted.sessions.size).toBe(0);
    await expect(fourth.reconnect(idle.memory)).rejects.toThrow('That refresh token is not one of ours');
    await fourth.close();
  });

  it('ends a session whose file was changed, and says so, and signs everyone out when there is no file', async () => {
    const clock = { now: 1_800_000_000_000 };
    const state = aFile();
    const first = await hostedOnAPort(clock, { state });
    const { memory, client } = await first.connectAsClaude();
    await client.close();
    await first.close();
    // Another session's sealed key in this one's place, as someone with the disk might try: it does not open.
    const kept = JSON.parse(readFileSync(state, 'utf8')) as { sessions: { sealedKey: string; sealedToken: string }[] };
    kept.sessions[0]!.sealedKey = kept.sessions[0]!.sealedToken;
    writeFileSync(state, JSON.stringify(kept));
    const said = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    try {
      const second = await hostedOnAPort(clock, { state, after: first });
      expect(second.hosted.sessions.size).toBe(1);
      expect((await bearer(second, memory.saved!.access_token)).status).toBe(401);
      expect(second.hosted.sessions.size).toBe(0);
      expect(said.mock.calls.map((c) => String(c[0])).join('')).toContain('glyph-mcp: a kept session would not open');
      await second.close();
    } finally {
      said.mockRestore();
    }

    // With no file, as it was before: memory only, and a restart is everyone signing in again.
    const plain = await hostedOnAPort(clock);
    const there = await plain.connectAsClaude();
    await there.client.close();
    await plain.close();
    const restarted = await hostedOnAPort(clock, { after: plain });
    expect(restarted.hosted.sessions.size).toBe(0);
    // Not even the client Claude registered as is known: what claude.ai reported as "connection invalidated".
    await expect(restarted.reconnect(there.memory)).rejects.toThrow('Invalid client_id');
    await restarted.close();
  });
});
