import { Book } from '@glacier/icons';
import type { BookPlace } from '../book/book.ts';
import styles from './BookPlaceMark.module.css';

/**
 * A page of a book says which (docs/BOOKS.md): the book's mark and its name, on the note's card (notes/NoteCard.tsx)
 * and on its row in the sidebar (notes/NoteTree.tsx), with the page it is said in full to whoever points at it. One
 * mark for both, so the two places a note is listed cannot come to say it differently.
 */
export function BookPlaceMark({ place }: { place: BookPlace }) {
  return (
    <span className={styles.mark} title={`Page ${place.at + 1} of ${place.title}`}>
      <Book size={12} aria-hidden="true" />
      <span className={styles.name}>{place.title}</span>
    </span>
  );
}
