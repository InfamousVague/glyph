import type { Offer } from '../capture/take.ts';
import { listTitle } from '../capture/instructionMutation.ts';
import { withoutLead } from '../core/itemSyntax.ts';
import type { Note } from '../core/store.ts';
import styles from './ConfirmCard.module.css';

/**
 * The confirm card: exactly what a command is about to do, before it does
 * it, for a command read at Done from a recording (capture/CaptureScreen.tsx):
 * words for a note by name, or a new list by name. Matt (PR #1): "Shows the
 * exact proposed change before applying it."
 */
export function ConfirmCard({ offer, onConfirm, onCancel }: { offer: Offer<Note>; onConfirm: () => void; onCancel: () => void }) {
  let heading: string;
  let action: string;
  let lines: string[];
  let detail: string | null = null;
  if (offer.kind === 'place') {
    heading = `Add to ${offer.title}`;
    action = 'Add';
    lines = offer.added.map(withoutLead);
    detail = offer.into === 'list' ? 'In its list' : 'As a new paragraph';
  } else {
    heading = `Create ${listTitle(offer.title)}`;
    action = 'Create';
    lines = [...(offer.lines ?? [])];
    if (offer.lines?.length) detail = 'As a new list';
  }
  return (
    <section className={styles.confirm} aria-live="assertive" aria-label={heading}>
      <p className={styles.heading}>{heading}</p>
      {lines.map((line, i) => (
        <p key={i} className={styles.line}>
          {line}
        </p>
      ))}
      {detail ? <p className={styles.detail}>{detail}</p> : null}
      <div className={styles.actions}>
        <button type="button" className="app-word" onClick={onCancel}>
          Cancel
        </button>
        <button type="button" className="app-pill" onClick={onConfirm}>
          {action}
        </button>
      </div>
    </section>
  );
}
