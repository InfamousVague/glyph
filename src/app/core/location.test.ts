import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { GeoTag } from './geotag.ts';

/*
 * Where the device is, and what becomes of it (location.ts): the fix asked only where it may be, the name asked of
 * Nominatim once and a second apart, the tag that waits for a recording's better words, and where a tapped map goes.
 * A phone is core/tauri.ts and core/platform.ts mocked; the module keeps names and asks in module state, so each
 * test imports it fresh, as linkPreview.test.ts does.
 */

let native = false;
let android = false;
let mac = false;
let generation = 20;
/** What `geocode_place` answers, or throws. */
let answer: () => Promise<unknown> = async () => ({ name: 'Trafalgar Square', addresstype: 'square', address: { city: 'London' } });
const invoked: { command: string; args: Record<string, unknown> }[] = [];
/** Whether a better-words pass is queued for a note (capture/refine.ts). */
const queued = new Set<string>();

vi.mock('./tauri.ts', () => ({
  isTauri: () => native,
  invoke: async (command: string, args: Record<string, unknown>) => {
    // Only the ask is the app's here; a store call on a "phone" is refused, and the tests that need the store use the web's.
    if (command !== 'geocode_place') throw new Error(`unexpected ${command}`);
    invoked.push({ command, args });
    return answer();
  },
}));
vi.mock('./nativeGeneration.ts', () => ({ hasNativeGeneration: async (wanted: number) => generation >= wanted }));
vi.mock('./platform.ts', () => ({
  get isAndroid() {
    return android;
  },
  get isMacApp() {
    return mac;
  },
  isMobile: false,
  isIOS: false,
  isNativeMobile: false,
}));
const openUrl = vi.fn(async (_url: string) => undefined);
vi.mock('@tauri-apps/plugin-opener', () => ({ openUrl: (url: string) => openUrl(url) }));
vi.mock('../capture/refine.ts', () => ({ refinePending: (id: string) => queued.has(id) }));

let location: typeof import('./location.ts');
let prefs: typeof import('./preferences.ts');
let store: typeof import('./store.ts');

const LONDON: GeoTag = { lat: 51.5074, lon: -0.1278, place: null, rough: false };
const DAY = 24 * 60 * 60_000;

/** A `navigator.geolocation` a test can answer: jsdom has none. */
function geolocation(respond: (ok: PositionCallback, fail: PositionErrorCallback) => void): { calls: PositionOptions[] } {
  const calls: PositionOptions[] = [];
  Object.defineProperty(navigator, 'geolocation', {
    configurable: true,
    value: {
      getCurrentPosition: (ok: PositionCallback, fail: PositionErrorCallback, options: PositionOptions) => {
        calls.push(options);
        respond(ok, fail);
      },
    },
  });
  return { calls };
}

const position = (lat: number, lon: number, accuracy = 20) => ({ coords: { latitude: lat, longitude: lon, accuracy }, timestamp: 1_000 } as GeolocationPosition);
const fixAt = (lat: number, lon: number, accuracy = 20) => geolocation((ok) => ok(position(lat, lon, accuracy)));
const failWith = (code: number) => geolocation((_ok, fail) => fail({ code, message: '' } as GeolocationPositionError));

/** Lets an ask, and what follows it, land. */
const settle = () => vi.advanceTimersByTimeAsync(0);

/** Nominatim as the web page reaches it: `fetch` stood in for, answering `answer`, with every address asked kept. */
function nominatim(): string[] {
  const asked: string[] = [];
  vi.stubGlobal('fetch', async (url: string) => {
    asked.push(url);
    const body = await answer();
    return { ok: true, json: async () => body };
  });
  return asked;
}

beforeEach(async () => {
  native = false;
  android = false;
  mac = false;
  generation = 20;
  answer = async () => ({ name: 'Trafalgar Square', addresstype: 'square', address: { city: 'London' } });
  invoked.length = 0;
  queued.clear();
  openUrl.mockClear();
  localStorage.clear();
  delete window.GlyphHost;
  delete window.__glyph;
  Reflect.deleteProperty(navigator, 'geolocation');
  vi.useFakeTimers();
  vi.setSystemTime(1_000 * DAY);
  vi.resetModules();
  location = await import('./location.ts');
  prefs = await import('./preferences.ts');
  store = await import('./store.ts');
  prefs.reloadPreferences();
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  Reflect.deleteProperty(navigator, 'geolocation');
});

describe('a fix', () => {
  it('comes from the device, asked without high accuracy, and is not asked for at all under Local only', async () => {
    const { calls } = fixAt(51.50741, -0.12776, 12);
    await expect(location.locate()).resolves.toEqual({ lat: 51.50741, lon: -0.12776, accuracy: 12, at: 1_000 });
    expect(calls).toEqual([{ enableHighAccuracy: false, timeout: 15_000, maximumAge: 120_000 }]);
    prefs.setPreferences({ localOnly: true });
    expect(location.canLocate()).toEqual({ ok: false, why: 'local-only' });
    await expect(location.locate()).rejects.toMatchObject({ why: 'local-only' });
    expect(calls).toHaveLength(1);
  });

  it('says why it did not come: refused, unavailable, timed out, or no way to ask', async () => {
    failWith(1);
    await expect(location.locate()).rejects.toMatchObject({ why: 'refused' });
    failWith(2);
    await expect(location.locate()).rejects.toMatchObject({ why: 'unavailable' });
    failWith(3);
    await expect(location.locate()).rejects.toMatchObject({ why: 'timeout' });
    Reflect.deleteProperty(navigator, 'geolocation');
    expect(location.canLocate()).toEqual({ ok: false, why: 'none' });
    await expect(location.locate()).rejects.toMatchObject({ why: 'none' });
    expect(location.whyLocateFailed(new Error('anything'))).toBe('unavailable');
  });

  it('is never asked of the Mac, whose WebView would never answer', async () => {
    mac = true;
    native = true;
    const { calls } = fixAt(1, 1);
    expect(location.canLocate()).toEqual({ ok: false, why: 'mac' });
    await expect(location.locate()).rejects.toMatchObject({ why: 'mac' });
    expect(calls).toHaveLength(0);
  });

  it('on Android asks the activity first, waits for its answer, and then the device', async () => {
    android = true;
    native = true;
    const { calls } = fixAt(51.5, -0.1);
    // An older binary, with no bridge and no permission in its manifest: nothing is asked.
    expect(location.canLocate()).toEqual({ ok: false, why: 'unavailable' });
    let access = 'ask';
    const requested: number[] = [];
    window.GlyphHost = {
      takeLaunch: () => '',
      isLocked: () => false,
      endCapture: () => undefined,
      locationAccess: () => access,
      requestLocation: () => {
        requested.push(1);
        // The activity answers later, as onRequestPermissionsResult does.
        setTimeout(() => {
          access = 'approximate';
          window.__glyph?.location?.();
        }, 50);
      },
    };
    expect(location.canLocate()).toEqual({ ok: true });
    const fix = location.locate();
    await vi.advanceTimersByTimeAsync(60);
    await expect(fix).resolves.toMatchObject({ lat: 51.5, lon: -0.1 });
    expect(requested).toEqual([1]);
    expect(calls).toHaveLength(1);
    // Denied twice, or off for the app: blocked, and no dialog is raised into silence.
    access = 'blocked';
    await expect(location.locate()).rejects.toMatchObject({ why: 'blocked' });
    expect(requested).toEqual([1]);
    // A quiet ask, over a locked phone, never raises the prompt.
    access = 'ask';
    await expect(location.locate({ quiet: true })).rejects.toMatchObject({ why: 'refused' });
    expect(requested).toEqual([1]);
  });
});

describe('the gates', () => {
  it('draw tiles only with the switch on and Local only off', () => {
    expect(location.canShowTiles()).toBe(true);
    prefs.setPreferences({ mapTiles: false });
    expect(location.canShowTiles()).toBe(false);
    prefs.setPreferences({ mapTiles: true, localOnly: true });
    expect(location.canShowTiles()).toBe(false);
  });

  it('ask for a name only with the switch on, Local only off, and in the app a binary that asks as itself', async () => {
    expect(await location.canAskPlace()).toBe(true);
    native = true;
    expect(await location.canAskPlace()).toBe(true);
    generation = 19;
    expect(await location.canAskPlace()).toBe(false);
    generation = 20;
    prefs.setPreferences({ placeNames: false });
    expect(await location.canAskPlace()).toBe(false);
    prefs.setPreferences({ placeNames: true, localOnly: true });
    expect(await location.canAskPlace()).toBe(false);
  });
});

describe('a place’s name', () => {
  it('is asked of the app once, at three decimals and zoom 15, and told to the note watching', async () => {
    native = true;
    const heard: unknown[] = [];
    location.watchTag('n1', (event) => heard.push(event));
    location.wantPlace('n1', LONDON);
    location.wantPlace('n1', LONDON);
    await settle();
    expect(invoked).toEqual([{ command: 'geocode_place', args: { lat: 51.507, lon: -0.128, zoom: 15, lang: navigator.language || 'en' } }]);
    expect(heard).toEqual([{ kind: 'place', place: 'Trafalgar Square, London', lat: 51.5074, lon: -0.1278 }]);
    // Known now: the next note at the same place is told at once, and nothing is asked again.
    location.watchTag('n2', (event) => heard.push(event));
    location.wantPlace('n2', LONDON);
    expect(heard).toHaveLength(2);
    expect(invoked).toHaveLength(1);
    expect(location.placeFor(LONDON)).toBe('Trafalgar Square, London');
  });

  it('is asked at two decimals and zoom 12 for a rough tag, and never for a tag that has one', async () => {
    native = true;
    location.wantPlace('n1', { ...LONDON, place: 'Somewhere' });
    location.wantPlace('n2', { lat: 51.51, lon: -0.13, place: null, rough: true });
    await settle();
    expect(invoked.map((call) => call.args)).toEqual([{ lat: 51.51, lon: -0.13, zoom: 12, lang: navigator.language || 'en' }]);
  });

  it('is fetched by the page itself on the web, from Nominatim’s own address', async () => {
    answer = async () => ({ address: { road: 'Rue de Rivoli', city: 'Paris' } });
    const asked = nominatim();
    const heard: unknown[] = [];
    location.watchTag('n1', (event) => heard.push(event));
    location.wantPlace('n1', LONDON);
    await settle();
    expect(asked).toEqual(['https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=51.507&lon=-0.128&zoom=15&addressdetails=1']);
    expect(heard).toEqual([{ kind: 'place', place: 'Rue de Rivoli, Paris', lat: 51.5074, lon: -0.1278 }]);
    expect(invoked).toEqual([]);
  });

  it('asks for two notes a second apart, and not again this run after a failure', async () => {
    native = true;
    location.wantPlace('n1', LONDON);
    location.wantPlace('n2', { ...LONDON, lat: 48.8566, lon: 2.3522 });
    await settle();
    expect(invoked).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(1099);
    expect(invoked).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(invoked).toHaveLength(2);
    answer = async () => {
      throw new Error('Nominatim answered 429.');
    };
    await vi.advanceTimersByTimeAsync(1100);
    location.wantPlace('n3', { ...LONDON, lat: 40, lon: -74 });
    await settle();
    expect(invoked).toHaveLength(3);
    location.wantPlace('n3', { ...LONDON, lat: 40, lon: -74 });
    await vi.advanceTimersByTimeAsync(1100);
    expect(invoked).toHaveLength(3);
    expect(location.placeFor({ ...LONDON, lat: 40, lon: -74 })).toBeNull();
  });

  it('is written into a closed note, unless a pass is queued to rewrite it, and waits for a pending tag', async () => {
    nominatim();
    await store.createNote('closed', '---\nlocation: 51.5074,-0.1278\n---\n# Out\n');
    location.wantPlace('closed', LONDON);
    await settle();
    await settle();
    expect((await store.getNote('closed'))?.body).toBe('---\nlocation: 51.5074,-0.1278\nplace: "Trafalgar Square, London"\n---\n# Out\n');
    // A pass queued: the name waits in memory, and on the pending tag where there is one.
    queued.add('held');
    await store.createNote('held', '---\nlocation: 48.8566,2.3522\n---\n# Out\n');
    location.setPendingTag('held', { ...LONDON, lat: 48.8566, lon: 2.3522 });
    location.wantPlace('held', { ...LONDON, lat: 48.8566, lon: 2.3522 });
    await vi.advanceTimersByTimeAsync(1200);
    expect((await store.getNote('held'))?.body).toBe('---\nlocation: 48.8566,2.3522\n---\n# Out\n');
    expect(location.pendingTag('held')?.place).toBe('Trafalgar Square, London');
  });
});

describe('a tag waiting for the better words', () => {
  it('is kept a day, and read back as it was set', () => {
    location.setPendingTag('n1', { ...LONDON, rough: true });
    expect(location.pendingTag('n1')).toEqual({ ...LONDON, rough: true });
    expect(location.pendingTag('n2')).toBeNull();
    vi.setSystemTime(1_000 * DAY + DAY - 1);
    expect(location.pendingTag('n1')).not.toBeNull();
    vi.setSystemTime(1_000 * DAY + DAY + 1);
    expect(location.pendingTag('n1')).toBeNull();
    location.setPendingTag('n3', LONDON);
    location.setPendingTag('n3', null);
    expect(location.pendingTag('n3')).toBeNull();
    expect(localStorage.getItem('glyph-geotag-pending')).toBeNull();
  });

  it('lands only once no pass is queued, no review is live, and the note has words', () => {
    location.setPendingTag('n1', LONDON);
    expect(location.settleTag('n1', '# Out\n', { reviewing: true })).toBeNull();
    queued.add('n1');
    expect(location.settleTag('n1', '# Out\n', { reviewing: false })).toBeNull();
    queued.delete('n1');
    expect(location.settleTag('n1', '', { reviewing: false })).toBeNull();
    expect(location.settleTag('n1', '---\ntitle: "A"\n---\n', { reviewing: false })).toBeNull();
    expect(location.settleTag('n1', '# Out\n', { reviewing: false })).toBe('---\nlocation: 51.5074,-0.1278\n---\n# Out\n');
    expect(location.settleTag('n2', '# Out\n', { reviewing: false })).toBeNull();
  });
});

describe('tagging new notes', () => {
  it('writes a closed note at once, sets a tag aside where a pass or a review is coming, and hands a watched note its tag', async () => {
    const asked = nominatim();
    await store.createNote('plain', '# Said\n');
    await store.createNote('refining', '# Said\n');
    await store.createNote('open', '# Said\n');
    queued.add('refining');
    const heard: unknown[] = [];
    location.watchTag('open', (event) => heard.push(event));
    const fix = Promise.resolve({ lat: 51.50741, lon: -0.12776, accuracy: 12, at: 0 });
    expect(await location.tagNewNotes(['plain', 'refining', 'open'], fix, { reviewing: false })).toBeNull();
    expect((await store.getNote('plain'))?.body).toBe('---\nlocation: 51.5074,-0.1278\n---\n# Said\n');
    expect(location.pendingTag('plain')).toBeNull();
    expect((await store.getNote('refining'))?.body).toBe('# Said\n');
    expect(location.pendingTag('refining')).toEqual(LONDON);
    expect((await store.getNote('open'))?.body).toBe('# Said\n');
    expect(location.pendingTag('open')).toEqual(LONDON);
    expect(heard).toEqual([{ kind: 'pending' }]);
    // The name is asked, once for the three: the same place.
    await settle();
    expect(asked).toHaveLength(1);
    // A review live for the note: set aside too.
    await store.createNote('reviewed', '# Said\n');
    await location.tagNewNotes(['reviewed'], fix, { reviewing: true });
    expect((await store.getNote('reviewed'))?.body).toBe('# Said\n');
    expect(location.pendingTag('reviewed')).toEqual(LONDON);
  });

  it('leaves a note with no words, and a note tagged already, as they are', async () => {
    await store.createNote('blank', '');
    await store.createNote('tagged', '---\nlocation: 1.0000,2.0000\n---\n# Here\n');
    await location.tagNewNotes(['blank', 'tagged'], Promise.resolve({ lat: 51.5074, lon: -0.1278, accuracy: 12, at: 0 }), { reviewing: false });
    expect((await store.getNote('blank'))?.body).toBe('');
    expect(location.pendingTag('blank')).toEqual(LONDON);
    expect((await store.getNote('tagged'))?.body).toBe('---\nlocation: 1.0000,2.0000\n---\n# Here\n');
    expect(location.pendingTag('tagged')).toBeNull();
  });

  it('remembers a refusal so the device is not asked again, until a fix comes', async () => {
    await store.createNote('n1', '# Said\n');
    failWith(1);
    expect(await location.tagNewNotesIfWanted(['n1'], { reviewing: false })).toBe('refused');
    expect(location.autoTagRefusal()).toBe('refused');
    fixAt(51.5074, -0.1278);
    expect(await location.tagNewNotesIfWanted(['n1'], { reviewing: false })).toBe('refused');
    expect((await store.getNote('n1'))?.body).toBe('# Said\n');
    location.forgetRefusal();
    expect(await location.tagNewNotesIfWanted(['n1'], { reviewing: false })).toBeNull();
    expect((await store.getNote('n1'))?.body).toBe('---\nlocation: 51.5074,-0.1278\n---\n# Said\n');
    expect(location.autoTagRefusal()).toBeNull();
    // A timeout is not a refusal: asked again next time.
    failWith(3);
    await store.createNote('n2', '# Said\n');
    expect(await location.tagNewNotesIfWanted(['n2'], { reviewing: false })).toBe('timeout');
    expect(location.autoTagRefusal()).toBeNull();
  });

  it('does nothing with the switch off, under Local only, or with nothing to tag', async () => {
    const { calls } = fixAt(1, 1);
    expect(await location.tagNewNotesIfWanted([], { reviewing: false })).toBeNull();
    prefs.setPreferences({ tagNewNotes: false });
    expect(await location.tagNewNotesIfWanted(['n1'], { reviewing: false })).toBeNull();
    prefs.setPreferences({ tagNewNotes: true, localOnly: true });
    expect(await location.tagNewNotesIfWanted(['n1'], { reviewing: false })).toBeNull();
    expect(calls).toHaveLength(0);
  });
});

describe('where a tapped map goes', () => {
  it('opens the maps app on Android, Apple Maps on the Mac, and openstreetmap.org elsewhere, never with the title', async () => {
    expect(location.placeUrl(LONDON)).toBe('https://www.openstreetmap.org/?mlat=51.5074&mlon=-0.1278#map=15/51.5074/-0.1278');
    expect(location.placeUrl({ ...LONDON, lat: 51.51, lon: -0.13, rough: true })).toBe('https://www.openstreetmap.org/?mlat=51.51&mlon=-0.13#map=12/51.51/-0.13');
    mac = true;
    native = true;
    expect(location.placeUrl({ ...LONDON, place: 'Trafalgar Square, London' })).toBe('https://maps.apple.com/?ll=51.5074,-0.1278&q=Trafalgar%20Square%2C%20London');
    expect(location.placeUrl(LONDON)).toBe('https://maps.apple.com/?ll=51.5074,-0.1278&q=51.5074%2C%20-0.1278');
    mac = false;
    android = true;
    // An older Android binary has no `geo:` scope: the site instead.
    expect(location.placeUrl(LONDON)).toContain('openstreetmap.org');
    window.GlyphHost = { takeLaunch: () => '', isLocked: () => false, endCapture: () => undefined, locationAccess: () => 'granted' };
    expect(location.placeUrl({ ...LONDON, place: 'Trafalgar Square' })).toBe('geo:51.5074,-0.1278?q=51.5074,-0.1278(Trafalgar%20Square)');
    await location.openPlace(LONDON);
    expect(openUrl).toHaveBeenCalledWith('geo:51.5074,-0.1278?q=51.5074,-0.1278');
  });
});
