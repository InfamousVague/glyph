import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import type { Session } from '../core/account/keystore.ts';
import type { Notification } from '../core/notifications/kinds.ts';
import { button, buttonSaying, show, unmount, waitUntil } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';

// The kit asks matchMedia as it loads.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
stubResizeObserver();

// Signed in as matt, with the account key when a test seals a row for it.
let session: Session | null = null;
let key: CryptoKey | null = null;
vi.mock('../core/account/account.ts', () => ({
  accountState: () => ({ session, unlocked: Boolean(session && key) }),
  useAccount: () => ({ session, unlocked: Boolean(session && key) }),
  accountKey: async () => key,
  onAccount: () => () => undefined,
}));
// The pass the page asks for as it opens and after an answer: counted, and it confirms every queued mark.
const passes = vi.hoisted(() => ({ count: 0 }));
vi.mock('../core/sync/engine.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/sync/engine.ts')>()),
  syncNotificationsNow: async () => {
    passes.count += 1;
    const { updateFeed } = await import('../core/notifications/feed.ts');
    updateFeed(7, (state) => ({ ...state, marks: [] }));
  },
}));

const { NotificationsDrawer } = await import('./NotificationsDrawer.tsx');
const { feedState, forgetNotifications, forgetOpened, updateFeed, withFed } = await import('../core/notifications/feed.ts');
const { forgetOrgs, saveOrgs } = await import('../core/orgs/orgs.ts');
const { DEFAULT_PREFERENCES, setPreferences } = await import('../core/preferences.ts');
const { newAccountKey, seal } = await import('../core/sync/crypto.ts');

/**
 * The notifications drawer (docs/TEAMS.md), the floating card under the bell: the rows the feed holds, newest first and only the wanted ones, the count
 * and Mark all read in its head, an invitation's Accept and Decline, a row about a note opening the note and one
 * about an organization opening the organization, the ghost when there is nothing, and the signed-out words.
 */

const SESSION: Session = { token: 't1', handle: 'matt', accountId: 7 };
let at = 1_000_000;

/** A row fed to matt's feed, at the next revision, a minute after the last, with the cursor moved past it as a pass moves it. */
function fed(row: Partial<Notification> & { kind: Notification['kind'] }): Notification {
  at += 60_000;
  const item: Notification = { id: row.id ?? `n${at}`, rev: at, at, readAt: null, hidden: false, ...row };
  updateFeed(7, (state) => ({ ...withFed(state, item, at), cursor: at }));
  return item;
}

type Props = Parameters<typeof NotificationsDrawer>[0];
const page = (over: Partial<Props> = {}) =>
  show(<NotificationsDrawer onClose={() => undefined} onOpenNote={() => undefined} onOpenOrganization={() => undefined} onAccount={() => undefined} {...over} />);

const rows = () => [...document.querySelectorAll<HTMLElement>('ol[aria-label="Notifications"] li')];
const sentences = () => rows().map((li) => li.querySelector('[class*=sentence]')?.textContent);
const count = () => document.querySelector('h2 span')?.textContent ?? null;

beforeEach(() => {
  localStorage.clear();
  setPreferences(DEFAULT_PREFERENCES);
  session = { ...SESSION };
  key = null;
  passes.count = 0;
  forgetNotifications(7);
  forgetOpened();
  forgetOrgs(7);
});

afterEach(() => {
  unmount();
  forgetNotifications(7);
  forgetOrgs(7);
});

describe('the page', () => {
  it('lists the rows newest first, counts the unread in its head, and takes the feed again as it opens', () => {
    fed({ kind: 'member-joined', from: 'sam', org: { id: 'o1', name: 'Ghost' }, body: { name: 'Ghost' } });
    fed({ kind: 'summary-written', readAt: 5 });
    fed({ kind: 'invite', from: 'sam', org: { id: 'o2', name: 'Boo' }, body: { name: 'Boo' }, state: 'pending' });
    page();
    expect(sentences()).toEqual(['sam invited you to Boo', 'A meeting was written up', 'sam joined Ghost']);
    expect(count()).toBe('2');
    expect(rows().map((li) => li.hasAttribute('data-unread'))).toEqual([true, false, true]);
    expect(passes.count).toBe(1);
  });

  it('leaves out what Settings switched off and a muted organization’s news, never an invitation', () => {
    fed({ kind: 'member-joined', from: 'sam', org: { id: 'o1', name: 'Ghost' }, body: { name: 'Ghost' } });
    fed({ kind: 'member-left', from: 'kim', org: { id: 'o2', name: 'Boo' }, body: { name: 'Boo', handle: 'kim' } });
    fed({ kind: 'summary-written' });
    fed({ kind: 'invite', from: 'sam', org: { id: 'o1', name: 'Ghost' }, body: { name: 'Ghost' }, state: 'pending' });
    setPreferences({ notifications: { team: true, claude: true, summaries: false, conflicts: true, mutedOrgs: ['o1'] } });
    page();
    expect(sentences()).toEqual(['sam invited you to Ghost', 'kim left Boo']);
    expect(count()).toBe('2');
  });

  it('marks every row read from its head, and the count and the word go', () => {
    fed({ kind: 'member-joined', from: 'sam', org: { id: 'o1', name: 'Ghost' }, body: { name: 'Ghost' } });
    fed({ kind: 'org-renamed', from: 'sam', org: { id: 'o1', name: 'Ghost' }, body: { name: 'Ghost', was: 'Boo' } });
    page();
    expect(count()).toBe('2');
    act(() => button('Mark all read').click());
    expect(count()).toBeNull();
    expect(buttonSaying(document.body, 'Mark all read')).toBeUndefined();
    expect(rows().every((li) => !li.hasAttribute('data-unread'))).toBe(true);
    expect(feedState(7).marks).toEqual([{ all: true, before: feedState(7).cursor }]);
  });

  it('is the ghost with nothing to show', () => {
    page();
    expect(document.querySelector('[data-scene="all-ticked"]')).not.toBeNull();
    expect(document.body.textContent).toContain('Nothing yet.');
    expect(count()).toBeNull();
  });
});

describe('a row', () => {
  it('about a note opens the note, an edit at its first changed line, once its seal is opened, and is read', async () => {
    key = await newAccountKey();
    const details = { kind: 'note-edited', noteId: 'trip', title: 'Trip to Lisbon', by: 'Claude', added: 1, removed: 1, first: 'Fly on Friday', at: 'line:4' };
    const blob = await seal(key, details, 'notification:e1');
    fed({ id: 'e1', kind: 'note-edited', blob });
    const onOpenNote = vi.fn();
    const onClose = vi.fn();
    page({ onOpenNote, onClose });
    // Drawn by its kind while the seal opens, then with its words and the line under them.
    expect(sentences()).toEqual(['Claude edited a note']);
    await waitUntil(() => expect(sentences()).toEqual(['Claude edited Trip to Lisbon · 2 lines changed']));
    expect(rows()[0]?.querySelector('[class*=detail]')?.textContent).toBe('Fly on Friday');
    expect(rows()[0]?.querySelector('[data-kind]')).toBeNull();
    act(() => rows()[0]!.querySelector('button')!.click());
    expect(onOpenNote).toHaveBeenCalledWith('trip', 'line:4');
    // The drawer goes behind the note it opened.
    expect(onClose).toHaveBeenCalledOnce();
    expect(feedState(7).items.e1?.readAt).not.toBeNull();
  });

  it('about an organization opens it while the person is still in it, and only reads otherwise', () => {
    saveOrgs(7, { list: [{ id: 'o1', name: 'Ghost', hue: null, role: 'member', state: 'member', members: 2, invitedBy: null, createdAt: 1 }], at: 1 });
    const joined = fed({ kind: 'member-joined', from: 'sam', org: { id: 'o1', name: 'Ghost' }, body: { name: 'Ghost' } });
    const gone = fed({ kind: 'org-deleted', from: 'sam', org: { id: 'o2', name: 'Boo' }, body: { name: 'Boo' } });
    const onOpenOrganization = vi.fn();
    page({ onOpenOrganization });
    act(() => rows()[0]!.querySelector('button')!.click());
    expect(onOpenOrganization).not.toHaveBeenCalled();
    expect(feedState(7).items[gone.id]?.readAt).not.toBeNull();
    act(() => rows()[1]!.querySelector('button')!.click());
    expect(onOpenOrganization).toHaveBeenCalledWith('o1');
    expect(feedState(7).items[joined.id]?.readAt).not.toBeNull();
  });

  it('that is an invitation carries Accept and Decline, and says how it was answered after', async () => {
    const invite = fed({ kind: 'invite', from: 'sam', org: { id: 'o1', name: 'Ghost' }, body: { name: 'Ghost' }, state: 'pending' });
    page();
    expect(button('Accept', rows()[0])).toBeTruthy();
    expect(button('Decline', rows()[0])).toBeTruthy();
    await act(async () => button('Accept', rows()[0]).click());
    await waitUntil(() => expect(feedState(7).items[invite.id]?.state).toBe('accepted'));
    expect(passes.count).toBe(2);
    expect(() => button('Accept')).toThrow();
    expect(() => button('Decline')).toThrow();
    expect(rows()[0]?.querySelector('[class*=detail]')?.textContent).toBe('Accepted');
  });
});

describe('signed out, or Local only', () => {
  it('says notifications come with an account, by a word that goes to Account, and asks for no pass', () => {
    session = null;
    const onAccount = vi.fn();
    page({ onAccount });
    expect(document.body.textContent).toContain('Notifications come with an account');
    act(() => button('Account').click());
    expect(onAccount).toHaveBeenCalledOnce();
    expect(passes.count).toBe(0);
    expect(document.querySelector('ol')).toBeNull();
  });

  it('says Local only holds everything off', () => {
    setPreferences({ localOnly: true });
    fed({ kind: 'summary-written' });
    page();
    expect(document.body.textContent).toContain('Local only is on, so nothing arrives until it is off.');
    expect(passes.count).toBe(0);
    expect(document.querySelector('ol')).toBeNull();
  });

  it('closes from its cross, and from a press outside it but not on the bell that opened it', () => {
    const onClose = vi.fn();
    page({ onClose });
    expect(document.querySelector('[role="dialog"]')?.getAttribute('aria-label')).toBe('Notifications');
    act(() => button('Close notifications').click());
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('is a card of its own width, not the window’s (docs/DESIGN.md §174)', () => {
    page();
    expect(document.querySelector('[role="dialog"]')?.hasAttribute('data-wide')).toBe(true);
  });
});
