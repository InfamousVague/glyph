import { isUntouched } from './untouched.ts';
import { refinePending } from '../capture/refine.ts';
import { frontMatterOffset } from './frontMatter.ts';
import { geoTagOf, shortPlace, tagOf, withGeoTag, type Fix, type GeoTag, type PlaceAnswer } from './geotag.ts';
import { answerHost } from './host.ts';
import { hasNativeGeneration } from './nativeGeneration.ts';
import { hasLocationBridge } from './placeLink.ts';
import { isAndroid, isIOS, isMacApp } from './platform.ts';
import { preferences } from './preferences.ts';
import { readStored, writeStored } from './stored.ts';
import { getNote, updateNote } from './store.ts';
import { invoke, isTauri } from './tauri.ts';

/**
 * Where the device is, and what becomes of that (Matt: "Add the ability to geotag notes and show a map card embedded
 * on the note"; then "Add a setting to geotag notes by default and turn it on"): the position fix, the place's name
 * asked of OpenStreetMap, and the tag that waits for a recording's better words. The tag itself, as the note carries
 * it, is core/geotag.ts, and where a tapped map goes is core/placeLink.ts (the shared page draws the card too).
 * Gated the way core/linkPreview.ts is: nothing leaves the device unless the person chose it. Four rules, each with
 * its reason:
 *
 * 1. THE FIX IS A NETWORK CALL, so Local only turns it off too. On Android and the web `getCurrentPosition` with
 *    `enableHighAccuracy: false` goes to the fused provider, which sends nearby Wi-Fi and cell identifiers to Google's
 *    location service (Firefox to Mozilla's, Safari to Apple's). A GPS-only fix - thirty seconds outdoors, nothing
 *    indoors - is not the same feature, so the app does not pretend it is.
 *
 * 2. THE NAME IS ASKED ONCE, FOR A TAG MADE HERE, at three decimals (about 100 m, enough for a street), and only once
 *    the tag is in the note: a tag still waiting (below), for a draft that may never get a word, sends nothing.
 *    Never for a note that arrived by sync, a forked share or one the MCP wrote: the viewer's IP address is never
 *    paired with coordinates they did not choose. Nominatim's usage policy: one request a second, and an identifying
 *    User-Agent or Referer. So one ask per place at a time, a second apart across the app, and the switches read
 *    again after the wait, since Local only may have been turned on during it. The page cannot set a User-Agent (a
 *    forbidden header), the Android page's Referer is `http://tauri.localhost/` and the Mac's page sends none, so in
 *    the app the ask goes through Rust (src-tauri/src/geocode.rs, native generation 20), which names the app; on the
 *    web the page's own origin is the name, and the page fetches for itself. A place a person adds with the + beside
 *    the line is asked for from the moment its fix comes, while its note is open and its spot is kept: the person
 *    chose these coordinates and this note seconds before (`placeName`), and asking then lets the place and its name
 *    land as one write and one Undo.
 *
 * 3. A TAG WAITS FOR THE BETTER WORDS. capture/refine.ts writes them only if the note still reads as Done saved it,
 *    and builds the whole body from the take, so a `location:` stamped after Done would either drop them silently or
 *    be written over. The review (ai/useNoteReview.ts) has the same compare one step later, when it hands its job
 *    back. So a tag for a new recording is kept aside (`setPendingTag`) while a pass is queued or a review is live,
 *    and it is written once the pass has landed or the review has handed back: by the note's screen when it is open,
 *    and otherwise here (`settleWaitingTags`), when a pass finishes, when a note is left, and at launch. The card is
 *    drawn from the waiting tag meanwhile. A pending tag lives a day (longer while its pass is still queued), and
 *    goes with the note to the trash and with the recording's Undo. It also waits for a note's first words: a typed
 *    new note is a draft with no file until it has some (docs/LIBRARY.md), and a tag written into an empty note
 *    would make one; a draft left without any takes its waiting tag with it. A journal's entry has words from birth,
 *    its template's, so its tag waits for the first of its own instead (`hasOwnWords`): an entry nobody wrote in is
 *    taken back when it is left (core/untouched.ts), and no place lands on it or is named first.
 *
 * 4. NEVER WHILE THE RECORDER IS LIVE. The generated RustWebChromeClient has one `permissionListener` shared by the
 *    microphone, geolocation and camera prompts: a location ask raised while the recorder's getUserMedia prompt is
 *    pending overwrites the microphone's callback. `locate` is called from four places only, none of them the
 *    recorder: a note's More sheet, the Location pane, a journal's place switch (book/TemplatePicker.tsx), and the
 *    shell after a capture has ended and its screen has gone (shell/useCaptureRoute.ts, App.tsx's new note and new
 *    entry).
 *
 * The first automatic ask on a device that has never answered the prompt is introduced in the app's own words first
 * (`introduce`, a toast with "Allow location" on it), so the system's dialog comes from a press rather than over a
 * blank note.
 *
 * On the Mac the WebView never answers `getCurrentPosition`, success or error (wry's WKUIDelegate implements no
 * geolocation decision method and macOS has no default position provider), so a page that waits there waits for
 * ever: the Mac is answered `mac` before anything is asked, draws what the phone tagged, and CoreLocation is a
 * follow-up. An older Android binary reached over the air declares no location permission in its manifest, and
 * Android denies an undeclared permission with no dialog, indistinguishable from a refusal: that is `unavailable`.
 * The iPhone app declares no location permission either (only the microphone's, src-tauri/Info.ios.plist), so its
 * WebView refuses every ask, and Rust's geocode refuses there too: that is `ios`, answered before anything is asked.
 */

export type LocateFailure = 'refused' | 'blocked' | 'unavailable' | 'timeout' | 'none' | 'mac' | 'ios' | 'local-only';

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
/**
 * The most a fix may take, prompt and all. The device's own `timeout` does not start while a browser's permission
 * prompt waits for an answer, so a prompt left open would otherwise hold the promise, and the note's "Finding where
 * you are.", for ever.
 */
const FIX_CAP_MS = 60_000;
/** How long the page waits for Android to answer its prompt before reading the state as it stands. */
const ASK_TIMEOUT_MS = 90_000;
/** A pending tag older than this is forgotten on read. */
const PENDING_MS = 24 * 60 * 60_000;
/** Nominatim's usage policy: at most one request a second, across the app. */
const NOMINATIM_GAP_MS = 1100;
/** A note just left: its last save lands before a waiting tag is written into it. */
const LEFT_MS = 2000;
const PENDING_KEY = 'glyph-geotag-pending';
const REFUSED_KEY = 'glyph-geotag-refused';

// ---- the fix -------------------------------------------------------------------------------------

type Access = 'granted' | 'approximate' | 'ask' | 'blocked';

/** Whether this Android binary has the bridge that declares the permission (native generation 20). */
const androidBridge = hasLocationBridge;

function readAccess(): Access {
  try {
    const answer = window.GlyphHost?.locationAccess?.();
    return answer === 'granted' || answer === 'approximate' || answer === 'blocked' ? answer : 'ask';
  } catch {
    return 'ask';
  }
}

/**
 * Whether this device and this build can find where they are at all, whatever the switches say: the Mac's WebView
 * never answers, the iPhone app declares no permission, a browser may have no geolocation, and an older Android
 * binary has no bridge. A row that can never work is not drawn (the + beside the line's list, editor/addRows.ts).
 */
export function locateHere(): { ok: true } | { ok: false; why: LocateFailure } {
  if (isMacApp) return { ok: false, why: 'mac' };
  if (isIOS && isTauri()) return { ok: false, why: 'ios' };
  if (typeof navigator === 'undefined' || !navigator.geolocation) return { ok: false, why: 'none' };
  if (isAndroid && isTauri() && !androidBridge()) return { ok: false, why: 'unavailable' };
  return { ok: true };
}

/** Whether a fix can be asked for here at all, and why not: read before anything is asked. */
export function canLocate(): { ok: true } | { ok: false; why: LocateFailure } {
  if (preferences().localOnly) return { ok: false, why: 'local-only' };
  return locateHere();
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
 * permission is already held, since a dialog over the lock screen is nobody's choice. A quiet ask that would have
 * needed the prompt answers `unavailable`, not `refused`: nobody refused anything, and the next new note may ask.
 */
export async function locate({ quiet = false }: { quiet?: boolean } = {}): Promise<Fix> {
  const can = canLocate();
  if (!can.ok) throw new LocateError(can.why);
  if (androidBridge()) {
    let state = readAccess();
    if (state === 'blocked') throw new LocateError('blocked');
    if (state === 'ask') {
      if (quiet) throw new LocateError('unavailable');
      await askAndroid();
      state = readAccess();
    }
    if (state === 'blocked') throw new LocateError('blocked');
    if (state === 'ask') throw new LocateError('refused');
  }
  return new Promise<Fix>((resolve, reject) => {
    const cap = window.setTimeout(() => reject(new LocateError('timeout')), FIX_CAP_MS);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        window.clearTimeout(cap);
        resolve({ lat: position.coords.latitude, lon: position.coords.longitude, accuracy: position.coords.accuracy, at: position.timestamp });
      },
      (failure) => {
        window.clearTimeout(cap);
        reject(new LocateError(failure.code === 1 ? 'refused' : failure.code === 3 ? 'timeout' : 'unavailable'));
      },
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
    if (set.size) return;
    watchers.delete(noteId);
    // The note left: a tag still waiting for it is written in once its last save has landed, where it may be.
    if (pendingTag(noteId)) window.setTimeout(() => void settleClosed(noteId), LEFT_MS);
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
/** Asks in flight, by the coordinates asked: a second note at the same place waits for the same answer. */
const inflight = new Map<string, Promise<string | null>>();
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

/**
 * The name for the tag's coordinates, asked of Nominatim: one ask per place at a time, a second after the last across
 * the app, and not at all if asking stopped being allowed while it waited its turn (nothing is counted failed then).
 * Null when nothing was asked or nothing usable came.
 */
function nameFor(tag: GeoTag): Promise<string | null> {
  const key = keyOf(tag);
  const already = inflight.get(key);
  if (already) return already;
  const asked = (async () => {
    if (!(await canAskPlace())) return null;
    const wait = Math.max(0, nextAllowedAt - Date.now());
    nextAllowedAt = Date.now() + wait + NOMINATIM_GAP_MS;
    if (wait) await new Promise((resolve) => window.setTimeout(resolve, wait));
    if (!(await canAskPlace())) return null;
    let place: string | null;
    try {
      place = shortPlace(await askNominatim(tag), tag.rough);
    } catch {
      // Offline, refused, or an answer that was not JSON: a coordinate until the location is added again.
      place = null;
    }
    if (place) known.set(key, place);
    else failed.add(key);
    return place;
  })().finally(() => inflight.delete(key));
  inflight.set(key, asked);
  return asked;
}

/**
 * The name for a place the + beside the line is adding (editor/NoteScreen.tsx): what is already known first, with no
 * ask; nothing for a place whose ask failed this run; otherwise asked once, on Nominatim's terms (`nameFor`). Null
 * when none may be asked or none came. Rule 2 in the header says why this may ask before the place is written.
 */
export function placeName(tag: GeoTag): Promise<string | null> {
  const key = keyOf(tag);
  const had = known.get(key);
  if (had) return Promise.resolve(had);
  if (failed.has(key)) return Promise.resolve(null);
  return nameFor(tag);
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

/** A name for `noteId`'s tag, where it can be taken: the note's screen, the tag still waiting, or the closed note. */
async function deliver(noteId: string, tag: GeoTag, place: string): Promise<void> {
  const pending = pendingTag(noteId);
  if (pending && pending.lat === tag.lat && pending.lon === tag.lon) setPendingTag(noteId, { ...pending, place });
  if (watched(noteId)) tell(noteId, { kind: 'place', place, lat: tag.lat, lon: tag.lon });
  else if (!pending) await writePlaceClosed(noteId, tag, place);
}

/**
 * Asks for the tag's name, once, for a tag this device made and has written into its note (a note's Add my location,
 * or a new note's tag once it lands): a no-op for a tag that has one, one that failed this run, or where asking is not
 * allowed. The note's screen is told when it arrives; a closed note is written; a name nobody could take waits in
 * memory (`placeFor`).
 */
export function wantPlace(noteId: string, tag: GeoTag): void {
  if (tag.place !== null) return;
  const key = keyOf(tag);
  const had = known.get(key);
  if (had) {
    void deliver(noteId, tag, had);
    return;
  }
  if (failed.has(key) || asking.has(noteId)) return;
  asking.add(noteId);
  void nameFor(tag)
    .then((place) => (place ? deliver(noteId, tag, place) : undefined))
    .finally(() => asking.delete(noteId));
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
    // A day, or for as long as the note's pass is still queued: the tag is what the pass is waited for.
    if (now - entry.at > PENDING_MS && !refinePending(id)) continue;
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
 * Whether the words are the person's own: any at all, and not a journal's entry still as this device made it from its
 * template (core/untouched.ts). An entry has words from birth, its date and its time, and a tag landing on one nobody
 * wrote in would keep it, and ask its name of Nominatim, for an entry about to be taken back.
 */
function hasOwnWords(noteId: string, body: string, note?: Parameters<typeof isUntouched>[2]): boolean {
  return hasWords(body) && !isUntouched(noteId, body, note);
}

/**
 * The body with the note's pending tag written in, when it may land: not while a better-words pass is queued or
 * running for the note, not while a review is live for it (`live.reviewing`), and not into a note with no words yet.
 * Null when it may not, or there is nothing waiting.
 */
export function settleTag(noteId: string, body: string, live: { reviewing: boolean }): string | null {
  const tag = pendingTag(noteId);
  if (!tag) return null;
  if (live.reviewing || refinePending(noteId) || !hasOwnWords(noteId, body)) return null;
  return withGeoTag(body, tag);
}

/** Why the last automatic tag did not come, kept so the note's sheet can say so and the device is not asked again. */
interface Refusal {
  why: LocateFailure;
  at: number;
}

/** A refusal is about the notes made from a little before it (the one whose ask it answered) onwards. */
const REFUSAL_REACH_MS = 5 * 60_000;

function readRefusal(): Refusal | null {
  return readStored<Refusal | null>(REFUSED_KEY, null, (raw) => (raw && typeof raw === 'object' && typeof (raw as Refusal).why === 'string' && typeof (raw as Refusal).at === 'number' ? (raw as Refusal) : null));
}

/** The refusal the last automatic ask met, if any. */
export function autoTagRefusal(): LocateFailure | null {
  return readRefusal()?.why ?? null;
}

/**
 * Why a note made at `createdAt` was not tagged on its own, if a refusal explains it: the note's More sheet says so.
 * A note older than the refusal was never going to be tagged (existing notes are left as they are), so it is told
 * nothing.
 */
export function refusedFor(createdAt: number): LocateFailure | null {
  const kept = readRefusal();
  return kept && createdAt >= kept.at - REFUSAL_REACH_MS ? kept.why : null;
}

/** An automatic ask was refused, or the phone blocks location: no automatic ask is made again until it is allowed. */
export function rememberRefusal(why: LocateFailure): void {
  if (why === 'refused' || why === 'blocked') writeStored(REFUSED_KEY, { why, at: Date.now() } satisfies Refusal);
}

/**
 * Where location is allowed again after a refusal, as a sentence's start: the phone's settings on Android, and the
 * browser's own for a page, where Ghost.md is the site and not an app.
 */
export function allowLocationWhere(): string {
  return androidBridge() ? 'Allow location for Ghost.md in the phone’s settings' : 'Allow location for this site in the browser’s settings';
}

/** A fix came, or the person allowed location: the automatic ask may be made again. */
export function forgetRefusal(): void {
  writeStored(REFUSED_KEY, null);
}

/**
 * Whether a kept refusal still stands. Allowing location in the phone's settings is a choice too: where the device
 * can say it is allowed now (Android's bridge, the browser's permissions), the refusal is forgotten and the ask made.
 */
async function stillRefused(): Promise<LocateFailure | null> {
  const why = autoTagRefusal();
  if (!why) return null;
  let allowed = false;
  if (androidBridge()) {
    const state = readAccess();
    allowed = state === 'granted' || state === 'approximate';
  } else if (typeof navigator !== 'undefined' && typeof navigator.permissions?.query === 'function') {
    allowed = await navigator.permissions
      .query({ name: 'geolocation' })
      .then((status) => status.state === 'granted')
      .catch(() => false);
  }
  if (!allowed) return why;
  forgetRefusal();
  return null;
}

/**
 * A waiting tag written into its note where no screen holds it: once no pass is queued for it and it has words, and
 * unless it says where it was written already (an existing tag is never written over). A note that is gone takes its
 * waiting tag with it. The name is asked then, since the tag has landed. Answers whether the tag landed.
 */
async function settleClosed(id: string): Promise<boolean> {
  const tag = pendingTag(id);
  if (!tag || watched(id)) return false;
  if (refinePending(id)) {
    // Still waiting for the pass: its day starts again, so the tag is there when the pass lands, however late.
    setPendingTag(id, tag);
    return false;
  }
  let fresh: Awaited<ReturnType<typeof getNote>>;
  try {
    fresh = await getNote(id);
  } catch {
    // The store did not answer: the tag waits for the next look.
    return false;
  }
  if (!fresh || geoTagOf(fresh.body)) {
    setPendingTag(id, null);
    return false;
  }
  if (!hasOwnWords(id, fresh.body, fresh)) return false;
  try {
    await updateNote(id, withGeoTag(fresh.body, tag), fresh.revision ?? 1);
  } catch {
    // Another writer got there first: the tag waits for the next look.
    return false;
  }
  setPendingTag(id, null);
  wantPlace(id, tag);
  return true;
}

let sweeping: Promise<number> | null = null;
let sweepAgain = false;

/**
 * Every waiting tag whose note is closed, written in where it may now land (`settleClosed`): called when a better-words
 * pass has finished and at launch (shell/useHousekeeping.ts), so a recording's tag reaches the note, the home card,
 * sync and the other devices without the note being opened again. Answers how many landed, so the list is read
 * again only when one did.
 */
export function settleWaitingTags(): Promise<number> {
  if (sweeping) {
    sweepAgain = true;
    return sweeping;
  }
  sweeping = (async () => {
    let landed = 0;
    do {
      sweepAgain = false;
      for (const id of Object.keys(readPending())) if (await settleClosed(id)) landed += 1;
    } while (sweepAgain);
    return landed;
  })().finally(() => {
    sweeping = null;
  });
  return sweeping;
}

/** A tag this device made for a note whose screen has gone (left while the fix was coming): kept, and written where it may land. */
export function landTag(noteId: string, tag: GeoTag): void {
  setPendingTag(noteId, tag);
  if (watched(noteId)) tell(noteId, { kind: 'pending' });
  else void settleClosed(noteId);
}

/**
 * Tags every note in `ids` with the fix once it comes: a note whose screen is open is handed the tag through its
 * editor (or holds it, section 3 of the header); a closed note with words, no pass queued and no review live is
 * written now; anything else waits as a pending tag. The name is asked for once the tag is in the note. Answers why
 * the fix did not come, or null.
 */
export async function tagNewNotes(ids: readonly string[], fix: Promise<Fix>, held: { reviewing: boolean }): Promise<LocateFailure | null> {
  if (!ids.length) return null;
  let position: Fix;
  try {
    position = await fix;
  } catch (failure) {
    const why = whyLocateFailed(failure);
    rememberRefusal(why);
    return why;
  }
  forgetRefusal();
  const tag = tagOf(position);
  for (const id of ids) {
    setPendingTag(id, tag);
    if (watched(id)) tell(id, { kind: 'pending' });
    else if (!held.reviewing) await settleClosed(id);
  }
  return null;
}

/** Whether a fix here would raise the system's prompt: the person has not answered it yet. */
async function wouldPrompt(): Promise<boolean> {
  if (androidBridge()) return readAccess() === 'ask';
  if (typeof navigator !== 'undefined' && typeof navigator.permissions?.query === 'function') {
    return navigator.permissions
      .query({ name: 'geolocation' })
      .then((status) => status.state === 'prompt')
      .catch(() => true);
  }
  return true;
}

/**
 * The system's prompt, raised from a press, where it can be asked and has never been answered: a journal's "With
 * where you are" turned on (book/TemplatePicker.tsx), so its first entry is not the first ask. A fix forgets a kept
 * refusal; a refusal is kept, as the new notes' ask keeps one. Answers why no fix came, or null, and null too where
 * nothing was asked.
 */
export async function askFromPress(): Promise<LocateFailure | null> {
  if (!canLocate().ok || !(await wouldPrompt())) return null;
  try {
    await locate();
    forgetRefusal();
    return null;
  } catch (failure) {
    const why = whyLocateFailed(failure);
    rememberRefusal(why);
    return why;
  }
}

/** The first automatic ask of this run was introduced: a person who let it pass is not asked again until the next. */
let introduced = false;

/**
 * Tags new notes the person made here, when Settings says so (`tagNewNotes`): never under Local only, and not again
 * after a refusal until the person allows location (the note's sheet says why the note was not tagged). `quiet`
 * never raises a prompt (a locked phone). Where the prompt has never been answered, `introduce` says what the ask is
 * for in the app's words and hands over the ask for a press to make, once a run: the system's dialog never comes
 * over a blank note unannounced.
 */
export async function tagNewNotesIfWanted(
  ids: readonly string[],
  held: { reviewing: boolean },
  { quiet = false, introduce }: { quiet?: boolean; introduce?: (allow: () => void) => void } = {},
): Promise<LocateFailure | null> {
  const prefs = preferences();
  if (!ids.length || !prefs.tagNewNotes || prefs.localOnly) return null;
  const refused = await stillRefused();
  if (refused) return refused;
  if (!quiet && introduce && canLocate().ok && (await wouldPrompt())) {
    if (introduced) return null;
    introduced = true;
    introduce(() => void tagNewNotes(ids, locate(), held));
    return null;
  }
  return tagNewNotes(ids, locate({ quiet }), held);
}

/** The first ask for a journal's entries this run was introduced: its own, not the new notes' (below). */
let entryIntroduced = false;

/**
 * Tags a journal's new entries with where they were written (docs/DESIGN.md §142), the journal's switch being the
 * choice: `tagNewNotesIfWanted` without its check of Tag new notes, and with an introduction of its own. Shared, a
 * note's introduction let pass earlier in the run would leave every entry untagged with no refusal kept to say why.
 * Everything that protects the device is the same: never under Local only, not again after a refusal until location
 * is allowed, `quiet` over a locked phone, and the system's prompt only from a press.
 */
export async function tagEntryIfWanted(
  ids: readonly string[],
  held: { reviewing: boolean },
  { quiet = false, introduce }: { quiet?: boolean; introduce?: (allow: () => void) => void } = {},
): Promise<LocateFailure | null> {
  if (!ids.length || preferences().localOnly) return null;
  const refused = await stillRefused();
  if (refused) return refused;
  if (!quiet && introduce && canLocate().ok && (await wouldPrompt())) {
    if (entryIntroduced) return null;
    entryIntroduced = true;
    introduce(() => void tagNewNotes(ids, locate(), held));
    return null;
  }
  return tagNewNotes(ids, locate({ quiet }), held);
}
