import { useSyncExternalStore } from 'react';
import { accountKey, accountState, onAccount } from '../account/account.ts';
import { ApiError, call, notYet } from '../account/api.ts';
import { externalStore } from '../externalStore.ts';
import { postInviteAnswer } from '../orgs/orgs.ts';
import type { NotificationPrefs } from '../preferences.ts';
import { readStored, writeStored } from '../stored.ts';
import { open } from '../sync/crypto.ts';
import { categoryOf, isDetails, isKind, type Details, type Notification } from './kinds.ts';

/**
 * The account's notifications on this device (docs/TEAMS.md, D4): the rows by id, how far along the account's feed
 * this device has read, and what the person did here that the service has not confirmed yet.
 *
 * The feed rides the account's one revision counter, as the notes do: every change to a row - read, hidden, an
 * invitation answered - takes a new revision on the service and the row is fed again, hidden rows included, and a
 * device takes a fed row only when its revision is above the copy it holds. So reading a row on the phone reaches
 * the Mac by the next pass, and nothing is ever fed twice at the same revision.
 *
 * What the person does here is applied at once and queued as a MARK, replayed at the start of the next pass
 * (`syncNotifications`) and dropped once the service confirms it. While a mark is pending, the local state wins over
 * any fed row that still lacks it: a page fetched before the mark landed would otherwise undo it. "Mark all read"
 * carries the cursor it was pressed at, so it marks only what this device had shown. A self row this device recorded
 * (core/notifications/record.ts) is shown at once with revision 0 and listed as UNSENT until its post lands, which
 * the next pass tries again; the post is idempotent, so a lost answer costs nothing.
 *
 * A sealed row is opened LAZILY, at draw time (`openDetails`), memoised by id, and never in the pass: a row that
 * will not open - sealed by a newer build, say - is drawn by its kind alone and never stalls the feed or moves the
 * cursor short. The unread count reads the plaintext fields only, so the bell is right before anything is opened.
 */

// --- what this device keeps -------------------------------------------------------------

/** Something the person did here, not yet confirmed by the service. */
export type Mark =
  /** One row read, or hidden. */
  | { id: string; read?: true; hidden?: true }
  /** Every row this device had been fed by `before` read. */
  | { all: true; before: number }
  /** An invitation to an organization answered. */
  | { org: string; answer: boolean };

export interface FeedState {
  /** The last revision of the account's feed this device has read. */
  cursor: number;
  items: Record<string, Notification>;
  /** Oldest first. */
  marks: Mark[];
  /** Self rows made here whose post has not landed, by id. */
  unsent: string[];
}

export function emptyFeed(): FeedState {
  return { cursor: 0, items: {}, marks: [], unsent: [] };
}

function stateKey(accountId: number): string {
  return `glyph-sync-${accountId}-notifications`;
}

/** A row as kept, if it has the shape this build reads; one of a kind this build does not know is kept, and not drawn. */
function asItem(raw: unknown): Notification | null {
  if (!raw || typeof raw !== 'object') return null;
  const n = raw as Partial<Record<keyof Notification, unknown>>;
  if (typeof n.id !== 'string' || typeof n.kind !== 'string' || typeof n.at !== 'number') return null;
  return {
    id: n.id,
    rev: typeof n.rev === 'number' ? n.rev : 0,
    kind: n.kind as Notification['kind'],
    at: n.at,
    readAt: typeof n.readAt === 'number' ? n.readAt : null,
    hidden: n.hidden === true,
    ...(n.from === null || typeof n.from === 'string' ? { from: n.from } : {}),
    ...(n.org && typeof n.org === 'object' && typeof (n.org as { id?: unknown }).id === 'string' ? { org: n.org as Notification['org'] } : {}),
    ...(n.body && typeof n.body === 'object' ? { body: n.body as Record<string, unknown> } : {}),
    ...(typeof n.blob === 'string' ? { blob: n.blob } : {}),
    ...(n.state === 'pending' || n.state === 'accepted' || n.state === 'declined' ? { state: n.state } : {}),
  };
}

function asMark(raw: unknown): Mark | null {
  if (!raw || typeof raw !== 'object') return null;
  const m = raw as { id?: unknown; read?: unknown; hidden?: unknown; all?: unknown; before?: unknown; org?: unknown; answer?: unknown };
  if (typeof m.id === 'string') return { id: m.id, ...(m.read === true ? { read: true } : {}), ...(m.hidden === true ? { hidden: true } : {}) };
  if (m.all === true && typeof m.before === 'number') return { all: true, before: m.before };
  if (typeof m.org === 'string' && typeof m.answer === 'boolean') return { org: m.org, answer: m.answer };
  return null;
}

function asFeed(raw: unknown): FeedState | null {
  if (!raw || typeof raw !== 'object') return null;
  const f = raw as Partial<Record<keyof FeedState, unknown>>;
  const items: Record<string, Notification> = {};
  if (f.items && typeof f.items === 'object') {
    for (const held of Object.values(f.items as Record<string, unknown>)) {
      const item = asItem(held);
      if (item) items[item.id] = item;
    }
  }
  return {
    cursor: typeof f.cursor === 'number' ? f.cursor : 0,
    items,
    marks: Array.isArray(f.marks) ? f.marks.map(asMark).filter((m): m is Mark => m !== null) : [],
    unsent: Array.isArray(f.unsent) ? f.unsent.filter((id): id is string => typeof id === 'string' && id in items) : [],
  };
}

let cache: { accountId: number; state: FeedState } | null = null;
const changes = externalStore(0);

/** The feed this device keeps for an account: read from storage once, then held. */
export function feedState(accountId: number): FeedState {
  if (cache?.accountId !== accountId) cache = { accountId, state: readStored(stateKey(accountId), emptyFeed(), asFeed) };
  return cache.state;
}

/** Keeps the feed for an account: on this device for the next launch, and for everything watching it now. */
export function saveFeed(accountId: number, state: FeedState): void {
  cache = { accountId, state };
  writeStored(stateKey(accountId), state);
  changes.update((n) => n + 1);
}

/** The feed changed by `fn`, which runs on the state as it is at that moment, so nothing done meanwhile is lost. */
export function updateFeed(accountId: number, fn: (state: FeedState) => FeedState): void {
  saveFeed(accountId, fn(feedState(accountId)));
}

/** Forgets the feed this device kept of an account: for signing out (core/sync/engine.ts). */
export function forgetNotifications(accountId: number): void {
  if (cache?.accountId === accountId) cache = null;
  writeStored(stateKey(accountId), null);
  changes.update((n) => n + 1);
}

// --- the rules, as functions of a state ------------------------------------------------

/** Whether a mark covers a row: what the local state says about it that the service has not confirmed. */
function covers(mark: Mark, item: Notification): boolean {
  if ('id' in mark) return mark.id === item.id;
  if ('all' in mark) return item.rev <= mark.before;
  return item.kind === 'invite' && item.org?.id === mark.org && item.state === 'pending';
}

/** The row with a mark applied. */
function marked(item: Notification, mark: Mark, now: number): Notification {
  if ('org' in mark) return { ...item, state: mark.answer ? 'accepted' : 'declined', readAt: item.readAt ?? now };
  if ('all' in mark) return { ...item, readAt: item.readAt ?? now };
  return { ...item, ...(mark.read && item.readAt === null ? { readAt: now } : {}), ...(mark.hidden ? { hidden: true } : {}) };
}

/** Whether two marks say the same thing, so the later replaces the earlier. */
function sameMark(a: Mark, b: Mark): boolean {
  if ('id' in a && 'id' in b) return a.id === b.id && !!a.read === !!b.read && !!a.hidden === !!b.hidden;
  if ('all' in a && 'all' in b) return true;
  if ('org' in a && 'org' in b) return a.org === b.org;
  return false;
}

/** The state with a mark applied to every row it covers, and queued for the service. */
export function withMark(state: FeedState, mark: Mark, now: number): FeedState {
  const items = { ...state.items };
  for (const item of Object.values(items)) if (covers(mark, item)) items[item.id] = marked(item, mark, now);
  return { ...state, items, marks: [...state.marks.filter((m) => !sameMark(m, mark)), mark] };
}

/** The state without a mark the service has confirmed, or answered for. */
function withoutMark(state: FeedState, mark: Mark): FeedState {
  return { ...state, marks: state.marks.filter((m) => m !== mark) };
}

/**
 * The state with a fed row: taken when its revision is above the copy held, with every pending mark laid over it
 * again, so a page fetched before a mark landed cannot undo it. A self row it answers for is no longer unsent.
 */
export function withFed(state: FeedState, item: Notification, now: number): FeedState {
  const held = state.items[item.id];
  if (held && held.rev >= item.rev) return state;
  let next = item;
  for (const mark of state.marks) if (covers(mark, next)) next = marked(next, mark, now);
  return { ...state, items: { ...state.items, [item.id]: next }, unsent: state.unsent.filter((id) => id !== item.id) };
}

/** The state with a self row made here, shown now and sent by the next pass if the post does not land first. */
export function withSelfRow(state: FeedState, item: Notification): FeedState {
  return { ...state, items: { ...state.items, [item.id]: item }, unsent: [...state.unsent.filter((id) => id !== item.id), item.id] };
}

/** The rows as the page lists them: of a kind this build knows, not hidden, newest first. */
export function listed(state: FeedState): Notification[] {
  return Object.values(state.items)
    .filter((n) => !n.hidden && isKind(n.kind))
    .sort((a, b) => b.at - a.at || b.rev - a.rev);
}

/**
 * Whether a row is one the person asked to see (Settings › Notifications): its category's switch is on, and its
 * organization is not muted. An invitation always is. Read from the plaintext kind, so no seal is opened.
 */
export function isWanted(n: Notification, prefs: NotificationPrefs): boolean {
  if (!isKind(n.kind)) return false;
  const category = categoryOf(n.kind);
  if (category === 'invites') return true;
  if (!prefs[category]) return false;
  return !(n.org && prefs.mutedOrgs.includes(n.org.id));
}

/** How many of the rows are unread and wanted: the bell's dot and the page's count, from plaintext fields only. */
export function unreadCount(prefs: NotificationPrefs, items: readonly Notification[] = notifications()): number {
  return items.filter((n) => n.readAt === null && isWanted(n, prefs)).length;
}

// --- what the page reads -------------------------------------------------------------------

let snapshot: { state: FeedState; list: Notification[] } | null = null;

/** The rows of the account signed in now, as the page lists them; none signed out. The same array until something changes. */
export function notifications(): readonly Notification[] {
  const session = accountState().session;
  if (!session) return NO_ROWS;
  const state = feedState(session.accountId);
  if (snapshot?.state !== state) snapshot = { state, list: listed(state) };
  return snapshot.list;
}

const NO_ROWS: readonly Notification[] = [];

/** Called after every change to the feed, after a sealed row opens, and after the account changes; answers the way to stop. */
export function onNotifications(listener: () => void): () => void {
  const stopChanges = changes.subscribe(listener);
  const stopAccount = onAccount(listener);
  return () => {
    stopChanges();
    stopAccount();
  };
}

export function useNotifications(): readonly Notification[] {
  return useSyncExternalStore(onNotifications, notifications, notifications);
}

/** A change made here, for the account signed in now; nothing signed out. */
function markHere(mark: Mark): void {
  const session = accountState().session;
  if (!session) return;
  updateFeed(session.accountId, (state) => withMark(state, mark, Date.now()));
}

export function markRead(id: string): void {
  markHere({ id, read: true });
}

/**
 * Every row this device holds read: those at or below the highest revision it has been fed, which is what the drawer
 * shows. It was the cursor alone, and a row held above the cursor - fed by a page whose cursor never landed - stayed
 * unread through every press (Matt: "I cant clear out old notifications from 17 mins ago and older").
 */
export function markAllRead(): void {
  const session = accountState().session;
  if (!session) return;
  const state = feedState(session.accountId);
  const highest = Object.values(state.items).reduce((most, item) => Math.max(most, item.rev), 0);
  markHere({ all: true, before: Math.max(state.cursor, highest) });
}

/** One row cleared out of the list: hidden here at once, and on every device once the service has the mark. */
export function hide(id: string): void {
  markHere({ id, hidden: true });
}

/**
 * Rows cleared out of the list together, as one change: the drawer's Clear all. The service hides a row at a time
 * (`PUT notifications/{id}`), so each is its own mark, replayed by the next pass.
 */
export function hideAll(ids: readonly string[]): void {
  const session = accountState().session;
  if (!session || !ids.length) return;
  const now = Date.now();
  updateFeed(session.accountId, (state) => ids.reduce((next, id) => withMark(next, { id, hidden: true }, now), state));
}

/**
 * The invitation to an organization answered: its row says so at once, and the answer is replayed by the next pass
 * (`syncNotificationsNow` in core/sync/engine.ts is what a screen calls right after, to replay it now and take the
 * organization's list again). Answered from another device already, the service's 404 is read as done.
 */
export function answerInvite(orgId: string, accept: boolean): void {
  markHere({ org: orgId, answer: accept });
}

// --- opening a sealed row --------------------------------------------------------------------

/** What each sealed row opened to, by id: null for one that would not open, and is drawn by its kind. */
const opened = new Map<string, Details | null>();
const opening = new Set<string>();

/** Remembers what a row made here was sealed from, so it is never opened again. */
export function rememberDetails(id: string, details: Details): void {
  opened.set(id, details);
}

/**
 * A sealed row's details, once this device has opened it; null before then, or for a row that will not open. The
 * first ask starts the open and the feed's listeners hear when it lands, so a row drawn by its kind is redrawn with
 * its words a moment later. Never throws, never waits.
 */
export function openDetails(n: Notification): Details | null {
  if (!n.blob) return null;
  const known = opened.get(n.id);
  if (known !== undefined) return known;
  if (!opening.has(n.id)) {
    opening.add(n.id);
    const blob = n.blob;
    void (async () => {
      let details: Details | null = null;
      try {
        const key = await accountKey();
        const payload = key ? await open<unknown>(key, blob, `notification:${n.id}`) : null;
        if (isDetails(payload)) details = payload;
      } catch {
        // Sealed by a newer build, moved from another id, or no key here: drawn by its kind.
      }
      opened.set(n.id, details);
      opening.delete(n.id);
      changes.update((count) => count + 1);
    })();
  }
  return null;
}

/**
 * A sealed row's details, waited for: what `openDetails` starts, for a caller that needs the words now - a phone
 * notification posted for the row (core/notifications/phone.ts). Null for a plaintext row or one that will not open.
 */
export async function detailsFor(n: Notification): Promise<Details | null> {
  if (!n.blob) return null;
  const known = opened.get(n.id);
  if (known !== undefined) return known;
  let details: Details | null = null;
  try {
    const key = await accountKey();
    const payload = key ? await open<unknown>(key, n.blob, `notification:${n.id}`) : null;
    if (isDetails(payload)) details = payload;
  } catch {
    // As openDetails: drawn by its kind.
  }
  opened.set(n.id, details);
  return details;
}

/** Forgets what was opened: for a test, or for signing out. */
export function forgetOpened(): void {
  opened.clear();
  opening.clear();
}

// --- the pass ----------------------------------------------------------------------------------

export interface NotificationsContext {
  token: string;
  /** The feed as it is now: read again at every step, since the page may have marked a row meanwhile. */
  read(): FeedState;
  /** The feed changed by `fn`, run on the state as it is at that moment. */
  update(fn: (state: FeedState) => FeedState): void;
  fetcher?: typeof fetch;
  /** The time, in ms: swapped in by the tests. */
  now?: () => number;
  /** Rows per page, 1 to 200. */
  limit?: number;
}

/** A self row posted: the service's revision for it, which is the one it already has if the id was posted before. */
export async function postSelfRow(token: string, item: Notification, fetcher?: typeof fetch): Promise<number> {
  const { rev } = await call<{ rev: number }>('POST', 'notifications', { token, fetcher, body: { id: item.id, kind: item.kind, blob: item.blob } });
  return rev;
}

/** A mark sent to the service as the route it stands for. */
async function send(ctx: NotificationsContext, mark: Mark): Promise<void> {
  const { token, fetcher } = ctx;
  if ('org' in mark) {
    await postInviteAnswer(mark.org, mark.answer, { token, fetcher });
    return;
  }
  if ('all' in mark) {
    await call('POST', 'notifications/read', { token, fetcher, body: { all: true, before: mark.before } });
    return;
  }
  await call('PUT', `notifications/${encodeURIComponent(mark.id)}`, { token, fetcher, body: { ...(mark.read ? { read: true } : {}), ...(mark.hidden ? { hidden: true } : {}) } });
}

/** Whether a failure is the service not having the route yet, which ends the pass quietly. */
class NotYet extends Error {}

function surfaced(failure: unknown): never {
  if (notYet(failure)) throw new NotYet();
  throw failure;
}

/**
 * One pass over the feed: every pending mark replayed, every unsent self row posted, then the feed read from the
 * cursor to its head. Answers whether the service has the routes: false, and nothing changed, when it does not yet.
 * A 404 in the service's words for a mark - "You were not invited.", an answer given elsewhere - drops the mark and
 * goes on; every other failure is thrown as it is, with the marks and the unsent rows kept for the next pass.
 */
export async function syncNotifications(ctx: NotificationsContext): Promise<boolean> {
  const now = ctx.now ?? Date.now;
  try {
    for (const mark of [...ctx.read().marks]) {
      try {
        await send(ctx, mark);
      } catch (failure) {
        if (!(failure instanceof ApiError && failure.status === 404) || notYet(failure)) surfaced(failure);
      }
      ctx.update((state) => withoutMark(state, mark));
    }
    for (const id of [...ctx.read().unsent]) {
      const item = ctx.read().items[id];
      if (!item) {
        ctx.update((state) => ({ ...state, unsent: state.unsent.filter((held) => held !== id) }));
        continue;
      }
      const rev = await postSelfRow(ctx.token, item, ctx.fetcher).catch(surfaced);
      ctx.update((state) => {
        const held = state.items[id];
        return held ? { ...state, items: { ...state.items, [id]: { ...held, rev } }, unsent: state.unsent.filter((held) => held !== id) } : state;
      });
      // Read or hidden here before the post landed: the service learns that too, or its copy would come back unread.
      const sent = ctx.read().items[id];
      if (sent && (sent.readAt !== null || sent.hidden)) {
        const mark: Mark = { id, ...(sent.readAt !== null ? { read: true } : {}), ...(sent.hidden ? { hidden: true } : {}) };
        await send(ctx, mark).catch(surfaced);
      }
    }
    for (;;) {
      const since = ctx.read().cursor;
      const limit = Math.min(200, Math.max(1, ctx.limit ?? 100));
      const page = await call<{ rev: number; items: Notification[]; more: boolean }>('GET', `notifications?since=${since}&limit=${limit}`, { token: ctx.token, fetcher: ctx.fetcher }).catch(surfaced);
      ctx.update((state) => {
        let next = state;
        for (const raw of page.items) {
          const item = asItem(raw);
          if (item) next = withFed(next, item, now());
        }
        return { ...next, cursor: Math.max(next.cursor, page.rev) };
      });
      if (!page.more) return true;
    }
  } catch (failure) {
    if (failure instanceof NotYet) return false;
    throw failure;
  }
}
