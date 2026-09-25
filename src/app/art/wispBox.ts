/**
 * What the two boxed wisps are built from: a board lane's foot (art/wispFoot.ts) and the tab row's ends
 * (art/wispSides.ts). Each is the page's smoke (art/WispEdgeFilter.tsx) said again as an SVG filter of its own, in
 * its element's own box, made once per size and kept; and the two had grown every part of that twice - the element
 * builder, the merge, the hidden holder, the cache with its oldest-out, the fractions of the box, and the whole chain
 * of primitives from the noise to the last merge. The parts that differ stay in each file: where the bands are, how
 * far the region reaches, and the noise's frequency, whose comment is the reason it is written per pixel there.
 *
 * DOM only, and nothing read at the top level, so importing it costs nothing where there is no document.
 */

const SVG = 'http://www.w3.org/2000/svg';

type Attributes = Record<string, string | number>;

/** One SVG element with its attributes, in the order given, and its children. */
export function svgPart(name: string, attributes: Attributes, ...children: Element[]): Element {
  const node = document.createElementNS(SVG, name);
  for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, String(value));
  node.append(...children);
  return node;
}

/** An feMerge of `inputs`, one over the next; no `result` for the filter's last primitive, which is its output. */
export function mergeOf(result: string, ...inputs: string[]): Element {
  return svgPart('feMerge', result ? { result } : {}, ...inputs.map((input) => svgPart('feMergeNode', { in: input })));
}

/**
 * Lengths as fractions of a `wide` × `tall` box, which is what `objectBoundingBox` units are: `box` for a rectangle,
 * and `corner`, the box's diagonal over root two, which is what `feDisplacementMap` measures its throw against.
 */
export function boxOf(wide: number, tall: number): { box: (x: number, y: number, w: number, h: number) => Attributes; corner: number } {
  return {
    box: (x, y, w, h) => ({ x: x / wide, y: y / tall, width: w / wide, height: h / tall }),
    corner: Math.sqrt((wide * wide + tall * tall) / 2),
  };
}

/**
 * Where one family of filters is kept: a hidden SVG of its own in the page, and the filters in it by key, the oldest
 * taken out once there are more than `keep`. The answer wears a filter - the one kept under `key` if it is still in
 * the page, else the one `make` builds, filed under `id` - as a CSS value.
 */
export function filterShelf(keep: number): (key: string, id: string, make: () => Element) => string {
  const made = new Map<string, string>();
  let holder: SVGSVGElement | null = null;
  return (key, id, make) => {
    const known = made.get(key);
    if (known && document.getElementById(known)) return `url(#${known})`;
    holder ??= makeHolder();
    if (!holder.isConnected) document.body.append(holder);
    holder.append(make());
    made.set(key, id);
    if (made.size > keep) {
      const [oldest] = made;
      if (oldest) {
        made.delete(oldest[0]);
        document.getElementById(oldest[1])?.remove();
      }
    }
    return `url(#${id})`;
  };
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

/**
 * The start of the chain: the noise, made opaque (the displacement reads colour unpremultiplied, and a see-through
 * value would shift the whole element), and the black the bands are laid on. `noise` is the turbulence's own
 * attributes - its frequency, seed and region - which each filter says for itself.
 */
export function noiseOnBlack(noise: Attributes): Element[] {
  return [
    svgPart('feTurbulence', { type: 'fractalNoise', ...noise, result: 'rawNoise' }),
    svgPart('feColorMatrix', { in: 'rawNoise', type: 'matrix', values: '1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 0 1', result: 'noise' }),
    svgPart('feFlood', { 'flood-color': '#000', result: 'black' }),
  ];
}

/**
 * The rest of the chain, from the band (a primitive whose result is `band`, white where the smoke is strongest):
 * the noise bent round it into a field, the element displaced by the field, a softened copy kept to the strokes, and
 * the element itself everywhere the band isn't. `bend` is the throw, already a fraction of the box's corner; `blur`
 * and `near` are both numbers, always, since one fraction shared between a wide box and a short one is two
 * different blurs. `within` is the subregion the bend and the blur are worked out over, where a filter has one.
 */
export function smokeFrom({ bend, blur, near, within = {} }: { bend: number; blur: string; near: string; within?: Attributes }): Element[] {
  return [
    svgPart('feComposite', { in: 'noise', in2: 'band', operator: 'arithmetic', k1: 1, k2: 0, k3: -0.5, k4: 0.5, result: 'field' }),
    svgPart('feDisplacementMap', { in: 'SourceGraphic', in2: 'field', scale: bend, xChannelSelector: 'R', yChannelSelector: 'G', ...within, result: 'bent' }),
    svgPart('feGaussianBlur', { in: 'bent', stdDeviation: blur, ...within, result: 'soft' }),
    svgPart('feMorphology', { in: 'bent', operator: 'dilate', radius: near, ...within, result: 'near' }),
    svgPart('feComposite', { in: 'soft', in2: 'near', operator: 'in', result: 'softNear' }),
    svgPart('feColorMatrix', { in: 'band', type: 'luminanceToAlpha', result: 'bandAlpha' }),
    svgPart('feComposite', { in: 'softNear', in2: 'bandAlpha', operator: 'in', result: 'smoke' }),
    svgPart('feComposite', { in: 'SourceGraphic', in2: 'bandAlpha', operator: 'out', result: 'rest' }),
    svgPart('feComposite', { in: 'bent', in2: 'bandAlpha', operator: 'in', result: 'bentIn' }),
    mergeOf('', 'rest', 'bentIn', 'smoke'),
  ];
}
