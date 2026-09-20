import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Editor } from '../editor/Editor.tsx';
import { NotePeek } from '../notes/NotePeek.tsx';
import { openLink } from '../core/linkPreview.ts';
import { shortUrl } from '../core/shortUrl.ts';
import { edgePath, fileTitle, isImageFile, paintOf, type Canvas, type CanvasNode } from './jsonCanvas.ts';
import { clampScale, FIT_ROOM, fitted, zoomedAt, type View } from './viewport.ts';
import styles from './CanvasView.module.css';

/**
 * A canvas drawn (docs/CANVAS.md): cards where the file puts them, lines between them, an infinite page under it all
 * that two fingers or a trackpad move and pinch. The first slice (Matt, 2026-09-20: "read and draw an Obsidian file"
 * first, editing second), so nothing here changes the canvas: it reads it faithfully, and a card that is a note or a
 * link opens on a tap.
 *
 * The drawing is one element, the world, moved and scaled with a transform: the cards sit at their own pixel
 * positions inside it, and the lines are one SVG laid over them in the same pixels, so a pinch scales everything at
 * once and nothing is laid out twice. The transform is written straight to the element as the fingers move, not
 * through React, so a pan is a style change and nothing else.
 *
 * A card of words is the note's own editor, read-only and in its peek mode, the way a home card draws a note
 * (notes/NotePeek.tsx) - so a card draws the same way a note does, and an editor is only made once a card is near the
 * screen, since a canvas may hold fifty and each costs a frame.
 */

export interface CanvasWiki {
  /** Whether a note by that title exists: a note card is drawn as a note, or as one waiting to be written. */
  known: (title: string) => boolean;
  /** Opens the note by that title, at an anchor when the card names one. */
  open: (title: string, at?: string) => void;
  /** The note's body by title, for drawing it small on its card; null where the note is not there. */
  body?: (title: string) => string | null;
}

export interface CanvasViewProps {
  canvas: Canvas;
  dark: boolean;
  wiki?: CanvasWiki;
  className?: string;
}

/** How far off the screen a card's editor is made, in screen pixels. */
const NEAR_PX = 300;
/** How far a finger moves before a press is a drag rather than a tap, in screen pixels. */
const SLOP_PX = 4;

/** Where two fingers are, as one point between them and the distance apart; one finger is its point and no distance. */
function grip(pointers: Map<number, { x: number; y: number }>): { x: number; y: number; distance: number } {
  const [a, b] = [...pointers.values()];
  if (!a) return { x: 0, y: 0, distance: 0 };
  if (!b) return { x: a.x, y: a.y, distance: 0 };
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, distance: Math.hypot(a.x - b.x, a.y - b.y) };
}

export function CanvasView({ canvas, dark, wiki, className }: CanvasViewProps) {
  const host = useRef<HTMLDivElement>(null);
  const world = useRef<HTMLDivElement>(null);
  const view = useRef<View>({ x: FIT_ROOM, y: FIT_ROOM, scale: 1 });
  /** Whether a finger or a wheel has moved the view: until then, a screen that changes size fits the canvas again. */
  const touched = useRef(false);
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  /** Where the fingers took hold and what the view was then: every move is measured from here, not from the last. */
  const hold = useRef<{ view: View; x: number; y: number; distance: number } | null>(null);
  /** Whether this press became a drag: the tap that would follow it is not one, and no card opens. */
  const dragged = useRef(false);

  const apply = useCallback(() => {
    const el = world.current;
    if (!el) return;
    const { x, y, scale } = view.current;
    el.style.transform = `translate(${x}px, ${y}px) scale(${scale})`;
  }, []);

  const fit = useCallback(() => {
    const el = host.current;
    if (!el) return;
    view.current = fitted(canvas, el.clientWidth, el.clientHeight);
    touched.current = false;
    apply();
  }, [canvas, apply]);

  // The canvas opens fitted to the screen, and follows the screen's size until it has been moved by hand.
  useEffect(() => {
    fit();
    const el = host.current;
    if (!el || typeof ResizeObserver === 'undefined') return undefined;
    const watcher = new ResizeObserver(() => {
      if (!touched.current) fit();
    });
    watcher.observe(el);
    return () => watcher.disconnect();
  }, [fit]);

  const takeHold = () => {
    const at = grip(pointers.current);
    hold.current = { view: { ...view.current }, x: at.x, y: at.y, distance: at.distance };
  };

  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    // A press is a tap until it moves: a tap on a card that opens something is the card's, and taking the pointer
    // here would take its click with it. It is only captured once it has become a drag.
    if (!pointers.current.size) dragged.current = false;
    pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
    takeHold();
  };

  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!pointers.current.has(event.pointerId) || !hold.current) return;
    pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
    const start = hold.current;
    const now = grip(pointers.current);
    if (!dragged.current) {
      if (pointers.current.size < 2 && Math.hypot(now.x - start.x, now.y - start.y) < SLOP_PX) return;
      dragged.current = true;
      touched.current = true;
      // The drag is the page's now, wherever the pointer goes: off a card, out of the window and back.
      for (const id of pointers.current.keys()) {
        try {
          host.current?.setPointerCapture(id);
        } catch {
          // A pointer already gone: nothing to hold.
        }
      }
    }
    // The point of the canvas that was under the fingers stays under them, whatever they do: a second finger's
    // spread scales about that point, and one finger's move carries it along.
    const scale = start.distance > 0 && now.distance > 0 ? clampScale((start.view.scale * now.distance) / start.distance) : start.view.scale;
    const underX = (start.x - start.view.x) / start.view.scale;
    const underY = (start.y - start.view.y) / start.view.scale;
    view.current = { x: now.x - underX * scale, y: now.y - underY * scale, scale };
    apply();
  };

  const onPointerUp = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!pointers.current.delete(event.pointerId)) return;
    if (pointers.current.size) takeHold();
    else hold.current = null;
  };

  // The click at the end of a drag is the drag's, not a card's: it goes no further.
  const onClickCapture = (event: React.MouseEvent<HTMLDivElement>) => {
    if (!dragged.current) return;
    event.stopPropagation();
    event.preventDefault();
  };

  // A wheel pans, as it does in Obsidian; with the modifier held - which is also what a trackpad pinch arrives as -
  // it zooms about the pointer. Attached by hand: React's wheel is passive, and the page must not scroll instead.
  useEffect(() => {
    const el = host.current;
    if (!el) return undefined;
    const onWheel = (event: WheelEvent) => {
      event.preventDefault();
      touched.current = true;
      const was = view.current;
      if (event.ctrlKey || event.metaKey) {
        const rect = el.getBoundingClientRect();
        view.current = zoomedAt(was, event.clientX - rect.left, event.clientY - rect.top, was.scale * Math.exp(-event.deltaY * 0.01));
      } else {
        view.current = { ...was, x: was.x - event.deltaX, y: was.y - event.deltaY };
      }
      apply();
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, [apply]);

  const edges = useMemo(() => canvas.edges.map((edge) => ({ edge, path: edgePath(canvas, edge) })).filter((e) => e.path), [canvas]);

  return (
    <div
      ref={host}
      className={className ? `${styles.canvas} ${className}` : styles.canvas}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
      onClickCapture={onClickCapture}
      role="img"
      aria-label={`A canvas of ${canvas.nodes.length} cards`}
    >
      <div ref={world} className={styles.world}>
        {canvas.nodes.map((node) => (
          <Card key={node.id} node={node} dark={dark} wiki={wiki} root={host} />
        ))}
        <svg className={styles.edges} aria-hidden="true">
          {edges.map(({ edge, path }) => {
            const paint = paintOf(edge.color);
            const style = paint && 'hex' in paint ? { '--app-space': paint.hex } : undefined;
            return (
              <g key={edge.id} className={styles.edge} data-hue={paint && 'hue' in paint ? paint.hue : undefined} style={style as React.CSSProperties}>
                <path className={styles.line} d={path!.d} />
                {path!.fromHead ? <path className={styles.head} d={path!.fromHead} /> : null}
                {path!.toHead ? <path className={styles.head} d={path!.toHead} /> : null}
                {edge.label ? (
                  <text className={styles.label} x={path!.mid.x} y={path!.mid.y}>
                    {edge.label}
                  </text>
                ) : null}
              </g>
            );
          })}
        </svg>
      </div>
      <div className={styles.tools}>
        <button type="button" className={`app-word ${styles.tool}`} onClick={fit} aria-label="Fit the whole canvas on the screen">
          Fit
        </button>
      </div>
    </div>
  );
}

interface CardProps {
  node: CanvasNode;
  dark: boolean;
  wiki?: CanvasWiki;
  /** The canvas, which is what "near the screen" is measured against. */
  root: React.RefObject<HTMLDivElement | null>;
}

function Card({ node, dark, wiki, root }: CardProps) {
  const paint = paintOf(node.color);
  const hue = paint && 'hue' in paint ? paint.hue : undefined;
  const place: React.CSSProperties = { left: node.x, top: node.y, width: node.width, height: node.height };
  if (paint && 'hex' in paint) (place as Record<string, string>)['--app-space'] = paint.hex;

  if (node.type === 'group') {
    return (
      <div className={styles.group} style={place} data-hue={hue}>
        {node.label ? <span className={styles.groupLabel}>{node.label}</span> : null}
      </div>
    );
  }

  if (node.type === 'text') {
    return (
      <div className={styles.card} style={place} data-hue={hue}>
        <Near root={root} className={styles.words}>
          <Editor value={node.text} onChange={noop} dark={dark} assist={false} readOnly display="formatted" peek grow />
        </Near>
      </div>
    );
  }

  if (node.type === 'link') {
    // An address, opened the way a link in a note is (core/linkPreview.ts): the phone's browser, not a window of ours.
    return (
      <a
        className={`${styles.card} ${styles.linkCard}`}
        style={place}
        data-hue={hue}
        href={node.url}
        onClick={(event) => {
          event.preventDefault();
          void openLink(node.url);
        }}
      >
        <span className={styles.cardTitle}>{shortUrl(node.url)}</span>
        <span className={styles.cardHint}>{node.url}</span>
      </a>
    );
  }

  // A file: a note by that name in Glyph, or a picture, or a file Glyph does not have.
  const title = fileTitle(node.file);
  const picture = isImageFile(node.file);
  const known = !picture && !!wiki?.known(title);
  const body = known ? (wiki?.body?.(title) ?? null) : null;
  const at = node.subpath ? node.subpath.slice(1) : undefined;
  return (
    <div
      className={`${styles.card} ${styles.fileCard}`}
      style={place}
      data-hue={hue}
      data-waiting={known || picture ? undefined : ''}
      role={picture ? undefined : 'button'}
      tabIndex={picture ? undefined : 0}
      onClick={picture ? undefined : () => wiki?.open(title, at)}
      onKeyDown={picture ? undefined : (event) => (event.key === 'Enter' || event.key === ' ') && wiki?.open(title, at)}
    >
      <span className={styles.cardTitle}>{title}</span>
      {body ? (
        <Near root={root}>
          <NotePeek body={body} className={styles.cardPeek} />
        </Near>
      ) : (
        <span className={styles.cardHint}>{picture ? 'A picture, in the vault it came from' : known ? '' : 'Not in Glyph yet'}</span>
      )}
    </div>
  );
}

/** Its children once the card is near the screen, and a blank until then: an editor costs a frame, a blank nothing. */
function Near({ root, className, children }: { root: React.RefObject<HTMLDivElement | null>; className?: string; children: React.ReactNode }) {
  const el = useRef<HTMLDivElement>(null);
  const [near, setNear] = useState(() => typeof IntersectionObserver === 'undefined');
  useEffect(() => {
    const me = el.current;
    if (!me || near || typeof IntersectionObserver === 'undefined') return undefined;
    const watcher = new IntersectionObserver(
      ([entry]) => {
        if (entry?.isIntersecting) setNear(true);
      },
      { root: root.current, rootMargin: `${NEAR_PX}px` },
    );
    watcher.observe(me);
    return () => watcher.disconnect();
  }, [near, root]);
  return (
    <div ref={el} className={className ? `${styles.near} ${className}` : styles.near}>
      {near ? children : null}
    </div>
  );
}

function noop(): void {
  // Read-only: nothing typed comes back.
}
