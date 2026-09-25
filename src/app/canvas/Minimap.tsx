import { useRef, type PointerEvent as ReactPointerEvent, type RefObject } from 'react';
import { isImageFile, paintProps } from './cardLooks.ts';
import { anchorOf, bounds, sidesOf } from './geometry.ts';
import type { Canvas, CanvasNode } from './jsonCanvas.ts';
import { shown as shownBox, type View } from './viewport.ts';
import styles from './Minimap.module.css';

/**
 * The minimap (choice 10), in the bottom corner of the canvas (canvas/CanvasView.tsx): the whole canvas small, with
 * the screen's box over it. Each kind of card is told apart - words filled, a note outlined, a picture filled dark, a
 * link outlined with a dot - and a card with a colour wears it; the lines between cards are drawn between the sides
 * they leave and arrive by, and a group is its dashed box with its name when there is room. The map keeps the
 * canvas's own shape inside its frame, and draws the screen's box even when the screen is off the cards. A canvas of
 * fewer than two cards has no map: there is nothing to find.
 *
 * A press on it grows it, and it stays grown until a press lands on the canvas (Matt: "make the minimap a bit
 * bigger when we click on it and allow clicking and dragging to navigate around the canvas"). A drag on the map,
 * small or grown, moves the screen's box with the finger - the view goes by what the finger moved, so nothing jumps
 * under it - and a tap on the grown map goes to the spot tapped. The map is drawn in one set of units, whatever its
 * size on the page, so where a finger is on it is read from the size it has at that moment, mid-growth included.
 */

/** The map's frame and the room inside it, in the map's own units; grown, the stylesheet draws it half again as big. */
const MINIMAP = { width: 180, height: 120, room: 8 };
/** A press that moves this far, in pixels on the page, is a drag rather than a tap. */
const MAP_DRAG = 3;

interface MinimapProps {
  canvas: Canvas;
  /** The view as last drawn: the map is redrawn from it once a frame at most. */
  view: View;
  /** The canvas's element, for the size of the screen the view shows. */
  host: RefObject<HTMLDivElement | null>;
  big: boolean;
  onBig: () => void;
  /** The screen centred on this point of the canvas. */
  onGo: (x: number, y: number) => void;
  /** The screen's box moved this far, in the canvas's own pixels. */
  onMove: (dx: number, dy: number) => void;
}

export function Minimap({ canvas, view, host, big, onBig, onGo, onMove }: MinimapProps) {
  /** The press under way: where the finger was last, on the page, and whether it has dragged. */
  const press = useRef<{ x: number; y: number; moved: boolean; wasBig: boolean } | null>(null);
  const box = bounds(canvas);
  if (!box || canvas.nodes.length < 2) return null;
  const el = host.current;
  const seen = shownBox(view, el?.clientWidth ?? 0, el?.clientHeight ?? 0);
  // The whole of the canvas and the screen's box together, so the screen is always drawn even when it is off the cards.
  const left = Math.min(box.x, seen.x);
  const top = Math.min(box.y, seen.y);
  const right = Math.max(box.x + box.width, seen.x + seen.width);
  const bottom = Math.max(box.y + box.height, seen.y + seen.height);
  const scale = Math.min((MINIMAP.width - MINIMAP.room * 2) / Math.max(right - left, 1), (MINIMAP.height - MINIMAP.room * 2) / Math.max(bottom - top, 1));
  // Centred in the frame, so a tall canvas sits in the middle of a wide map rather than against its left edge.
  const ox = MINIMAP.room + (MINIMAP.width - MINIMAP.room * 2 - (right - left) * scale) / 2;
  const oy = MINIMAP.room + (MINIMAP.height - MINIMAP.room * 2 - (bottom - top) * scale) / 2;
  const sx = (x: number) => ox + (x - left) * scale;
  const sy = (y: number) => oy + (y - top) * scale;
  /** Pixels on the page per unit of the map, at the size the map has now. */
  const unit = (rect: DOMRect) => (rect.width || MINIMAP.width) / MINIMAP.width;
  const go = (event: ReactPointerEvent<SVGSVGElement>) => {
    const rect = event.currentTarget.getBoundingClientRect();
    const k = unit(rect);
    onGo(left + ((event.clientX - rect.left) / k - ox) / scale, top + ((event.clientY - rect.top) / k - oy) / scale);
  };
  const kind = (n: CanvasNode) => (n.type === 'file' ? (isImageFile(n.file) ? 'picture' : 'note') : n.type);
  const groups = canvas.nodes.filter((n) => n.type === 'group');
  const cards = canvas.nodes.filter((n) => n.type !== 'group');
  return (
    <svg
      className={styles.minimap}
      viewBox={`0 0 ${MINIMAP.width} ${MINIMAP.height}`}
      data-big={big || undefined}
      role="img"
      aria-label="A map of the canvas; press to grow it, drag on it to move the screen, tap the grown map to go there"
      onPointerDown={(event) => {
        event.stopPropagation();
        press.current = { x: event.clientX, y: event.clientY, moved: false, wasBig: big };
        onBig();
        try {
          event.currentTarget.setPointerCapture(event.pointerId);
        } catch {
          // A pointer the browser is not tracking: the press still counts; only the drag past the edge is lost.
        }
      }}
      onPointerMove={(event) => {
        const p = press.current;
        if (!p || !event.buttons) return;
        const dx = event.clientX - p.x;
        const dy = event.clientY - p.y;
        if (!p.moved && Math.hypot(dx, dy) < MAP_DRAG) return;
        p.moved = true;
        p.x = event.clientX;
        p.y = event.clientY;
        const k = unit(event.currentTarget.getBoundingClientRect());
        onMove(dx / k / scale, dy / k / scale);
      }}
      onPointerUp={(event) => {
        const p = press.current;
        press.current = null;
        // A tap on the grown map goes there; the tap that grew it only grew it.
        if (p && !p.moved && p.wasBig) go(event);
      }}
      onPointerCancel={() => {
        press.current = null;
      }}
      onClick={(event) => event.stopPropagation()}
    >
      {groups.map((n) => (
        // A group wears a preset's hue; a hex is the cards' own, not the group's, on the map.
        <g key={n.id} className={styles.mapGroup} data-hue={paintProps(n.color).hue}>
          <rect x={sx(n.x)} y={sy(n.y)} width={Math.max(2, n.width * scale)} height={Math.max(2, n.height * scale)} rx={2} />
          {n.type === 'group' && n.label && n.width * scale > 36 ? (
            <text x={sx(n.x) + 3} y={sy(n.y) - 2} className={styles.mapLabel}>
              {n.label}
            </text>
          ) : null}
        </g>
      ))}
      {canvas.edges.map((edge) => {
        const from = canvas.nodes.find((n) => n.id === edge.fromNode);
        const to = canvas.nodes.find((n) => n.id === edge.toNode);
        if (!from || !to) return null;
        const sides = sidesOf(from, to, edge);
        const a = anchorOf(from, sides.from);
        const b = anchorOf(to, sides.to);
        return <line key={edge.id} className={styles.mapLine} x1={sx(a.x)} y1={sy(a.y)} x2={sx(b.x)} y2={sy(b.y)} />;
      })}
      {cards.map((n) => {
        const paint = paintProps(n.color);
        const w = Math.max(3, n.width * scale);
        const h = Math.max(3, n.height * scale);
        return (
          <g key={n.id} className={styles.mapCard} data-kind={kind(n)} data-hue={paint.hue} style={paint.style}>
            <rect x={sx(n.x)} y={sy(n.y)} width={w} height={h} rx={1.5} />
            {kind(n) === 'link' ? <circle cx={sx(n.x) + w / 2} cy={sy(n.y) + h / 2} r={Math.min(2, h / 3)} /> : null}
          </g>
        );
      })}
      <rect className={styles.mapSeen} x={sx(seen.x)} y={sy(seen.y)} width={seen.width * scale} height={seen.height * scale} rx={1} />
    </svg>
  );
}
