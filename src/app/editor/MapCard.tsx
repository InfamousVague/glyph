import { useEffect, useRef, useState } from 'react';
import type { Map as LeafletMap } from 'leaflet';
import { PLACE_PATH, Place } from '../art/Icons.tsx';
import { tagLabel, type GeoTag } from '../core/geotag.ts';
import { openPlace } from '../core/location.ts';
import styles from './MapCard.module.css';

/**
 * The map card: where a note was written, drawn at the top of the note with the byline (editor/NoteScreen.tsx) and on
 * a shared page (src/read/Reader.tsx). Matt: "show a map card embedded on the note". A dumb component: it draws the
 * tag it is given, never reads the note, never asks for a name and never writes.
 *
 * Two layers, always both. Under, the quiet card: paper, a faint dot grid (a map without a map, in the dotwork family
 * of the ghost) and the drawn pin, or a ring for a rough tag, since an area is not a point. Over it, in `map` mode,
 * OpenStreetMap's tiles through Leaflet, fading in once the tile layer has loaded, whatever a failed tile said
 * before: loading, offline and every tile failed are one state, the quiet card. No spinner, no error copy. The tile
 * pane is greyed and washed with the page's paper so every tile sits between the fourth and third inks and the pin is
 * the only full-ink mark, inverted on a dark page from the app's own theme (`dark`, never the OS's). Leaflet is
 * imported only here and only for a map, so it arrives as its own chunk and never in the page's entry.
 *
 * In `ask` mode (the reader) the quiet card carries "Show the map" and a tap fetches nothing until then. Otherwise a
 * tap opens the place in the device's maps app (core/location.ts `openPlace`), with the place or the coordinates and
 * never the note's title.
 */

export interface MapCardProps {
  tag: GeoTag;
  /** Tiles from OpenStreetMap; the quiet card (coordinates and a drawn pin); or the quiet card with "Show the map" on it, one tap from tiles (the reader). */
  mode: 'map' | 'quiet' | 'ask';
  /** Why the card is quiet, said in a chip, or nothing (offline, a failed tile, a tile switch). */
  quietWhy?: 'local-only' | 'off';
  dark: boolean;
  /** `ask` pressed: the caller switches mode to `map`. */
  onShow?: () => void;
  /** The card just appeared on an open note: it arrives on the kit's beat rather than popping in at full height. */
  arrive?: boolean;
  className?: string;
}

/** OpenStreetMap's standard tiles, under its tile usage policy (docs/THIRD_PARTY.md). */
const OSM_TILES = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/** The pin as the map's marker: the app's own line, its body filled with the paper so it reads over tiles. */
const PIN_SVG = `<svg viewBox="0 0 24 24" width="28" height="28" aria-hidden="true"><path d="${PLACE_PATH}" fill="var(--app-paper)" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/><circle cx="12" cy="10.5" r="2.2" fill="currentColor"/></svg>`;
/** A rough tag's mark: a ring, since an area is not a point. */
const RING_SVG = `<svg viewBox="0 0 32 32" width="32" height="32" aria-hidden="true"><circle cx="16" cy="16" r="14" fill="color-mix(in srgb, currentColor 10%, transparent)" stroke="currentColor" stroke-width="2.4"/></svg>`;

const WHY = { 'local-only': 'Local only is on.', off: 'Map off in Settings.' } as const;

export function MapCard({ tag, mode, quietWhy, dark, onShow, arrive, className }: MapCardProps) {
  const mapEl = useRef<HTMLDivElement>(null);
  const [loaded, setLoaded] = useState(false);
  const { lat, lon, rough } = tag;

  useEffect(() => {
    if (mode !== 'map') return undefined;
    const el = mapEl.current;
    if (!el) return undefined;
    let live = true;
    let map: LeafletMap | null = null;
    let observer: ResizeObserver | null = null;
    // A street for a fine tag, a district for a rough one.
    const zoom = rough ? 12 : 15;
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
        const tiles = L.tileLayer(OSM_TILES, { maxZoom: 19, detectRetina: false });
        tiles.on('load', () => {
          if (live) setLoaded(true);
        });
        tiles.addTo(map);
        // Never Leaflet's own marker image, whose path detection 404s under a bundler: the app's pin, as a div icon.
        const icon = L.divIcon({ className: styles.pin, html: rough ? RING_SVG : PIN_SVG, iconSize: rough ? [32, 32] : [28, 28], iconAnchor: rough ? [16, 16] : [14, 27] });
        L.marker([lat, lon], { icon, interactive: false, keyboard: false }).addTo(map);
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
  const credit = (mode === 'map') || tag.place !== null;
  const asks = mode === 'ask';
  const press = () => {
    if (asks) onShow?.();
    else void openPlace(tag).catch(() => undefined);
  };

  return (
    <div className={`${styles.card} ${className ?? ''}`} data-dark={dark || undefined} data-loaded={loaded || undefined} data-mode={mode} data-arrive={arrive || undefined}>
      <div className={styles.quiet} aria-hidden="true">
        {rough ? <span className={styles.ring} /> : <Place className={styles.pinMark} />}
      </div>
      {mode === 'map' ? <div ref={mapEl} className={styles.map} aria-hidden="true" /> : null}
      <span className={`${styles.chip} ${styles.where}`}>{label}</span>
      {asks ? (
        <span className={`${styles.chip} ${styles.why} ${styles.show}`}>Show the map</span>
      ) : quietWhy && mode === 'quiet' ? (
        <span className={`${styles.chip} ${styles.why}`}>{WHY[quietWhy]}</span>
      ) : null}
      {credit ? <span className={`${styles.chip} ${styles.credit}`}>© OpenStreetMap contributors</span> : null}
      <button type="button" className={styles.tap} aria-label={asks ? 'Show the map' : `Open ${label} on a map`} onClick={press} />
    </div>
  );
}
