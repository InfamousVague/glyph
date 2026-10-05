import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent, type RefObject } from 'react';
import { HOLD_MS } from '../core/gestures.ts';
import { fireFelt } from '../core/haptics.ts';
import type { Camera } from './camera.ts';
import { atDot, movedWithHeld } from './edits.ts';
import type { Canvas, CanvasNode } from './jsonCanvas.ts';
import { clampScale, type View } from './viewport.ts';

/**
 * The fingers on a canvas (canvas/CanvasView.tsx): a press is a tap until it moves, one finger that moves pans, two
 * pinch, and a press held still on a card lifts it to be carried.
 *
 * Nothing is captured until a press has become a drag, so a tap still reaches the card it landed on. The point of
 * the canvas under the fingers stays under them, whatever they do: a second finger's spread scales about that point,
 * and one finger's move carries it along; every move is measured from where the fingers took hold, not from the last
 * move. A press held `HOLD_MS` on a card, on a canvas that can change, lifts it - the way a board's card and a tab
 * are moved (editor/boards.ts, notes/NoteTabs.tsx), so one habit serves the whole app - and a finger that moved
 * first was panning, so a card never moves by mistake. A carried card, and a group with everything wholly inside it,
 * follows the finger in the canvas's own pixels from the canvas as it was at the hold, and is put down where the
 * finger lets go.
 *
 * Some presses need no hold (Matt: "navigating it and resizing things are not easy especially on mobile"). A mouse
 * that drags a card moves it, as every canvas on a desktop does, and the page is panned from the open ground between
 * cards, by the wheel, with Space held or with the middle button. A finger that drags the card already picked moves
 * it; any other card under a moving finger is still the page being panned, since a phone's screen is mostly cards. A
 * group is taken by its name or by its border, with either: its ground is the page's, to pan and to double-tap a new
 * card onto, and a group the size of the screen would otherwise leave nowhere to pan from.
 *
 * With snapping on (the preference `canvasSnap`), a carried card goes from dot to dot of the grid rather than pixel
 * to pixel, and the phone ticks each time it lands on a new one (Matt: "Give haptics when it snaps"): the tick is the
 * hand's proof the card is on the grid, where the eye has only a dot under a corner. Ticks come through the app's
 * floor on haptics (core/haptics.ts `fireFelt`), so a fast drag across many dots is a purr, not a queue.
 */

/** How far a finger moves before a press is a drag rather than a tap, in screen pixels. */
const SLOP_PX = 4;
/** How near a group's edge a press is on its border, in screen pixels: a finger's reach, not a hairline's. */
const BORDER_PX = 14;
/**
 * How long a press stays put before it lifts the card under it rather than panning the page: the boards' own wait
 * (core/gestures.ts). Passed on for the canvas's tests, which wait it out.
 */
export { HOLD_MS };

type Pointers = Map<number, { x: number; y: number }>;

/** Where two fingers are, as one point between them and the distance apart; one finger is its point and no distance. */
function grip(pointers: Pointers): { x: number; y: number; distance: number } {
  const [a, b] = [...pointers.values()];
  if (!a) return { x: 0, y: 0, distance: 0 };
  if (!b) return { x: a.x, y: a.y, distance: 0 };
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, distance: Math.hypot(a.x - b.x, a.y - b.y) };
}

interface GestureOptions {
  host: RefObject<HTMLDivElement | null>;
  camera: Camera;
  /** The canvas as it is drawn now: a held card is found in it, and carried from it. */
  live: Canvas;
  /** Whether a held press may lift a card: the canvas can change. */
  editable: boolean;
  /** Whether a card is open: a press inside it is its editor's, for the caret and the selection. */
  editing: boolean;
  /** The card picked, by id: a finger that drags it moves it without the hold. */
  selected: string | null;
  /** Whether a carried card lands on the grid's dots. */
  snap: boolean;
  /** Any press on the canvas itself, before it is anything else. */
  onPress: () => void;
  /** A carried card moved: the canvas with it where the finger is, drawn but not yet handed on. */
  onCarry: (next: Canvas) => void;
  /** A carried card let go: the canvas with it where it was put down, which card it was, and whether it moved at all. */
  onPutDown: (next: Canvas, id: string, moved: boolean) => void;
}

export interface Gestures {
  onPointerDown: (event: ReactPointerEvent<HTMLDivElement>) => void;
  onPointerMove: (event: ReactPointerEvent<HTMLDivElement>) => void;
  /** Also the answer to a cancelled pointer. */
  onPointerUp: (event: ReactPointerEvent<HTMLDivElement>) => void;
  /** Whether the press now ending became a drag: the tap that would follow it is not one, and no card opens. */
  dragged: RefObject<boolean>;
  /** The card lifted, by id, for its look while it is carried. */
  lifted: string | null;
}

/** Whether a press on a group is on what it is taken by: its name, or its border. */
function onGroupGrip(target: HTMLElement, el: HTMLElement, x: number, y: number): boolean {
  if (target.closest('[data-group-grip]')) return true;
  const box = el.getBoundingClientRect();
  return x - box.left < BORDER_PX || box.right - x < BORDER_PX || y - box.top < BORDER_PX || box.bottom - y < BORDER_PX;
}

export function useGestures({ host, camera, live, editable, editing, selected, snap, onPress, onCarry, onPutDown }: GestureOptions): Gestures {
  const pointers = useRef<Pointers>(new Map());
  /** Where the fingers took hold and what the view was then: every move is measured from here, not from the last. */
  const hold = useRef<{ view: View; x: number; y: number; distance: number } | null>(null);
  const dragged = useRef(false);
  /** The card a held press lifted, where the press was, and the canvas as it was then: the move is measured from there. */
  const carrying = useRef<{ node: CanvasNode; x: number; y: number; base: Canvas } | null>(null);
  /** The card this press would move if it turned into a drag, with no hold: a mouse's, or the picked card under a finger. */
  const grab = useRef<{ node: CanvasNode; x: number; y: number; base: Canvas } | null>(null);
  /** The dot a carried card last landed on, so a tick is felt when it lands on another; null until it has landed on one. */
  const landed = useRef<string | null>(null);
  /** The wait for a press on a card to become a hold; cleared by movement or by letting go. */
  const holdTimer = useRef(0);
  /** Space held: every drag pans, whatever is under the pointer, as in every drawing program. */
  const spaceHeld = useRef(false);
  useEffect(() => {
    const typing = (event: KeyboardEvent) => event.target instanceof Element && !!event.target.closest('input, textarea, [contenteditable]');
    const down = (event: KeyboardEvent) => {
      if (event.code === 'Space' && !typing(event)) spaceHeld.current = true;
    };
    const up = (event: KeyboardEvent) => {
      if (event.code === 'Space') spaceHeld.current = false;
    };
    window.addEventListener('keydown', down);
    window.addEventListener('keyup', up);
    return () => {
      window.removeEventListener('keydown', down);
      window.removeEventListener('keyup', up);
    };
  }, []);
  const [lifted, setLifted] = useState<string | null>(null);

  const takeHold = () => {
    const at = grip(pointers.current);
    hold.current = { view: { ...camera.view.current }, x: at.x, y: at.y, distance: at.distance };
  };

  /** The carried card moved by what the finger has moved since the hold, in the canvas's own pixels. */
  const carried = (to: { clientX: number; clientY: number }): Canvas | null => {
    const held = carrying.current;
    if (!held) return null;
    const scale = camera.view.current.scale;
    const x = held.node.x + (to.clientX - held.x) / scale;
    const y = held.node.y + (to.clientY - held.y) / scale;
    if (!snap) return movedWithHeld(held.base, held.node, x, y);
    // On the grid: the card's corner at the nearest dot, and a tick when that is a new one.
    const dot = atDot(x, y);
    const key = `${dot.x},${dot.y}`;
    if (landed.current !== key) {
      if (landed.current !== null) fireFelt('selection');
      landed.current = key;
    }
    return movedWithHeld(held.base, held.node, dot.x, dot.y);
  };

  const onPointerDown = (event: ReactPointerEvent<HTMLDivElement>) => {
    const target = event.target as HTMLElement;
    // Typing in a card that is open: the press is the editor's, for its caret and its selection.
    if (editing && target.closest('[data-editing]')) return;
    onPress();
    // A press is a tap until it moves: a tap on a card that opens something is the card's, and taking the pointer
    // here would take its click with it. It is only captured once it has become a drag.
    window.clearTimeout(holdTimer.current);
    if (!pointers.current.size) {
      dragged.current = false;
      carrying.current = null;
      grab.current = null;
      landed.current = null;
      // The middle button and Space pan, whatever is under the pointer.
      const panning = event.button === 1 || spaceHeld.current;
      // One finger on a card, on a canvas that can change: held still for a moment, it lifts the card.
      const el = editable && !panning ? target.closest<HTMLElement>('[data-card]') : null;
      const id = el?.dataset.card;
      const node = id ? live.nodes.find((n) => n.id === id) : undefined;
      if (node && el) {
        // And some are moved by the drag itself, with no hold (see the header).
        const taken = node.type === 'group' ? onGroupGrip(target, el, event.clientX, event.clientY) : event.pointerType === 'mouse' || node.id === selected;
        // The main button only: a right-click is a menu's, not a drag.
        if (taken && event.button <= 0) grab.current = { node, x: event.clientX, y: event.clientY, base: live };
        const at = { x: event.clientX, y: event.clientY };
        const pointerId = event.pointerId;
        holdTimer.current = window.setTimeout(() => {
          if (pointers.current.size !== 1 || !pointers.current.has(pointerId)) return;
          carrying.current = { node, x: at.x, y: at.y, base: live };
          dragged.current = true;
          setLifted(node.id);
          try {
            host.current?.setPointerCapture(pointerId);
          } catch {
            // Already gone: nothing to hold.
          }
        }, HOLD_MS);
      }
    } else {
      // A second finger: the two pan and pinch the page, and nothing is carried.
      carrying.current = null;
      grab.current = null;
      setLifted(null);
    }
    pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
    takeHold();
  };

  const onPointerMove = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (!pointers.current.has(event.pointerId) || !hold.current) return;
    pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
    const start = hold.current;
    const now = grip(pointers.current);
    if (!dragged.current) {
      if (pointers.current.size < 2 && Math.hypot(now.x - start.x, now.y - start.y) < SLOP_PX) return;
      // Moved before the hold: a pan, and the card stays where it is - unless this press takes its card with it.
      window.clearTimeout(holdTimer.current);
      dragged.current = true;
      if (grab.current && pointers.current.size < 2) {
        carrying.current = grab.current;
        setLifted(grab.current.node.id);
      }
      grab.current = null;
      // The drag is the page's now, wherever the pointer goes: off a card, out of the window and back.
      for (const id of pointers.current.keys()) {
        try {
          host.current?.setPointerCapture(id);
        } catch {
          // A pointer already gone: nothing to hold.
        }
      }
    }
    // A card being carried: it follows the finger in the canvas's own pixels, and the page stays put.
    const next = pointers.current.size < 2 ? carried(event) : null;
    if (next) {
      onCarry(next);
      return;
    }
    // The point of the canvas that was under the fingers stays under them, whatever they do: a second finger's
    // spread scales about that point, and one finger's move carries it along.
    const scale = start.distance > 0 && now.distance > 0 ? clampScale((start.view.scale * now.distance) / start.distance) : start.view.scale;
    const underX = (start.x - start.view.x) / start.view.scale;
    const underY = (start.y - start.view.y) / start.view.scale;
    camera.moveTo({ x: now.x - underX * scale, y: now.y - underY * scale, scale });
  };

  const onPointerUp = (event: ReactPointerEvent<HTMLDivElement>) => {
    window.clearTimeout(holdTimer.current);
    if (!pointers.current.delete(event.pointerId)) return;
    // A card let go where it was carried to: the canvas is handed on with it there.
    const next = carried(event);
    grab.current = null;
    if (next) {
      const held = carrying.current!;
      carrying.current = null;
      setLifted(null);
      onPutDown(next, held.node.id, event.clientX !== held.x || event.clientY !== held.y);
    }
    if (pointers.current.size) takeHold();
    else hold.current = null;
  };

  return { onPointerDown, onPointerMove, onPointerUp, dragged, lifted };
}
