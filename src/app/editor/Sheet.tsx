import { useRef, type ReactNode } from 'react';
import { useBack } from '../core/back.ts';
import { useSheetDrag } from './sheetDrag.ts';
import sheet from './NoteSettings.module.css';

/**
 * A sheet from the bottom over the dimmed page, where a thumb already is: the one shell every bottom sheet shares.
 *
 * A fixed scrim that closes the sheet on a tap; the panel, a dialog that keeps its own taps; a grip along its top
 * that takes a pull down (editor/sheetDrag.ts); and the back gesture, or Escape, closing it before it leaves whatever
 * is under it (core/back.ts). It is mounted only while it is open, and takes the gesture for as long as it is.
 *
 * The look is NoteSettings.module.css, which is the app's sheet stylesheet in all but its name - it began as the
 * note's settings - and the rows inside are plugins/kit.tsx's. The note's More sheet and a linked line's drawer are
 * drawn in this; the other sheets (notes/, book/, canvas/) still write the same shell out by hand.
 */

interface SheetProps {
  /** What the dialog is called, for a screen reader. */
  label: string;
  /** A tap on the scrim, or a pull down on the grip. */
  onClose: () => void;
  /** The back gesture; `onClose` unless the sheet has pages of its own to step back through first. */
  onBack?: () => void;
  /** The panel's own look, on top of the sheet's. */
  className?: string;
  children: ReactNode;
}

export function Sheet({ label, onClose, onBack = onClose, className, children }: SheetProps) {
  const panel = useRef<HTMLElement>(null);
  const drag = useSheetDrag(panel, onClose);
  useBack(true, onBack);
  return (
    <div className={sheet.scrim} onClick={onClose}>
      <section ref={panel} className={className ? `${sheet.sheet} ${className}` : sheet.sheet} role="dialog" aria-modal="true" aria-label={label} onClick={(e) => e.stopPropagation()}>
        <span className={sheet.grip} aria-hidden="true" {...drag} />
        {children}
      </section>
    </div>
  );
}
