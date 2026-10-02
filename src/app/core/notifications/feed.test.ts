import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fakeService, type FakeService } from '../../../test/fakeService.ts';
import type { Session } from '../account/keystore.ts';
import { DEFAULT_NOTIFICATION_PREFS } from '../preferences.ts';
import { seal } from '../sync/crypto.ts';
import type { Notification } from './kinds.ts';

/*
 * The feed against the service in memory (feed.ts): two devices converging on what was read and hidden, a mark
 * made here outliving a row fed before it landed, an invitation answered inline, a sealed row opened lazily and
 * never stalling, and the two 404s told apart - the service without the routes yet, which is quiet, and an answer
 * in the service's words, which is not. The module's own store is read through a session the test hands out.
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

let feed: typeof import('./feed.ts');

/** A device's feed, synced through `service`: its own state, and a clock the test moves. */
function device(service: FakeService, fetcher: typeof fetch = service.fetcher) {
  let state = feed.emptyFeed();
  const clock = { at: 1_000 };
  return {
    clock,
    get state() {
      return state;
    },
    /** The rows as the page lists them. */
    rows: () => feed.listed(state),
    row: (id: string) => state.items[id],
    mark: (mark: Parameters<typeof feed.withMark>[1]) => {
      state = feed.withMark(state, mark, clock.at);
    },
    sync: () =>
      feed.syncNotifications({
        token: service.signedIn(),
        read: () => state,
        update: (fn) => {
          state = fn(state);
        },
        fetcher,
        now: () => clock.at,
      }),
  };
}

beforeEach(async () => {
  vi.resetModules();
  localStorage.clear();
  session = { ...SESSION };
  key = null;
  feed = await import('./feed.ts');
  feed.forgetOpened();
});

describe('what was read and hidden', () => {
  it('reaches every device: read on the phone, hidden on the Mac, and both converge', async () => {
    const service = await fakeService(ACCOUNT);
    const a = service.notifies({ kind: 'member-joined', from: 'sam', org: { id: 'o1', name: 'Ghost' } });
    const b = service.notifies({ kind: 'member-left', from: 'sam', org: { id: 'o1', name: 'Ghost' } });
    const phone = device(service);
    const mac = device(service);
    await phone.sync();
    await mac.sync();
    expect(phone.rows().map((n) => n.id)).toEqual([b.id, a.id]);
    expect(mac.rows()).toHaveLength(2);

    phone.mark({ id: a.id, read: true });
    expect(phone.row(a.id)?.readAt).toBe(1_000);
    mac.mark({ id: b.id, hidden: true });
    expect(mac.rows().map((n) => n.id)).toEqual([a.id]);
    await phone.sync();
    await mac.sync();
    await phone.sync();
    // Each took the other's change: the service fed the rows again at the revisions the marks made.
    expect(phone.row(b.id)?.hidden).toBe(true);
    expect(phone.rows().map((n) => n.id)).toEqual([a.id]);
    expect(mac.row(a.id)?.readAt).not.toBeNull();
    expect(phone.state.marks).toEqual([]);
    expect(mac.state.marks).toEqual([]);
    expect(service.calls.filter((c) => c.startsWith('PUT notifications/'))).toHaveLength(2);
  });

  it('marks everything this device had been fed, and nothing fed since', async () => {
    const service = await fakeService(ACCOUNT);
    const a = service.notifies({ kind: 'member-joined', from: 'sam' });
    const phone = device(service);
    await phone.sync();
    phone.mark({ all: true, before: phone.state.cursor });
    const b = service.notifies({ kind: 'member-left', from: 'sam' });
    expect(phone.row(a.id)?.readAt).toBe(1_000);
    await phone.sync();
    // Confirmed, the row comes back with the service's own time on it.
    expect(phone.row(a.id)?.readAt).not.toBeNull();
    expect(phone.row(b.id)?.readAt).toBeNull();
    expect(service.feed.get(a.id)?.readAt).not.toBeNull();
    expect(service.feed.get(b.id)?.readAt).toBeNull();
  });

  it('keeps a mark made here over a row fed before the mark landed', async () => {
    const service = await fakeService(ACCOUNT);
    const a = service.notifies({ kind: 'member-joined', from: 'sam' });
    // As a rule: a row fed at a higher revision is taken, with the pending mark laid over it again; a lower one is not taken at all.
    let state = feed.withFed(feed.emptyFeed(), a, 1);
    state = feed.withMark(state, { id: a.id, read: true }, 5);
    const refed = feed.withFed(state, { ...a, rev: a.rev + 1, readAt: null }, 6);
    expect(refed.items[a.id]).toMatchObject({ rev: a.rev + 1, readAt: 6 });
    expect(feed.withFed(refed, { ...a, rev: a.rev, readAt: null, hidden: true }, 7)).toBe(refed);

    // Live: read while the page carrying it unread is in flight.
    let raced = false;
    const racing: typeof fetch = async (input, init) => {
      const response = await service.fetcher(input, init);
      if (/notifications\?/.test(String(input)) && !raced) {
        raced = true;
        phone.mark({ id: a.id, read: true });
      }
      return response;
    };
    const phone = device(service, racing);
    await phone.sync();
    expect(raced).toBe(true);
    expect(phone.row(a.id)?.readAt).toBe(1_000);
    expect(phone.state.marks).toHaveLength(1);
    // The next pass replays it, and the service agrees.
    await phone.sync();
    expect(phone.state.marks).toEqual([]);
    expect(service.feed.get(a.id)?.readAt).not.toBeNull();
    expect(phone.row(a.id)?.readAt).not.toBeNull();
  });
});

describe('an invitation', () => {
  it('arrives, is answered inline, and the answer reaches the service and the other device', async () => {
    const service = await fakeService(ACCOUNT);
    const orgId = service.invited('Ghost', 'sam');
    const phone = device(service);
    const mac = device(service);
    await phone.sync();
    await mac.sync();
    const [invite] = phone.rows();
    expect(invite).toMatchObject({ kind: 'invite', from: 'sam', org: { id: orgId, name: 'Ghost' }, state: 'pending' });
    phone.mark({ org: orgId, answer: true });
    expect(phone.row(invite!.id)).toMatchObject({ state: 'accepted', readAt: 1_000 });
    await phone.sync();
    expect(service.rowIn(orgId)).toEqual({ role: 'member', state: 'member' });
    expect(service.calls).toContain(`POST orgs/${orgId}/invite`);
    await mac.sync();
    expect(mac.row(invite!.id)?.state).toBe('accepted');
  });

  it('answered elsewhere already, is read as done: the service’s "not invited" drops the mark and the pass goes on', async () => {
    const service = await fakeService(ACCOUNT);
    const orgId = service.invited('Ghost', 'sam');
    const phone = device(service);
    const mac = device(service);
    await phone.sync();
    await mac.sync();
    mac.mark({ org: orgId, answer: false });
    await mac.sync();
    expect(service.rowIn(orgId)?.state).toBe('declined');
    phone.mark({ org: orgId, answer: true });
    await expect(phone.sync()).resolves.toBe(true);
    expect(phone.state.marks).toEqual([]);
    // The service's row, fed again at its new revision, says what the other device said.
    expect(phone.rows()[0]?.state).toBe('declined');
  });
});

describe('the two 404s', () => {
  it('is quiet against a service without the routes yet, and changes nothing', async () => {
    const service = await fakeService(ACCOUNT, { teams: false });
    const phone = device(service);
    phone.mark({ id: 'x', read: true });
    await expect(phone.sync()).resolves.toBe(false);
    expect(phone.state).toMatchObject({ cursor: 0, marks: [{ id: 'x', read: true }] });
  });

  it('surfaces a 404 in the service’s words, which is an answer', async () => {
    const service = await fakeService(ACCOUNT);
    const worded: typeof fetch = async (input, init) => {
      if (/notifications\?/.test(String(input))) return new Response(JSON.stringify({ error: 'Nothing for you here.' }), { status: 404 });
      return service.fetcher(input, init);
    };
    const phone = device(service, worded);
    await expect(phone.sync()).rejects.toThrow('Nothing for you here.');
  });

  it('keeps its marks and unsent rows through any other failure, for the next pass', async () => {
    const service = await fakeService(ACCOUNT);
    service.notifies({ kind: 'member-joined', from: 'sam', id: 'a' });
    const phone = device(service);
    await phone.sync();
    phone.mark({ id: 'a', read: true });
    const down: typeof fetch = async () => new Response(JSON.stringify({ error: 'The service is down.' }), { status: 500 });
    const offline = device(service, down);
    offline.mark({ id: 'a', read: true });
    await expect(offline.sync()).rejects.toThrow('The service is down.');
    expect(offline.state.marks).toHaveLength(1);
  });
});

describe('a sealed row', () => {
  const details = { kind: 'note-edited' as const, noteId: 'n1', title: 'Trip to Lisbon', by: 'Claude', added: 2, removed: 0, first: '- pack', at: 'l3' };

  async function sealed(service: FakeService, id: string, payload: unknown): Promise<Notification> {
    return service.notifies({ kind: 'note-edited', id, blob: await seal(service.accountKey, payload, `notification:${id}`) });
  }

  /** The feed's listeners told `count` times: once per open that lands. */
  function landed(count: number): Promise<void> {
    return new Promise((resolve) => {
      let told = 0;
      const off = feed.onNotifications(() => {
        told += 1;
        if (told === count) {
          off();
          resolve();
        }
      });
    });
  }

  it('is opened lazily, once, and the feed’s listeners hear when it lands', async () => {
    const service = await fakeService(ACCOUNT);
    key = service.accountKey;
    const row = await sealed(service, 'sealed', details);
    let told = 0;
    const off = feed.onNotifications(() => {
      told += 1;
    });
    const one = landed(1);
    expect(feed.openDetails(row)).toBeNull();
    expect(feed.openDetails(row)).toBeNull();
    await one;
    expect(feed.openDetails(row)).toEqual(details);
    expect(told).toBe(1);
    off();
  });

  it('never stalls on one that will not open: drawn by its kind, remembered as such, and the pass unaffected', async () => {
    const service = await fakeService(ACCOUNT);
    key = service.accountKey;
    const moved = await sealed(service, 'moved', details);
    // Sealed for another id: the context does not match, and the seal will not open.
    const stolen: Notification = { ...moved, id: 'stolen' };
    const rubbish = service.notifies({ kind: 'note-created', id: 'rubbish', blob: 'not-a-seal' });
    const wrongShape = await sealed(service, 'shape', { hello: 'there' });
    const three = landed(3);
    expect(feed.openDetails(stolen)).toBeNull();
    expect(feed.openDetails(rubbish)).toBeNull();
    expect(feed.openDetails(wrongShape)).toBeNull();
    await three;
    expect(feed.openDetails(stolen)).toBeNull();
    expect(feed.openDetails(rubbish)).toBeNull();
    expect(feed.openDetails(wrongShape)).toBeNull();
    const phone = device(service);
    await expect(phone.sync()).resolves.toBe(true);
    expect(phone.rows()).toHaveLength(3);
    // Without the key - a private window - nothing opens, and nothing throws.
    key = null;
    feed.forgetOpened();
    const one = landed(1);
    expect(feed.openDetails(moved)).toBeNull();
    await one;
    expect(feed.openDetails(moved)).toBeNull();
  });

  it('is trusted for its kind over the row’s column', async () => {
    const { sentenceOf } = await import('./kinds.ts');
    const row: Notification = { id: 'r', rev: 1, kind: 'summary-written', at: 1, readAt: null, hidden: false, blob: 'x' };
    expect(sentenceOf(row, details)).toBe('Claude edited Trip to Lisbon · 2 lines changed');
    expect(sentenceOf(row, null)).toBe('A meeting was written up');
  });
});

describe('what the page reads', () => {
  it('lists the rows of the account signed in, newest first and never a hidden one, and counts the unread wanted ones', async () => {
    const service = await fakeService(ACCOUNT);
    const a = service.notifies({ kind: 'member-joined', from: 'sam', org: { id: 'o1', name: 'Ghost' }, at: 10 });
    const b = service.notifies({ kind: 'invite', from: 'sam', org: { id: 'o2', name: 'Boo' }, state: 'pending', at: 20 });
    const c = service.notifies({ kind: 'summary-written', at: 30, readAt: 5 });
    const d = service.notifies({ kind: 'member-left', from: 'sam', org: { id: 'o1', name: 'Ghost' }, at: 40, hidden: true });
    const phone = device(service);
    await phone.sync();
    feed.saveFeed(7, phone.state);
    const listed = feed.notifications();
    expect(listed.map((n) => n.id)).toEqual([c.id, b.id, a.id]);
    expect(listed).toBe(feed.notifications());
    expect(feed.unreadCount(DEFAULT_NOTIFICATION_PREFS)).toBe(2);
    // Team news off: the invitation still counts; an organization muted: its news does not.
    expect(feed.unreadCount({ ...DEFAULT_NOTIFICATION_PREFS, team: false })).toBe(1);
    expect(feed.unreadCount({ ...DEFAULT_NOTIFICATION_PREFS, mutedOrgs: ['o1'] })).toBe(1);
    expect(feed.isWanted(d, DEFAULT_NOTIFICATION_PREFS)).toBe(true);
    expect(feed.isWanted({ ...c, readAt: null }, { ...DEFAULT_NOTIFICATION_PREFS, summaries: false })).toBe(false);
    session = null;
    expect(feed.notifications()).toEqual([]);
  });

  it('applies what the person did here at once, for the account signed in', async () => {
    const service = await fakeService(ACCOUNT);
    const a = service.notifies({ kind: 'member-joined', from: 'sam', id: 'a' });
    const orgId = service.invited('Ghost');
    const phone = device(service);
    await phone.sync();
    feed.saveFeed(7, phone.state);
    feed.markRead('a');
    expect(feed.feedState(7).items.a?.readAt).not.toBeNull();
    feed.hide('a');
    expect(feed.notifications().some((n) => n.id === a.id)).toBe(false);
    feed.answerInvite(orgId, false);
    expect(feed.notifications()[0]?.state).toBe('declined');
    feed.markAllRead();
    expect(feed.feedState(7).marks).toEqual([{ id: 'a', read: true }, { id: 'a', hidden: true }, { org: orgId, answer: false }, { all: true, before: phone.state.cursor }]);
    // Replayed by the next pass, and gone.
    await feed.syncNotifications({ token: service.signedIn(), read: () => feed.feedState(7), update: (fn) => feed.updateFeed(7, fn), fetcher: service.fetcher });
    expect(feed.feedState(7).marks).toEqual([]);
    expect(service.feed.get('a')).toMatchObject({ hidden: true });
    expect(service.rowIn(orgId)?.state).toBe('declined');
  });

  it('forgets an account’s feed, and keeps another’s', async () => {
    feed.saveFeed(7, { ...feed.emptyFeed(), cursor: 4 });
    feed.saveFeed(8, { ...feed.emptyFeed(), cursor: 9 });
    feed.forgetNotifications(7);
    expect(feed.feedState(7).cursor).toBe(0);
    expect(feed.feedState(8).cursor).toBe(9);
  });
});
