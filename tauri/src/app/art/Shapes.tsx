import type { ReactNode } from 'react';
import styles from './Shapes.module.css';

/**
 * The guide's pictures: abstract shapes in the page's own ink, for its last page (guide/pages/Start.tsx). The empty
 * states that had shapes here before them are the ghost's now (art/Ghost.tsx, docs/GHOSTS.md), and the side key's
 * phone went with its page (docs/DESIGN.md §173); the lid is what is left.
 *
 * Nothing figurative - Matt's direction was "no ink inspiration, they're both
 * black and white markdown notes, maybe abstract shapes". So the motifs are a
 * note's: a box with its lid. Flat, no
 * gradients, drawn on currentColor only, so a page sets their weight with
 * `color` and they invert with the theme. Square, sized by the page, and
 * decoration only: every one is aria-hidden.
 *
 * They move (Shapes.module.css): each one does the thing it stands for, slowly
 * and on a loop with long rests, so a page feels alive without asking to be
 * watched. Only transforms and opacity, so nothing lays out again. With
 * reduced motion they stand still in their finished pose, which is the pose
 * the markup draws.
 *
 * The recorder's own two - sound beginning, a sentence stopping - live with it
 * in capture/Opening.tsx.
 */

interface ShapeProps {
  className?: string;
}

const svg = (className: string | undefined, children: ReactNode, motion?: string) => (
  <svg viewBox="0 0 120 120" className={[styles.shape, motion, className].filter(Boolean).join(' ')} aria-hidden="true">
    {children}
  </svg>
);

/** A lid lifting off a box and settling back: the tips page. */
export function Tips({ className }: ShapeProps) {
  return svg(
    className,
    <>
      <rect x="34" y="58" width="52" height="38" rx="5" fill="currentColor" />
      <rect className={styles.lid} x="30" y="44" width="60" height="10" rx="5" fill="currentColor" />
    </>,
    styles.tips,
  );
}
