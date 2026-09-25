import type { CSSProperties } from 'react';
import { LoaderCircle } from '@glacier/icons';
import { noteTitle, type Note } from '../core/store.ts';
import { chaptersOf, isBookBody, type BookPlace } from '../book/book.ts';
import { activeGist } from '../format/gist.ts';
import { hasMarks } from '../ai/marks.ts';
import { shortenUrls } from '../core/shortUrl.ts';
import { ArchiveBox, Pin } from '../art/Icons.tsx';
import { BookPlaceMark } from './BookPlaceMark.tsx';
import { NotePeek } from './NotePeek.tsx';
import { when } from './when.ts';
import styles from './NoteCard.module.css';

/**
 * A note as a card: its title, what it is about when the phone has written that (format/gist.ts), the note itself
 * drawn small (notes/NotePeek.tsx), and when it was last touched. A book's card is its name, how many pages it has and
 * the first few of them (docs/BOOKS.md). The AI at work on the note, or its changes still marked in it, is said in the
 * card's corner.
 *
 * One card for the home page's rows and the All notes grid (home/HomeScreen.tsx, notes/AllNotesScreen.tsx), so a
 * note looks the same wherever it is picked up. The grid draws it `dense`: a step smaller, for a page of many, with
 * its own marks for pinned and archived, since there the cards are not sorted under headings that say so.
 */

export interface NoteCardProps {
  note: Note;
  /** Its place in the run of cards, for the beat it arrives on: the ninth and after arrive together. */
  index: number;
  onOpen: (id: string) => void;
  /** What the note is about in a line (format/gist.ts), when there is one. */
  gist?: string;
  /** The book this note is a page of (book/book.ts `placeOf`), when it is one. */
  place?: BookPlace | null;
  /** A step smaller, with the pin and the archive said on the card itself. */
  dense?: boolean;
}

export function NoteCard({ note, index, onOpen, gist, place, dense = false }: NoteCardProps) {
  const title = noteTitle(note.body);
  const book = isBookBody(note.body);
  const chapters = book ? chaptersOf(note.body) : [];
  return (
    <li key={note.id} className={styles.item} data-dense={dense || undefined} style={{ '--i': Math.min(index, 8) } as CSSProperties}>
      <button type="button" className={styles.card} onClick={() => onOpen(note.id)}>
        <span className={styles.title} data-untitled={title ? undefined : ''}>
          {title ? shortenUrls(title) : book ? 'Untitled book' : 'Untitled'}
        </span>
        {/* The AI at work on this note's line (format/gist.ts), or changes of its own still marked in the note (ai/marks.ts): said in the card's corner. */}
        {activeGist() === note.id ? (
          <LoaderCircle size={14} strokeWidth={2.2} className={styles.working} aria-label="The AI is writing this note's line" />
        ) : hasMarks(note.id) ? (
          <span className={styles.dot} role="img" aria-label="Changes from the AI are marked in this note" />
        ) : null}
        {dense && (note.starred || note.archivedAt) ? (
          <span className={styles.flags}>
            {note.starred ? (
              <span className={styles.flag} role="img" aria-label="Pinned">
                <Pin />
              </span>
            ) : null}
            {note.archivedAt ? (
              <span className={styles.flag} role="img" aria-label="Archived">
                <ArchiveBox />
              </span>
            ) : null}
          </span>
        ) : null}
        {book ? (
          <>
            <span className={styles.bookMeta}>{chapters.length === 0 ? 'No pages yet' : chapters.length === 1 ? '1 page' : `${chapters.length} pages`}</span>
            {chapters.length ? (
              <ol className={styles.bookPages} aria-hidden="true">
                {chapters.slice(0, 4).map((c, n) => (
                  <li key={`${c.line}-${c.title}`} data-depth={c.depth}>
                    <span className={styles.bookPageNumber}>{n + 1}</span>
                    {c.title}
                  </li>
                ))}
                {chapters.length > 4 ? <li className={styles.bookMore}>and {chapters.length - 4} more</li> : null}
              </ol>
            ) : null}
          </>
        ) : (
          <>
            {/* A page of a book says which (docs/BOOKS.md). */}
            {place ? <BookPlaceMark place={place} /> : null}
            {/* What the note is about, when the phone has written it; the preview under it is the note itself. */}
            {gist ? <span className={styles.gist}>{gist}</span> : null}
            <NotePeek body={note.body} className={styles.peek} />
          </>
        )}
        <span className={styles.when}>{when(note.updatedAt)}</span>
      </button>
    </li>
  );
}
