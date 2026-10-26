import { call } from '../app/core/account/api.ts';
import { openShare, type Shared } from '../app/share/share.ts';

// A page's name in its address (slugs.ts): pure, so the docs build (vite.docs.config.ts) names its pages as a site does.
export { siteSlugs, slugOf } from './slugs.ts';

/**
 * A published site's address and its pages' (docs/SITES.md; the app's half is lib/share/sites.dart).
 *
 * A site is a shared note or notebook in all that keeps it private: sealed under a key only its link carries, after the
 * `#`, which a browser never sends. Its own part is the address: `/s/<id>` is its first page (a notebook's index, or
 * the note), and `/s/<id>/<page>` each other page, so a page can be linked to and comes back on reload. The web server
 * routes every `/s/…` to the reader page (scripts/deploy-landing.mjs), which reads the id from the path and the key
 * from the fragment and asks the service for the id alone.
 *
 * A page's name in its address is its title as a slug ([slugOf]), worked out here the same way each time from the
 * titles the site carries, so nothing about the pages is kept anywhere but in the sealed site. The page names are the
 * one part of a site the web server receives as written, when someone opens a page's own address; the words never are.
 */

/** The context a site is sealed in (lib/share/sites.dart `siteContext`). */
export const SITE_CONTEXT = 'glyph/v1/site';

/** Where a site is, as its address says: its id, the page asked for (null for its first), and the key after the `#`. */
export interface SiteAddress {
  id: string;
  slug: string | null;
  key: string | null;
}

const ID = /^[A-Za-z0-9_-]{22,64}$/;
const KEY = /^[A-Za-z0-9_-]{43}$/;

/** The site an address names: `/s/<id>`, `/s/<id>/`, `/s/<id>/<page>`, with its key after the `#`; null for any other. */
export function readSiteAddress(pathname: string, hash: string): SiteAddress | null {
  const parts = pathname.split('/').filter(Boolean);
  if (parts[0] !== 's' || parts.length < 2 || parts.length > 3 || !ID.test(parts[1]!)) return null;
  let slug: string | null = null;
  if (parts[2]) {
    try {
      slug = decodeURIComponent(parts[2]);
    } catch {
      slug = parts[2];
    }
  }
  const key = hash.replace(/^#/, '').trim();
  return { id: parts[1]!, slug: slug || null, key: KEY.test(key) ? key : null };
}

/** Whether this page was opened at a site's address. */
export function isSitePath(pathname: string): boolean {
  return /^\/s\/[A-Za-z0-9_-]{22,64}(\/|$)/.test(pathname);
}

/** A page's address on the site, its key carried as it came. */
export function sitePath(id: string, slug: string, hash: string): string {
  return `/s/${id}${slug ? `/${encodeURIComponent(slug)}` : ''}${hash}`;
}

/** The site, read and opened: anyone with its link can, with no account. */
export async function readSite(id: string, key: string, fetcher: typeof fetch = fetch): Promise<Shared> {
  const answer = await call<{ blob: string }>('GET', `sites/${id}`, { fetcher });
  return openShare(answer.blob, key, SITE_CONTEXT);
}
