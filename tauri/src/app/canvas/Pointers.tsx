import type { CSSProperties } from 'react';
import type { Other } from './useTeamCanvas.ts';
import styles from './CanvasView.module.css';

/**
 * The other members' pointers on a team's canvas (docs/SHARED.md, S9): a small arrow in each member's colour with
 * their handle beside it, at the pointer's place in the canvas's own pixels and scaled back by the view's scale, so
 * it is the same size on the screen at any zoom. Drawn in the world, over the cards, and taking no taps.
 */
export function Pointers({ others, scale }: { others: readonly Other[]; scale: number }) {
  const shown = others.filter((other) => other.pointer);
  if (shown.length === 0) return null;
  return (
    <div className={styles.pointers} aria-hidden="true">
      {shown.map((other) => (
        <div key={other.client} className={styles.pointer} data-handle={other.name} style={{ left: other.pointer!.x, top: other.pointer!.y, transform: `scale(${1 / scale})`, '--pointer': other.color } as CSSProperties}>
          <svg className={styles.pointerArrow} viewBox="0 0 16 16" width="16" height="16">
            <path d="M1.5 1 L14.5 7.5 L8.5 9.2 L5.2 15 Z" />
          </svg>
          <span className={styles.pointerName}>{other.name}</span>
        </div>
      ))}
    </div>
  );
}
