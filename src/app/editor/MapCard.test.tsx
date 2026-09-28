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
    maps: [] as { el: HTMLElement; options: Record<string, unknown>; views: unknown[]; removed: boolean }[],
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
      const made = { el, options, views: [] as unknown[], removed: false };
      leaflet.maps.push(made);
      return {
        setView: (at: unknown, zoom: number) => made.views.push([at, zoom]),
        invalidateSize: () => undefined,
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

describe('the quiet card', () => {
  it('shows the pin and the coordinates, imports no map, and credits nobody until there is a place', async () => {
    show(<MapCard tag={LONDON} mode="quiet" dark={false} />);
    await act(async () => Promise.resolve());
    expect(leaflet.imported).toBe(0);
    expect(document.querySelector('[class*=pinMark]')).not.toBeNull();
    expect(chips()).toEqual(['51.5074, -0.1278']);
    rerender(<MapCard tag={NAMED} mode="quiet" dark={false} />);
    expect(chips()).toEqual(['Trafalgar Square, London', '© OpenStreetMap contributors']);
    expect(tap().getAttribute('aria-label')).toBe('Open Trafalgar Square, London on a map');
  });

  it('says why it is quiet, and draws a ring for a rough tag', () => {
    show(<MapCard tag={{ ...LONDON, lat: 51.51, lon: -0.13, rough: true }} mode="quiet" quietWhy="local-only" dark={false} />);
    expect(chips()).toEqual(['Roughly 51.51, -0.13', 'Local only is on.']);
    expect(document.querySelector('[class*=ring]')).not.toBeNull();
    expect(document.querySelector('[class*=pinMark]')).toBeNull();
    rerender(<MapCard tag={LONDON} mode="quiet" quietWhy="off" dark={false} />);
    expect(chips()).toEqual(['51.5074, -0.1278', 'Map off in Settings.']);
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
    expect(leaflet.tiles[0]).toMatchObject({ url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', options: { maxZoom: 19 } });
    // Never Leaflet's marker nor its picture: the card's own pin, over the wash.
    expect(leaflet.markers).toHaveLength(0);
    expect(leaflet.icons).toHaveLength(0);
    expect(leaflet.iconImages).toBe(0);
    expect(document.querySelector('[class*=mark] path')).not.toBeNull();
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

  it('draws a rough tag at zoom 12 with a ring', async () => {
    show(<MapCard tag={{ ...LONDON, lat: 51.51, lon: -0.13, rough: true }} mode="map" dark />);
    await waitUntil(() => expect(leaflet.maps).toHaveLength(1));
    expect(leaflet.maps[0]!.views).toEqual([[[51.51, -0.13], 12]]);
    expect(document.querySelector('[class*=mark][data-rough] circle')).not.toBeNull();
    expect(document.querySelector('[class*=mark] path')).toBeNull();
    expect(card().hasAttribute('data-dark')).toBe(true);
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
