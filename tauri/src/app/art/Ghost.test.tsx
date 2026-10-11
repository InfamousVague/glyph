import { describe, expect, it } from 'vitest';
import type { ReactElement } from 'react';
import { show } from '../../test/render.tsx';
import { Ghost } from './Ghost.tsx';
import { GHOST_RATIOS, GHOSTS, type GhostScene } from './ghosts.ts';

/** The ghost itself, drawn: the element it renders, not the host around it. */
const drawn = (element: ReactElement): HTMLElement => show(element).firstElementChild as HTMLElement;

describe('the ghost', () => {
  it('has a picture for every scene, each its own file', () => {
    const files = Object.values(GHOSTS);
    expect(files).toHaveLength(14);
    expect(new Set(files).size).toBe(14);
  });

  it('is drawn in the page’s ink through its picture, hidden from a screen reader, at the size asked', () => {
    const ghost = drawn(<Ghost scene="no-notes" size="lead" align="center" />);
    expect(ghost.getAttribute('aria-hidden')).toBe('true');
    expect(ghost.getAttribute('data-size')).toBe('lead');
    expect(ghost.getAttribute('data-align')).toBe('center');
    expect(ghost.style.getPropertyValue('--ghost-image')).toBe(`url("${GHOSTS['no-notes']}")`);
    // Its own shape, cropped to the drawing: no picture is a square with room round it any more.
    expect(Number(ghost.style.getPropertyValue('--ghost-ratio'))).toBeCloseTo(GHOST_RATIOS['no-notes']);
  });

  it('is small and at the start unless told otherwise, and keeps a class it is given', () => {
    const scene: GhostScene = 'welcome';
    const ghost = drawn(<Ghost scene={scene} className="here" />);
    expect(ghost.getAttribute('data-size')).toBe('small');
    expect(ghost.getAttribute('data-align')).toBe('start');
    expect(ghost.className).toContain('here');
  });
});
