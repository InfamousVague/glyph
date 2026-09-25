import { frontMatterEnd, quotedTitle } from '../core/frontMatter.ts';

/**
 * JSON Canvas (jsoncanvas.org, 1.0), the open format Obsidian's canvas is written in, read and written as it is.
 *
 * Matt's choices (2026-09-20): a canvas in Glyph is the spec verbatim, so a canvas made here opens in Obsidian and an
 * Obsidian canvas opens here, rather than a grammar of Glyph's own. A canvas is a note whose body is the JSON
 * (docs/CANVAS.md), named by front matter since Obsidian names one by its file and Glyph has no files; a note shows
 * one inside its words as a `![[Title]]` frame (editor/canvasFrames.ts). This file is the format and the note that
 * holds it. What is made and changed on a canvas is edits.ts and where things are geometry.ts, neither of which knows
 * the screen; how lines run is lines.ts, which knows only how wide a label's letters are drawn; and cards.ts is what
 * the screen makes of a node: the hue or colour it wears, the title of its file, whether it is a picture or a table.
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

/**
 * The body after its front matter, where it opens with one: what `withoutFrontMatter` (core/noteTitle.ts) does, but
 * without putting the title back as a first line - a canvas's first line is `{`, and the title is the note's name.
 */
function afterFrontMatter(body: string): string {
  const lines = body.split('\n');
  const end = frontMatterEnd(lines);
  return end ? lines.slice(end).join('\n') : body;
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
 * A canvas note's body: the title as front matter, which is how the note gets its name (core/noteTitle.ts reads
 * `title:`), then the canvas exactly as the spec writes it. Quoted, so a title with a colon in it stays one line.
 */
export function canvasNoteBody(title: string, canvas: Canvas): string {
  return `---\ntitle: ${quotedTitle(title, 'Canvas')}\n---\n${serializeCanvas(canvas)}`;
}

/**
 * The note's body with its canvas replaced and everything else kept: the front matter that names it, character for
 * character, then the canvas as the spec writes it. `canvasNoteBody` is for a new note; this is for a note being
 * edited, whose front matter may hold more than a title.
 */
export function withCanvas(body: string, canvas: Canvas): string {
  const lines = body.split('\n');
  const end = frontMatterEnd(lines);
  return end ? `${lines.slice(0, end).join('\n')}\n${serializeCanvas(canvas)}` : serializeCanvas(canvas);
}
