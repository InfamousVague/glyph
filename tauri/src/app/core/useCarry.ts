import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react';
import { edgeRoller, holdDrag, liftGhost, type Ghost } from './holdDrag.ts';

/**
 * A thing carried in a React list by the app's one drag (core/holdDrag.ts): a query's board cards and grouped rows
 * (editor/QueryView.tsx) and a notebook's pages (book/rowDrag.ts). The hook holds what is carried and where it would
 * land; the list draws the thing as the gap it leaves (`[data-drag-gap]`, app.css) at that place, and the copy in the
 * air is the gesture's.
 *
 * A place is a lane and an index in it: a lane is a group of a board or a list (its key), or '' for a list of one, and
 * the index is where among its things it would go - or -1 in a lane whose order is not the person's to set (a query's,
 * sorted by its `sort:`), where only the lane counts.
 */

export interface Spot {
  lane: string;
  index: number;
}

export interface Carried<T> {
  item: T;
  from: Spot;
  /** The thing's height, for the gap it leaves where it would land. */
  height: number;
}

export interface CarryOptions<T> {
  /** Where a thing held at (x, y) would land; null where nothing would take it (it keeps the last place). */
  spotAt: (x: number, y: number) => Spot | null;
  /** Let go somewhere else than it came from. */
  onDrop: (item: T, from: Spot, to: Spot) => void;
  /** What rolls along when the thing is held near its edges. */
  scrollers?: () => { element: HTMLElement; axis: 'x' | 'y' }[];
}

export interface Carry<T> {
  carried: Carried<T> | null;
  over: Spot | null;
  /** The thing's pointerdown, once it has decided the press is its own and not one of its controls'. */
  press: (event: ReactPointerEvent<HTMLElement>, item: T, from: Spot) => void;
}

export const sameSpot = (a: Spot | null, b: Spot | null): boolean => !!a && !!b && a.lane === b.lane && a.index === b.index;

export function useCarry<T>({ spotAt, onDrop, scrollers }: CarryOptions<T>): Carry<T> {
  const [carried, setCarried] = useState<Carried<T> | null>(null);
  const [over, setOver] = useState<Spot | null>(null);
  // The latest options, for a gesture that outlives the render it started in.
  const options = useRef({ spotAt, onDrop, scrollers });
  options.current = { spotAt, onDrop, scrollers };
  // How to give up a carry in flight, for a list taken off the page in the middle of one.
  const abandon = useRef<(() => void) | null>(null);
  useEffect(() => () => abandon.current?.(), []);

  const press = (event: ReactPointerEvent<HTMLElement>, item: T, from: Spot) => {
    const element = event.currentTarget;
    let ghost: Ghost | null = null;
    let rollers: ReturnType<typeof edgeRoller>[] = [];
    let target: Spot = from;
    let at = { x: event.clientX, y: event.clientY };
    const place = () => {
      const spot = options.current.spotAt(at.x, at.y);
      if (spot && !sameSpot(spot, target)) {
        target = spot;
        setOver(spot);
      }
    };
    const putDown = () => {
      ghost?.remove();
      ghost = null;
      for (const roller of rollers) roller.stop();
      rollers = [];
      delete document.documentElement.dataset.dragging;
      abandon.current = null;
      setCarried(null);
      setOver(null);
    };
    const finish = holdDrag(event.nativeEvent, {
      lift: (x, y) => {
        ghost = liftGhost(element, x, y);
        document.documentElement.dataset.dragging = '';
        setCarried({ item, from, height: element.getBoundingClientRect().height });
        setOver(from);
        rollers = (options.current.scrollers?.() ?? []).map(({ element: scroller, axis }) => edgeRoller(scroller, axis, place));
      },
      move: (x, y) => {
        at = { x, y };
        ghost?.follow(x, y);
        place();
        for (const roller of rollers) roller.at(x, y);
      },
      drop: () => {
        const to = target;
        putDown();
        if (!sameSpot(to, from)) options.current.onDrop(item, from, to);
      },
      end: (lifted) => {
        if (lifted) putDown();
      },
    });
    abandon.current = () => {
      finish();
      putDown();
    };
  };

  return { carried, over, press };
}
