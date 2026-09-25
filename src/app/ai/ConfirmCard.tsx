import type { ReactNode } from 'react';
import type { Offer } from '../capture/take.ts';
import { listTitle } from '../capture/instructionMutation.ts';
import type { Note } from '../core/store.ts';
import { capitalise } from '../core/text.ts';
import styles from './ConfirmCard.module.css';

/**
 * The confirm card: exactly what a command is about to do, before it does
 * it. One card for a command however it arrived - spoken to the recorder
 * (capture/CaptureScreen.tsx) or typed into the bar (editor/NoteScreen.tsx)
 * - so the preview reads the same wherever the command came from. Matt
 * (PR #1): "Shows the exact proposed change before applying it."
 */
export function ConfirmCard({
  offer,
  onConfirm,
  onCancel,
  hint,
  table,
}: {
  offer: Offer<Note>;
  onConfirm: () => void;
  onCancel: () => void;
  /** The line under the words: the recorder says a "yes" or a "no" will do. */
  hint?: string;
  /** A table's own preview, drawn by whoever has the rows. */
  table?: ReactNode;
}) {
  const show = (line: string) => line.replace(/^\s*(?:- \[[ xX]\] |[-*+] |\d+[.)] )/, '');
  let heading: string;
  let action: string;
  let lines: string[] = [];
  let detail: string | null = null;
  switch (offer.kind) {
    case 'place':
      heading = `Add to ${offer.title}`;
      action = 'Add';
      lines = offer.added.map(show);
      detail = offer.into === 'list' ? 'In its list' : 'As a new paragraph';
      if (offer.placement.target) detail += `, then to ${capitalise(offer.placement.target)}`;
      break;
    case 'change':
      heading = `${offer.heading} in ${offer.title}`;
      action = offer.action;
      lines = offer.lines;
      break;
    case 'board':
      heading = 'Make this note a board';
      action = 'Make it';
      detail = 'Its list items become cards';
      break;
    case 'book':
      heading = `Make a book called ${offer.title}`;
      action = 'Make it';
      lines = offer.pages;
      detail = offer.pages.length ? 'Its pages, in this order' : 'Empty, with its index ready';
      break;
    case 'move':
      heading = `Move this recording to ${offer.title}`;
      action = 'Move';
      break;
    case 'new':
      heading = offer.title ? `Create ${listTitle(offer.title)}` : 'Start a new note from here';
      action = offer.title ? 'Create' : 'Start';
      lines = [...(offer.lines ?? [])];
      if (offer.lines?.length) detail = 'As a new list';
      break;
    case 'table':
      heading = `Add this table to ${offer.title}`;
      action = 'Add';
      detail = `${offer.rows.length} ${offer.rows.length === 1 ? 'row' : 'rows'}, at the end of the note`;
      break;
    default:
      heading = offer.title;
      action = offer.action;
  }
  return (
    <section className={styles.confirm} aria-live="assertive" aria-label={heading}>
      <p className={styles.heading}>{heading}</p>
      {lines.map((line, i) => (
        <p key={i} className={styles.line}>
          {line}
        </p>
      ))}
      {offer.kind === 'table' ? table : null}
      {detail ? <p className={styles.detail}>{detail}</p> : null}
      <div className={styles.actions}>
        <button type="button" className="app-word" onClick={onCancel}>
          Cancel
        </button>
        <button type="button" className="app-pill" onClick={onConfirm}>
          {action}
        </button>
      </div>
      {hint ? <p className={styles.hint}>{hint}</p> : null}
    </section>
  );
}
