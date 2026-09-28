import { coordsText, type GeoTag } from './geotag.ts';
import { openLink } from './linkPreview.ts';
import { isAndroid, isMacApp } from './platform.ts';
import { isTauri } from './tauri.ts';

/**
 * Where a tap on a note's map card goes (editor/MapCard.tsx), per platform, carrying the place name or the
 * coordinates and never the note's title: a title goes to whichever app takes the intent, and a maps app keeps its
 * searches on the account.
 *
 * Its own small module, apart from core/location.ts, because the card is drawn on the shared page too
 * (src/read/Reader.tsx), and everything the card imports is loaded by every shared link, tagged or not: the fix, the
 * waiting tag and the place names bring the recorder's better words and the library with them, which a reader never
 * needs.
 */

/**
 * Whether this is an Android binary of native generation 20: its bridge answers `locationAccess`, which also means
 * its manifest declares the location permission and its opener allows `geo:` (both built in with it).
 */
export function hasLocationBridge(): boolean {
  return isAndroid && isTauri() && typeof window.GlyphHost?.locationAccess === 'function';
}

/**
 * The phone's maps chooser on an Android binary with the `geo:` scope, Apple Maps on the Mac, and openstreetmap.org
 * everywhere else (an older Android binary, the web, the reader, iOS), which carries no label.
 */
export function placeUrl(tag: GeoTag): string {
  const { lat, lon } = tag;
  if (hasLocationBridge()) return `geo:${lat},${lon}?q=${lat},${lon}${tag.place ? `(${encodeURIComponent(tag.place)})` : ''}`;
  if (isMacApp) return `https://maps.apple.com/?ll=${lat},${lon}&q=${encodeURIComponent(tag.place ?? coordsText(tag))}`;
  const zoom = tag.rough ? 12 : 15;
  return `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}#map=${zoom}/${lat}/${lon}`;
}

/** Opens the place in the device's maps app, or the browser. */
export async function openPlace(tag: GeoTag): Promise<void> {
  await openLink(placeUrl(tag));
}
