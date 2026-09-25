import { useEffect, useRef, type ReactNode } from 'react';
import { useBack } from '../core/back.ts';
import styles from './FloatingCard.module.css';

/**
 * A card that floats over the note, hung from the top bar's icon that opened it: the notes drawer at the left
 * (notes/NotesDrawer.tsx) and the aside at the right (aside/Aside.tsx `AsideCard`; Matt: "the new right hand sidebar
 * doesn't match the floating left sidebar"). The page stays live beside it rather than behind a scrim; the card
 * closes on a tap outside it, on Escape and the phone's back gesture (core/back.ts), and on whatever its contents
 * close it for.
 *
 * The icon that opened it is left to close it (Matt: "I should be able to click the sidebar button again to close the
 * sidebar"). Closed here on the press, the click that followed opened it straight back up. So each card names its own
 * icon, and a press there is not a press outside.
 *
 * Drawn only while it is open: the caller mounts it, and its going is the close.
 */
export function FloatingCard({ side = 'start', label, toggle, onClose, children }: {
  /** Which edge of the window it hangs at: the start for the drawer, the end for the aside. */
  side?: 'start' | 'end';
  /** What a screen reader calls the card. */
  label: string;
  /** A selector for the icon that opened it, which a press outside the card does not count. */
  toggle: string;
  onClose: () => void;
  children: ReactNode;
}) {
  const card = useRef<HTMLDivElement>(null);
  // The phone's back gesture and Escape close the card before they leave the note.
  useBack(true, onClose);
  useEffect(() => {
    const outside = (event: PointerEvent) => {
      if ((event.target as Element).closest?.(toggle)) return;
      if (!card.current?.contains(event.target as Node)) onClose();
    };
    // On the next frame: the press that opened it would otherwise close it again.
    const timer = window.setTimeout(() => document.addEventListener('pointerdown', outside), 0);
    return () => {
      window.clearTimeout(timer);
      document.removeEventListener('pointerdown', outside);
    };
  }, [toggle, onClose]);
  return (
    <div className={styles.over}>
      <div ref={card} className={styles.card} data-side={side === 'end' ? 'end' : undefined} role="dialog" aria-modal="false" aria-label={label}>
        {children}
      </div>
    </div>
  );
}
