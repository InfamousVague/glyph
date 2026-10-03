import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Session } from '../account/keystore.ts';
import type { Notification } from './kinds.ts';

// Signed in as matt, or signed out; no account key, so a sealed row is worded by its kind.
let session: Session | null = { token: 'tok', handle: 'matt', accountId: 7 };
vi.mock('../account/account.ts', () => ({
  accountState: () => ({ session, unlocked: session !== null }),
  useAccount: () => ({ session, unlocked: session !== null }),
  accountKey: async () => null,
  onAccount: () => () => undefined,
}));

const { forgetPhoneWatch, linkFor, phoneNoticesOn, postNewRows, postsToPhone, setPhoneNoticesOn, syncPhoneWatch } = await import('./phone.ts');
const { saveFeed, emptyFeed } = await import('./feed.ts');
const { reloadPreferences, setPreferences, preferences } = await import('../preferences.ts');

/**
 * The bell's rows as the phone's own notifications (docs/TEAMS.md "On the phone"), against a stand-in for the Android
 * shell: what is posted while the app is in the background, and the watch the closed app's worker is handed.
 */

let posted: { id: string; title: string; text?: string | null; link: string }[];
let watches: string[];
let state: 'off' | 'on' | 'blocked';

function row(over: Partial<Notification> & { kind: Notification['kind'] }): Notification {
  return { id: `n${Math.random()}`, rev: 10, at: 1, readAt: null, hidden: false, from: 'sam', org: { id: 'org1', name: 'Ghost' }, body: { name: 'Ghost' }, ...over };
}

function hidden(on: boolean) {
  Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => (on ? 'hidden' : 'visible') });
}

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
  session = { token: 'tok', handle: 'matt', accountId: 7 };
  posted = [];
  watches = [];
  state = 'on';
  window.GlyphHost = {
    postNotice: (json: string) => {
      posted.push(JSON.parse(json));
      return 'posted';
    },
    watchNotices: (json: string) => {
      watches.push(json);
      state = json ? 'on' : 'off';
      return state;
    },
    noticesState: () => state,
  } as unknown as Window['GlyphHost'];
  forgetPhoneWatch();
  hidden(true);
});

afterEach(() => {
  delete window.GlyphHost;
  hidden(false);
});

describe('a row on the phone', () => {
  it('is what the bell counts, less a meeting and a conflict, which have their own', () => {
    expect(postsToPhone(row({ kind: 'member-joined' }))).toBe(true);
    expect(postsToPhone(row({ kind: 'note-edited', org: undefined, body: undefined, blob: 'x' }))).toBe(true);
    expect(postsToPhone(row({ kind: 'invite', state: 'pending' }))).toBe(true);
    expect(postsToPhone(row({ kind: 'invite', state: 'accepted' }))).toBe(false);
    expect(postsToPhone(row({ kind: 'summary-written' }))).toBe(false);
    expect(postsToPhone(row({ kind: 'sync-conflict' }))).toBe(false);
    expect(postsToPhone(row({ kind: 'member-joined', readAt: 5 }))).toBe(false);
    expect(postsToPhone(row({ kind: 'member-joined', hidden: true }))).toBe(false);
    setPreferences({ notifications: { ...preferences().notifications, mutedOrgs: ['org1'] } });
    expect(postsToPhone(row({ kind: 'member-joined' }))).toBe(false);
    expect(postsToPhone(row({ kind: 'invite' })), 'an invitation is never muted').toBe(true);
  });

  it('opens the note Claude changed, the organization while it is yours, or the drawer', () => {
    expect(linkFor(row({ kind: 'note-edited' }), 'note-1')).toBe('ghostmd://note/note-1');
    expect(linkFor(row({ kind: 'member-joined' }), null)).toBe('ghostmd://org/org1');
    expect(linkFor(row({ kind: 'invite' }), null)).toBe('ghostmd://notifications');
    expect(linkFor(row({ kind: 'org-deleted' }), null)).toBe('ghostmd://notifications');
    expect(linkFor(row({ kind: 'member-removed' }), null)).toBe('ghostmd://notifications');
    expect(linkFor(row({ kind: 'member-removed', body: { name: 'Ghost', handle: 'kim' } }), null)).toBe('ghostmd://org/org1');
  });
});

describe('posting a pass’s rows', () => {
  it('posts the new ones, oldest first, in the bell’s words, while the app is in the background', async () => {
    const rows = [row({ id: 'b', rev: 12, kind: 'member-joined' }), row({ id: 'a', rev: 11, kind: 'note-edited', org: undefined, body: undefined, blob: 'sealed' }), row({ id: 'old', rev: 9, kind: 'member-left' })];
    expect(await postNewRows(10, rows)).toBe(2);
    expect(posted).toEqual([
      { id: 'a', title: 'Claude edited a note', text: null, link: 'ghostmd://notifications' },
      { id: 'b', title: 'sam joined Ghost', text: 'Ghost', link: 'ghostmd://org/org1' },
    ]);
  });

  it('posts nothing with the app in front, on a device’s first look, or with the switch off', async () => {
    const rows = [row({ rev: 12, kind: 'member-joined' })];
    hidden(false);
    expect(await postNewRows(10, rows)).toBe(0);
    hidden(true);
    expect(await postNewRows(0, rows)).toBe(0);
    setPhoneNoticesOn(false);
    expect(phoneNoticesOn()).toBe(false);
    expect(await postNewRows(10, rows)).toBe(0);
    expect(posted).toEqual([]);
  });

  it('posts nothing where the binary cannot', async () => {
    delete window.GlyphHost;
    expect(await postNewRows(10, [row({ rev: 12, kind: 'member-joined' })])).toBe(0);
  });
});

describe('the closed app’s watch', () => {
  it('hands the session, the cursor and the switches, once while nothing changes', () => {
    saveFeed(7, { ...emptyFeed(), cursor: 42 });
    syncPhoneWatch();
    syncPhoneWatch();
    expect(watches).toHaveLength(1);
    expect(JSON.parse(watches[0]!)).toEqual({ api: 'https://ghostmarkdown.com/api', token: 'tok', accountId: 7, cursor: 42, team: true, claude: true, mutedOrgs: [] });
    setPreferences({ notifications: { ...preferences().notifications, claude: false } });
    syncPhoneWatch();
    expect(JSON.parse(watches[1]!).claude).toBe(false);
  });

  it('stops on signing out, on Local only, and with the switch off', () => {
    syncPhoneWatch();
    session = null;
    syncPhoneWatch();
    expect(watches.at(-1)).toBe('');
    session = { token: 'tok', handle: 'matt', accountId: 7 };
    syncPhoneWatch();
    expect(watches.at(-1)).not.toBe('');
    setPreferences({ localOnly: true });
    syncPhoneWatch();
    expect(watches.at(-1)).toBe('');
    setPreferences({ localOnly: false });
    syncPhoneWatch();
    setPhoneNoticesOn(false);
    expect(watches.at(-1)).toBe('');
  });

  it('tries again on a binary that could not take it', () => {
    delete window.GlyphHost;
    syncPhoneWatch();
    window.GlyphHost = { watchNotices: (json: string) => (watches.push(json), 'on') } as unknown as Window['GlyphHost'];
    syncPhoneWatch();
    expect(watches).toHaveLength(1);
  });
});
