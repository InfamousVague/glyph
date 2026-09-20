/**
 * JSON Canvas (jsoncanvas.org, 1.0), the open format Obsidian's canvas is written in, read and written as it is.
 *
 * Matt's choices (2026-09-20): a canvas in Glyph is the spec verbatim, so a canvas made here opens in Obsidian and an
 * Obsidian canvas opens here, rather than a grammar of Glyph's own. A canvas is either a note whose body is the JSON
 * (docs/CANVAS.md), named by front matter since Obsidian names one by its file and Glyph has no files, or a
 * ```canvas fence in an ordinary note. This file is the format and its geometry, and knows nothing of the screen.
 *
 * Read leniently, written exactly: a node or edge that is not what the spec says is left out rather than the whole
 * canvas refused, since one bad card should not lose the other forty; what is kept is written back with only the
 * fields the spec names, in the order the spec names them, so a round trip changes nothing a person meant.
 */

/** The spec's colour: one of six presets, "1" to "6", or a hex colour like "#FF0000". */
export type CanvasColor = string;

export type Side = 'top' | 'right' | 'bottom' | 'left';
export type End = 'none' | 'arrow';

interface NodeBase {
  id: string;
  /** Pixels, in the canvas's own space. The spec says integers. */
  x: number;
  y: number;
  width: number;
  height: number;
  color?: CanvasColor;
}

export type CanvasNode =
  | (NodeBase & { type: 'text'; text: string })
  | (NodeBase & { type: 'file'; file: string; subpath?: string })
  | (NodeBase & { type: 'link'; url: string })
  | (NodeBase & { type: 'group'; label?: string; background?: string; backgroundStyle?: 'cover' | 'ratio' | 'repeat' });

export interface CanvasEdge {
  id: string;
  fromNode: string;
  toNode: string;
  fromSide?: Side;
  toSide?: Side;
  /** The spec's defaults: nothing at the start, an arrow at the end. */
  fromEnd?: End;
  toEnd?: End;
  color?: CanvasColor;
  label?: string;
}

/** Nodes in ascending z-order, as the spec has them: the first is drawn first, under the rest. */
export interface Canvas {
  nodes: CanvasNode[];
  edges: CanvasEdge[];
}

const SIDES: readonly Side[] = ['top', 'right', 'bottom', 'left'];
const ENDS: readonly End[] = ['none', 'arrow'];
const STYLES = ['cover', 'ratio', 'repeat'] as const;

const isRecord = (value: unknown): value is Record<string, unknown> => !!value && typeof value === 'object' && !Array.isArray(value);
const str = (value: unknown): string | undefined => (typeof value === 'string' ? value : undefined);
const num = (value: unknown): number | undefined => (typeof value === 'number' && Number.isFinite(value) ? Math.round(value) : undefined);
const oneOf = <T extends string>(value: unknown, of: readonly T[]): T | undefined => (typeof value === 'string' && (of as readonly string[]).includes(value) ? (value as T) : undefined);
/** A colour the spec allows: a preset digit, or a hex colour. Anything else is read as no colour. */
const color = (value: unknown): CanvasColor | undefined => (typeof value === 'string' && /^([1-6]|#[0-9a-f]{6}|#[0-9a-f]{3})$/i.test(value) ? value : undefined);

function readNode(value: unknown): CanvasNode | null {
  if (!isRecord(value)) return null;
  const id = str(value.id);
  const x = num(value.x);
  const y = num(value.y);
  const width = num(value.width);
  const height = num(value.height);
  if (!id || x === undefined || y === undefined || width === undefined || height === undefined) return null;
  const base: NodeBase = { id, x, y, width, height };
  const c = color(value.color);
  if (c) base.color = c;
  switch (value.type) {
    case 'text': {
      const text = str(value.text);
      return text === undefined ? null : { ...base, type: 'text', text };
    }
    case 'file': {
      const file = str(value.file);
      if (!file) return null;
      const subpath = str(value.subpath);
      return subpath && subpath.startsWith('#') ? { ...base, type: 'file', file, subpath } : { ...base, type: 'file', file };
    }
    case 'link': {
      const url = str(value.url);
      return url ? { ...base, type: 'link', url } : null;
    }
    case 'group': {
      const node: CanvasNode = { ...base, type: 'group' };
      const label = str(value.label);
      const background = str(value.background);
      const backgroundStyle = oneOf(value.backgroundStyle, STYLES);
      if (label) node.label = label;
      if (background) node.background = background;
      if (backgroundStyle) node.backgroundStyle = backgroundStyle;
      return node;
    }
    default:
      return null;
  }
}

function readEdge(value: unknown, nodes: ReadonlySet<string>): CanvasEdge | null {
  if (!isRecord(value)) return null;
  const id = str(value.id);
  const fromNode = str(value.fromNode);
  const toNode = str(value.toNode);
  if (!id || !fromNode || !toNode || !nodes.has(fromNode) || !nodes.has(toNode)) return null;
  const edge: CanvasEdge = { id, fromNode, toNode };
  const fromSide = oneOf(value.fromSide, SIDES);
  const toSide = oneOf(value.toSide, SIDES);
  const fromEnd = oneOf(value.fromEnd, ENDS);
  const toEnd = oneOf(value.toEnd, ENDS);
  const c = color(value.color);
  const label = str(value.label);
  if (fromSide) edge.fromSide = fromSide;
  if (toSide) edge.toSide = toSide;
  if (fromEnd) edge.fromEnd = fromEnd;
  if (toEnd) edge.toEnd = toEnd;
  if (c) edge.color = c;
  if (label) edge.label = label;
  return edge;
}

/**
 * The canvas in `text`, or null where the text is not one. A canvas is a JSON object with a `nodes` or an `edges`
 * array (the spec makes both optional; an object with neither is not a canvas, it is `{}`). Nodes that are not nodes
 * are left out, as are edges to nodes that are not there, and a node's id appearing twice keeps the first.
 */
export function parseCanvas(text: string): Canvas | null {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return null;
  }
  if (!isRecord(value)) return null;
  if (!Array.isArray(value.nodes) && !Array.isArray(value.edges)) return null;
  const nodes: CanvasNode[] = [];
  const seen = new Set<string>();
  for (const entry of Array.isArray(value.nodes) ? value.nodes : []) {
    const node = readNode(entry);
    if (node && !seen.has(node.id)) {
      seen.add(node.id);
      nodes.push(node);
    }
  }
  const edges: CanvasEdge[] = [];
  const edgeIds = new Set<string>();
  for (const entry of Array.isArray(value.edges) ? value.edges : []) {
    const edge = readEdge(entry, seen);
    if (edge && !edgeIds.has(edge.id)) {
      edgeIds.add(edge.id);
      edges.push(edge);
    }
  }
  return { nodes, edges };
}

/** The canvas as the spec writes it, two spaces in, a newline at the end, the way Obsidian saves one. */
export function serializeCanvas(canvas: Canvas): string {
  return `${JSON.stringify({ nodes: canvas.nodes, edges: canvas.edges }, null, 2)}\n`;
}

// ---- a canvas as a note ---------------------------------------------------------------------

/** A front matter fence, `---` or `+++`, on a line of its own. */
const FENCE = /^(---|\+\+\+)\s*$/;

/**
 * The body after its front matter, where it opens with one: what `withoutFrontMatter` (core/store.ts) does, but
 * without putting the title back as a first line - a canvas's first line is `{`, and the title is the note's name.
 */
function afterFrontMatter(body: string): string {
  const lines = body.split('\n');
  if (!FENCE.test(lines[0] ?? '')) return body;
  for (let n = 1; n < Math.min(lines.length, 40); n += 1) {
    if (FENCE.test(lines[n] ?? '')) return lines.slice(n + 1).join('\n');
  }
  return body;
}

/** The canvas a note's body is, or null for a note that is words: front matter, then the JSON and nothing else. */
export function canvasOf(body: string): Canvas | null {
  const rest = afterFrontMatter(body).trim();
  return rest.startsWith('{') ? parseCanvas(rest) : null;
}

/** Whether the note is a canvas rather than words: cheap enough to ask of every note in a list. */
export function isCanvasBody(body: string): boolean {
  return canvasOf(body) !== null;
}

/**
 * A canvas note's body: the title as front matter, which is how the note gets its name (core/store.ts `noteTitle`
 * reads `title:`), then the canvas exactly as the spec writes it. Quoted, so a title with a colon in it stays one line.
 */
export function canvasNoteBody(title: string, canvas: Canvas): string {
  const safe = title.replace(/["\n]/g, "'").trim() || 'Canvas';
  return `---\ntitle: "${safe}"\n---\n${serializeCanvas(canvas)}`;
}

// ---- changing a canvas ----------------------------------------------------------------------

/**
 * The note's body with its canvas replaced and everything else kept: the front matter that names it, character for
 * character, then the canvas as the spec writes it. `canvasNoteBody` is for a new note; this is for a note being
 * edited, whose front matter may hold more than a title.
 */
export function withCanvas(body: string, canvas: Canvas): string {
  const lines = body.split('\n');
  if (FENCE.test(lines[0] ?? '')) {
    for (let n = 1; n < Math.min(lines.length, 40); n += 1) {
      if (FENCE.test(lines[n] ?? '')) return `${lines.slice(0, n + 1).join('\n')}\n${serializeCanvas(canvas)}`;
    }
  }
  return serializeCanvas(canvas);
}

/** An id for a new node or edge: sixteen hex characters, the shape Obsidian gives its own. */
export function newCanvasId(): string {
  const bytes = new Uint8Array(8);
  if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') crypto.getRandomValues(bytes);
  else for (let n = 0; n < bytes.length; n += 1) bytes[n] = Math.floor(Math.random() * 256);
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** The size a new card of words starts at, in the canvas's pixels: Obsidian's, so a canvas made here looks like one. */
export const NEW_CARD = { width: 260, height: 120 };

/** A new card of words, empty, with its top-left corner at (x, y). It goes last, so it is drawn on top. */
export function newTextNode(x: number, y: number, id = newCanvasId()): CanvasNode {
  return { id, type: 'text', x: Math.round(x), y: Math.round(y), width: NEW_CARD.width, height: NEW_CARD.height, text: '' };
}

/** A new card that is a note, by its title: the spec's file node, named as Obsidian names a note's file. */
export function newFileNode(title: string, x: number, y: number, id = newCanvasId()): CanvasNode {
  const name = title.trim().replace(/[\\/]/g, '-') || 'Untitled';
  return { id, type: 'file', x: Math.round(x), y: Math.round(y), width: NEW_CARD.width, height: 160, file: `${name}.md` };
}

/** A new card that is one of Glyph's own pictures, by the name the picture store keeps it under (core/images.ts). */
export function newPictureNode(name: string, x: number, y: number, id = newCanvasId()): CanvasNode {
  return { id, type: 'file', x: Math.round(x), y: Math.round(y), width: NEW_CARD.width, height: 200, file: name };
}

/** What a new chart card starts with: a small Mermaid diagram to change, drawn as a diagram on the card. */
export const CHART_CARD = '```mermaid\nflowchart LR\n  A[Start] --> B[Then]\n  B --> C[Done]\n```\n';
/** Whether a card of words is nothing but a table, which is then drawn edge to edge (canvas/CanvasView.tsx). */
export function isOnlyTable(text: string): boolean {
  const lines = text.trim().split('\n');
  return lines.length >= 2 && lines.every((line) => /^\s*\|.*\|\s*$/.test(line));
}

/** What a new table card starts with. */
export const TABLE_CARD = '| Thing | Note |\n| --- | --- |\n| One | |\n| Two | |\n';

/** A new card that is a web address; a bare address is given https. Null for no address at all. */
export function newLinkNode(url: string, x: number, y: number, id = newCanvasId()): CanvasNode | null {
  const given = url.trim();
  if (!given) return null;
  const address = /^[a-z][a-z0-9+.-]*:/i.test(given) ? given : `https://${given}`;
  return { id, type: 'link', x: Math.round(x), y: Math.round(y), width: NEW_CARD.width, height: 100, url: address };
}

/** The canvas with this node in place of the one with its id, or added at the end where there was none. */
export function withNode(canvas: Canvas, node: CanvasNode): Canvas {
  const at = canvas.nodes.findIndex((n) => n.id === node.id);
  const nodes = at < 0 ? [...canvas.nodes, node] : canvas.nodes.map((n) => (n.id === node.id ? node : n));
  return { nodes, edges: canvas.edges };
}

/** The canvas without this node, and without any edge that joined it. */
export function withoutNode(canvas: Canvas, id: string): Canvas {
  return { nodes: canvas.nodes.filter((n) => n.id !== id), edges: canvas.edges.filter((e) => e.fromNode !== id && e.toNode !== id) };
}

/** A new line from one card to another: an arrow at its end, its sides chosen from where the cards are (`sidesOf`). */
export function newEdge(fromNode: string, toNode: string, id = newCanvasId()): CanvasEdge {
  return { id, fromNode, toNode };
}

/** The canvas with this line in place of the one with its id, or added at the end where there was none. */
export function withEdge(canvas: Canvas, edge: CanvasEdge): Canvas {
  const at = canvas.edges.findIndex((e) => e.id === edge.id);
  const edges = at < 0 ? [...canvas.edges, edge] : canvas.edges.map((e) => (e.id === edge.id ? edge : e));
  return { nodes: canvas.nodes, edges };
}

export function withoutEdge(canvas: Canvas, id: string): Canvas {
  return { nodes: canvas.nodes, edges: canvas.edges.filter((e) => e.id !== id) };
}

/** The line with these words on it, or with none: the spec has no empty label, so blank takes the label off. */
export function labelledEdge(edge: CanvasEdge, label: string): CanvasEdge {
  const words = label.trim();
  const { label: _was, ...rest } = edge;
  return words ? { ...rest, label: words } : rest;
}

/** Whether a line already joins these two cards, either way round: a second one would only lie on the first. */
export function joined(canvas: Canvas, a: string, b: string): boolean {
  return canvas.edges.some((e) => (e.fromNode === a && e.toNode === b) || (e.fromNode === b && e.toNode === a));
}

/** The smallest a card can be made, in the canvas's pixels: room for a word and the cross. */
export const LEAST_CARD = { width: 120, height: 60 };

/** The node made this size, to the pixel and no smaller than `LEAST_CARD`; its top-left corner stays put. */
export function resizedNode(node: CanvasNode, width: number, height: number): CanvasNode {
  return { ...node, width: Math.max(LEAST_CARD.width, Math.round(width)), height: Math.max(LEAST_CARD.height, Math.round(height)) };
}

/** The nodes a group holds: every other node whose box is wholly inside the group's, as Obsidian counts them. */
export function heldBy(canvas: Canvas, group: CanvasNode): CanvasNode[] {
  return canvas.nodes.filter(
    (n) => n.id !== group.id && n.x >= group.x && n.y >= group.y && n.x + n.width <= group.x + group.width && n.y + n.height <= group.y + group.height,
  );
}

/**
 * The canvas with this node moved to (x, y) - and, for a group, everything it holds moved with it by the same
 * amount (choice 5: "cards inside move with it"). A card moved on its own leaves its group where it is.
 */
export function movedWithHeld(canvas: Canvas, node: CanvasNode, x: number, y: number): Canvas {
  const dx = Math.round(x) - node.x;
  const dy = Math.round(y) - node.y;
  const moving = new Set(node.type === 'group' ? [node.id, ...heldBy(canvas, node).map((n) => n.id)] : [node.id]);
  return { nodes: canvas.nodes.map((n) => (moving.has(n.id) ? movedNode(n, n.x + dx, n.y + dy) : n)), edges: canvas.edges };
}

/** Room a new group leaves around the cards it is drawn round, in the canvas's pixels. */
export const GROUP_ROOM = 40;

/**
 * A new group drawn round these nodes with room to spare, placed first so it is drawn under everything (the spec's
 * z-order is the array's). Null for no nodes: a group holds something.
 */
export function newGroupAround(canvas: Canvas, ids: readonly string[], label?: string, id = newCanvasId()): Canvas | null {
  const held = canvas.nodes.filter((n) => ids.includes(n.id));
  if (!held.length) return null;
  const box = bounds({ nodes: held, edges: [] })!;
  const group: CanvasNode = {
    id,
    type: 'group',
    x: box.x - GROUP_ROOM,
    y: box.y - GROUP_ROOM - 24,
    width: box.width + GROUP_ROOM * 2,
    height: box.height + GROUP_ROOM * 2 + 24,
    ...(label ? { label } : {}),
  };
  return { nodes: [group, ...canvas.nodes], edges: canvas.edges };
}

/** The group with these words as its name, or with none. */
export function labelledGroup(node: CanvasNode, label: string): CanvasNode {
  if (node.type !== 'group') return node;
  const words = label.trim();
  const { label: _was, ...rest } = node;
  return words ? { ...rest, label: words } : rest;
}

/** The node moved so its top-left corner is at (x, y), to the pixel, as the spec keeps positions. */
export function movedNode(node: CanvasNode, x: number, y: number): CanvasNode {
  return { ...node, x: Math.round(x), y: Math.round(y) };
}

// ---- geometry -------------------------------------------------------------------------------

export interface Box {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** The smallest box around every node, or null for an empty canvas. */
export function bounds(canvas: Canvas): Box | null {
  if (!canvas.nodes.length) return null;
  let left = Infinity;
  let top = Infinity;
  let right = -Infinity;
  let bottom = -Infinity;
  for (const node of canvas.nodes) {
    left = Math.min(left, node.x);
    top = Math.min(top, node.y);
    right = Math.max(right, node.x + node.width);
    bottom = Math.max(bottom, node.y + node.height);
  }
  return { x: left, y: top, width: right - left, height: bottom - top };
}

export interface Point {
  x: number;
  y: number;
}

const centre = (box: Box): Point => ({ x: box.x + box.width / 2, y: box.y + box.height / 2 });

/** The middle of a node's side: where an edge attaches. */
export function anchorOf(node: Box, side: Side): Point {
  switch (side) {
    case 'top':
      return { x: node.x + node.width / 2, y: node.y };
    case 'right':
      return { x: node.x + node.width, y: node.y + node.height / 2 };
    case 'bottom':
      return { x: node.x + node.width / 2, y: node.y + node.height };
    case 'left':
      return { x: node.x, y: node.y + node.height / 2 };
  }
}

/** Which way a side faces, as a unit step. */
const NORMAL: Record<Side, Point> = { top: { x: 0, y: -1 }, right: { x: 1, y: 0 }, bottom: { x: 0, y: 1 }, left: { x: -1, y: 0 } };

/**
 * The sides an edge leaves and arrives by when it does not say: the side of each node that faces the other, by
 * whichever of across or down the two are further apart in. Obsidian writes the sides it chose; another writer may
 * not, and the spec allows it.
 */
export function sidesOf(from: Box, to: Box, edge: Pick<CanvasEdge, 'fromSide' | 'toSide'>): { from: Side; to: Side } {
  const a = centre(from);
  const b = centre(to);
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const across = Math.abs(dx) >= Math.abs(dy);
  const out: Side = across ? (dx >= 0 ? 'right' : 'left') : dy >= 0 ? 'bottom' : 'top';
  const back: Side = across ? (dx >= 0 ? 'left' : 'right') : dy >= 0 ? 'top' : 'bottom';
  return { from: edge.fromSide ?? out, to: edge.toSide ?? back };
}

/** The size of an arrow head, in the canvas's pixels; the line stops short of the tip by this much. */
export const HEAD = 10;

export interface EdgePath {
  /** The curve, as an SVG path: from one anchor to the other, stopping short of any arrow head. */
  d: string;
  /** The head at each end, as an SVG path of a filled triangle, where that end is an arrow. */
  fromHead: string | null;
  toHead: string | null;
  /** Halfway along the curve, where its label sits. */
  mid: Point;
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

/**
 * The line for an edge: a curve out of one side and into the other, bowing further the further apart the nodes are,
 * the way Obsidian draws one; the heads the edge asks for (an arrow at the end unless it says otherwise); and the
 * point halfway along, for the label. Null where either node is missing.
 */
export function edgePath(canvas: Canvas, edge: CanvasEdge): EdgePath | null {
  const from = canvas.nodes.find((n) => n.id === edge.fromNode);
  const to = canvas.nodes.find((n) => n.id === edge.toNode);
  if (!from || !to) return null;
  const sides = sidesOf(from, to, edge);
  const a = anchorOf(from, sides.from);
  const b = anchorOf(to, sides.to);
  const na = NORMAL[sides.from];
  const nb = NORMAL[sides.to];
  const fromArrow = (edge.fromEnd ?? 'none') === 'arrow';
  const toArrow = (edge.toEnd ?? 'arrow') === 'arrow';
  // The curve ends at the base of a head, not its tip, so the line never pokes through the point.
  const start = fromArrow ? { x: a.x + na.x * HEAD, y: a.y + na.y * HEAD } : a;
  const end = toArrow ? { x: b.x + nb.x * HEAD, y: b.y + nb.y * HEAD } : b;
  const reach = Math.max(30, Math.min(Math.hypot(end.x - start.x, end.y - start.y) * 0.4, 200));
  const c1 = { x: start.x + na.x * reach, y: start.y + na.y * reach };
  const c2 = { x: end.x + nb.x * reach, y: end.y + nb.y * reach };
  const mid = {
    x: (start.x + 3 * c1.x + 3 * c2.x + end.x) / 8,
    y: (start.y + 3 * c1.y + 3 * c2.y + end.y) / 8,
  };
  return {
    d: `M${start.x} ${start.y}C${c1.x} ${c1.y} ${c2.x} ${c2.y} ${end.x} ${end.y}`,
    fromHead: fromArrow ? head(a, sides.from) : null,
    toHead: toArrow ? head(b, sides.to) : null,
    mid,
  };
}

// ---- colour ---------------------------------------------------------------------------------

/** The page's hues (ink.css `[data-hue]`), which are what a workspace wears too (core/workspaces.ts). */
export type CanvasHue = 'rose' | 'ember' | 'amber' | 'moss' | 'sea' | 'violet';

/**
 * The spec's six presets - red, orange, yellow, green, cyan, purple, their exact values "intentionally not defined"
 * so each app paints them its own way - as the page's own hues (Matt: workspace hues, not a palette of the canvas's
 * own). A hex colour is a colour someone chose in Obsidian and is kept as it is.
 */
export function paintOf(color: CanvasColor | undefined): { hue: CanvasHue } | { hex: string } | null {
  switch (color) {
    case '1':
      return { hue: 'rose' };
    case '2':
      return { hue: 'ember' };
    case '3':
      return { hue: 'amber' };
    case '4':
      return { hue: 'moss' };
    case '5':
      return { hue: 'sea' };
    case '6':
      return { hue: 'violet' };
    default:
      return color && color.startsWith('#') ? { hex: color } : null;
  }
}

/** A file node's name as a note's title: the last part of the path, without `.md`. `Plans/Cabin trip.md` is "Cabin trip". */
export function fileTitle(file: string): string {
  const name = file.split('/').pop() ?? file;
  return name.replace(/\.md$/i, '');
}

/** Whether a file node points at a picture rather than a note. */
export function isImageFile(file: string): boolean {
  return /\.(png|jpe?g|gif|webp|avif|svg|bmp)$/i.test(file);
}
