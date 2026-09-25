import { useRef, type Dispatch, type MouseEvent as ReactMouseEvent, type PointerEvent as ReactPointerEvent, type RefObject, type SetStateAction } from 'react';
import { HOLD_MS } from '../core/gestures.ts';
import { coasted, groupAt, placeAt, type DropSpot, type RowStop } from './tabDrag.ts';
import { joinGroup, leaveGroup, type TabGroups } from './tabGroups.ts';

/**
 * A finger or a mouse on the tab row (notes/NoteTabs.tsx): pressed and held, a tab is picked up and carried along the
 * row, into a group or out of one; pulled sideways first, the row pans, and a flick carries on and slows to a stop;
 * held on a phone and let go where it was, the tab's menu opens. notes/tabDrag.ts works out the places from the
 * boxes; this measures them and follows the gesture.
 *
 * Dragging a tab along the row (Matt: "Add dragging around tabs into different positions"): the row reorders under
 * the finger rather than a ghost following it. The tab being dragged is the tab in the row, and it swaps with a
 * neighbour the moment the pointer passes that neighbour's middle.
 *
 * The drag is followed on the WINDOW rather than on the tab, and deliberately: reordering moves the tab's own element
 * in the DOM, which drops a pointer capture held on it. Held that way, a drag lost its end - no pointerup ever arrived
 * at the tab - and every later tap was swallowed as "the click that ends a drag". The window sees the whole gesture
 * whatever React does to the row underneath.
 *
 * One rule for a finger and a mouse alike: press and HOLD to pick a tab up (Matt: "the clicking and dragging is eating
 * me moving the tabs - the tabs should only move when I press and hold"). A mouse used to reorder the moment it had
 * travelled a few pixels, so a click that slid under the hand carried the tab with it. A finger waits for the same
 * reason a phone's home screen waits before it lets you move an icon: the row scrolls sideways, and a flick along it
 * must stay a flick.
 */

/** How far a pointer must travel before a press on a tab is a pull on the row rather than a click. */
const TRAVEL = 6;

export interface TabDragOptions {
  groups: TabGroups;
  /** A tab moved to `to` in the order as drawn; `grouped` says the drag has settled its group already. Absent, no tab moves. */
  onMove?: (id: string, to: number, grouped?: boolean) => void;
  /** Absent, there are no groups to drag into, and no menu for a hold to open. */
  onGroups?: (next: TabGroups) => void;
  /** The tab being carried, while it is: the row marks it, and the outline does not slide from under it. */
  setMoving: Dispatch<SetStateAction<string | null>>;
  /** A finger held on a tab and let go where it was: that tab's menu, as a mouse's right-click opens it. */
  onHeld: (id: string) => void;
  /** Where the tab being read is outlined, put right after the row changes under it (notes/useTabOutline.ts). */
  placeOutline: () => void;
}

export interface TabDrag {
  /** For the row's `onPointerDown`. */
  takeHold: (event: ReactPointerEvent<HTMLDivElement>) => void;
  /** For the row's `onClickCapture`: the click that ends a drag or a pan must not also open a note. */
  swallowClick: (event: ReactMouseEvent) => void;
}

/** The tabs and folded chips in the row, measured, all but the one being dragged (notes/tabDrag.ts `placeAt`). */
function stopsOf(row: HTMLElement, dragging: string): RowStop[] {
  return [...row.querySelectorAll<HTMLElement>('[data-tab], [data-group-chip][data-collapsed]')]
    .filter((item) => item.dataset.tabId !== dragging)
    .map((item) => {
      const box = item.getBoundingClientRect();
      return { left: box.left, width: box.width, tabs: item.dataset.tab === undefined ? Number(item.dataset.count) || 0 : 1 };
    });
}

/** The tabs, chips and the + in the row, measured, all but the one being dragged (notes/tabDrag.ts `groupAt`). */
function spotsOf(row: HTMLElement, dragging: string): DropSpot[] {
  return [...row.querySelectorAll<HTMLElement>('[data-tab], [data-group-chip], [data-new-tab]')]
    .filter((el) => el.dataset.tabId !== dragging)
    .map((el) => {
      const box = el.getBoundingClientRect();
      const group = el.dataset.groupChip || (el.dataset.newTab !== undefined ? null : (el.dataset.groupId ?? null));
      return { left: box.left, right: box.right, group };
    });
}

export function useTabDrag(row: RefObject<HTMLDivElement | null>, { groups, onMove, onGroups, setMoving, onHeld, placeOutline }: TabDragOptions): TabDrag {
  /** A drag ends in a click somewhere in the row, which must not also open a note. */
  const dragged = useRef(false);

  /*
   * A flick along the row keeps going and slows to a stop (Matt: "Scrolling through the tabs doesn't have momentum").
   * The row is panned by hand rather than by the engine - a finger on it may be about to pick a tab up instead - so
   * the pan is spent on `scrollLeft` as the finger moves, and a hand-panned scroller stops dead when the finger lifts,
   * where the engine would have carried it on. So the speed the finger left at is carried on here until it is too
   * slow to see or the row reaches its end (notes/tabDrag.ts `coasted`). A new touch on the row stops it where it is,
   * as a finger stops a scrolling page.
   */
  const coasting = useRef(0);
  const coast = (box: HTMLElement, speed: number) => {
    let last = performance.now();
    let left = box.scrollLeft;
    let pace = speed;
    const step = (now: number) => {
      const next = coasted(left, pace, now - last, box.scrollWidth - box.clientWidth);
      last = now;
      left = next.left;
      pace = next.pace;
      box.scrollLeft = left;
      if (next.done) return;
      coasting.current = requestAnimationFrame(step);
    };
    coasting.current = requestAnimationFrame(step);
  };

  const takeHold = (event: ReactPointerEvent<HTMLDivElement>) => {
    cancelAnimationFrame(coasting.current);
    if (!onMove || (event.pointerType === 'mouse' && event.button !== 0)) return;
    const tab = (event.target as HTMLElement).closest<HTMLElement>('[data-tab]');
    const id = tab?.dataset.tabId;
    if (!id) return;
    // The cross is not a handle: pressing it means close, whatever the finger does next.
    if ((event.target as HTMLElement).closest('[data-close]')) return;

    const from = event.clientX;
    let on = false;
    /** Whether the finger went anywhere once the tab was picked up: a hold that did not is a menu, not a move. */
    let travelled = false;
    /*
     * The groups as they were when the tab was picked up, and the group it is in now. Each move says where it belongs
     * from these, not from the last move's answer: a tab dragged out of a group of one empties it, and an empty group
     * goes, so worked out move by move, passing over the next tab would lose the group for good. From the start, it
     * comes back the moment the tab is back over it. A folded group takes the tab only when it is let go, since
     * joining a folded group hides the tab, and a tab hidden under the finger cannot be carried on.
     */
    const base = groups;
    let joined: string | null = base.of[id] ?? null;
    let dropInto: string | null = null;
    const hold = window.setTimeout(() => {
      on = true;
      setMoving(id);
    }, HOLD_MS);

    // Where along the tab it was taken hold of, so it hangs off the finger at the point it was picked up rather than
    // jumping its middle to the pointer.
    const grabbed = from - tab.getBoundingClientRect().left;

    const follow = (x: number) => {
      const el = row.current?.querySelector<HTMLElement>(`[data-tab-id="${CSS.escape(id)}"]`);
      if (!el) return;
      // Measured with the offset off, since a transform moves the box it would otherwise be measured from.
      el.style.transform = '';
      const home = el.getBoundingClientRect().left;
      el.style.transform = `translateX(${Math.round(x - grabbed - home)}px)`;
      // The tab being read carries its gap in the line along with it.
      placeOutline();
    };

    /*
     * Before the hold fires, a finger going sideways pans the row instead of picking a tab up (Matt: "I should be
     * able to scroll left or right on the tabs to see overflowing ones"). The row keeps `touch-action: pan-y`, so a
     * vertical swipe still scrolls the page natively and the sideways movement arrives here to be spent on
     * scrollLeft. It is the phone's own convention: swipe to move along, press and hold to pick something up.
     */
    let panned = from;
    /** How fast the finger is going along the row, in pixels a millisecond, smoothed so one odd frame cannot throw it. */
    let pace = 0;
    let paced = event.timeStamp;
    const along = (moved: PointerEvent) => {
      // Not held yet: this is a drag across the row, so it moves the row rather than anything in it.
      if (!on) {
        const step = panned - moved.clientX;
        if (Math.abs(moved.clientX - from) >= TRAVEL && row.current) {
          window.clearTimeout(hold);
          row.current.scrollLeft += step;
          const since = moved.timeStamp - paced;
          if (since > 0) {
            pace = pace * 0.7 + (step / since) * 0.3;
            paced = moved.timeStamp;
          }
          panned = moved.clientX;
          // A pan is not a tap: letting go must not open the tab it started on.
          dragged.current = true;
        }
        return;
      }
      dragged.current = true;
      travelled = true;
      const into = row.current ? groupAt(spotsOf(row.current, id), moved.clientX) : undefined;
      dropInto = null;
      if (into !== undefined && into !== joined) {
        const folded = !!into && base.list.find((g) => g.id === into)?.collapsed;
        if (folded) dropInto = into;
        else {
          joined = into;
          onGroups?.(into ? joinGroup(base, id, into) : leaveGroup(base, id));
        }
      }
      onMove(id, row.current ? placeAt(stopsOf(row.current, id), moved.clientX) : 0, true);
      // After the row has been told where the tab belongs, not before: the tab has to follow the finger even between
      // two places (Matt: "moving tabs doesn't look like you're actually moving it, doesn't follow my finger").
      follow(moved.clientX);
    };
    const done = () => {
      window.clearTimeout(hold);
      window.removeEventListener('pointermove', along);
      window.removeEventListener('pointerup', done);
      window.removeEventListener('pointercancel', done);
      // Let go and it settles into its place, rather than snapping there.
      const el = row.current?.querySelector<HTMLElement>(`[data-tab-id="${CSS.escape(id)}"]`);
      if (el) el.style.transform = '';
      // Let go mid-flick: the row carries on at the speed it was going. A tab picked up was not a flick.
      if (!on && row.current && Math.abs(pace) > 0.05) coast(row.current, pace);
      placeOutline();
      if (dropInto) onGroups?.(joinGroup(base, id, dropInto));
      // Held in one place and let go: the menu a mouse gets from a right-click. The tap that ends it must not also
      // open the note, so it is swallowed the way the end of a drag is.
      if (on && !travelled && event.pointerType !== 'mouse' && onGroups) {
        dragged.current = true;
        onHeld(id);
      }
      setMoving(null);
      // The click that ends the drag is swallowed below; this clears the flag even when the gesture ends
      // somewhere that sends no click at all.
      if (dragged.current) window.setTimeout(() => {
        dragged.current = false;
      }, 0);
    };
    window.addEventListener('pointermove', along);
    window.addEventListener('pointerup', done);
    window.addEventListener('pointercancel', done);
  };

  const swallowClick = (event: ReactMouseEvent) => {
    if (!dragged.current) return;
    dragged.current = false;
    event.preventDefault();
    event.stopPropagation();
  };

  return { takeHold, swallowClick };
}
