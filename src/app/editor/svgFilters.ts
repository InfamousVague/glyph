/**
 * The SVG filters the editor's moving text is drawn through: the recorder's words arriving from smoke
 * (editor/wispArrivals.ts), a spoiler's smoke (editor/wispFormat.ts), the voice's ripples (editor/wispRipples.ts) and
 * the effects on words (editor/textEffects.ts).
 *
 * A note's DOM is CodeMirror's, so none of these moves an element: each marks its letters with
 * `filter: url(#id)`, and the filter, kept in a hidden SVG beside the editor, is what changes. Here are that SVG, the
 * elements written into it, and the five-step filter both smoke looks are drawn through. What each filter does over
 * time - the arc, the sway, the breathing - stays with its module.
 */

const SVG_NS = 'http://www.w3.org/2000/svg';

/** An SVG element with `attributes` set in the order given, holding `children`. */
export function svgElement<T extends SVGElement = SVGElement>(name: string, attributes: Record<string, string | number>, ...children: Element[]): T {
  const node = document.createElementNS(SVG_NS, name) as T;
  for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, String(value));
  node.append(...children);
  return node;
}

/**
 * A hidden SVG at the end of `parent` (the editor's own element), and the `<defs>` the filters go in. It takes no room
 * and is read by nothing; the caller removes the SVG when it is done.
 */
export function hiddenDefs(parent: HTMLElement): { svg: SVGSVGElement; defs: SVGDefsElement } {
  const svg = document.createElementNS(SVG_NS, 'svg');
  svg.setAttribute('aria-hidden', 'true');
  svg.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden';
  const defs = document.createElementNS(SVG_NS, 'defs');
  svg.appendChild(defs);
  parent.appendChild(svg);
  return { svg, defs };
}

/** Where a filter may paint, in shares of what it is on (`-150%`, `400%`), never in pixels. */
export interface FilterRegion {
  x: string;
  y: string;
  width: string;
  height: string;
}

/** The parts of a smoke filter a frame changes. */
export interface Smoke {
  filter: SVGElement;
  /** The noise that bends the letters: its `baseFrequency`. */
  noise: SVGElement;
  /** How far they are bent: its `scale`. */
  disp: SVGElement;
  /** How soft they are: its `stdDeviation`. */
  blur: SVGElement;
  /** How far they are lifted: its `dx` and `dy`. */
  lift: SVGElement;
  /** How much of them shows: its `slope`. */
  alpha: SVGElement;
}

/**
 * A smoke filter added to `defs`: fractal noise bending the letters, a blur, a lift and a fade, in that order, in
 * sRGB so thin type doesn't brighten. The region is room for the bend and the blur, so smeared strokes are never
 * clipped. `bend`, `soft` and `shown` are where it starts; the caller moves them.
 */
export function smokeFilter(
  defs: SVGDefsElement,
  { id, region, frequency, octaves, seed, bend, soft, shown }: { id: string; region: FilterRegion; frequency: string; octaves: number; seed: number; bend: string; soft: string; shown: string },
): Smoke {
  const noise = svgElement('feTurbulence', { type: 'fractalNoise', baseFrequency: frequency, numOctaves: octaves, seed, result: 'n' });
  const disp = svgElement('feDisplacementMap', { in: 'SourceGraphic', in2: 'n', scale: bend, xChannelSelector: 'R', yChannelSelector: 'G', result: 'd' });
  const blur = svgElement('feGaussianBlur', { in: 'd', stdDeviation: soft, result: 'b' });
  const lift = svgElement('feOffset', { in: 'b', dx: '0', dy: '0', result: 'l' });
  const alpha = svgElement('feFuncA', { type: 'linear', slope: shown });
  const transfer = svgElement('feComponentTransfer', { in: 'l' }, alpha);
  const filter = svgElement('filter', { id, x: region.x, y: region.y, width: region.width, height: region.height, 'color-interpolation-filters': 'sRGB' }, noise, disp, blur, lift, transfer);
  defs.appendChild(filter);
  return { filter, noise, disp, blur, lift, alpha };
}
