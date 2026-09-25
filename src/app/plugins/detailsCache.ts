import { failureText } from '../core/failure.ts';
import { markDetailsChanged, type MarkDetails, type MarkEntry } from '../core/markDetails.ts';
import type { PluginHost } from './types.ts';

/**
 * What a plugin has read back about the things a note links to - a Notion task, a GitHub issue - kept, paced and
 * refreshed the one way both do it, for their MarkDetailsProviders (core/markDetails.ts). Notion's and GitHub's were
 * the same seventy lines written twice (notion/details.ts, github/details.ts); what differs is what a key is, how one
 * is read, and what can be done to it, and those stay with each plugin.
 *
 * - **Reads are paced**: `atOnce` at a time, the rest queued, so a long list scrolled past doesn't fire a read per
 *   line at a service that allows a few a second.
 * - **An answer is fresh for `freshMs`**, so the same line drawn again doesn't read it again; `want(…, true)` is a
 *   Refresh by hand, and reads whatever is kept.
 * - **A read that failed is tried again once it is as old as a stale answer**, not only by hand. It used to wait for
 *   a Refresh, so one failure - the network not back yet as the phone woke, Notion asking Glyph to slow down - left a
 *   new task unread for as long as the app stayed open, and its item never ticked or moved to Done. A failure over an
 *   answer already had keeps the answer.
 * - **The last `keep` answers are kept** in the plugin's own storage, newest first, so a note opened offline shows
 *   what its links last said, with when they were read. What is kept is checked as it is read back: an entry from
 *   another build's shape is left out, not trusted.
 *
 * Every change tells the pills and cards showing a link to look again (`markDetailsChanged`).
 */

interface Known {
  details?: MarkDetails;
  failed?: string;
  /** When the last read failed: a link never read is tried again once this is as old as a stale answer. */
  failedAt?: number;
  loading: boolean;
}

export interface DetailsCacheOptions {
  host: PluginHost;
  /** The plugin's storage key the answers are kept under (it must be in the plugin's manifest). */
  storageKey: string;
  /** Reads one link: the key it is kept under, and its address. What it throws is said on the card as the failure. */
  read: (key: string, url: string) => Promise<MarkDetails>;
  /** Whether reading is possible at all yet (Notion's binary check); a want before then does nothing. Always, by default. */
  ready?: () => boolean;
  /** How long an answer, or a failure, is fresh enough not to read again: 45 seconds unless said. */
  freshMs?: number;
  /** How many answers are kept in storage, newest first: 300 unless said. */
  keep?: number;
  /** How many reads run at once: two unless said. */
  atOnce?: number;
}

export interface DetailsCache {
  /** What is known about `key` now, for a pill: the answer, a failure, a read under way, or nothing yet. */
  peek(key: string): MarkEntry | null;
  /** Asks for `key` to be read, unless it is being read or its answer (or its failure) is fresh; `fresh` reads anyway. */
  want(key: string, url: string, fresh?: boolean): void;
  /** Reads `key` now, outside the queue: after a write, to show what the write did. */
  reread(key: string, url: string): Promise<void>;
  /** Keeps an answer that was not read (what a create or a write just answered), and tells everything showing it. */
  keep(key: string, details: MarkDetails): void;
  /** The answer kept for `key`, if there is one. */
  details(key: string): MarkDetails | undefined;
  /** Forgets every answer, kept or not: for signing out, when another account's links are not this one's. */
  forget(): void;
}

export function detailsCache({ host, storageKey, read, ready = () => true, freshMs = 45_000, keep: most = 300, atOnce = 2 }: DetailsCacheOptions): DetailsCache {
  const known = new Map<string, Known>();
  const queue: { key: string; url: string }[] = [];
  let running = 0;
  let restored = false;

  /** What was kept, read back the first time anything is asked: a page that never shows a link never reads it. */
  const restore = () => {
    if (restored) return;
    restored = true;
    const saved = host.storage.get<Record<string, MarkDetails>>(storageKey, {});
    if (!saved || typeof saved !== 'object') return;
    for (const [key, details] of Object.entries(saved)) {
      if (details && typeof details.title === 'string' && Array.isArray(details.fields)) known.set(key, { details, loading: false });
    }
  };

  const persist = () => {
    const kept = [...known.entries()]
      .filter(([, entry]) => entry.details)
      .sort(([, a], [, b]) => (b.details?.readAt ?? 0) - (a.details?.readAt ?? 0))
      .slice(0, most);
    host.storage.set(storageKey, Object.fromEntries(kept.map(([key, entry]) => [key, entry.details])));
  };

  const load = async (key: string, url: string) => {
    const entry = known.get(key) ?? { loading: true };
    try {
      known.set(key, { details: await read(key, url), loading: false });
      persist();
    } catch (failure) {
      known.set(key, { details: entry.details, failed: entry.details ? undefined : failureText(failure), failedAt: Date.now(), loading: false });
    }
    markDetailsChanged();
  };

  const pump = () => {
    while (running < atOnce && queue.length) {
      const next = queue.shift()!;
      running += 1;
      void load(next.key, next.url).finally(() => {
        running -= 1;
        pump();
      });
    }
  };

  return {
    peek(key) {
      restore();
      const entry = known.get(key);
      if (entry?.details) return { state: 'ready', details: entry.details, loading: entry.loading };
      if (entry?.failed) return { state: 'failed', message: entry.failed };
      return entry?.loading ? { state: 'loading' } : null;
    },
    want(key, url, fresh = false) {
      if (!ready()) return;
      restore();
      const entry = known.get(key);
      if (entry?.loading) return;
      if (!fresh && entry?.details && Date.now() - entry.details.readAt < freshMs) return;
      if (!fresh && entry?.failed && Date.now() - (entry.failedAt ?? 0) < freshMs) return;
      known.set(key, { details: entry?.details, loading: true });
      queue.push({ key, url });
      pump();
    },
    reread: load,
    keep(key, details) {
      restore();
      known.set(key, { details, loading: false });
      persist();
      markDetailsChanged();
    },
    details: (key) => known.get(key)?.details,
    forget() {
      known.clear();
      host.storage.remove(storageKey);
      markDetailsChanged();
    },
  };
}
