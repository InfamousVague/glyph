import type { CSSProperties, ReactNode } from 'react';
import { LoaderCircle } from '@glacier/icons';
import { noteTitle, type Note } from '../core/store.ts';
import { geoTagOf } from '../core/geotag.ts';
import { counter } from '../capture/tape.ts';
import { hasTape } from './allNotes.ts';
import { chaptersOf, isBookBody, isJournalBody, type BookPlace } from '../book/book.ts';
import type { JournalCard } from '../book/journalMonths.ts';
import { activeGist } from '../format/gist.ts';
import { hasMarks } from '../ai/marks.ts';
import { shortenUrls } from '../core/shortUrl.ts';
import { ArchiveBox, Pin } from '../art/Icons.tsx';
import { BookPlaceMark } from './BookPlaceMark.tsx';
import { TicketMark } from './TicketMark.tsx';
import { NotePeek } from './NotePeek.tsx';
import { SwipeRow } from './SwipeRow.tsx';
import type { SwipeAction } from './swipe.ts';
import { when } from './when.ts';
import styles from './NoteCard.module.css';

/**
 * A note as a card: its title, what it is about when the phone has written that (format/gist.ts), the note itself
 * drawn small (notes/NotePeek.tsx), and when it was last touched. A book's card is its name, how many pages it has and
 * the first few of them (docs/BOOKS.md); a journal's, how many entries and the newest few by when each was written
 * (docs/DESIGN.md §142). The AI at work on the note, or its changes still marked in it, is said in the
 * card's corner.
 *
 * One card for the home page's rows and the All notes grid (home/HomeScreen.tsx, notes/AllNotesScreen.tsx), so a
 * note looks the same wherever it is picked up. The grid draws it `dense`: a step smaller, for a page of many, with
 * its own marks for pinned and archived, since there the cards are not sorted under headings that say so.
 *
 * A note with a tape wears the tape's counter in its foot, "12:40 · Yesterday", in figures and with no icon. A note
 * the recorder made is a cassette on the home page's shelf (home/TapeShelf.tsx); a note that was written and then
 * talked into keeps its card, and the counter is how it is told from a typed one (docs/DESIGN.md §127).
 *
 * Where the note was written (core/geotag.ts) is the foot's third fragment, "12:40 · 26 Sep · Trafalgar Square": the
 * foot is "when", and "where" belongs beside it, with no mark of its own (a line on every tagged card is the kind
 * label §132 left out). Only the place's name, never the coordinates, so no page of cards lists a position for anyone
 * looking over a shoulder; and only from the note's own words, never from a tag still waiting to be written.
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
  /** The notebook it is a page of, said or not, whose workflow a ticket's status is placed in; absent, `place`'s. */
  notebook?: string;
  /** A journal's entries, newest first (book/journalMonths.ts `journalCards`), when the note is a journal. */
  entries?: JournalCard;
  /** A step smaller, with the pin and the archive said on the card itself. */
  dense?: boolean;
  /** The card swipes (notes/SwipeRow.tsx): its actions each way and what a swipe past a detent does (docs/DESIGN.md §151). */
  swipe?: { start: SwipeAction[]; end: SwipeAction[]; onAction: (id: string) => void };
}

export function NoteCard({ note, index, onOpen, gist, place, notebook, entries, dense = false, swipe }: NoteCardProps) {
  const title = noteTitle(note.body);
  const book = isBookBody(note.body);
  const journal = book && isJournalBody(note.body);
  // A journal's newest entries, by when each was written and with no number, since a journal has no page order: else a
  // notebook's first pages, numbered as the index has them.
  const listed = journal ? (entries?.newest ?? []).map((entry, line) => ({ title: entry.when, line, depth: 0 as const })) : book ? chaptersOf(note.body) : [];
  const count = journal ? (entries?.count ?? listed.length) : listed.length;
  const part = journal ? ['entry', 'entries'] : ['page', 'pages'];
  const where = geoTagOf(note.body)?.place ?? null;
  return (
    <li key={note.id} className={styles.item} data-dense={dense || undefined} style={{ '--i': Math.min(index, 8) } as CSSProperties}>
      <Swiped swipe={swipe}>
        <button type="button" className={styles.card} onClick={() => onOpen(note.id)}>
          <span className={styles.title} data-untitled={title ? undefined : ''}>
            {title ? shortenUrls(title) : journal ? 'Untitled journal' : book ? 'Untitled notebook' : 'Untitled'}
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
              <span className={styles.bookMeta}>{count === 0 ? `No ${part[1]} yet` : count === 1 ? `1 ${part[0]}` : `${count} ${part[1]}`}</span>
              {listed.length ? (
                <ol className={styles.bookPages} aria-hidden="true">
                  {listed.slice(0, 4).map((c, n) => (
                    <li key={`${c.line}-${c.title}`} data-depth={c.depth}>
                      {journal ? null : <span className={styles.bookPageNumber}>{n + 1}</span>}
                      {c.title}
                    </li>
                  ))}
                  {count > 4 ? <li className={styles.bookMore}>and {count - 4} more</li> : null}
                </ol>
              ) : null}
            </>
          ) : (
            <>
              {/* A page of a book says which (docs/BOOKS.md), and a ticket its key and status (docs/DESIGN.md §157). */}
              {place ? <BookPlaceMark place={place} /> : null}
              <TicketMark body={note.body} notebook={notebook ?? place?.book.body} />
              {/* What the note is about, when the phone has written it; the preview under it is the note itself. */}
              {gist ? <span className={styles.gist}>{gist}</span> : null}
              <NotePeek body={note.body} className={styles.peek} />
            </>
          )}
          <span className={styles.when}>
            {hasTape(note) ? (
              <>
                <span className={styles.tapeLength}>{counter(note.recordingMs ?? 0)}</span> ·{' '}
              </>
            ) : null}
            {when(note.updatedAt)}
            {where ? ` · ${where}` : null}
          </span>
        </button>
      </Swiped>
    </li>
  );
}

/** The card in a swipe's frame, cut to the card's corners, where it swipes; the card alone where it does not. */
function Swiped({ swipe, children }: { swipe: NoteCardProps['swipe']; children: ReactNode }) {
  if (!swipe) return children;
  return (
    <SwipeRow start={swipe.start} end={swipe.end} onAction={swipe.onAction} className={styles.swipe}>
      {children}
    </SwipeRow>
  );
}
