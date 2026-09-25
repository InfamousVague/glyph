import { chmodSync, existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import type { Transport } from '@modelcontextprotocol/sdk/shared/transport.js';
import { failureText } from '../src/app/core/failure.ts';
import { DEFAULT_API, GlyphAccount, GlyphApiError, type StoredSession } from './glyph.ts';
import { buildServer, VERSION } from './server.ts';
import { ensureWebCrypto } from './webcrypto.ts';

/**
 * The `glyph-mcp` command's work (docs/MCP.md), which mcp/main.ts runs with the process's own arguments, environment
 * and terminal:
 *
 *   glyph-mcp login <handle>     sign in with the password (asked for, or GLYPH_PASSWORD), and keep the session
 *   glyph-mcp status             which account is signed in, and whether the session still works
 *   glyph-mcp logout             forget the session
 *   glyph-mcp version            the server's version
 *   glyph-mcp                    serve: what Claude Desktop, Claude Code and the rest run
 *
 * The session - the token, the account key, and this client's own signing key - is kept in one file in the person's
 * config folder (`~/.config/glyph-mcp/session.json`, or under GLYPH_MCP_HOME), readable by them alone. It is what a
 * signed-in phone keeps, and it is the reason the password is never needed again and never stored. A headless setup
 * can give GLYPH_HANDLE and GLYPH_PASSWORD instead, and the server signs in each time it starts.
 *
 * Everything the command touches outside itself comes in through `CliIo`, so its tests can run it against a folder
 * of their own, a terminal of their own and the sync service in memory.
 */

/** What the command reads and writes besides its files: the process's own, unless a test says otherwise. */
export interface CliIo {
  env: Record<string, string | undefined>;
  /** Where a password is typed. */
  stdin: Pick<NodeJS.ReadStream, 'isTTY' | 'setRawMode' | 'resume' | 'pause' | 'setEncoding' | 'on' | 'off'>;
  /** The command's answer, for `version`. */
  out: (words: string) => void;
  /** Everything said to the person: stdout is the MCP conversation's while serving, so it is kept for that. */
  err: (words: string) => void;
  /** How a sign-in reaches the service and stretches the password; the real ones unless a test's fast few. */
  signIn?: { fetcher?: typeof fetch; rounds?: number };
  /** What the served tools are spoken over: stdio, unless a test holds the other end. */
  transport?: () => Transport;
}

/** Where the session is kept: under GLYPH_MCP_HOME, else the config folder's glyph-mcp. */
export function sessionFileIn(env: CliIo['env']): string {
  const home = env.GLYPH_MCP_HOME || join(env.XDG_CONFIG_HOME || join(homedir(), '.config'), 'glyph-mcp');
  return join(home, 'session.json');
}

/** The kept session, or null where there is none, or what is there is not one. */
export function readStored(file: string): StoredSession | null {
  try {
    const value = JSON.parse(readFileSync(file, 'utf8')) as StoredSession;
    return value && value.v === 1 && typeof value.token === 'string' && typeof value.accountKey === 'string' ? value : null;
  } catch {
    return null;
  }
}

/** The session kept, readable by its owner alone: the folder 0700, the file 0600, whatever the umask. */
export function writeStored(file: string, session: StoredSession): void {
  mkdirSync(dirname(file), { recursive: true, mode: 0o700 });
  writeFileSync(file, JSON.stringify(session, null, 2), { mode: 0o600 });
  chmodSync(file, 0o600);
}

/** Ctrl-C and backspace, as a terminal in raw mode sends them. */
const INTERRUPT = '\x03';
const DELETE = '\x7f';

/** The password, typed without echo, or from GLYPH_PASSWORD. */
export async function askPassword(prompt: string, { env, stdin, err }: Pick<CliIo, 'env' | 'stdin' | 'err'>): Promise<string> {
  const given = env.GLYPH_PASSWORD;
  if (given) return given;
  if (!stdin.isTTY) throw new Error('No terminal to ask for the password: set GLYPH_PASSWORD for this one command.');
  err(prompt);
  return new Promise((resolve, reject) => {
    let typed = '';
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding('utf8');
    const onData = (chunk: string) => {
      for (const ch of chunk) {
        if (ch === '\r' || ch === '\n') {
          stdin.setRawMode(false);
          stdin.pause();
          stdin.off('data', onData);
          err('\n');
          resolve(typed);
          return;
        }
        if (ch === INTERRUPT) {
          stdin.setRawMode(false);
          reject(new Error('Cancelled.'));
          return;
        }
        if (ch === DELETE || ch === '\b') typed = typed.slice(0, -1);
        else typed += ch;
      }
    };
    stdin.on('data', onData);
  });
}

/** How a failure is said to the person: the service's refusals as its own, anything else in its own words. */
export function failureWords(failure: unknown): string {
  return failure instanceof GlyphApiError ? `Ghost.md's sync service refused: ${failure.message}` : failureText(failure);
}

/** Runs the command named by `argv` (the arguments after the program's own). */
export async function runCli(argv: readonly string[], io: CliIo): Promise<void> {
  ensureWebCrypto();
  const sessionFile = sessionFileIn(io.env);
  const api = (io.env.GLYPH_API || DEFAULT_API).replace(/\/+$/, '');
  const signIn = (handle: string, password: string) => GlyphAccount.signIn(api, handle, password, { ...io.signIn, label: 'Claude' });

  /** The account to serve: a sign-in from the environment, or the kept session - and which of the two it was. */
  const openAccount = async (): Promise<{ account: GlyphAccount; from: string }> => {
    const handle = io.env.GLYPH_HANDLE;
    const password = io.env.GLYPH_PASSWORD;
    if (handle && password) {
      const session = await signIn(handle, password);
      return { account: new GlyphAccount(session, { fetcher: io.signIn?.fetcher }), from: 'from GLYPH_HANDLE and GLYPH_PASSWORD' };
    }
    const stored = readStored(sessionFile);
    if (!stored) throw new Error(`Not signed in. Run: glyph-mcp login <handle>   (or set GLYPH_HANDLE and GLYPH_PASSWORD)`);
    const account = new GlyphAccount(stored, { save: (session) => writeStored(sessionFile, session), fetcher: io.signIn?.fetcher });
    await account.resume();
    return { account, from: sessionFile };
  };

  const [command, ...rest] = argv;
  switch (command) {
    case 'login': {
      const handle = rest[0];
      if (!handle) throw new Error('Say which account: glyph-mcp login <handle>');
      const password = await askPassword(`Password for ${handle} on ${api}: `, io);
      io.err('Signing in (this takes a moment: the password is stretched 600 000 times, as the app does)…\n');
      const session = await signIn(handle, password);
      writeStored(sessionFile, session);
      io.err(`Signed in as ${session.handle}. The session is kept in ${sessionFile}; the password is not.\n`);
      return;
    }
    case 'status': {
      const { account, from } = await openAccount();
      await account.pull();
      const notes = await account.list({ archived: true });
      io.err(`Signed in as ${account.handle} at ${account.api}: ${notes.length} notes.\nSession: ${from}\n`);
      return;
    }
    case 'logout':
      if (existsSync(sessionFile)) unlinkSync(sessionFile);
      io.err('Signed out: the session file is gone.\n');
      return;
    case 'version':
      io.out(`${VERSION}\n`);
      return;
    case undefined:
    case 'serve': {
      const { account } = await openAccount();
      const server = buildServer(account);
      await server.connect(io.transport ? io.transport() : new StdioServerTransport());
      io.err(`glyph-mcp ${VERSION}: serving ${account.handle}'s notes over stdio.\n`);
      return;
    }
    default:
      throw new Error(`Unknown command ${command}. Use: login <handle>, status, logout, or none to serve.`);
  }
}
