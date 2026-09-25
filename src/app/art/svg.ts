/**
 * The one SVG element builder, for everything that writes filters by hand: the editor's moving text
 * (editor/svgFilters.ts), the boxed wisps (art/wispBox.ts) and the typed-in words (art/WispText.tsx).
 *
 * DOM only, and nothing read at the top level, so importing it costs nothing where there is no document.
 */

export const SVG_NS = 'http://www.w3.org/2000/svg';

/** An SVG element with `attributes` set in the order given, holding `children`. */
export function svgElement<T extends SVGElement = SVGElement>(name: string, attributes: Record<string, string | number>, ...children: Element[]): T {
  const node = document.createElementNS(SVG_NS, name) as T;
  for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, String(value));
  node.append(...children);
  return node;
}
