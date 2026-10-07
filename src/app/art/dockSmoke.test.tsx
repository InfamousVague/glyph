import { act, useRef } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
const drift = vi.hoisted(() => ({ followers: new Set<(dx: number, dy: number) => void>() }));
vi.mock('./wispEdge.ts', () => ({
  followWispDrift: (follower: (dx: number, dy: number) => void) => {
    drift.followers.add(follower);
    return () => drift.followers.delete(follower);
  },
}));

const { DOCK_SMOKE_REACH, DOCK_SMOKE_TILE, dockSmokeCore, dockSmokeRamp, dockSmokeTile, useDockSmoke } = await import('./dockSmoke.ts');

/**
 * The wisp round the home page's dock (art/dockSmoke.ts; Matt: "Change the shadow behind the floating dock to be the
 * wisp blur effect we use on the bottom under the header"; "it's static on the dock and it doesn't match"): the three
 * pictures the halo's mask is composed from, the hook that gives them to the halo once it is measured and slides the
 * smoke with the page's, and the dock with no drop shadow.
 */

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const svgOf = (image: string) => decodeURIComponent(image.slice('url("data:image/svg+xml,'.length, -2));

let root: Root | null = null;
let host: HTMLElement | null = null;

afterEach(() => {
  act(() => root?.unmount());
  host?.remove();
  root = null;
  host = null;
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

function Halo() {
  const ref = useRef<HTMLDivElement>(null);
  useDockSmoke(ref);
  return <div ref={ref} data-halo="" />;
}

function draw(width: number, height: number): HTMLElement {
  vi.stubGlobal(
    'ResizeObserver',
    class {
      observe() {}
      disconnect() {}
    },
  );
  vi.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue({ width, height, top: 0, left: 0, right: width, bottom: height, x: 0, y: 0, toJSON: () => ({}) } as DOMRect);
  host = document.createElement('div');
  document.body.append(host);
  root = createRoot(host);
  act(() => root!.render(<Halo />));
  return host.querySelector<HTMLElement>('[data-halo]')!;
}

describe('the smoke round the dock', () => {
  it('is a core and a ramp the halo’s size, pills round the dock, the ramp the wider and the softer', () => {
    const core = svgOf(dockSmokeCore(155.4, 299.2));
    const ramp = svgOf(dockSmokeRamp(155.4, 299.2));
    for (const svg of [core, ramp]) expect(svg).toContain('width="155" height="299"');
    const pill = (out: number) => {
      const inset = DOCK_SMOKE_REACH - out;
      return `<rect x="${inset}" y="${inset}" width="${155 - 2 * inset}" height="${299 - 2 * inset}" rx="${(155 - 2 * inset) / 2}" fill="#000" filter="url(#b)"/>`;
    };
    expect(core).toContain(pill(Math.round(DOCK_SMOKE_REACH * 0.12)));
    expect(ramp).toContain(pill(DOCK_SMOKE_REACH / 2));
    const soft = (svg: string) => Number(/stdDeviation="([\d.]+)"/.exec(svg)![1]);
    expect(soft(ramp)).toBeGreaterThan(soft(core));
    // Neither holds noise: they stay put while the smoke slides.
    expect(core + ramp).not.toContain('feTurbulence');
  });

  it('is a tile of the header’s turbulence, stitched so it can slide without a seam', () => {
    const svg = svgOf(dockSmokeTile());
    expect(svg).toContain(`width="${DOCK_SMOKE_TILE}" height="${DOCK_SMOKE_TILE}"`);
    expect(svg).toContain('<feTurbulence type="fractalNoise"');
    expect(svg).toContain('stitchTiles="stitch"');
  });

  it('is given to the halo once it is measured', () => {
    const halo = draw(155, 299);
    expect(halo.dataset.smoke).toBe('');
    for (const name of ['--dock-smoke-core', '--dock-smoke-ramp', '--dock-smoke-tile']) expect(halo.style.getPropertyValue(name)).toContain('data:image/svg+xml');
  });

  it('slides with the page’s smoke, and lets go when the dock is gone', () => {
    const halo = draw(155, 299);
    expect(drift.followers.size).toBe(1);
    for (const follower of drift.followers) follower(2.5, 14);
    expect(halo.style.getPropertyValue('--dock-smoke-x')).toBe('2.5px');
    expect(halo.style.getPropertyValue('--dock-smoke-y')).toBe('14px');
    act(() => root?.unmount());
    root = null;
    expect(drift.followers.size).toBe(0);
  });

  it('leaves the stylesheet’s feather where nothing lays out', () => {
    const halo = draw(0, 0);
    expect(halo.dataset.smoke).toBeUndefined();
    expect(halo.getAttribute('style')).toBeNull();
  });

  it('stands in for the dock’s drop shadow, which is gone', () => {
    const css = readFileSync(join(process.cwd(), 'src/app/home/HomeScreen.module.css'), 'utf8');
    const dock = css.slice(css.indexOf('\n.dock {'), css.indexOf('}', css.indexOf('\n.dock {')));
    expect(dock).not.toMatch(/box-shadow\s*:/);
    expect(css).toContain('.dockHalo[data-smoke]');
    // The tile alone is placed by the drift: the core and the ramp stay.
    expect(css).toMatch(/\n {2}mask-position:\s+0 0,\s+0 0,\s+var\(--dock-smoke-x, 0px\) var\(--dock-smoke-y, 0px\);/);
  });
});
