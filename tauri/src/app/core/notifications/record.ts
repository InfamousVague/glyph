import { accountKey, accountState } from '../account/account.ts';
import { shortId } from '../ids.ts';
import { preferences } from '../preferences.ts';
import { seal } from '../sync/crypto.ts';
import { postSelfRow, rememberDetails, updateFeed, withSelfRow } from './feed.ts';
import type { Details, DetailsOf, Notification, SelfKind } from './kinds.ts';

/**
 * A notification the app makes for itself (docs/TEAMS.md, D2): a meeting written up, a note kept twice by a sync.
 * Sealed under the account key with the kind inside, as `notification:<id>`, and posted to the account so every
 * device lists it; the row is in the feed here before the post is made, and stays listed as unsent if the post does
 * not land - offline, or a service without the route yet - for the next pass to send again
 * (core/notifications/feed.ts). The post is idempotent, so a retry after a lost answer makes no second row.
 *
 * Nothing is recorded without an account and its key: the feed is the account's. With "Nothing leaves the phone"
 * on, the row is kept here and never sent. The MCP server records Claude's writes the same way from its side
 * (mcp/glyph.ts), with the same id maker and the same seal.
 */

export interface RecordOptions {
  /** Swapped in by the tests. */
  fetcher?: typeof fetch;
  now?: () => number;
}

/** Records one self notification. Never throws: a failure to post leaves the row unsent for the next pass. */
export async function record<K extends SelfKind>(kind: K, details: DetailsOf<K>, { fetcher, now = Date.now }: RecordOptions = {}): Promise<void> {
  const session = accountState().session;
  if (!session) return;
  const key = await accountKey().catch(() => null);
  if (!key) return;
  const id = shortId();
  const payload = { kind, ...details } as Details;
  const blob = await seal(key, payload, `notification:${id}`);
  const item: Notification = { id, rev: 0, kind, at: now(), readAt: null, hidden: false, blob };
  rememberDetails(id, payload);
  updateFeed(session.accountId, (state) => withSelfRow(state, item));
  if (preferences().localOnly) return;
  try {
    const rev = await postSelfRow(session.token, item, fetcher);
    updateFeed(session.accountId, (state) => {
      const held = state.items[id];
      return held ? { ...state, items: { ...state.items, [id]: { ...held, rev } }, unsent: state.unsent.filter((other) => other !== id) } : state;
    });
  } catch {
    // Not sent: listed as unsent, and tried again by the next pass.
  }
}
