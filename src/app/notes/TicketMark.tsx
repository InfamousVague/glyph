import { statusesOf, ticketOf } from '../core/properties.ts';
import styles from './TicketMark.module.css';

/**
 * A ticket says so where it is listed (docs/DESIGN.md §157): its key and its status, small and quiet, the status in its
 * category's colour, on the home page's rows and lines, a note's card and a notebook's index (home/HomeScreen.tsx,
 * notes/NoteCard.tsx, book/BookView.tsx). One mark for all of them, as a page's notebook has one (BookPlaceMark.tsx),
 * so the places a ticket is listed cannot come to say it differently. Nothing for a note that is not a ticket.
 *
 * The status is placed in the workflow of the notebook it is in, where the list knows it (core/properties.ts
 * `statusesOf`); a status the default knows reads the same either way.
 */
export function TicketMark({ body, notebook, className }: { body: string; notebook?: string | null; className?: string }) {
  const ticket = ticketOf(body, notebook ? statusesOf(notebook) : undefined);
  if (!ticket || (!ticket.id && !ticket.status)) return null;
  return (
    <span className={className ? `${styles.mark} ${className}` : styles.mark} data-category={ticket.category} title={[ticket.id, ticket.status].filter(Boolean).join(' · ')}>
      {ticket.id ? <span className={styles.key}>{ticket.id}</span> : null}
      {ticket.status ? (
        <span className={styles.status}>
          <span className={styles.dot} aria-hidden="true" />
          {ticket.status}
        </span>
      ) : null}
    </span>
  );
}
