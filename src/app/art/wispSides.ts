import { preferences } from '../core/preferences.ts';
import { WISP_EDGE_BUDGET } from './wispEdge.ts';

/**
 * The wisp for a row that scrolls sideways: the tabs (notes/NoteTabs.tsx). Matt: "Blur the right side of the tabs and
 * the left when scrolled with the wisp animation but don't apply it to the left when it's scrolled all the way". What
 * runs off either end is bent by fractal noise and softened, the smoke a page makes under its header, turned on its
 * side - where the row had only a fade on its right end.
 *
 * Built like a board lane's foot (art/wispFoot.ts): a filter of the row's own size, since a filter's coordinates start
 * at the box wearing it, made once per size and pair of ends and kept. `wispSides(width, height, start, end)` answers
 * the filter to wear, as a CSS value, or null where the smoke is not wanted: switched off under Settings (`wispEdge`),
 * with reduced motion, with neither end open, and where the filter's region would not fit its budget
 * (`WISP_EDGE_BUDGET`, art/wispEdge.ts) - over it Apple's engine paints the whole box black rather than clipping it.
 *
 * Measured in two frames at once, because the engines disagree about which one a filter on an HTML box uses. Chromium
 * measures from the box's own corner; WebKit - the Mac app, and Safari - from the DOCUMENT's, the page's top left
 * before any page scrolling. Probed with a red square at (0, 0): Chromium drew it at the row's corner, 57px down, and
 * WebKit drew nothing, since (0, 0) was above the row and a filter's output is clipped to the box; a green one at
 * (0, 57) was WebKit's row corner. A filter placed for the row's own frame drew the row as nothing at all in WebKit.
 * So nothing here depends on where the row is up and down - the bands and the noise run far above and below it, over
 * both frames - and across, the row starts at the page's left edge in every layout, where the frames agree. `left`
 * says where it starts; anywhere else, no wisp (the fade stays).
 *
 * This note used to say the window's corner, which is the same corner while the page is at its top, and that is
 * where it was probed. Re-probed at a page scrolled down (art/wispFoot.ts), it is the document's. Nothing here
 * changes for it: the row sits at the top of the window inside a page that does not scroll sideways, so the two
 * corners agree across, which is the only direction this filter places anything in. The cleaner answer to all of it
 * is wispFoot's - say the whole filter in the box's own units (`objectBoundingBox`) and there is no corner to pick -
 * and it would let this one drop the `left` test and smoke a row anywhere on the page.
 *
 * The noise stays where it is and the tabs scroll through it, so the edge churns while they move and rests when they
 * stop: that is the animation, and a row at rest costs nothing but its bands. Sliding the noise as well was tried in
 * the plan and left out - a filter draws nothing outside its own region, so noise slid in from past the row's end
 * arrives blank.
 */

/** The full-strength lip at each end, and the soft ramp in from it. */
const BAND = 6;
const SOFT = 12;
/** How far outside the row the bend may throw a pixel, and so how far the region reaches around it. */
const SIDE = 24;
/**
 * How far above and below the row the region, the bands and the noise reach: past the row's own top in both frames
 * (it is under 400px from the window's top on every screen, its title bar included), so either engine finds it inside.
 */
const REACH = 400;
/** The strip reaches this far past each end, so its blur never opens the row's own edge. */
const PAST = 60;
/**
 * How far in from each end the lip sits: where the tabs are still drawn, as the header's lip sits a little below the
 * header. At the very end the row's fade had already taken them, and the smoke bent nothing anyone could see.
 */
const IN = 14;
/** Smaller than a page's: a tab's words are small. */
const BEND = 14;
const BLUR = 1.6;
const NEAR = 1.5;
/** How many are kept before the oldest is taken out: a row changes size as tabs open and the window moves. */
const KEEP = 16;

const SVG = 'http://www.w3.org/2000/svg';
const made = new Map<string, string>();
let holder: SVGSVGElement | null = null;

export function wispSides(width: number, height: number, start: boolean, end: boolean, left = 0): string | null {
  if (typeof document === 'undefined' || !preferences().wispEdge || (!start && !end)) return null;
  // Across, the two frames agree only where the row starts at the window's own left edge.
  if (Math.abs(left) > 1) return null;
  if (typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches) return null;
  const wide = Math.round(width);
  const tall = Math.round(height);
  if (wide <= (BAND + SOFT) * 2 || tall <= 0) return null;
  const dots = typeof devicePixelRatio === 'number' && devicePixelRatio > 0 ? devicePixelRatio : 1;
  if (Math.ceil((wide + SIDE * 2) * dots) * Math.ceil((tall + REACH * 2) * dots) > WISP_EDGE_BUDGET) return null;
  const key = `${wide}x${tall}${start ? 's' : ''}${end ? 'e' : ''}`;
  const known = made.get(key);
  if (known && document.getElementById(known)) return `url(#${known})`;
  const id = `wispSides${key}`;
  holder ??= makeHolder();
  if (!holder.isConnected) document.body.append(holder);
  holder.append(sidesFilter(id, wide, tall, start, end));
  made.set(key, id);
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
 * The header's band of art/WispEdgeFilter.tsx turned on its side: noise, a white strip at each open end on black,
 * blurred across into a ramp that decides where the noise bends the row, a softened copy kept to the strokes, and the
 * row itself everywhere the bands aren't. The noise runs in tall streaks, as the header's runs in long ones.
 */
function sidesFilter(id: string, wide: number, tall: number, start: boolean, end: boolean): Element {
  const region = { x: -SIDE, y: -REACH, width: wide + SIDE * 2, height: tall + REACH * 2 };
  const merge = (result: string, ...inputs: string[]) =>
    part('feMerge', result ? { result } : {}, ...inputs.map((input) => part('feMergeNode', { in: input })));
  const strips = [
    ...(start ? [part('feFlood', { 'flood-color': '#fff', x: -PAST, y: -REACH, width: PAST + IN + BAND, height: tall + REACH * 2, result: 'startStrip' })] : []),
    ...(end ? [part('feFlood', { 'flood-color': '#fff', x: wide - IN - BAND, y: -REACH, width: PAST + IN + BAND, height: tall + REACH * 2, result: 'endStrip' })] : []),
  ];
  return part(
    'filter',
    { id, filterUnits: 'userSpaceOnUse', ...region, 'color-interpolation-filters': 'sRGB' },
    part('feTurbulence', { type: 'fractalNoise', baseFrequency: '0.07 0.035', numOctaves: 2, seed: 5, ...region, result: 'rawNoise' }),
    part('feColorMatrix', { in: 'rawNoise', type: 'matrix', values: '1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 0 1', result: 'noise' }),
    part('feFlood', { 'flood-color': '#000', result: 'black' }),
    ...strips,
    merge('stripsOnBlack', 'black', ...(start ? ['startStrip'] : []), ...(end ? ['endStrip'] : [])),
    part('feGaussianBlur', { in: 'stripsOnBlack', stdDeviation: `${SOFT} 0`, result: 'band' }),
    part('feComposite', { in: 'noise', in2: 'band', operator: 'arithmetic', k1: 1, k2: 0, k3: -0.5, k4: 0.5, result: 'field' }),
    part('feDisplacementMap', { in: 'SourceGraphic', in2: 'field', scale: BEND, xChannelSelector: 'R', yChannelSelector: 'G', result: 'bent' }),
    part('feGaussianBlur', { in: 'bent', stdDeviation: BLUR, result: 'soft' }),
    part('feMorphology', { in: 'bent', operator: 'dilate', radius: NEAR, result: 'near' }),
    part('feComposite', { in: 'soft', in2: 'near', operator: 'in', result: 'softNear' }),
    part('feColorMatrix', { in: 'band', type: 'luminanceToAlpha', result: 'bandAlpha' }),
    part('feComposite', { in: 'softNear', in2: 'bandAlpha', operator: 'in', result: 'smoke' }),
    part('feComposite', { in: 'SourceGraphic', in2: 'bandAlpha', operator: 'out', result: 'rest' }),
    part('feComposite', { in: 'bent', in2: 'bandAlpha', operator: 'in', result: 'bentIn' }),
    merge('', 'rest', 'bentIn', 'smoke'),
  );
}
