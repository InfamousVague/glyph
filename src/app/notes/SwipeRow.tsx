import { useCallback, useRef, useState, type ReactNode } from 'react';
import { fireNativeHaptic } from '../core/haptics.ts';
import { ArchiveBox, Bin, Pin, Unarchive } from '../art/Icons.tsx';
import { armedAt, followFinger, startsInGestureEdge, type SwipeAction } from './swipe.ts';
import styles from './SwipeRow.module.css';

/**
 * A row you can swipe: right for one action, left for up to two, each armed at
 * a DETENT you can feel.
 *
 * A detent is a distance, as a fraction of the row's width. Crossing one on the
 * way out ticks the motor and fills the gap behind the row with the action's
 * colour, its picture doing a small move (a pin pressed in, a box dropped, a
 * bin shaken); crossing back ticks more softly and empties it, so a thumb can
 * find Archive and then Delete without looking, and back off either. Letting go past a detent does
 * that action; letting go short of the first does nothing and the row springs
 * home.
 *
 * Horizontal intent is decided once per touch, from the first 10 px of travel:
 * a drag that starts mostly vertical belongs to the list's scroll and this row
 * never moves. `touch-action: pan-y` hands vertical panning to the browser and
 * leaves horizontal to us, which is what keeps a long list scrolling at native
 * speed with swipeable rows in it.
 *
 * The row's own tap still opens the note. A swipe swallows the click that
 * follows its pointerup, so letting go of a swipe never also opens the note.
 *
 * Every detent is SHOWN as well as felt - a ring round the picture fills as the
 * swipe nears it, and the gap turns ink, or red for delete, once it is armed -
 * because a fast fling can cross two detents inside one motor pulse, and a
 * threshold you can only feel is one you can miss.
 */

interface SwipeRowProps {
  children: ReactNode;
  /** Revealed by swiping RIGHT, nearest detent first. */
  start?: SwipeAction[];
  /** Revealed by swiping LEFT, nearest detent first. */
  end?: SwipeAction[];
  onAction: (id: string) => void;
}

const INTENT_PX = 10;

export function SwipeRow({ children, start = [], end = [], onAction }: SwipeRowProps) {
  const rowRef = useRef<HTMLDivElement>(null);
  const [dx, setDx] = useState(0);
  const [settling, setSettling] = useState<'home' | 'away-left' | 'away-right' | null>(null);
  const gesture = useRef<{
    id: number;
    x: number;
    y: number;
    intent: 'undecided' | 'horizontal' | 'vertical';
    width: number;
    armed: string | null;
  } | null>(null);
  const swallowClick = useRef(false);

  const [armed, setArmed] = useState<SwipeAction | null>(null);
  const side = dx > 0 ? start : dx < 0 ? end : [];

  const onPointerDown = useCallback((event: React.PointerEvent) => {
    if (event.pointerType === 'mouse' && event.button !== 0) return;
    if (event.pointerType === 'touch' && startsInGestureEdge(event.clientX, window.innerWidth)) return;
    gesture.current = {
      id: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      intent: 'undecided',
      width: rowRef.current?.offsetWidth ?? 1,
      armed: null,
    };
    setSettling(null);
  }, []);

  const onPointerMove = useCallback(
    (event: React.PointerEvent) => {
      const g = gesture.current;
      if (!g || g.id !== event.pointerId) return;
      const moveX = event.clientX - g.x;
      const moveY = event.clientY - g.y;

      if (g.intent === 'undecided') {
        if (Math.abs(moveX) < INTENT_PX && Math.abs(moveY) < INTENT_PX) return;
        const horizontal = Math.abs(moveX) > Math.abs(moveY) * 1.2 && (moveX > 0 ? start.length : end.length) > 0;
        g.intent = horizontal ? 'horizontal' : 'vertical';
        if (!horizontal) return;
        rowRef.current?.setPointerCapture(event.pointerId);
      }
      if (g.intent !== 'horizontal') return;

      const actions = moveX > 0 ? start : end;
      const shown = actions.length ? followFinger(moveX, actions.at(-1)?.detent ?? 0, g.width) : 0;
      setDx(shown);

      const next = armedAt(actions, Math.abs(shown) / g.width);
      if ((next?.id ?? null) !== g.armed) {
        const deeper = next && (!g.armed || actions.findIndex((a) => a.id === next.id) > actions.findIndex((a) => a.id === g.armed));
        // Out through a detent: a firm click, heavier for a destructive one.
        // Back through it: the lightest tick, so the two directions feel different.
        if (deeper) fireNativeHaptic(next.tone === 'danger' ? 'heavy' : 'medium');
        else fireNativeHaptic('selection');
        g.armed = next?.id ?? null;
        setArmed(next);
      }
    },
    [start, end],
  );

  const finish = useCallback(
    (event: React.PointerEvent, cancelled: boolean) => {
      const g = gesture.current;
      if (!g || g.id !== event.pointerId) return;
      gesture.current = null;
      if (g.intent !== 'horizontal') return;
      swallowClick.current = true;

      const actions = dx > 0 ? start : end;
      const action = cancelled ? null : armedAt(actions, Math.abs(dx) / g.width);
      setArmed(null);
      if (!action) {
        setSettling('home');
        setDx(0);
        return;
      }
      if (action.removes) {
        setSettling(dx > 0 ? 'away-right' : 'away-left');
        setDx(Math.sign(dx) * g.width * 1.1);
        window.setTimeout(() => onAction(action.id), 180);
      } else {
        setSettling('home');
        setDx(0);
        onAction(action.id);
      }
    },
    [dx, start, end, onAction],
  );

  // What shows behind the row: the action the swipe has armed, or the first
  // one it is heading for, with how far there is still to go.
  const width = rowRef.current?.offsetWidth ?? 1;
  const distance = Math.abs(dx) / width;
  const current = armed ?? side[0] ?? null;
  const next = current ? side[side.findIndex((a) => a.id === current.id) + 1] : undefined;
  const progress = current ? Math.min(1, distance / current.detent) : 0;

  return (
    <div className={styles.frame} data-swiping={dx !== 0 ? '' : undefined}>
      {/*
        The gap the row leaves as it slides is the action: its picture in a
        ring that fills as the swipe nears the detent, and its word under it.
        Armed, the ring closes, the picture does its small move, and the gap
        fills: ink for pin and archive, red for delete. A deeper action waits
        its turn; its detent swaps the picture when it is reached.
      */}
      <div
        className={styles.behind}
        data-side={dx > 0 ? 'start' : 'end'}
        data-tone={armed?.tone}
        style={{ inlineSize: `${Math.abs(dx)}px` }}
        aria-hidden="true"
      >
        {current ? (
          <span key={current.id} className={styles.action} data-armed={armed ? '' : undefined} data-icon={current.icon}>
            <span className={styles.badge} style={{ '--progress': progress } as React.CSSProperties}>
              <svg viewBox="0 0 44 44" className={styles.ring}>
                <circle cx="22" cy="22" r="20" pathLength={1} />
              </svg>
              <ActionIcon icon={current.icon} />
            </span>
            <span className={styles.label}>{current.label}</span>
            {armed && next ? <span className={styles.more}>Further to {next.label.toLowerCase()}</span> : null}
          </span>
        ) : null}
      </div>
      <div
        ref={rowRef}
        className={styles.row}
        data-settling={settling ?? undefined}
        data-side={dx > 0 ? 'start' : dx < 0 ? 'end' : undefined}
        style={{ transform: dx ? `translateX(${dx}px)` : undefined }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={(e) => finish(e, false)}
        onPointerCancel={(e) => finish(e, true)}
        onClickCapture={(event) => {
          if (swallowClick.current) {
            swallowClick.current = false;
            event.preventDefault();
            event.stopPropagation();
          }
        }}
      >
        {children}
      </div>
    </div>
  );
}

/** The picture for an action: the app's own strokes, in the colour of the gap it sits in. */
function ActionIcon({ icon }: { icon: SwipeAction['icon'] }) {
  switch (icon) {
    case 'pin':
    case 'unpin':
      return <Pin className={styles.icon} />;
    case 'archive':
      return <ArchiveBox className={styles.icon} />;
    case 'restore':
      return <Unarchive className={styles.icon} />;
    default:
      return <Bin className={styles.icon} />;
  }
}
