import { useEffect, useRef, useState, type ReactNode, type RefObject } from 'react';
import styles from './CanvasView.module.css';

/**
 * What a card draws once it is near the screen, and a blank until then (canvas/Card.tsx): an editor costs a frame and
 * a blank nothing, and a canvas may hold fifty cards. Near is measured against the canvas with room to spare, so the
 * words are there before the card comes into view. A page that cannot watch the screen (no IntersectionObserver)
 * draws everything at once, as it would have without this.
 */

/** How far off the screen a card's editor is made, in screen pixels. */
const NEAR_PX = 300;

export function Near({ root, className, children }: { root: RefObject<HTMLDivElement | null>; className?: string; children: ReactNode }) {
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
