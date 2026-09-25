import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import type { Note } from '../src/app/core/store.ts';
import { fakeService, FAST, type FakeService } from '../src/test/fakeService.ts';
import { makeNote } from '../src/test/notes.ts';
import { GlyphAccount, type Hooks } from './glyph.ts';
import { buildServer, type HostedHooks } from './server.ts';

/**
 * What the MCP server's tests share (glyph.test.ts, server.test.ts, hosted.test.ts): a note as another device wrote
 * it, the words a tool answered with, and an account signed in to the sync service in memory (src/test/fakeService.ts)
 * with Claude connected to its tools over a pair of in-memory transports. For the tests only; nothing built imports it.
 */

/** The fixed moment a test's notes were written: long enough ago that anything the tools write is newer. */
export const WRITTEN = 1_700_000_000_000;

/** A note another device wrote at `WRITTEN`, as a phone would have made it by voice. */
export function aNote(id: string, body: string, over: Partial<Note> = {}): Note {
  return makeNote(id, body, { createdAt: WRITTEN, updatedAt: WRITTEN, source: 'capture', starred: false, archivedAt: null, ...over });
}

/** The words a tool answered with: its first piece of text. */
export function asText(result: Awaited<ReturnType<Client['callTool']>>): string {
  return (result.content as { text?: string }[])[0]?.text ?? '';
}

/** The service's address in these tests: never reached, since the fake answers every call. */
export const API = 'https://fake.test/glyph/api';

/**
 * Matt's account on a fresh service in memory, signed in as the MCP client signs in, and Claude connected to the
 * server's tools. `hooks` reach the account (a fetcher that steps in, say); `hosted` makes it the hosted server.
 */
export async function connected({ hooks = {}, hosted }: { hooks?: Omit<Hooks, 'fetcher'> & { fetcher?: (service: FakeService) => typeof fetch }; hosted?: HostedHooks } = {}) {
  const service = await fakeService({ handle: 'matt', password: 'correct horse' });
  const session = await GlyphAccount.signIn(API, 'matt', 'correct horse', { rounds: FAST, fetcher: service.fetcher });
  const { fetcher, ...rest } = hooks;
  const account = new GlyphAccount(session, { ...rest, fetcher: fetcher ? fetcher(service) : service.fetcher });
  const client = new Client({ name: 'claude-ai', version: '0' });
  const [ours, theirs] = InMemoryTransport.createLinkedPair();
  await Promise.all([buildServer(account, hosted).connect(theirs), client.connect(ours)]);
  /** A tool called, and what it said: its words, and whether it said them as a refusal. */
  const call = async (name: string, args: Record<string, unknown> = {}) => {
    const result = await client.callTool({ name, arguments: args });
    return { text: asText(result), isError: Boolean(result.isError) };
  };
  return { service, session, account, client, call };
}
