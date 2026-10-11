import { Workflow } from '@glacier/icons';
import styles from './CanvasMark.module.css';

/**
 * The canvas's mark, beside a title that is a canvas: the one the + sheet gives a canvas, so a book reads as the
 * pages and the boards of cards it is made of. Drawn by the book's index and reading straight through
 * (book/BookView.tsx), and by the New book sheet's pages and the notes it offers (book/NewBookSheet.tsx).
 */
export function CanvasMark() {
  return (
    <span className={styles.canvasMark} title="A canvas">
      <Workflow size={13} strokeWidth={2.2} aria-hidden="true" />
    </span>
  );
}
