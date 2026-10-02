import { useEffect, useRef, useState, type CSSProperties, type PointerEvent as ReactPointerEvent } from 'react';
import { HOLD_MS } from '../core/gestures.ts';
import { holdDrag, liftGhost, type Ghost } from '../core/holdDrag.ts';

/**
 * Rows dragged into a new order, by their grip (Matt: "drag to reorder pages"), by the app's one drag
 * (core/holdDrag.ts; Matt: "the same mechanism as clicking and dragging on board view"): press and hold the grip, a
 * mouse as much as a finger, and the row lifts - a copy of it in the air under the pointer, the row itself the gap it
 * would leave, standing where it would land while the others make room. On release, the row's new place is handed
 * back as an index. The rows' own arrow buttons stay for the keyboard.
 */

/** How long a press holds before a row lifts (core/gestures.ts), passed on for the rows' tests. */
export const ROW_HOLD_MS = HOLD_MS;

export interface RowDrag {
  /** The row being dragged. */
  lifted: { index: number } | null;
  /** Where it would land now. */
  over: number | null;
  /** The grip's handlers, for row `index`. */
  grip: (index: number) => {
    onPointerDown: (event: ReactPointerEvent<HTMLElement>) => void;
    style: CSSProperties;
  };
  /** The row's own style: the gap standing where it would land, or shifted to make room for it. */
  rowStyle: (index: number) => CSSProperties | undefined;
}

/**
 * `rows` are the rows' elements in order, read when a drag starts; `onMove(from, to)` is called on release with a
 * changed place.
 */
export function useRowDrag(rows: () => (HTMLElement | null)[], onMove: (from: number, to: number) => void): RowDrag {
  const [lifted, setLifted] = useState<{ index: number } | null>(null);
  const [over, setOver] = useState<number | null>(null);
  const height = useRef(40);
  const latest = useRef(onMove);
  latest.current = onMove;
  // How to give up a drag in flight, for rows taken off the page in the middle of one.
  const abandon = useRef<(() => void) | null>(null);
  useEffect(() => () => abandon.current?.(), []);

  const grip = (index: number) => ({
    onPointerDown: (event: ReactPointerEvent<HTMLElement>) => {
      const row = rows()[index];
      if (!row) return;
      // The grip answers its own press and hold: not the page's long-press menu, nor a row's own press.
      event.stopPropagation();
      let ghost: Ghost | null = null;
      let tops: number[] = [];
      let startY = event.clientY;
      let to = index;
      const putDown = () => {
        ghost?.remove();
        ghost = null;
        delete document.documentElement.dataset.dragging;
        abandon.current = null;
        setLifted(null);
        setOver(null);
      };
      // The first row whose middle is above the lifted row's middle, where it is now.
      const landing = (y: number) => {
        const middle = tops[index]! + height.current / 2 + (y - startY);
        let at = 0;
        for (let i = 0; i < tops.length; i += 1) if (tops[i]! + height.current / 2 < middle) at = i;
        return at;
      };
      const finish = holdDrag(event.nativeEvent, {
        lift: (x, y) => {
          const els = rows();
          tops = els.map((el) => el?.getBoundingClientRect().top ?? 0);
          height.current = row.getBoundingClientRect().height || 40;
          startY = y;
          ghost = liftGhost(row, x, y);
          document.documentElement.dataset.dragging = '';
          setLifted({ index });
          setOver(index);
        },
        move: (x, y) => {
          ghost?.follow(x, y);
          to = landing(y);
          setOver(to);
        },
        drop: () => {
          putDown();
          if (to !== index) latest.current(index, to);
        },
        end: (wasLifted) => {
          if (wasLifted) putDown();
        },
      });
      abandon.current = () => {
        finish();
        putDown();
      };
    },
    style: { touchAction: 'none' } as CSSProperties,
  });

  const rowStyle = (index: number): CSSProperties | undefined => {
    if (!lifted || over === null) return undefined;
    const step = height.current;
    // The gap stands where the row would land; the rows between make room for it.
    if (index === lifted.index) return { transform: `translateY(${(over - lifted.index) * step}px)`, position: 'relative', zIndex: 1 };
    if (lifted.index < over && index > lifted.index && index <= over) return { transform: `translateY(${-step}px)`, transition: 'transform 120ms' };
    if (lifted.index > over && index >= over && index < lifted.index) return { transform: `translateY(${step}px)`, transition: 'transform 120ms' };
    return undefined;
  };

  return { lifted, over, grip, rowStyle };
}
