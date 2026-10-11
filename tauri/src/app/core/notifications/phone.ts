import { accountState } from '../account/account.ts';
import { API_BASE } from '../account/api.ts';
import { externalStore } from '../externalStore.ts';
import { noticesStateOnHost, postNoticeOnHost, watchNoticesOnHost, type NoticesState } from '../host.ts';
import { preferences } from '../preferences.ts';
import { readStoredText, writeStoredText } from '../stored.ts';
import { detailsFor, feedState, isWanted } from './feed.ts';
import { categoryOf, detailOf, isKind, sentenceOf, type Notification } from './kinds.ts';

/**
 * The bell's rows as the phone's own notifications (docs/TEAMS.md "On the phone"; native generation 23). Matt: "also
 * send notifications as actual phone notifications too".
 *
 * Two roads, one gate. While the app runs in the background, the rows a sync brings are posted from here
 * (`postNewRows`), in their own words, since the page holds the account key a Claude row is sealed under. While the app
 * is closed, the phone's own worker reads the feed every fifteen minutes or so with the session this module hands it
 * (`syncPhoneWatch`), and words a sealed row by its kind. The phone posts each row once whichever road reaches it
 * first (notices/NoticeAlerts.kt `post`).
 *
 * What comes to the phone is what the bell counts (feed.ts `isWanted`): team news, invitations waiting for an answer,
 * and Claude's changes, by the same switches and mutes. A meeting written up already has its own phone notification
 * (Recording), and a note kept twice is this device's own doing, so neither is posted again here. Nothing is posted
 * with the app in front, where the bell is in view, nor from a device's first look at the feed, which would post its
 * whole history.
 *
 * On or off per phone, not synced: the switch on Settings › Notifications says whether this phone posts them, on unless
 * it was turned off. Nothing here does anything on the Mac, in a browser, or on an APK from before generation 23.
 */

const SWITCH_KEY = 'glyph-phone-notices';

/** The kinds that come to the phone: the categories the bell counts, less the two with a notification of their own. */
const PHONE_CATEGORIES = new Set(['invites', 'team', 'claude']);

/** Whether this phone posts the bell's rows. On unless turned off here. */
export function phoneNoticesOn(): boolean {
  return readStoredText(SWITCH_KEY) !== 'off';
}

/** The phone's row on Settings › Notifications: what Android says now, re-read whenever the page asks. */
const shown = externalStore<NoticesState | null>(null);
export const usePhoneNotices = shown.use;

/** The switch turned, and the phone told at once. */
export function setPhoneNoticesOn(on: boolean): void {
  writeStoredText(SWITCH_KEY, on ? null : 'off');
  syncPhoneWatch();
}

/** What Android says of the phone's notices, read again: after the permission was answered, or the page came back. */
export function readPhoneNotices(): NoticesState | null {
  const state = noticesStateOnHost();
  shown.set(state);
  return state;
}

let lastWatch: string | null = null;

/**
 * The phone told what to watch while the app is closed: the service, the session, the feed's cursor and the switches,
 * or nothing when signed out or switched off. Called after every pass of the feed, on a change of the switches, and on
 * signing in or out; the same watch twice is not handed again.
 */
export function syncPhoneWatch(): void {
  const session = accountState().session;
  const prefs = preferences().notifications;
  const watch =
    session && phoneNoticesOn() && !preferences().localOnly
      ? JSON.stringify({
          api: API_BASE,
          token: session.token,
          accountId: session.accountId,
          cursor: feedState(session.accountId).cursor,
          team: prefs.team,
          claude: prefs.claude,
          mutedOrgs: prefs.mutedOrgs,
        })
      : '';
  if (watch === lastWatch) return;
  const state = watchNoticesOnHost(watch);
  // An APK from before generation 23 answers nothing: nothing was handed, so the next call tries again.
  if (state === null) return;
  lastWatch = watch;
  shown.set(state);
}

/** Forgets the last watch handed: for a test. */
export function forgetPhoneWatch(): void {
  lastWatch = null;
  shown.set(null);
}

/** Where tapping a row's notification goes: the note Claude changed, an organization while it is yours, or the drawer. */
export function linkFor(n: Notification, noteId: string | null): string {
  if (noteId) return `ghostmd://note/${noteId}`;
  const gone = n.kind === 'invite' || n.kind === 'org-deleted' || (n.kind === 'member-removed' && typeof n.body?.handle !== 'string');
  return n.org && !gone ? `ghostmd://org/${n.org.id}` : 'ghostmd://notifications';
}

/** Whether a row is one the phone posts: wanted, unread, not hidden, of a kind that comes here, and not answered. */
export function postsToPhone(n: Notification): boolean {
  if (!isKind(n.kind) || n.readAt !== null || n.hidden) return false;
  if (!PHONE_CATEGORIES.has(categoryOf(n.kind))) return false;
  if (n.kind === 'invite' && n.state !== undefined && n.state !== 'pending') return false;
  return isWanted(n, preferences().notifications);
}

/**
 * The rows a pass brought, posted to the phone: those above `before`, the cursor the pass began at, while the app is
 * not in front. `before` of 0 is a device's first look at the feed, which posts nothing.
 */
export async function postNewRows(before: number, rows: readonly Notification[]): Promise<number> {
  if (before <= 0 || !phoneNoticesOn()) return 0;
  if (typeof document !== 'undefined' && document.visibilityState !== 'hidden') return 0;
  let posted = 0;
  // Oldest first, so the newest lands on top of the phone's list.
  for (const n of [...rows].sort((a, b) => a.rev - b.rev)) {
    if (n.rev <= before || !postsToPhone(n)) continue;
    const details = await detailsFor(n);
    const text = detailOf(details) ?? n.org?.name ?? null;
    const noteId = details && 'noteId' in details ? details.noteId : null;
    if (postNoticeOnHost({ id: n.id, title: sentenceOf(n, details), text, link: linkFor(n, noteId) })) posted += 1;
  }
  return posted;
}
