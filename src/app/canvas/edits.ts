import type { Canvas, CanvasEdge, CanvasNode } from './jsonCanvas.ts';

/**
 * Making and changing a canvas: the cards and lines the view adds, and the edits it makes to them - moved, resized,
 * named, written in, taken off. Every edit is a new Canvas, the old one left as it was, so the view can hold the
 * canvas as it was when a finger took hold and measure a drag from there (canvas/CanvasView.tsx), and hand the note
 * the whole canvas to write back (jsonCanvas.ts `withCanvas`).
 *
 * The node array is the z-order (jsonCanvas.ts `Canvas`): a new card goes last, so it is drawn on top, and an edit
 * keeps every other node where it was in the array, since sorting them would change both the drawing and the file
 * Obsidian reads.
 */

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

/** The canvas without this line; the cards it joined stay. */
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
