import { useLayoutEffect, type RefObject } from 'react';

/**
 * The wisp around the home page's floating dock (home/HomeScreen.module.css `.dockHalo`; Matt: "Change the shadow
 * behind the floating dock to be the wisp blur effect we use on the bottom under the header").
 *
 * The dock had a dark drop shadow and, behind it, a halo that blurred what scrolled under it and feathered away
 * evenly. The shadow is gone and the halo's edge is the header's smoke: the same recipe art/wispMask.ts makes the
 * header's band from - turbulence over a soft ramp, taken to alpha through a steep curve, so the edge tears into
 * tendrils rather than misting - with the ramp wrapped round the dock's pill instead of laid along a header's lip.
 * A mask, as the Mac's header wears, on every engine: the filter that bends the page under a phone's header is worn
 * by the page itself, and nothing can bend only what lies around a floating thing (`backdrop-filter: url()` is not in
 * WebKit). A mask is rasterised once and composited on the GPU, so the notes scrolling under the dock redraw nothing.
 *
 * The image is made for the halo's own size, measured, since the ramp follows the pill and the pill's size is the
 * dock's: two buttons or four, a phone or the Fold. Until it is measured, and where nothing lays out (a test), the
 * halo keeps the plain feather its stylesheet gives it.
 */

/** How far past the pill the smoke reaches, in px: the halo's inset (`.dockHalo`, 3rem). */
export const DOCK_SMOKE_REACH = 48;

/**
 * The halo's mask for a halo `width` by `height`, the pill standing `reach` in from every side: white where the blur
 * and the wash show, torn to nothing by the smoke over the reach. Whole pixels, so one size is one image.
 */
export function dockSmokeMask(width: number, height: number, reach = DOCK_SMOKE_REACH): string {
  const w = Math.max(1, Math.round(width));
  const h = Math.max(1, Math.round(height));
  // The shape the ramp is blurred from stands half the reach past the pill: a blurred edge is half gone where the edge
  // was, so a ramp from the pill's own edge left smoke a few pixels deep. From here it is whole at the pill, half gone
  // midway, and nothing by the halo's edge, which is what keeps the image's own sides from showing.
  const out = Math.round(reach / 2);
  const inner = { w: Math.max(1, w - 2 * out), h: Math.max(1, h - 2 * out) };
  const radius = Math.min(inner.w, inner.h) / 2;
  const soft = Math.max(1, Math.round(reach * 0.26));
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}">` +
    `<filter id="s" x="0" y="0" width="1" height="1" color-interpolation-filters="sRGB">` +
    // Finer along the pill than the header's band, and the same both ways: the smoke leaves the dock on every side.
    `<feTurbulence type="fractalNoise" baseFrequency="0.045" numOctaves="3" seed="7" result="raw"/>` +
    // Opaque noise, or the arithmetic below would read a see-through value and lift the whole halo.
    `<feColorMatrix in="raw" type="matrix" values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 0 1" result="noise"/>` +
    `<feGaussianBlur in="SourceGraphic" stdDeviation="${soft}" result="ramp"/>` +
    // The ramp with the noise on it, as the header's band has it: the noise decides the tendrils.
    `<feComposite in="noise" in2="ramp" operator="arithmetic" k1="0" k2="0.9" k3="1" k4="-0.45" result="field"/>` +
    `<feColorMatrix in="field" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  1 0 0 0 0" result="alpha"/>` +
    // A gentler curve than the header's band: a halo thins out as it leaves the dock, where a header's lip is one line.
    `<feComponentTransfer in="alpha" result="torn"><feFuncA type="table" tableValues="0 0 0.08 0.3 0.62 0.86 1 1"/></feComponentTransfer>` +
    `<feFlood flood-color="#000" result="ink"/>` +
    `<feComposite in="ink" in2="torn" operator="in"/>` +
    `</filter>` +
    `<g filter="url(#s)">` +
    `<rect width="${w}" height="${h}" fill="#000"/>` +
    `<rect x="${out}" y="${out}" width="${inner.w}" height="${inner.h}" rx="${radius}" fill="#fff"/>` +
    `</g>` +
    `</svg>`;
  return `url("data:image/svg+xml,${encodeURIComponent(svg)}")`;
}

/**
 * The halo at `ref` given its smoke: its mask made for its size, and made again when the dock changes size. Nothing
 * where nothing lays out or sizes cannot be watched, which leaves the stylesheet's feather.
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
      const image = dockSmokeMask(width, height);
      halo.style.setProperty('-webkit-mask-image', image);
      halo.style.setProperty('mask-image', image);
      halo.dataset.smoke = '';
    };
    draw();
    const sizes = new ResizeObserver(draw);
    sizes.observe(halo);
    return () => sizes.disconnect();
  }, [ref]);
}
