import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show } from '../../test/render.tsx';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

// Signed in as sam, or out, as each test says.
let session: { handle: string; token: string; accountId: number } | null = { handle: 'sam', token: 't', accountId: 1 };
vi.mock('../core/account/account.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/account/account.ts')>()),
  useAccount: () => ({ session, unlocked: Boolean(session) }),
  accountState: () => ({ session, unlocked: Boolean(session) }),
}));

const { NotificationsPane } = await import('./NotificationsPane.tsx');
const { preferences, setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');
const { saveOrgs, forgetOrgs } = await import('../core/orgs/orgs.ts');
const { forgetPhoneWatch, phoneNoticesOn } = await import('../core/notifications/phone.ts');

/**
 * Settings › Notifications (docs/TEAMS.md, D8 and D9): the four switches over the synced preference, the organizations
 * that can be muted once there are any, and on a phone whose app can raise them, the phone's own notifications.
 */

beforeEach(() => {
  localStorage.clear();
  session = { handle: 'sam', token: 't', accountId: 1 };
  setPreferences(DEFAULT_PREFERENCES);
});

afterEach(() => {
  forgetOrgs(1);
  delete window.GlyphHost;
  forgetPhoneWatch();
});

const labels = (host: HTMLElement) => [...host.querySelectorAll('.setk-row__label')].map((label) => label.textContent);
const hint = (host: HTMLElement, label: string) =>
  [...host.querySelectorAll('.setk-row')].find((row) => row.querySelector('.setk-row__label')?.textContent === label)?.querySelector('.setk-row__hint')?.textContent;
const toggle = (host: HTMLElement, label: string) => host.querySelector<HTMLInputElement>(`[aria-label="${label}"]`)!;

describe('the switches', () => {
  it('are the four categories, all on by default, each writing the synced preference', () => {
    const host = show(<NotificationsPane />);
    expect(labels(host)).toEqual(['Team', 'Claude', 'Summaries', 'Conflicts']);
    for (const label of ['Team', 'Claude', 'Summaries', 'Conflicts']) expect(toggle(host, label).checked).toBe(true);
    act(() => toggle(host, 'Claude').click());
    expect(preferences().notifications).toEqual({ team: true, claude: false, summaries: true, conflicts: true, mutedOrgs: [] });
    act(() => toggle(host, 'Claude').click());
    expect(preferences().notifications.claude).toBe(true);
  });

  it('say where the phone’s own notification for a meeting still lives, and that an invitation always arrives', () => {
    const host = show(<NotificationsPane />);
    expect(hint(host, 'Summaries')).toBe('A meeting written up. Here, in the list; the phone’s own notification is under Recording.');
    expect(host.querySelector('.setk__footer')?.textContent).toBe('An invitation to an organization always arrives: whoever sent it is waiting for your answer.');
  });
});

describe('muting an organization', () => {
  it('offers no card without one, and a row for each the account has joined, never one it is only invited to', () => {
    const none = show(<NotificationsPane />);
    expect(none.textContent).not.toContain('Mute an organization');
    none.remove();
    saveOrgs(1, {
      list: [
        { id: 'ghost', name: 'Ghost', hue: 'sea', role: 'member', state: 'member', members: 3, invitedBy: null, createdAt: 1 },
        { id: 'boo', name: 'Boo', hue: null, role: 'member', state: 'invited', members: 1, invitedBy: 'sam', createdAt: 2 },
      ],
      at: 1,
    });
    const host = show(<NotificationsPane />);
    expect([...host.querySelectorAll('.setk__title')].map((t) => t.textContent)).toEqual(['What reaches you', 'Mute an organization']);
    expect(labels(host)).toEqual(['Team', 'Claude', 'Summaries', 'Conflicts', 'Ghost']);
    expect(hint(host, 'Ghost')).toBe('3 members');
    act(() => toggle(host, 'Mute Ghost').click());
    expect(preferences().notifications.mutedOrgs).toEqual(['ghost']);
    act(() => toggle(host, 'Mute Ghost').click());
    expect(preferences().notifications.mutedOrgs).toEqual([]);
  });
});

describe('the rest of the page', () => {
  it('says what the phone does while the app is closed: nothing', () => {
    const host = show(<NotificationsPane />);
    expect(host.querySelector('.setk-footnote')?.textContent).toBe('Ghost.md looks when it opens; the bell shows what arrived.');
  });

  it('sends a signed-out person to Account, by a word that goes there', () => {
    session = null;
    const onOpen = vi.fn();
    const host = show(<NotificationsPane onOpen={onOpen} />);
    expect(host.querySelector('.setk-callout')?.textContent).toBe('Notifications come with an account. Sign in under Account and they arrive here.');
    act(() => host.querySelector<HTMLButtonElement>('.setk-callout .setk-go')!.click());
    expect(onOpen).toHaveBeenCalledWith({ id: 'account' });
    // The switches are still there to set: they travel with the account once there is one.
    expect(labels(host)).toEqual(['Team', 'Claude', 'Summaries', 'Conflicts']);
  });
});

describe('on this phone', () => {
  let state: 'off' | 'on' | 'blocked';
  let watches: string[];
  let asked: number;
  beforeEach(() => {
    state = 'on';
    watches = [];
    asked = 0;
    window.GlyphHost = {
      noticesState: () => state,
      watchNotices: (json: string) => {
        watches.push(json);
        if (!json) state = 'off';
        return state;
      },
      requestNotifications: () => {
        asked += 1;
        return 'asked';
      },
    } as unknown as Window['GlyphHost'];
  });

  it('is not there where the app cannot raise a notification: the Mac, a browser, an older phone', () => {
    delete window.GlyphHost;
    const host = show(<NotificationsPane />);
    expect(labels(host)).not.toContain('Phone notifications');
  });

  it('is on until turned off here, and turning it off stops the closed app reading the feed', () => {
    const host = show(<NotificationsPane />);
    expect(labels(host)).toContain('Phone notifications');
    expect(toggle(host, 'Phone notifications').checked).toBe(true);
    act(() => toggle(host, 'Phone notifications').click());
    expect(phoneNoticesOn()).toBe(false);
    expect(watches.at(-1)).toBe('');
    expect(toggle(host, 'Phone notifications').checked).toBe(false);
  });

  it('says when Android is keeping them from showing, and asks to allow them', () => {
    state = 'blocked';
    const host = show(<NotificationsPane />);
    expect(hint(host, 'Phone notifications')).toMatch(/^It’s on, but Android is not showing notifications/);
    act(() => [...host.querySelectorAll('button')].find((b) => b.textContent === 'Allow notifications')!.click());
    expect(asked).toBe(1);
  });
});
