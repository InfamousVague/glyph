import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import type { GeoTag } from '../core/geotag.ts';
import { rerender, show, unmount, waitUntil } from '../../test/render.tsx';

/**
 * The map card (MapCard.tsx): the quiet card under and the map over it, Leaflet imported only for a map and never for
 * the quiet card or the reader's ask, the app's own pin and never Leaflet's picture, the chips that say the place
 * and whose data the tiles are, and where a tap goes.
 */

/** Leaflet, stood in for: how many times it was imported, and what was asked of it. */
const leaflet = vi.hoisted(() => {
  const state = {
    imported: 0,
    maps: [] as { el: HTMLElement; options: Record<string, unknown>; views: unknown[]; removed: boolean; resized: number }[],
    tiles: [] as { url: string; options: Record<string, unknown>; on: Record<string, () => void> }[],
    markers: [] as { at: unknown; options: Record<string, unknown> }[],
    icons: [] as Record<string, unknown>[],
    iconImages: 0,
  };
  return state;
});
vi.mock('leaflet', () => {
  leaflet.imported += 1;
  const L = {
    map: (el: HTMLElement, options: Record<string, unknown>) => {
      const made = { el, options, views: [] as unknown[], removed: false, resized: 0 };
      leaflet.maps.push(made);
      return {
        setView: (at: unknown, zoom: number) => made.views.push([at, zoom]),
        invalidateSize: () => {
          made.resized += 1;
        },
        remove: () => {
          made.removed = true;
        },
      };
    },
    tileLayer: (url: string, options: Record<string, unknown>) => {
      const layer = { url, options, on: {} as Record<string, () => void> };
      leaflet.tiles.push(layer);
      return {
        on: (event: string, handler: () => void) => {
          layer.on[event] = handler;
        },
        addTo: () => undefined,
      };
    },
    divIcon: (options: Record<string, unknown>) => {
      leaflet.icons.push(options);
      return options;
    },
    icon: () => {
      leaflet.iconImages += 1;
      return {};
    },
    marker: (at: unknown, options: Record<string, unknown>) => {
      leaflet.markers.push({ at, options });
      return { addTo: () => undefined };
    },
  };
  return { ...L, default: L };
});
vi.mock('leaflet/dist/leaflet.css', () => ({}));
const opened: GeoTag[] = [];
vi.mock('../core/placeLink.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/placeLink.ts')>()),
  openPlace: async (tag: GeoTag) => {
    opened.push(tag);
  },
}));

const { MapCard } = await import('./MapCard.tsx');

const LONDON: GeoTag = { lat: 51.5074, lon: -0.1278, place: null, rough: false };
const NAMED: GeoTag = { ...LONDON, place: 'Trafalgar Square, London' };

/** The box has a size, as it does on a page: jsdom lays nothing out. */
function sized(width: number): void {
  Object.defineProperty(HTMLDivElement.prototype, 'clientWidth', { configurable: true, get: () => width });
  Object.defineProperty(HTMLDivElement.prototype, 'clientHeight', { configurable: true, get: () => (width ? 96 : 0) });
}

const card = () => document.querySelector<HTMLElement>('[data-mode]')!;
const tap = () => document.querySelector<HTMLButtonElement>('button')!;
const chips = () => [...document.querySelectorAll('[class*=chip]')].map((el) => el.textContent);

beforeEach(() => {
  leaflet.imported = 0;
  leaflet.maps.length = 0;
  leaflet.tiles.length = 0;
  leaflet.markers.length = 0;
  leaflet.icons.length = 0;
  leaflet.iconImages = 0;
  opened.length = 0;
  sized(320);
});

afterEach(() => {
  unmount();
  Reflect.deleteProperty(HTMLDivElement.prototype, 'clientWidth');
  Reflect.deleteProperty(HTMLDivElement.prototype, 'clientHeight');
  Reflect.deleteProperty(globalThis, 'ResizeObserver');
});

/** The pins drawn: the quiet card's and, with a map, the one over it. */
const marks = () => [...document.querySelectorAll<HTMLElement>('[class*=mark]')];

describe('the quiet card', () => {
  it('shows the pin and the coordinates, imports no map, and credits nobody until there is a place', async () => {
    show(<MapCard tag={LONDON} mode="quiet" dark={false} />);
    await act(async () => Promise.resolve());
    expect(leaflet.imported).toBe(0);
    expect(marks()).toHaveLength(1);
    expect(marks()[0]!.querySelector('path')).not.toBeNull();
    expect(chips()).toEqual(['51.5074, -0.1278']);
    rerender(<MapCard tag={NAMED} mode="quiet" dark={false} />);
    expect(chips()).toEqual(['Trafalgar Square, London', '© OpenStreetMap contributors']);
    expect(tap().getAttribute('aria-label')).toBe('Open Trafalgar Square, London on a map');
  });

  it('says why it is quiet, and draws a ring for a rough tag, as wide as the area its decimals leave open', () => {
    show(<MapCard tag={{ ...LONDON, lat: 51.51, lon: -0.13, rough: true }} mode="quiet" quietWhy="local-only" dark={false} />);
    expect(chips()).toEqual(['Roughly 51.51, -0.13', 'Local only is on.']);
    expect(card().hasAttribute('data-rough')).toBe(true);
    // Two decimals round to a cell 0.01° on a side: at zoom 11 its half diagonal is 14 px in London, 10 at the equator.
    expect(document.querySelector('[class*=mark][data-rough] circle')?.getAttribute('r')).toBe('14');
    expect(document.querySelector('[class*=mark] path')).toBeNull();
    rerender(<MapCard tag={{ lat: 0.01, lon: 10.01, place: null, rough: true }} mode="quiet" dark={false} />);
    expect(document.querySelector('[class*=mark][data-rough] circle')?.getAttribute('r')).toBe('10');
    rerender(<MapCard tag={{ lat: 69.65, lon: 18.96, place: null, rough: true }} mode="quiet" dark={false} />);
    expect(document.querySelector('[class*=mark][data-rough] circle')?.getAttribute('r')).toBe('18');
    rerender(<MapCard tag={LONDON} mode="quiet" quietWhy="off" dark={false} />);
    expect(chips()).toEqual(['51.5074, -0.1278', 'Map off in Settings.']);
  });

  it('leaves on its beat when the tag is taken off, and is then let go', () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    try {
      const onLeft = vi.fn();
      show(<MapCard tag={LONDON} mode="quiet" dark={false} leave onLeft={onLeft} />);
      expect(card().hasAttribute('data-leave')).toBe(true);
      expect(tap().disabled).toBe(true);
      act(() => vi.advanceTimersByTime(299));
      expect(onLeft).not.toHaveBeenCalled();
      act(() => vi.advanceTimersByTime(1));
      expect(onLeft).toHaveBeenCalledTimes(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it('opens the place on a tap', () => {
    show(<MapCard tag={LONDON} mode="quiet" dark />);
    expect(card().hasAttribute('data-dark')).toBe(true);
    act(() => tap().click());
    expect(opened).toEqual([LONDON]);
  });
});

describe('the reader’s ask', () => {
  it('offers the map and hands the tap to the caller, opening nothing and importing nothing', async () => {
    const onShow = vi.fn();
    show(<MapCard tag={LONDON} mode="ask" dark={false} onShow={onShow} />);
    await act(async () => Promise.resolve());
    expect(chips()).toEqual(['51.5074, -0.1278', 'Show the map']);
    // Drawn as the one thing to press, with the map's mark before the words.
    expect(document.querySelector('[class*=show] svg')).not.toBeNull();
    expect(tap().getAttribute('aria-label')).toBe('Show the map');
    act(() => tap().click());
    expect(onShow).toHaveBeenCalledTimes(1);
    expect(opened).toEqual([]);
    expect(leaflet.imported).toBe(0);
  });
});

describe('the map', () => {
  it('imports Leaflet lazily, draws a still map with the OSM tiles and the app’s pin, and fades in on load after a failed tile', async () => {
    show(<MapCard tag={LONDON} mode="map" dark={false} />);
    await waitUntil(() => expect(leaflet.maps).toHaveLength(1));
    expect(leaflet.imported).toBe(1);
    expect(leaflet.maps[0]!.options).toMatchObject({ dragging: false, touchZoom: false, scrollWheelZoom: false, doubleClickZoom: false, keyboard: false, zoomControl: false, attributionControl: false, zoomAnimation: false });
    expect(leaflet.maps[0]!.views).toEqual([[[51.5074, -0.1278], 15]]);
    // The page's origin as the Referer, which the tile policy asks of a web page; never the shared page's address.
    expect(leaflet.tiles[0]).toMatchObject({ url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', options: { maxZoom: 19, detectRetina: false, referrerPolicy: 'strict-origin' } });
    expect(leaflet.maps[0]!.options).toMatchObject({ fadeAnimation: false, markerZoomAnimation: false, tapHold: false, boxZoom: false });
    // Never Leaflet's marker nor its picture: the card's own pin, over the wash.
    expect(leaflet.markers).toHaveLength(0);
    expect(leaflet.icons).toHaveLength(0);
    expect(leaflet.iconImages).toBe(0);
    // One drawing on both layers, in the same place: the quiet card's pin and the one over the map.
    expect(marks()).toHaveLength(2);
    expect(marks()[0]!.querySelector('path')?.getAttribute('d')).toBe(marks()[1]!.querySelector('path')?.getAttribute('d'));
    expect(marks()[0]!.className.replace(/\S*over\S*/, '').trim()).toBe(marks()[1]!.className.replace(/\S*over\S*/, '').trim());
    // Nothing of OSM's is shown yet, so nobody is credited.
    expect(chips()).toEqual(['51.5074, -0.1278']);
    // A failed tile says nothing; the layer's load, once any tile has come, is what fades the map in.
    expect(card().hasAttribute('data-loaded')).toBe(false);
    act(() => leaflet.tiles[0]!.on.tileerror?.());
    act(() => leaflet.tiles[0]!.on.tileload!());
    act(() => leaflet.tiles[0]!.on.load!());
    expect(card().hasAttribute('data-loaded')).toBe(true);
    expect(chips()).toEqual(['51.5074, -0.1278', '© OpenStreetMap contributors']);
  });

  it('stays the quiet card when no tile came at all', async () => {
    show(<MapCard tag={LONDON} mode="map" dark={false} />);
    await waitUntil(() => expect(leaflet.maps).toHaveLength(1));
    // Offline: every tile failed, and Leaflet still says the layer has loaded.
    act(() => leaflet.tiles[0]!.on.load!());
    expect(card().hasAttribute('data-loaded')).toBe(false);
    expect(chips()).toEqual(['51.5074, -0.1278']);
  });

  it('draws a rough tag a district wide, at zoom 11, with a ring', async () => {
    show(<MapCard tag={{ ...LONDON, lat: 51.51, lon: -0.13, rough: true }} mode="map" dark />);
    await waitUntil(() => expect(leaflet.maps).toHaveLength(1));
    expect(leaflet.maps[0]!.views).toEqual([[[51.51, -0.13], 11]]);
    expect(document.querySelector('[class*=mark][data-rough] circle')).not.toBeNull();
    expect(document.querySelector('[class*=mark] path')).toBeNull();
    expect(card().hasAttribute('data-dark')).toBe(true);
  });

  it('draws the map only in map mode, and redraws it for a new width', async () => {
    let watch: (() => void) | null = null;
    globalThis.ResizeObserver = class {
      constructor(callback: () => void) {
        watch = callback;
      }
      observe(): void {}
      unobserve(): void {}
      disconnect(): void {}
    } as unknown as typeof ResizeObserver;
    show(<MapCard tag={LONDON} mode="quiet" dark={false} />);
    await act(async () => Promise.resolve());
    expect(leaflet.imported).toBe(0);
    rerender(<MapCard tag={LONDON} mode="map" dark={false} />);
    await waitUntil(() => expect(leaflet.maps).toHaveLength(1));
    const made = leaflet.maps[0]!;
    // The Fold opening: Leaflet is told its box changed, and the tag is set where the pin is again.
    act(() => watch!());
    expect(made.resized).toBe(1);
    expect(made.views).toEqual([
      [[51.5074, -0.1278], 15],
      [[51.5074, -0.1278], 15],
    ]);
  });

  it('waits for the box to have a size, and draws once it does', async () => {
    sized(0);
    let watch: (() => void) | null = null;
    globalThis.ResizeObserver = class {
      constructor(callback: () => void) {
        watch = callback;
      }
      observe(): void {}
      unobserve(): void {}
      disconnect(): void {}
    } as unknown as typeof ResizeObserver;
    show(<MapCard tag={LONDON} mode="map" dark={false} />);
    await waitUntil(() => expect(watch).not.toBeNull());
    expect(leaflet.maps).toHaveLength(0);
    sized(412);
    act(() => watch!());
    expect(leaflet.maps).toHaveLength(1);
  });

  it('is taken down with the card, and an unmount before Leaflet arrives draws nothing', async () => {
    show(<MapCard tag={LONDON} mode="map" dark={false} />);
    await waitUntil(() => expect(leaflet.maps).toHaveLength(1));
    unmount();
    expect(leaflet.maps[0]!.removed).toBe(true);
    show(<MapCard tag={LONDON} mode="map" dark={false} />);
    unmount();
    await act(async () => {
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(leaflet.maps).toHaveLength(1);
  });
});

describe('Leaflet’s weight', () => {
  /*
   * Leaflet (150 kB, and 15 kB of CSS) arrives only when a map is shown, as its own chunk: never in the page's entry
   * (which the OTA manifest and the deploy key on) and never in the chunk the shared page shares with the app. The
   * build shows it; nothing in a test run would, so the sources are read for the one way in there is.
   */
  const src = dirname(dirname(import.meta.dirname));
  const walk = (dir: string): string[] =>
    readdirSync(dir).flatMap((name) => {
      const path = join(dir, name);
      return statSync(path).isDirectory() ? walk(path) : [path];
    });
  const code = walk(src)
    .filter((file) => /\.tsx?$/.test(file) && !file.includes('.test.'))
    .map((file) => ({ file: relative(src, file), text: readFileSync(file, 'utf8') }));

  it('is imported by value only inside the card, and only lazily', () => {
    const statics = code.filter(({ text }) => /^\s*import\s+(?!type\b)[^;]*?from\s+['"]leaflet(\/[^'"]*)?['"]|^\s*import\s+['"]leaflet(\/[^'"]*)?['"]/m.test(text));
    expect(statics.map(({ file }) => file)).toEqual([]);
    const lazy = code.filter(({ text }) => /import\(\s*['"]leaflet(\/[^'"]*)?['"]\s*\)/.test(text));
    expect(lazy.map(({ file }) => file)).toEqual([join('app', 'editor', 'MapCard.tsx')]);
  });

  it('is reached from the shared page only through a lazy card', () => {
    const reader = code.filter(({ file }) => file.startsWith(`read${'/'}`));
    for (const { file, text } of reader) {
      expect(text, file).not.toMatch(/^\s*import\s+(?!type\b)[^;]*?from\s+['"][^'"]*editor\/MapCard\.tsx['"]/m);
    }
    expect(reader.some(({ text }) => /import\(\s*['"][^'"]*editor\/MapCard\.tsx['"]\s*\)/.test(text))).toBe(true);
  });
});
