import { act, useRef } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DOCK_SMOKE_REACH, dockSmokeMask, useDockSmoke } from './dockSmoke.ts';

/**
 * The wisp round the home page's dock (art/dockSmoke.ts; Matt: "Change the shadow behind the floating dock to be the
 * wisp blur effect we use on the bottom under the header"): the mask's image, made for the halo's size from the
 * header's recipe, the hook that gives it to the halo once it is measured, and the dock with no drop shadow.
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
  it('is an image the halo’s size, the header’s turbulence over a ramp from a pill half the reach out', () => {
    const svg = svgOf(dockSmokeMask(155.4, 299.2));
    expect(svg).toContain('width="155" height="299"');
    expect(svg).toContain('<feTurbulence type="fractalNoise"');
    // The noise on the ramp and the curve to alpha, as art/wispMask.ts makes the header's band.
    expect(svg).toContain('operator="arithmetic" k1="0" k2="0.9" k3="1" k4="-0.45"');
    const out = DOCK_SMOKE_REACH / 2;
    expect(svg).toContain(`<rect x="${out}" y="${out}" width="${155 - 2 * out}" height="${299 - 2 * out}" rx="${(155 - 2 * out) / 2}" fill="#fff"/>`);
  });

  it('is given to the halo once it is measured', () => {
    const halo = draw(155, 299);
    expect(halo.dataset.smoke).toBe('');
    expect(halo.style.getPropertyValue('mask-image') || halo.style.getPropertyValue('-webkit-mask-image')).toContain('data:image/svg+xml');
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
  });
});
