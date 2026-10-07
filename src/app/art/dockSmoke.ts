import { useLayoutEffect, type RefObject } from 'react';
import { isAndroid } from '../core/platform.ts';
import { followWispDrift } from './wispEdge.ts';
import { wispDraw, wispHead } from './wispMask.ts';

/**
 * The wisp around the home page's floating dock (home/HomeScreen.module.css `.dockHalo`; Matt: "Change the shadow
 * behind the floating dock to be the wisp blur effect we use on the bottom under the header").
 *
 * The dock had a dark drop shadow and, behind it, a halo that blurred what scrolled under it and feathered away
 * evenly. The shadow is gone and the halo's edge is the header's smoke: turbulence over a soft ramp, torn into
 * tendrils rather than misted (art/wispMask.ts makes the header's band the same way), with the ramp wrapped round the
 * dock's pill instead of laid along a header's lip. A mask, as the Mac's header wears, on every engine: the filter
 * that bends the page under a phone's header is worn by the page itself, and nothing can bend only what lies round a
 * floating thing (`backdrop-filter: url()` is not in WebKit).
 *
 * **It moves as the header's does** (Matt: "it's static on the dock and it doesn't match"). The first cut was one
 * picture, noise and ramp together, so it could not: a pill's ramp cannot slide. It is three layers now, composed by
 * the stylesheet: a soft core that keeps the halo whole at the pill, over a wider ramp cut by a tile of smoke. The
 * tile slides and the other two stay, so the tendrils past the core sway while the halo keeps its shape. The slide
 * is the page band's own (art/wispEdge.ts `followWispDrift`): the same few pixels, on the same clock, only while the
 * page is being scrolled, still with reduced motion and while a recording holds the drift.
 *
 * **And on a phone it bends what scrolls behind it, as the foot does** (Matt: "the smoke effect warbles and wobbles as
 * I scroll but the dock remains static breaking the effect"). The slide alone was true to the header's and too faint
 * to see: a few pixels over twenty seconds, on a blur. What warbles at the foot is the page itself, bent by the noise
 * as it scrolls through, and a mask bends nothing. Chromium takes an SVG filter as a backdrop filter, which is the one
 * way to bend only what lies behind a floating thing, so on Android the halo's backdrop is the foot's own recipe
 * (`DOCK_BEND_FILTER_ID`, drawn by art/WispEdgeFilter.tsx): the same turbulence, the same strength, breathed by the
 * same drift. WebKit has no such backdrop filter, and the Mac's header has no smoke to match, so there the
 * halo stays the blur under the sliding mask.
 *
 * The core and the ramp are made for the halo's own size, measured, since they follow the pill and the pill's size is
 * the dock's: two buttons or four, a phone or the Fold. Until it is measured, and where nothing lays out (a test),
 * the halo keeps the plain feather its stylesheet gives it.
 */

/** How far past the pill the smoke reaches, in px: the halo's inset (`.dockHalo`, 3rem). */
export const DOCK_SMOKE_REACH = 48;
/** The smoke tile's side, in px: it repeats, stitched so no seam shows as it slides. */
export const DOCK_SMOKE_TILE = 256;

/** The filter that bends the halo's backdrop, and its noise, which the drift breathes (art/WispEdgeFilter.tsx). */
export const DOCK_BEND_FILTER_ID = 'dockWisp';
export const DOCK_BEND_NOISE_ID = 'dockWispNoise';

/**
 * Whether the halo bends its backdrop: where the page's own foot is bent (a phone drawing the filter), on the one
 * engine that takes an SVG filter as a backdrop filter.
 */
export function dockBends(): boolean {
  return isAndroid && wispDraw() === 'filter' && wispHead() === 'smoke';
}

const image = (svg: string) => `url("data:image/svg+xml,${encodeURIComponent(svg)}")`;

/**
 * A pill in ink, soft at its edge, for a halo `width` by `height` whose dock stands `reach` in from every side: the
 * pill stands `out` past the dock's own edge and is blurred by `soft`. Alpha is what a mask reads: ink is shown.
 */
function softPill(width: number, height: number, reach: number, out: number, soft: number): string {
  const w = Math.max(1, Math.round(width));
  const h = Math.max(1, Math.round(height));
  const inset = Math.max(0, reach - out);
  const inner = { w: Math.max(1, w - 2 * inset), h: Math.max(1, h - 2 * inset) };
  return image(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}">` +
      `<filter id="b" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="${soft}"/></filter>` +
      `<rect x="${inset}" y="${inset}" width="${inner.w}" height="${inner.h}" rx="${Math.min(inner.w, inner.h) / 2}" fill="#000" filter="url(#b)"/>` +
      `</svg>`,
  );
}

/** The halo's core: whole at the dock's edge and gone a third of the reach out, so the pill never stands on a hole. */
export function dockSmokeCore(width: number, height: number, reach = DOCK_SMOKE_REACH): string {
  return softPill(width, height, reach, Math.round(reach * 0.12), Math.max(1, Math.round(reach * 0.1)));
}

/** The ramp the smoke is cut from: strong near the dock, nothing by the halo's edge, so the image's own sides never show. */
export function dockSmokeRamp(width: number, height: number, reach = DOCK_SMOKE_REACH): string {
  return softPill(width, height, reach, Math.round(reach * 0.5), Math.max(1, Math.round(reach * 0.2)));
}

/**
 * The smoke itself: a tile of the header's turbulence, taken to alpha through a curve that leaves tendrils and clear
 * between them, the same both ways since a halo leaves the dock on every side. Made once.
 */
export function dockSmokeTile(): string {
  const t = DOCK_SMOKE_TILE;
  return image(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${t}" height="${t}">` +
      `<filter id="s" x="0" y="0" width="1" height="1" color-interpolation-filters="sRGB">` +
      `<feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="3" seed="7" stitchTiles="stitch" result="raw"/>` +
      // The noise's red, as alpha: the rest of the picture is ink.
      `<feColorMatrix in="raw" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  1 0 0 0 0" result="alpha"/>` +
      `<feComponentTransfer in="alpha"><feFuncA type="table" tableValues="0 0 0.05 0.5 0.95 1 1"/></feComponentTransfer>` +
      `</filter>` +
      `<rect width="${t}" height="${t}" filter="url(#s)"/>` +
      `</svg>`,
  );
}

let tile: string | null = null;

/**
 * The halo at `ref` given its smoke: its core and ramp made for its size, and again when the dock changes size, and
 * its tile slid with the page's smoke. Nothing where nothing lays out or sizes cannot be watched, which leaves the
 * stylesheet's feather.
 */
export function useDockSmoke(ref: RefObject<HTMLElement | null>): void {
  useLayoutEffect(() => {
    const halo = ref.current;
    if (!halo || typeof ResizeObserver !== 'function') return undefined;
    let drawn = '';
    const draw = () => {
      const { width, height } = halo.getBoundingClientRect();
      if (width < 2 * DOCK_SMOKE_REACH + 2 || height < 2 * DOCK_SMOKE_REACH + 2) return;
      const key = `${Math.round(width)}x${Math.round(height)}`;
      if (key === drawn) return;
      drawn = key;
      halo.style.setProperty('--dock-smoke-core', dockSmokeCore(width, height));
      halo.style.setProperty('--dock-smoke-ramp', dockSmokeRamp(width, height));
      halo.style.setProperty('--dock-smoke-tile', (tile ??= dockSmokeTile()));
      halo.dataset.smoke = '';
    };
    draw();
    const sizes = new ResizeObserver(draw);
    sizes.observe(halo);
    // Written on the halo alone, as the header's slide is written on its own views: a property set on the root this
    // often would restyle the whole document.
    const bends = dockBends();
    if (bends) halo.dataset.bend = '';
    const unfollow = followWispDrift((dx, dy, frequency) => {
      halo.style.setProperty('--dock-smoke-x', `${dx}px`);
      halo.style.setProperty('--dock-smoke-y', `${dy}px`);
      if (!bends) return;
      document.getElementById(DOCK_BEND_NOISE_ID)?.setAttribute('baseFrequency', frequency);
    });
    return () => {
      sizes.disconnect();
      unfollow();
    };
  }, [ref]);
}
