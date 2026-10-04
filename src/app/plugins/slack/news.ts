import { sentenceOf, type Notification } from '../../core/notifications/kinds.ts';
import { orgsState } from '../../core/orgs/orgs.ts';
import { NEWS } from '../../notes/orgNews.tsx';
import { channelById, postToChannel, type Channel } from './channels.ts';
import { host } from './manifest.ts';

/**
 * An organization's news, posted to the Slack channel the person chose for it (Matt's #5: "It pairs well with
 * organizations: a team's news could go to its channel too").
 *
 * The news is what the organization's dashboard draws (notes/orgNews.tsx `NEWS`): someone joined, left, was removed,
 * took or declined an invitation, a role changed, it was renamed. Each goes as the sentence the bell reads it by
 * (core/notifications/kinds.ts `sentenceOf`), and nothing else: no note, and nothing sealed.
 *
 * When it goes is the phone's rule for its own notifications (core/notifications/phone.ts `postNewRows`): after a pass
 * of the feed, the rows above the cursor the pass began at, oldest first, and nothing on a device's first look at the
 * feed, which would post its whole history. Three more rules make it once:
 *
 * - **Once per row on this device.** A row is written again when it is read, so it can come above the cursor twice;
 *   the ids posted are kept (`glyph-slack-posted`, the last 300), and an id is kept before its post goes, so two passes
 *   close together cannot both send it. A post that fails is not tried again: the person is not there to be told, and
 *   a retry that lands twice is worse than one that never lands.
 * - **Nothing from before the choice.** A row older than the moment its organization's channel was set is not posted,
 *   so setting a channel today does not send last month's news when one of its rows is read on another device.
 * - **Only an organization the person is a member of**, with a channel chosen for it on this device.
 *
 * The choice is this device's, as the channels are: each device with a channel set for an organization posts its
 * news, so it is set on one device, and the pane says so.
 */

const NEWS_KEY = 'glyph-slack-news';
const POSTED_KEY = 'glyph-slack-posted';
/** How many posted ids are kept: far more than a pass ever brings. */
const POSTED_KEPT = 300;

/** Where one organization's news goes, and since when. */
interface NewsChoice {
  channel: string;
  /** When it was set, in ms: older rows are not posted. */
  since: number;
}

function choices(): Record<string, NewsChoice> {
  const kept = host.storage.get<unknown>(NEWS_KEY, {});
  return kept && typeof kept === 'object' ? (kept as Record<string, NewsChoice>) : {};
}

/** The channel an organization's news goes to on this device, or null: none set, or the channel since forgotten. */
export function newsChannelFor(orgId: string): Channel | null {
  const choice = choices()[orgId];
  return choice && typeof choice.channel === 'string' ? channelById(choice.channel) : null;
}

/** Sends an organization's news to a channel from now on, or to nowhere with null. */
export function setNewsChannel(orgId: string, channelId: string | null, now = Date.now()): void {
  const next = { ...choices() };
  if (channelId) next[orgId] = { channel: channelId, since: now };
  else delete next[orgId];
  if (Object.keys(next).length) host.storage.set(NEWS_KEY, next);
  else host.storage.remove(NEWS_KEY);
}

function postedIds(): string[] {
  const kept = host.storage.get<unknown>(POSTED_KEY, []);
  return Array.isArray(kept) ? kept.filter((id): id is string => typeof id === 'string') : [];
}

/** Whether the account is a member of an organization now, by the list this device keeps (core/orgs/orgs.ts). */
function isMember(orgId: string): boolean {
  return orgsState().list.some((row) => row.id === orgId && row.state === 'member');
}

export interface ForwardDeps {
  post?: (channel: Channel, text: string) => Promise<void>;
  member?: (orgId: string) => boolean;
}

/**
 * The rows a pass brought, each new piece of an organization's news posted to its channel: those above `before`, of a
 * kind that is news, about an organization with a channel set here, from no earlier than it was set, and not posted
 * from this device already. Answers how many went.
 */
export async function forwardNews(before: number, rows: readonly Notification[], { post = postToChannel, member = isMember }: ForwardDeps = {}): Promise<number> {
  if (before <= 0) return 0;
  const chosen = choices();
  if (!Object.keys(chosen).length) return 0;
  let posted = 0;
  // Oldest first, so the channel reads in the order it happened.
  for (const n of [...rows].sort((a, b) => a.rev - b.rev)) {
    if (n.rev <= before || !NEWS.has(n.kind)) continue;
    const orgId = n.org?.id;
    const choice = orgId ? chosen[orgId] : undefined;
    if (!orgId || !choice || n.at < choice.since || !member(orgId)) continue;
    const channel = channelById(choice.channel);
    if (!channel) continue;
    const done = postedIds();
    if (done.includes(n.id)) continue;
    // Kept before it goes: at most once, never twice.
    host.storage.set(POSTED_KEY, [...done, n.id].slice(-POSTED_KEPT));
    try {
      await post(channel, `${sentenceOf(n).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}.`);
      posted += 1;
    } catch {
      // Not said anywhere: this runs in the background, after a sync, with nobody looking at a note to tell.
    }
  }
  return posted;
}
