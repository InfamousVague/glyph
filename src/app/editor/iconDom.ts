import { createElement } from 'react';
import { createRoot } from 'react-dom/client';
import type { LucideIcon } from '@glacier/icons';

/**
 * The kit's icons as plain SVG elements, for what the editor draws outside React: a blank's square and its panel
 * (editor/blanks.ts, editor/fillPanel.ts). Each icon is drawn by React once, into a detached element, and copied from
 * then on, so a note with forty blanks draws forty copies, not forty React roots.
 *
 * The first draw is React's own, whenever it commits, never forced: CodeMirror asks for a widget while React is
 * committing the editor, where a forced draw does nothing, and every square in the app was an empty `<svg>` until the
 * shots showed it. Until then each copy is an empty `<svg>` that the drawn icon fills in, attributes and paths.
 */

const SVG = 'http://www.w3.org/2000/svg';

interface Drawing {
  svg: SVGElement | null;
  /** Copies handed out before the icon was drawn, filled in when it is. */
  waiting: Set<SVGElement>;
}

const drawings = new Map<LucideIcon, Map<number, Drawing>>();

/** Makes `copy` the drawn icon: its attributes and its children. */
function fill(copy: SVGElement, drawn: SVGElement): void {
  for (const { name, value } of [...drawn.attributes]) copy.setAttribute(name, value);
  copy.replaceChildren(...[...drawn.childNodes].map((node) => node.cloneNode(true)));
}

function draw(Icon: LucideIcon, strokeWidth: number, drawing: Drawing): void {
  const host = document.createElement('div');
  const root = createRoot(host);
  const drawn = (svg: SVGSVGElement | null) => {
    if (!svg || drawing.svg) return;
    drawing.svg = svg.cloneNode(true) as SVGElement;
    for (const copy of drawing.waiting) fill(copy, drawing.svg);
    drawing.waiting.clear();
    // Taken down after React's commit, never in the middle of it (editor/reactMount.ts).
    queueMicrotask(() => root.unmount());
  };
  root.render(createElement(Icon, { size: '1em', strokeWidth, 'aria-hidden': true, focusable: false, ref: drawn }));
}

/** A copy of `Icon` as an SVG element, sized to the text (`1em`), in the current ink, hidden from screen readers. */
export function iconElement(Icon: LucideIcon, strokeWidth = 2.2): SVGElement {
  let widths = drawings.get(Icon);
  if (!widths) drawings.set(Icon, (widths = new Map()));
  let drawing = widths.get(strokeWidth);
  if (!drawing) {
    drawing = { svg: null, waiting: new Set() };
    widths.set(strokeWidth, drawing);
    draw(Icon, strokeWidth, drawing);
  }
  if (drawing.svg) return drawing.svg.cloneNode(true) as SVGElement;
  const copy = document.createElementNS(SVG, 'svg');
  copy.setAttribute('aria-hidden', 'true');
  drawing.waiting.add(copy);
  return copy;
}
