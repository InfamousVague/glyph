import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fakeService, type FakeService } from '../../../test/fakeService.ts';
import type { Session } from '../account/keystore.ts';
import { setPreferences } from '../preferences.ts';
import { open } from '../sync/crypto.ts';
import * as feed from './feed.ts';
import { record } from './record.ts';

/*
 * A self notification recorded (record.ts): sealed with the kind inside, in the feed here before the post is made,
 * and listed as unsent until the post lands - which the next pass does again, and the service answers the same for
 * an id it already has.
 */

const SESSION: Session = { token: 't1', handle: 'matt', accountId: 7 };
let session: Session | null = null;
let key: CryptoKey | null = null;
vi.mock('../account/account.ts', () => ({
  accountState: () => ({ session, unlocked: Boolean(session && key) }),
  accountKey: async () => key,
  onAccount: () => () => undefined,
}));

const ACCOUNT = { handle: 'matt', password: 'correct horse' };

/** Signed in to `service`, with a token it issued and its key here. */
function signIn(service: FakeService): void {
  session = { ...SESSION, token: service.signedIn() };
  key = service.accountKey;
}

beforeEach(() => {
  localStorage.clear();
  session = { ...SESSION };
  key = null;
  setPreferences({ localOnly: false });
  feed.forgetNotifications(7);
  feed.forgetOpened();
});

describe('recording a notification', () => {
  it('seals the kind and the details under the account key, keeps the row here, and posts it', async () => {
    const service = await fakeService(ACCOUNT);
    signIn(service);
    await record('summary-written', { noteId: 'n1', title: 'Standup' }, { fetcher: service.fetcher, now: () => 42 });
    const [row] = feed.notifications();
    expect(row).toMatchObject({ kind: 'summary-written', at: 42, readAt: null, hidden: false });
    expect(row?.id).toHaveLength(22);
    expect(row?.rev).toBeGreaterThan(0);
    expect(feed.feedState(7).unsent).toEqual([]);
    expect(service.calls).toEqual(['POST notifications']);
    // What the service holds opens only as this notification, and says what it is inside.
    const stored = service.feed.get(row!.id)!;
    expect(await open(service.accountKey, stored.blob!, `notification:${row!.id}`)).toEqual({ kind: 'summary-written', noteId: 'n1', title: 'Standup' });
    await expect(open(service.accountKey, stored.blob!, 'notification:other')).rejects.toBeTruthy();
    // Already opened here: never asked of the seal.
    expect(feed.openDetails(row!)).toEqual({ kind: 'summary-written', noteId: 'n1', title: 'Standup' });
  });

  it('keeps the row as unsent when the post fails, and the next pass sends it, clearing it', async () => {
    const service = await fakeService(ACCOUNT);
    signIn(service);
    const down: typeof fetch = async () => new Response(JSON.stringify({ error: 'The service is down.' }), { status: 500 });
    await record('sync-conflict', { noteId: 'n2', title: 'Trip to Lisbon' }, { fetcher: down });
    const [row] = feed.notifications();
    expect(row).toMatchObject({ kind: 'sync-conflict', rev: 0 });
    expect(feed.feedState(7).unsent).toEqual([row!.id]);
    const sync = () => feed.syncNotifications({ token: service.signedIn(), read: () => feed.feedState(7), update: (fn) => feed.updateFeed(7, fn), fetcher: service.fetcher });
    await sync();
    expect(feed.feedState(7).unsent).toEqual([]);
    expect(feed.feedState(7).items[row!.id]?.rev).toBe(1);
    expect(service.feed.has(row!.id)).toBe(true);
  });

  it('is idempotent: a post sent again for an id the service has answers the same revision and writes nothing', async () => {
    const service = await fakeService(ACCOUNT);
    signIn(service);
    // The answer is lost on the way back: the row is unsent here though the service has it.
    const lossy: typeof fetch = async (input, init) => {
      await service.fetcher(input, init);
      throw new TypeError('Failed to fetch');
    };
    await record('summary-written', { noteId: 'n1', title: 'Standup' }, { fetcher: lossy });
    const [row] = feed.notifications();
    expect(feed.feedState(7).unsent).toEqual([row!.id]);
    const rev = service.feed.get(row!.id)!.rev;
    await feed.syncNotifications({ token: service.signedIn(), read: () => feed.feedState(7), update: (fn) => feed.updateFeed(7, fn), fetcher: service.fetcher });
    expect(feed.feedState(7).unsent).toEqual([]);
    expect(feed.feedState(7).items[row!.id]?.rev).toBe(rev);
    expect(service.feed.size).toBe(1);
    expect(feed.notifications()).toHaveLength(1);
  });

  it('records nothing signed out or without the key, and keeps the row here alone under Local only', async () => {
    const service = await fakeService(ACCOUNT);
    signIn(service);
    key = null;
    await record('summary-written', { noteId: 'n1', title: 'Standup' }, { fetcher: service.fetcher });
    expect(feed.notifications()).toEqual([]);
    key = service.accountKey;
    const was = session;
    session = null;
    await record('summary-written', { noteId: 'n1', title: 'Standup' }, { fetcher: service.fetcher });
    session = was;
    expect(feed.notifications()).toEqual([]);
    setPreferences({ localOnly: true });
    await record('summary-written', { noteId: 'n1', title: 'Standup' }, { fetcher: service.fetcher });
    expect(feed.notifications()).toHaveLength(1);
    expect(service.calls).toEqual([]);
  });

  it('marks a row read here before its post landed on the service too, so it does not come back unread', async () => {
    const service = await fakeService(ACCOUNT);
    signIn(service);
    const down: typeof fetch = async () => new Response(JSON.stringify({ error: 'The service is down.' }), { status: 500 });
    await record('summary-written', { noteId: 'n1', title: 'Standup' }, { fetcher: down });
    const [row] = feed.notifications();
    feed.markRead(row!.id);
    await feed.syncNotifications({ token: service.signedIn(), read: () => feed.feedState(7), update: (fn) => feed.updateFeed(7, fn), fetcher: service.fetcher });
    expect(service.feed.get(row!.id)?.readAt).not.toBeNull();
    expect(feed.feedState(7).items[row!.id]?.readAt).not.toBeNull();
  });
});
