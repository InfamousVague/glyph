import { frontMatterValue, quotedTitle, withFrontMatterValue } from './frontMatter.ts';

/**
 * Where a note was written, as the note itself says it (Matt: "Add the ability to geotag notes and show a map card
 * embedded on the note"). Two flat keys in the note's own front matter, beside `title:`, `book:` and `authors:`:
 *
 *   ---
 *   location: 51.5074,-0.1278
 *   place: "Trafalgar Square, London"
 *   ---
 *
 * So the tag syncs like typing, travels in the note's own file, and shows quiet in the Markdown view. `location:` is
 * `lat,lon` in decimal degrees, four decimals at most (about 11 m); a fix Android calls Approximate (an accuracy past
 * `ROUGH_M`) is written with two (about 1.1 km), and a tag read back with two decimals or fewer is `rough`: drawn at
 * a wider zoom, a ring rather than a pin, "Roughly" before the numbers. The precision is the signal; there is no
 * third key. `place:` is quoted the way `title:` is, and is written only once a name is known.
 *
 * Reading is tolerant (spaces after the comma, quotes, `[a, b]` brackets) and never rewrites: a `location:` that is
 * not two numbers in range reads as no tag and is left exactly as it was typed. Writing keeps every other key as it
 * was, which core/frontMatter.ts guarantees.
 *
 * This half of the feature imports nothing but the front matter rule, on purpose: the MCP server (mcp/server.ts)
 * carries the tag across a rewrite the way it carries the authors, and it bundles for Node, which cannot take the
 * device half (core/location.ts: the position fix, the name from Nominatim, the tag waiting for better words).
 */

export interface GeoTag {
  lat: number;
  lon: number;
  /** The place's name, once asked and kept in the note; null until then. */
  place: string | null;
  /** Written or read at two decimals: an area, not a point. */
  rough: boolean;
}

/** A position as the device answered it: degrees, metres, and when. */
export interface Fix {
  lat: number;
  lon: number;
  accuracy: number;
  at: number;
}

/** A fix less exact than this many metres is Android's "Approximate": written rough. */
export const ROUGH_M = 1000;
/** The most a place name may run to, as a title may. */
const PLACE_CHARS = 80;

const LOCATION = 'location';
const PLACE = 'place';

/** How many decimals a number was written with. */
function decimalsOf(text: string): number {
  const dot = text.indexOf('.');
  return dot < 0 ? 0 : text.length - dot - 1;
}

/** Two numbers out of `location:`'s value, however it was spaced or wrapped, or null. */
function readPair(raw: string): { lat: number; lon: number; rough: boolean } | null {
  const text = raw
    .trim()
    .replace(/^(["'])(.*)\1$/, '$2')
    .replace(/^\[(.*)\]$/, '$1')
    .trim();
  const found = /^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$/.exec(text);
  if (!found) return null;
  const [, a = '', b = ''] = found;
  const lat = Number(a);
  const lon = Number(b);
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return null;
  return { lat, lon, rough: Math.max(decimalsOf(a), decimalsOf(b)) <= 2 };
}

/** The tag a note carries, or null: `location:` read, and `place:` with it when there is one. */
export function geoTagOf(body: string): GeoTag | null {
  const raw = frontMatterValue(body, LOCATION);
  if (raw === null) return null;
  const pair = readPair(raw);
  if (!pair) return null;
  const place = frontMatterValue(body, PLACE)?.trim() || null;
  return { ...pair, place };
}

/** A fix as a tag: four decimals, or two where the fix was rough; no name yet. */
export function tagOf(fix: Fix): GeoTag {
  const rough = fix.accuracy > ROUGH_M;
  const digits = rough ? 2 : 4;
  return { lat: Number(fix.lat.toFixed(digits)), lon: Number(fix.lon.toFixed(digits)), place: null, rough };
}

/** `location:`'s value as it is written: no space, the tag's own precision. */
function locationValue(tag: GeoTag): string {
  const digits = tag.rough ? 2 : 4;
  return `${tag.lat.toFixed(digits)},${tag.lon.toFixed(digits)}`;
}

/** The body with every `key:` line taken out of its front matter: a second one typed by hand, or two devices adding a location at once. */
function withoutKey(body: string, key: string): string {
  let out = body;
  while (frontMatterValue(out, key) !== null) {
    const next = withFrontMatterValue(out, key, null);
    if (next === out) break;
    out = next;
  }
  return out;
}

/**
 * The body with `tag` written into its front matter, `location:` first and `place:` after it once known, or with
 * both taken out, every line of either (and the block with them, when nothing else is in it), for null: a share
 * leaves the tag out this way (share/share.ts), so a second `location:` must not stay behind. The words are untouched.
 */
export function withGeoTag(body: string, tag: GeoTag | null): string {
  if (!tag) return withoutKey(withoutKey(body, PLACE), LOCATION);
  const located = withFrontMatterValue(body, LOCATION, locationValue(tag));
  const name = tag.place?.replace(/\s+/g, ' ').trim().slice(0, PLACE_CHARS) ?? '';
  return withFrontMatterValue(located, PLACE, name ? quotedTitle(name, name) : null);
}

/** The coordinates as a person reads them: "51.5074, -0.1278", or "Roughly 51.51, -0.13". */
export function coordsText(tag: GeoTag): string {
  const digits = tag.rough ? 2 : 4;
  return `${tag.rough ? 'Roughly ' : ''}${tag.lat.toFixed(digits)}, ${tag.lon.toFixed(digits)}`;
}

/** The place's name, or the coordinates where none is known. */
export function tagLabel(tag: GeoTag): string {
  return tag.place ?? coordsText(tag);
}

/** Whether two tags say the same thing, for a card that redraws only when its tag changes. */
export function sameTag(a: GeoTag | null, b: GeoTag | null): boolean {
  if (!a || !b) return a === b;
  return a.lat === b.lat && a.lon === b.lon && a.place === b.place && a.rough === b.rough;
}

/** What Nominatim's reverse lookup answers with, as much of it as the short name reads (`jsonv2`, `addressdetails=1`). */
export interface PlaceAnswer {
  name?: string;
  display_name?: string;
  addresstype?: string;
  address?: Record<string, string | undefined>;
}

const SETTLEMENT = ['city', 'town', 'village', 'hamlet', 'municipality'] as const;
const REGION = ['state', 'country'] as const;

function first(address: Record<string, string | undefined>, keys: readonly string[]): string | null {
  for (const key of keys) {
    const value = address[key]?.trim();
    if (value) return value;
  }
  return null;
}

/**
 * A place's short name out of Nominatim's answer: "Trafalgar Square, London", "Rue de Rivoli, Paris", "Hardangervidda,
 * Vestland". A named place (a square, a park) or the road, then the settlement; never a house's name or number, which
 * is an address rather than a place. A rough tag takes the settlement and its region only. Nothing usable reads as
 * null, which the asker counts as a failed ask.
 */
export function shortPlace(answer: PlaceAnswer, rough: boolean): string | null {
  const address = answer.address ?? {};
  const settlement = first(address, SETTLEMENT);
  const region = first(address, REGION);
  const parts: string[] = [];
  if (rough) {
    if (settlement) parts.push(settlement);
    if (region && region !== settlement) parts.push(region);
  } else {
    const house = answer.addresstype === 'building' || answer.addresstype === 'house' || Boolean(address.house_number?.trim());
    const named = !house ? answer.name?.trim() || null : null;
    const local = named ?? first(address, ['road', 'neighbourhood', 'suburb']);
    if (local) parts.push(local);
    if (settlement && settlement !== local) parts.push(settlement);
    else if (!settlement && region && region !== local) parts.push(region);
  }
  if (!parts.length && answer.display_name) {
    parts.push(
      ...answer.display_name
        .split(',')
        .map((part) => part.trim().replace(/^\d+[a-z]?\s*/i, ''))
        .filter(Boolean)
        .slice(0, 2),
    );
  }
  const name = parts.join(', ').replace(/\s+/g, ' ').trim().slice(0, PLACE_CHARS);
  return name || null;
}
