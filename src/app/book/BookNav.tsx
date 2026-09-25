import { BookOpen, ChevronLeft, ChevronRight } from '@glacier/icons';
import type { BookPlace } from './book.ts';
import styles from './BookNav.module.css';

/**
 * A chapter's way round the book it is in (editor/NoteScreen.tsx, src/read/Reader.tsx): the bar under the note's
 * header, and the foot under its last line. Both read the chapters either side from one `sides`, so the two can never
 * disagree (docs/DESIGN.md §87), and both open a neighbour through `open`, which the note screen points at the book's
 * one tab (§77).
 */

/** The chapters either side of this one: null at either end. */
function sides(place: BookPlace): { prev: string | null; next: string | null } {
  return {
    prev: place.at > 0 ? place.chapters[place.at - 1]!.title : null,
    next: place.at < place.chapters.length - 1 ? place.chapters[place.at + 1]!.title : null,
  };
}

/**
 * The bar a chapter wears under its header: the book it is in, its place in it, and the chapters either side
 * (`bookOf` in book/book.ts finds them). A tap on the book opens the index; the ends open the neighbours.
 */
export function BookBar({ place, open }: { place: BookPlace; open: (title: string) => void }) {
  const { prev, next } = sides(place);
  return (
    <nav className={styles.bar} aria-label="Book">
      <button type="button" className={styles.end} disabled={!prev} onClick={() => prev && open(prev)} aria-label={prev ? `Previous chapter: ${prev}` : 'First chapter'}>
        <ChevronLeft size={16} aria-hidden="true" />
        <span className={styles.endTitle}>{prev ?? ''}</span>
      </button>
      <button type="button" className={styles.middle} onClick={() => open(place.title)} aria-label={`Open the book ${place.title}`}>
        <BookOpen size={15} aria-hidden="true" />
        <span className={styles.bookTitle}>{place.title}</span>
        <span className={styles.count}>
          {place.at + 1} of {place.chapters.length}
        </span>
      </button>
      <button type="button" className={styles.end} data-next="" disabled={!next} onClick={() => next && open(next)} aria-label={next ? `Next chapter: ${next}` : 'Last chapter'}>
        <span className={styles.endTitle}>{next ?? ''}</span>
        <ChevronRight size={16} aria-hidden="true" />
      </button>
    </nav>
  );
}

/**
 * The foot a chapter wears (Matt: "add the book navigation for next and prev buttons at the bottom of the page"): the
 * chapters either side, as two wide buttons under the last line, so a reader who reaches the end of a page goes on
 * from there rather than scrolling back up to the bar. At the first chapter there is only Next, at the last only
 * Previous, and a book of one chapter has no foot.
 */
export function BookFoot({ place, open }: { place: BookPlace; open: (title: string) => void }) {
  const { prev, next } = sides(place);
  if (!prev && !next) return null;
  return (
    <nav className={styles.foot} aria-label="Previous and next chapter" data-book-foot="">
      {prev ? (
        <button type="button" className={styles.step} onClick={() => open(prev)} aria-label={`Previous: ${prev}`}>
          <span className={styles.stepLabel}>
            <ChevronLeft size={14} aria-hidden="true" />
            Previous
          </span>
          <span className={styles.stepTitle}>{prev}</span>
        </button>
      ) : null}
      {next ? (
        <button type="button" className={styles.step} data-next="" onClick={() => open(next)} aria-label={`Next: ${next}`}>
          <span className={styles.stepLabel}>
            Next
            <ChevronRight size={14} aria-hidden="true" />
          </span>
          <span className={styles.stepTitle}>{next}</span>
        </button>
      ) : null}
    </nav>
  );
}
