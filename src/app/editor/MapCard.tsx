import { useEffect, useRef, useState } from 'react';
import type { Map as LeafletMap } from 'leaflet';
import { PLACE_PATH } from '../art/Icons.tsx';
import { tagLabel, type GeoTag } from '../core/geotag.ts';
import { prefersStill } from '../core/motion.ts';
import { openPlace } from '../core/placeLink.ts';
import styles from './MapCard.module.css';

/**
 * The map card: where a note was written, drawn at the top of the note with the byline (editor/NoteScreen.tsx) and on
 * a shared page (src/read/Reader.tsx). Matt: "show a map card embedded on the note". A dumb component: it draws the
 * tag it is given, never reads the note, never asks for a name and never writes.
 *
 * Two layers, always both. Under, the quiet card: paper, a faint dot grid (a map without a map, in the dotwork family
 * of the ghost) and the pin, or a ring for a rough tag, since an area is not a point. The pin is the same drawing in
 * the same place on both layers, so a map arriving only deepens its ink. It sits a little below the middle of the box
 * (the map is centred to match), clear of the place's chip above it and the chips at the foot. Over it, in `map` mode,
 * OpenStreetMap's tiles through Leaflet, fading in once the tile layer has loaded, whatever a failed tile said
 * before: loading, offline and every tile failed are one state, the quiet card. No spinner, no error copy. The tile
 * pane is greyed and washed with the page's paper so every tile sits between the fourth and third inks and the pin is
 * the only full-ink mark, inverted on a dark page from the app's own theme (`dark`, never the OS's). Leaflet is
 * imported only here and only for a map, so it arrives as its own chunk and never in the page's entry.
 *
 * In `ask` mode (the reader) the quiet card carries "Show the map" and a tap fetches nothing until then. Otherwise a
 * tap opens the place in the device's maps app (core/placeLink.ts `openPlace`), with the place or the coordinates and
 * never the note's title. That module is kept apart from core/location.ts so a shared page loads none of the rest.
 *
 * Two sizes (docs/DESIGN.md §144): the card, and the header a note made from A map at the top wears (`look: map`),
 * 10rem tall on a phone and 16rem from 600px, as wide as the note's column up to 48rem. And `MapPicture`: the same box
 * with the quiet layer alone, for a box held while a new note's fix is on its way, a map note with no place yet, and
 * the template cards. No tag, no button, no Leaflet, no credit, nothing asked; `inert`, since it is a picture.
 */

/** The ordinary card, or the header across a map note's column (`look: map`). */
export type MapSize = 'card' | 'header';

export interface MapCardProps {
  tag: GeoTag;
  /** The card, or a map note's header. */
  size?: MapSize;
  /** Tiles from OpenStreetMap; the quiet card (coordinates and a drawn pin); or the quiet card with "Show the map" on it, one tap from tiles (the reader). */
  mode: 'map' | 'quiet' | 'ask';
  /** Why the card is quiet, said in a chip, or nothing (offline, a failed tile, a tile switch). */
  quietWhy?: 'local-only' | 'off';
  dark: boolean;
  /** `ask` pressed: the caller switches mode to `map`. */
  onShow?: () => void;
  /** The card just appeared on an open note: it arrives on the kit's beat rather than popping in at full height. */
  arrive?: boolean;
  /** The tag was just taken off: the card leaves on the same beat, then `onLeft` lets it go. */
  leave?: boolean;
  onLeft?: () => void;
  /**
   * The place's chip at the top of the card: on by default. A card under a place line in the words (editor/placeCards.ts)
   * leaves it off, because the line above it already says the name.
   */
  where?: boolean;
  className?: string;
}

/** OpenStreetMap's standard tiles, under its tile usage policy (docs/THIRD_PARTY.md). */
const OSM_TILES = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
/** How long the card takes to leave, as the arrival's beat (MapCard.module.css `mapLeave`). */
const LEAVE_MS = 300;

/** A street for a fine tag; for a rough one a district, a step wider than the name is asked at, so its ring fits the box. */
const zoomOf = (rough: boolean) => (rough ? 11 : 15);

/**
 * How wide a rough tag's ring is drawn, in pixels at its zoom (11): the half diagonal of the cell its two decimals
 * round to. A hundredth of a degree of longitude is 14.6 px at that zoom anywhere; of latitude, that over the
 * latitude's cosine (Web Mercator's stretch), so the ring's radius is 14 px in London, 10 at the equator and more
 * towards the poles. A ring of a fixed size read as a precise spot; at zoom 12 the true one crowded the chips.
 */
function ringRadius(lat: number): number {
  const half = (0.01 / 360) * 256 * 2 ** zoomOf(true) * 0.5;
  const cos = Math.max(0.2, Math.cos((lat * Math.PI) / 180));
  return Math.round(Math.min(18, Math.max(10, Math.hypot(half, half / cos))));
}

/**
 * The mark, on both layers: the app's pin, its body filled with the paper so it reads over tiles, its tip on the
 * place; or, for a rough tag, a ring the size of the area its decimals leave open, since an area is not a point.
 * Drawn by the card rather than as Leaflet's marker: the map never moves from the tag it was centred on, so the place
 * is always the same spot in the box, and Leaflet's marker pane sits inside its map pane, under the wash, where the
 * pin would be as grey as the streets.
 */
function MapMark({ rough, lat, over }: { rough: boolean; lat: number; over: boolean }) {
  const r = ringRadius(lat);
  const box = 2 * r + 4;
  return (
    <span className={`${styles.mark} ${over ? styles.over : ''}`} data-rough={rough || undefined} aria-hidden="true" style={rough ? { translate: `${-box / 2}px ${-box / 2}px` } : undefined}>
      {rough ? (
        <svg viewBox={`0 0 ${box} ${box}`} width={box} height={box}>
          <circle cx={box / 2} cy={box / 2} r={r} fill="color-mix(in srgb, currentColor 10%, transparent)" stroke="currentColor" strokeWidth="2.4" />
        </svg>
      ) : (
        <svg viewBox="0 0 24 24" width="28" height="28">
          <path d={PLACE_PATH} fill="var(--app-paper)" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
          <circle cx="12" cy="10.5" r="2.2" fill="currentColor" />
        </svg>
      )}
    </span>
  );
}

const WHY = { 'local-only': 'Local only is on.', off: 'Map off in Settings.' } as const;

export function MapCard({ tag, size = 'card', mode, quietWhy, dark, onShow, arrive, leave, onLeft, where = true, className }: MapCardProps) {
  const mapEl = useRef<HTMLDivElement>(null);
  const [loaded, setLoaded] = useState(false);
  const { lat, lon, rough } = tag;
  const left = useRef(onLeft);
  left.current = onLeft;

  // Leaving: the card goes on its beat, and then is let go (at once, for a phone that asks for less motion).
  useEffect(() => {
    if (!leave) return undefined;
    const timer = window.setTimeout(() => left.current?.(), prefersStill() ? 0 : LEAVE_MS);
    return () => window.clearTimeout(timer);
  }, [leave]);

  useEffect(() => {
    if (mode !== 'map') return undefined;
    const el = mapEl.current;
    if (!el) return undefined;
    let live = true;
    let map: LeafletMap | null = null;
    let observer: ResizeObserver | null = null;
    const zoom = zoomOf(rough);
    void (async () => {
      const mod = await import('leaflet');
      await import('leaflet/dist/leaflet.css');
      // Unmounted before Leaflet arrived: nothing to draw into.
      if (!live) return;
      const L = (mod.default ?? mod) as typeof import('leaflet');
      // A map made at 0×0 never loads a tile and never fades in: it waits for the box to have a size.
      const make = () => {
        if (map || !live || !el.clientWidth || !el.clientHeight) return;
        map = L.map(el, {
          attributionControl: false,
          zoomControl: false,
          dragging: false,
          touchZoom: false,
          scrollWheelZoom: false,
          doubleClickZoom: false,
          boxZoom: false,
          keyboard: false,
          tapHold: false,
          // The map is a picture: nothing on it moves.
          fadeAnimation: false,
          zoomAnimation: false,
          markerZoomAnimation: false,
        });
        map.setView([lat, lon], zoom);
        // Standard tiles, not retina ones: at the Fold's 2.6 dpr the z+1 tiles drawn at half size were sharper but
        // twice as busy (every shop's mark, the street names at half size), and the card is a picture under a wash.
        // The page's origin as the Referer, which OSM's tile policy asks of a web page: the shared page sends none
        // of its own (read.html's no-referrer, which guards the share's address), and an origin carries no share.
        const tiles = L.tileLayer(OSM_TILES, { maxZoom: 19, detectRetina: false, referrerPolicy: 'strict-origin' });
        // The map shows once its tiles are in, whatever a failed one said on the way: a failed tile is the map's
        // paper. Only a map with no tile at all (offline, every one refused) stays the quiet card.
        let drawn = false;
        tiles.on('tileload', () => {
          drawn = true;
        });
        tiles.on('load', () => {
          if (live && drawn) setLoaded(true);
        });
        tiles.addTo(map);
        // No Leaflet marker (its default image's path detection 404s under a bundler, and its pane is under the
        // wash): the card draws the pin at the middle of the box itself (MapMark).
      };
      make();
      // The Fold opening, or a hidden tab coming back: the tiles are redrawn for the new width.
      if (typeof ResizeObserver !== 'undefined') {
        observer = new ResizeObserver(() => {
          if (!map) {
            make();
            return;
          }
          map.invalidateSize({ animate: false });
          map.setView([lat, lon], zoom, { animate: false });
        });
        observer.observe(el);
      }
    })();
    return () => {
      live = false;
      observer?.disconnect();
      map?.remove();
      map = null;
      setLoaded(false);
    };
  }, [mode, lat, lon, rough]);

  const label = tagLabel(tag);
  // OSM's data is credited where it is shown: the tiles, or the name it gave. The coordinates are the phone's.
  const credit = (mode === 'map' && loaded) || tag.place !== null;
  const asks = mode === 'ask';
  const press = () => {
    if (asks) onShow?.();
    else void openPlace(tag).catch(() => undefined);
  };

  return (
    <div
      className={`${styles.card} ${className ?? ''}`}
      data-dark={dark || undefined}
      data-size={size}
      data-loaded={loaded || undefined}
      data-mode={mode}
      data-rough={rough || undefined}
      data-arrive={(arrive && !leave) || undefined}
      data-leave={leave || undefined}
    >
      <div className={styles.quiet} aria-hidden="true">
        <MapMark rough={rough} lat={lat} over={false} />
      </div>
      {mode === 'map' ? <div ref={mapEl} className={styles.map} aria-hidden="true" /> : null}
      {mode === 'map' ? <MapMark rough={rough} lat={lat} over /> : null}
      {where ? <span className={`${styles.chip} ${styles.where}`}>{label}</span> : null}
      {asks ? (
        <span className={`${styles.chip} ${styles.why} ${styles.show}`}>
          <svg viewBox="0 0 24 24" width="12" height="12" aria-hidden="true">
            <path d="M3 6.5l6-2.5 6 2.5 6-2.5v13.5l-6 2.5-6-2.5-6 2.5zM9 4v13.5M15 6.5v13.5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" />
          </svg>
          Show the map
        </span>
      ) : quietWhy && mode === 'quiet' ? (
        <span className={`${styles.chip} ${styles.why}`}>{WHY[quietWhy]}</span>
      ) : null}
      {credit ? <span className={`${styles.chip} ${styles.credit}`}>© OpenStreetMap contributors</span> : null}
      <button type="button" className={styles.tap} aria-label={asks ? 'Show the map' : `Open ${label} on a map`} onClick={press} disabled={leave} />
    </div>
  );
}

export interface MapPictureProps {
  size?: MapSize;
  /** A stand-in pin, where the card would put one: on a template's card, which shows a map it has no place for yet. */
  pin?: boolean;
  /** Why the box has no map, said in its chip, or nothing while a fix is on its way. */
  why?: string;
  dark: boolean;
  className?: string;
}

/**
 * The map's box with no map in it: the quiet layer alone, the card's own box and dot grid, so a box held for a fix and
 * the card that arrives in it are the same box and nothing moves. A picture: no button, nothing to press, nothing read
 * out, and nothing fetched.
 */
export function MapPicture({ size = 'card', pin = false, why, dark, className }: MapPictureProps) {
  return (
    <div className={`${styles.card} ${styles.picture} ${className ?? ''}`} data-dark={dark || undefined} data-size={size} data-mode="quiet" aria-hidden="true" inert>
      <div className={styles.quiet}>{pin ? <MapMark rough={false} lat={0} over={false} /> : null}</div>
      {why ? <span className={`${styles.chip} ${styles.why}`}>{why}</span> : null}
    </div>
  );
}
