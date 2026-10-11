import { statusesOf, ticketOf } from '../core/properties.ts';
import { StatusIcon } from '../editor/FieldPicker.tsx';
import { statusLook } from '../editor/fieldPicks.ts';
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
export function TicketMark({ body, notebook, className, keyOnly = false }: { body: string; notebook?: string | null; className?: string; keyOnly?: boolean }) {
  const ticket = ticketOf(body, notebook ? statusesOf(notebook) : undefined);
  if (!ticket || (!ticket.id && !ticket.status)) return null;
  if (keyOnly && !ticket.id) return null;
  return (
    <span className={className ? `${styles.mark} ${className}` : styles.mark} data-category={ticket.category} title={[ticket.id, ticket.status].filter(Boolean).join(' · ')}>
      {ticket.id ? <span className={styles.key}>{ticket.id}</span> : null}
      {ticket.status && !keyOnly ? (
        <span className={styles.status}>
          <span className={styles.dot} aria-hidden="true" />
          {ticket.status}
        </span>
      ) : null}
    </span>
  );
}

/**
 * A ticket's status as a button, where its list can change it (book/BookView.tsx; docs/DESIGN.md §169): a pill in its
 * category's colour with its mark, as a query's cell draws it, that opens the sheet of its workflow. "Set status" on a
 * ticket that has none. Nothing for a note that is not a ticket.
 */
export function TicketStatusButton({ body, notebook, onPress }: { body: string; notebook?: string | null; onPress: () => void }) {
  const workflow = notebook ? statusesOf(notebook) : undefined;
  const ticket = ticketOf(body, workflow);
  if (!ticket) return null;
  const look = ticket.status ? statusLook(ticket.status, workflow) : 'todo';
  return (
    <button
      type="button"
      className={styles.statusButton}
      data-category={ticket.status ? ticket.category : undefined}
      data-look={ticket.status ? look : undefined}
      data-empty={ticket.status ? undefined : ''}
      aria-haspopup="dialog"
      aria-label={ticket.status ? `Status: ${ticket.status}. Change it` : 'Set a status'}
      title="Change the status"
      onPointerDown={(event) => event.stopPropagation()}
      onClick={onPress}
    >
      <StatusIcon look={look} size="1em" />
      <span className={styles.statusWords}>{ticket.status ?? 'Status'}</span>
    </button>
  );
}
