import { isWebKit } from '../core/platform.ts';
import { preferences } from '../core/preferences.ts';

/**
 * The wisp edge's foot (art/wispEdge.ts) for a small box that scrolls inside a page: a board's lane with more cards
 * than it shows (editor/boards.ts). Matt: "the blur at the bottom of the swimlanes should be the wisp effect we use on
 * text". What slides off the lane's foot is bent by fractal noise and softened, the same smoke a page makes under its
 * header, where a plain fade used to be.
 *
 * The page's filter is one element placed for one view at a time (`placeFoot`), so a lane can't wear it. A lane has
 * its own: the same primitives with the band at the lane's own foot, since a filter's coordinates start at the top of
 * the box wearing it. Lanes in a board are all one height, so one filter serves a board, and boards the same height
 * share it. It is made once per height and kept, and nothing about it moves, so a lane at rest costs nothing but its
 * band.
 *
 * `wispFoot(height)` answers the filter to wear, as a CSS value, or null where the smoke is not wanted: switched off
 * under Settings (`wispEdge`), with reduced motion, and in WebKit, which paints an element wearing a filter like this
 * one solid black (app.css). There the lane keeps its plain fade.
 */

/** The full-strength lip at the lane's foot, the soft ramp above it, and how far the bend and blur reach. */
const BAND = 8;
const SOFT = 16;
const REACH = BAND + SOFT * 4 + 16;
/** The strip reaches this far below the lane, so its blur never opens the foot. */
const BELOW = 120;
/** Smaller than the page's: a card's words are smaller than a page's. */
const BEND = 28;
const BLUR = 2.4;
const NEAR = 2;
/** How many heights are kept before the oldest is taken out. */
const KEEP = 24;

const SVG = 'http://www.w3.org/2000/svg';
const made = new Map<number, string>();
let holder: SVGSVGElement | null = null;

export function wispFoot(height: number): string | null {
  if (typeof document === 'undefined' || isWebKit || !preferences().wispEdge) return null;
  if (typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches) return null;
  const tall = Math.round(height);
  if (tall < REACH) return null;
  const known = made.get(tall);
  if (known && document.getElementById(known)) return `url(#${known})`;
  const id = `wispFoot${tall}`;
  holder ??= makeHolder();
  if (!holder.isConnected) document.body.append(holder);
  holder.append(footFilter(id, tall));
  made.set(tall, id);
  if (made.size > KEEP) {
    const [oldest] = made;
    if (oldest) {
      made.delete(oldest[0]);
      document.getElementById(oldest[1])?.remove();
    }
  }
  return `url(#${id})`;
}

function makeHolder(): SVGSVGElement {
  const svg = document.createElementNS(SVG, 'svg');
  svg.setAttribute('width', '0');
  svg.setAttribute('height', '0');
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('focusable', 'false');
  svg.style.position = 'absolute';
  document.body.append(svg);
  return svg;
}

function part(name: string, attributes: Record<string, string | number>, ...children: Element[]): Element {
  const node = document.createElementNS(SVG, name);
  for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, String(value));
  node.append(...children);
  return node;
}

/**
 * The foot band of art/WispEdgeFilter.tsx at `height`: noise, a white strip from the lane's foot down on black,
 * blurred into a ramp that decides where the noise bends the lane, a softened copy kept to the strokes, and the lane
 * itself everywhere the band isn't. The bend and the blur are only worked out over the band's reach.
 */
function footFilter(id: string, height: number): Element {
  const top = height - REACH;
  const reach = { x: -40, y: top, width: 4000, height: REACH + 40 };
  const merge = (result: string, ...inputs: string[]) =>
    part('feMerge', result ? { result } : {}, ...inputs.map((input) => part('feMergeNode', { in: input })));
  return part(
    'filter',
    { id, filterUnits: 'userSpaceOnUse', x: -40, y: -40, width: 4000, height: height + 80 + BELOW, 'color-interpolation-filters': 'sRGB' },
    part('feTurbulence', { type: 'fractalNoise', baseFrequency: '0.02 0.07', numOctaves: 2, seed: 3, ...reach, result: 'rawNoise' }),
    part('feColorMatrix', { in: 'rawNoise', type: 'matrix', values: '1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 0 1', result: 'noise' }),
    part('feFlood', { 'flood-color': '#000', result: 'black' }),
    part('feFlood', { 'flood-color': '#fff', x: -40, y: height - BAND, width: 4000, height: BAND + BELOW, result: 'strip' }),
    merge('stripOnBlack', 'black', 'strip'),
    part('feGaussianBlur', { in: 'stripOnBlack', stdDeviation: `0 ${SOFT}`, result: 'band' }),
    part('feComposite', { in: 'noise', in2: 'band', operator: 'arithmetic', k1: 1, k2: 0, k3: -0.5, k4: 0.5, result: 'field' }),
    part('feDisplacementMap', { in: 'SourceGraphic', in2: 'field', scale: BEND, xChannelSelector: 'R', yChannelSelector: 'G', ...reach, result: 'bent' }),
    part('feGaussianBlur', { in: 'bent', stdDeviation: BLUR, ...reach, result: 'soft' }),
    part('feMorphology', { in: 'bent', operator: 'dilate', radius: NEAR, ...reach, result: 'near' }),
    part('feComposite', { in: 'soft', in2: 'near', operator: 'in', result: 'softNear' }),
    part('feColorMatrix', { in: 'band', type: 'luminanceToAlpha', result: 'bandAlpha' }),
    part('feComposite', { in: 'softNear', in2: 'bandAlpha', operator: 'in', result: 'smoke' }),
    part('feComposite', { in: 'SourceGraphic', in2: 'bandAlpha', operator: 'out', result: 'rest' }),
    part('feComposite', { in: 'bent', in2: 'bandAlpha', operator: 'in', result: 'bentIn' }),
    merge('', 'rest', 'bentIn', 'smoke'),
  );
}
