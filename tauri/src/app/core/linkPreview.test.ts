import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/*
 * A link card's title (linkPreview.ts): read by the app, kept for a week, a failure asked again after a day, and
 * asked for only where asking is allowed. A phone is core/tauri.ts mocked; the module keeps what it knows in module
 * state, so each test imports it fresh.
 */

let native = true;
let generation = 17;
/** What `link_preview` answers for each address asked, or throws. */
let answer: (url: string) => Promise<unknown> = async (url) => ({ title: `Title of ${url}`, site: 'Site' });
const asked: string[] = [];

vi.mock('./tauri.ts', () => ({
  isTauri: () => native,
  invoke: async (command: string, args: { url: string }) => {
    if (command !== 'link_preview') throw new Error(`unexpected ${command}`);
    asked.push(args.url);
    return answer(args.url);
  },
}));
vi.mock('./nativeGeneration.ts', () => ({ hasNativeGeneration: async (wanted: number) => generation >= wanted }));
const openUrl = vi.fn(async (_url: string) => undefined);
vi.mock('@tauri-apps/plugin-opener', () => ({ openUrl: (url: string) => openUrl(url) }));

let links: typeof import('./linkPreview.ts');
let prefs: typeof import('./preferences.ts');
const DAY = 24 * 60 * 60_000;
const URL_A = 'https://www.airbnb.com/rooms/1234';

/** How many cards have been told to draw again. */
let ready = 0;
const onReady = () => {
  ready += 1;
};

/** Lets an ask, and the event after it, land. */
const settle = () => vi.advanceTimersByTimeAsync(0);

beforeEach(async () => {
  native = true;
  generation = 17;
  answer = async (url) => ({ title: `Title of ${url}`, site: 'Site' });
  asked.length = 0;
  openUrl.mockClear();
  localStorage.clear();
  vi.useFakeTimers();
  vi.setSystemTime(1_000 * DAY);
  vi.resetModules();
  links = await import('./linkPreview.ts');
  prefs = await import('./preferences.ts');
  ready = 0;
  window.addEventListener(links.LINK_PREVIEW_READY, onReady);
});

afterEach(() => {
  window.removeEventListener(links.LINK_PREVIEW_READY, onReady);
  vi.useRealTimers();
});

describe('a link’s title', () => {
  it('is asked of the app once, kept, and drawn at once the next time', async () => {
    expect(links.previewFor(URL_A)).toBeNull();
    links.wantPreview(URL_A);
    links.wantPreview(URL_A);
    await settle();
    expect(asked).toEqual([URL_A]);
    expect(ready).toBe(1);
    expect(links.previewFor(URL_A)).toEqual({ url: URL_A, title: `Title of ${URL_A}`, site: 'Site', description: undefined });
    // A reload reads it back from storage.
    vi.resetModules();
    const again = await import('./linkPreview.ts');
    expect(again.previewFor(URL_A)?.title).toBe(`Title of ${URL_A}`);
  });

  it('is asked again after a week, and not before', async () => {
    links.wantPreview(URL_A);
    await settle();
    vi.setSystemTime(1_000 * DAY + 7 * DAY - 1);
    links.wantPreview(URL_A);
    await settle();
    expect(asked).toHaveLength(1);
    vi.setSystemTime(1_000 * DAY + 7 * DAY);
    links.wantPreview(URL_A);
    await settle();
    expect(asked).toHaveLength(2);
  });

  it('is nothing after a failure, and is asked again a day later', async () => {
    answer = async () => {
      throw new Error('the site did not answer');
    };
    links.wantPreview(URL_A);
    await settle();
    expect(links.previewFor(URL_A)).toBeNull();
    expect(ready).toBe(1);
    vi.setSystemTime(1_000 * DAY + DAY - 1);
    links.wantPreview(URL_A);
    await settle();
    expect(asked).toHaveLength(1);
    vi.setSystemTime(1_000 * DAY + DAY);
    links.wantPreview(URL_A);
    await settle();
    expect(asked).toHaveLength(2);
  });

  it('is never asked in a browser, on an app too old to read one, with previews off, or with Nothing leaves the phone on', async () => {
    native = false;
    links.wantPreview('https://a.example/');
    generation = 16;
    native = true;
    links.wantPreview('https://b.example/');
    generation = 17;
    prefs.setPreferences({ linkPreviews: false });
    links.wantPreview('https://c.example/');
    prefs.setPreferences({ linkPreviews: true, localOnly: true });
    links.wantPreview('https://d.example/');
    await settle();
    expect(asked).toEqual([]);
    expect(ready).toBe(0);
  });

  it('keeps the three hundred most recently asked', async () => {
    for (let i = 0; i < 301; i += 1) {
      vi.setSystemTime(1_000 * DAY + i);
      links.wantPreview(`https://example.com/${i}`);
      await settle();
    }
    const kept = JSON.parse(localStorage.getItem('glyph-link-previews') ?? '{}') as Record<string, unknown>;
    expect(Object.keys(kept)).toHaveLength(300);
    expect(kept['https://example.com/0']).toBeUndefined();
    expect(kept['https://example.com/300']).toBeDefined();
  });
});

describe('an address as a card says it', () => {
  it('names the site without www, and the path short', () => {
    expect(links.siteOf(URL_A)).toBe('airbnb.com');
    expect(links.siteOf('not a url')).toBe('not a url');
    expect(links.pathOf(URL_A)).toBe('/rooms/1234');
    expect(links.pathOf('https://example.com/')).toBe('');
    expect(links.pathOf(`https://example.com/${'a'.repeat(40)}?q=1`)).toBe(`/${'a'.repeat(30)}…`);
    expect(links.pathOf('nonsense')).toBe('');
  });

  it('opens in the phone’s browser through the app, and in a new tab on the web', async () => {
    await links.openLink(URL_A);
    expect(openUrl).toHaveBeenCalledWith(URL_A);
    native = false;
    const open = vi.spyOn(window, 'open').mockImplementation(() => null);
    await links.openLink(URL_A);
    expect(open).toHaveBeenCalledWith(URL_A, '_blank', 'noopener');
    open.mockRestore();
  });
});
