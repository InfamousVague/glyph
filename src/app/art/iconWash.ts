/**
 * Which shapes of an icon wear the wash (app.css "Icons are outlines, with a wash inside"; iconWash.css, which is
 * made from this). Matt: "a bunch of the icons across the app is missing the semiopaque fill that the icons should
 * all have".
 *
 * The wash was once set on every icon whole, and an icon is several shapes: the mic's capsule and the arc round it,
 * a page and its lines. Filled whole, the inside doubled up and the detail went, so the wash was cut back to the
 * seven icons that are one closed silhouette, and every other icon was left hollow. The house (art/Icons.tsx) showed
 * the way out: the wash on the icon's body alone, the detail drawn over it as strokes.
 *
 * So this picks each icon's body: its largest closed shape - a box, a circle, a path that comes back to where it
 * began - and any other closed shape of some size that sits clear of it (a second head beside the first, the three
 * shapes of Shapes). A shape inside the body is detail, and stays a stroke: the cog's hole, an eye's pupil, the tick
 * in a circle. An open path is never washed, since a fill closes it with a straight line from its end to its start,
 * which is the mic's cup filled over its capsule. An icon with no closed shape - an arrow, a tick, a list's lines -
 * has no body and stays an outline, which is right: there is nothing in it to fill.
 *
 * Pure: a shape is its tag and attributes, as the kit's icons list them. The stylesheet is written by
 * iconWash.test.ts, which also fails when an icon the app uses is not in it.
 */

export interface IconShape {
  tag: string;
  attrs: Record<string, string | number | undefined>;
}

interface Bounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

/** The least a body's box covers, of the icon's 24 by 24: a dot is not a body. */
const LEAST_AREA = 24;
/** A second shape is washed too when it is at least this much of the first, and clear of it. */
const BESIDE = 0.3;
/** How near a path's end is to its start for it to have come back: under a stroke's width. */
const CLOSED = 0.75;

const area = (b: Bounds) => Math.max(0, b.right - b.left) * Math.max(0, b.bottom - b.top);
const num = (value: string | number | undefined, fallback = 0) => (value === undefined ? fallback : Number(value));

function boundsOf(points: readonly [number, number][]): Bounds | null {
  if (!points.length) return null;
  const xs = points.map((p) => p[0]);
  const ys = points.map((p) => p[1]);
  return { left: Math.min(...xs), top: Math.min(...ys), right: Math.max(...xs), bottom: Math.max(...ys) };
}

/**
 * A path walked: the box round every point it names, and whether it is one line that comes back to its start. The
 * box is of the path's end points and control points, which is near enough to rank shapes by; an arc is taken by its
 * ends.
 */
export function walkPath(d: string): { bounds: Bounds | null; closed: boolean } {
  let at = 0;
  const skip = () => {
    while (at < d.length && /[\s,]/.test(d[at]!)) at += 1;
  };
  const number = (): number => {
    skip();
    const match = /^[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?/.exec(d.slice(at));
    if (!match) throw new Error(`no number at ${at} in "${d}"`);
    at += match[0].length;
    return Number(match[0]);
  };
  /** An arc's flag is one character, and may be set against the next number with no space. */
  const flag = (): number => {
    skip();
    const value = d[at] === '1' ? 1 : 0;
    at += 1;
    return value;
  };
  const points: [number, number][] = [];
  let x = 0;
  let y = 0;
  let startX = 0;
  let startY = 0;
  let subpaths = 0;
  let allClosed = true;
  let open = false;
  const endSubpath = (zed: boolean) => {
    if (!open) return;
    if (!zed && Math.hypot(x - startX, y - startY) > CLOSED) allClosed = false;
    open = false;
  };
  let command = '';
  for (;;) {
    skip();
    if (at >= d.length) break;
    if (/[a-zA-Z]/.test(d[at]!)) {
      command = d[at]!;
      at += 1;
    } else if (!command) throw new Error(`no command in "${d}"`);
    const rel = command === command.toLowerCase();
    const to = (px: number, py: number): [number, number] => (rel ? [x + px, y + py] : [px, py]);
    switch (command.toUpperCase()) {
      case 'M': {
        endSubpath(false);
        [x, y] = to(number(), number());
        startX = x;
        startY = y;
        subpaths += 1;
        open = true;
        points.push([x, y]);
        // Further pairs after a move are lines.
        command = rel ? 'l' : 'L';
        break;
      }
      case 'L':
      case 'T':
        [x, y] = to(number(), number());
        points.push([x, y]);
        break;
      case 'H':
        x = rel ? x + number() : number();
        points.push([x, y]);
        break;
      case 'V':
        y = rel ? y + number() : number();
        points.push([x, y]);
        break;
      case 'C': {
        const a = to(number(), number());
        const b = to(number(), number());
        const end = to(number(), number());
        points.push(a, b, end);
        [x, y] = end;
        break;
      }
      case 'S':
      case 'Q': {
        const a = to(number(), number());
        const end = to(number(), number());
        points.push(a, end);
        [x, y] = end;
        break;
      }
      case 'A': {
        number();
        number();
        number();
        flag();
        flag();
        [x, y] = to(number(), number());
        points.push([x, y]);
        break;
      }
      case 'Z':
        endSubpath(true);
        x = startX;
        y = startY;
        break;
      default:
        throw new Error(`unknown command ${command} in "${d}"`);
    }
  }
  endSubpath(false);
  return { bounds: boundsOf(points), closed: subpaths === 1 && allClosed };
}

/** The box a closed shape covers, or null for one that is open, or is not a shape that can be filled. */
function closedBounds(shape: IconShape): Bounds | null {
  const a = shape.attrs;
  switch (shape.tag) {
    case 'rect':
      return { left: num(a.x), top: num(a.y), right: num(a.x) + num(a.width), bottom: num(a.y) + num(a.height) };
    case 'circle':
      return { left: num(a.cx) - num(a.r), top: num(a.cy) - num(a.r), right: num(a.cx) + num(a.r), bottom: num(a.cy) + num(a.r) };
    case 'ellipse':
      return { left: num(a.cx) - num(a.rx), top: num(a.cy) - num(a.ry), right: num(a.cx) + num(a.rx), bottom: num(a.cy) + num(a.ry) };
    case 'polygon': {
      const values = String(a.points ?? '')
        .trim()
        .split(/[\s,]+/)
        .map(Number);
      const points: [number, number][] = [];
      for (let n = 0; n + 1 < values.length; n += 2) points.push([values[n]!, values[n + 1]!]);
      return boundsOf(points);
    }
    case 'path': {
      const walked = walkPath(String(a.d ?? ''));
      return walked.closed ? walked.bounds : null;
    }
    default:
      return null;
  }
}

const apart = (a: Bounds, b: Bounds) => a.right <= b.left + 0.5 || b.right <= a.left + 0.5 || a.bottom <= b.top + 0.5 || b.bottom <= a.top + 0.5;

/**
 * The shapes of an icon that wear the wash, by their place among its shapes (from 0), in that order: its body, and
 * whatever else is closed, of some size, and clear of everything already chosen. None for an icon with no body.
 */
export function bodiesOf(shapes: readonly IconShape[]): number[] {
  const closed = shapes
    .map((shape, index) => ({ index, bounds: closedBounds(shape) }))
    .filter((entry): entry is { index: number; bounds: Bounds } => entry.bounds !== null && area(entry.bounds) >= LEAST_AREA)
    .sort((a, b) => area(b.bounds) - area(a.bounds) || a.index - b.index);
  const first = closed[0];
  if (!first) return [];
  const chosen = [first];
  for (const entry of closed.slice(1)) {
    if (area(entry.bounds) >= area(first.bounds) * BESIDE && chosen.every((held) => apart(held.bounds, entry.bounds))) chosen.push(entry);
  }
  return chosen.map((entry) => entry.index).sort((a, b) => a - b);
}

/**
 * Bodies the rule above cannot see: a path left open along an edge that another stroke of the icon draws, or that is
 * the shape's own straight side. A fill closes an open path with a line from its end to its start, and for these
 * that line is the edge: the bin's rim, the flag's pole, the foot of a lightbulb, a box with one corner cut for an
 * arrow. Chosen by eye, one icon at a time, by the name the kit gives its svg and the shape's place among its shapes;
 * an icon is only added here once it has been looked at washed.
 */
export const OPEN_BODIES: Readonly<Record<string, readonly number[]>> = {
  trash: [2],
  // The book: closed across its page edge, which leaves the pages clear under the washed cover.
  book: [0],
  flag: [0],
  lightbulb: [0],
  hourglass: [2, 3],
  'flask-conical': [0],
  eraser: [0],
  download: [1],
  'external-link': [2],
  'log-out': [2],
  'image-plus': [2],
  gauge: [1],
  // The history clock: a ring open only where its arrow turns back.
  'rotate-ccw-clock': [0],
  // The archive's box under its lid, open along the top the lid draws (Matt: "The archive icon's bottom box is missing
  // the icon fill style"). With its X too. Not archive-restore, whose box is two open halves either side of its arrow.
  archive: [1],
  'archive-x': [1],
};

/** The wash itself: a third of the icon's own ink, as the house's body and the seven whole icons wear (app.css). */
export const WASH = 'color-mix(in srgb, currentColor 33%, transparent)';

/**
 * The stylesheet's rule for one icon: its washed shapes by their place under the svg. `:where()` round the icon keeps
 * the rule as light as the rules beside it, so an icon's own stylesheet still wins.
 */
export function washRule(name: string, bodies: readonly number[]): string {
  return bodies.map((index) => `:where(svg.lucide-${name}) > :nth-child(${index + 1})`).join(',\n');
}
