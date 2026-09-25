// @vitest-environment node
import { EventEmitter } from 'node:events';
import { chmodSync, existsSync, mkdtempSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { fakeService, FAST, type FakeService } from '../src/test/fakeService.ts';
import { askPassword, failureWords, readStored, runCli, sessionFileIn, writeStored, type CliIo } from './cli.ts';
import { GlyphApiError, type StoredSession } from './glyph.ts';
import { VERSION } from './server.ts';
import { aNote } from './testKit.ts';

/**
 * The `glyph-mcp` command, run as a person runs it: in a config folder of the test's own, with a terminal the test
 * types into, against the sync service in memory. Its session file, its password prompt and each of its commands.
 */

let folder = '';
beforeEach(() => {
  folder = mkdtempSync(join(tmpdir(), 'glyph-mcp-test-'));
});
afterEach(() => {
  rmSync(folder, { recursive: true, force: true });
});

const aSession = (token = 'tok-1'): StoredSession => ({ v: 1, api: 'https://fake.test/glyph/api', handle: 'matt', accountId: 7, token, accountKey: 'AAAA', deviceKey: null });

/** A terminal in raw mode that the test types into, one chunk at a time. */
function terminal(isTTY = true) {
  const events = new EventEmitter();
  const raw: boolean[] = [];
  const stdin = {
    isTTY,
    setRawMode: (on: boolean) => {
      raw.push(on);
      return stdin;
    },
    resume: () => stdin,
    pause: () => stdin,
    setEncoding: () => stdin,
    on: (event: string, listener: (chunk: string) => void) => {
      events.on(event, listener);
      return stdin;
    },
    off: (event: string, listener: (chunk: string) => void) => {
      events.off(event, listener);
      return stdin;
    },
  };
  return { stdin: stdin as unknown as CliIo['stdin'], raw, type: (chunk: string) => events.emit('data', chunk), listening: () => events.listenerCount('data') };
}

describe('the session file', () => {
  it('lives under GLYPH_MCP_HOME, else the config folder the environment names, else ~/.config', () => {
    expect(sessionFileIn({ GLYPH_MCP_HOME: '/srv/claude' })).toBe('/srv/claude/session.json');
    expect(sessionFileIn({ XDG_CONFIG_HOME: '/home/m/.cfg' })).toBe('/home/m/.cfg/glyph-mcp/session.json');
    expect(sessionFileIn({})).toBe(join(homedir(), '.config', 'glyph-mcp', 'session.json'));
  });

  it('is written readable by its owner alone, in a folder made for it, however loosely it was left', () => {
    const file = join(folder, 'deeper', 'glyph-mcp', 'session.json');
    writeStored(file, aSession());
    expect(statSync(file).mode & 0o777).toBe(0o600);
    expect(statSync(join(folder, 'deeper', 'glyph-mcp')).mode & 0o077).toBe(0);
    chmodSync(file, 0o644);
    writeStored(file, aSession('tok-2'));
    expect(statSync(file).mode & 0o777).toBe(0o600);
    expect(readStored(file)?.token).toBe('tok-2');
  });

  it('reads back a session, and nothing from a file that is missing, not JSON, or not a session', () => {
    const file = join(folder, 'session.json');
    expect(readStored(file)).toBeNull();
    writeFileSync(file, 'not json');
    expect(readStored(file)).toBeNull();
    for (const wrong of [{ ...aSession(), v: 2 }, { ...aSession(), token: 5 }, { ...aSession(), accountKey: null }, null]) {
      writeFileSync(file, JSON.stringify(wrong));
      expect(readStored(file)).toBeNull();
    }
    writeFileSync(file, JSON.stringify(aSession()));
    expect(readStored(file)).toEqual(aSession());
  });
});

describe('the password prompt', () => {
  it('takes GLYPH_PASSWORD without asking, and will not ask without a terminal', async () => {
    const said: string[] = [];
    await expect(askPassword('Password: ', { env: { GLYPH_PASSWORD: 'given' }, stdin: terminal(false).stdin, err: (w) => said.push(w) })).resolves.toBe('given');
    await expect(askPassword('Password: ', { env: {}, stdin: terminal(false).stdin, err: (w) => said.push(w) })).rejects.toThrow('No terminal to ask for the password');
    expect(said).toEqual([]);
  });

  it('reads what is typed without echo, backspace and delete taking a letter back, until Return', async () => {
    const said: string[] = [];
    const tty = terminal();
    const asked = askPassword('Password: ', { env: {}, stdin: tty.stdin, err: (w) => said.push(w) });
    tty.type('corx\x7f');
    tty.type('rect\bt horse\r');
    await expect(asked).resolves.toBe('correct horse');
    expect(said).toEqual(['Password: ', '\n']);
    // Raw while typing, and the terminal given back, and no longer listened to, after.
    expect(tty.raw).toEqual([true, false]);
    expect(tty.listening()).toBe(0);
  });

  it('is cancelled by Ctrl-C', async () => {
    const tty = terminal();
    const asked = askPassword('Password: ', { env: {}, stdin: tty.stdin, err: () => undefined });
    tty.type('abc\x03');
    await expect(asked).rejects.toThrow('Cancelled.');
    expect(tty.raw).toEqual([true, false]);
  });
});

describe('the commands', () => {
  let service: FakeService;
  let said: string[];
  let answered: string[];
  beforeEach(async () => {
    service = await fakeService({ handle: 'matt', password: 'correct horse' });
    said = [];
    answered = [];
  });

  const io = (env: Record<string, string> = {}, more: Partial<CliIo> = {}): CliIo => ({
    env: { GLYPH_MCP_HOME: folder, GLYPH_API: 'https://fake.test/glyph/api/', ...env },
    stdin: terminal(false).stdin,
    out: (w) => answered.push(w),
    err: (w) => said.push(w),
    signIn: { fetcher: service.fetcher, rounds: FAST },
    ...more,
  });
  const file = () => join(folder, 'session.json');

  it('signs in and keeps the session, says so, and serves nothing until asked', async () => {
    await runCli(['login', 'matt'], io({ GLYPH_PASSWORD: 'correct horse' }));
    const kept = readStored(file());
    expect(kept).toMatchObject({ v: 1, api: 'https://fake.test/glyph/api', handle: 'matt', accountId: 7 });
    expect(kept?.deviceKey?.kty).toBe('OKP');
    expect(said.at(-1)).toBe(`Signed in as matt. The session is kept in ${file()}; the password is not.\n`);
    await expect(runCli(['login'], io())).rejects.toThrow('Say which account: glyph-mcp login <handle>');
  });

  it('tells which account and where the session came from, and keeps a renewed token', async () => {
    await runCli(['login', 'matt'], io({ GLYPH_PASSWORD: 'correct horse' }));
    await service.deviceWrites(aNote('a', '# One'));
    const before = readStored(file())!.token;
    await runCli(['status'], io());
    expect(said.at(-1)).toBe(`Signed in as matt at https://fake.test/glyph/api: 1 notes.\nSession: ${file()}\n`);
    // Opening the session renews its token, and the renewed one is what is kept.
    expect(readStored(file())!.token).not.toBe(before);
    // A week on, the token has lapsed: the command renews it with its own key, and keeps that too.
    service.expireAllTokens();
    const lapsed = readStored(file())!.token;
    await runCli(['status'], io());
    expect(readStored(file())!.token).not.toBe(lapsed);
  });

  it('says the session came from the file when only GLYPH_PASSWORD is set, since that is where it came from', async () => {
    await runCli(['login', 'matt'], io({ GLYPH_PASSWORD: 'correct horse' }));
    await runCli(['status'], io({ GLYPH_PASSWORD: 'correct horse' }));
    expect(said.at(-1)).toContain(`Session: ${file()}\n`);
    await runCli(['status'], io({ GLYPH_HANDLE: 'matt', GLYPH_PASSWORD: 'correct horse' }));
    expect(said.at(-1)).toContain('Session: from GLYPH_HANDLE and GLYPH_PASSWORD\n');
  });

  it('forgets the session on logout, and then is not signed in', async () => {
    await runCli(['login', 'matt'], io({ GLYPH_PASSWORD: 'correct horse' }));
    await runCli(['logout'], io());
    expect(existsSync(file())).toBe(false);
    expect(said.at(-1)).toBe('Signed out: the session file is gone.\n');
    // Signing out twice is still signed out.
    await runCli(['logout'], io());
    await expect(runCli(['status'], io())).rejects.toThrow('Not signed in. Run: glyph-mcp login <handle>');
  });

  it('serves the kept session’s notes as tools, and answers version and nothing else', async () => {
    await runCli(['login', 'matt'], io({ GLYPH_PASSWORD: 'correct horse' }));
    await service.deviceWrites(aNote('a', '# Groceries'));
    const [ours, theirs] = InMemoryTransport.createLinkedPair();
    await runCli([], io({}, { transport: () => theirs }));
    expect(said.at(-1)).toBe(`glyph-mcp ${VERSION}: serving matt's notes over stdio.\n`);
    const client = new Client({ name: 'claude', version: '0' });
    await client.connect(ours);
    const listed = await client.callTool({ name: 'list_notes', arguments: {} });
    expect(JSON.stringify(listed.content)).toContain('Groceries');
    await client.close();
    await runCli(['version'], io());
    expect(answered).toEqual([`${VERSION}\n`]);
    await expect(runCli(['help'], io())).rejects.toThrow('Unknown command help. Use: login <handle>, status, logout, or none to serve.');
  });

  it('says a refusal as the service’s and anything else in its own words', async () => {
    expect(failureWords(new GlyphApiError(401, 'This session has lapsed.'))).toBe("Ghost.md's sync service refused: This session has lapsed.");
    expect(failureWords(new Error('Cancelled.'))).toBe('Cancelled.');
    await runCli(['login', 'matt'], io({ GLYPH_PASSWORD: 'wrong horse' })).catch((failure: unknown) => said.push(failureWords(failure)));
    expect(said.at(-1)).toMatch(/^Ghost\.md's sync service refused: /);
    expect(existsSync(file())).toBe(false);
  });
});
