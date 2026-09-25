import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Session } from '../account/keystore.ts';
import type { LiveEvents, LiveTransport } from './transport.ts';

/*
 * Live sync's one connection on a device (hub.ts): made for the first live note, shared by the rest, closed with the
 * last, and the relay's events handed to the note they are about. The sessions are real; the account is a session the
 * test hands out, and the connection a stand-in that records what it was asked and lets the test speak as the relay.
 */

let session: Session | null = { token: 't1', handle: 'matt', accountId: 7 };
let key: CryptoKey | null = null;
vi.mock('../account/account.ts', () => ({
  accountState: () => ({ session, unlocked: Boolean(key) }),
  accountKey: async () => key,
}));

/** Every connection made, with the relay's events it was given and what it was asked to do. */
const connections: { url: string; events: LiveEvents; joined: string[]; closed: boolean }[] = [];
vi.mock('./transport.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./transport.ts')>()),
  WebSocketTransport: class implements LiveTransport {
    private readonly made: (typeof connections)[number];
    constructor(options: { url: string; events: LiveEvents }) {
      this.made = { url: options.url, events: options.events, joined: [], closed: false };
      connections.push(this.made);
    }
    join(room: string): void {
      this.made.joined.push(room);
    }
    leave(): void {}
    send(): void {}
    close(): void {
      this.made.closed = true;
    }
  },
}));

const { closeLive, openLive } = await import('./hub.ts');
const { setLiveEnabled } = await import('./enabled.ts');
const { newAccountKey, settle } = await import('../sync/crypto.ts');

const hooks = { hasUnsynced: async () => false, keepCopy: async () => undefined };

/** A listener that counts what its session tells the screen. */
function listener() {
  const heard = { ready: [] as string[], peers: [] as number[] };
  return { heard, ready: (words: string) => heard.ready.push(words), peers: (count: number) => heard.peers.push(count) };
}

beforeEach(async () => {
  localStorage.clear();
  connections.length = 0;
  session = { token: 't1', handle: 'matt', accountId: 7 };
  key = await settle(await newAccountKey());
  setLiveEnabled(true);
});

describe('a note made live', () => {
  it('is not, with the switch off, signed out, or without the key to seal a word', async () => {
    setLiveEnabled(false);
    expect(await openLive('a', 'words', listener(), hooks)).toBeNull();
    setLiveEnabled(true);
    session = null;
    expect(await openLive('a', 'words', listener(), hooks)).toBeNull();
    session = { token: 't1', handle: 'matt', accountId: 7 };
    key = null;
    expect(await openLive('a', 'words', listener(), hooks)).toBeNull();
    expect(connections).toEqual([]);
  });

  it('shares one connection with every other live note, and hears only its own room', async () => {
    const one = listener();
    const two = listener();
    const a = await openLive('a', 'words of a', one, hooks);
    const b = await openLive('b', 'words of b', two, hooks);
    expect(connections).toHaveLength(1);
    expect(connections[0]?.url).toMatch(/^wss?:\/\/.*\/v1\/live$/);
    expect(connections[0]?.joined).toEqual(['a', 'b']);
    connections[0]?.events.joined('b', true, 0);
    expect(b?.state).toBe('ready');
    expect(a?.state).toBe('joining');
    expect(two.heard.ready).toEqual(['words of b']);
    connections[0]?.events.peers('a', 2);
    expect(one.heard.peers).toEqual([2]);
    expect(two.heard.peers).toEqual([0]);
    closeLive('a');
    closeLive('b');
  });

  it('opened again, closes the session it had', async () => {
    const first = await openLive('a', 'words', listener(), hooks);
    const second = await openLive('a', 'words', listener(), hooks);
    expect(first?.state).toBe('closed');
    expect(second?.state).toBe('joining');
    closeLive('a');
  });

  it('leaves the connection up while any note is live, and takes it down with the last', async () => {
    await openLive('a', 'words', listener(), hooks);
    await openLive('b', 'words', listener(), hooks);
    closeLive('a');
    expect(connections[0]?.closed).toBe(false);
    closeLive('b');
    expect(connections[0]?.closed).toBe(true);
    // The next live note has a connection of its own.
    await openLive('c', 'words', listener(), hooks);
    expect(connections).toHaveLength(2);
    closeLive('c');
  });
});
