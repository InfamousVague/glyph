import { useMemo } from 'react';
import { notePeek, PEEK_LINES, type PeekLine } from './peek.ts';
import styles from './NotePeek.module.css';

/**
 * A note drawn small: the first few lines of it, each keeping the shape it has in the note (notes/peek.ts).
 *
 * This is the card's description in the desktop sidebar. It is the note itself rather than anything written about it,
 * so it is right the moment the note changes and it needs no model, which is the whole point - the AI gist only ever
 * appears on a phone.
 *
 * Drawn, not read: a heading is a heavier line, a to-do is a box, a block of code is a tinted mono strip, a rule is a
 * rule. Every line is one line - clipped rather than wrapped - so six lines are always six lines and the cards stay
 * the same height whatever is in them. The exception is a note that opens with prose, where there are no shapes to
 * see: there the first paragraph is given three lines, because words are all it has.
 *
 * It says nothing to a screen reader: the row already has its name and its date, and reading six clipped lines after
 * every title would make the list slower to hear, not richer.
 */

export interface NotePeekProps {
  body: string;
  /** How many lines to draw. The sidebar's default is `PEEK_LINES`. */
  lines?: number;
  className?: string;
}

function Line({ line, lead }: { line: PeekLine; lead: boolean }) {
  switch (line.kind) {
    case 'heading':
      return (
        <span className={styles.heading} data-level={Math.min(line.level, 3)}>
          {line.text}
        </span>
      );
    case 'quote':
      return <span className={styles.quote}>{line.text}</span>;
    case 'bullet':
      return (
        <span className={styles.item}>
          <span className={styles.dot} aria-hidden="true" />
          <span className={styles.words}>{line.text}</span>
        </span>
      );
    case 'number':
      return (
        <span className={styles.item}>
          <span className={styles.bar} aria-hidden="true" />
          <span className={styles.words}>{line.text}</span>
        </span>
      );
    case 'task':
      return (
        <span className={styles.item}>
          <span className={styles.box} data-done={line.done ? '' : undefined} aria-hidden="true" />
          <span className={styles.words} data-done={line.done ? '' : undefined}>
            {line.text}
          </span>
        </span>
      );
    case 'code':
      return <span className={styles.code}>{line.text}</span>;
    case 'table':
      return (
        <span className={styles.table}>
          {line.cells.map((cell, i) => (
            <span key={i} className={styles.cell}>
              {cell}
            </span>
          ))}
        </span>
      );
    case 'image':
      return (
        <span className={styles.item}>
          <span className={styles.frame} aria-hidden="true" />
          <span className={styles.words}>{line.text || 'Picture'}</span>
        </span>
      );
    case 'rule':
      return <span className={styles.rule} aria-hidden="true" />;
    default:
      return (
        <span className={styles.words} data-lead={lead ? '' : undefined}>
          {line.text}
        </span>
      );
  }
}

export function NotePeek({ body, lines = PEEK_LINES, className }: NotePeekProps) {
  const peek = useMemo(() => notePeek(body, lines), [body, lines]);
  if (!peek.length) return null;
  // Prose with no shapes in it gets the room to be read; anything else is a stack of single lines.
  const lead = peek[0]?.kind === 'text';
  /*
   * The count is a budget of DRAWN lines, not of the note's: an opening paragraph takes three of them, so it pays for
   * three. Without that a card of prose stood half again as tall as a card of to-dos and the column looked ragged.
   */
  const drawn = lead ? peek.slice(0, Math.max(1, lines - 2)) : peek;
  return (
    <span className={className ? `${styles.peek} ${className}` : styles.peek} aria-hidden="true">
      {drawn.map((line, i) => (
        <Line key={i} line={line} lead={lead && i === 0} />
      ))}
    </span>
  );
}
