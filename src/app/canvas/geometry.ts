import type { Canvas, CanvasEdge, Side } from './jsonCanvas.ts';

/**
 * Where a canvas's cards are, in the canvas's own pixels: the box round them all, the middle of a card's side where
 * a line attaches, and which sides two cards face each other by. Pure, and shared by the lines (lines.ts), the view
 * maths (viewport.ts) and the minimap (Minimap.tsx), so all three agree on where a card's edge is.
 */

export interface Box {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface Point {
  x: number;
  y: number;
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

/** The middle of a box. */
export const centre = (box: Box): Point => ({ x: box.x + box.width / 2, y: box.y + box.height / 2 });

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
export const NORMAL: Record<Side, Point> = { top: { x: 0, y: -1 }, right: { x: 1, y: 0 }, bottom: { x: 0, y: 1 }, left: { x: -1, y: 0 } };

/**
 * The sides an edge leaves and arrives by when it does not say: the side of each node that faces the other, by
 * whichever of across or down the two are further apart in, across when they are as far apart each way. Obsidian
 * writes the sides it chose; another writer may not, and the spec allows it.
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
