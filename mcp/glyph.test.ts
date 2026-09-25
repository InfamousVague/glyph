// @vitest-environment node
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { describe, expect, it, vi } from 'vitest';
import { imageNames } from '../src/app/core/imageRefs.ts';
import { noteTitle } from '../src/app/core/noteTitle.ts';
import { toBase64Url } from '../src/app/core/sync/crypto.ts';
import type { Note } from '../src/app/core/store.ts';
import { fakeService, FAST } from '../src/test/fakeService.ts';
import { makeNote } from '../src/test/notes.ts';
import { Conflict, GlyphAccount, GlyphApiError, type StoredSession } from './glyph.ts';
import { buildServer } from './server.ts';

/**
 * The client against a sync service stood in for in memory: the same routes, revisions and refusals as
 * server/src/sync.rs and accounts.rs, so every rule the client lives by is tried without a server. The end-to-end
 * test (mcp.e2e.test.ts) tries the same against the real one.
 */

const API = 'https://fake.test/glyph/api';

const aNote = (id: string, body: string): Note => makeNote(id, body, { createdAt: 1_700_000_000_000, updatedAt: 1_700_000_000_000, source: 'capture', starred: false, archivedAt: null });

describe('signing in from outside the app', () => {
  it('derives the password the way the app does and comes away with the account key and a device key', async () => {
    const service = await fakeService({ handle: 'matt', password: 'correct horse' });
    const session = await GlyphAccount.signIn(API, 'matt', 'correct horse', { rounds: FAST, fetcher: service.fetcher });
    expect(session.handle).toBe('matt');
    expect(session.accountId).toBe(7);
    expect(session.token).toMatch(/^tok-/);
    expect(session.deviceKey?.kty).toBe('OKP');
    expect(service.calls).toEqual(['POST login', 'POST device']);
    // The key is the account's: a note another device sealed opens with it.
    await service.deviceWrites(aNote('n1', '# Groceries\n\n- eggs'));
    const account = new GlyphAccount(session, { fetcher: service.fetcher });
    const [note] = await account.list();
    expect(note?.note.body).toBe('# Groceries\n\n- eggs');
    expect(note?.rev).toBe(1);
  });

  it('says so on the wrong password, without leaking which half was wrong', async () => {
    const service = await fakeService({ handle: 'matt', password: 'correct horse' });
    await expect(GlyphAccount.signIn(API, 'matt', 'wrong horse', { rounds: FAST, fetcher: service.fetcher })).rejects.toThrow(GlyphApiError);
  });
});

describe('the session between runs', () => {
  async function signedIn() {
    const service = await fakeService({ handle: 'matt', password: 'correct horse' });
    const session = await GlyphAccount.signIn(API, 'matt', 'correct horse', { rounds: FAST, fetcher: service.fetcher });
    const saved: StoredSession[] = [];
    const account = new GlyphAccount(session, { fetcher: service.fetcher, save: (s) => saved.push(s) });
    return { service, account, saved, session };
  }

  it('renews a lapsed token with its own key, and keeps the new one', async () => {
    const { service, account, saved, session } = await signedIn();
    service.expireAllTokens();
    await account.resume();
    expect(saved).toHaveLength(1);
    expect(saved[0]?.token).not.toBe(session.token);
    expect(service.calls.slice(-3)).toEqual(['POST refresh', 'POST login/challenge', 'POST login/device']);
    // And works: a call with the renewed token.
    expect(await account.list()).toEqual([]);
  });

  it('renews once in the middle of a call, so a long-running server never notices a token lapsing', async () => {
    const { service, account } = await signedIn();
    await service.deviceWrites(aNote('n1', 'Hello'));
    service.expireAllTokens();
    const notes = await account.list();
    expect(notes.map((r) => r.note.body)).toEqual(['Hello']);
  });

  // The client's own words, which name the way back (`login`), and the `lapsed` hook the hosted server marks a sign-in
  // over by (hosted.ts). The service's own refusal of a lapsed token says "Sign in again" too, so a looser match would
  // pass a raw 401 handed straight through.
  it('asks for the password again when it has no device key', async () => {
    const { service, session } = await signedIn();
    const lapsed = vi.fn();
    const account = new GlyphAccount({ ...session, deviceKey: null }, { fetcher: service.fetcher, lapsed });
    service.expireAllTokens();
    await expect(account.list()).rejects.toThrow('This session has lapsed. Sign in again with `login`.');
    expect(lapsed).toHaveBeenCalledOnce();
    // No key to answer a challenge with, so none is asked for.
    expect(service.calls.slice(-2)).toEqual(['GET notes', 'POST refresh']);
  });

  it('asks for the password again when the account no longer knows its device key', async () => {
    const { service, session } = await signedIn();
    // A key the account never registered, as for a client whose device the account has since dropped.
    const stranger = (await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify'])) as CryptoKeyPair;
    const lapsed = vi.fn();
    const account = new GlyphAccount({ ...session, deviceKey: await crypto.subtle.exportKey('jwk', stranger.privateKey) }, { fetcher: service.fetcher, lapsed });
    service.expireAllTokens();
    await expect(account.list()).rejects.toThrow('This session has lapsed and could not be renewed. Sign in again with `login`.');
    expect(lapsed).toHaveBeenCalledOnce();
    expect(service.calls.slice(-3)).toEqual(['POST refresh', 'POST login/challenge', 'POST login/device']);
  });
});

describe('reading and writing notes', () => {
  async function ready() {
    const service = await fakeService({ handle: 'matt', password: 'correct horse' });
    const session = await GlyphAccount.signIn(API, 'matt', 'correct horse', { rounds: FAST, fetcher: service.fetcher });
    const account = new GlyphAccount(session, { fetcher: service.fetcher });
    return { service, account };
  }

  it('lists what the account holds, newest change first, and follows the feed', async () => {
    const { service, account } = await ready();
    await service.deviceWrites({ ...aNote('a', '# A'), updatedAt: 1 });
    await service.deviceWrites({ ...aNote('b', '# B'), updatedAt: 2 });
    expect((await account.list()).map((r) => noteTitle(r.note.body))).toEqual(['B', 'A']);
    await service.deviceWrites({ ...aNote('a', '# A again'), updatedAt: 3 });
    await account.pull();
    expect((await account.list()).map((r) => noteTitle(r.note.body))).toEqual(['A again', 'B']);
    expect(await account.byTitle('b')).toMatchObject({ note: { id: 'b' } });
  });

  it('makes a note the app can open, and sends it from nothing', async () => {
    const { service, account } = await ready();
    const made = await account.create('# From Claude\n\n- [ ] Book the ferry', { pinned: true });
    expect(made.rev).toBe(1);
    const stored = await service.stored(made.note.id);
    expect(stored?.v).toBe(1);
    expect(stored?.note).toMatchObject({ body: '# From Claude\n\n- [ ] Book the ferry', source: 'editor', starred: true, archivedAt: null });
    expect(stored?.note.createdAt).toBe(stored?.note.updatedAt);
    expect(stored?.recording).toBeUndefined();
    expect(stored?.images).toBeUndefined();
  });

  it('edits from the revision it read, keeping what the note carried', async () => {
    const { service, account } = await ready();
    const rev = await service.deviceWrites({ ...aNote('a', '# Trip\n\nWe leave Friday.'), starred: true, path: 'Inbox/Trip.md', recordingMs: 12_000, formatted: 'old', formattedFor: 3 }, { recording: 'abc123', images: ['sea.jpg', 'gone.png'] });
    const edited = await account.edit('a', (note) => ({ ...note, body: '# Trip\n\nWe leave Friday.\n\n![](image/sea.jpg)' }));
    expect(edited.rev).toBe(rev + 1);
    const stored = await service.stored('a');
    expect(stored?.note).toMatchObject({ body: '# Trip\n\nWe leave Friday.\n\n![](image/sea.jpg)', starred: true, path: 'Inbox/Trip.md', recordingMs: 12_000, formatted: null, formattedFor: null });
    expect(stored?.note.updatedAt).toBeGreaterThan(1_700_000_000_000);
    expect(stored?.note.createdAt).toBe(1_700_000_000_000);
    expect(stored?.recording).toBe('abc123');
    // Only the pictures the body still names go back: nothing is claimed that the body no longer shows.
    expect(stored?.images).toEqual(['sea.jpg']);
  });

  it('names a picture the words newly show, so the devices fetch it (Matt: the HelloTrade chapters had none named)', async () => {
    const { service, account } = await ready();
    await service.deviceWrites(aNote('b', '# Orders'));
    await account.edit('b', (note) => ({ ...note, body: '# Orders\n\n![The ticket](image/ticket.jpg)\n\n![](image/fill.png)' }));
    expect((await service.stored('b'))?.images).toEqual(['ticket.jpg', 'fill.png']);
    const made = await account.create('# New\n\n![](image/new.jpg)');
    expect((await service.stored(made.note.id))?.images).toEqual(['new.jpg']);
  });

  it('never writes over what another device wrote first: the conflict carries their note', async () => {
    const { service, account } = await ready();
    await service.deviceWrites(aNote('a', 'Mine, read at rev 1'));
    await account.list();
    await service.deviceWrites(aNote('a', 'Theirs, at rev 2'));
    const failure = await account.edit('a', (note) => ({ ...note, body: 'Mine, written blind' })).catch((e: unknown) => e);
    expect(failure).toBeInstanceOf(Conflict);
    expect((failure as Conflict).theirs?.note.body).toBe('Theirs, at rev 2');
    // The service still has theirs, and the client now reads theirs.
    expect((await service.stored('a'))?.note.body).toBe('Theirs, at rev 2');
    expect((await account.get('a'))?.note.body).toBe('Theirs, at rev 2');
    // Read again, the edit goes through.
    const edited = await account.edit('a', (note) => ({ ...note, body: `${note.body}\n\nAnd mine.` }));
    expect(edited.note.body).toBe('Theirs, at rev 2\n\nAnd mine.');
  });
});

/**
 * The server titles notes and names their pictures with the app's own code (core/noteTitle.ts, core/imageRefs.ts).
 * It used to keep copies, and the title's drifted: it took any block between two fences as front matter, so a note
 * that opens with a rule, some words and another rule was "---" in the app's list and "Real title" to Claude, who
 * could then find it by a name the person had never seen. These pin the app's answer through the tools.
 */
describe('titles and pictures, read as the app reads them', () => {
  const asText = (result: Awaited<ReturnType<Client['callTool']>>) => (result.content as { text?: string }[])[0]?.text ?? '';

  async function connected() {
    const service = await fakeService({ handle: 'matt', password: 'correct horse' });
    const session = await GlyphAccount.signIn(API, 'matt', 'correct horse', { rounds: FAST, fetcher: service.fetcher });
    const account = new GlyphAccount(session, { fetcher: service.fetcher });
    const client = new Client({ name: 'claude', version: '0' });
    const [ours, theirs] = InMemoryTransport.createLinkedPair();
    await Promise.all([buildServer(account).connect(theirs), client.connect(ours)]);
    return { service, account, client };
  }

  it('names a note in list_notes and read_note what the app’s list names it, and by nothing else', async () => {
    const { service, account, client } = await connected();
    const ruled = '---\nSome words here\n---\nReal title';
    await service.deviceWrites({ ...aNote('r', ruled), updatedAt: 2 });
    await service.deviceWrites({ ...aNote('f', '---\ntitle: "Front"\nbook: true\n---\n# Front'), updatedAt: 1 });
    expect(noteTitle(ruled)).toBe('---');

    const listed = JSON.parse(asText(await client.callTool({ name: 'list_notes', arguments: {} }))) as { notes: { id: string; title: string }[] };
    expect(listed.notes.map((n) => [n.id, n.title])).toEqual([
      ['r', '---'],
      ['f', 'Front'],
    ]);
    const missing = await client.callTool({ name: 'read_note', arguments: { title: 'Real title' } });
    expect(missing.isError).toBe(true);
    expect(await account.byTitle('Real title')).toBeNull();
    expect(await account.byTitle('---')).toMatchObject({ note: { id: 'r' } });
    expect(await account.byTitle('front')).toMatchObject({ note: { id: 'f' } });
    await client.close();
  });

  it('previews a note by the words under its title, with its front matter off (Matt: it previewed as "title: … authors: …")', async () => {
    const { service, client } = await connected();
    const fronted = '---\ntitle: Everything a note can hold\nauthors: matt, Claude\n---\n# Everything a note can hold\n\nWords first,\nthen more words.\nNot these.';
    await service.deviceWrites({ ...aNote('f', fronted), updatedAt: 2 });
    await service.deviceWrites({ ...aNote('p', '# Trip\n\nWe went\nto the sea\nand back'), updatedAt: 1 });

    const listed = JSON.parse(asText(await client.callTool({ name: 'list_notes', arguments: {} }))) as { notes: { id: string; title: string; preview: string }[] };
    expect(listed.notes.map((n) => [n.id, n.title, n.preview])).toEqual([
      ['f', 'Everything a note can hold', 'Words first, then more words.'],
      ['p', 'Trip', 'We went to the sea'],
    ]);
    await client.close();
  });

  it('names the pictures a note it writes carries as the app names them', async () => {
    const { service, account, client } = await connected();
    const body = '# Trip\n\n![a](image/one.jpg) and ![](image/two.png) and ![](http://elsewhere/x.png)';
    const made = await account.create(body);
    expect(made.images).toEqual(['one.jpg', 'two.png']);
    expect((await service.stored(made.note.id))?.images).toEqual(imageNames(body));
    expect(toBase64Url(new Uint8Array([1, 2, 3]))).toBe('AQID');
    await client.close();
  });
});
