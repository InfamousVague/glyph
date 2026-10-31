import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * What a library says about its site: `publish.json` at the repository's root, or the `publish` key of
 * `.glyph/config.json` (docs/MARKDOWN_FIRST.md §6), the first winning key by key, and the command line over both.
 *
 *   {
 *     "title": "Matt's notes",            the site's name; the library folder's otherwise
 *     "baseUrl": "https://notes.example.com",   where it will live, for the sitemap, the feed and canonical links
 *     "folders": ["Inbox", "workspaces/Work"],  which folders to publish; every personal folder when left out
 *     "orgs": false,                       `orgs/` is never published unless this is true or names organizations
 *     "robots": "noindex",                 ask search engines to stay out
 *     "recent": 20,                        how many notes the home page lists after the pinned ones
 *     "description": "Notes on …"          a line under the title on the home page
 *   }
 *
 * `.trash/` is never published, whatever the file says, and a note with `private: true` in its front matter is left
 * out whichever folder it is in.
 */

export interface PublishConfig {
  title: string | null;
  description: string | null;
  baseUrl: string | null;
  /** Folders to publish, by path from the library's root; null for every personal folder. */
  folders: string[] | null;
  /** Organizations: false for none, true for all, or the names under `orgs/`. */
  orgs: boolean | string[];
  robots: 'noindex' | null;
  recent: number;
}

export const DEFAULTS: PublishConfig = { title: null, description: null, baseUrl: null, folders: null, orgs: false, robots: null, recent: 20 };

function readJson(path: string): Record<string, unknown> | null {
  if (!existsSync(path)) return null;
  try {
    const value = JSON.parse(readFileSync(path, 'utf8')) as unknown;
    return value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

const str = (value: unknown): string | null => (typeof value === 'string' && value.trim() ? value.trim() : null);
const strings = (value: unknown): string[] | null => (Array.isArray(value) ? value.filter((v): v is string => typeof v === 'string' && v.trim() !== '').map((v) => v.trim().replace(/^\/+|\/+$/g, '')) : null);

/** `raw` read as the config, over `base`. */
export function configFrom(raw: Record<string, unknown>, base: PublishConfig = DEFAULTS): PublishConfig {
  const out = { ...base };
  if (str(raw.title)) out.title = str(raw.title);
  if (str(raw.description)) out.description = str(raw.description);
  if (str(raw.baseUrl)) out.baseUrl = str(raw.baseUrl)!.replace(/\/+$/, '');
  if (strings(raw.folders)) out.folders = strings(raw.folders);
  if (typeof raw.orgs === 'boolean') out.orgs = raw.orgs;
  else if (strings(raw.orgs)) out.orgs = strings(raw.orgs)!;
  if (raw.robots === 'noindex' || raw.robots === true) out.robots = 'noindex';
  if (typeof raw.recent === 'number' && Number.isFinite(raw.recent) && raw.recent >= 0) out.recent = Math.floor(raw.recent);
  return out;
}

/** The library's config: `.glyph/config.json`'s `publish` first, then `publish.json` over it. */
export function readConfig(library: string): PublishConfig {
  let config = DEFAULTS;
  const glyph = readJson(join(library, '.glyph', 'config.json'));
  const inner = glyph?.publish;
  if (inner && typeof inner === 'object' && !Array.isArray(inner)) config = configFrom(inner as Record<string, unknown>, config);
  const own = readJson(join(library, 'publish.json'));
  if (own) config = configFrom(own, config);
  return config;
}
