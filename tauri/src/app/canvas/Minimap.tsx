import { memo, useRef, type PointerEvent as ReactPointerEvent, type RefObject } from 'react';
import { imageUrl } from '../core/images.ts';
import { fileTitle, isImageFile, ownPicture, paintProps } from './cardLooks.ts';
import { bounds } from './geometry.ts';
import type { Canvas, CanvasEdge, CanvasNode } from './jsonCanvas.ts';
import type { EdgePath } from './lines.ts';
import { noteBars, roundedBox, wordBars, type MapBar } from './mapDetail.ts';
import { shown as shownBox, type View } from './viewport.ts';
import styles from './Minimap.module.css';

/**
 * The minimap (choice 10), in the bottom corner of the canvas (canvas/CanvasView.tsx): the whole canvas small, with
 * the screen's box over it. The map keeps the canvas's own shape inside its frame, and draws the screen's box even
 * when the screen is off the cards. A canvas of fewer than two cards has no map: there is nothing to find.
 *
 * It is the canvas itself, small, and not a diagram of it (Matt: "the canvas minimap could also be far more detailed
 * with modern displays"). Everything is drawn in the canvas's own pixels under one transform, as vectors, so it is as
 * sharp as the screen is: a card of words shows the shape of its words - a heading's heavier bar, a list's dots, a
 * paragraph's lines (mapDetail.ts) - a note its title and a few lines, a picture is the picture, an address a ring;
 * the lines are the canvas's own curves and arrow heads (lines.ts, handed in by the view, which has already worked
 * them out); a group is its dashed box and its name. A card with a colour wears it.
 *
 * The screen's box is a soft line with round corners, and what is outside it is shaded, so where you are reads as the
 * lit part of the map (Matt: "the frame is too bright white and has no radii": it was a line of the page's full ink,
 * a pixel and a half thick, with a one-pixel corner).
 *
 * A press on it grows it, and it stays grown until a press lands on the canvas (Matt: "make the minimap a bit
 * bigger when we click on it and allow clicking and dragging to navigate around the canvas"). A drag on the map,
 * small or grown, moves the screen's box with the finger - the view goes by what the finger moved, so nothing jumps
 * under it - and a tap on the grown map goes to the spot tapped. The map is drawn in one set of units, whatever its
 * size on the page, so where a finger is on it is read from the size it has at that moment, mid-growth included.
 */

/** The map's frame and the room inside it, in the map's own units; grown, the stylesheet draws it half again as big. */
const MINIMAP = { width: 204, height: 136, room: 8 };
/** The round of the screen's box, in the map's units. */
const SEEN_ROUND = 5;
/** A press that moves this far, in pixels on the page, is a drag rather than a tap. */
const MAP_DRAG = 3;

interface MinimapProps {
  canvas: Canvas;
  /** The canvas's lines as the view draws them (lines.ts `edgePaths`), so the map's are the same curves. */
  lines: readonly { edge: CanvasEdge; path: EdgePath }[];
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

const kindOf = (n: CanvasNode) => (n.type === 'file' ? (isImageFile(n.file) ? 'picture' : 'note') : n.type);

/** A card's bars, in the canvas's pixels, where the card is. */
function Bars({ node, bars }: { node: CanvasNode; bars: MapBar[] }) {
  return (
    <>
      {bars.map((bar, i) => (
        <rect key={i} className={styles.mapBar} data-strong={bar.strong || undefined} x={node.x + bar.x} y={node.y + bar.y} width={bar.width} height={bar.height} rx={bar.height / 2} />
      ))}
    </>
  );
}

/**
 * Everything on the canvas, in the canvas's own pixels: the groups under, then the lines, then the cards. Kept
 * between draws while the canvas is the same one (and its pictures have the same addresses), so a pan redraws the
 * screen's box and one transform and nothing else. `detail` is whether a line of words would be seen at all at the
 * size the map is.
 */
const MapWorld = memo(function MapWorld({ canvas, lines, pictures, detail, unit }: { canvas: Canvas; lines: MinimapProps['lines']; pictures: string; detail: boolean; unit: number }) {
  const urls = new Map(pictures ? pictures.split('\n').map((line) => line.split('\t') as [string, string]) : []);
  const groups = canvas.nodes.filter((n) => n.type === 'group');
  const cards = canvas.nodes.filter((n) => n.type !== 'group');
  return (
    <>
      {groups.map((n) => (
        // A group wears a preset's hue; a hex is the cards' own, not the group's, on the map.
        <g key={n.id} className={styles.mapGroup} data-hue={paintProps(n.color).hue}>
          <rect x={n.x} y={n.y} width={n.width} height={n.height} rx={16} />
          {n.type === 'group' && n.label && n.width / unit > 36 ? (
            <text x={n.x + 4 * unit} y={n.y - 3 * unit} className={styles.mapLabel} style={{ fontSize: 7 * unit }}>
              {n.label}
            </text>
          ) : null}
        </g>
      ))}
      {lines.map(({ edge, path }) => {
        const paint = paintProps(edge.color);
        return (
          <g key={edge.id} className={styles.mapEdge} data-hue={paint.hue} style={paint.style}>
            <path className={styles.mapLine} d={path.d} />
            {path.fromHead ? <path className={styles.mapHead} d={path.fromHead} /> : null}
            {path.toHead ? <path className={styles.mapHead} d={path.toHead} /> : null}
          </g>
        );
      })}
      {cards.map((n) => {
        const paint = paintProps(n.color);
        const kind = kindOf(n);
        const url = urls.get(n.id);
        return (
          <g key={n.id} className={styles.mapCard} data-kind={kind} data-hue={paint.hue} style={paint.style}>
            <rect className={styles.mapCardBox} x={n.x} y={n.y} width={n.width} height={n.height} rx={12} />
            {url ? (
              <>
                <clipPath id={`map-clip-${n.id}`}>
                  <rect x={n.x} y={n.y} width={n.width} height={n.height} rx={12} />
                </clipPath>
                <image href={url} x={n.x} y={n.y} width={n.width} height={n.height} preserveAspectRatio="xMidYMid slice" clipPath={`url(#map-clip-${n.id})`} />
              </>
            ) : null}
            {detail && n.type === 'text' ? <Bars node={n} bars={wordBars(n.text, n.width, n.height)} /> : null}
            {detail && kind === 'note' && n.type === 'file' ? <Bars node={n} bars={noteBars(fileTitle(n.file), n.width, n.height)} /> : null}
            {kind === 'link' ? <circle className={styles.mapDot} cx={n.x + n.width / 2} cy={n.y + n.height / 2} r={Math.min(14, n.height / 3)} /> : null}
          </g>
        );
      })}
    </>
  );
});

export function Minimap({ canvas, lines, view, host, big, onBig, onGo, onMove }: MinimapProps) {
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
  // The pictures the store has an address for, by card: the map draws them, and draws again when one arrives.
  const pictures = canvas.nodes
    .map((n) => {
      const own = ownPicture(n);
      const url = own ? imageUrl(own) : null;
      return url ? `${n.id}\t${url}` : '';
    })
    .filter(Boolean)
    .join('\n');
  // A line of a card's words is worth drawing once it is a quarter of a unit thick: a device pixel, near enough, on
  // the screens this is for. Below that the bars are a grey and the card is drawn plain.
  const detail = scale * 8 >= 0.25;
  const sw = seen.width * scale;
  const sh = seen.height * scale;
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
      {/* The canvas, in its own pixels, moved and scaled into the frame by one transform. */}
      <g transform={`translate(${ox - left * scale} ${oy - top * scale}) scale(${scale})`}>
        <MapWorld canvas={canvas} lines={lines} pictures={pictures} detail={detail} unit={1 / scale} />
      </g>
      {/* What the screen does not show, shaded; and the screen's box, a soft line with round corners. */}
      <path className={styles.mapShade} fillRule="evenodd" d={`M0 0H${MINIMAP.width}V${MINIMAP.height}H0Z${roundedBox(sx(seen.x), sy(seen.y), sw, sh, SEEN_ROUND)}`} />
      <rect className={styles.mapSeen} x={sx(seen.x)} y={sy(seen.y)} width={sw} height={sh} rx={Math.min(SEEN_ROUND, sw / 2, sh / 2)} />
    </svg>
  );
}
