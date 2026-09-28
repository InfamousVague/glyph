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
let ios = false;
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
  get isIOS() {
    return ios;
  },
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
  ios = false;
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
    await expect(location.locate({ quiet: true })).rejects.toMatchObject({ why: 'unavailable' });
    expect(requested).toEqual([1]);
  });

  it('on Android reads a prompt answered with neither permission as refused, and asks nothing of the device', async () => {
    android = true;
    native = true;
    const { calls } = fixAt(51.5, -0.1);
    window.GlyphHost = {
      takeLaunch: () => '',
      isLocked: () => false,
      endCapture: () => undefined,
      locationAccess: () => 'ask',
      requestLocation: () => setTimeout(() => window.__glyph?.location?.(), 10),
    };
    const fix = location.locate();
    const said = expect(fix).rejects.toMatchObject({ why: 'refused' });
    await vi.advanceTimersByTimeAsync(20);
    await said;
    expect(calls).toHaveLength(0);
  });

  it('gives up after a minute when nothing answers, a browser’s prompt left open included', async () => {
    const { calls } = geolocation(() => undefined);
    const fix = location.locate();
    const said = expect(fix).rejects.toMatchObject({ why: 'timeout' });
    await vi.advanceTimersByTimeAsync(59_999);
    expect(calls).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(1);
    await said;
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

describe('a place’s name for the + beside the line', () => {
  it('answers from what is known without asking', async () => {
    native = true;
    location.wantPlace('n1', LONDON);
    await settle();
    expect(invoked).toHaveLength(1);
    await expect(location.placeName(LONDON)).resolves.toBe('Trafalgar Square, London');
    expect(invoked).toHaveLength(1);
  });

  it('answers nothing, without asking, for a place whose ask failed this run', async () => {
    native = true;
    answer = async () => {
      throw new Error('offline');
    };
    await expect(location.placeName(LONDON)).resolves.toBeNull();
    expect(invoked).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(2000);
    await expect(location.placeName(LONDON)).resolves.toBeNull();
    expect(invoked).toHaveLength(1);
  });

  it('otherwise asks once, and never where names may not be asked', async () => {
    native = true;
    const named = location.placeName(LONDON);
    const again = location.placeName(LONDON);
    await settle();
    await expect(named).resolves.toBe('Trafalgar Square, London');
    await expect(again).resolves.toBe('Trafalgar Square, London');
    expect(invoked).toHaveLength(1);
    prefs.setPreferences({ placeNames: false });
    await expect(location.placeName({ ...LONDON, lat: 40, lon: -74 })).resolves.toBeNull();
    expect(invoked).toHaveLength(1);
  });
});

describe('the iPhone app', () => {
  it('is never asked for a fix: it declares no permission, so its WebView refuses every ask', async () => {
    ios = true;
    native = true;
    const { calls } = fixAt(1, 1);
    expect(location.canLocate()).toEqual({ ok: false, why: 'ios' });
    expect(location.locateHere()).toEqual({ ok: false, why: 'ios' });
    await expect(location.locate()).rejects.toMatchObject({ why: 'ios' });
    expect(calls).toHaveLength(0);
    // Safari on an iPhone is a browser, and asks as one.
    native = false;
    expect(location.canLocate()).toEqual({ ok: true });
  });

  it('under Local only still says Local only, and a phone that can locate says so without it', () => {
    fixAt(1, 1);
    expect(location.locateHere()).toEqual({ ok: true });
    prefs.setPreferences({ localOnly: true });
    expect(location.canLocate()).toEqual({ ok: false, why: 'local-only' });
    expect(location.locateHere()).toEqual({ ok: true });
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

  it('asks once for two notes at the same place, and not at all if Local only comes on while an ask waits its turn', async () => {
    native = true;
    location.wantPlace('one', LONDON);
    location.wantPlace('two', LONDON);
    await vi.advanceTimersByTimeAsync(5_000);
    expect(invoked).toHaveLength(1);
    // Two places: the second waits its second, and Local only turned on meanwhile stops it being sent.
    location.wantPlace('n1', { ...LONDON, lat: 40, lon: -74 });
    location.wantPlace('n2', { ...LONDON, lat: 48.8606, lon: 2.3376 });
    await vi.advanceTimersByTimeAsync(10);
    expect(invoked).toHaveLength(2);
    prefs.setPreferences({ localOnly: true });
    await vi.advanceTimersByTimeAsync(5_000);
    expect(invoked).toHaveLength(2);
    // Not counted as failed: asked again, once asking is allowed again.
    prefs.setPreferences({ localOnly: false });
    location.wantPlace('n2', { ...LONDON, lat: 48.8606, lon: 2.3376 });
    await vi.advanceTimersByTimeAsync(5_000);
    expect(invoked.map((call) => call.args.lat)).toEqual([51.507, 40, 48.861]);
  });

  it('writes a closed note only while its tag is the one asked about, and never while a pass is queued for it', async () => {
    nominatim();
    // Moved since the ask: the name is not this tag's.
    await store.createNote('moved', '---\nlocation: 40.7128,-74.0060\n---\n# NYC\n');
    location.wantPlace('moved', LONDON);
    await vi.advanceTimersByTimeAsync(1200);
    expect((await store.getNote('moved'))?.body).toBe('---\nlocation: 40.7128,-74.0060\n---\n# NYC\n');
    // A pass queued, and no tag waiting: the note is left for the pass's compare.
    queued.add('queued');
    await store.createNote('queued', '---\nlocation: 51.5074,-0.1278\n---\n# Out\n');
    location.wantPlace('queued', LONDON);
    await vi.advanceTimersByTimeAsync(1200);
    expect((await store.getNote('queued'))?.body).toBe('---\nlocation: 51.5074,-0.1278\n---\n# Out\n');
    expect(location.placeFor(LONDON)).toBe('Trafalgar Square, London');
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
    // The name is asked only for the tag that landed; the others are named when theirs do.
    await settle();
    expect(asked).toHaveLength(1);
    expect((await store.getNote('plain'))?.body).toBe('---\nlocation: 51.5074,-0.1278\nplace: "Trafalgar Square, London"\n---\n# Said\n');
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

  it('writes a closed note’s waiting tag once its pass has gone, keeps it past a day while the pass is queued, and drops it for a note that is gone', async () => {
    const asked = nominatim();
    await store.createNote('rec', '# Said\n');
    queued.add('rec');
    await location.tagNewNotes(['rec', 'gone'], Promise.resolve({ lat: 51.50741, lon: -0.12776, accuracy: 12, at: 0 }), { reviewing: false });
    expect(location.pendingTag('rec')).toEqual(LONDON);
    // A day and more with the pass still queued: the tag is what it waits for, so it is kept.
    vi.setSystemTime(1_000 * DAY + 2 * DAY);
    expect(await location.settleWaitingTags()).toBe(0);
    expect(location.pendingTag('rec')).toEqual(LONDON);
    expect((await store.getNote('rec'))?.body).toBe('# Said\n');
    expect(asked).toHaveLength(0);
    // The pass lands (the words rewritten) and leaves the queue: the tag goes in with the better words, then its name.
    await store.updateNote('rec', '# Said better\n', (await store.getNote('rec'))!.revision ?? 1);
    queued.delete('rec');
    expect(await location.settleWaitingTags()).toBe(1);
    await settle();
    expect((await store.getNote('rec'))?.body).toBe('---\nlocation: 51.5074,-0.1278\nplace: "Trafalgar Square, London"\n---\n# Said better\n');
    expect(location.pendingTag('rec')).toBeNull();
    // A note that is not there any more takes its waiting tag with it.
    expect(location.pendingTag('gone')).toBeNull();
  });

  it('writes a note’s waiting tag a moment after its screen is left, and keeps one made after it was', async () => {
    nominatim();
    await store.createNote('left', '# Walk\n');
    const stop = location.watchTag('left', () => undefined);
    location.setPendingTag('left', LONDON);
    stop();
    await vi.advanceTimersByTimeAsync(1999);
    expect((await store.getNote('left'))?.body).toBe('# Walk\n');
    await vi.advanceTimersByTimeAsync(1);
    expect((await store.getNote('left'))?.body).toContain('location: 51.5074,-0.1278');
    // A fix that came after the screen went (landTag): written straight into the closed note.
    await store.createNote('late', '# Late\n');
    location.landTag('late', { ...LONDON, lat: 48.8566, lon: 2.3522 });
    await settle();
    expect((await store.getNote('late'))?.body).toBe('---\nlocation: 48.8566,2.3522\n---\n# Late\n');
  });

  it('introduces the first ask where the prompt has never been answered, once a run, and asks on the press', async () => {
    await store.createNote('n1', '# Said\n');
    await store.createNote('n2', '# Said too\n');
    const { calls } = fixAt(51.5074, -0.1278);
    let allow: (() => void) | null = null;
    const introduce = vi.fn((press: () => void) => {
      allow = press;
    });
    expect(await location.tagNewNotesIfWanted(['n1'], { reviewing: false }, { introduce })).toBeNull();
    expect(introduce).toHaveBeenCalledTimes(1);
    expect(calls).toHaveLength(0);
    // Let pass: the next new note this run is neither introduced again nor asked for.
    expect(await location.tagNewNotesIfWanted(['n2'], { reviewing: false }, { introduce })).toBeNull();
    expect(introduce).toHaveBeenCalledTimes(1);
    expect(calls).toHaveLength(0);
    // Pressed: the ask is made, from the press, and the note is tagged.
    allow!();
    await settle();
    expect(calls).toHaveLength(1);
    expect((await store.getNote('n1'))?.body).toContain('location: 51.5074,-0.1278');
    // Where the prompt was answered already, nothing is introduced.
    Object.defineProperty(navigator, 'permissions', { configurable: true, value: { query: async () => ({ state: 'granted' }) } });
    try {
      await store.createNote('n3', '# Said\n');
      const told = vi.fn();
      await location.tagNewNotesIfWanted(['n3'], { reviewing: false }, { introduce: told });
      expect(told).not.toHaveBeenCalled();
      expect(calls).toHaveLength(2);
    } finally {
      Reflect.deleteProperty(navigator, 'permissions');
    }
  });

  it('says where location is allowed again in the words of where it runs', () => {
    expect(location.allowLocationWhere()).toBe('Allow location for this site in the browser’s settings');
    native = true;
    android = true;
    window.GlyphHost = { takeLaunch: () => '', isLocked: () => false, endCapture: () => undefined, locationAccess: () => 'blocked' };
    expect(location.allowLocationWhere()).toBe('Allow location for Ghost.md in the phone’s settings');
  });

  it('forgets a kept refusal once a fix comes', async () => {
    location.rememberRefusal('refused');
    expect(location.autoTagRefusal()).toBe('refused');
    await location.tagNewNotes(['n1'], Promise.resolve({ lat: 1, lon: 2, accuracy: 12, at: 0 }), { reviewing: false });
    expect(location.autoTagRefusal()).toBeNull();
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

  it('says why only on notes made since the refusal, and forgets it once the phone allows location', async () => {
    failWith(1);
    await store.createNote('n1', '# Said\n');
    expect(await location.tagNewNotesIfWanted(['n1'], { reviewing: false })).toBe('refused');
    // A note from before the refusal was never going to be tagged; one made since was not, for this reason.
    expect(location.refusedFor(1_000 * DAY - 60 * 60_000)).toBeNull();
    expect(location.refusedFor(1_000 * DAY)).toBe('refused');
    // Not allowed yet: still refused, and nothing is asked.
    const { calls } = fixAt(51.5074, -0.1278);
    expect(await location.tagNewNotesIfWanted(['n1'], { reviewing: false })).toBe('refused');
    expect(calls).toHaveLength(0);
    // Allowed since, in the phone's settings: the refusal is forgotten and the next new note is asked for again.
    native = true;
    android = true;
    window.GlyphHost = { takeLaunch: () => '', isLocked: () => false, endCapture: () => undefined, locationAccess: () => 'granted' };
    await location.tagNewNotesIfWanted(['n1'], { reviewing: false });
    expect(calls).toHaveLength(1);
    expect(location.autoTagRefusal()).toBeNull();
  });

  it('never counts a quiet ask over a locked phone as a refusal', async () => {
    native = true;
    android = true;
    window.GlyphHost = { takeLaunch: () => '', isLocked: () => true, endCapture: () => undefined, locationAccess: () => 'ask' };
    fixAt(51.5074, -0.1278);
    expect(await location.tagNewNotesIfWanted(['n1'], { reviewing: false }, { quiet: true })).toBe('unavailable');
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
    // Its own module (placeLink.ts), since the shared page draws the card and must not load the rest of this one.
    const link = await import('./placeLink.ts');
    expect(link.placeUrl(LONDON)).toBe('https://www.openstreetmap.org/?mlat=51.5074&mlon=-0.1278#map=15/51.5074/-0.1278');
    expect(link.placeUrl({ ...LONDON, lat: 51.51, lon: -0.13, rough: true })).toBe('https://www.openstreetmap.org/?mlat=51.51&mlon=-0.13#map=12/51.51/-0.13');
    mac = true;
    native = true;
    expect(link.placeUrl({ ...LONDON, place: 'Trafalgar Square, London' })).toBe('https://maps.apple.com/?ll=51.5074,-0.1278&q=Trafalgar%20Square%2C%20London');
    expect(link.placeUrl(LONDON)).toBe('https://maps.apple.com/?ll=51.5074,-0.1278&q=51.5074%2C%20-0.1278');
    mac = false;
    android = true;
    // An older Android binary has no `geo:` scope: the site instead.
    expect(link.placeUrl(LONDON)).toContain('openstreetmap.org');
    window.GlyphHost = { takeLaunch: () => '', isLocked: () => false, endCapture: () => undefined, locationAccess: () => 'granted' };
    expect(link.placeUrl({ ...LONDON, place: 'Trafalgar Square' })).toBe('geo:51.5074,-0.1278?q=51.5074,-0.1278(Trafalgar%20Square)');
    await link.openPlace(LONDON);
    expect(openUrl).toHaveBeenCalledWith('geo:51.5074,-0.1278?q=51.5074,-0.1278');
  });
});
