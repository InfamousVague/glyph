import { createElement } from 'react';
import { flushSync } from 'react-dom';
import { createRoot } from 'react-dom/client';
import type { LucideIcon } from '@glacier/icons';

/**
 * The kit's icons as plain SVG elements, for what the editor draws outside React: a blank's square and its panel
 * (editor/blanks.ts, editor/fillPanel.ts). Each icon is drawn by React once, into a detached element, and copied from
 * then on, so a note with forty blanks draws forty copies, not forty React roots.
 */

const drawn = new Map<LucideIcon, SVGElement>();

/** A copy of `Icon` as an SVG element, sized to the text (`1em`), in the current ink, hidden from screen readers. */
export function iconElement(Icon: LucideIcon, strokeWidth = 2.2): SVGElement {
  let svg = drawn.get(Icon);
  if (!svg) {
    const host = document.createElement('div');
    const root = createRoot(host);
    flushSync(() => root.render(createElement(Icon, { size: '1em', strokeWidth, 'aria-hidden': true, focusable: false })));
    svg = host.querySelector('svg')?.cloneNode(true) as SVGElement | undefined;
    root.unmount();
    if (!svg) svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    drawn.set(Icon, svg);
  }
  return svg.cloneNode(true) as SVGElement;
}
