import * as Y from 'yjs';
import { beforeEach, describe, expect, it } from 'vitest';
import { newAccountKey, settle } from '../sync/crypto.ts';
import { LiveSession } from './session.ts';
import type { LiveTransport } from './transport.ts';
import { Kind, newSeed, openEnvelope, packState, sealEnvelope, type Envelope } from './wire.ts';

/*
 * One device's session, driven by hand (session.ts): the rules for a device that comes back to a room, a device
 * nobody answers, a question answered to the one who asked, and a session that has ended. session.test.ts runs whole
 * rooms through a relay; here there is no relay and no clock, only a transport that keeps what was sent and a
 * scheduler that keeps what was asked to run later, so every step is the test's.
 */

let key: CryptoKey;

/** A transport that keeps every message sent, opened with the key of the test that made it, with who it was for. */
function transport() {
  const opener = key;
  const sent: { kind: number; to: number | undefined }[] = [];
  const pending: Promise<void>[] = [];
  const left: string[] = [];
  const t: LiveTransport = {
    join: () => undefined,
    leave: (room) => left.push(room),
    send: (room, data, to) => {
      pending.push(openEnvelope(opener, room, data).then((envelope) => void sent.push({ kind: envelope.kind, to })));
    },
    close: () => undefined,
  };
  return { t, sent, left, opened: () => Promise.all(pending) };
}

/** A session on note `n`, and the retries it asked to be run later. */
function session(words = 'the words here') {
  const wire = transport();
  const later: (() => void)[] = [];
  const heard = { ready: [] as string[], copies: [] as string[] };
  const live = new LiveSession(
    'n',
    words,
    {
      transport: wire.t,
      key,
      hasUnsynced: () => true,
      keepCopy: async (_id, kept) => void heard.copies.push(kept),
      schedule: (run) => later.push(run),
    },
    { ready: (text) => heard.ready.push(text), peers: () => undefined },
  );
  return { live, wire, later, heard, settled: async () => (await live.sent(), await wire.opened()) };
}

/** A sealed message from device `from`, as the relay hands it over. */
async function from(live: LiveSession, sender: number, envelope: Envelope): Promise<void> {
  await live.message(sender, await sealEnvelope(key, 'n', envelope));
}

/** A room's document holding `words` under `seed`, as a State payload. */
function stateOf(seed: string, words: string): Uint8Array {
  const doc = new Y.Doc();
  doc.getText('body').insert(0, words);
  return packState(seed, Y.encodeStateAsUpdate(doc));
}

beforeEach(async () => {
  key = await settle(await newAccountKey());
});

describe('a device nobody answers', () => {
  it('asks three times and then makes the document itself, when nobody else is in the room', async () => {
    const { live, wire, later, heard, settled } = session();
    live.joined(false, 0);
    expect(live.state).toBe('waiting');
    while (later.length) later.shift()!();
    await settled();
    expect(wire.sent.filter((m) => m.kind === Kind.Query)).toHaveLength(3);
    expect(live.state).toBe('ready');
    expect(heard.ready).toEqual(['the words here']);
  });

  it('stays out of the room when somebody is there who will not answer, rather than risk a second history', async () => {
    const { live, later, heard, settled } = session();
    live.joined(false, 1);
    while (later.length) later.shift()!();
    await settled();
    expect(live.state).toBe('waiting');
    expect(heard.ready).toEqual([]);
  });
});

describe('a device already in the room', () => {
  it('answers a question with its document, to the one who asked and nobody else', async () => {
    const { live, wire, settled } = session();
    live.joined(true, 0);
    await from(live, 9, { kind: Kind.Query, payload: new Uint8Array() });
    await settled();
    expect(wire.sent).toEqual([{ kind: Kind.State, to: 9 }]);
  });

  it('trades whole documents with the room when it comes back after a drop', async () => {
    const { live, wire, settled } = session();
    live.joined(true, 0);
    live.joined(false, 1);
    await settled();
    expect(wire.sent).toEqual([
      { kind: Kind.Query, to: undefined },
      { kind: Kind.State, to: undefined },
    ]);
  });

  it('merges a document from its own history, and ends rather than merge one from another', async () => {
    const { live } = session('mine');
    live.joined(true, 0);
    await from(live, 9, { kind: Kind.State, payload: stateOf(live.seed!, 'more') });
    expect(live.state).toBe('ready');
    await from(live, 9, { kind: Kind.State, payload: stateOf(newSeed(), 'a room made again') });
    expect(live.state).toBe('closed');
  });
});

describe('a session that has ended', () => {
  it('leaves the room, sends nothing more, and takes no more messages', async () => {
    const { live, wire, settled } = session();
    live.joined(true, 0);
    live.close();
    expect(wire.left).toEqual(['n']);
    await from(live, 9, { kind: Kind.Query, payload: new Uint8Array() });
    await settled();
    expect(wire.sent).toEqual([]);
    live.close();
    expect(wire.left).toEqual(['n']);
  });
});
