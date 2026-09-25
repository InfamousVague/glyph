import { useCallback, useEffect, useRef, useState, type RefObject } from 'react';
import type { Box, Point } from './geometry.ts';
import type { Canvas } from './jsonCanvas.ts';
import { fitted, fittedTo, HOME, zoomedAt, type View } from './viewport.ts';

/**
 * Where the screen is over a canvas, and what moves it (canvas/CanvasView.tsx): the view (viewport.ts), written
 * straight to the world element as a transform and to the page as the three variables the dot grid is drawn from
 * (CanvasView.module.css `.canvas`), so a pan is a style change and nothing re-renders. The view is copied into
 * React state once a frame at most, for what is drawn from it (the minimap).
 *
 * The canvas opens fitted to the screen and follows the screen's size until a hand has moved the view: a finger, a
 * wheel, the minimap or a zoom to a card. A wheel pans, as it does in Obsidian; with ctrl or meta held - which is
 * also what a trackpad pinch arrives as - it zooms about the pointer. The wheel is listened for by hand, not through
 * React, whose wheel listener is passive and cannot keep the page from scrolling instead.
 */
export interface Camera {
  /** The world element the view moves: every card and line is inside it, in the canvas's own pixels. */
  world: RefObject<HTMLDivElement | null>;
  /** The view now. Read it, never write it: `moveTo` writes it and draws it. */
  view: RefObject<View>;
  /** The view as last copied for drawing, a frame behind at most. */
  shown: View;
  /** The whole canvas fitted to the screen, and the view following the screen's size again. */
  fit: () => void;
  /** The view moved by hand to `next`: drawn at once, and no longer refitted when the screen changes size. */
  moveTo: (next: View) => void;
  /** The view fitted to one box of the canvas, no larger than life: zoom to a card. */
  zoomToBox: (box: Box) => void;
  /** The screen centred on this point of the canvas, at the scale it is at: a tap on the minimap. */
  centreOn: (point: Point) => void;
  /** The screen moved this far over the canvas, in the canvas's own pixels: a drag on the minimap. */
  panBy: (dx: number, dy: number) => void;
  /** The point of the canvas under a point of the screen. */
  under: (clientX: number, clientY: number) => Point;
  /** The middle of the screen, in the canvas's pixels. */
  middle: () => Point;
}

export function useCamera(host: RefObject<HTMLDivElement | null>, canvas: Canvas): Camera {
  const world = useRef<HTMLDivElement>(null);
  const view = useRef<View>({ ...HOME });
  /** Whether a finger or a wheel has moved the view: until then, a screen that changes size fits the canvas again. */
  const touched = useRef(false);
  const [shown, setShown] = useState<View>(view.current);
  const frame = useRef(0);

  const apply = useCallback(() => {
    const el = world.current;
    if (!el) return;
    const { x, y, scale } = view.current;
    el.style.transform = `translate(${x}px, ${y}px) scale(${scale})`;
    // The dots under the cards move and scale with them (CanvasView.module.css `.canvas`).
    const page = host.current;
    if (page) {
      page.style.setProperty('--canvas-x', `${x}px`);
      page.style.setProperty('--canvas-y', `${y}px`);
      page.style.setProperty('--canvas-scale', String(scale));
    }
    cancelAnimationFrame(frame.current);
    frame.current = requestAnimationFrame(() => setShown({ ...view.current }));
  }, [host]);

  const fit = useCallback(() => {
    const el = host.current;
    if (!el) return;
    view.current = fitted(canvas, el.clientWidth, el.clientHeight);
    touched.current = false;
    apply();
  }, [host, canvas, apply]);

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
  }, [host, fit]);

  const moveTo = useCallback(
    (next: View) => {
      view.current = next;
      touched.current = true;
      apply();
    },
    [apply],
  );

  // A wheel pans; with the modifier held it zooms about the pointer. Attached by hand: React's wheel is passive.
  useEffect(() => {
    const el = host.current;
    if (!el) return undefined;
    const onWheel = (event: WheelEvent) => {
      event.preventDefault();
      const was = view.current;
      if (event.ctrlKey || event.metaKey) {
        const rect = el.getBoundingClientRect();
        moveTo(zoomedAt(was, event.clientX - rect.left, event.clientY - rect.top, was.scale * Math.exp(-event.deltaY * 0.01)));
      } else {
        moveTo({ ...was, x: was.x - event.deltaX, y: was.y - event.deltaY });
      }
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, [host, moveTo]);

  const zoomToBox = useCallback(
    (box: Box) => {
      const el = host.current;
      if (el) moveTo(fittedTo(box, el.clientWidth, el.clientHeight));
    },
    [host, moveTo],
  );

  const centreOn = ({ x, y }: Point) => {
    const el = host.current;
    if (!el) return;
    const { scale } = view.current;
    moveTo({ x: el.clientWidth / 2 - x * scale, y: el.clientHeight / 2 - y * scale, scale });
  };

  const panBy = (dx: number, dy: number) => {
    const { x, y, scale } = view.current;
    moveTo({ x: x - dx * scale, y: y - dy * scale, scale });
  };

  const under = (clientX: number, clientY: number): Point => {
    const rect = host.current?.getBoundingClientRect();
    const { x, y, scale } = view.current;
    return { x: (clientX - (rect?.left ?? 0) - x) / scale, y: (clientY - (rect?.top ?? 0) - y) / scale };
  };

  const middle = (): Point => {
    const rect = host.current?.getBoundingClientRect();
    return under((rect?.left ?? 0) + (rect?.width ?? 0) / 2, (rect?.top ?? 0) + (rect?.height ?? 0) / 2);
  };

  return { world, view, shown, fit, moveTo, zoomToBox, centreOn, panBy, under, middle };
}
