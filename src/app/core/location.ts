import { refinePending } from '../capture/refine.ts';
import { frontMatterOffset } from './frontMatter.ts';
import { coordsText, geoTagOf, shortPlace, tagOf, withGeoTag, type Fix, type GeoTag, type PlaceAnswer } from './geotag.ts';
import { answerHost } from './host.ts';
import { openLink } from './linkPreview.ts';
import { hasNativeGeneration } from './nativeGeneration.ts';
import { isAndroid, isMacApp } from './platform.ts';
import { preferences } from './preferences.ts';
import { readStored, writeStored } from './stored.ts';
import { getNote, updateNote } from './store.ts';
import { invoke, isTauri } from './tauri.ts';

/**
 * Where the device is, and what becomes of that (Matt: "Add the ability to geotag notes and show a map card embedded
 * on the note"; then "Add a setting to geotag notes by default and turn it on"): the position fix, the place's name
 * asked of OpenStreetMap, the tag that waits for a recording's better words, and the way a tapped map opens the
 * phone's maps app. The tag itself, as the note carries it, is core/geotag.ts. Gated the way core/linkPreview.ts is:
 * nothing leaves the device unless the person chose it. Four rules, each with its reason:
 *
 * 1. THE FIX IS A NETWORK CALL, so Local only turns it off too. On Android and the web `getCurrentPosition` with
 *    `enableHighAccuracy: false` goes to the fused provider, which sends nearby Wi-Fi and cell identifiers to Google's
 *    location service (Firefox to Mozilla's, Safari to Apple's). A GPS-only fix - thirty seconds outdoors, nothing
 *    indoors - is not the same feature, so the app does not pretend it is.
 *
 * 2. THE NAME IS ASKED ONCE, FOR A TAG MADE HERE, at three decimals (about 100 m, enough for a street). Never for a
 *    note that arrived by sync, a forked share or one the MCP wrote: the viewer's IP address is never paired with
 *    coordinates they did not choose. Nominatim's usage policy: one request a second, and an identifying User-Agent
 *    or Referer. The page cannot set a User-Agent (a forbidden header), the Android page's Referer is
 *    `http://tauri.localhost/` and the Mac's page sends none, so in the app the ask goes through Rust
 *    (src-tauri/src/geocode.rs, native generation 20), which names the app; on the web the page's own origin is the
 *    name, and the page fetches for itself.
 *
 * 3. A TAG WAITS FOR THE BETTER WORDS. capture/refine.ts writes them only if the note still reads as Done saved it,
 *    and builds the whole body from the take, so a `location:` stamped after Done would either drop them silently or
 *    be written over. The review (ai/useNoteReview.ts) has the same compare one step later, when it hands its job
 *    back. So a tag for a new recording is kept aside (`setPendingTag`) while a pass is queued or a review is live,
 *    and the note's screen writes it once the pass has landed or the review has handed back; the card is drawn from
 *    the waiting tag meanwhile. A pending tag lives a day, and goes with the note to the trash and with the
 *    recording's Undo. It also waits for a note's first words: a typed new note is a draft with no file until it has
 *    some (docs/LIBRARY.md), and a tag written into an empty note would make one.
 *
 * 4. NEVER WHILE THE RECORDER IS LIVE. The generated RustWebChromeClient has one `permissionListener` shared by the
 *    microphone, geolocation and camera prompts: a location ask raised while the recorder's getUserMedia prompt is
 *    pending overwrites the microphone's callback. `locate` is called from three places only, none of them the
 *    recorder: a note's More sheet, the Location pane, and the shell after a capture has ended and its screen has
 *    gone (shell/useCaptureRoute.ts, App.tsx's new note).
 *
 * On the Mac the WebView never answers `getCurrentPosition`, success or error (wry's WKUIDelegate implements no
 * geolocation decision method and macOS has no default position provider), so a page that waits there waits for
 * ever: the Mac is answered `mac` before anything is asked, draws what the phone tagged, and CoreLocation is a
 * follow-up. An older Android binary reached over the air declares no location permission in its manifest, and
 * Android denies an undeclared permission with no dialog, indistinguishable from a refusal: that is `unavailable`.
 */

export type LocateFailure = 'refused' | 'blocked' | 'unavailable' | 'timeout' | 'none' | 'mac' | 'local-only';

/** Why a fix did not come: `locate` rejects with one of these. */
export class LocateError extends Error {
  constructor(readonly why: LocateFailure) {
    super(why);
    this.name = 'LocateError';
  }
}

/** The failure a rejected `locate` carries, and `unavailable` for anything else. */
export function whyLocateFailed(failure: unknown): LocateFailure {
  return failure instanceof LocateError ? failure.why : 'unavailable';
}

/** The native generation whose binary asks Nominatim with the app's own User-Agent (src-tauri/src/geocode.rs). */
export const LOCATION_GENERATION = 20;
/** How long the device may take over a fix. */
const FIX_TIMEOUT_MS = 15_000;
/** A fix this recent is taken as it is: a person does not move far in two minutes. */
const FIX_MAX_AGE_MS = 120_000;
/** How long the page waits for Android to answer its prompt before reading the state as it stands. */
const ASK_TIMEOUT_MS = 90_000;
/** A pending tag older than this is forgotten on read. */
const PENDING_MS = 24 * 60 * 60_000;
/** Nominatim's usage policy: at most one request a second, across the app. */
const NOMINATIM_GAP_MS = 1100;
const PENDING_KEY = 'glyph-geotag-pending';
const REFUSED_KEY = 'glyph-geotag-refused';

// ---- the fix -------------------------------------------------------------------------------------

type Access = 'granted' | 'approximate' | 'ask' | 'blocked';

/** Whether this Android binary has the bridge that declares the permission (native generation 20). */
function androidBridge(): boolean {
  return isAndroid && isTauri() && typeof window.GlyphHost?.locationAccess === 'function';
}

function readAccess(): Access {
  try {
    const answer = window.GlyphHost?.locationAccess?.();
    return answer === 'granted' || answer === 'approximate' || answer === 'blocked' ? answer : 'ask';
  } catch {
    return 'ask';
  }
}

/** Whether a fix can be asked for here at all, and why not: read before anything is asked. */
export function canLocate(): { ok: true } | { ok: false; why: LocateFailure } {
  if (preferences().localOnly) return { ok: false, why: 'local-only' };
  if (isMacApp) return { ok: false, why: 'mac' };
  if (typeof navigator === 'undefined' || !navigator.geolocation) return { ok: false, why: 'none' };
  if (isAndroid && isTauri() && !androidBridge()) return { ok: false, why: 'unavailable' };
  return { ok: true };
}

/** Raises Android's prompt through the activity's own request code, and waits for its answer (or for the app to come back). */
function askAndroid(): Promise<void> {
  return new Promise((resolve) => {
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      window.clearTimeout(timer);
      document.removeEventListener('visibilitychange', onVisible);
      unanswer();
      resolve();
    };
    const onVisible = () => {
      if (document.visibilityState === 'visible') finish();
    };
    const unanswer = answerHost('location', finish);
    const timer = window.setTimeout(finish, ASK_TIMEOUT_MS);
    document.addEventListener('visibilitychange', onVisible);
    try {
      window.GlyphHost?.requestLocation?.();
    } catch {
      finish();
    }
  });
}

/**
 * Where the device is now. `quiet` never raises a prompt: on a locked phone a recording's tag is taken only where the
 * permission is already held, since a dialog over the lock screen is nobody's choice.
 */
export async function locate({ quiet = false }: { quiet?: boolean } = {}): Promise<Fix> {
  const can = canLocate();
  if (!can.ok) throw new LocateError(can.why);
  if (androidBridge()) {
    let state = readAccess();
    if (state === 'blocked') throw new LocateError('blocked');
    if (state === 'ask') {
      if (quiet) throw new LocateError('refused');
      await askAndroid();
      state = readAccess();
    }
    if (state === 'blocked') throw new LocateError('blocked');
    if (state === 'ask') throw new LocateError('refused');
  }
  return new Promise<Fix>((resolve, reject) => {
    navigator.geolocation.getCurrentPosition(
      (position) => resolve({ lat: position.coords.latitude, lon: position.coords.longitude, accuracy: position.coords.accuracy, at: position.timestamp }),
      (failure) => reject(new LocateError(failure.code === 1 ? 'refused' : failure.code === 3 ? 'timeout' : 'unavailable')),
      { enableHighAccuracy: false, timeout: FIX_TIMEOUT_MS, maximumAge: FIX_MAX_AGE_MS },
    );
  });
}

// ---- the gates ------------------------------------------------------------------------------------

/** Whether a tagged note draws OpenStreetMap's tiles: the switch, and never under Local only. */
export function canShowTiles(): boolean {
  const prefs = preferences();
  return !prefs.localOnly && prefs.mapTiles;
}

/** Whether a place's name may be asked for: the switch, never under Local only, and in the app a binary that asks as itself. */
export async function canAskPlace(): Promise<boolean> {
  const prefs = preferences();
  if (!prefs.placeNames || prefs.localOnly) return false;
  return isTauri() ? hasNativeGeneration(LOCATION_GENERATION) : true;
}

// ---- the watchers --------------------------------------------------------------------------------

export type TagEvent = { kind: 'place'; place: string; lat: number; lon: number } | { kind: 'pending' };

const watchers = new Map<string, Set<(event: TagEvent) => void>>();

/** The note's screen, following its tag: a name arriving, or a tag now waiting to be written. Answers the way to stop. */
export function watchTag(noteId: string, listener: (event: TagEvent) => void): () => void {
  const set = watchers.get(noteId) ?? new Set();
  set.add(listener);
  watchers.set(noteId, set);
  return () => {
    set.delete(listener);
    if (!set.size) watchers.delete(noteId);
  };
}

function watched(noteId: string): boolean {
  return (watchers.get(noteId)?.size ?? 0) > 0;
}

function tell(noteId: string, event: TagEvent): void {
  for (const listener of watchers.get(noteId) ?? []) listener(event);
}

// ---- the place's name ----------------------------------------------------------------------------

/** The coordinates a name is asked for, and kept under: three decimals, or two for a rough tag. */
function askedAs(tag: GeoTag): { lat: number; lon: number; zoom: 12 | 15 } {
  const digits = tag.rough ? 2 : 3;
  return { lat: Number(tag.lat.toFixed(digits)), lon: Number(tag.lon.toFixed(digits)), zoom: tag.rough ? 12 : 15 };
}

const keyOf = (tag: GeoTag) => {
  const { lat, lon, zoom } = askedAs(tag);
  return `${lat},${lon}@${zoom}`;
};

/** Names that came this run, by the coordinates asked: a note closed when its name arrived reads it at the next open. */
const known = new Map<string, string>();
/** Asks that failed this run: not asked again until the tag is made again. */
const failed = new Set<string>();
/** Notes with an ask in flight. */
const asking = new Set<string>();
let nextAllowedAt = 0;

/** A name that came for these coordinates while nothing was open to take it, or null. */
export function placeFor(tag: GeoTag): string | null {
  return known.get(keyOf(tag)) ?? null;
}

async function askNominatim(tag: GeoTag): Promise<PlaceAnswer> {
  const { lat, lon, zoom } = askedAs(tag);
  const lang = typeof navigator === 'undefined' ? 'en' : navigator.language || 'en';
  if (isTauri()) return invoke<PlaceAnswer>('geocode_place', { lat, lon, zoom, lang });
  const url = `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lon}&zoom=${zoom}&addressdetails=1`;
  const response = await fetch(url, { headers: { Accept: 'application/json', 'Accept-Language': lang } });
  if (!response.ok) throw new Error(`Nominatim answered ${response.status}.`);
  return (await response.json()) as PlaceAnswer;
}

/** A name that arrived for a note that is closed: written straight in, unless a pass is queued to rewrite it. */
async function writePlaceClosed(noteId: string, tag: GeoTag, place: string): Promise<void> {
  if (refinePending(noteId)) return;
  const fresh = await getNote(noteId).catch(() => null);
  if (!fresh) return;
  const now = geoTagOf(fresh.body);
  if (!now || now.place || now.lat !== tag.lat || now.lon !== tag.lon) return;
  await updateNote(noteId, withGeoTag(fresh.body, { ...now, place }), fresh.revision ?? 1).catch(() => undefined);
}

/**
 * Asks for the tag's name, once, for a tag this device made (a note's Add my location, or a new note's tag): a no-op
 * for a tag that has one, one already known, one that failed this run, or where asking is not allowed. The note's
 * screen is told when it arrives; a closed note is written; a name nobody could take waits in memory (`placeFor`).
 */
export function wantPlace(noteId: string, tag: GeoTag): void {
  if (tag.place !== null) return;
  const key = keyOf(tag);
  const had = known.get(key);
  if (had) {
    tell(noteId, { kind: 'place', place: had, lat: tag.lat, lon: tag.lon });
    return;
  }
  if (failed.has(key) || asking.has(noteId)) return;
  asking.add(noteId);
  void (async () => {
    if (!(await canAskPlace())) return;
    const wait = Math.max(0, nextAllowedAt - Date.now());
    nextAllowedAt = Date.now() + wait + NOMINATIM_GAP_MS;
    if (wait) await new Promise((resolve) => window.setTimeout(resolve, wait));
    let place: string | null;
    try {
      place = shortPlace(await askNominatim(tag), tag.rough);
    } catch {
      // Offline, refused, or an answer that was not JSON: a coordinate until the location is added again.
      place = null;
    }
    if (!place) {
      failed.add(key);
      return;
    }
    known.set(key, place);
    const pending = pendingTag(noteId);
    if (pending && pending.lat === tag.lat && pending.lon === tag.lon) setPendingTag(noteId, { ...pending, place });
    if (watched(noteId)) tell(noteId, { kind: 'place', place, lat: tag.lat, lon: tag.lon });
    else if (!pending) await writePlaceClosed(noteId, tag, place);
  })().finally(() => asking.delete(noteId));
}

// ---- the tag waiting for the better words --------------------------------------------------------

interface Pending {
  lat: number;
  lon: number;
  rough: boolean;
  place?: string;
  at: number;
}

function readPending(): Record<string, Pending> {
  const all = readStored<Record<string, Pending>>(PENDING_KEY, {}, (raw) => (raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as Record<string, Pending>) : null));
  const now = Date.now();
  const kept: Record<string, Pending> = {};
  for (const [id, entry] of Object.entries(all)) {
    if (!entry || typeof entry.lat !== 'number' || typeof entry.lon !== 'number' || typeof entry.at !== 'number') continue;
    if (now - entry.at > PENDING_MS) continue;
    kept[id] = entry;
  }
  return kept;
}

/** The tag waiting to be written into `noteId`, or null. */
export function pendingTag(noteId: string): GeoTag | null {
  const entry = readPending()[noteId];
  return entry ? { lat: entry.lat, lon: entry.lon, rough: Boolean(entry.rough), place: entry.place ?? null } : null;
}

/** Keeps `tag` aside for `noteId`, or (null) forgets it: the note went to the trash, its words were undone, or the tag landed. */
export function setPendingTag(noteId: string, tag: GeoTag | null): void {
  const all = readPending();
  if (tag) all[noteId] = { lat: tag.lat, lon: tag.lon, rough: tag.rough, ...(tag.place ? { place: tag.place } : {}), at: Date.now() };
  else if (!(noteId in all)) return;
  else delete all[noteId];
  writeStored(PENDING_KEY, Object.keys(all).length ? all : null);
}

/** Whether the words after the front matter say anything. */
function hasWords(body: string): boolean {
  return body.slice(frontMatterOffset(body)).trim() !== '';
}

/**
 * The body with the note's pending tag written in, when it may land: not while a better-words pass is queued or
 * running for the note, not while a review is live for it (`live.reviewing`), and not into a note with no words yet.
 * Null when it may not, or there is nothing waiting.
 */
export function settleTag(noteId: string, body: string, live: { reviewing: boolean }): string | null {
  const tag = pendingTag(noteId);
  if (!tag) return null;
  if (live.reviewing || refinePending(noteId) || !hasWords(body)) return null;
  return withGeoTag(body, tag);
}

/** Why the last automatic tag did not come, kept so the note's sheet can say so and the device is not asked again. */
interface Refusal {
  why: LocateFailure;
  at: number;
}

/** The refusal the last automatic ask met, if any: the note's More sheet says why the note was not tagged. */
export function autoTagRefusal(): LocateFailure | null {
  const kept = readStored<Refusal | null>(REFUSED_KEY, null, (raw) => (raw && typeof raw === 'object' && typeof (raw as Refusal).why === 'string' ? (raw as Refusal) : null));
  return kept?.why ?? null;
}

/** A fix came, or the person allowed location: the automatic ask may be made again. */
export function forgetRefusal(): void {
  writeStored(REFUSED_KEY, null);
}

/**
 * Tags every note in `ids` with the fix once it comes: a note whose screen is open is handed the tag through its
 * editor (or holds it, section 3 of the header); a closed note with words, no pass queued and no review live is
 * written now; anything else waits as a pending tag. The name is then asked for, since this device made the tag.
 * Answers why the fix did not come, or null.
 */
export async function tagNewNotes(ids: readonly string[], fix: Promise<Fix>, held: { reviewing: boolean }): Promise<LocateFailure | null> {
  if (!ids.length) return null;
  let position: Fix;
  try {
    position = await fix;
  } catch (failure) {
    const why = whyLocateFailed(failure);
    if (why === 'refused' || why === 'blocked') writeStored(REFUSED_KEY, { why, at: Date.now() } satisfies Refusal);
    return why;
  }
  forgetRefusal();
  const tag = tagOf(position);
  for (const id of ids) {
    setPendingTag(id, tag);
    if (watched(id)) {
      tell(id, { kind: 'pending' });
    } else if (!held.reviewing && !refinePending(id)) {
      const fresh = await getNote(id).catch(() => null);
      if (fresh && geoTagOf(fresh.body)) {
        // Tagged already, by hand or by another device: an existing tag is never written over.
        setPendingTag(id, null);
        continue;
      }
      if (fresh && hasWords(fresh.body)) {
        try {
          await updateNote(id, withGeoTag(fresh.body, tag), fresh.revision ?? 1);
          setPendingTag(id, null);
        } catch {
          // Another writer got there first: the tag waits for the note's next open.
        }
      }
    }
    wantPlace(id, tag);
  }
  return null;
}

/**
 * Tags new notes the person made here, when Settings says so (`tagNewNotes`): never under Local only, and not again
 * after a refusal until the person allows location (the note's sheet says why the note was not tagged). `quiet`
 * never raises a prompt (a locked phone).
 */
export function tagNewNotesIfWanted(ids: readonly string[], held: { reviewing: boolean }, { quiet = false }: { quiet?: boolean } = {}): Promise<LocateFailure | null> {
  const prefs = preferences();
  if (!ids.length || !prefs.tagNewNotes || prefs.localOnly) return Promise.resolve(null);
  const refused = autoTagRefusal();
  if (refused) return Promise.resolve(refused);
  return tagNewNotes(ids, locate({ quiet }), held);
}

// ---- opening the place ---------------------------------------------------------------------------

/**
 * Where a tap on the card goes, per platform, carrying the place name or the coordinates and never the note's title
 * (a title goes to whichever app takes the intent, and a maps app keeps its searches): the phone's maps chooser on an
 * Android binary that has the opener's `geo:` scope (the one whose bridge declares the permission), Apple Maps on the
 * Mac, and openstreetmap.org everywhere else, which carries no label.
 */
export function placeUrl(tag: GeoTag): string {
  const { lat, lon } = tag;
  if (androidBridge()) return `geo:${lat},${lon}?q=${lat},${lon}${tag.place ? `(${encodeURIComponent(tag.place)})` : ''}`;
  if (isMacApp) return `https://maps.apple.com/?ll=${lat},${lon}&q=${encodeURIComponent(tag.place ?? coordsText(tag))}`;
  const zoom = tag.rough ? 12 : 15;
  return `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}#map=${zoom}/${lat}/${lon}`;
}

/** Opens the place in the device's maps app, or the browser. */
export async function openPlace(tag: GeoTag): Promise<void> {
  await openLink(placeUrl(tag));
}
