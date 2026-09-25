import { anchorOf, centre, NORMAL, sidesOf, type Box, type Point } from './geometry.ts';
import type { Canvas, CanvasEdge, CanvasNode, Side } from './jsonCanvas.ts';

/**
 * A canvas's lines as they are drawn (canvas/CanvasView.tsx): each a curve out of one card's side and into another's,
 * with its arrow heads and its label. Drawn together rather than one by one, because where one line's end sits
 * depends on the others' (docs/DESIGN.md §62): ends that share a side are set along it so they leave without
 * crossing, heads on neighbouring cards that would meet are moved apart, and a label sits over open canvas rather
 * than over a card, broken onto two or three lines where one will not fit down the gap. Pure, in the canvas's own
 * pixels; the screen only draws what this answers.
 */

/** The size of an arrow head, in the canvas's pixels; the line stops short of the tip by this much. */
export const HEAD = 10;

/** One line as it is drawn, by `edgePaths`. */
export interface EdgePath {
  /** The curve, as an SVG path: from one anchor to the other, stopping short of any arrow head. */
  d: string;
  /** The head at each end, as an SVG path of a filled triangle, where that end is an arrow. */
  fromHead: string | null;
  toHead: string | null;
  /** Where its label sits: along the curve, over open canvas rather than over a card (`labelPlace`). */
  mid: Point;
  /** The label's words as lines, broken where one line would not fit between the cards; none without a label. */
  lines: string[];
}

function head(tip: Point, side: Side): string {
  const n = NORMAL[side];
  // The base of the head sits back along the side's normal; the wings sit across it.
  const base = { x: tip.x + n.x * HEAD, y: tip.y + n.y * HEAD };
  const wing = HEAD * 0.55;
  const a = { x: base.x - n.y * wing, y: base.y + n.x * wing };
  const b = { x: base.x + n.y * wing, y: base.y - n.x * wing };
  return `M${tip.x} ${tip.y}L${a.x} ${a.y}L${b.x} ${b.y}Z`;
}

/** How far apart two line ends on the same side of a card are set. Exported, as `HEAD_CLEAR` is, for its test. */
export const END_SPREAD = 28;
/**
 * How close two arrow heads on different cards may come before they are moved apart along their sides. Two lines
 * into the facing sides of neighbouring cards landed at the same height, their heads base to base in the gap, and
 * read as one shape (Matt: "they look joined like a diamond"). A little over five heads' lengths (`HEAD` is 10),
 * wide enough that two heads are plainly two.
 */
export const HEAD_CLEAR = 56;
/** A line end keeps this far from a side's corners. */
const END_MARGIN = 16;

/** A unit step along a side: the way an end moves when it is set apart from another. */
const ALONG: Record<Side, Point> = { top: { x: 1, y: 0 }, bottom: { x: 1, y: 0 }, left: { x: 0, y: 1 }, right: { x: 0, y: 1 } };

/** One end of one line: which card and side it is on, how far along the side it has been set, and where it goes. */
interface LineEnd {
  edge: CanvasEdge;
  node: CanvasNode;
  side: Side;
  /** Whether a head is drawn at this end. */
  arrow: boolean;
  /** How far along the side from its middle this end sits, in the canvas's pixels. */
  offset: number;
  /** The centre of the card at the line's other end, for ordering ends along a side so lines do not cross. */
  other: Point;
}

const sideLength = (node: Box, side: Side): number => (side === 'top' || side === 'bottom' ? node.width : node.height);
/** A point's coordinate along a side's axis. */
const along = (p: Point, side: Side): number => (side === 'top' || side === 'bottom' ? p.x : p.y);
/** A point's coordinate across a side's axis. */
const across = (p: Point, side: Side): number => (side === 'top' || side === 'bottom' ? p.y : p.x);

function keptOnSide(end: LineEnd, offset: number): number {
  const half = Math.max(0, sideLength(end.node, end.side) / 2 - END_MARGIN);
  return Math.max(-half, Math.min(half, offset));
}

/** Where an end is now: the side's middle, moved along it by the end's offset. */
function pointOf(end: LineEnd): Point {
  const a = anchorOf(end.node, end.side);
  const step = ALONG[end.side];
  return { x: a.x + step.x * end.offset, y: a.y + step.y * end.offset };
}

/**
 * Ends that share one side of one card are set along it, evenly about the middle, in the order their far ends come
 * along that axis so the lines leave without crossing. A side too short for the spread packs them closer.
 */
function spreadShared(ends: readonly LineEnd[]): void {
  const shared = new Map<string, LineEnd[]>();
  for (const end of ends) {
    const key = `${end.node.id}/${end.side}`;
    shared.set(key, [...(shared.get(key) ?? []), end]);
  }
  for (const group of shared.values()) {
    if (group.length < 2) continue;
    group.sort((a, b) => along(a.other, a.side) - along(b.other, b.side));
    const first = group[0]!;
    const room = Math.max(0, sideLength(first.node, first.side) - 2 * END_MARGIN);
    const step = Math.min(END_SPREAD, room / (group.length - 1));
    group.forEach((end, i) => {
      end.offset = keptOnSide(end, (i - (group.length - 1) / 2) * step);
    });
  }
}

/**
 * Two heads on different cards nearer each other than `HEAD_CLEAR` are moved apart, each along its own side, until
 * they are that far apart or a side runs out. Which goes which way: away from the other along the side's axis; when
 * they are level, the one whose line comes from further along that axis goes that way. Two passes settle what one
 * move undoes.
 */
function partHeads(ends: readonly LineEnd[]): void {
  const heads = ends.filter((end) => end.arrow);
  for (let pass = 0; pass < 2; pass += 1) {
    for (let i = 0; i < heads.length; i += 1) {
      for (let j = i + 1; j < heads.length; j += 1) {
        const a = heads[i]!;
        const b = heads[j]!;
        if (a.node.id === b.node.id || a.edge.id === b.edge.id) continue;
        const pa = pointOf(a);
        const pb = pointOf(b);
        if (Math.hypot(pa.x - pb.x, pa.y - pb.y) >= HEAD_CLEAR) continue;
        for (const [self, other, selfAt, otherAt] of [
          [a, b, pa, pb],
          [b, a, pb, pa],
        ] as const) {
          // Along this end's own side: how far apart they are already, and how far they need to be, given how far
          // apart they are across it, which moving along the side cannot change.
          const gapAcross = Math.abs(across(selfAt, self.side) - across(otherAt, self.side));
          const have = along(selfAt, self.side) - along(otherAt, self.side);
          const need = Math.sqrt(Math.max(0, HEAD_CLEAR * HEAD_CLEAR - gapAcross * gapAcross));
          const short = need - Math.abs(have);
          if (short <= 0) continue;
          let way = Math.sign(have);
          if (way === 0) way = Math.sign(along(self.other, self.side) - along(other.other, self.side)) || (self === a ? -1 : 1);
          self.offset = keptOnSide(self, self.offset + (way * short) / 2);
        }
      }
    }
  }
}

/** Where along the curve a label is tried, the middle first and then either way from it. */
const LABEL_TRIES = [0.5, 0.45, 0.55, 0.4, 0.6, 0.35, 0.65, 0.3, 0.7, 0.25, 0.75, 0.2, 0.8, 0.15, 0.85];
/** About what a label's letters take at the label's size (CanvasView.module.css `.label`, 13px), and a line's height. */
const LABEL_LETTER = 6.8;
export const LABEL_LINE = 15;
/** How many lines a label may be broken into to fit between cards. */
const LABEL_LINES_MOST = 3;

const overlaps = (a: Box, b: Box): boolean => a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;

/**
 * The words broken into `count` lines of about equal length, never inside a word; fewer where there are not the
 * words. Each line is aimed at an equal share of what is still to be placed, and takes the next word when that
 * lands nearer the aim than stopping short does. Exported for its test; the labels are its one caller.
 */
export function brokenInto(words: string, count: number): string[] {
  const parts = words.split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let line = '';
  for (let i = 0; i < parts.length; i += 1) {
    const part = parts[i]!;
    if (!line) {
      line = part;
      continue;
    }
    const linesLeft = count - lines.length;
    if (linesLeft <= 1) {
      line = `${line} ${part}`;
      continue;
    }
    const rest = parts.slice(i).join(' ').length;
    const aim = (line.length + 1 + rest) / linesLeft;
    const taken = line.length + 1 + part.length;
    if (Math.abs(taken - aim) <= Math.abs(line.length - aim)) {
      line = `${line} ${part}`;
    } else {
      lines.push(line);
      line = part;
    }
  }
  if (line) lines.push(line);
  return lines;
}

/**
 * Where a label sits, and on how many lines: the first point along the curve, trying the middle and then either
 * way from it, where the label's box is over open canvas and not over a card (Matt: "the text that's on arrow paths
 * sometimes overlaps content and we can't read the boxes below"); on one line first, and where one line fits
 * nowhere, on two, then three, so words longer than the gap between two cards fit down it. Groups are open canvas.
 * Where nothing fits anywhere, one line at the middle, and the label's own halo does what it can.
 */
function labelPlace(p0: Point, c1: Point, c2: Point, p3: Point, label: string | undefined, cards: readonly Box[]): { at: Point; lines: string[] } {
  const at = (t: number): Point => {
    const u = 1 - t;
    return {
      x: u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p3.x,
      y: u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p3.y,
    };
  };
  const whole = label ? [label] : [];
  for (let count = 1; count <= LABEL_LINES_MOST; count += 1) {
    const lines = label ? brokenInto(label, count) : [];
    if (count > 1 && lines.length < count) break;
    const width = Math.max(40, Math.max(6, ...lines.map((line) => line.length)) * LABEL_LETTER + 8);
    const height = Math.max(1, lines.length) * LABEL_LINE + 5;
    for (const t of LABEL_TRIES) {
      const p = at(t);
      const box = { x: p.x - width / 2, y: p.y - height / 2, width, height };
      if (!cards.some((card) => overlaps(box, card))) return { at: p, lines: label ? lines : [] };
    }
  }
  return { at: at(0.5), lines: whole };
}

/** The curve between two ends as they have been set, its heads, and its label's place. */
function pathBetween(from: LineEnd, to: LineEnd, edge: CanvasEdge, cards: readonly Box[]): EdgePath {
  const a = pointOf(from);
  const b = pointOf(to);
  const na = NORMAL[from.side];
  const nb = NORMAL[to.side];
  // The curve ends at the base of a head, not its tip, so the line never pokes through the point.
  const start = from.arrow ? { x: a.x + na.x * HEAD, y: a.y + na.y * HEAD } : a;
  const end = to.arrow ? { x: b.x + nb.x * HEAD, y: b.y + nb.y * HEAD } : b;
  const reach = Math.max(30, Math.min(Math.hypot(end.x - start.x, end.y - start.y) * 0.4, 200));
  const c1 = { x: start.x + na.x * reach, y: start.y + na.y * reach };
  const c2 = { x: end.x + nb.x * reach, y: end.y + nb.y * reach };
  const label = labelPlace(start, c1, c2, end, edge.label, cards);
  return {
    d: `M${start.x} ${start.y}C${c1.x} ${c1.y} ${c2.x} ${c2.y} ${end.x} ${end.y}`,
    fromHead: from.arrow ? head(a, from.side) : null,
    toHead: to.arrow ? head(b, to.side) : null,
    mid: label.at,
    lines: label.lines,
  };
}

/**
 * The lines of a canvas, by edge id: each a curve out of one side and into the other, bowing further the further
 * apart the nodes are, the way Obsidian draws one; the heads the edge asks for (an arrow at the end unless it says
 * otherwise); and where its label sits. Drawn together rather than one by one, because where one line's end goes
 * depends on the others': ends on a shared side are set along it (`spreadShared`), heads that would meet are moved
 * apart (`partHeads`), and a label keeps off the cards (`labelPlace`). An edge whose node is missing is left out.
 */
export function edgePaths(canvas: Canvas): Map<string, EdgePath> {
  const byId = new Map(canvas.nodes.map((node) => [node.id, node] as const));
  const ends: LineEnd[] = [];
  const lines: { edge: CanvasEdge; from: LineEnd; to: LineEnd }[] = [];
  for (const edge of canvas.edges) {
    const from = byId.get(edge.fromNode);
    const to = byId.get(edge.toNode);
    if (!from || !to) continue;
    const sides = sidesOf(from, to, edge);
    const start: LineEnd = { edge, node: from, side: sides.from, arrow: (edge.fromEnd ?? 'none') === 'arrow', offset: 0, other: centre(to) };
    const finish: LineEnd = { edge, node: to, side: sides.to, arrow: (edge.toEnd ?? 'arrow') === 'arrow', offset: 0, other: centre(from) };
    ends.push(start, finish);
    lines.push({ edge, from: start, to: finish });
  }
  spreadShared(ends);
  partHeads(ends);
  const cards = canvas.nodes.filter((node) => node.type !== 'group');
  const out = new Map<string, EdgePath>();
  for (const { edge, from, to } of lines) out.set(edge.id, pathBetween(from, to, edge, cards));
  return out;
}
