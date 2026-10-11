import { createElement, useEffect } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { Calculator, Globe } from '@glacier/icons';
import { show } from '../../test/render.tsx';
import { iconElement } from './iconDom.ts';

/**
 * A square's icon (editor/blanks.ts) is asked for while React is committing the editor: Editor.tsx makes its view in
 * an effect, and the view draws its widgets there. An icon asked for there must still arrive, paths and all, and an
 * empty `<svg>` must never be what is kept.
 */

describe('an icon for the editor', () => {
  it('arrives when it was asked for inside an effect, as the editor asks, and is copied whole after', async () => {
    let first: SVGElement | null = null;
    function Asks() {
      useEffect(() => {
        first = iconElement(Globe);
      }, []);
      return null;
    }
    show(createElement(Asks));
    await vi.waitFor(() => expect(first?.querySelector('path, circle')).not.toBeNull());
    expect(first!.getAttribute('viewBox')).toBe('0 0 24 24');
    const later = iconElement(Globe);
    expect(later).not.toBe(first);
    expect(later.innerHTML).toBe(first!.innerHTML);
  });

  it('keeps each stroke width apart', async () => {
    const thin = iconElement(Calculator, 1.5);
    const thick = iconElement(Calculator, 2.5);
    await vi.waitFor(() => expect(thin.querySelector('path, rect, line')).not.toBeNull());
    await vi.waitFor(() => expect(thick.querySelector('path, rect, line')).not.toBeNull());
    expect(thin.getAttribute('stroke-width')).toBe('1.5');
    expect(thick.getAttribute('stroke-width')).toBe('2.5');
  });
});
