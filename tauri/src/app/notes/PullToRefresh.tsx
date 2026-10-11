import { useEffect, useRef, useState, type CSSProperties, type RefObject } from 'react';
import { ArrowDown, Check, LoaderCircle } from '@glacier/icons';
import { tickNow, type Approaching } from '../core/detentFeel.ts';
import { fireMicroTick, fireNativeHaptic } from '../core/haptics.ts';
import { armed, PULL_DETENT_PX, PULL_LEAST_MS, PULL_REST_PX, pullIntent, pullOffset } from '../core/pull.ts';
import styles from './PullToRefresh.module.css';

/**
 * Pull a page down from its top to refresh it (docs/DESIGN.md §152; Matt: "add a pull to refresh feature on notes and
 * the home page"). The home page, All notes, and an open note wear it; what a refresh does is theirs (`onRefresh`):
 * a sync, and the notes read again, and on a note its newest words taken into the editor.
 *
 * It is felt the way the swipes are (notes/SwipeRow.tsx): light ticks quicken as the page nears the detent
 * (core/detentFeel.ts), a firm click says it is there, and the lightest says it was backed out of; the refresh done,
 * a light tap. It is shown too: under the top bar, in the gap the page leaves as it comes down, a ring fills round an
 * arrow as the detent nears, the arrow turns once it is armed, the ring spins while the refresh runs, and a tick says
 * it is done. A let-go short of the detent does nothing, and the page goes back up.
 *
 * Only a touch that is plainly a pull is one (core/pull.ts `pullIntent`): down, more than across, from a page already
 * at its top, and at once - a finger that rests first is choosing words in a note. It is the page's scroller's own
 * touches, listened to directly: a pull has to stop the browser's own overscroll, which only a touchmove that is not
 * passive can do. The page's content comes down with the finger (each of the scroller's children, by `translate`, so a
 * transform of their own is left alone), and the scroller's padding stays, so the gap opens under the bar.
 */

type Phase = 'idle' | 'pulling' | 'refreshing' | 'done';

interface PullToRefreshProps {
  /** The page's scroller: its touches are the pull, and its children are what come down. */
  scroller: RefObject<HTMLElement | null>;
  /** The refresh itself; the ring spins until it settles, and at least `PULL_LEAST_MS`. It may fail: the page goes back up either way. */
  onRefresh: () => Promise<unknown>;
  /** Off where the page does not scroll, or while it is showing something a pull should leave alone. */
  enabled?: boolean;
}

const SETTLE = 'translate 240ms var(--glacier-ease-out, ease-out)';

export function PullToRefresh({ scroller, onRefresh, enabled = true }: PullToRefreshProps) {
  const [offset, setOffset] = useState(0);
  const [phase, setPhase] = useState<Phase>('idle');
  // Where the gap opens: the scroller's top, below its padding (the bar), across its middle. Measured as a pull begins.
  const [place, setPlace] = useState<{ top: number; left: number } | null>(null);
  const refresh = useRef(onRefresh);
  refresh.current = onRefresh;

  useEffect(() => {
    const page = scroller.current;
    if (!page || !enabled) return undefined;
    let gesture: { x: number; y: number; at: number; pulling: boolean; armed: boolean; approaching: Approaching } | null = null;
    let busy = false;
    let live = true;
    const timers: number[] = [];

    /** The page's content down by `px`, following the finger or settling to it. */
    const lower = (px: number, settle: boolean) => {
      for (const child of Array.from(page.children) as HTMLElement[]) {
        child.style.transition = settle ? SETTLE : '';
        child.style.translate = px ? `0 ${px}px` : '';
      }
      setOffset(px);
    };

    const start = (event: TouchEvent) => {
      const touch = event.touches[0];
      if (busy || event.touches.length !== 1 || !touch) return;
      gesture = { x: touch.clientX, y: touch.clientY, at: event.timeStamp, pulling: false, armed: false, approaching: { lastTickAt: -Infinity, lastDistance: 0 } };
    };

    const move = (event: TouchEvent) => {
      const touch = event.touches[0];
      if (!gesture || !touch) return;
      const dx = touch.clientX - gesture.x;
      const dy = touch.clientY - gesture.y;
      if (!gesture.pulling) {
        const intent = pullIntent(dx, dy, page.scrollTop <= 0, event.timeStamp - gesture.at);
        if (intent === 'undecided') return;
        if (intent === 'other') {
          gesture = null;
          return;
        }
        gesture.pulling = true;
        const box = page.getBoundingClientRect();
        setPlace({ top: box.top + (parseFloat(getComputedStyle(page).paddingTop) || 0), left: box.left + box.width / 2 });
        setPhase('pulling');
      }
      // The browser's own overscroll (a glow, a bounce) would pull against this one.
      if (event.cancelable) event.preventDefault();
      const px = pullOffset(dy);
      lower(px, false);
      if (tickNow(gesture.approaching, [1], px / PULL_DETENT_PX, event.timeStamp)) fireMicroTick();
      const now = armed(px);
      if (now !== gesture.armed) {
        // Out through the detent a firm click; back through it the lightest, so the two directions feel different.
        fireNativeHaptic(now ? 'medium' : 'selection');
        gesture.armed = now;
      }
    };

    const end = () => {
      const was = gesture;
      gesture = null;
      if (!was?.pulling) return;
      if (!was.armed) {
        lower(0, true);
        setPhase('idle');
        return;
      }
      busy = true;
      setPhase('refreshing');
      lower(PULL_REST_PX, true);
      const least = new Promise((done) => timers.push(window.setTimeout(done, PULL_LEAST_MS)));
      void Promise.allSettled([Promise.resolve().then(() => refresh.current()), least]).then(() => {
        if (!live) return;
        fireNativeHaptic('light');
        setPhase('done');
        timers.push(
          window.setTimeout(() => {
            lower(0, true);
            setPhase('idle');
            busy = false;
          }, 350),
        );
      });
    };

    page.addEventListener('touchstart', start, { passive: true });
    page.addEventListener('touchmove', move, { passive: false });
    page.addEventListener('touchend', end);
    page.addEventListener('touchcancel', end);
    return () => {
      live = false;
      for (const timer of timers) window.clearTimeout(timer);
      page.removeEventListener('touchstart', start);
      page.removeEventListener('touchmove', move);
      page.removeEventListener('touchend', end);
      page.removeEventListener('touchcancel', end);
      for (const child of Array.from(page.children) as HTMLElement[]) {
        child.style.translate = '';
        child.style.transition = '';
      }
    };
  }, [scroller, enabled]);

  const shown = phase !== 'idle' && place !== null;
  const progress = Math.min(1, offset / PULL_DETENT_PX);
  return (
    <div
      className={styles.pull}
      data-phase={phase}
      data-armed={armed(offset) || undefined}
      hidden={!shown}
      style={shown ? ({ top: `${place.top + offset / 2}px`, left: `${place.left}px`, '--progress': progress } as CSSProperties) : undefined}
      role="status"
    >
      <svg viewBox="0 0 40 40" className={styles.ring} aria-hidden="true">
        <circle cx="20" cy="20" r="18" pathLength={1} />
      </svg>
      {phase === 'refreshing' ? (
        <LoaderCircle size={18} strokeWidth={2.4} className={styles.spin} aria-hidden="true" />
      ) : phase === 'done' ? (
        <Check size={18} strokeWidth={2.6} aria-hidden="true" />
      ) : (
        <ArrowDown size={18} strokeWidth={2.4} className={styles.arrow} aria-hidden="true" />
      )}
      <span className="app-unseen">{phase === 'refreshing' ? 'Refreshing' : phase === 'done' ? 'Up to date' : armed(offset) ? 'Let go to refresh' : ''}</span>
    </div>
  );
}
